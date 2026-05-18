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

