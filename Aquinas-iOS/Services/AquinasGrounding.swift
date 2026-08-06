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
