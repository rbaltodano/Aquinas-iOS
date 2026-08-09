//
//  LocalInsightTreeSeedStore.swift
//  Aquinas-iOS
//

import Foundation

/// A persistent on-device Node Concept extracted from a conversation turn. The embedding version
/// prevents vectors created in the old `NLEmbedding` space from being compared with bundled
/// MiniLM vectors; stale seeds are re-embedded before their next relatedness decision.
struct LocalInsightTreeSeed: Codable, Equatable {
    let id: UUID
    let label: String
    let summary: String
    let embedding: [Double]?
    let embeddingVersion: String?
    let createdAt: Date

    init(
        id: UUID,
        label: String,
        summary: String,
        embedding: [Double]?,
        embeddingVersion: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.label = label
        self.summary = summary
        self.embedding = embedding
        self.embeddingVersion = embeddingVersion
        self.createdAt = createdAt
    }
}

struct LocalInsightTreeSeedFileStore {
    static let legacyKey = "aquinas.insight-tree.local-seeds.v1"

    let fileURL: URL
    let defaults: UserDefaults
    let fileManager: FileManager

    init(
        fileURL: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func load() -> [String: [LocalInsightTreeSeed]] {
        if let data = try? Data(contentsOf: fileURL),
           let seeds = try? JSONDecoder().decode(
            [String: [LocalInsightTreeSeed]].self,
            from: data
           ) {
            return seeds
        }
        guard let data = defaults.data(forKey: Self.legacyKey),
              let seeds = try? JSONDecoder().decode(
                [String: [LocalInsightTreeSeed]].self,
                from: data
              ) else {
            return [:]
        }
        do {
            try save(seeds)
            defaults.removeObject(forKey: Self.legacyKey)
        } catch {
            // Preserve the legacy value until the protected file write succeeds.
        }
        return seeds
    }

    func save(_ seeds: [String: [LocalInsightTreeSeed]]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(seeds)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

enum LocalInsightTreeSeedStore {
    static func seeds(for conversationID: UUID) -> [LocalInsightTreeSeed] {
        liveStore()?.load()[conversationID.uuidString, default: []] ?? []
    }

    static func appendSeed(_ seed: LocalInsightTreeSeed, for conversationID: UUID) {
        var all = liveStore()?.load() ?? [:]
        all[conversationID.uuidString, default: []].append(seed)
        try? liveStore()?.save(all)
    }

    static func replaceSeeds(
        _ seeds: [LocalInsightTreeSeed],
        for conversationID: UUID
    ) {
        var all = liveStore()?.load() ?? [:]
        all[conversationID.uuidString] = seeds
        try? liveStore()?.save(all)
    }

    static func removeConversation(_ conversationID: UUID) {
        var all = liveStore()?.load() ?? [:]
        all.removeValue(forKey: conversationID.uuidString)
        try? liveStore()?.save(all)
    }

    private static func liveStore() -> LocalInsightTreeSeedFileStore? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return LocalInsightTreeSeedFileStore(
            fileURL: applicationSupport.appending(
                path: "Aquinas/InsightTree/local-seeds-v2.json"
            )
        )
    }
}
