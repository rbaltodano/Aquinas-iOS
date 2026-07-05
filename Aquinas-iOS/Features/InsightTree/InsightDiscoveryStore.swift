//
//  InsightDiscoveryStore.swift
//  Aquinas-iOS
//

import Foundation

enum InsightDiscoveryStore {
    private static let seenInsightIDsKey = "AquinasSeenInsightIDs"
    private static let undiscoveredIDsKey = "AquinasUndiscoveredInsightIDs"

    static func loadSeenInsightIDs() -> Set<UUID> {
        guard let strings = UserDefaults.standard.stringArray(forKey: seenInsightIDsKey) else {
            return []
        }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    static func saveSeenInsightIDs(_ ids: [UUID]) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: seenInsightIDsKey)
    }

    static func loadUndiscoveredInsightIDs() -> Set<UUID> {
        guard let strings = UserDefaults.standard.stringArray(forKey: undiscoveredIDsKey) else {
            return []
        }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    static func saveUndiscoveredInsightIDs(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: undiscoveredIDsKey)
    }

    @discardableResult
    static func markUndiscovered(_ ids: [UUID]) -> Set<UUID> {
        var current = loadUndiscoveredInsightIDs()
        var changed = false
        for id in ids where !current.contains(id) {
            current.insert(id)
            changed = true
        }
        if changed {
            saveUndiscoveredInsightIDs(current)
        }
        return current
    }

    @discardableResult
    static func markNewInsightsUndiscovered(_ currentInsightIDs: [UUID]) -> Set<UUID> {
        let seenIDs = loadSeenInsightIDs()
        let newIDs = currentInsightIDs.filter { !seenIDs.contains($0) }
        return markUndiscovered(newIDs)
    }

    static func visibleUndiscoveredCount(for visibleInsightIDs: [UUID]) -> Int {
        loadUndiscoveredInsightIDs()
            .intersection(Set(visibleInsightIDs))
            .count
    }
}
