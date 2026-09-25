//
//  ConceptDefinition.swift
//  Aquinas-iOS
//

import Foundation

nonisolated struct InsightDefinition: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    let context: String
    let meaning: String

    init(id: UUID? = nil, context: String, meaning: String) {
        let cleanedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedMeaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id ?? stableUUID(
            from: "insight-definition:\(cleanedContext.lowercased()):\(cleanedMeaning.lowercased())"
        )
        self.context = cleanedContext
        self.meaning = cleanedMeaning
    }

    fileprivate var deduplicationKey: String {
        "\(context.lowercased())\u{1f}\(meaning.lowercased())"
    }
}

nonisolated struct ConceptDefinition: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    let word: String
    let partOfSpeech: String
    let pronunciation: String
    let meaning: String
    let example: String
    let definitions: [InsightDefinition]

    init(
        id: UUID = UUID(),
        word: String,
        partOfSpeech: String,
        pronunciation: String,
        meaning: String,
        example: String,
        context: String = "",
        definitions: [InsightDefinition]? = nil
    ) {
        self.id = id
        self.word = word
        self.partOfSpeech = partOfSpeech
        self.pronunciation = pronunciation
        self.meaning = meaning
        self.example = example
        self.definitions = definitions ?? (
            meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? []
                : [InsightDefinition(context: context, meaning: meaning)]
        )
    }

    var contextualDefinitions: [InsightDefinition] {
        definitions.isEmpty && !meaning.isEmpty
            ? [InsightDefinition(context: "", meaning: meaning)]
            : definitions
    }

    var semanticDefinition: String {
        contextualDefinitions.map { definition in
            definition.context.isEmpty
                ? definition.meaning
                : "\(definition.context): \(definition.meaning)"
        }
        .joined(separator: "\n")
    }

    func containsDefinitions(from other: ConceptDefinition) -> Bool {
        let savedKeys = Set(contextualDefinitions.map(\.deduplicationKey))
        let incoming = other.contextualDefinitions
        return !incoming.isEmpty
            && incoming.allSatisfy { savedKeys.contains($0.deduplicationKey) }
    }

    func mergingDefinitions(from other: ConceptDefinition) -> ConceptDefinition {
        var merged = contextualDefinitions
        var seen = Set(merged.map(\.deduplicationKey))
        for definition in other.contextualDefinitions
        where seen.insert(definition.deduplicationKey).inserted {
            merged.append(definition)
        }
        return ConceptDefinition(
            id: id,
            word: word,
            partOfSpeech: "",
            pronunciation: "",
            meaning: merged.first?.meaning ?? meaning,
            example: "",
            definitions: merged
        )
    }

    /// A stable id derived from the term's canonical text, so re-defining/re-saving the same term
    /// (tapping it again in a different message, or after removing and re-saving it) always
    /// resolves to the same Insight instead of a duplicate with a fresh random id. Use this rather
    /// than the default random `id` whenever a concept originates from a highlighted term.
    static func stableID(forTerm term: String) -> UUID {
        stableUUID(from: "term:\(term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case word
        case partOfSpeech
        case pronunciation
        case meaning
        case example
        case definitions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        partOfSpeech = try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? ""
        pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation) ?? ""
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        definitions = try container.decodeIfPresent(
            [InsightDefinition].self,
            forKey: .definitions
        ) ?? (
            meaning.isEmpty ? [] : [InsightDefinition(context: "", meaning: meaning)]
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(word, forKey: .word)
        try container.encode(partOfSpeech, forKey: .partOfSpeech)
        try container.encode(pronunciation, forKey: .pronunciation)
        try container.encode(meaning, forKey: .meaning)
        try container.encode(example, forKey: .example)
        try container.encode(definitions, forKey: .definitions)
    }
}
