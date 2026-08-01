//
//  InsightTreeModels.swift
//  Aquinas-iOS
//

import CoreGraphics
import Foundation

// MARK: - Insight Tree Models

struct InsightModel: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    let definition: String
    let conversationID: UUID
    let savedAt: Date
    var embedding: [Double]?
    /// Which `EmbeddingProvider` produced `embedding` (e.g. `NLEmbeddingProvider.version`). A
    /// mismatch against the currently-configured provider means the cached vector is from a
    /// different, incompatible vector space and must be recomputed rather than compared —
    /// see `EmbeddingProvider`'s doc comment.
    var embeddingVersion: String?
    /// Backend-computed relationship to the owning Node. Present for persisted conversation
    /// trees; nil for the legacy in-memory/global-library canvas.
    var relatednessToNode: Double?
    var distanceToNode: Double?

    init(
        id: UUID = UUID(),
        title: String,
        definition: String,
        conversationID: UUID = UUID(),
        savedAt: Date = Date(),
        embedding: [Double]? = nil,
        embeddingVersion: String? = nil,
        relatednessToNode: Double? = nil,
        distanceToNode: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.definition = definition
        self.conversationID = conversationID
        self.savedAt = savedAt
        self.embedding = embedding
        self.embeddingVersion = embeddingVersion
        self.relatednessToNode = relatednessToNode
        self.distanceToNode = distanceToNode
    }

    init(concept: ConceptDefinition, conversationID: UUID = UUID()) {
        id = concept.id
        title = concept.word.capitalized
        definition = concept.semanticDefinition
        self.conversationID = conversationID
        savedAt = Date()
        embedding = nil
        embeddingVersion = nil
        relatednessToNode = nil
        distanceToNode = nil
    }
}

struct NodeModel: Identifiable, Equatable {
    let id: UUID
    private var titleCasedConceptLabel: String
    var conceptLabel: String {
        get { titleCasedConceptLabel }
        set { titleCasedConceptLabel = newValue.capitalized }
    }
    /// The concept's own definition, shown in its docked card just like an insight's. Set when an
    /// insight is promoted to a node (carries the source insight's definition); empty for auto
    /// clustered nodes, whose card falls back to a summary of their member insights.
    var definition: String = ""
    var insights: [InsightModel]
    var embedding: [Double]
    var position: CGPoint
    var isSuggested: Bool
    var suggestedInsights: [InsightModel]?

    init(
        id: UUID,
        conceptLabel: String,
        definition: String = "",
        insights: [InsightModel],
        embedding: [Double],
        position: CGPoint,
        isSuggested: Bool,
        suggestedInsights: [InsightModel]? = nil
    ) {
        self.id = id
        self.titleCasedConceptLabel = conceptLabel.capitalized
        self.definition = definition
        self.insights = insights
        self.embedding = embedding
        self.position = position
        self.isSuggested = isSuggested
        self.suggestedInsights = suggestedInsights
    }
}

struct EdgeModel: Identifiable, Equatable {
    let id: UUID
    let fromNodeID: UUID
    let toNodeID: UUID
    var distance: Double
    var isSuggested: Bool
    var showSuggestButton: Bool
}

/// A source a placed midpoint was spawned from — either a specific insight chip (`isNode == false`,
/// connect to the chip) or a whole node concept (`isNode == true`, connect to the node center).
struct MidpointSource: Equatable {
    let insightID: UUID
    let isNode: Bool
}

/// A Node already represents an Insight whose normalized title exactly matches the Node label.
/// Keep that Insight in the model for its definition, persistence, and docked-card access, but do
/// not draw a second same-named chip beside the Node. Placed Midpoints are exempt because their
/// Node circle is intentionally hidden and the chip is their only visible representation.
func canvasInsightMembers(
    nodeLabel: String,
    insights: [InsightModel],
    preservesMatchingTitle: Bool
) -> [InsightModel] {
    guard !preservesMatchingTitle else { return insights }
    let nodeKey = canonicalInsightTreeTitle(nodeLabel)
    guard !nodeKey.isEmpty else { return insights }
    return insights.filter {
        canonicalInsightTreeTitle($0.title) != nodeKey
    }
}

private func canonicalInsightTreeTitle(_ title: String) -> String {
    var words = title
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        .split(whereSeparator: { $0.isWhitespace })
        .map(String.init)
    if let first = words.first, ["a", "an", "the"].contains(first) {
        words.removeFirst()
    }
    return words.joined(separator: " ")
}

// MARK: - Layout Geometry

/// Radius of the ring an insight chip orbits around its node. Grows with the chip count and
/// the longest title so adjacent chips don't overlap. Shared by the layout engine
/// (`InsightTreeViewModel.nodeFootprintRadius`) and the renderer
/// (`InsightTreeCanvasView.insightWorldPosition`) — both MUST use this so they never desync.
func insightOrbitRadius(longestTitleChars: Int, count: Int, isSuggested: Bool) -> CGFloat {
    let base: CGFloat = isSuggested ? 118 : 190
    let n = max(count, 1)
    guard n > 1 else { return base }
    // Estimate chip width: fixed chrome (icon 14 + spacing 10 + h-padding 40 ≈ 64) + glyphs.
    let chipWidth = 64 + CGFloat(min(longestTitleChars, 24)) * 8.5
    // Adjacent chips sit on a chord = 2·r·sin(π/n); require chord ≥ chipWidth + gap.
    let required = (chipWidth + 16) / (2 * sin(.pi / CGFloat(n)))
    return max(base, required)
}
