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

    init(
        id: UUID = UUID(),
        title: String,
        definition: String,
        conversationID: UUID = UUID(),
        savedAt: Date = Date(),
        embedding: [Double]? = nil
    ) {
        self.id = id
        self.title = title
        self.definition = definition
        self.conversationID = conversationID
        self.savedAt = savedAt
        self.embedding = embedding
    }

    init(concept: ConceptDefinition, conversationID: UUID = UUID()) {
        id = concept.id
        title = concept.word.capitalized
        definition = concept.meaning
        self.conversationID = conversationID
        savedAt = Date()
        embedding = nil
    }
}

struct NodeModel: Identifiable, Equatable {
    let id: UUID
    var conceptLabel: String
    /// The concept's own definition, shown in its docked card just like an insight's. Set when an
    /// insight is promoted to a node (carries the source insight's definition); empty for auto
    /// clustered nodes, whose card falls back to a summary of their member insights.
    var definition: String = ""
    var insights: [InsightModel]
    var embedding: [Double]
    var position: CGPoint
    var isSuggested: Bool
    var suggestedInsights: [InsightModel]?
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

// MARK: - Layout Geometry

/// Radius of the ring an insight chip orbits around its node. Grows with the chip count and
/// the longest title so adjacent chips don't overlap. Shared by the layout engine
/// (`InsightTreeViewModel.insightOrbitPosition`) and the renderer
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

