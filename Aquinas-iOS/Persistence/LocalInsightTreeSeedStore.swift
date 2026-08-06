//
//  LocalInsightTreeSeedStore.swift
//  Aquinas-iOS
//

import Foundation

/// An on-device-labeled Node Concept seeded from a conversation's questions/answers, used only
/// when the backend-owned persisted tree is unreachable (see `InsightTreeView`'s
/// `loadPersistedTree`). Not MiniLM parity — each seed's `embedding` is Apple's on-device
/// `NLEmbedding` space (`computeEmbedding`/`cosineSimilarity` in `InsightTreeViewModel.swift`),
/// used only to avoid spawning near-duplicate Nodes for the same conversation, not for full
/// clustering/relatedness math.
struct LocalInsightTreeSeed: Codable, Equatable {
    let id: UUID
    let label: String
    let summary: String
    let embedding: [Double]?
    let createdAt: Date
}

enum LocalInsightTreeSeedStore {
    private static let storageKey = "aquinas.insight-tree.local-seeds.v1"

    static func seeds(for conversationID: UUID) -> [LocalInsightTreeSeed] {
        let result = load()[conversationID.uuidString, default: []]
#if DEBUG
        print("Aquinas local seed store: read \(result.count) seed(s) for \(conversationID)")
#endif
        return result
    }

    static func appendSeed(_ seed: LocalInsightTreeSeed, for conversationID: UUID) {
        var all = load()
        var conversationSeeds = all[conversationID.uuidString, default: []]
        conversationSeeds.append(seed)
        all[conversationID.uuidString] = conversationSeeds
        save(all)
#if DEBUG
        print("Aquinas local seed store: appended '\(seed.label)' for \(conversationID), now \(conversationSeeds.count) seed(s)")
#endif
    }

    static func removeConversation(_ conversationID: UUID) {
        var all = load()
        all.removeValue(forKey: conversationID.uuidString)
        save(all)
#if DEBUG
        print("Aquinas local seed store: removed all seeds for \(conversationID)")
#endif
    }

    private static func load() -> [String: [LocalInsightTreeSeed]] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let seeds = try? JSONDecoder().decode(
                [String: [LocalInsightTreeSeed]].self,
                from: data
              ) else {
            return [:]
        }
        return seeds
    }

    private static func save(_ seeds: [String: [LocalInsightTreeSeed]]) {
        guard let data = try? JSONEncoder().encode(seeds) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
