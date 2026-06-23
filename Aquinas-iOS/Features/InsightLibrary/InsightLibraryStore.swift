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

extension Array where Element == ConceptDefinition {
    func uniquedByWord() -> [ConceptDefinition] {
        var seenWords = Set<String>()
        var uniqueInsights: [ConceptDefinition] = []

        for insight in self {
            let key = insight.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seenWords.contains(key) else { continue }
            seenWords.insert(key)
            uniqueInsights.append(insight)
        }

        return uniqueInsights
    }
}
