//
//  AquinasApplicationRuntime.swift
//  Aquinas-iOS
//

import Foundation

/// Constructs the live model and queue together so every queued operation leases the same engine
/// that performs generation. The object is process-scoped and intentionally survives navigation.
@MainActor
final class AquinasApplicationRuntime {
    static let shared = AquinasApplicationRuntime()

    let model: any AquinasModel
    let modelTasks: ModelTaskQueue
    let isOnDevice: Bool

    private init(modelStore: LiteRTModelStore = LiteRTModelStore()) {
#if DEBUG
        let forcesMacBackend = ProcessInfo.processInfo.arguments.contains(
            "--force-backend-model"
        )
#else
        let forcesMacBackend = false
#endif
        if !forcesMacBackend, modelStore.hasInstalledModel() {
            let runtime = LiteRTAquinasRuntime(modelStore: modelStore)
            let lifecycle = ModelRuntimeLifecycleManager(
                driver: runtime,
                configuration: .adaptiveOnDevice
            )
            model = LiteRTAquinasModel(runtime: runtime)
            modelTasks = ModelTaskQueue(runtimeLifecycle: lifecycle)
            isOnDevice = true
        } else {
            model = BackendAquinasModel()
            modelTasks = ModelTaskQueue()
            isOnDevice = false
        }
    }
}
