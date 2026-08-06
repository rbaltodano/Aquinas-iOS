//
//  MiniLMGroundingProvider.swift
//  Aquinas-iOS
//

import Foundation

/// Real semantic grounding retrieval, replacing `LocalAquinasGroundingProvider`'s tiny hardcoded
/// lexical index with an on-device MiniLM embedder searching the same corpus the backend uses
/// (see Aquinas_Backend/grounding_retrieval.py and ingest_corpus.py) — bundled as a flat,
/// pre-embedded export under `LocalGrounding/` rather than requiring the Mac backend.
nonisolated final class MiniLMGroundingProvider: AquinasGroundingProviding {
    private let embedder: MiniLMEmbedder
    private let store: OnDeviceGroundingStore

    init(embedder: MiniLMEmbedder, store: OnDeviceGroundingStore) {
        self.embedder = embedder
        self.store = store
    }

    convenience init(bundle: Bundle = .main) throws {
        guard let modelURL = bundle.url(
            forResource: "MiniLM",
            withExtension: "mlmodelc",
            subdirectory: "LocalGrounding"
        ) ?? bundle.url(forResource: "MiniLM", withExtension: "mlmodelc") else {
            throw MiniLMGroundingProviderError.resourceMissing("MiniLM.mlmodelc")
        }
        guard let vocabURL = bundle.url(
            forResource: "vocab",
            withExtension: "txt",
            subdirectory: "LocalGrounding"
        ) ?? bundle.url(forResource: "vocab", withExtension: "txt") else {
            throw MiniLMGroundingProviderError.resourceMissing("vocab.txt")
        }
        guard let embeddingsURL = bundle.url(
            forResource: "embeddings",
            withExtension: "bin",
            subdirectory: "LocalGrounding"
        ) ?? bundle.url(forResource: "embeddings", withExtension: "bin") else {
            throw MiniLMGroundingProviderError.resourceMissing("embeddings.bin")
        }
        guard let passagesURL = bundle.url(
            forResource: "passages",
            withExtension: "json",
            subdirectory: "LocalGrounding"
        ) ?? bundle.url(forResource: "passages", withExtension: "json") else {
            throw MiniLMGroundingProviderError.resourceMissing("passages.json")
        }

        let embedder = try MiniLMEmbedder(modelURL: modelURL, vocabURL: vocabURL)
        let store = try OnDeviceGroundingStore(
            embeddingsURL: embeddingsURL,
            passagesURL: passagesURL
        )
        self.init(embedder: embedder, store: store)
    }

    func references(
        for question: String,
        limit: Int
    ) -> [AquinasGroundingReference] {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let passages: [GroundingPassage]
        do {
            let queryEmbedding = try embedder.embed(question)
            passages = store.retrieve(queryEmbedding: queryEmbedding, k: limit)
        } catch {
            return []
        }
        return passages.map { passage in
            AquinasGroundingReference(
                id: "\(passage.sourceID)-\(passage.distance)",
                title: passage.title,
                sourceName: passage.title,
                facts: passage.text,
                retrievalAliases: []
            )
        }
    }
}

enum MiniLMGroundingProviderError: LocalizedError {
    case resourceMissing(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            "The on-device grounding corpus is missing \(name)."
        }
    }
}
