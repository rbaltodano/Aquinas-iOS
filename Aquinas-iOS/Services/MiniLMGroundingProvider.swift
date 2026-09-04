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

    /// Grounding is assembled in three layers, most authoritative first, because semantic search
    /// alone measurably fails two whole classes of question against this corpus:
    ///
    /// 1. **Curated facts.** The export carries almost no conciliar or creedal text, so council
    ///    questions retrieve Roman history. Alias-matched curated entries cover that gap and are
    ///    the only source of the stable ids (`nicaea-325`, `constantinople-381`, …) that
    ///    `LiteRTAquinasModel.verifiedGroundedResponse` gates its verified answers on.
    /// 2. **Explicit citations.** "John 14" is a lookup key, not a topic; resolved lexically
    ///    against the corpus's own chapter tags. See `ScriptureCitation`.
    /// 3. **Semantic search**, which is strong for doctrinal and conceptual questions, filling any
    ///    remaining slots.
    ///
    /// Every layer can legitimately return nothing, and returning nothing is correct when the
    /// corpus has no real answer — generation then proceeds ungrounded rather than grounded in
    /// something false.
    func references(
        for question: String,
        limit: Int
    ) -> [AquinasGroundingReference] {
        guard limit > 0,
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return [] }

        var collected: [AquinasGroundingReference] = []
        var seenIDs: Set<String> = []

        func append(_ reference: AquinasGroundingReference) {
            guard collected.count < limit, seenIDs.insert(reference.id).inserted else { return }
            collected.append(reference)
        }

        for reference in LocalAquinasGroundingProvider.aliasMatchedReferences(
            for: question,
            // Curated notes anchor an answer; they must not crowd out the corpus itself.
            limit: max(1, limit - 1)
        ) {
            append(reference)
        }

        for citation in ScriptureCitation.citations(in: question) {
            guard collected.count < limit else { break }
            for passage in store.chapter(for: citation, limit: limit - collected.count) {
                append(Self.reference(for: passage, id: "citation-\(citation.bookCode)\(citation.chapter)-\(passage.sourceID)-\(collected.count)"))
            }
        }

        if collected.count < limit {
            do {
                let queryEmbedding = try embedder.embed(question)
                let passages = store.retrieve(
                    queryEmbedding: queryEmbedding,
                    k: limit - collected.count
                )
                for (offset, passage) in passages.enumerated() {
                    append(Self.reference(for: passage, id: "corpus-\(passage.sourceID)-\(offset)"))
                }
            } catch {
                // A failed embed leaves whatever the earlier layers found, which is still
                // better grounding than none.
            }
        }

        return collected
    }

    private static func reference(
        for passage: GroundingPassage,
        id: String
    ) -> AquinasGroundingReference {
        AquinasGroundingReference(
            id: id,
            title: passage.title,
            sourceName: passage.title,
            facts: passage.text,
            retrievalAliases: []
        )
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
