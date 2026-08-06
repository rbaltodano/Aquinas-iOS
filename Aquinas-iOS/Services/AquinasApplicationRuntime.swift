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
    /// The relatedness signal for on-device Insight clustering (the global Insight Library, and
    /// any local fallback before a conversation's persisted tree loads). MiniLM when the bundled
    /// on-device model is available; `NLEmbedding` only as a last resort, since its similarity
    /// scores are too noisy on short Insight text to cluster on — see
    /// `MiniLMEmbeddingProvider`'s doc comment.
    let embeddingProvider: any EmbeddingProvider

    private init(modelStore: LiteRTModelStore = LiteRTModelStore()) {
        do {
            embeddingProvider = try MiniLMEmbeddingProvider()
        } catch {
            // Missing/corrupt on-device model assets fall back to NLEmbedding rather than
            // losing Insight clustering entirely — degraded (noisy) rather than broken.
            embeddingProvider = NLEmbeddingProvider()
        }
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
            let groundingProvider: any AquinasGroundingProviding
            do {
                groundingProvider = try MiniLMGroundingProvider()
            } catch {
                // Missing/corrupt corpus assets fall back to the small hardcoded
                // reference set rather than losing grounding entirely.
                groundingProvider = LocalAquinasGroundingProvider()
            }
            model = LiteRTAquinasModel(runtime: runtime, groundingProvider: groundingProvider)
            modelTasks = ModelTaskQueue(runtimeLifecycle: lifecycle)
            isOnDevice = true
        } else {
            model = BackendAquinasModel()
            modelTasks = ModelTaskQueue()
            isOnDevice = false
        }
    }
}
