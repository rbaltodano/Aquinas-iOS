//
//  ScholasticNode.swift
//  Aquinas-iOS
//
//  Created by Ryan on 5/4/26.
//

import Foundation

// MARK: - Scholastic Canvas Model

/// Represents the historical, structural role of the node.
enum NodeType: String, Codable, Equatable {
    case quaestio = "Quaestio"
    case videtur = "Videtur"
    case sedContra = "Sed Contra"
    case respondeo = "Respondeo"
    case insight = "Insight"
}

/// The core data structure driving the Infinite Canvas.
struct ScholasticNode: Identifiable, Codable, Equatable {
    let id: UUID
    let type: NodeType
    let title: String
    let content: String

    // Recursive child nodes allow a question to branch into objections, answers, and insights.
    var children: [ScholasticNode]

    init(type: NodeType, title: String, content: String, children: [ScholasticNode] = []) {
        self.id = UUID()
        self.type = type
        self.title = title
        self.content = content
        self.children = children
    }
}
