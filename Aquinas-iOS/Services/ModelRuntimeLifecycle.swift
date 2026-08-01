//
//  ModelRuntimeLifecycle.swift
//  Aquinas-iOS
//

import Foundation
import os
import Darwin

nonisolated enum ModelRuntimeState: String, Sendable, Equatable {
    case unloaded
    case loading
    case ready
    case generating
    case unloading
}

nonisolated enum ModelRuntimeThermalPressure: String, Sendable, Equatable {
    case nominal
    case fair
    case serious
    case critical
}

nonisolated enum ModelRuntimeUnloadReason: String, Sendable {
    case idle
    case background
    case memoryPressure
    case criticalThermalPressure
}

nonisolated enum ModelRuntimeRetentionPolicy: Sendable, Equatable {
    case alwaysResident
    case strictSixtySeconds
    case adaptive
}

nonisolated struct ModelRuntimeLifecycleConfiguration: Sendable, Equatable {
    static let normalIdleTimeout: TimeInterval = 5 * 60
    static let seriousThermalIdleTimeout: TimeInterval = 60

    let retentionPolicy: ModelRuntimeRetentionPolicy
    let normalIdleTimeout: TimeInterval
    let seriousThermalIdleTimeout: TimeInterval

    static let backendResident = ModelRuntimeLifecycleConfiguration(
        retentionPolicy: .alwaysResident,
        normalIdleTimeout: normalIdleTimeout,
        seriousThermalIdleTimeout: seriousThermalIdleTimeout
    )

    static let adaptiveOnDevice = ModelRuntimeLifecycleConfiguration(
        retentionPolicy: .adaptive,
        normalIdleTimeout: normalIdleTimeout,
        seriousThermalIdleTimeout: seriousThermalIdleTimeout
    )

    static let strictSixtySecondsOnDevice = ModelRuntimeLifecycleConfiguration(
        retentionPolicy: .strictSixtySeconds,
        normalIdleTimeout: seriousThermalIdleTimeout,
        seriousThermalIdleTimeout: seriousThermalIdleTimeout
    )
}

/// The eventual on-device model engine implements this seam. `unloadModelWeights()` should
/// release model weights, generation/KV caches, and compute resources while retaining cheap
/// tokenizer/configuration state for the next lazy load.
nonisolated protocol ModelRuntimeDriver: Sendable {
    var supportsUnloading: Bool { get }
    func loadModelWeights() async throws
    func unloadModelWeights() async
}

/// The development backend owns its process-scoped MLX model, so the iOS client must never try
/// to unload it. This keeps today's behavior unchanged while exercising the same lease boundary.
nonisolated struct BackendResidentModelRuntimeDriver: ModelRuntimeDriver {
    let supportsUnloading = false

    func loadModelWeights() async throws {}
    func unloadModelWeights() async {}
}

nonisolated struct ModelRuntimeLease: Sendable, Equatable {
    fileprivate let id: UUID
}

/// Serializes load, generation leases, idle retention, and unload. All model tasks acquire a
/// lease through `ModelTaskQueue`; a model can only unload after the last lease is released.
actor ModelRuntimeLifecycleManager {
    private let driver: any ModelRuntimeDriver
    private let configuration: ModelRuntimeLifecycleConfiguration
    private let signpostLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.aquinas",
        category: "ModelRuntime"
    )

    private var state: ModelRuntimeState
    private var thermalPressure: ModelRuntimeThermalPressure = .nominal
    private var activeLeaseIDs: Set<UUID> = []
    private var idleSince: ContinuousClock.Instant?
    private var lastLeaseEndedAt: ContinuousClock.Instant?
    private var idleUnloadTask: Task<Void, Never>?
    private var loadTask: Task<Void, Error>?
    private var unloadTask: Task<Void, Never>?
    private var transitionWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        driver: any ModelRuntimeDriver = BackendResidentModelRuntimeDriver(),
        configuration: ModelRuntimeLifecycleConfiguration = .backendResident
    ) {
        self.driver = driver
        self.configuration = configuration
        state = driver.supportsUnloading ? .unloaded : .ready
    }

    func currentState() -> ModelRuntimeState {
        state
    }

    func requiresLoadingForNextLease() -> Bool {
        guard driver.supportsUnloading else { return false }
        return state == .unloaded || state == .loading || state == .unloading
    }

    func acquireLease() async -> ModelRuntimeLease? {
        cancelIdleUnload()

        if state == .unloading {
            await finishCurrentUnload()
        }
        guard await ensureLoaded(), !Task.isCancelled else {
            return nil
        }

        let lease = ModelRuntimeLease(id: UUID())
        activeLeaseIDs.insert(lease.id)
        idleSince = nil
        transition(to: .generating)

        let now = ContinuousClock.now
        if let lastLeaseEndedAt {
            os_signpost(
                .event,
                log: signpostLog,
                name: "Model Task Started",
                "seconds_since_previous_task=%{public}.3f thermal=%{public}s resident_bytes=%{public}llu",
                Self.seconds(lastLeaseEndedAt.duration(to: now)),
                thermalPressure.rawValue,
                Self.residentMemoryBytes()
            )
        }
        return lease
    }

    func releaseLease(_ lease: ModelRuntimeLease) {
        guard activeLeaseIDs.remove(lease.id) != nil else { return }
        guard activeLeaseIDs.isEmpty else {
            notifyTransitionWaiters()
            return
        }

        let now = ContinuousClock.now
        lastLeaseEndedAt = now
        idleSince = now
        transition(to: .ready)
        scheduleIdleUnload()
    }

    func updateThermalPressure(_ pressure: ModelRuntimeThermalPressure) {
        guard thermalPressure != pressure else { return }
        thermalPressure = pressure
        os_signpost(
            .event,
            log: signpostLog,
            name: "Thermal State Changed",
            "thermal=%{public}s resident_bytes=%{public}llu",
            pressure.rawValue,
            Self.residentMemoryBytes()
        )

        guard activeLeaseIDs.isEmpty else { return }
        scheduleIdleUnload()
    }

    func unloadAsSoonAsIdle(reason: ModelRuntimeUnloadReason) async {
        guard canUnload else { return }
        cancelIdleUnload()

        while !activeLeaseIDs.isEmpty {
            await waitForTransition()
        }
        guard !Task.isCancelled else { return }
        await unload(reason: reason)
    }

    private var canUnload: Bool {
        driver.supportsUnloading
            && configuration.retentionPolicy != .alwaysResident
    }

    private func ensureLoaded() async -> Bool {
        guard driver.supportsUnloading else {
            transition(to: activeLeaseIDs.isEmpty ? .ready : .generating)
            return true
        }
        if state == .ready || state == .generating {
            return true
        }
        if let loadTask {
            do {
                try await loadTask.value
                if state == .loading {
                    self.loadTask = nil
                    transition(to: .ready)
                }
                return state == .ready || state == .generating
            } catch {
                if state == .loading {
                    self.loadTask = nil
                    transition(to: .unloaded)
                }
                return false
            }
        }

        transition(to: .loading)
        let driver = self.driver
        let signpostLog = self.signpostLog
        let task = Task {
            os_signpost(
                .begin,
                log: signpostLog,
                name: "Model Load",
                "resident_bytes_before=%{public}llu",
                Self.residentMemoryBytes()
            )
            do {
                try await driver.loadModelWeights()
                os_signpost(
                    .end,
                    log: signpostLog,
                    name: "Model Load",
                    "result=success resident_bytes_after=%{public}llu",
                    Self.residentMemoryBytes()
                )
            } catch {
                os_signpost(
                    .end,
                    log: signpostLog,
                    name: "Model Load",
                    "result=failure resident_bytes_after=%{public}llu",
                    Self.residentMemoryBytes()
                )
                throw error
            }
        }
        loadTask = task

        do {
            try await task.value
            loadTask = nil
            transition(to: .ready)
            return true
        } catch {
            loadTask = nil
            transition(to: .unloaded)
            return false
        }
    }

    private func scheduleIdleUnload() {
        cancelIdleUnload()
        guard canUnload,
              activeLeaseIDs.isEmpty,
              state == .ready,
              let idleSince,
              let timeout = idleTimeout else {
            return
        }

        let elapsed = Self.seconds(idleSince.duration(to: .now))
        let remaining = max(0, timeout - elapsed)
        let marker = idleSince
        idleUnloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return
            }
            await self?.idleTimerFired(marker: marker)
        }
    }

    private var idleTimeout: TimeInterval? {
        switch configuration.retentionPolicy {
        case .alwaysResident:
            return nil
        case .strictSixtySeconds:
            return configuration.seriousThermalIdleTimeout
        case .adaptive:
            return thermalPressure == .serious
                ? configuration.seriousThermalIdleTimeout
                : configuration.normalIdleTimeout
        }
    }

    private func idleTimerFired(marker: ContinuousClock.Instant) async {
        idleUnloadTask = nil
        guard activeLeaseIDs.isEmpty,
              idleSince == marker,
              state == .ready else {
            return
        }
        await unload(reason: .idle)
    }

    private func unload(reason: ModelRuntimeUnloadReason) async {
        guard canUnload, activeLeaseIDs.isEmpty else { return }
        if state == .unloaded { return }
        if state == .loading, let loadTask {
            _ = try? await loadTask.value
            self.loadTask = nil
        }
        if let unloadTask {
            await unloadTask.value
            if state == .unloading {
                self.unloadTask = nil
                transition(to: .unloaded)
            }
            return
        }

        transition(to: .unloading)
        idleSince = nil
        let driver = self.driver
        let signpostLog = self.signpostLog
        let task = Task {
            os_signpost(
                .begin,
                log: signpostLog,
                name: "Model Unload",
                "reason=%{public}s resident_bytes_before=%{public}llu",
                reason.rawValue,
                Self.residentMemoryBytes()
            )
            await driver.unloadModelWeights()
            os_signpost(
                .end,
                log: signpostLog,
                name: "Model Unload",
                "reason=%{public}s resident_bytes_after=%{public}llu",
                reason.rawValue,
                Self.residentMemoryBytes()
            )
        }
        unloadTask = task
        await task.value
        unloadTask = nil
        transition(to: .unloaded)
    }

    private func finishCurrentUnload() async {
        guard let unloadTask else { return }
        await unloadTask.value
        if state == .unloading {
            self.unloadTask = nil
            transition(to: .unloaded)
        }
    }

    private func cancelIdleUnload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
    }

    private func transition(to newState: ModelRuntimeState) {
        guard state != newState else { return }
        state = newState
        os_signpost(
            .event,
            log: signpostLog,
            name: "Model Runtime State",
            "state=%{public}s thermal=%{public}s active_leases=%{public}d resident_bytes=%{public}llu",
            newState.rawValue,
            thermalPressure.rawValue,
            activeLeaseIDs.count,
            Self.residentMemoryBytes()
        )
        notifyTransitionWaiters()
    }

    private func waitForTransition() async {
        await withCheckedContinuation { continuation in
            transitionWaiters.append(continuation)
        }
    }

    private func notifyTransitionWaiters() {
        let waiters = transitionWaiters
        transitionWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    nonisolated private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    nonisolated private static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size
                / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
}
