//
//  AquinasModel.swift
//  Aquinas-iOS
//

import Foundation
import SwiftUI

// MARK: - Model Boundary

/// The single boundary between the app and "the model" — whatever text-generation backend is
/// answering conversations, defining terms, labeling subjects, blending concepts, and generating
/// Make Node children. Every generative call in the app funnels through here.
/// `BackendAquinasModel` is the live environment default; `MockAquinasModel` remains available for
/// previews and tests only. See
/// `MODEL-INTEGRATION.md` §3/§6 for the backend JSON/route contract and `INSIGHT-TREE.md` §10 for
/// the Insight Tree-specific seam inventory.
protocol AquinasModel {
    /// The response to the running conversation: plain prose plus the terms worth defining within
    /// it (see `ModelResponse`). This complete-response operation remains available as the
    /// compatibility and validation-repair fallback for the streaming overload below.
    func respond(to context: ConversationContext) async -> ModelResponse

    /// Streams approved, user-facing progress while a response is generated. Implementations
    /// must never surface a provider's private scratch work or hidden chain-of-thought.
    func respond(
        to context: ConversationContext,
        thinkingEnabled: Bool,
        onUpdate: @escaping (ModelResponseUpdate) -> Void
    ) async -> ModelResponse

    /// Produces hidden, durable context that can replace older turns in future requests.
    func compact(_ context: ConversationContext) async -> String

    /// A definition for a tapped highlighted term, generated as it relates to this conversation
    /// (not a dictionary lookup).
    func defineTerm(
        _ term: String,
        in context: ConversationContext
    ) async throws -> ConceptDefinition

    /// A dynamic definition scoped to one persisted conversation. Implementations can use the
    /// conversation id to reuse definitions already generated for the same response context.
    func defineTerm(
        _ term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async throws -> ConceptDefinition

    /// Returns an already-generated contextual definition without asking the model to do work.
    /// A `nil` result means this conversation/source combination has not been defined yet.
    func cachedDefinition(
        for term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async -> ConceptDefinition?

    /// The most elementary 1–5 word subject label organizing a set of contextual Insight
    /// descriptions — used to name a Node Concept.
    func labelSubject(forTitles titles: [String]) async throws -> String

    /// Candidate syntheses for mathematical vector-space selection by the Midpoint tool.
    func blendConceptCandidates(
        _ concepts: [ConceptDefinition],
        weights: [Double]
    ) async throws -> [ConceptDefinition]

    /// The 3 child Insights generated when `concept` is promoted into a Node Concept (Make Node).
    func generateChildren(for concept: ConceptDefinition) async throws -> [ConceptDefinition]

    /// Creates a once-daily home prompt from one recent conversation.
    func generateQuestionOfTheDay(
        from context: ConversationContext,
        conversationTitle: String,
        insights: [ConceptDefinition]
    ) async throws -> DailyQuestionDraft
}

enum AquinasModelActionError: Error {
    case unavailable
    case invalidRequest
    case invalidResponse
}

extension AquinasModel {
    func respond(
        to context: ConversationContext,
        thinkingEnabled: Bool,
        onUpdate: @escaping (ModelResponseUpdate) -> Void
    ) async -> ModelResponse {
        onUpdate(.generationStarted)
        let response = await respond(to: context)
        if thinkingEnabled && !response.thinkingSummary.isEmpty {
            onUpdate(.thinkingSummary(response.thinkingSummary))
        }
        onUpdate(.responseText(response.text))
        guard !thinkingEnabled else {
            return response
        }
        return ModelResponse(
            text: response.text,
            thinkingSummary: [],
            keyTerms: response.keyTerms
        )
    }

    func defineTerm(
        _ term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async throws -> ConceptDefinition {
        try await defineTerm(term, in: context)
    }

    func cachedDefinition(
        for term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async -> ConceptDefinition? {
        nil
    }

    func generateQuestionOfTheDay(
        from context: ConversationContext,
        conversationTitle: String,
        insights: [ConceptDefinition]
    ) async throws -> DailyQuestionDraft {
        let citedInsight = insights.first
        let subject = citedInsight?.word ?? conversationTitle
        return DailyQuestionDraft(
            question: "What implication of \(subject) would be most fruitful to explore next?",
            reasonForAsking: "It seemed like this was the next place your recent inquiry could open up.",
            citedInsightTitle: citedInsight?.word
        )
    }
}

enum ConversationPersonality: String, CaseIterable, Identifiable, Codable {
    case balanced
    case scholarly
    case socratic
    case fun

    var id: Self { self }

    var displayName: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .scholarly:
            return "Scholarly"
        case .socratic:
            return "Socratic"
        case .fun:
            return "Fun Mode"
        }
    }

    var shortDescription: String {
        switch self {
        case .balanced:
            return "Warm, friendly, and ready for deeper dialogue."
        case .scholarly:
            return "Formal, rigorous, and grounded in the Thomistic tradition."
        case .socratic:
            return "Guides understanding through questions and careful dialogue."
        case .fun:
            return "Your personable, casual, slightly eccentric best friend."
        }
    }
}

/// The running conversation, passed to the model for any call that needs it as context.
struct ConversationContext {
    let compactedContext: String?
    let transcript: [ChatBlock]
    let personality: ConversationPersonality

    init(
        compactedContext: String? = nil,
        transcript: [ChatBlock] = [],
        personality: ConversationPersonality = .balanced
    ) {
        self.compactedContext = compactedContext
        self.transcript = transcript
        self.personality = personality
    }
}

/// A term the model flagged as worth defining, with enough context to place its highlight
/// precisely. Mirrors the backend's `key_terms` shape (MODEL-INTEGRATION.md §3) — the model
/// returns plain prose plus this structured list; application code, not the model, turns
/// validated terms into `aq://` highlight markup, since the model isn't trusted to produce
/// correct application URLs itself.
struct KeyTerm {
    let displayText: String
    let canonicalTerm: String
    let contextExcerpt: String

    init(displayText: String, canonicalTerm: String? = nil, contextExcerpt: String = "") {
        self.displayText = displayText
        self.canonicalTerm = canonicalTerm ?? displayText
        self.contextExcerpt = contextExcerpt
    }
}

enum ModelResponseUpdate {
    case generationStarted
    case thinkingSummary([String])
    case responseText(String)
}

/// The model's answer to a conversation turn: plain prose plus the terms worth defining within
/// it. `annotatedText` is what the UI actually renders — see `KeyTerm`'s doc comment for why the
/// splice happens here instead of trusting the model to emit `aq://` links directly.
struct ModelResponse {
    let text: String
    let thinkingSummary: [String]
    let keyTerms: [KeyTerm]
    let insight: ConceptDefinition?

    init(
        text: String,
        thinkingSummary: [String] = [],
        keyTerms: [KeyTerm] = [],
        insight: ConceptDefinition? = nil
    ) {
        self.text = text
        self.thinkingSummary = thinkingSummary
        self.keyTerms = keyTerms
        self.insight = insight
    }

    /// `text` with each key term wrapped as `[term](aq://slug)` — the markup
    /// `StreamingMessageView`'s existing link parser (`CachedRegex.insightLink`) expects. Matches
    /// each term within its `contextExcerpt` when one is given (to disambiguate a repeated word),
    /// else the first occurrence in the full text.
    var annotatedText: String {
        let source = text as NSString
        var replacements: [(range: NSRange, markup: String)] = []

        // Resolve every range against the untouched prose. Mutating while searching can make a
        // later short term match inside an earlier aq:// URL and leak literal markdown.
        for term in keyTerms.sorted(by: {
            $0.displayText.count > $1.displayText.count
        }) {
            let termRange: NSRange
            if !term.contextExcerpt.isEmpty {
                let excerptRange = source.range(of: term.contextExcerpt)
                termRange = excerptRange.location == NSNotFound
                    ? Self.matchingRange(
                        of: term.displayText,
                        in: text
                    )
                    : Self.matchingRange(
                        of: term.displayText,
                        in: text,
                        searchRange: excerptRange
                    )
            } else {
                termRange = Self.matchingRange(
                    of: term.displayText,
                    in: text
                )
            }
            guard termRange.location != NSNotFound,
                  !replacements.contains(where: {
                      NSIntersectionRange($0.range, termRange).length > 0
                  }) else {
                continue
            }
            replacements.append((
                termRange,
                "[\(term.displayText)](aq://\(Self.slugify(term.canonicalTerm)))"
            ))
        }

        let mutable = NSMutableString(string: text)
        for replacement in replacements.sorted(by: {
            $0.range.location > $1.range.location
        }) {
            mutable.replaceCharacters(
                in: replacement.range,
                with: replacement.markup
            )
        }
        var result = mutable as String
        if let insight {
            result = "\(InlineInsightMarkup.marker(for: insight))\n\n\(result)"
        }
        return result
    }

    private static func slugify(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private static func matchingRange(
        of term: String,
        in text: String,
        searchRange: NSRange? = nil
    ) -> NSRange {
        let escaped = NSRegularExpression.escapedPattern(for: term)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}])\#(escaped)(?![\p{L}\p{N}])"#,
            options: [.caseInsensitive]
        ) else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return regex.firstMatch(
            in: text,
            range: searchRange ?? NSRange(text.startIndex..., in: text)
        )?.range ?? NSRange(location: NSNotFound, length: 0)
    }
}

/// Encodes generated Insight cards inside the existing persisted response string. Keeping this
/// metadata on its own line lets old conversations remain decodable while the response renderer
/// can restore the complete interactive card after relaunch.
enum InlineInsightMarkup {
    private static let prefix = "<!--aq-inline-insight:"
    private static let suffix = "-->"

    static func marker(for insight: ConceptDefinition) -> String {
        guard let data = try? JSONEncoder().encode(insight) else { return "" }
        return "\(prefix)\(data.base64EncodedString())\(suffix)"
    }

    static func insight(from line: String) -> ConceptDefinition? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(suffix) else {
            return nil
        }
        let payload = trimmed
            .dropFirst(prefix.count)
            .dropLast(suffix.count)
        guard let data = Data(base64Encoded: String(payload)),
              let decoded = try? JSONDecoder().decode(
                ConceptDefinition.self,
                from: data
              ) else {
            return nil
        }
        return decoded
    }

    static func insights(in text: String) -> [ConceptDefinition] {
        var result: [ConceptDefinition] = []
        for line in text.components(separatedBy: "\n") {
            if let decoded = insight(from: line) {
                result.append(decoded)
            }
        }
        return result
    }

    static func plainText(from text: String) -> String {
        text.components(separatedBy: "\n")
            .map { line in
                guard let insight = insight(from: line) else { return line }
                return "\(insight.word)\n\(insight.meaning)"
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Environment

private let defaultAquinasModel: AquinasModel = BackendAquinasModel()

extension EnvironmentValues {
    @Entry var aquinasModel: AquinasModel = defaultAquinasModel
    @Entry var embeddingProvider: EmbeddingProvider = NLEmbeddingProvider()
}
