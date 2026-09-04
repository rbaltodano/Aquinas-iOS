//
//  AquinasGrounding.swift
//  Aquinas-iOS
//

import Foundation

/// A short, trusted reference passage supplied to Aquinas before generation. The language model
/// may explain these facts, but it must not replace or contradict them.
nonisolated struct AquinasGroundingReference: Sendable, Equatable {
    let id: String
    let title: String
    let sourceName: String
    let facts: String
    let retrievalAliases: [String]

    var promptText: String {
        "[\(title) — \(sourceName)]\n\(facts)"
    }
}

/// Retrieval boundary for factual grounding. The first implementation uses a tiny local lexical
/// index so the contract works offline today. A MiniLM-backed provider can replace its ranking
/// implementation later without changing conversation generation or UI code.
nonisolated protocol AquinasGroundingProviding: Sendable {
    func references(
        for question: String,
        limit: Int
    ) -> [AquinasGroundingReference]
}

nonisolated struct LocalAquinasGroundingProvider: AquinasGroundingProviding {
    private static let references: [AquinasGroundingReference] = [
        AquinasGroundingReference(
            id: "nicaea-325",
            title: "First Council of Nicaea (325)",
            sourceName: "Catechism of the Catholic Church §242",
            facts: "The first ecumenical council met at Nicaea in 325. It addressed the Arian controversy and confessed that the Son is consubstantial (homoousios) with the Father. Nicaea is the historical English spelling; modern İznik is the city at that site.",
            retrievalAliases: [
                "first ecumenical council", "council of nicaea", "council of nicea",
                "nicaea", "nicea", "nica", "nicene creed", "homoousios", "arian"
            ]
        ),
        AquinasGroundingReference(
            id: "constantinople-381",
            title: "First Council of Constantinople (381)",
            sourceName: "Catechism of the Catholic Church §245",
            facts: "The First Council of Constantinople met in 381 and is counted as the second ecumenical council. It reaffirmed the faith of Nicaea and confessed the divinity of the Holy Spirit, contributing to the Nicene-Constantinopolitan Creed. It was not called the Council of Adhesion and it was not the council that settled the veneration of icons.",
            retrievalAliases: [
                "second ecumenical council", "first council of constantinople",
                "council of constantinople", "constantinople", "council of adhesion",
                "holy spirit", "nicene constantinopolitan creed"
            ]
        ),
        AquinasGroundingReference(
            id: "nicaea-787",
            title: "Second Council of Nicaea (787)",
            sourceName: "Catechism of the Catholic Church §2131",
            facts: "The Second Council of Nicaea met in 787 and is counted as the seventh ecumenical council. It defended the veneration of sacred images against iconoclasm. It must not be confused with Nicaea in 325 or Constantinople in 381.",
            retrievalAliases: [
                "second council of nicaea", "nicaea ii", "seventh ecumenical council",
                "icons", "icon veneration", "iconoclasm"
            ]
        ),
        AquinasGroundingReference(
            id: "didache-authorship",
            title: "The Didache",
            sourceName: "Aquinas curated reference note",
            facts: "The Didache, also called the Teaching of the Twelve Apostles, is an anonymous early Christian church-order and teaching text. Its author is unknown. It is not known to have been written by the Apostle Paul.",
            retrievalAliases: [
                "didache", "teaching of the twelve apostles", "written by paul",
                "apostle paul", "didache authorship"
            ]
        ),
        // A small stopgap for extremely well-known, doctrinally-central chapters, not an attempt
        // at Bible-wide coverage — full Scripture retrieval remains a separate on-device RAG
        // roadmap item.
        AquinasGroundingReference(
            id: "john-14",
            title: "Gospel of John, Chapter 14",
            sourceName: "Aquinas curated reference note",
            facts: "John 14 is part of Jesus's Farewell Discourse to his disciples at the Last Supper, the night before his crucifixion. It opens with Jesus telling the disciples not to let their hearts be troubled, and to trust in God and in him. In response to Thomas's question about the way, Jesus says he is the way, the truth, and the life, and that no one comes to the Father except through him. Jesus promises to send the Holy Spirit, called the Advocate (or Helper), to be with the disciples after he is gone, and to teach them and remind them of all he has said. This is a different passage from John 4, the account of Jesus and the Samaritan woman at the well.",
            retrievalAliases: [
                "john 14", "john chapter 14", "gospel of john 14", "farewell discourse",
                "way the truth and the life", "let not your hearts be troubled"
            ]
        ),
        AquinasGroundingReference(
            id: "john-3",
            title: "Gospel of John, Chapter 3",
            sourceName: "Aquinas curated reference note",
            facts: "John 3 recounts Jesus's night conversation with Nicodemus, a Pharisee and member of the Jewish ruling council, about being born again (or born from above) of water and the Spirit in order to enter the kingdom of God. The chapter contains the statement that God so loved the world that he gave his only Son, so that whoever believes in him should not perish but have eternal life.",
            retrievalAliases: [
                "john 3", "john chapter 3", "gospel of john 3", "nicodemus",
                "born again", "god so loved the world"
            ]
        ),
        AquinasGroundingReference(
            id: "matthew-5",
            title: "Gospel of Matthew, Chapter 5",
            sourceName: "Aquinas curated reference note",
            facts: "Matthew 5 opens the Sermon on the Mount, Jesus's extended teaching to his disciples and the crowds. It begins with the Beatitudes, a series of blessings on the poor in spirit, those who mourn, the meek, and others, and goes on to describe the disciples as salt of the earth and light of the world, and to deepen several commands of the Mosaic law (on anger, adultery, oaths, and retaliation) beyond their external observance.",
            retrievalAliases: [
                "matthew 5", "matthew chapter 5", "sermon on the mount", "beatitudes",
                "salt of the earth", "light of the world"
            ]
        ),
        AquinasGroundingReference(
            id: "romans-8",
            title: "Letter to the Romans, Chapter 8",
            sourceName: "Aquinas curated reference note",
            facts: "Romans 8 is Paul's teaching on life in the Spirit. It opens with the statement that there is now no condemnation for those who are in Christ Jesus, describes the Spirit as testifying with believers that they are children of God, and closes with the assurance that nothing in creation can separate believers from the love of God in Christ Jesus.",
            retrievalAliases: [
                "romans 8", "romans chapter 8", "no condemnation", "life in the spirit",
                "more than conquerors"
            ]
        ),
        AquinasGroundingReference(
            id: "1-corinthians-13",
            title: "First Letter to the Corinthians, Chapter 13",
            sourceName: "Aquinas curated reference note",
            facts: "1 Corinthians 13 is Paul's teaching on love (agape), often called the \"love chapter.\" It states that without love, even great gifts and knowledge are worthless, describes love as patient and kind, and concludes that faith, hope, and love remain, with love as the greatest of the three.",
            retrievalAliases: [
                "1 corinthians 13", "first corinthians 13", "corinthians chapter 13",
                "love chapter", "love is patient"
            ]
        ),
        AquinasGroundingReference(
            id: "psalm-23",
            title: "Psalm 23",
            sourceName: "Aquinas curated reference note",
            facts: "Psalm 23 is a psalm of David describing the Lord as a shepherd who provides, guides, and protects. It includes the images of green pastures, still waters, and walking through the valley of the shadow of death without fear, and closes with the psalmist's confidence in dwelling in the house of the Lord forever.",
            retrievalAliases: [
                "psalm 23", "the lord is my shepherd", "valley of the shadow of death",
                "green pastures"
            ]
        )
    ]

    func references(
        for question: String,
        limit: Int = 3
    ) -> [AquinasGroundingReference] {
        guard limit > 0 else { return [] }
        let normalizedQuestion = Self.normalized(question)
        let questionTokens = Self.tokens(in: normalizedQuestion)

        return Self.references
            .compactMap { reference -> (AquinasGroundingReference, Int)? in
                let aliasScore = reference.retrievalAliases.reduce(into: 0) { score, alias in
                    if normalizedQuestion.contains(Self.normalized(alias)) {
                        score += 12
                    }
                }
                let referenceTokens = Self.tokens(
                    in: reference.title + " " + reference.facts + " "
                        + reference.retrievalAliases.joined(separator: " ")
                )
                let overlapScore = questionTokens.intersection(referenceTokens).count * 2
                let score = aliasScore + overlapScore
                return score > 2 ? (reference, score) : nil
            }
            .sorted {
                if $0.1 == $1.1 { return $0.0.id < $1.0.id }
                return $0.1 > $1.1
            }
            .prefix(limit)
            .map(\.0)
    }

    /// Curated references whose question matched a retrieval *alias* rather than merely sharing a
    /// couple of tokens.
    ///
    /// The general `references(for:limit:)` ranking above admits a two-token overlap, which is the
    /// right bar when these entries are the entire corpus but far too loose when they are merged
    /// ahead of MiniLM results for every question. Alias hits are the precise signal, so the
    /// merged path uses only those — see `MiniLMGroundingProvider`.
    ///
    /// This exists because the bundled 48k-passage corpus has essentially no conciliar or creedal
    /// text: "Nicene Creed" appears once in the whole export (incidentally, in the Thirty-Nine
    /// Articles) and "begotten, not made" once, so semantic search answers council questions out
    /// of Livy and Herodotus. These curated entries carry the anti-confusion facts that coverage
    /// gap would otherwise lose, and their stable ids are what `verifiedGroundedResponse` gates on.
    static func aliasMatchedReferences(
        for question: String,
        limit: Int
    ) -> [AquinasGroundingReference] {
        guard limit > 0 else { return [] }
        let normalizedQuestion = normalized(question)

        return references
            .compactMap { reference -> (AquinasGroundingReference, Int)? in
                let score = reference.retrievalAliases.reduce(into: 0) { score, alias in
                    if normalizedQuestion.contains(normalized(alias)) {
                        score += alias.count
                    }
                }
                return score > 0 ? (reference, score) : nil
            }
            .sorted {
                if $0.1 == $1.1 { return $0.0.id < $1.0.id }
                return $0.1 > $1.1
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .lowercased()
    }

    private static func tokens(in text: String) -> Set<String> {
        Set(
            normalized(text)
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
        )
    }
}
