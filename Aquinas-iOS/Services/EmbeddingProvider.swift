//
//  EmbeddingProvider.swift
//  Aquinas-iOS
//

import Foundation
import NaturalLanguage

/// The source of an Insight's embedding vector — the numeric representation its relatedness to
/// everything else in the tree is computed from (see `cosineSimilarity`/`semanticDistance` in
/// InsightTreeViewModel.swift). Swappable so the vector source (on-device today, model-supplied
/// later) can change without touching any of the relatedness/layout math that consumes vectors.
///
/// `version` MUST change whenever the underlying vector space changes (different model, different
/// dimensionality) — cached vectors are tagged with the version that produced them
/// (`InsightModel.embeddingVersion`) so a source swap triggers a recompute instead of comparing
/// incompatible spaces. `cosineSimilarity` returns 0 for mismatched dimensions with no error,
/// which would otherwise silently look like "everything stopped being related."
protocol EmbeddingProvider {
    var version: String { get }
    func embed(_ text: String) async -> [Double]?
}

/// Today's on-device implementation — Apple's `NLEmbedding`, wrapped to the async shape the rest
/// of the pipeline expects so a network-backed provider drops in later with no further refactor.
/// Wraps the same `computeEmbedding` free function `HomeDashboardView`'s bridge-suggestion feature
/// also calls directly (that call site stays synchronous — it's a separate, smaller feature
/// outside the Insight Tree's versioned embedding pipeline).
struct NLEmbeddingProvider: EmbeddingProvider {
    static let version = "nl.en.v1"
    var version: String { Self.version }

    func embed(_ text: String) async -> [Double]? {
        computeEmbedding(for: text)
    }
}
