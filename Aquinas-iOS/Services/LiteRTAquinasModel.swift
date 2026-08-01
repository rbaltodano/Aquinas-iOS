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
    private let runtime: LiteRTAquinasRuntime
    private let fallback: BackendAquinasModel

    init(
        runtime: LiteRTAquinasRuntime,
        fallback: BackendAquinasModel = BackendAquinasModel()
    ) {
        self.runtime = runtime
        self.fallback = fallback
    }

    static func definitionRequestTerm(
        in transcript: [ChatBlock]
    ) -> String? {
        requestedDefinitionTerm(in: transcript)
    }

    static func visibleResponseText(
        from raw: String
    ) -> String {
        sanitizedVisibleText(raw)
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
            let liveThinkingSummary = thinkingEnabled
                ? Self.publicApproachSummary(for: context)
                : []
            onUpdate(.generationStarted)
            if !liveThinkingSummary.isEmpty {
                onUpdate(.thinkingSummary(liveThinkingSummary))
            }
            if let term = Self.requestedDefinitionTerm(
                in: context.transcript
            ) {
                let definition = try await generateDefinition(
                    term,
                    context: context
                )
                try Task.checkCancellation()
                let response = ModelResponse(
                    text: definition.meaning,
                    thinkingSummary: liveThinkingSummary,
                    keyTerms: [KeyTerm(displayText: definition.word)],
                    insight: definition
                )
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
                context: context,
                explicitCorrection: correction
            )
            var text = try await runtime.generate(
                systemInstruction: systemInstruction,
                initialMessages: request.history,
                message: request.latest,
                sampling: .conversation
            )
            try Task.checkCancellation()
            var visibleText = Self.sanitizedVisibleText(text)
            if let correction,
               Self.contradictsAuthorshipCorrection(
                    correction,
                    response: visibleText
               ) {
                text = try await runtime.generate(
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
                visibleText = Self.sanitizedVisibleText(text)
            }

            let analysis = Self.analyzeResponse(
                visibleText,
                thinkingSummary: liveThinkingSummary
            )
            let response = ModelResponse(
                text: visibleText,
                thinkingSummary: analysis.thinkingSummary,
                keyTerms: analysis.keyTerms,
                insight: nil
            )
            if thinkingEnabled, !response.thinkingSummary.isEmpty {
                onUpdate(.thinkingSummary(response.thinkingSummary))
            }
            onUpdate(.responseText(response.text))
            return response
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
            return await fallback.compact(context)
        }
    }

    func defineTerm(
        _ term: String,
        in context: ConversationContext
    ) async throws -> ConceptDefinition {
        do {
            return try await generateDefinition(term, context: context)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            return try await fallback.defineTerm(term, in: context)
        }
    }

    func defineTerm(
        _ term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async throws -> ConceptDefinition {
        do {
            return try await generateDefinition(term, context: context)
        } catch {
            if Task.isCancelled { throw CancellationError() }
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
        await fallback.cachedDefinition(
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
            let label = response.label.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard (1...5).contains(label.split(whereSeparator: \.isWhitespace).count),
                  label.rangeOfCharacter(from: .alphanumerics) != nil else {
                throw AquinasModelActionError.invalidResponse
            }
            return label
        } catch {
            if Task.isCancelled { throw CancellationError() }
            return try await fallback.labelSubject(forTitles: titles)
        }
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
        prose—not a checklist, glossary, simple 50/50 metaphor, or cosmetic rewrite. Return JSON
        only with this shape:
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
                try $0.validatedConcept()
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
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
        Generate exactly three child Insights that help a learner understand the parent Node
        Concept. Each child must be distinct, accurate, intellectually useful, and subordinate to
        the parent rather than a renaming or restatement. Return JSON only:
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
        let prompt = """
        <TASK:QUESTION_OF_THE_DAY>
        Ask one concise, specific, open-ended question grounded in the recent inquiry. It should
        invite reflection or a meaningful next step, not quiz recall, assume agreement, or repeat
        a question already answered. Use an Insight only when its actual definition contributes.
        Return JSON only:
        {"question":"...","reason_for_asking":"...","cited_insight_title":null}

        Conversation title: \(conversationTitle)
        Recent conversation:
        \(Self.plainTranscript(context.transcript))
        Relevant Insights:
        \(Self.jsonString(relevantInsights))
        </TASK:QUESTION_OF_THE_DAY>
        """
        do {
            let raw = try await generateStructured(prompt)
            let response: DailyQuestionPayload = try Self.decodeJSON(raw)
            guard !response.question.trimmed.isEmpty,
                  !response.reasonForAsking.trimmed.isEmpty else {
                throw AquinasModelActionError.invalidResponse
            }
            return DailyQuestionDraft(
                question: response.question.trimmed,
                reasonForAsking: response.reasonForAsking.trimmed,
                citedInsightTitle: response.citedInsightTitle?.trimmed.nilIfEmpty
            )
        } catch {
            if Task.isCancelled { throw CancellationError() }
            return try await fallback.generateQuestionOfTheDay(
                from: context,
                conversationTitle: conversationTitle,
                insights: insights
            )
        }
    }

    private func generateDefinition(
        _ term: String,
        context: ConversationContext
    ) async throws -> ConceptDefinition {
        let cleanedTerm = term.trimmed
        guard !cleanedTerm.isEmpty else {
            throw AquinasModelActionError.invalidRequest
        }
        let prompt = """
        <TASK:CONTEXTUAL_DEFINITION>
        Define the requested term according to its meaning in the supplied context. Prefer the
        precise contextual sense over a generic dictionary entry. Do not invent claims the context
        does not support. Write a concise self-contained definition in 1-2 modern-English
        sentences. Begin directly with the definition. Do not include a heading, pronunciation,
        part of speech, example, JSON, source imitation, promises about later discussion, or
        repeated restatements. Return only the definition prose.

        Term: \(cleanedTerm)
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
            example: "",
            context: "The term as used in the current conversation"
        )
    }

    private static func analyzeResponse(
        _ response: String,
        thinkingSummary: [String]
    ) -> LocalPresentationAnalysis {
        LocalPresentationAnalysis(
            thinkingSummary: thinkingSummary,
            keyTerms: foundationalKeyTerms(in: response)
        )
    }

    private func generateStructured(_ prompt: String) async throws -> String {
        try await runtime.generate(
            systemInstruction: Self.neutralStructuredSystem,
            message: Message(prompt),
            sampling: .structured
        )
    }
}

private extension LiteRTAquinasModel {
    struct ConversationRequest {
        let history: [Message]
        let latest: Message
    }

    static let neutralStructuredSystem = """
    You are Aquinas performing a neutral application operation. Follow the task contract exactly.
    Return only the requested JSON or prose, with no markdown fence, preamble, persona, or hidden
    reasoning. Be precise, concise, and honest about what the supplied context supports.
    """

    static func conversationSystemInstruction(
        context: ConversationContext,
        explicitCorrection: AuthorshipCorrection? = nil
    ) -> String {
        """
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
        authorship, date, source, and attribution questions, do not guess; say that the evidence
        or authorship is uncertain when that is the accurate conclusion.

        \(explicitCorrection.map {
            "The latest question disputes whether \($0.author) wrote “\($0.subject)”. Determine whether that correction is accurate rather than assuming either side. Answer the disputed attribution directly and do not drift into discussing \($0.author)'s other writings."
        } ?? "")

        \(personalityInstruction(context.personality))

        \(context.compactedContext.map {
            "Earlier compacted conversation context:\n\($0)"
        } ?? "")
        """
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

    static func personalityInstruction(
        _ personality: ConversationPersonality
    ) -> String {
        switch personality {
        case .balanced:
            "Use a warm, clear, neutral conversational voice."
        case .scholarly:
            "Use a formal, rigorous voice and make careful distinctions."
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
        return ConversationRequest(
            history: context.transcript[..<latestIndex].compactMap {
                liteRTMessage($0)
            },
            latest: latest
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
            var prompt = text.trimmed
            if let concept {
                prompt = """
                \(prompt)

                <quoted_insight title="\(concept.word)">
                \(concept.semanticDefinition)
                </quoted_insight>
                """
            }
            if isLatestUserRequest, !prompt.isEmpty {
                prompt = """
                <TASK:ANSWER_USER>
                Respond directly at a length proportional to what the user's question actually
                requires. Be concise for a simple question and develop a complex question only as
                far as needed for clarity and accuracy. Explain the governing reason, make useful
                distinctions, and include an implication or example only when it helps. Stop when
                the response is complete. Begin with its substantive content, never a wrapper or
                label such as "Answer:", "Response:", or "Aquinas:". Never repeat a claim merely
                to create length. If the user asks whether a claim is correct, begin with a direct
                yes, no, or qualified answer and keep every named person and work distinct.

                User question:
                \(prompt)
                </TASK:ANSWER_USER>
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
                var value = text.trimmed
                if let concept {
                    value += "\nQuoted Insight — \(concept.word): \(concept.semanticDefinition)"
                }
                return value.isEmpty ? nil : "User: \(value)"
            }
        }
        .joined(separator: "\n\n")
    }

    static func requestedDefinitionTerm(
        in transcript: [ChatBlock]
    ) -> String? {
        guard case .user(let raw, _, _) = transcript.last else { return nil }
        let patterns = [
            #"(?i)^\s*what\s+does\s+["“']?(.+?)["”']?\s+mean\??\s*$"#,
            #"(?i)^\s*what\s+is\s+the\s+meaning\s+of\s+["“']?(.+?)["”']?\??\s*$"#,
            #"(?i)^\s*what\s+is\s+(?:an?\s+|the\s+)?["“']?(.+?)["”']?\??\s*$"#,
            #"(?i)^\s*(?:please\s+)?define\s+["“']?(.+?)["”']?[.!?]?\s*$"#
        ]
        for pattern in patterns {
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
        return nil
    }

    static func publicApproachSummary(
        for context: ConversationContext
    ) -> [String] {
        guard case .user(let rawQuestion, _, _) = context.transcript.last else {
            return ["Identifying the central issue and the distinctions needed for a direct answer."]
        }
        let question = rawQuestion.lowercased()
        if let term = requestedDefinitionTerm(in: context.transcript) {
            return ["Clarifying what \(term) means in the context of the question."]
        }
        if question.contains("forgiv")
            || question.contains("guilt")
            || question.contains("shame")
            || question.contains("moral failing")
            || question.contains("regret") {
            return ["Distinguishing forgiveness, repentance, guilt, and growth after repeated failure."]
        }
        if question.contains("different")
            || question.contains("compare")
            || question.contains("relationship")
            || question.contains("versus")
            || question.contains(" vs ") {
            return ["Distinguishing the concepts by their principles, purposes, and implications."]
        }
        if question.hasPrefix("why ") || question.contains(" why ") {
            return ["Identifying the governing principle and tracing why the conclusion follows."]
        }
        if question.contains("is it a sin")
            || question.contains("is this a sin")
            || question.contains("morally permissible")
            || question.contains("morally wrong")
            || question.contains("is it wrong") {
            return ["Separating the act, intention, and circumstances before judging the whole."]
        }
        let focus = conciseQuestionFocus(rawQuestion)
        guard !focus.isEmpty else {
            return ["Identifying the central issue and the distinctions needed for a direct answer."]
        }
        return ["Focusing on “\(focus)” and the distinctions needed for a direct answer."]
    }

    private static func conciseQuestionFocus(_ rawQuestion: String) -> String {
        let normalized = rawQuestion
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 72 else { return normalized }

        let end = normalized.index(normalized.startIndex, offsetBy: 69)
        let prefix = normalized[..<end]
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]) + "…"
        }
        return String(prefix) + "…"
    }

    static func foundationalKeyTerms(in response: String) -> [KeyTerm] {
        let preferredPhrases = [
            "practical wisdom", "practical reason", "moral virtue", "intellectual virtue",
            "natural law", "first principle", "first principles", "common good",
            "human flourishing", "final cause", "efficient cause", "formal cause",
            "material cause", "act and potency", "double effect", "moral object",
            "free will", "conscience", "substantial form"
        ]
        var selected: [(display: String, canonical: String, location: Int, score: Int)] = []
        var usedCanonical = Set<String>()

        for phrase in preferredPhrases {
            guard let range = response.range(
                of: phrase,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) else {
                continue
            }
            let display = String(response[range])
            let canonical = phrase.lowercased()
            if usedCanonical.insert(canonical).inserted {
                selected.append((
                    display,
                    canonical,
                    response.distance(from: response.startIndex, to: range.lowerBound),
                    100
                ))
            }
        }

        let stopWords: Set<String> = [
            "about", "after", "again", "against", "along", "also", "among", "another",
            "because", "before", "being", "between", "could", "directly", "enough",
            "every", "first", "further", "having", "helps", "however", "human",
            "includes", "instead", "itself", "means", "might", "often", "other",
            "rather", "really", "should", "since", "something", "still", "their",
            "therefore", "these", "thing", "think", "those", "through", "under",
            "useful", "using", "which", "while", "without", "would"
        ]
        let philosophicalTerms: Set<String> = [
            "analogy", "causality", "conscience", "essence", "existence", "flourishing",
            "intellect", "justice", "metaphysics", "morality", "ontology", "participation",
            "potentiality", "prudence", "reason", "teleology", "temperance", "virtue",
            "wisdom"
        ]
        let regex = try? NSRegularExpression(
            pattern: #"\b[\p{L}][\p{L}'’\-]{4,}\b"#
        )
        let fullRange = NSRange(response.startIndex..., in: response)
        var words: [String: (display: String, count: Int, location: Int)] = [:]
        regex?.enumerateMatches(in: response, range: fullRange) { match, _, _ in
            guard let match,
                  let range = Range(match.range, in: response) else {
                return
            }
            let display = String(response[range])
            let canonical = display.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()
            guard !stopWords.contains(canonical),
                  !usedCanonical.contains(canonical) else {
                return
            }
            let location = response.distance(
                from: response.startIndex,
                to: range.lowerBound
            )
            if let current = words[canonical] {
                words[canonical] = (
                    current.display,
                    current.count + 1,
                    current.location
                )
            } else {
                words[canonical] = (display, 1, location)
            }
        }

        selected.append(contentsOf: words.map { canonical, value in
            let score = (philosophicalTerms.contains(canonical) ? 30 : 0)
                + min(canonical.count, 16)
                + min(value.count, 4) * 3
            return (value.display, canonical, value.location, score)
        })

        return selected
            .sorted {
                $0.score == $1.score
                    ? $0.location < $1.location
                    : $0.score > $1.score
            }
            .prefix(5)
            .map { candidate in
                KeyTerm(
                    displayText: candidate.display,
                    canonicalTerm: candidate.canonical,
                    contextExcerpt: contextExcerpt(
                        containing: candidate.display,
                        in: response
                    )
                )
            }
    }

    static func sanitizedVisibleText(_ raw: String) -> String {
        var text = raw
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

private struct DefinitionPayload: Codable {
    let title: String
    let context: String?
    let definition: String

    func validatedConcept() throws -> ConceptDefinition {
        let title = title.trimmed
        let definition = definition.trimmed
        guard !title.isEmpty, !definition.isEmpty else {
            throw AquinasModelActionError.invalidResponse
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

private struct DailyQuestionPayload: Decodable {
    let question: String
    let reasonForAsking: String
    let citedInsightTitle: String?

    private enum CodingKeys: String, CodingKey {
        case question
        case reasonForAsking = "reason_for_asking"
        case citedInsightTitle = "cited_insight_title"
    }
}

private struct LocalPresentationAnalysis {
    let thinkingSummary: [String]
    let keyTerms: [KeyTerm]
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
