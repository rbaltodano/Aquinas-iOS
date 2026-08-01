//
//  InsightLibraryStore.swift
//  Aquinas-iOS
//

import Foundation

// MARK: - Saved Insight Library

/// Lightweight persistence for saved insights until the production SwiftData layer owns them.
enum InsightLibraryStore {
    private static let savedInsightsKey = "aquinas.saved.insights.v1"

    static func load() -> [ConceptDefinition] {
        guard let data = UserDefaults.standard.data(forKey: savedInsightsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([ConceptDefinition].self, from: data)
        } catch {
            UserDefaults.standard.removeObject(forKey: savedInsightsKey)
            return []
        }
    }

    static func save(_ insights: [ConceptDefinition]) {
        let uniqueInsights = insights.uniquedByWord()

        do {
            let data = try JSONEncoder().encode(uniqueInsights)
            UserDefaults.standard.set(data, forKey: savedInsightsKey)
        } catch {
            assertionFailure("Unable to save insight library: \(error)")
        }
    }
}

/// The last bookmark collection the user explicitly accepted for the Global Insight Tree.
///
/// Keeping this separate from `InsightLibraryStore` lets saving remain immediate while the
/// potentially disruptive canvas regrouping waits for confirmation when Global Insights opens.
enum GlobalInsightTreeStore {
    private static let snapshotKey = "aquinas.global-insight-tree.snapshot.v1"

    static func load() -> [ConceptDefinition] {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              let insights = try? JSONDecoder().decode(
                [ConceptDefinition].self,
                from: data
              ) else {
            return []
        }
        return insights.uniquedByWord()
    }

    static func save(_ insights: [ConceptDefinition]) {
        do {
            let data = try JSONEncoder().encode(insights.uniquedByWord())
            UserDefaults.standard.set(data, forKey: snapshotKey)
        } catch {
            assertionFailure("Unable to save Global Insight Tree snapshot: \(error)")
        }
    }
}

extension Array where Element == ConceptDefinition {
    func uniquedByWord() -> [ConceptDefinition] {
        var indexByWord: [String: Int] = [:]
        var uniqueInsights: [ConceptDefinition] = []

        for insight in self {
            let key = insight.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            if let existingIndex = indexByWord[key] {
                uniqueInsights[existingIndex] = uniqueInsights[
                    existingIndex
                ].mergingDefinitions(from: insight)
            } else {
                indexByWord[key] = uniqueInsights.count
                uniqueInsights.append(insight)
            }
        }

        return uniqueInsights
    }
}
