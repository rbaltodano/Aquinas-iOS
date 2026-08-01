//
//  InsightDiscoveryStore.swift
//  Aquinas-iOS
//

import Foundation

enum InsightDiscoveryStore {
    private static let seenInsightIDsKey = "AquinasSeenInsightIDs"
    private static let undiscoveredIDsKey = "AquinasUndiscoveredInsightIDs"
    private static let undiscoveredNodeIDsKey = "AquinasUndiscoveredNodeIDs"
    private static let pendingInsightPresentationIDsKey =
        "AquinasPendingInsightPresentationIDs"
    private static let pendingNodePresentationIDsKey =
        "AquinasPendingNodePresentationIDs"

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

    static func loadUndiscoveredNodeIDs() -> Set<UUID> {
        loadIDs(forKey: undiscoveredNodeIDsKey)
    }

    static func saveUndiscoveredNodeIDs(_ ids: Set<UUID>) {
        saveIDs(ids, forKey: undiscoveredNodeIDsKey)
    }

    @discardableResult
    static func markNodesUndiscovered(_ ids: [UUID]) -> Set<UUID> {
        var current = loadUndiscoveredNodeIDs()
        let previousCount = current.count
        current.formUnion(ids)
        if current.count != previousCount {
            saveUndiscoveredNodeIDs(current)
        }
        return current
    }

    static func markPendingTreePresentation(
        insightIDs: [UUID],
        nodeIDs: [UUID]
    ) {
        var pendingInsights = pendingInsightPresentationIDs()
        var pendingNodes = pendingNodePresentationIDs()
        pendingInsights.formUnion(insightIDs)
        pendingNodes.formUnion(nodeIDs)
        saveIDs(pendingInsights, forKey: pendingInsightPresentationIDsKey)
        saveIDs(pendingNodes, forKey: pendingNodePresentationIDsKey)
    }

    static func pendingInsightPresentationIDs() -> Set<UUID> {
        loadIDs(forKey: pendingInsightPresentationIDsKey)
    }

    static func pendingNodePresentationIDs() -> Set<UUID> {
        loadIDs(forKey: pendingNodePresentationIDsKey)
    }

    static func clearPendingTreePresentation(
        insightIDs: Set<UUID>,
        nodeIDs: Set<UUID>
    ) {
        var pendingInsights = pendingInsightPresentationIDs()
        var pendingNodes = pendingNodePresentationIDs()
        pendingInsights.subtract(insightIDs)
        pendingNodes.subtract(nodeIDs)
        saveIDs(pendingInsights, forKey: pendingInsightPresentationIDsKey)
        saveIDs(pendingNodes, forKey: pendingNodePresentationIDsKey)
    }

    private static func loadIDs(forKey key: String) -> Set<UUID> {
        guard let strings = UserDefaults.standard.stringArray(forKey: key) else {
            return []
        }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    private static func saveIDs(_ ids: Set<UUID>, forKey key: String) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: key)
    }
}
