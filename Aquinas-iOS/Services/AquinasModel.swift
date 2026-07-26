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
/// previews, fallback, and backend tasks that are not implemented yet. See
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
    func defineTerm(_ term: String, in context: ConversationContext) async -> ConceptDefinition

    /// A dynamic definition scoped to one persisted conversation. Implementations can use the
    /// conversation id to reuse definitions already generated for the same response context.
    func defineTerm(
        _ term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async -> ConceptDefinition

    /// Returns an already-generated contextual definition without asking the model to do work.
    /// A `nil` result means this conversation/source combination has not been defined yet.
    func cachedDefinition(
        for term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async -> ConceptDefinition?

    /// A 1–3 word subject label capturing what a set of Insight titles have in common — used to
    /// name a Node Concept.
    func labelSubject(forTitles titles: [String]) async -> String

    /// A single concept blending several source concepts at the given weights (the Midpoint tool).
    func blendConcepts(_ concepts: [ConceptDefinition], weights: [Double]) async -> ConceptDefinition

    /// The 3 child Insights generated when `concept` is promoted into a Node Concept (Make Node).
    func generateChildren(for concept: ConceptDefinition) async -> [ConceptDefinition]
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
    ) async -> ConceptDefinition {
        await defineTerm(term, in: context)
    }

    func cachedDefinition(
        for term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async -> ConceptDefinition? {
        nil
    }
}

/// The running conversation, passed to the model for any call that needs it as context.
struct ConversationContext {
    let compactedContext: String?
    let transcript: [ChatBlock]

    init(
        compactedContext: String? = nil,
        transcript: [ChatBlock] = []
    ) {
        self.compactedContext = compactedContext
        self.transcript = transcript
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

    init(
        text: String,
        thinkingSummary: [String] = [],
        keyTerms: [KeyTerm] = []
    ) {
        self.text = text
        self.thinkingSummary = thinkingSummary
        self.keyTerms = keyTerms
    }

    /// `text` with each key term wrapped as `[term](aq://slug)` — the markup
    /// `StreamingMessageView`'s existing link parser (`CachedRegex.insightLink`) expects. Matches
    /// each term within its `contextExcerpt` when one is given (to disambiguate a repeated word),
    /// else the first occurrence in the full text.
    var annotatedText: String {
        var result = text
        for term in keyTerms {
            let markup = "[\(term.displayText)](aq://\(Self.slugify(term.canonicalTerm)))"
            if !term.contextExcerpt.isEmpty,
               let excerptRange = result.range(of: term.contextExcerpt),
               let termRange = result.range(of: term.displayText, range: excerptRange) {
                result.replaceSubrange(termRange, with: markup)
            } else if let termRange = result.range(of: term.displayText) {
                result.replaceSubrange(termRange, with: markup)
            }
        }
        return result
    }

    private static func slugify(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}

// MARK: - Environment

private let defaultAquinasModel: AquinasModel = BackendAquinasModel()

extension EnvironmentValues {
    @Entry var aquinasModel: AquinasModel = defaultAquinasModel
    @Entry var embeddingProvider: EmbeddingProvider = NLEmbeddingProvider()
}
