import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Adaptive model runtime lifecycle")
struct ModelRuntimeLifecycleTests {
    @Test("Short foreground pauses keep the model warm")
    func shortPauseKeepsModelWarm() async throws {
        let driver = TestModelRuntimeDriver()
        // A generous idle timeout, so a slow CI machine can't stretch the short pause past it.
        let manager = makeManager(
            driver: driver,
            normalTimeout: 5,
            seriousTimeout: 1
        )

        let lease = try #require(await manager.acquireLease())
        await manager.releaseLease(lease)
        try await Task.sleep(for: .milliseconds(40))

        #expect(await manager.currentState() == .ready)
        #expect(await driver.unloadCount == 0)
    }

    @Test("Normal idle timeout unloads the model")
    func normalIdleTimeoutUnloads() async throws {
        let driver = TestModelRuntimeDriver()
        let manager = makeManager(
            driver: driver,
            normalTimeout: 0.03,
            seriousTimeout: 0.01
        )

        let lease = try #require(await manager.acquireLease())
        await manager.releaseLease(lease)
        try await waitUntil { await manager.currentState() == .unloaded }

        #expect(await driver.unloadCount == 1)
    }

    @Test("Serious thermal pressure shortens an existing idle timer")
    func seriousThermalPressureShortensTimeout() async throws {
        let driver = TestModelRuntimeDriver()
        let manager = makeManager(
            driver: driver,
            normalTimeout: 1,
            seriousTimeout: 0.03
        )

        let lease = try #require(await manager.acquireLease())
        await manager.releaseLease(lease)
        await manager.updateThermalPressure(.serious)
        try await waitUntil { await manager.currentState() == .unloaded }

        #expect(await driver.unloadCount == 1)
    }

    @Test("An active generation lease blocks immediate unloading")
    func activeLeaseBlocksUnload() async throws {
        let driver = TestModelRuntimeDriver()
        let manager = makeManager(driver: driver)
        let lease = try #require(await manager.acquireLease())

        let unloadRequest = Task {
            await manager.unloadAsSoonAsIdle(reason: .memoryPressure)
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(await manager.currentState() == .generating)
        #expect(await driver.unloadCount == 0)

        await manager.releaseLease(lease)
        await unloadRequest.value
        #expect(await manager.currentState() == .unloaded)
        #expect(await driver.unloadCount == 1)
    }

    @Test("The first task after unloading performs one clean reload")
    func coldTaskReloadsOnce() async throws {
        let driver = TestModelRuntimeDriver()
        let manager = makeManager(driver: driver)

        let firstLease = try #require(await manager.acquireLease())
        await manager.releaseLease(firstLease)
        await manager.unloadAsSoonAsIdle(reason: .background)
        let secondLease = try #require(await manager.acquireLease())

        #expect(await driver.loadCount == 2)
        #expect(await manager.currentState() == .generating)
        await manager.releaseLease(secondLease)
    }

    @Test("The development backend remains resident")
    func backendRuntimeIgnoresUnloadRequests() async {
        let manager = ModelRuntimeLifecycleManager()

        await manager.unloadAsSoonAsIdle(reason: .memoryPressure)

        #expect(await manager.currentState() == .ready)
        #expect(await manager.requiresLoadingForNextLease() == false)
    }

    @MainActor
    @Test("Backgrounding preserves and retries background queue work")
    func backgroundingPreservesBackgroundWork() async throws {
        let driver = TestModelRuntimeDriver()
        let manager = makeManager(driver: driver)
        let queue = ModelTaskQueue(runtimeLifecycle: manager)
        let attempts = TestAttemptCounter()

        queue.enqueue(kind: .refreshQuestionOfTheDay, priority: .background) {
            await attempts.started()
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await attempts.completed()
        }
        try await waitUntil { await attempts.startCount == 1 }

        queue.setApplicationActive(false)
        try await waitUntil { await manager.currentState() == .unloaded }
        #expect(queue.upcomingTasks.count == 1)

        queue.setApplicationActive(true)
        try await waitUntil { await attempts.completionCount == 1 }
        #expect(await attempts.startCount == 2)
    }

    @MainActor
    @Test("Latest completion retains its origin after completed rows clear")
    func latestCompletionRetainsOrigin() async throws {
        let driver = TestModelRuntimeDriver()
        let queue = ModelTaskQueue(runtimeLifecycle: makeManager(driver: driver))

        let taskID = queue.enqueue(
            kind: .refreshQuestionOfTheDay,
            originPage: .studyTopics
        ) { }

        try await waitUntil { await queue.latestCompletedTask?.id == taskID }
        #expect(queue.latestCompletedTask?.originPage == .studyTopics)

        // Completed rows clear 0.7 s after finishing; wait for that rather than a fixed sleep.
        try await waitUntil { await queue.completedTasks.isEmpty }
        #expect(queue.latestCompletedTask?.id == taskID)
    }

    private func makeManager(
        driver: TestModelRuntimeDriver,
        normalTimeout: TimeInterval = 10,
        seriousTimeout: TimeInterval = 1
    ) -> ModelRuntimeLifecycleManager {
        ModelRuntimeLifecycleManager(
            driver: driver,
            configuration: ModelRuntimeLifecycleConfiguration(
                retentionPolicy: .adaptive,
                normalIdleTimeout: normalTimeout,
                seriousThermalIdleTimeout: seriousTimeout
            )
        )
    }

    private func waitUntil(
        // Generous for slow CI machines; passing checks return as soon as the condition holds.
        timeout: Duration = .seconds(10),
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Condition did not become true before the timeout.")
    }
}

private actor TestModelRuntimeDriver: ModelRuntimeDriver {
    nonisolated let supportsUnloading = true
    private(set) var loadCount = 0
    private(set) var unloadCount = 0

    func loadModelWeights() async throws {
        loadCount += 1
    }

    func unloadModelWeights() async {
        unloadCount += 1
    }
}

private actor TestAttemptCounter {
    private(set) var startCount = 0
    private(set) var completionCount = 0

    func started() {
        startCount += 1
    }

    func completed() {
        completionCount += 1
    }
}
