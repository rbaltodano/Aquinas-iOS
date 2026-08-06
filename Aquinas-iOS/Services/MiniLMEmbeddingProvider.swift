//
//  MiniLMEmbeddingProvider.swift
//  Aquinas-iOS
//

import Foundation

/// The real relatedness signal for clustering Insights — on-device MiniLM
/// (`sentence-transformers/all-MiniLM-L6-v2` via Core ML), replacing `NLEmbeddingProvider`'s Apple
/// `NLEmbedding` space. `NLEmbedding`'s cosine similarity on short Insight text is dominated by
/// noise: empirically, unrelated pairs ("Quantum Entanglement" / "Photosynthesis") routinely score
/// *higher* than related ones, so any fixed membership threshold either merges everything into one
/// cluster or splits everything apart — there's no working cutoff in that space. MiniLM is the
/// same embedding space `MiniLMGroundingProvider` searches the grounding corpus with, and the same
/// one the backend's persisted Insight Tree clusters with server-side, so on-device clustering
/// (the global Insight Library, and the local fallback before a conversation's persisted tree
/// loads) finally compares apples to apples instead of noise to noise.
struct MiniLMEmbeddingProvider: EmbeddingProvider {
    static let version = "minilm-l6-v2.v1"
    var version: String { Self.version }

    private let embedder: MiniLMEmbedder

    init(embedder: MiniLMEmbedder) {
        self.embedder = embedder
    }

    /// Loads its own `MiniLMEmbedder` from the bundled `LocalGrounding/` assets — the same model
    /// file `MiniLMGroundingProvider` loads for grounding retrieval, just a second Core ML
    /// instance. Small, one-time, once-per-launch cost; not worth threading a shared instance
    /// across two otherwise-unrelated provider types for this.
    init(bundle: Bundle = .main) throws {
        guard let modelURL = bundle.url(
            forResource: "MiniLM",
            withExtension: "mlmodelc",
            subdirectory: "LocalGrounding"
        ) ?? bundle.url(forResource: "MiniLM", withExtension: "mlmodelc") else {
            throw MiniLMEmbeddingProviderError.resourceMissing("MiniLM.mlmodelc")
        }
        guard let vocabURL = bundle.url(
            forResource: "vocab",
            withExtension: "txt",
            subdirectory: "LocalGrounding"
        ) ?? bundle.url(forResource: "vocab", withExtension: "txt") else {
            throw MiniLMEmbeddingProviderError.resourceMissing("vocab.txt")
        }
        self.embedder = try MiniLMEmbedder(modelURL: modelURL, vocabURL: vocabURL)
    }

    func embed(_ text: String) async -> [Double]? {
        try? embedder.embed(text).map(Double.init)
    }
}

enum MiniLMEmbeddingProviderError: LocalizedError {
    case resourceMissing(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            "The on-device embedding model is missing \(name)."
        }
    }
}
