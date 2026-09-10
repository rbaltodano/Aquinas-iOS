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

    /// Grounding is assembled in five layers, most authoritative first, because semantic search
    /// alone measurably fails two whole classes of question against this corpus:
    ///
    /// 1. **Curated facts.** The export carries almost no conciliar or creedal text, so council
    ///    questions retrieve Roman history. Alias-matched curated entries cover that gap and are
    ///    the only source of the stable ids (`nicaea-325`, `constantinople-381`, …) that
    ///    `LiteRTAquinasModel.verifiedGroundedResponse` gates its verified answers on.
    /// 2. **Explicit citations.** "John 14" is a lookup key, not a topic; resolved lexically
    ///    against the corpus's own chapter tags. See `ScriptureCitation`.
    /// 3. **Authority-section lookup.** A named doctrinal question such as Trent on justification
    ///    resolves to a section heading in that primary source. The pointer only selects corpus
    ///    text; it never supplies an answer.
    /// 4. **Named source lookup.** A council, creed or work title is a document key, not a broad
    ///    historical topic. It constrains semantic ranking to that real source.
    /// 5. **Semantic search**, which is strong for doctrinal and conceptual questions, filling any
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
        guard !CorpusScope.excludes(question) else { return [] }

        var collected: [AquinasGroundingReference] = []
        var seenPassages: Set<String> = []

        func append(_ reference: AquinasGroundingReference) {
            let passageKey = "\(reference.sourceName)\u{1F}\(reference.facts)"
            guard collected.count < limit, seenPassages.insert(passageKey).inserted else { return }
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
                for route in AuthoritySection.routes(in: question) {
                    guard collected.count < limit else { break }
                    for (offset, passage) in store.section(
                        sourceIDs: route.sourceIDs,
                        requiredTerms: route.sectionTerms,
                        limit: limit - collected.count
                    ).enumerated() {
                        append(Self.reference(
                            for: passage,
                            id: "authority-section-\(passage.sourceID)-\(offset)"
                        ))
                    }
                }
                let namedSourceIDs = NamedCorpusSource.sourceIDs(in: question)
                if !namedSourceIDs.isEmpty {
                    let sourceRankingQuery = NamedCorpusSource.rankingQuery(in: question)
                    let sourceEmbedding = sourceRankingQuery == question
                        ? queryEmbedding
                        : try embedder.embed(sourceRankingQuery)
                    for (offset, passage) in store.retrieve(
                        queryEmbedding: sourceEmbedding,
                        k: limit - collected.count,
                        sourceIDs: namedSourceIDs,
                        prioritizingTerms: NamedCorpusSource.searchTerms(in: question)
                    ).enumerated() {
                        append(Self.reference(for: passage, id: "source-\(passage.sourceID)-\(offset)"))
                    }
                }
                // A single global floor cannot serve both jobs. Loose enough to retrieve ordinary
                // narrative scripture (the Good Samaritan, the prodigal son) is also loose enough
                // to admit the 0.554-similarity Livy passages on "what did the Council of Nicaea
                // decide" -- measured, not hypothetical. So the floor depends on what the earlier
                // layers already found: when nothing authoritative matched, semantic search is the
                // only grounding available and uses the standard floor; when a curated fact or a
                // cited chapter already answered the question, weak semantic passages are padding
                // next to a confident answer, and padding is how a model ends up writing about
                // John 4 when it was handed John 14.
                let semanticMaxDistance: Float? = collected.isEmpty
                    ? nil
                    : Self.corroborationMaxDistance
                let passages = store.retrieve(
                    queryEmbedding: queryEmbedding,
                    k: limit - collected.count,
                    maxDistance: semanticMaxDistance
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

    /// Bar a semantic passage must clear to be added *alongside* an authoritative curated fact or
    /// cited chapter, as opposed to standing on its own. Stricter than the store's default floor.
    private static let corroborationMaxDistance: Float = 0.38

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

/// The bundled sources end before Vatican II and contain no current ecclesial data. These are
/// explicit corpus-boundary checks, not responses: they prevent unrelated historical passages from
/// being presented as evidence for a question this fixed, offline corpus cannot substantiate.
private enum CorpusScope {
    static func excludes(_ question: String) -> Bool {
        let normalized = question.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        let words = Set(normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return (words.contains("current") && words.contains("pope"))
            || normalized.contains("vatican ii")
            || normalized.contains("vatican 2")
            || normalized.contains("second vatican council")
    }
}

private enum NamedCorpusSource {
    /// A person's name may be the only meaningful lookup term in an otherwise generic question
    /// ("Who was Arius?"). Document titles deliberately do not use this fallback: matching
    /// "Roman" and "Catechism" throughout the Roman Catechism promotes front matter above its
    /// actual teaching.
    private static let personAliases: Set<String> = ["arius"]

    private static let aliases: [(name: String, sourceIDs: Set<String>)] = [
        ("council of trent", ["council-of-trent"]),
        ("trent", ["council-of-trent"]),
        ("roman catechism", ["roman-catechism-donovan"]),
        ("catechism of the council of trent", ["roman-catechism-donovan"]),
        ("tridentine catechism", ["roman-catechism-donovan"]),
        ("didache", ["didache"]),
        ("teaching of the twelve apostles", ["didache"]),
        ("council of nicaea", ["seven-ecumenical-councils"]),
        ("council of constantinople", ["seven-ecumenical-councils"]),
        ("council of chalcedon", ["seven-ecumenical-councils"]),
        ("arius", ["seven-ecumenical-councils"]),
        ("nicene creed", ["ecumenical-creeds-schaff"]),
        ("apostles' creed", ["ecumenical-creeds-schaff"]),
        ("apostles creed", ["ecumenical-creeds-schaff"])
    ]

    static func sourceIDs(in question: String) -> Set<String> {
        let normalized = normalized(question)
        return aliases.reduce(into: []) { matched, entry in
            if normalized.contains(entry.name) { matched.formUnion(entry.sourceIDs) }
        }
    }

    /// Within a named source, topic-bearing query terms should outrank title and front-matter
    /// chunks. For example, the Council of Trent source contains its own title on several early
    /// pages, while the question's "justification" term identifies the actual decree. Source
    /// aliases are stripped because the caller has already used them to choose the source.
    static func searchTerms(in question: String) -> Set<String> {
        let normalizedQuestion = normalized(question)
        let matchingAliases = aliases.filter { normalizedQuestion.contains($0.name) }
        let aliasWords = Set(matchingAliases.flatMap { entry in
            entry.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        })
        let stopWords: Set<String> = [
            "about", "after", "against", "and", "before", "could", "does", "from", "have", "into",
            "are", "council", "catechism", "decide", "did", "does", "is", "say", "should", "teach", "that", "the", "their", "these", "they", "this", "was", "what", "when", "who", "why",
            "where", "which", "with", "would"
        ]
        let terms = Set(normalizedQuestion.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) })
        let topicTerms = terms.subtracting(aliasWords)
        // A person-only question (for example, "Who was Arius?") still needs the name to find a
        // passage. When a document title is the whole question, preserve semantic source ranking
        // instead; common title words would otherwise make its front matter a false lookup hit.
        let matchesPersonAlias = matchingAliases.contains { personAliases.contains($0.name) }
        return topicTerms.isEmpty && matchesPersonAlias ? terms : topicTerms
    }

    static func rankingQuery(in question: String) -> String {
        let terms = searchTerms(in: question).sorted()
        return terms.isEmpty ? question : terms.joined(separator: " ")
    }

    private static func normalized(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
    }
}

/// Maps a well-known doctrinal formulation to the heading that contains it in an imported
/// primary source. This is retrieval metadata: it identifies the source text to read, and never
/// carries a paraphrase, conclusion, or negative example for the language model to repeat.
private enum AuthoritySection {
    private static let table: [(
        authorityTerms: [String],
        topicTerms: Set<String>,
        sourceIDs: Set<String>,
        sectionTerms: Set<String>
    )] = [
        (
            authorityTerms: ["trent"],
            topicTerms: ["justification", "justified"],
            sourceIDs: ["council-of-trent"],
            sectionTerms: ["what the justification of the impious is"]
        ),
        (
            authorityTerms: ["trent"],
            topicTerms: ["communion", "eucharist", "host", "presence"],
            sourceIDs: ["council-of-trent"],
            sectionTerms: ["on the real presence of our lord"]
        ),
        (
            authorityTerms: ["trent"],
            topicTerms: ["absolution", "confession", "penance"],
            sourceIDs: ["council-of-trent"],
            sectionTerms: ["doctrine on the sacrament of penance"]
        ),
        (
            authorityTerms: ["roman", "catechism"],
            topicTerms: ["baptism", "baptized", "baptize"],
            sourceIDs: ["roman-catechism-donovan"],
            sectionTerms: ["define baptism as we may"]
        ),
        (
            authorityTerms: ["roman", "catechism"],
            topicTerms: ["communion", "eucharist"],
            sourceIDs: ["roman-catechism-donovan"],
            sectionTerms: ["on the sacrament of the eucharist"]
        ),
        (
            authorityTerms: ["roman", "catechism"],
            topicTerms: ["absolution", "confession", "penance"],
            sourceIDs: ["roman-catechism-donovan"],
            sectionTerms: ["penance may be administered and becomes necessary"]
        ),
        (
            authorityTerms: ["nicaea"],
            topicTerms: ["christ", "consubstantial", "father", "homoousios", "jesus", "son"],
            sourceIDs: ["seven-ecumenical-councils"],
            sectionTerms: ["very god of very god"]
        ),
        (
            authorityTerms: ["chalcedon"],
            topicTerms: ["christ", "incarnation", "nature", "natures"],
            sourceIDs: ["seven-ecumenical-councils"],
            sectionTerms: ["in two natures"]
        )
    ]

    static func routes(in question: String) -> [(sourceIDs: Set<String>, sectionTerms: Set<String>)] {
        let words = Set(
            question.folding(
                options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        )
        return table.compactMap { route in
            guard route.authorityTerms.allSatisfy(words.contains),
                  !route.topicTerms.isDisjoint(with: words)
            else { return nil }
            return (sourceIDs: route.sourceIDs, sectionTerms: route.sectionTerms)
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
