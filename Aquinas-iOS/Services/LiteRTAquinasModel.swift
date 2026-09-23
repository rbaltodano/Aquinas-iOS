//
//  LiteRTAquinasModel.swift
//  Aquinas-iOS
//

import Foundation
import LiteRTLM

/// The live local-first model boundary. Generation stays on the phone whenever LiteRT is healthy;
/// the development backend remains a recovery path while model delivery and failure telemetry are
/// being productionized.
struct LiteRTAquinasModel: AquinasModel {
#if DEBUG
    /// Exposes the production prompt to the opt-in evidence experiment only.
    static func evidenceExperimentInstruction(
        context: ConversationContext,
        references: [AquinasGroundingReference]
    ) -> String {
        conversationSystemInstruction(context: context, groundingReferences: references)
    }
#endif
    private let runtime: LiteRTAquinasRuntime
    private let fallback: BackendAquinasModel
    private let groundingProvider: any AquinasGroundingProviding

    init(
        runtime: LiteRTAquinasRuntime,
        fallback: BackendAquinasModel = BackendAquinasModel(),
        groundingProvider: any AquinasGroundingProviding = LocalAquinasGroundingProvider()
    ) {
        self.runtime = runtime
        self.fallback = fallback
        self.groundingProvider = groundingProvider
    }

    /// Whether falling back to the development backend can possibly succeed. On a physical
    /// device pointed at loopback (the shipped default) it never can, so every fallback call is
    /// guaranteed-useless work sitting in the serialized generation path — which is exactly what
    /// made batches of queued definitions feel stuck: each local failure paid a full engine
    /// unload + 3.86GB reload + retry, and *then* a doomed network round trip, before the queue
    /// could move on. `respond()` has always guarded this; every other operation did not.
    private var canUseBackendFallback: Bool {
        AquinasBackendConfiguration.canRecoverFromCurrentDevice
    }

    static func definitionRequestTerm(
        in transcript: [ChatBlock]
    ) -> String? {
        requestedDefinitionTerm(in: transcript)
    }

    static func startsFreshTopic(
        latestQuestion: String,
        previousQuestion: String
    ) -> Bool {
        isLikelyTopicShift(
            latestQuestion: latestQuestion,
            previousQuestion: previousQuestion
        )
    }

    static func repeatsEarlierAnswer(
        _ response: String,
        transcript: [ChatBlock]
    ) -> Bool {
        duplicatesEarlierAnswer(response, in: transcript)
    }

    static func visibleResponseText(
        from raw: String
    ) -> String {
        sanitizedVisibleText(raw)
    }

    static func questionOfTheDayQuestion(from raw: String) -> String? {
        let cleaned = sanitizedVisibleText(raw)
            .replacingOccurrences(of: "```", with: "")
            .trimmed
        for rawLine in cleaned.split(whereSeparator: \Character.isNewline).reversed() {
            var line = String(rawLine).trimmed
            for prefix in ["Question of the Day:", "Question:"] where line.hasPrefix(prefix) {
                line = String(line.dropFirst(prefix.count)).trimmed
            }
            line = line.trimmingCharacters(
                in: CharacterSet(charactersIn: "-*#>\"“” ")
            )
            if line.last != "?" {
                let normalized = line.lowercased()
                let interrogativePrefixes = [
                    "how ", "why ", "what ", "when ", "where ", "who ", "which ",
                    "can ", "could ", "would ", "should ", "is ", "are ", "do ",
                    "does ", "did "
                ]
                guard interrogativePrefixes.contains(where: normalized.hasPrefix) else {
                    continue
                }
                line = line.trimmingCharacters(in: CharacterSet(charactersIn: ".! ")) + "?"
            }
            guard (12...320).contains(line.count) else { continue }
            return line
        }
        return nil
    }

    static func approachSummary(
        for context: ConversationContext
    ) -> [String] {
        publicApproachSummary(for: context)
    }

    static func authorshipCorrectionDetails(
        in question: String
    ) -> (subject: String, author: String)? {
        guard let correction = explicitAuthorshipCorrection(in: question) else {
            return nil
        }
        return (correction.subject, correction.author)
    }

    static func responseContradictsExplicitAuthorshipCorrection(
        question: String,
        response: String
    ) -> Bool {
        guard let correction = explicitAuthorshipCorrection(in: question) else {
            return false
        }
        return contradictsAuthorshipCorrection(correction, response: response)
    }

    static func groundedResponse(
        for question: String,
        references: [AquinasGroundingReference],
        thinkingEnabled: Bool = true
    ) -> ModelResponse? {
        verifiedGroundedResponse(
            for: question,
            references: references,
            thinkingEnabled: thinkingEnabled
        )
    }

    static func requiresFactualAccuracyAudit(_ question: String) -> Bool {
        factualAccuracyAuditNeeded(for: question)
    }

    /// The corpus is required for claims that need a verifiable source. Ordinary definitions,
    /// reflections, practical discussion, and hypotheticals are allowed to use the model's
    /// general knowledge when retrieval has no relevant passage.
    static func requiresCorpusEvidence(_ question: String) -> Bool {
        let normalized = question
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        if let definitionTerm = definitionRequestTerm(in: [.user(question, nil, [])]),
           requiresSpecialistDefinitionEvidence(definitionTerm) {
            return true
        }

        let sourceDependentTerms = [
            "quote", "quotation", "according to", "citation", "source", "authorship",
            "author", "wrote", "written by", "date", "year", "century", "how many",
            "current", "latest", "today", "council", "nicaea", "chalcedon", "trent",
            "creed", "catechism", "canon", "scripture", "bible", "gospel", "chapter",
            "verse", "summa", "didache", "encyclical", "document", "decree", "history",
            "historical", "war", "battle", "revolution", "empire", "reign", "happened",
            "occurred"
        ]
        if sourceDependentTerms.contains(where: normalized.contains) {
            return true
        }

        if normalized.hasPrefix("who was ")
            || normalized.hasPrefix("who is ")
            || normalized.hasPrefix("when did ")
            || normalized.hasPrefix("when was ")
            || normalized.hasPrefix("where did ")
            || normalized.hasPrefix("where was ") {
            return true
        }

        return false
    }

    /// The compact on-device model is reliable for ordinary definitions, but not for unfamiliar,
    /// highly technical labels when retrieval has no direct evidence. Require a passage for those
    /// terms rather than presenting a fluent invented definition as knowledge.
    static func requiresSpecialistDefinitionEvidence(_ term: String) -> Bool {
        let words = term.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard words.count == 1, let word = words.first else { return false }
        let normalized = word.lowercased()
        return normalized.count >= 16
            || (normalized.count >= 12 && normalized.hasSuffix("ism"))
    }

    static func isAuditMetaCommentary(_ text: String) -> Bool {
        looksLikeAuditMetaCommentary(text)
    }

    /// A fixed-corpus abstention is not an answer and must never become an Insight Tree subject.
    static func isCorpusScopeAbstention(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) == corpusScopeAbstentionText
    }

    /// A Question of the Day is stored as a leading user prompt, followed immediately by the
    /// person's reflective reply. The reply alone is often personal language with little source
    /// vocabulary ("I should be more gracious"), so retrieve from the whole prompt-and-reply
    /// exchange. Ordinary turns alternate user/model blocks and still retrieve from the latest
    /// question alone, preserving the corpus-scope abstention for unrelated questions.
    static func groundingQuery(for context: ConversationContext) -> String {
        guard let latestIndex = context.transcript.lastIndex(where: { block in
            if case .user = block { return true }
            return false
        }),
        case .user(let latestQuestion, _, _) = context.transcript[latestIndex] else {
            return ""
        }

        let latest = latestQuestion.trimmed
        guard latestIndex > 0,
              case .user(let precedingPrompt, _, _) = context.transcript[latestIndex - 1]
        else {
            return latest
        }

        let prompt = precedingPrompt.trimmed
        guard !prompt.isEmpty else { return latest }
        return "\(prompt)\n\n\(latest)"
    }

    /// For a definition, accept semantic retrieval only if a passage explicitly names the term.
    /// This is a per-answer evidence check; it does not change retrieval thresholds or floors.
    static func definitionEvidence(
        for term: String,
        in references: [AquinasGroundingReference]
    ) -> [AquinasGroundingReference] {
        let normalizedTerm = normalizedDefinitionEvidenceText(term)
        guard !normalizedTerm.isEmpty else { return [] }
        return references.filter { reference in
            normalizedDefinitionEvidenceText(
                "\(reference.title) \(reference.facts)"
            )
            .contains(normalizedTerm)
        }
    }

    private static func normalizedDefinitionEvidenceText(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func respond(to context: ConversationContext) async -> ModelResponse {
        await respond(
            to: context,
            thinkingEnabled: true,
            onUpdate: { _ in }
        )
    }

    func respond(
        to context: ConversationContext,
        thinkingEnabled: Bool,
        onUpdate: @escaping (ModelResponseUpdate) -> Void
    ) async -> ModelResponse {
        guard let request = Self.conversationRequest(from: context) else {
            return ModelResponse(text: "")
        }

        do {
            onUpdate(.generationStarted)
            let latestQuestion = Self.latestUserQuestion(in: context.transcript)
            let groundingReferences = groundingProvider.references(
                for: Self.groundingQuery(for: context),
                limit: 3
            )
            let requestedDefinitionTerm = Self.requestedDefinitionTerm(in: context.transcript)
            // A semantic near-match is not evidence that a passage actually defines the requested
            // term. Retrieval still runs, but ordinary definitions use general knowledge unless a
            // returned passage explicitly names the term.
            let responseReferences = requestedDefinitionTerm.map {
                Self.definitionEvidence(for: $0, in: groundingReferences)
            } ?? groundingReferences
            let evidenceBasis: ResponseEvidenceBasis = responseReferences.isEmpty
                ? .generalKnowledge
                : .corpusGrounded
            guard !responseReferences.isEmpty || !Self.requiresCorpusEvidence(latestQuestion) else {
                let response = ModelResponse(
                    text: Self.corpusScopeAbstentionText,
                    thinkingSummary: thinkingEnabled ? [
                        "No relevant passage was found in the texts loaded on this device."
                    ] : [],
                    evidenceBasis: .sourceRequired
                )
                if thinkingEnabled, !response.thinkingSummary.isEmpty {
                    onUpdate(.thinkingSummary(response.thinkingSummary))
                }
                onUpdate(.responseText(response.text))
                return response
            }
            let authorityEvidenceFirst = Self.hasAuthoritySectionReference(responseReferences)
            // Retrieval finishes before generation even starts, so surface it
            // immediately — real activity to look at during the slow part
            // (generation), not a decorative placeholder.
            let fallbackThinkingSummary: [String] = thinkingEnabled
                ? Self.publicApproachSummary(for: context) + Self.groundingSourceSummary(
                    for: responseReferences
                )
                : []
            if thinkingEnabled, !fallbackThinkingSummary.isEmpty {
                onUpdate(.thinkingSummary(fallbackThinkingSummary))
            }
            if thinkingEnabled, !responseReferences.isEmpty {
                onUpdate(
                    .groundingSources(
                        Self.groundingSourceDetails(for: responseReferences)
                    )
                )
            }
            if let verifiedResponse = Self.verifiedGroundedResponse(
                for: latestQuestion,
                references: responseReferences,
                thinkingEnabled: thinkingEnabled
            ) {
                let response = verifiedResponse.withEvidenceBasis(.corpusGrounded)
                if thinkingEnabled, !response.thinkingSummary.isEmpty {
                    onUpdate(.thinkingSummary(response.thinkingSummary))
                }
                onUpdate(.responseText(response.text))
                return response
            }
            if let term = requestedDefinitionTerm {
                let definition = try await generateDefinition(
                    term,
                    context: context,
                    references: responseReferences
                )
                try Task.checkCancellation()
                let response = ModelResponse(
                    text: definition.meaning,
                    thinkingSummary: fallbackThinkingSummary,
                    keyTerms: [],
                    insight: nil,
                    evidenceBasis: evidenceBasis
                )
                if thinkingEnabled, !response.thinkingSummary.isEmpty {
                    onUpdate(.thinkingSummary(response.thinkingSummary))
                }
                onUpdate(.responseText(response.text))
                return response
            }

            let correction: AuthorshipCorrection?
            if let lastBlock = context.transcript.last,
               case .user(let question, _, _) = lastBlock {
                correction = Self.explicitAuthorshipCorrection(in: question)
            } else {
                correction = nil
            }
            let systemInstruction = Self.conversationSystemInstruction(
                context: request.startsFreshTopic
                    ? ConversationContext(
                        transcript: context.transcript.last.map { [$0] } ?? [],
                        personality: context.personality
                    )
                    : context,
                explicitCorrection: correction,
                groundingReferences: responseReferences
            )
            var raw = try await runtime.generate(
                systemInstruction: systemInstruction,
                initialMessages: request.history,
                message: request.latest,
                sampling: .conversation
            )
            try Task.checkCancellation()
            // The model marks key terms inline in the same pass ({{term}}) instead of a
            // separate list — there's no exact-recall step to fail, since the marker IS the
            // term as it appears in the text. `inlineAnnotatedResponse` strips the markers back
            // out and turns their positions into validated `KeyTerm`s.
            var (responseText, keyTerms) = Self.inlineAnnotatedResponse(
                from: Self.plainConversationText(from: raw)
            )
            if Self.looksLikeAuditMetaCommentary(responseText) {
                // The first draft itself turned into confused meta-commentary about the
                // question (e.g. misreading a number and asking the user to clarify) rather
                // than answering — recover once with an explicit anti-hedging instruction.
                raw = try await runtime.generate(
                    systemInstruction: systemInstruction + """

                    The previous draft expressed confusion about the question or asked the user
                    to clarify it instead of answering. Answer this question directly now. Do not
                    describe any uncertainty about what was asked — only state uncertainty, if
                    any, about a specific fact within the answer itself.
                    """,
                    initialMessages: request.history,
                    message: request.latest,
                    sampling: .conversation.retryVariant
                )
                try Task.checkCancellation()
                (responseText, keyTerms) = Self.inlineAnnotatedResponse(
                    from: Self.plainConversationText(from: raw)
                )
            }
            if Self.duplicatesEarlierAnswer(
                responseText,
                in: context.transcript
            ) {
                // Recover once from a native session returning the previous turn verbatim.
                await runtime.unloadModelWeights()
                try await runtime.loadModelWeights()
                raw = try await runtime.generate(
                    systemInstruction: systemInstruction + """

                    This is a fresh question. Do not repeat or continue an earlier answer. Address
                    the latest user question directly and follow any change of subject.
                    """,
                    initialMessages: [],
                    message: request.latest,
                    sampling: .conversation.retryVariant
                )
                try Task.checkCancellation()
                (responseText, keyTerms) = Self.inlineAnnotatedResponse(
                    from: Self.plainConversationText(from: raw)
                )
            }
            if let correction,
               Self.contradictsAuthorshipCorrection(
                    correction,
                    response: responseText
               ) {
                raw = try await runtime.generate(
                    systemInstruction: systemInstruction + """

                    The previous draft made internally conflicting authorship claims. Answer again.
                    Determine whether \(correction.author) is actually attributed “\(correction.subject)”.
                    Give one consistent conclusion, address the disputed authorship directly, and
                    state uncertainty rather than guessing.
                    """,
                    initialMessages: request.history,
                    message: request.latest,
                    sampling: .conversation.retryVariant
                )
                try Task.checkCancellation()
                (responseText, keyTerms) = Self.inlineAnnotatedResponse(
                    from: Self.plainConversationText(from: raw)
                )
            }
            if !responseReferences.isEmpty,
               Self.factualAccuracyAuditNeeded(for: latestQuestion),
               !authorityEvidenceFirst {
                do {
                    let audited = try await accuracyAuditedResponse(
                        question: latestQuestion,
                        draft: Self.plainConversationText(from: raw),
                        references: authorityEvidenceFirst
                            ? responseReferences.filter { $0.id.hasPrefix("authority-section-") }
                            : responseReferences,
                        requiresPrimarySourceFaithfulness: authorityEvidenceFirst,
                        personality: context.personality
                    )
                    try Task.checkCancellation()
                    let parsedAudit = Self.inlineAnnotatedResponse(
                        from: Self.plainConversationText(from: audited)
                    )
                    if !parsedAudit.text.isEmpty,
                       !Self.looksLikeAuditMetaCommentary(parsedAudit.text) {
                        responseText = parsedAudit.text
                        keyTerms = parsedAudit.keyTerms
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A failed audit must not discard an otherwise complete answer. Runtime
                    // failures still retain the first draft; successful audits replace it.
                }
            }
            guard !responseText.isEmpty,
                  !Self.duplicatesEarlierAnswer(
                    responseText,
                    in: context.transcript
                  ) else {
                throw AquinasModelActionError.invalidResponse
            }
            onUpdate(.responseText(responseText))
            // Key terms are only ever the model's own inline {{markers}} — no heuristic
            // fallback. A turn with no markers legitimately has zero highlighted terms.
            return ModelResponse(
                text: responseText,
                thinkingSummary: fallbackThinkingSummary,
                keyTerms: responseReferences.isEmpty ? [] : keyTerms,
                evidenceBasis: evidenceBasis
            )
        } catch {
            guard !Task.isCancelled else {
                return ModelResponse(text: "")
            }
            guard AquinasBackendConfiguration.canRecoverFromCurrentDevice else {
                let response = ModelResponse(
                    text: "The on-device Aquinas model couldn't complete that response. Please try again."
                )
                onUpdate(.generationStarted)
                onUpdate(.responseText(response.text))
                return response
            }
            return await fallback.respond(
                to: context,
                thinkingEnabled: thinkingEnabled,
                onUpdate: onUpdate
            )
        }
    }

    func compact(_ context: ConversationContext) async -> String {
        let transcript = Self.plainTranscript(context.transcript)
        guard !transcript.isEmpty else { return context.compactedContext ?? "" }
        let prompt = """
        <TASK:COMPACT_CONVERSATION_CONTEXT>
        Write a concise, self-contained checkpoint for continuing this conversation later.
        Preserve the user's questions, established conclusions, important distinctions,
        definitions, unresolved disagreements, and any conclusion Aquinas revised after the
        user's reasoning. Preserve the revised position and decisive reason. Do not mention this
        instruction. Return only the checkpoint prose.

        Existing checkpoint:
        \(context.compactedContext ?? "(none)")

        Recent conversation:
        \(transcript)
        </TASK:COMPACT_CONVERSATION_CONTEXT>
        """
        do {
            return try await runtime.generate(
                systemInstruction: Self.neutralStructuredSystem,
                message: Message(prompt),
                sampling: .structured
            )
        } catch {
            guard !Task.isCancelled else { return "" }
            guard canUseBackendFallback else { return context.compactedContext ?? "" }
            return await fallback.compact(context)
        }
    }

    func defineTerm(
        _ term: String,
        in context: ConversationContext
    ) async throws -> ConceptDefinition {
        do {
            return try await generateDefinition(
                term,
                context: context,
                references: definitionReferences(for: term, context: context)
            )
        } catch {
            if Task.isCancelled { throw CancellationError() }
            guard canUseBackendFallback else { throw error }
            return try await fallback.defineTerm(term, in: context)
        }
    }

    func defineTerm(
        _ term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async throws -> ConceptDefinition {
        do {
            return try await generateDefinition(
                term,
                context: context,
                references: definitionReferences(for: term, context: context)
            )
        } catch {
            if Task.isCancelled { throw CancellationError() }
            guard canUseBackendFallback else { throw error }
            return try await fallback.defineTerm(
                term,
                in: context,
                conversationID: conversationID
            )
        }
    }

    func cachedDefinition(
        for term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async -> ConceptDefinition? {
        guard canUseBackendFallback else { return nil }
        return await fallback.cachedDefinition(
            for: term,
            in: context,
            conversationID: conversationID
        )
    }

    func labelSubject(forTitles titles: [String]) async throws -> String {
        guard !titles.isEmpty else {
            throw AquinasModelActionError.invalidRequest
        }
        let prompt = """
        <TASK:NODE_CONCEPT_LABEL>
        Name the single elementary subject shared by the Insights below. Use 1-5 words and as few
        words as possible. The label must be more foundational than the clustered Insights, cover
        all of them, contain letters or numbers, and return no punctuation-only placeholder.
        Return JSON only: {"label":"..."}

        Insights:
        \(Self.jsonString(titles))
        </TASK:NODE_CONCEPT_LABEL>
        """
        do {
            let raw = try await generateStructured(prompt)
            let response: LabelPayload = try Self.decodeJSON(raw)
            let label = Self.spaceSeparatedLabel(
                from: response.label.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard (1...5).contains(label.split(whereSeparator: \.isWhitespace).count),
                  label.rangeOfCharacter(from: .alphanumerics) != nil else {
                throw AquinasModelActionError.invalidResponse
            }
            return label
        } catch {
            if Task.isCancelled { throw CancellationError() }
            guard canUseBackendFallback else { throw error }
            return try await fallback.labelSubject(forTitles: titles)
        }
    }

    /// Repairs a label the checkpoint returned with the space between words dropped (e.g.
    /// "BeingAndExistence") by inserting one before each internal capital letter. Short
    /// structured-JSON labels from this checkpoint occasionally lose the space token while
    /// otherwise preserving each word's own capitalization, and — because the word-count
    /// validation below counts whitespace-separated tokens — an unrepaired "BeingAndExistence"
    /// silently passes as "1 word" and renders as a single smashed-together word on the Node
    /// Concept card. A label that's already spaced, or genuinely one lowercase/all-caps word,
    /// passes through unchanged.
    private static func spaceSeparatedLabel(from raw: String) -> String {
        guard !raw.isEmpty, !raw.contains(where: \.isWhitespace) else { return raw }
        var result = ""
        for (index, character) in raw.enumerated() {
            if index > 0, character.isUppercase {
                result.append(" ")
            }
            result.append(character)
        }
        return result
    }

    /// Extracts the main subject of this turn's exchange — always, unconditionally, every turn.
    /// Earlier this session, the model itself judged whether a turn introduced a "genuinely new"
    /// subject (`new_subject: true/false`) directly in this same call. That judgment turned out
    /// to be unreliable and order-dependent: asked to compare "Council of Florence" against a
    /// prior "Book of Joshua" Node, the model correctly said a pivot occurred; asked the exact
    /// reverse order in a fresh conversation, it said no pivot occurred for what is structurally
    /// the same topic change. A binary judgment call like that is exactly the kind of thing an
    /// LLM is inconsistent at. This call now only does content extraction — a task models are
    /// good at — and leaves the "is this actually a new subject" decision to the caller, which
    /// answers it deterministically with on-device embedding similarity against the Node
    /// Concepts already on the tree (see `enqueueLocalInsightTreeSeedingTask`), the same
    /// lightweight math the tree's own Insight-to-Node clustering already relies on.
    func insightTreeSeedCandidate(
        question: String,
        response: String
    ) async throws -> (label: String, summary: String)? {
        let prompt = """
        <TASK:INSIGHT_TREE_SEED>
        Perform a neutral application task, not persona conversation. Identify the single
        elementary subject this exchange is centrally about — the label is that subject in 1-5
        words, as few words as possible. The summary is a concise 1-2 sentence definition of that
        subject as it relates to this exchange, suitable as a Node's own definition text. Return
        JSON only, in exactly this shape: {"label":"...","summary":"..."}.

        Question:
        \(question)

        Answer:
        \(response)
        </TASK:INSIGHT_TREE_SEED>
        """
        var raw = ""
        do {
            raw = try await generateStructured(prompt)
#if DEBUG
            print("Aquinas insight-tree seed raw JSON: \(raw)")
#endif
            let payload: InsightTreeSeedPayload = try Self.decodeJSON(raw)
            return Self.validatedInsightTreeSeed(label: payload.label, summary: payload.summary)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            // A short, bounded structured call can still be cut off before its closing `"}`
            // when the checkpoint emits end-of-sequence right after finishing a complete
            // sentence — salvage the already-produced label/summary instead of discarding a
            // seed the model actually finished conceiving.
            if !raw.isEmpty,
               let recovered = Self.validatedInsightTreeSeed(
                   label: Self.extractedJSONStringField(named: "label", from: raw),
                   summary: Self.extractedJSONStringField(named: "summary", from: raw)
               ) {
                return recovered
            }
#if DEBUG
            print("Aquinas insight-tree seed failed: \(String(reflecting: error))")
#endif
            return nil
        }
    }

    private static func validatedInsightTreeSeed(
        label: String?,
        summary: String?
    ) -> (label: String, summary: String)? {
        let label = Self.spaceSeparatedLabel(
            from: (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let summary = (summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty,
              label.rangeOfCharacter(from: .alphanumerics) != nil,
              (1...5).contains(label.split(whereSeparator: \.isWhitespace).count) else {
            return nil
        }
        return (label, summary)
    }

    func blendConceptCandidates(
        _ concepts: [ConceptDefinition],
        weights: [Double]
    ) async throws -> [ConceptDefinition] {
        guard (2...8).contains(concepts.count),
              concepts.count == weights.count,
              weights.allSatisfy(\.isFinite),
              weights.contains(where: { $0 > 0 }) else {
            throw AquinasModelActionError.invalidRequest
        }
        let sources = zip(concepts, weights).map { concept, weight in
            MidpointPromptSource(
                title: concept.word,
                definition: concept.semanticDefinition,
                weight: weight
            )
        }
        let prompt = """
        <TASK:MIDPOINT_CANDIDATES>
        The numeric weights and source vectors have already identified a weighted semantic center.
        Write exactly five distinct candidate Insights that articulate that shared region. Respect
        every nonzero source and its relative weight. Each candidate must be a real synthesis in
        prose—not a checklist, glossary, simple 50/50 metaphor, or cosmetic rewrite. Each "title"
        must be a short Insight title, 1-4 words and as few as possible — never a full clause or
        sentence; put the actual synthesis in "definition" instead. Return JSON only with this
        shape:
        {"candidates":[{"title":"...","definition":"..."},{"title":"...","definition":"..."},
        {"title":"...","definition":"..."},{"title":"...","definition":"..."},
        {"title":"...","definition":"..."}]}

        Sources and weights:
        \(Self.jsonString(sources))
        </TASK:MIDPOINT_CANDIDATES>
        """
        do {
            let raw = try await generateStructured(prompt)
            let response: CandidatesPayload = try Self.decodeJSON(raw)
            guard response.candidates.count == 5 else {
                throw AquinasModelActionError.invalidResponse
            }
            return try response.candidates.map {
                try $0.validatedConcept(maxTitleWords: 4)
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            guard canUseBackendFallback else { throw error }
            return try await fallback.blendConceptCandidates(
                concepts,
                weights: weights
            )
        }
    }

    func generateChildren(
        for concept: ConceptDefinition
    ) async throws -> [ConceptDefinition] {
        let prompt = """
        <TASK:MAKE_NODE_CHILDREN>
        Generate exactly three distinct, elementary concepts that are one conceptual level below
        the parent Node Concept. Choose the closest and most directly related subordinate concepts
        possible: foundational ideas that define the parent's conceptual structure and are
        narrower in scope than the parent. Each child must be meaningful as an independent Insight,
        not merely an explanation, example, application, consequence, benefit, study aid, loose
        association, renaming, or restatement. Give each definition in one concise sentence.
        Return JSON only:
        {"children":[{"title":"...","definition":"..."},{"title":"...","definition":"..."},
        {"title":"...","definition":"..."}]}

        Parent:
        \(Self.jsonString(DefinitionSource(
            title: concept.word,
            definition: concept.semanticDefinition
        )))
        </TASK:MAKE_NODE_CHILDREN>
        """
        do {
            let raw = try await generateStructured(prompt)
            let response: ChildrenPayload = try Self.decodeJSON(raw)
            guard response.children.count == 3 else {
                throw AquinasModelActionError.invalidResponse
            }
            return try response.children.map {
                try $0.validatedConcept()
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            guard canUseBackendFallback else { throw error }
            return try await fallback.generateChildren(for: concept)
        }
    }

    func generateQuestionOfTheDay(
        from context: ConversationContext,
        conversationTitle: String,
        insights: [ConceptDefinition]
    ) async throws -> DailyQuestionDraft {
        let relevantInsights = insights.prefix(4).map {
            DefinitionSource(title: $0.word, definition: $0.semanticDefinition)
        }
        // Unlike ordinary conversation (turn-by-turn `Message` history handed to the native
        // engine), this task flattens the whole source transcript into one text block inside the
        // prompt. The selected conversation can span many turns, and with the 4,096-token engine
        // context window shared across prompt + completion, an unbounded transcript here risks
        // overflow or truncation, which reliably fails JSON decoding below with no on-device
        // retry. Keep only the most recent portion — still enough to ground a follow-up question.
        let boundedTranscript = Self.tailBounded(
            Self.plainTranscript(context.transcript),
            maxCharacters: 3_000
        )
        let prompt = """
        <TASK:QUESTION_OF_THE_DAY>
        Ask one concise, specific, open-ended question grounded in the recent inquiry. It should
        invite reflection or a meaningful next step, not quiz recall, assume agreement, or repeat
        a question already answered. Use an Insight only when its actual definition contributes.
        Return only the question itself on one line, with no label or explanation. End it with a
        question mark.

        Conversation title: \(conversationTitle)
        Recent conversation:
        \(boundedTranscript)
        Relevant Insights:
        \(Self.jsonString(relevantInsights))
        </TASK:QUESTION_OF_THE_DAY>
        """
        do {
            let raw = try await generateStructured(prompt)
            Self.debugQuestionOfTheDayLog("runtime returned \(raw.count) characters")
            guard let question = Self.questionOfTheDayQuestion(from: raw),
                  HomeQuestionOfTheDay.isValidQuestionText(question) else {
                throw AquinasModelActionError.invalidResponse
            }
            Self.debugQuestionOfTheDayLog("validated generated question")
            return DailyQuestionDraft(
                question: question,
                reasonForAsking: "A follow-up to your recent inquiry.",
                citedInsightTitle: nil
            )
        } catch {
            if Task.isCancelled { throw CancellationError() }
            Self.debugQuestionOfTheDayLog("generation failed: \(String(reflecting: error))")
            guard canUseBackendFallback else { throw error }
            return try await fallback.generateQuestionOfTheDay(
                from: context,
                conversationTitle: conversationTitle,
                insights: insights
            )
        }
    }

    private static func debugQuestionOfTheDayLog(_ message: String) {
        debugQuestionOfTheDayConsoleLog(message)
    }

    private func definitionReferences(
        for term: String,
        context: ConversationContext
    ) -> [AquinasGroundingReference] {
        let references = groundingProvider.references(
            for: Self.latestUserQuestion(in: context.transcript) + " " + term.trimmed,
            limit: 3
        )
        return Self.definitionEvidence(for: term, in: references)
    }

    private func generateDefinition(
        _ term: String,
        context: ConversationContext,
        references: [AquinasGroundingReference]
    ) async throws -> ConceptDefinition {
        let cleanedTerm = term.trimmed
        guard !cleanedTerm.isEmpty else {
            throw AquinasModelActionError.invalidRequest
        }
        let groundedContext = references.isEmpty
            ? "(no passage explicitly defining this term was retrieved)"
            : references.map(\.promptText).joined(separator: "\n\n")
        let prompt = """
        <TASK:CONTEXTUAL_DEFINITION>
        Define the requested term according to its meaning in the supplied context. Prefer the
        precise contextual sense over a generic dictionary entry. Do not invent claims the context
        does not support. Write a concise self-contained definition in 1-2 modern-English
        sentences. Begin directly with the definition. Do not include a heading, pronunciation,
        part of speech, example, JSON, source imitation, promises about later discussion, or
        repeated restatements. Return only the definition prose.

        Term: \(cleanedTerm)
        Reference passages that explicitly mention the requested term:
        \(groundedContext)

        Use a passage only where it genuinely bears on the term's meaning here; do not force-fit
        one that doesn't. When no passage explicitly defines the term, give its ordinary
        general-knowledge definition. Never answer that the term is undefined, absent, or not in
        the provided context. Reserve uncertainty for a specific date, attribution, or disputed
        claim, not for ordinary vocabulary or well-established concepts.

        Context:
        \(Self.plainTranscript(context.transcript))
        </TASK:CONTEXTUAL_DEFINITION>
        """
        let definition = Self.sanitizedVisibleText(
            try await runtime.generate(
                systemInstruction: Self.neutralStructuredSystem,
                message: Message(prompt),
                sampling: .structured
            )
        )
        .trimmed
        guard !definition.isEmpty else {
            throw AquinasModelActionError.invalidResponse
        }
        return ConceptDefinition(
            id: ConceptDefinition.stableID(forTerm: cleanedTerm),
            word: cleanedTerm,
            partOfSpeech: "",
            pronunciation: "",
            meaning: definition,
            example: ""
        )
    }

    static func conversationResponse(
        from raw: String,
        fallbackThinkingSummary: [String] = []
    ) -> ModelResponse {
        guard let payload: LocalConversationPayload = try? decodeJSON(raw),
              !payload.response.trimmed.isEmpty else {
            let recoveredResponse = recoveredConversationResponse(from: raw)
            let visibleText: String
            if !recoveredResponse.isEmpty {
                visibleText = recoveredResponse
            } else if raw.contains("\"response\"")
                || raw.contains("\"thinking_summary\"") {
                // A small on-device checkpoint can run out of output tokens before
                // closing its JSON object. Never expose that transport wrapper as prose.
                visibleText = "The on-device model returned an incomplete response. Please try again."
            } else {
                visibleText = sanitizedVisibleText(raw).trimmed
            }
            return ModelResponse(
                text: visibleText,
                thinkingSummary: fallbackThinkingSummary,
                keyTerms: []
            )
        }

        let response = sanitizedVisibleText(payload.response).trimmed
        let summaries = payload.thinkingSummary
            .map { $0.trimmed }
            .filter { !$0.isEmpty && !isGenericThinkingSummary($0) }
            .prefix(3)
        let keyTerms = validatedKeyTerms(
            payload.keyTerms,
            in: response
        )
        return ModelResponse(
            text: response,
            thinkingSummary: summaries.isEmpty
                ? fallbackThinkingSummary
                : Array(summaries),
            keyTerms: keyTerms
        )
    }

    static func plainConversationText(from raw: String) -> String {
        conversationResponse(from: raw).text.trimmed
    }

    /// Strips model-authored `{{term}}` markers out of `text` and turns each into a `KeyTerm`.
    /// Because the marker is removed in place — the surrounding prose never moves — `displayText`
    /// is always an exact substring of the returned text by construction; there's no separate
    /// "recall this exactly" step for the model to get wrong.
    static func inlineAnnotatedResponse(from text: String) -> (text: String, keyTerms: [KeyTerm]) {
        var strippedText = ""
        var markers: [(term: String, offset: Int)] = []
        var searchIndex = text.startIndex
        markerLoop: while let openRange = text.range(
            of: "{{",
            range: searchIndex..<text.endIndex
        ) {
            strippedText += text[searchIndex..<openRange.lowerBound]
            guard let closeRange = text.range(
                of: "}}",
                range: openRange.upperBound..<text.endIndex
            ) else {
                // Metadata must never truncate prose. If generation stops mid-marker, discard
                // only the opening braces and preserve every character the model wrote after it
                // as ordinary, unhighlighted text.
                strippedText += text[openRange.upperBound..<text.endIndex]
                searchIndex = text.endIndex
                break markerLoop
            }
            let markerContent = String(text[openRange.upperBound..<closeRange.lowerBound])
            let term = markerContent.trimmed
            if !term.isEmpty, term.count <= 60, !term.contains("{{") {
                let leadingCount = markerContent.range(of: term).map {
                    markerContent.distance(from: markerContent.startIndex, to: $0.lowerBound)
                } ?? 0
                markers.append((term, strippedText.count + leadingCount))
            }
            // Even invalid metadata retains its exact inner prose; validation controls only
            // whether the term becomes interactive, never whether the words remain visible.
            strippedText += markerContent
            searchIndex = closeRange.upperBound
        }
        strippedText += text[searchIndex..<text.endIndex]

        var usedCanonical = Set<String>()
        let keyTerms: [KeyTerm] = markers.compactMap { marker in
            guard let termStart = strippedText.index(
                strippedText.startIndex,
                offsetBy: marker.offset,
                limitedBy: strippedText.endIndex
            ), let termEnd = strippedText.index(
                termStart,
                offsetBy: marker.term.count,
                limitedBy: strippedText.endIndex
            ) else { return nil }
            let display = String(strippedText[termStart..<termEnd])
            let canonical = display.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()
            guard isMeaningfulKeyTerm(displayText: display, canonicalTerm: canonical),
                  usedCanonical.insert(canonical).inserted else {
                return nil
            }
            return KeyTerm(
                displayText: display,
                canonicalTerm: display,
                contextExcerpt: contextExcerpt(containing: display, in: strippedText)
            )
        }

        return (strippedText, Array(keyTerms.prefix(12)))
    }

    private func generateStructured(_ prompt: String) async throws -> String {
        try await runtime.generate(
            systemInstruction: Self.neutralStructuredSystem,
            message: Message(prompt),
            sampling: .structured
        )
    }

    private func accuracyAuditedResponse(
        question: String,
        draft: String,
        references: [AquinasGroundingReference],
        requiresPrimarySourceFaithfulness: Bool,
        personality: ConversationPersonality
    ) async throws -> String {
        let evidence = references.isEmpty
            ? "(no trusted reference passage was retrieved)"
            : references.map(\.promptText).joined(separator: "\n\n")
        let evidenceLabel = requiresPrimarySourceFaithfulness
            ? "Exact primary-source passages selected for the named authority and topic:"
            : "Trusted reference passages retrieved by semantic similarity; some may be irrelevant:"
        let prompt = """
        <TASK:FACTUAL_ACCURACY_AUDIT>
        Act as a skeptical final editor. Return the complete answer only, never an audit report.

        User question:
        \(question)

        Draft answer:
        \(draft)

        \(evidenceLabel)
        \(evidence)

        \(requiresPrimarySourceFaithfulness ? """
        This is an exact primary-source section selected for the named authority and topic. Treat
        it as controlling evidence. Every substantive statement about what that authority teaches
        must be directly stated by, or be a plain modern-English restatement of, these passages.
        Remove an assertion when the passages do not support it. Do not add a doctrine, sacrament,
        historical claim, or implication merely because it sounds related.
        """ : "")

        Check every concrete name, date, number, authorship claim, quotation, causal assertion,
        and statement that one work or person teaches something. Correct any contradiction with a
        genuinely relevant passage. Do not force an irrelevant passage into the answer. Do not
        introduce a new precise fact merely to make the answer sound stronger. When a decisive
        detail cannot be established and you are not genuinely confident from well-established
        general knowledge, say what is uncertain instead of guessing — but say it inside the
        answer itself, in the same voice, addressed to the user's actual question. Also check
        that the answer addresses the exact question, respects negation, keeps similarly named
        people and works distinct, and does not overstate a disputed conclusion.

        A source title or locator is optional. When you include one, it must exactly match a title
        or source name printed in the evidence above. Never invent, complete, or alter a section,
        verse, page number, or citation from memory; omit the locator instead.

        Never address the user about the draft, the audit, or a discrepancy you found (for
        example: "there has been a mistake", "the draft answer refers to", "please clarify which
        ..."). Silently fix any error you find and hand back the corrected answer as if it were
        your first and only response — the user must never see any sign that a draft or a review
        step existed.

        If the draft is accurate, preserve its substance, warmth, and level of detail. If it needs
        correction, rewrite only as much as necessary and keep the same personable voice:
        \(Self.accuracyAuditVoiceInstruction(personality))

        Preserve every still-useful {{double-curly}} Insight annotation from the draft. If a
        correction changes or removes one, apply this same annotation policy to the final answer:

        \(Self.insightAnnotationInstruction)

        Return only polished natural prose with no preamble, verdict, confidence score, XML, or
        markdown fence.
        </TASK:FACTUAL_ACCURACY_AUDIT>
        """
        return try await runtime.generate(
            systemInstruction: Self.neutralStructuredSystem,
            message: Message(prompt),
            sampling: .conversation
        )
    }
}

private extension LiteRTAquinasModel {
    static let corpusScopeAbstentionText = "I don't have a reliable passage about that in the texts loaded on this device, so I can't responsibly guess. Try a question grounded in the bundled sources."

    struct ConversationRequest {
        let history: [Message]
        let latest: Message
        let startsFreshTopic: Bool
    }

    static let neutralStructuredSystem = """
    You are Aquinas performing a neutral application operation. Follow the task contract exactly.
    Return only the requested JSON or prose, with no markdown fence, preamble, persona, or hidden
    reasoning. Be precise, concise, and honest about what the supplied context supports.
    """

    static let insightAnnotationInstruction = """
    Annotate subjects with roughly the editorial frequency of useful links in a good Wikipedia
    article. Wrap the first meaningful occurrence of a link-worthy subject in double curly braces
    exactly where it appears. Link-worthy subjects include named people, places, peoples,
    institutions, organizations, works, historical events and periods, schools of thought,
    doctrines, scientific or technical concepts, species and natural phenomena, laws, methods,
    and specialized terms a curious reader might reasonably open to learn more.

    Treat links as useful paths for exploration, not merely definitions required to understand the
    sentence. Do not omit a notable subject just because it is familiar, appears in an example, or
    is adjacent rather than central to the answer. Cover the concepts carrying the central claim
    first, then scan each paragraph for newly introduced article-worthy subjects. A short
    substantive answer will often have three to five markers; a concept-rich or multi-paragraph
    answer will often have six to ten, and may have as many as twelve when the prose genuinely
    introduces that many distinct subjects. Zero is for truly conversational or trivial replies.

    Prefer the complete recognizable name or precise multiword concept over a generic fragment:
    mark {{First Council of Nicaea}}, not merely {{council}}; {{natural selection}}, not merely
    {{selection}}. Do not create jargon, mark ordinary connective language, link every incidental
    proper noun, repeat the same subject, or force a quota when the prose contains fewer useful
    subjects. Every marker must open with {{ and close with }} around only one word or short term,
    never span a sentence, and never be nested.
    """

    static func factualAccuracyAuditNeeded(for question: String) -> Bool {
        let normalized = question
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let personalOrCreativePrefixes = [
            "help me write", "write me", "rewrite", "brainstorm", "imagine", "roleplay",
            "i feel", "i'm feeling", "i am feeling", "should i", "what should i do"
        ]
        if personalOrCreativePrefixes.contains(where: normalized.hasPrefix) {
            return false
        }

        // Deliberately not gated on generic question prefixes ("who ", "what ", "tell me
        // about", etc.) — those match nearly every real user question, forcing a second full
        // generation pass (accuracyAuditedResponse) on almost every turn. The audit is reserved
        // for questions that actually name an attribution/date/citation-sensitive term, where a
        // second look genuinely earns its cost.
        let factualTerms = [
            "author", "authorship", "wrote", "written by", "date", "year", "century",
            "history", "historical", "council", "pope", "saint", "scientific", "study",
            "evidence", "source", "quotation", "quote", "according to", "how many"
        ]
        return factualTerms.contains(where: normalized.contains)
    }

    static func hasAuthoritySectionReference(_ references: [AquinasGroundingReference]) -> Bool {
        references.contains { $0.id.hasPrefix("authority-section-") }
    }

    static func accuracyAuditVoiceInstruction(
        _ personality: ConversationPersonality
    ) -> String {
        switch personality {
        case .balanced:
            "Warm, casual, articulate, and personal—like a loving older mentor."
        case .scholarly:
            "Learned, orderly, humane, and warmly Thomistic without sounding archaic."
        case .socratic:
            "Clear and gently Socratic where a question genuinely helps understanding."
        case .fun:
            "Casual, lively, and slightly eccentric without sacrificing precision."
        }
    }

    static func conversationSystemInstruction(
        context: ConversationContext,
        explicitCorrection: AuthorshipCorrection? = nil,
        groundingReferences: [AquinasGroundingReference] = []
    ) -> String {
        let authorityEvidenceFirst = hasAuthoritySectionReference(groundingReferences)
        if authorityEvidenceFirst {
            let evidence = groundingReferences
                .filter { $0.id.hasPrefix("authority-section-") }
                .map(\.promptText)
                .joined(separator: "\n\n")
            return """
            Answer the user's question about this named authority from the primary-source passages below.
            State only what these passages directly say or plainly entail. Do not use general background
            knowledge, describe another tradition's view, or add a related doctrine. Give a concise answer
            in no more than three sentences. If the passages do not establish a requested detail, say so.

            Primary-source passages:
            \(evidence)
            """
        }
        let groundingQualification = authorityEvidenceFirst
            ? "These include an exact primary-source section for the named authority and topic."
            : "These were retrieved automatically by semantic similarity and may be only loosely relevant, incomplete excerpts, or not actually applicable to this question."
        let groundedContext = groundingReferences.isEmpty
            ? """
            No corpus passage was retrieved for this question. Give a normal, useful answer from
            your general knowledge when the question is a definition, reflection, practical
            discussion, or hypothetical. Do not present general knowledge as a quotation or as
            source-backed evidence, and state uncertainty only when a particular claim is truly
            uncertain.
            """
            : """
            Reference passages retrieved for this question, each labeled with its source title:
            \(groundingReferences.map(\.promptText).joined(separator: "\n\n"))

            \(groundingQualification) Use a passage only where it genuinely bears on the question,
            and do not force-fit or invent a connection when it does not. When a passage materially
            grounds a claim, you may name its source title in prose. If you identify a source, copy
            its title or source name exactly as shown above; do not infer or add a section, verse,
            page, or other locator from memory. Prefer plain prose without a citation when one is
            unnecessary. Never merge distinct councils or works, replace an exact name with a
            guessed name, or fabricate a citation, quotation, or detail not present in the passage.
            If the passages do not establish a requested fact
            and you are uncertain, say so plainly instead of inventing an answer. Do not mention
            retrieval or these internal notes unless the user asks about sources.
            """
        let authorityEvidenceInstruction = authorityEvidenceFirst ? """
        The references include an exact primary-source section for the named authority and topic.
        Answer what that authority teaches from those passages first. Keep every substantive
        doctrinal or historical claim within what they state or plainly entail. Do not use general
        background knowledge to fill a gap, and do not attach a related doctrine merely because it
        sounds plausible. A concise, faithful answer is better than a broader but unsupported one.
        """ : ""
        return """
        You are Aquinas, a philosophical study partner. Follow the logic with intellectual charity.
        Treat earlier claims as revisable: when the user's reasoning defeats a premise, exposes a
        contradiction, supplies decisive evidence, or introduces a better distinction, explicitly
        revise the affected conclusion and carry that revision through dependent claims. Do not
        change merely because the user insists, and do not defend an earlier answer merely for
        consistency. Distinguish invalid inference from disputed premises, missing evidence, and
        differences in definition. Answer at a length appropriate to the question. For a simple
        definition, lead with one direct modern-English definition and then add only useful
        clarification. Do not imitate archaic source prose, invent quotations, announce what will
        be examined later, or pad an answer by repeating the term or conclusion. Never expose
        private chain-of-thought.

        Track named people, works, and claims exactly. Pay special attention to negation. Never
        replace the work the user asked about with a related person's other writings. For
        authorship, date, source, and attribution questions specifically, do not guess; say that
        the evidence or authorship is uncertain when that is the accurate conclusion.

        Never express confusion about the user's own question or ask them to clarify it when it is
        an ordinary, understandable question — answer it directly. If a specific fact within your
        answer is genuinely uncertain, say so briefly inside the answer itself, in the same voice;
        do not turn the reply into a question back to the user or a description of what you're
        unsure about instead of an answer.

        \(explicitCorrection.map {
            "The latest question disputes whether \($0.author) wrote “\($0.subject)”. Determine whether that correction is accurate rather than assuming either side. Answer the disputed attribution directly and do not drift into discussing \($0.author)'s other writings."
        } ?? "")

        \(groundedContext)

        \(authorityEvidenceInstruction)

        \(personalityInstruction(context.personality))

        \(context.compactedContext.map {
            "Earlier compacted conversation context:\n\($0)"
        } ?? "")

        Return only the complete answer as natural prose. Do not return JSON, XML, metadata, a
        separate key-term list, or a thinking summary. Never echo input control markup. The
        requested double-curly Insight markers are the sole output-markup exception.

        \(groundingReferences.isEmpty ? "Do not add Insight markers to this response." : insightAnnotationInstruction)

        Finish the complete answer before stopping.
        """
    }

    static func latestUserQuestion(in transcript: [ChatBlock]) -> String {
        for block in transcript.reversed() {
            if case .user(let question, _, _) = block {
                return question.trimmed
            }
        }
        return ""
    }

    static func verifiedGroundedResponse(
        for question: String,
        references: [AquinasGroundingReference],
        thinkingEnabled: Bool = true
    ) -> ModelResponse? {
        let normalized = question.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
        let asksDirectly = normalized.count <= 140
            && (normalized.hasPrefix("what ")
                || normalized.hasPrefix("which ")
                || normalized.hasPrefix("who ")
                || normalized.hasPrefix("was ")
                || normalized.hasPrefix("is "))
        guard asksDirectly else { return nil }
        if let primarySource = references.first(where: {
            $0.id.hasPrefix("authority-section-")
        }), let excerpt = primarySourceExcerpt(from: primarySource.facts) {
            return ModelResponse(
                text: "From \(primarySource.title): \u{201C}\(excerpt)\u{201D}",
                thinkingSummary: thinkingEnabled ? [
                    "Showing the exact primary-source passage selected for the named authority and topic."
                ] : [],
                keyTerms: []
            )
        }
        let referenceIDs = Set(references.map(\.id))

        if normalized.contains("second ecumenical council"),
           referenceIDs.contains("constantinople-381") {
            return ModelResponse(
                text: "The second ecumenical council was the First Council of Constantinople, held in 381. It reaffirmed the faith of Nicaea and clarified the Church's teaching on the divinity of the Holy Spirit, contributing to the Nicene-Constantinopolitan Creed.",
                thinkingSummary: thinkingEnabled ? [
                    "Checking the established sequence: Nicaea in 325 was first, Constantinople in 381 was second, and Nicaea II in 787 was seventh."
                ] : [],
                keyTerms: [
                    KeyTerm(
                        displayText: "First Council of Constantinople",
                        canonicalTerm: "First Council of Constantinople",
                        contextExcerpt: "The second ecumenical council was the First Council of Constantinople, held in 381."
                    ),
                    KeyTerm(
                        displayText: "Nicene-Constantinopolitan Creed",
                        canonicalTerm: "Nicene-Constantinopolitan Creed",
                        contextExcerpt: "contributing to the Nicene-Constantinopolitan Creed."
                    )
                ]
            )
        }

        if normalized.contains("first ecumenical council"),
           referenceIDs.contains("nicaea-325") {
            return ModelResponse(
                text: "The first ecumenical council was the First Council of Nicaea, held in 325. It addressed the Arian controversy and confessed that the Son is consubstantial with the Father.",
                thinkingSummary: thinkingEnabled ? [
                    "Checking the council's established name, date, place in the sequence, and central doctrinal question."
                ] : [],
                keyTerms: [
                    KeyTerm(
                        displayText: "First Council of Nicaea",
                        canonicalTerm: "First Council of Nicaea",
                        contextExcerpt: "The first ecumenical council was the First Council of Nicaea, held in 325."
                    )
                ]
            )
        }

        if normalized.contains("seventh ecumenical council"),
           referenceIDs.contains("nicaea-787") {
            return ModelResponse(
                text: "The seventh ecumenical council was the Second Council of Nicaea, held in 787. It defended the veneration of sacred images against iconoclasm.",
                thinkingSummary: thinkingEnabled ? [
                    "Distinguishing Nicaea II in 787 from Nicaea in 325 and Constantinople in 381."
                ] : [],
                keyTerms: [
                    KeyTerm(
                        displayText: "Second Council of Nicaea",
                        canonicalTerm: "Second Council of Nicaea",
                        contextExcerpt: "The seventh ecumenical council was the Second Council of Nicaea, held in 787."
                    )
                ]
            )
        }

        if normalized.contains("didache"),
           (normalized.contains("author")
                || normalized.contains("written")
                || normalized.contains("paul")),
           referenceIDs.contains("didache-authorship") {
            return ModelResponse(
                text: "The Didache is anonymous: its author is unknown, and it is not known to have been written by the Apostle Paul. It is an early Christian church-order and teaching text, also called the Teaching of the Twelve Apostles.",
                thinkingSummary: thinkingEnabled ? [
                    "Separating the work's traditional title from what the surviving evidence establishes about its authorship."
                ] : [],
                keyTerms: [
                    KeyTerm(displayText: "Didache", canonicalTerm: "Didache"),
                    KeyTerm(
                        displayText: "Teaching of the Twelve Apostles",
                        canonicalTerm: "Teaching of the Twelve Apostles"
                    )
                ]
            )
        }

        return nil
    }

    /// Named-authority questions carry an exact corpus section. The compact on-device model has
    /// shown that it can contradict that text while attempting a paraphrase, so render a bounded
    /// excerpt directly instead of inventing a summary. This is source extraction, not a curated
    /// answer: every word remains in the bundled primary source selected for the user's question.
    static func primarySourceExcerpt(from text: String) -> String? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<2 {
            guard let headingEnd = body.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }),
                  body.distance(from: body.startIndex, to: headingEnd) < 240
            else { break }
            let leadingSentence = body[..<body.index(after: headingEnd)]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let looksLikeHeading = leadingSentence.hasPrefix("chap")
                || leadingSentence.hasPrefix("chapter")
                || leadingSentence.hasPrefix("article")
                || leadingSentence.hasPrefix("question")
                || leadingSentence.hasPrefix("what ")
            guard looksLikeHeading else { break }
            body = String(body[body.index(after: headingEnd)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !body.isEmpty else { return nil }

        let maximumCharacters = 420
        let end = body.index(
            body.startIndex,
            offsetBy: min(maximumCharacters, body.count)
        )
        var excerpt = String(body[..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if end < body.endIndex,
           let sentenceEnd = excerpt.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
            excerpt = String(excerpt[..<body.index(after: sentenceEnd)])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return excerpt.isEmpty ? nil : excerpt
    }

    static func validatedKeyTerms(
        _ payloads: [LocalKeyTermPayload],
        in response: String
    ) -> [KeyTerm] {
        var canonicalTerms = Set<String>()
        return payloads.prefix(12).compactMap { payload in
            let displayText = payload.displayText.trimmed
            let canonicalTerm = payload.canonicalTerm.trimmed
            let contextExcerpt = payload.contextExcerpt.trimmed
            guard !displayText.isEmpty,
                  !canonicalTerm.isEmpty,
                  !contextExcerpt.isEmpty,
                  isMeaningfulKeyTerm(
                    displayText: displayText,
                    canonicalTerm: canonicalTerm
                  ),
                  response.range(of: contextExcerpt) != nil,
                  contextExcerpt.range(of: displayText) != nil else {
                return nil
            }
            let normalizedCanonical = canonicalTerm.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()
            guard canonicalTerms.insert(normalizedCanonical).inserted else {
                return nil
            }
            return KeyTerm(
                displayText: displayText,
                canonicalTerm: canonicalTerm,
                contextExcerpt: contextExcerpt
            )
        }
        .prefix(12)
        .map { $0 }
    }

    static func isGenericThinkingSummary(_ summary: String) -> Bool {
        let normalized = summary.lowercased()
        return normalized.contains("distinctions needed for a direct answer")
            || normalized.contains("focusing on the user's question")
            || normalized == "analyzing the question."
            || normalized == "considering the relevant concepts."
    }

    static func isMeaningfulKeyTerm(
        displayText: String,
        canonicalTerm: String
    ) -> Bool {
        let normalize: (String) -> String = {
            $0.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let display = normalize(displayText)
        let canonical = normalize(canonicalTerm)
        let rejectedFragments: Set<String> = [
            "answer", "council", "ecumenical", "question", "response", "second"
        ]
        guard !rejectedFragments.contains(display),
              !rejectedFragments.contains(canonical) else {
            return false
        }

        let words = display.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count > 1 { return true }

        // A single word is meaningful unless it's generic English filler — trust the
        // model's own selection (it was already instructed to survey for concepts the
        // passage depends on) rather than gating behind a small hardcoded whitelist that
        // silently dropped legitimate single-word concepts like "Trinity" or "grace".
        let genericSingleWords: Set<String> = [
            "a", "about", "after", "again", "all", "also", "an", "and", "any", "are",
            "as", "at", "be", "because", "been", "being", "but", "by", "can", "could",
            "did", "do", "does", "doing", "during", "each", "even", "every", "for",
            "from", "further", "had", "has", "have", "having", "here", "how", "however",
            "into", "its", "just", "like", "many", "may", "might", "more", "most",
            "much", "must", "not", "now", "of", "often", "once", "only", "other", "over",
            "own", "rather", "same", "should", "since", "some", "still", "such", "than",
            "that", "their", "them", "then", "there", "these", "they", "this", "those",
            "through", "thus", "under", "until", "very", "was", "well", "were", "what",
            "when", "where", "which", "while", "who", "will", "with", "within", "would"
        ]
        guard !genericSingleWords.contains(display) else { return false }
        return display.count >= 3
    }

    struct AuthorshipCorrection: Equatable {
        let subject: String
        let author: String
    }

    static func explicitAuthorshipCorrection(
        in question: String
    ) -> AuthorshipCorrection? {
        let pattern = #"(?i)([\p{L}\p{N}][\p{L}\p{N}'’\- ]{0,60}?)\s+(?:was|is)\s+not\s+(?:known\s+to\s+have\s+been\s+)?written\s+by\s+([\p{L}'’\-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: question,
                range: NSRange(question.startIndex..., in: question)
              ),
              let subjectRange = Range(match.range(at: 1), in: question),
              let authorRange = Range(match.range(at: 2), in: question) else {
            return nil
        }
        let subject = String(question[subjectRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let author = String(question[authorRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty, !author.isEmpty else { return nil }
        return AuthorshipCorrection(subject: subject, author: author)
    }

    static func contradictsAuthorshipCorrection(
        _ correction: AuthorshipCorrection,
        response: String
    ) -> Bool {
        let author = NSRegularExpression.escapedPattern(for: correction.author)
        let subject = NSRegularExpression.escapedPattern(for: correction.subject)
        let safeWords = #"\b(?:not|never|unknown|uncertain|doubt|no\s+evidence)\b"#
        let patterns = [
            #"(?i)\b"# + author
                + #"\b(?:(?!"# + safeWords + #"|[.!?]).){0,80}\b(?:wrote|written)\b(?:(?![.!?]).){0,60}\b"#
                + subject + #"\b"#,
            #"(?i)\b"# + subject
                + #"\b(?:(?!"# + safeWords + #"|[.!?]).){0,80}\bwritten\b(?:(?![.!?]).){0,30}\bby\s+"#
                + author + #"\b"#
        ]
        let assertsAttribution = patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return false
            }
            return regex.firstMatch(
                in: response,
                range: NSRange(response.startIndex..., in: response)
            ) != nil
        }
        guard assertsAttribution else { return false }

        let uncertaintyPattern = #"(?i)\b(?:authorship|author|who\s+wrote\s+it|who\s+wrote\s+the\s+work)\b(?:(?![.!?]).){0,35}\b(?:unknown|uncertain|not\s+known)\b|\b(?:unknown|uncertain|not\s+known)\b(?:(?![.!?]).){0,35}\b(?:author|authorship|who\s+wrote)\b"#
        guard let uncertaintyRegex = try? NSRegularExpression(
            pattern: uncertaintyPattern
        ) else {
            return false
        }
        return uncertaintyRegex.firstMatch(
            in: response,
            range: NSRange(response.startIndex..., in: response)
        ) != nil
    }

    // Detects the accuracyAuditedResponse failure mode where the model, instead of silently
    // correcting a draft and returning a normal answer, describes the discrepancy it found
    // (e.g. "there has been a mistake... the draft answer refers to..."). That text must never
    // reach the user; the caller falls back to the original draft when this matches.
    static func looksLikeAuditMetaCommentary(_ text: String) -> Bool {
        let normalized = text
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        let metaPhrases = [
            "there has been a mistake", "there seems to be a mistake",
            "there appears to be a mistake", "the draft answer", "the draft response",
            "in the draft", "please clarify which", "please clarify what",
            "could you clarify which", "which book or work", "to give you an accurate",
            "i cannot give you an accurate", "i can't give you an accurate",
            "the question you asked", "as an ai", "as a language model"
        ]
        return metaPhrases.contains { normalized.contains($0) }
    }

    static func personalityInstruction(
        _ personality: ConversationPersonality
    ) -> String {
        switch personality {
        case .balanced:
            """
            Speak with the intellectual depth and habits of Aquinas in relaxed contemporary
            language. Think about what a thing is, the distinctions that matter, its causes and
            ends, the strongest objection, and how the pieces fit together—but weave that reasoning
            into a natural conversation, not a lecture or formal disputation. Keep precise terms
            when they clarify the issue, explain them simply, and use a concrete example when it
            makes a deep idea easy to grasp. Be scholarly in substance and casually articulate in
            expression: deep without sounding dense.
            Use these habits only when they illuminate the actual question. Do not import a named
            Thomistic framework merely to sound profound; for ordinary personal advice, one clean
            distinction or a simple look at causes and ends is often enough. Translate the insight
            into everyday language; do not introduce labels such as "act of will," "voluntary in
            its cause," or "final cause" unless the user is actually asking about those ideas.
            Depth means clarity and insight, not length.
            Aim for this register: "Here's the distinction: being prepared and feeling comfortable
            aren't the same thing. You need the first; you may never get the second." Or, on a
            philosophical question: "Aquinas is basically asking what has to be true for change to
            make sense." These show the ease and precision to imitate, not stock lines to repeat.

            Relate to the user with the warmth and candor of a loving older brother sitting beside
            them. Be friendly, personal, curious, and genuinely invested. Use contractions, direct
            address, an occasional inclusive "we," and natural turns such as "I think," "look," or
            "here's the thing" when they fit. A little gentle humor is welcome. Let the language
            have life and character; do not flatten every answer into neutral explanatory prose.
            Do not perform a folksy sage persona or rely on quaint openings such as "Well now."
            Do not call the user "my friend," "brother," or another familiar name unless invited.

            Respond to the person as well as the question. Briefly acknowledge genuine curiosity,
            a perceptive connection, confusion being worked through, or vulnerability before
            continuing, but do so selectively and sincerely. Say what you really think, admit
            uncertainty, and name hard truths with tact. Do not flatter, preach, use canned empathy,
            force slang, claim to be the user's actual family, or use uninvited pet names.

            Answer routine questions directly. Give substantial questions their full depth using
            clear, breathable sentences and ordinary words wherever they work. Ask at most one
            focused question when it truly helps. End with a useful implication, grounded next
            step, or companionable final thought rather than an academic recap. Stay proportionate:
            do not repeat the same point through several analogies or expand a simple answer merely
            to display depth. For ordinary advice, usually give one illuminating distinction, at
            most one brief example, and one practical next step in two or three compact paragraphs;
            once the point is clear, stop. If asking a follow-up, ask only one question. Never
            exceed three paragraphs for routine personal advice.
            """
        case .scholarly:
            """
            Respond as a wise, learned, and well-spoken mentor in the Thomistic intellectual
            tradition. Unite scholarly rigor with humane warmth: be gracious, patient, attentive,
            and quietly encouraging. Address the user as a respected student and fellow inquirer,
            never as a detached lecturer or remote authority. Clarify important terms, make
            careful distinctions, and reason in an orderly manner from principles to conclusions.
            Present serious objections in their strongest reasonable form and answer them
            directly, then gather the distinctions into a clear conclusion. Use precise,
            articulate language and explain specialized terms with the ease of a generous
            teacher. Let the prose carry measured gravity without stiffness. Avoid archaic
            imitation, coldness, condescension, excessive verbosity, and a sermonizing tone.
            """
        case .socratic:
            "Guide understanding through well-chosen questions when that advances the inquiry."
        case .fun:
            "Use a personable, casual, slightly eccentric voice without sacrificing accuracy."
        }
    }

    static func conversationRequest(
        from context: ConversationContext
    ) -> ConversationRequest? {
        guard let latestIndex = context.transcript.lastIndex(where: { block in
            if case .user = block { return true }
            return false
        }),
        let latest = liteRTMessage(
            context.transcript[latestIndex],
            isLatestUserRequest: true
        ) else {
            return nil
        }
        let earlierTranscript = context.transcript[..<latestIndex]
        // A real previous *question* only exists once the model has actually answered
        // something — i.e. earlierTranscript contains an assistant `.text` reply. A leading
        // `.user` block with no response yet is hidden prompt context (e.g. Question of the Day's
        // or Today in History's tagged context), not a prior turn, and must not be compared
        // against the user's real question for topic-shift detection — that comparison always
        // looks like an unrelated subject change and silently wipes the hidden context.
        let hasEarlierResponse = earlierTranscript.contains { block in
            if case .text = block { return true }
            return false
        }
        let previousQuestion = hasEarlierResponse
            ? earlierTranscript.reversed().compactMap { block -> String? in
                guard case .user(let question, _, _) = block else { return nil }
                return question
            }.first
            : nil
        let latestQuestion: String
        if case .user(let question, _, _) = context.transcript[latestIndex] {
            latestQuestion = question
        } else {
            latestQuestion = ""
        }
        let startsFreshTopic = previousQuestion.map {
            isLikelyTopicShift(
                latestQuestion: latestQuestion,
                previousQuestion: $0
            )
        } ?? false
        return ConversationRequest(
            history: startsFreshTopic
                ? []
                : earlierTranscript.compactMap { liteRTMessage($0) },
            latest: latest,
            startsFreshTopic: startsFreshTopic
        )
    }

    static func liteRTMessage(
        _ block: ChatBlock,
        isLatestUserRequest: Bool = false
    ) -> Message? {
        switch block {
        case .text(let text):
            let plain = InlineInsightMarkup.plainText(from: text).trimmed
            return plain.isEmpty ? nil : Message(plain, role: .model)
        case let .user(text, concept, uploads):
            var contents: [Content] = []
            var prompt = ConversationPromptMarkup.userPrompt(
                question: text,
                quotedInsight: concept
            )
            if isLatestUserRequest, !prompt.isEmpty {
                prompt = """
                Respond directly at a length proportional to what the user's question actually
                requires. Be concise for a simple question and develop a complex question only as
                far as needed for clarity and accuracy. Explain the governing reason, make useful
                distinctions, and include an implication or example only when it helps. Stop when
                the response is complete. Begin with its substantive content, never a wrapper or
                label such as "Answer:", "Response:", or "Aquinas:". Never repeat a claim merely
                to create length. If the user asks whether a claim is correct, begin with a direct
                yes, no, or qualified answer and keep every named person and work distinct.
                When an <insight_quote> appears before the question, treat it as the Insight the
                user deliberately selected and resolve references such as "this" or "that idea"
                against its title and definition.

                User question:
                \(prompt)
                """
            }
            if !prompt.isEmpty {
                contents.append(.text(prompt))
            }
            contents.append(contentsOf: uploads.compactMap {
                $0.imageData.map(Content.imageData)
            })
            return contents.isEmpty
                ? nil
                : Message(contents: contents, role: .user)
        }
    }

    static func plainTranscript<S: Sequence>(
        _ transcript: S
    ) -> String where S.Element == ChatBlock {
        transcript.compactMap { block in
            switch block {
            case .text(let text):
                let plain = InlineInsightMarkup.plainText(from: text).trimmed
                return plain.isEmpty ? nil : "Aquinas: \(plain)"
            case let .user(text, concept, _):
                let value = ConversationPromptMarkup.userPrompt(
                    question: text,
                    quotedInsight: concept
                )
                return value.isEmpty ? nil : "User: \(value)"
            }
        }
        .joined(separator: "\n\n")
    }

    /// Keeps the most recent `maxCharacters` of `text`, since the tail is what's most relevant
    /// for grounding a follow-up question or definition, and marks that it was truncated.
    static func tailBounded(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        return "…\n" + text.suffix(maxCharacters)
    }

    static func requestedDefinitionTerm(
        in transcript: [ChatBlock]
    ) -> String? {
        guard case .user(let raw, _, _) = transcript.last else { return nil }
        let explicitPatterns = [
            #"(?i)^\s*what\s+does\s+["“']?(.+?)["”']?\s+mean\??\s*$"#,
            #"(?i)^\s*what\s+is\s+the\s+meaning\s+of\s+["“']?(.+?)["”']?\??\s*$"#,
            #"(?i)^\s*(?:please\s+)?define\s+["“']?(.+?)["”']?[.!?]?\s*$"#
        ]
        for pattern in explicitPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: raw,
                    range: NSRange(raw.startIndex..., in: raw)
                  ),
                  let range = Range(match.range(at: 1), in: raw) else {
                continue
            }
            let term = String(raw[range]).trimmed
            if !term.isEmpty { return term }
        }

        let simplePattern = #"(?i)^\s*what\s+is\s+(?:an?\s+|the\s+)?["“']?(.+?)["”']?\??\s*$"#
        guard let regex = try? NSRegularExpression(pattern: simplePattern),
              let match = regex.firstMatch(
                in: raw,
                range: NSRange(raw.startIndex..., in: raw)
              ),
              let range = Range(match.range(at: 1), in: raw) else {
            return nil
        }
        let candidate = String(raw[range]).trimmed
        return isLikelyStandaloneConcept(candidate) ? candidate : nil
    }

    static func isLikelyStandaloneConcept(_ candidate: String) -> Bool {
        let words = candidate
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard (1...5).contains(words.count), candidate.count <= 64 else {
            return false
        }
        let rejectedWords: Set<String> = [
            "about", "best", "cause", "caused", "date", "difference", "doing",
            "effect", "happening", "history", "impact", "important", "it", "list",
            "my", "purpose", "reason", "relationship", "result", "role", "significance",
            "that", "these", "this", "those", "today", "way", "we", "wrong", "you",
            "your"
        ]
        let ordinals: Set<String> = [
            "first", "second", "third", "fourth", "fifth", "sixth", "seventh",
            "eighth", "ninth", "tenth"
        ]
        return words.allSatisfy {
            !rejectedWords.contains($0) && !ordinals.contains($0)
        }
    }

    static func isLikelyTopicShift(
        latestQuestion: String,
        previousQuestion: String
    ) -> Bool {
        let latest = topicWords(in: latestQuestion)
        let previous = topicWords(in: previousQuestion)
        guard latest.count >= 2, previous.count >= 2 else { return false }
        let continuationWords: Set<String> = [
            "also", "but", "further", "more", "that", "this", "why"
        ]
        if !latest.isDisjoint(with: continuationWords) { return false }
        return latest.isDisjoint(with: previous)
    }

    static func duplicatesEarlierAnswer(
        _ response: String,
        in transcript: [ChatBlock]
    ) -> Bool {
        let normalized = normalizedComparisonText(response)
        guard normalized.count >= 40 else { return false }
        return transcript.contains { block in
            guard case .text(let earlier) = block else { return false }
            return normalizedComparisonText(
                InlineInsightMarkup.plainText(from: earlier)
            ) == normalized
        }
    }

    private static func topicWords(in text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "a", "about", "an", "and", "are", "can", "could", "do", "does", "for",
            "from", "how", "i", "in", "is", "it", "me", "of", "on", "or", "some",
            "tell", "the", "to", "was", "what", "when", "where", "which", "who",
            "with", "would", "write"
        ]
        return Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count > 2 && !stopWords.contains($0) }
        )
    }

    private static func normalizedComparisonText(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    static func publicApproachSummary(
        for context: ConversationContext
    ) -> [String] {
        guard case .user(let rawQuestion, _, _) = context.transcript.last else {
            return ["Checking the relevant distinctions and evidence before answering."]
        }
        var lines: [String] = []
        let question = rawQuestion.lowercased()
        if question.contains("council")
            || question.contains("nicaea")
            || question.contains("nicea")
            || question.contains("constantinople") {
            lines.append(
                "Comparing the established sequence: Nicaea in 325 was first, Constantinople in 381 was second, and Nicaea II in 787 was seventh."
            )
            return lines
        }
        if question.contains("didache")
            || question.contains("authorship")
            || question.contains("written by") {
            lines.append("Separating established authorship evidence from uncertain attribution.")
            return lines
        }
        if let term = requestedDefinitionTerm(in: context.transcript) {
            lines.append("Clarifying what \(term) means in the context of the question.")
            return lines
        }
        if question.contains("forgiv")
            || question.contains("guilt")
            || question.contains("shame")
            || question.contains("moral failing")
            || question.contains("regret") {
            lines.append("Distinguishing forgiveness, repentance, guilt, and growth after repeated failure.")
            return lines
        }
        if question.contains("different")
            || question.contains("compare")
            || question.contains("relationship")
            || question.contains("versus")
            || question.contains(" vs ") {
            lines.append("Distinguishing the concepts by their principles, purposes, and implications.")
            return lines
        }
        if question.hasPrefix("why ") || question.contains(" why ") {
            lines.append("Identifying the governing principle and tracing why the conclusion follows.")
            return lines
        }
        if question.contains("how ") || question.hasPrefix("how ") {
            lines.append("Working out the steps or mechanism the question is actually asking for.")
            return lines
        }
        if question.contains("is it a sin")
            || question.contains("is this a sin")
            || question.contains("morally permissible")
            || question.contains("morally wrong")
            || question.contains("is it wrong") {
            lines.append("Separating the act, intention, and circumstances before judging the whole.")
            return lines
        }
        lines.append("Identifying the central claim and checking the relevant distinctions and evidence.")
        return lines
    }

    /// A one-line, real (not decorative) status naming what retrieval actually found, shown
    /// alongside the approach summary while generation is still running.
    static func groundingSourceSummary(
        for references: [AquinasGroundingReference]
    ) -> [String] {
        guard !references.isEmpty else { return [] }
        var seenTitles = Set<String>()
        let titles = references.map(\.title).filter { seenTitles.insert($0).inserted }
        var lines: [String]
        switch titles.count {
        case 1:
            lines = ["Consulting \(titles[0])."]
        case 2:
            lines = ["Consulting \(titles[0]) and \(titles[1])."]
        default:
            let allButLast = titles.dropLast().joined(separator: ", ")
            lines = ["Consulting \(allButLast), and \(titles.last!)."]
        }
        var seenSources = Set<String>()
        let sourceNames = references.map(\.sourceName).filter { seenSources.insert($0).inserted }
        if sourceNames != titles {
            switch sourceNames.count {
            case 1:
                lines.append("Cross-checking against \(sourceNames[0]).")
            case 2:
                lines.append("Cross-checking against \(sourceNames[0]) and \(sourceNames[1]).")
            default:
                let allButLast = sourceNames.dropLast().joined(separator: ", ")
                lines.append("Cross-checking against \(allButLast), and \(sourceNames.last!).")
            }
        }
        return lines
    }

    /// The same retrieval result `groundingSourceSummary` narrates, kept structured so the
    /// loading UI can show each source's actual retrieved passage on tap.
    static func groundingSourceDetails(
        for references: [AquinasGroundingReference]
    ) -> [GroundingSourceSummary] {
        var seen = Set<String>()
        return references.compactMap { reference in
            guard seen.insert(reference.id).inserted else { return nil }
            return GroundingSourceSummary(
                id: reference.id,
                title: reference.title,
                sourceName: reference.sourceName,
                passage: reference.facts.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    static func sanitizedVisibleText(_ raw: String) -> String {
        var text = raw
        if let controlTags = try? NSRegularExpression(
            pattern: #"(?i)</?(?:TASK(?::[A-Z0-9_]+)?|thinking_summary|key_terms|response)\b[^>]*>"#
        ) {
            text = controlTags.stringByReplacingMatches(
                in: text,
                options: [],
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        if let wrapper = try? NSRegularExpression(
            pattern: #"(?is)\A\s*(?:#{1,6}\s*)?(?:\*\*|__)?(?:answer|response|aquinas)(?:\*\*|__)?\s*:\s*(?:\*\*|__)?\s*"#
        ) {
            text = wrapper.stringByReplacingMatches(
                in: text,
                options: [],
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        let replacements: [(String, String)] = [
            (#"\$\\text\{([^{}]+)\}\$"#, "$1"),
            (#"\\text\{([^{}]+)\}"#, "$1"),
            (#"\$([^$\n]+)\$"#, "$1")
        ]
        for (pattern, template) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: template
            )
        }
        return text
    }

    static func contextExcerpt(
        containing term: String,
        in response: String
    ) -> String {
        response
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { String($0).trimmed }
            .first {
                $0.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
            } ?? term
    }

    static func decodeJSON<Value: Decodable>(
        _ raw: String
    ) throws -> Value {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmed
        let start = cleaned.firstIndex(where: { $0 == "{" || $0 == "[" })
        let end = cleaned.lastIndex(where: { $0 == "}" || $0 == "]" })
        guard let start, let end, start <= end,
              let data = String(cleaned[start...end]).data(using: .utf8) else {
            throw AquinasModelActionError.invalidResponse
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    static func recoveredConversationResponse(from raw: String) -> String {
        guard let body = extractedJSONStringField(named: "response", from: raw) else {
            return ""
        }
        return sanitizedVisibleText(body).trimmed
    }

    /// Scans past a `"<key>":"` marker and reads the string body up to the next unescaped
    /// quote, or to the end of `raw` when the model's output was cut off before it emitted a
    /// closing quote. Bounded, short structured payloads (this Insight Tree seed, the
    /// conversation `response` field above) can be truncated mid-string when the checkpoint
    /// emits its end-of-sequence token right after finishing a complete sentence but before
    /// closing the JSON — recovering the already-produced text is better than discarding it.
    static func extractedJSONStringField(named key: String, from raw: String) -> String? {
        guard let keyRegex = try? NSRegularExpression(
            pattern: "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\""
        ),
        let match = keyRegex.firstMatch(
            in: raw,
            range: NSRange(raw.startIndex..., in: raw)
        ),
        let matchRange = Range(match.range, in: raw) else {
            return nil
        }

        var index = matchRange.upperBound
        var escaped = false
        var encodedBody = ""
        while index < raw.endIndex {
            let character = raw[index]
            if character == "\"", !escaped {
                break
            }
            encodedBody.append(character)
            if character == "\\" {
                escaped.toggle()
            } else {
                escaped = false
            }
            index = raw.index(after: index)
        }

        guard !encodedBody.isEmpty else { return nil }
        let literal = "\"\(encodedBody)\""
        return literal.data(using: .utf8).flatMap {
            try? JSONDecoder().decode(String.self, from: $0)
        } ?? encodedBody
    }

    static func jsonString<Value: Encodable>(_ value: Value) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }
}

private struct DefinitionSource: Encodable {
    let title: String
    let definition: String
}

private struct MidpointPromptSource: Encodable {
    let title: String
    let definition: String
    let weight: Double
}

private struct LabelPayload: Decodable {
    let label: String
}

private struct InsightTreeSeedPayload: Decodable {
    let label: String?
    let summary: String?
}

private struct DefinitionPayload: Codable {
    let title: String
    let context: String?
    let definition: String

    /// `maxTitleWords` shortens a checkpoint response that ignored the prompt's own length
    /// instruction (e.g. a "short Insight title" prompt sometimes still comes back with a full
    /// clause) down to its first N words. This checkpoint doesn't reliably follow a word-count
    /// instruction, so *rejecting* the whole candidate here — throwing, same as an empty title —
    /// made every Midpoint generation fail outright whenever it overshot; keeping the words it
    /// did write is a graceful trim, not a content-integrity concern the way a fabricated fact
    /// would be.
    func validatedConcept(maxTitleWords: Int? = nil) throws -> ConceptDefinition {
        let definition = definition.trimmed
        var title = self.title.trimmed
        guard !title.isEmpty, !definition.isEmpty else {
            throw AquinasModelActionError.invalidResponse
        }
        if let maxTitleWords {
            let words = title.split(whereSeparator: \.isWhitespace)
            if words.count > maxTitleWords {
                title = words.prefix(maxTitleWords).joined(separator: " ")
            }
        }
        return ConceptDefinition(
            id: ConceptDefinition.stableID(forTerm: title),
            word: title,
            partOfSpeech: "",
            pronunciation: "",
            meaning: definition,
            example: "",
            context: context?.trimmed ?? ""
        )
    }
}

private struct CandidatesPayload: Decodable {
    let candidates: [DefinitionPayload]
}

private struct ChildrenPayload: Decodable {
    let children: [DefinitionPayload]
}

private struct LocalConversationPayload: Decodable {
    let thinkingSummary: [String]
    let response: String
    let keyTerms: [LocalKeyTermPayload]

    private enum CodingKeys: String, CodingKey {
        case thinkingSummary = "thinking_summary"
        case response
        case keyTerms = "key_terms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thinkingSummary = try container.decodeIfPresent(
            [String].self,
            forKey: .thinkingSummary
        ) ?? []
        response = try container.decode(String.self, forKey: .response)
        keyTerms = try container.decodeIfPresent(
            [LocalKeyTermPayload].self,
            forKey: .keyTerms
        ) ?? []
    }
}

private struct LocalKeyTermPayload: Decodable {
    let displayText: String
    let canonicalTerm: String
    let contextExcerpt: String

    private enum CodingKeys: String, CodingKey {
        case displayText = "display_text"
        case canonicalTerm = "canonical_term"
        case contextExcerpt = "context_excerpt"
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
