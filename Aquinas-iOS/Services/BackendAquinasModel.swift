//
//  BackendAquinasModel.swift
//  Aquinas-iOS
//

import Foundation
import ImageIO
import UIKit

/// The live model boundary. Generative tasks use the local FastAPI service and fail explicitly
/// when it is unavailable; deterministic mock content is restricted to previews and tests.
struct BackendAquinasModel: AquinasModel {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = AquinasBackendConfiguration.defaultBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func respond(to context: ConversationContext) async -> ModelResponse {
        await completeResponse(to: context, thinkingEnabled: false)
    }

    func compact(_ context: ConversationContext) async -> String {
        let messages = context.backendMessages
        guard !messages.isEmpty || context.compactedContext != nil else {
            return ""
        }

        do {
            let response: ConversationCompactionResponse = try await post(
                path: "conversation/compact",
                body: ConversationCompactionRequest(
                    recentMessages: messages,
                    compactedContext: context.compactedContext
                )
            )
            return response.summary
        } catch {
            logFailure(error, operation: "compact conversation")
            return ""
        }
    }

    private func completeResponse(
        to context: ConversationContext,
        thinkingEnabled: Bool
    ) async -> ModelResponse {
        let messages = context.backendMessages
        guard !messages.isEmpty else {
            return ModelResponse(text: "")
        }

        do {
            let response: StructuredConversationResponse = try await post(
                path: "conversation/respond",
                body: ConversationResponseRequest(
                    recentMessages: messages,
                    compactedContext: context.compactedContext,
                    thinkingEnabled: thinkingEnabled,
                    personality: context.personality
                )
            )
            return ModelResponse(
                text: response.response,
                thinkingSummary: response.thinkingSummary ?? [],
                keyTerms: response.keyTerms.map {
                    KeyTerm(
                        displayText: $0.displayText,
                        canonicalTerm: $0.canonicalTerm,
                        contextExcerpt: $0.contextExcerpt
                    )
                },
                insight: response.insight?.conceptDefinition
            )
        } catch {
            logFailure(error, operation: "answer conversation")
            return Self.backendUnavailableResponse(baseURL: baseURL)
                .withThinkingEnabled(thinkingEnabled)
        }
    }

    func respond(
        to context: ConversationContext,
        thinkingEnabled: Bool,
        onUpdate: @escaping (ModelResponseUpdate) -> Void
    ) async -> ModelResponse {
        let messages = context.backendMessages
        guard !messages.isEmpty else {
            return ModelResponse(text: "")
        }

        do {
            return try await streamConversationResponse(
                messages: messages,
                compactedContext: context.compactedContext,
                thinkingEnabled: thinkingEnabled,
                personality: context.personality,
                onUpdate: onUpdate
            )
        } catch {
            // Cancellation is an intentional user action. Do not turn it into a second,
            // non-streaming backend request whose result will immediately be discarded.
            guard !Task.isCancelled else {
                return ModelResponse(text: "", thinkingSummary: [], keyTerms: [])
            }
            logFailure(error, operation: "stream conversation")
            onUpdate(.generationStarted)
            let response = await completeResponse(
                to: context,
                thinkingEnabled: thinkingEnabled
            )
            if thinkingEnabled && !response.thinkingSummary.isEmpty {
                onUpdate(.thinkingSummary(response.thinkingSummary))
            }
            onUpdate(.responseText(response.annotatedText))
            return response
        }
    }

    func defineTerm(
        _ term: String,
        in context: ConversationContext
    ) async throws -> ConceptDefinition {
        let payload = ContextualDefinitionRequest(
            term: term,
            sourceExcerpt: context.sourceExcerpt(for: term),
            recentMessages: context.backendMessages
        )

        do {
            let response: ContextualDefinitionResponse = try await post(
                path: "concept/define",
                body: payload
            )
            return ConceptDefinition(
                word: response.title,
                partOfSpeech: response.partOfSpeech,
                pronunciation: response.pronunciation,
                meaning: response.definition.removingContextLeadIn(),
                example: response.example,
                context: response.context
            )
        } catch {
            logFailure(error, operation: "define term")
            throw AquinasModelActionError.unavailable
        }
    }

    func defineTerm(
        _ term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async throws -> ConceptDefinition {
        guard let conversationID else {
            return try await defineTerm(term, in: context)
        }

        let payload = ContextualDefinitionRequest(
            term: term,
            sourceExcerpt: context.sourceExcerpt(for: term),
            recentMessages: context.backendMessages
        )

        do {
            let response: ContextualDefinitionResponse = try await post(
                path: "conversation/\(conversationID.uuidString)/concept/define",
                body: payload
            )
            return ConceptDefinition(
                word: response.title,
                partOfSpeech: response.partOfSpeech,
                pronunciation: response.pronunciation,
                meaning: response.definition.removingContextLeadIn(),
                example: response.example,
                context: response.context
            )
        } catch {
            logFailure(error, operation: "define cached term")
            return try await defineTerm(term, in: context)
        }
    }

    func cachedDefinition(
        for term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async -> ConceptDefinition? {
        guard let conversationID else { return nil }

        let payload = ContextualDefinitionRequest(
            term: term,
            sourceExcerpt: context.sourceExcerpt(for: term),
            recentMessages: context.backendMessages
        )

        do {
            let response: ContextualDefinitionResponse? = try await post(
                path: "conversation/\(conversationID.uuidString)/concept/lookup",
                body: payload
            )
            guard let response else { return nil }
            return ConceptDefinition(
                word: response.title,
                partOfSpeech: response.partOfSpeech,
                pronunciation: response.pronunciation,
                meaning: response.definition.removingContextLeadIn(),
                example: response.example,
                context: response.context
            )
        } catch {
            logFailure(error, operation: "look up cached term")
            return nil
        }
    }

    func labelSubject(forTitles titles: [String]) async throws -> String {
        do {
            let response: BackendNodeSubjectResponse = try await post(
                path: "insight-tree/label-node",
                body: BackendNodeSubjectRequest(insightDescriptions: titles)
            )
            return response.label
        } catch {
            logFailure(error, operation: "label Node Concept")
            throw AquinasModelActionError.unavailable
        }
    }

    func blendConceptCandidates(
        _ concepts: [ConceptDefinition],
        weights: [Double]
    ) async throws -> [ConceptDefinition] {
        guard concepts.count >= 2, concepts.count == weights.count else {
            throw AquinasModelActionError.invalidRequest
        }

        do {
            let response: MidpointCandidatesResponse = try await post(
                path: "concept/blend",
                body: MidpointBlendRequest(
                    concepts: concepts.map {
                        MidpointConceptPayload(
                            title: $0.word,
                            definition: $0.meaning,
                            example: $0.example
                        )
                    },
                    weights: weights
                )
            )
            guard !response.candidates.isEmpty else {
                throw BackendModelError.invalidResponse
            }
            return response.candidates.map {
                ConceptDefinition(
                    word: $0.title,
                    partOfSpeech: $0.partOfSpeech,
                    pronunciation: $0.pronunciation,
                    meaning: $0.definition.removingContextLeadIn(),
                    example: $0.example
                )
            }
        } catch {
            logFailure(error, operation: "blend Midpoint concepts")
            throw AquinasModelActionError.unavailable
        }
    }

    func generateChildren(
        for concept: ConceptDefinition
    ) async throws -> [ConceptDefinition] {
        do {
            let response: MakeNodeChildrenResponse = try await post(
                path: "concept/children",
                body: MakeNodeChildrenRequest(
                    concept: MidpointConceptPayload(
                        title: concept.word,
                        definition: concept.meaning,
                        example: concept.example
                    )
                )
            )
            guard response.children.count == 3 else {
                throw BackendModelError.invalidResponse
            }
            return response.children.map {
                ConceptDefinition(
                    word: $0.title,
                    partOfSpeech: $0.partOfSpeech,
                    pronunciation: $0.pronunciation,
                    meaning: $0.definition.removingContextLeadIn(),
                    example: $0.example
                )
            }
        } catch {
            logFailure(error, operation: "generate Make Node children")
            throw AquinasModelActionError.unavailable
        }
    }

    func generateQuestionOfTheDay(
        from context: ConversationContext,
        conversationTitle: String,
        insights: [ConceptDefinition]
    ) async throws -> DailyQuestionDraft {
        let messages = context.backendMessages
        guard !messages.isEmpty else {
            throw AquinasModelActionError.invalidRequest
        }

        do {
            let response: DailyQuestionResponse = try await post(
                path: "home/question-of-the-day",
                body: DailyQuestionRequest(
                    conversationTitle: conversationTitle,
                    recentMessages: messages,
                    insights: insights.prefix(4).map {
                        DailyQuestionInsightPayload(
                            title: $0.word,
                            definition: $0.semanticDefinition
                        )
                    }
                )
            )
            return DailyQuestionDraft(
                question: response.question,
                reasonForAsking: response.reasonForAsking,
                citedInsightTitle: response.citedInsightTitle
            )
        } catch {
            logFailure(error, operation: "generate Question of the Day")
            throw AquinasModelActionError.unavailable
        }
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        let endpoint = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendModelError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw BackendModelError.httpFailure(
                statusCode: httpResponse.statusCode,
                detail: BackendErrorResponse.decodeDetail(from: data)
            )
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw BackendModelError.invalidPayload(error)
        }
    }

    private func streamConversationResponse(
        messages: [BackendConversationMessage],
        compactedContext: String? = nil,
        thinkingEnabled: Bool,
        personality: ConversationPersonality,
        onUpdate: @escaping (ModelResponseUpdate) -> Void
    ) async throws -> ModelResponse {
        let endpoint = baseURL.appendingPathComponent("conversation/respond/stream")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            ConversationResponseRequest(
                recentMessages: messages,
                compactedContext: compactedContext,
                thinkingEnabled: thinkingEnabled,
                personality: personality
            )
        )

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendModelError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw BackendModelError.httpFailure(
                statusCode: httpResponse.statusCode,
                detail: nil
            )
        }

        var streamedText = ""
        var lastPublishedText = ""
        var lastTextPublish = ContinuousClock.now
        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8) else {
                continue
            }
            let event: ConversationStreamEvent
            do {
                event = try JSONDecoder().decode(ConversationStreamEvent.self, from: data)
            } catch {
                throw BackendModelError.invalidPayload(error)
            }

            switch event.type {
            case "start":
                onUpdate(.generationStarted)
            case "thinking_summary":
                if thinkingEnabled {
                    onUpdate(.thinkingSummary(event.thinkingSummary ?? []))
                }
            case "response_delta":
                streamedText += event.delta ?? ""
                let now = ContinuousClock.now
                if now - lastTextPublish >= .milliseconds(50) {
                    let publishableText = Self.completedTokenPrefix(in: streamedText)
                    if publishableText != lastPublishedText {
                        onUpdate(.responseText(publishableText))
                        lastPublishedText = publishableText
                        lastTextPublish = now
                    }
                }
            case "complete":
                guard let responseText = event.response else {
                    throw BackendModelError.invalidResponse
                }
                let result = ModelResponse(
                    text: responseText,
                    thinkingSummary: event.thinkingSummary ?? [],
                    keyTerms: (event.keyTerms ?? []).map {
                        KeyTerm(
                            displayText: $0.displayText,
                            canonicalTerm: $0.canonicalTerm,
                            contextExcerpt: $0.contextExcerpt
                        )
                    },
                    insight: event.insight?.conceptDefinition
                )
                if thinkingEnabled && !result.thinkingSummary.isEmpty {
                    onUpdate(.thinkingSummary(result.thinkingSummary))
                }
                // Keep the live renderer on plain generated prose. The caller swaps
                // in `annotatedText` atomically when this method returns so raw
                // aq:// markdown never flashes before the final underline pass.
                onUpdate(.responseText(result.text))
                return result
            case "error":
                throw BackendModelError.streamingFailure(
                    event.detail ?? "The streaming response failed."
                )
            default:
                continue
            }
        }

        throw BackendModelError.invalidResponse
    }

    private func logFailure(_ error: Error, operation: String) {
#if DEBUG
        print("Aquinas backend failed to \(operation): \(error.localizedDescription)")
#endif
    }

    private static func backendUnavailableResponse(baseURL: URL) -> ModelResponse {
        ModelResponse(
            text: "I couldn't reach the local Aquinas backend at \(baseURL.absoluteString). Make sure the backend is running and that this device can reach that address, then try again."
        )
    }

    private static func completedTokenPrefix(in text: String) -> String {
        guard let boundary = text.lastIndex(where: \.isWhitespace) else {
            return ""
        }
        return String(text[...boundary])
    }
}

private struct BackendNodeSubjectRequest: Encodable {
    let insightDescriptions: [String]

    enum CodingKeys: String, CodingKey {
        case insightDescriptions = "insight_descriptions"
    }
}

private struct BackendNodeSubjectResponse: Decodable {
    let label: String
}

private struct MidpointCandidatesResponse: Decodable {
    let candidates: [ContextualDefinitionResponse]
}

private extension ModelResponse {
    func withThinkingEnabled(_ isEnabled: Bool) -> ModelResponse {
        guard !isEnabled else {
            return self
        }
        return ModelResponse(
            text: text,
            thinkingSummary: [],
            keyTerms: keyTerms,
            insight: insight,
            evidenceBasis: evidenceBasis
        )
    }
}

// MARK: - Configuration

enum AquinasBackendConfiguration {
    static let defaultBaseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["AQUINAS_BACKEND_URL"],
           let url = URL(string: override) {
            return url
        }
        if let configured = Bundle.main.object(
            forInfoDictionaryKey: "AquinasBackendURL"
        ) as? String,
           let url = URL(string: configured) {
            return url
        }
        return URL(string: "http://127.0.0.1:8000")!
    }()

    static var canRecoverFromCurrentDevice: Bool {
#if targetEnvironment(simulator)
        true
#else
        !isLoopback(defaultBaseURL)
#endif
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}

// MARK: - Conversation Mapping

private extension ConversationContext {
    var backendMessages: [BackendConversationMessage] {
        let messages = transcript.compactMap { block in
            switch block {
            case .text(let text):
                return BackendConversationMessage(
                    role: "assistant",
                    text: InlineInsightMarkup.plainText(from: text),
                    images: [],
                    insightQuote: nil
                )
            case .user(let text, let concept, let uploads):
                return BackendConversationMessage(
                    role: "user",
                    text: text,
                    images: uploads.compactMap(\.backendImagePayload),
                    insightQuote: concept.map {
                        BackendConversationInsightQuote(
                            title: $0.word,
                            definition: $0.semanticDefinition
                        )
                    }
                )
            }
        }
        .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .suffix(20)

        // Keep multimodal requests bounded while retaining the most recently attached images,
        // which are the ones a follow-up question is most likely to reference.
        var remainingImageCount = 8
        return messages.reversed().map { message in
            let images = Array(message.images.prefix(remainingImageCount))
            remainingImageCount -= images.count
            return BackendConversationMessage(
                role: message.role,
                text: message.text,
                images: images,
                insightQuote: message.insightQuote
            )
        }
        .reversed()
        .map { $0 }
    }

    func sourceExcerpt(for term: String) -> String {
        for block in transcript.reversed() {
            guard case .text(let storedText) = block else {
                continue
            }
            let text = InlineInsightMarkup.plainText(from: storedText)
            guard let termRange = text.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive]
                  ) else {
                continue
            }
            let lowerBound = text.index(
                termRange.lowerBound,
                offsetBy: -200,
                limitedBy: text.startIndex
            ) ?? text.startIndex
            let upperBound = text.index(
                termRange.upperBound,
                offsetBy: 200,
                limitedBy: text.endIndex
            ) ?? text.endIndex
            return String(text[lowerBound..<upperBound])
        }
        return ""
    }
}

// MARK: - API Payloads

private struct BackendConversationMessage: Codable {
    let role: String
    let text: String
    let images: [BackendConversationImage]
    let insightQuote: BackendConversationInsightQuote?

    enum CodingKeys: String, CodingKey {
        case role
        case text
        case images
        case insightQuote = "insight_quote"
    }
}

private struct BackendConversationInsightQuote: Codable {
    let title: String
    let definition: String
}

private struct BackendConversationImage: Codable {
    let name: String
    let mediaType: String
    let dataBase64: String

    enum CodingKeys: String, CodingKey {
        case name
        case mediaType = "media_type"
        case dataBase64 = "data_base64"
    }
}

private extension UploadedFile {
    var backendImagePayload: BackendConversationImage? {
        guard let imageData,
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1_536
                ] as CFDictionary
              ),
              let jpegData = UIImage(cgImage: thumbnail).jpegData(
                compressionQuality: 0.82
              ) else {
            return nil
        }

        return BackendConversationImage(
            name: name,
            mediaType: "image/jpeg",
            dataBase64: jpegData.base64EncodedString()
        )
    }
}

private struct ConversationResponseRequest: Encodable {
    let recentMessages: [BackendConversationMessage]
    let compactedContext: String?
    let thinkingEnabled: Bool
    let personality: ConversationPersonality
    let generationMode: String = "automatic"

    enum CodingKeys: String, CodingKey {
        case recentMessages = "recent_messages"
        case compactedContext = "compacted_context"
        case thinkingEnabled = "thinking_enabled"
        case personality
        case generationMode = "generation_mode"
    }
}

private struct ConversationCompactionRequest: Encodable {
    let recentMessages: [BackendConversationMessage]
    let compactedContext: String?

    enum CodingKeys: String, CodingKey {
        case recentMessages = "recent_messages"
        case compactedContext = "compacted_context"
    }
}

private struct ConversationCompactionResponse: Decodable {
    let summary: String
}

private struct DailyQuestionRequest: Encodable {
    let conversationTitle: String
    let recentMessages: [BackendConversationMessage]
    let insights: [DailyQuestionInsightPayload]

    enum CodingKeys: String, CodingKey {
        case conversationTitle = "conversation_title"
        case recentMessages = "recent_messages"
        case insights
    }
}

private struct DailyQuestionInsightPayload: Encodable {
    let title: String
    let definition: String
}

private struct DailyQuestionResponse: Decodable {
    let question: String
    let reasonForAsking: String
    let citedInsightTitle: String?

    enum CodingKeys: String, CodingKey {
        case question
        case reasonForAsking = "reason_for_asking"
        case citedInsightTitle = "cited_insight_title"
    }
}

private struct StructuredConversationResponse: Decodable {
    let response: String
    let thinkingSummary: [String]?
    let keyTerms: [GeneratedKeyTermResponse]
    let insight: ContextualDefinitionResponse?

    enum CodingKeys: String, CodingKey {
        case response
        case thinkingSummary = "thinking_summary"
        case keyTerms = "key_terms"
        case insight
    }
}

private struct ConversationStreamEvent: Decodable {
    let type: String
    let delta: String?
    let response: String?
    let thinkingSummary: [String]?
    let keyTerms: [GeneratedKeyTermResponse]?
    let insight: ContextualDefinitionResponse?
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case response
        case thinkingSummary = "thinking_summary"
        case keyTerms = "key_terms"
        case insight
        case detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        // Stream progress is deliberately lossy. A malformed optional progress
        // field should be ignored so a later valid `complete` event can still
        // finish the response instead of being reported as a connection error.
        delta = try? container.decode(String.self, forKey: .delta)
        response = try? container.decode(String.self, forKey: .response)
        thinkingSummary = try? container.decode(
            [String].self,
            forKey: .thinkingSummary
        )
        keyTerms = try? container.decode(
            [GeneratedKeyTermResponse].self,
            forKey: .keyTerms
        )
        insight = try? container.decode(
            ContextualDefinitionResponse.self,
            forKey: .insight
        )
        detail = try? container.decode(String.self, forKey: .detail)
    }
}

private struct GeneratedKeyTermResponse: Decodable {
    let displayText: String
    let canonicalTerm: String
    let contextExcerpt: String

    enum CodingKeys: String, CodingKey {
        case displayText = "display_text"
        case canonicalTerm = "canonical_term"
        case contextExcerpt = "context_excerpt"
    }
}

private struct ContextualDefinitionRequest: Encodable {
    let term: String
    let sourceExcerpt: String
    let recentMessages: [BackendConversationMessage]

    enum CodingKeys: String, CodingKey {
        case term
        case sourceExcerpt = "source_excerpt"
        case recentMessages = "recent_messages"
    }
}

private struct MidpointConceptPayload: Encodable {
    let title: String
    let definition: String
    let example: String
}

private struct MidpointBlendRequest: Encodable {
    let concepts: [MidpointConceptPayload]
    let weights: [Double]
}

private struct MakeNodeChildrenRequest: Encodable {
    let concept: MidpointConceptPayload
}

private struct MakeNodeChildrenResponse: Decodable {
    let children: [ContextualDefinitionResponse]
}

private struct ContextualDefinitionResponse: Decodable {
    let title: String
    let partOfSpeech: String
    let pronunciation: String
    let definition: String
    let example: String
    let context: String

    enum CodingKeys: String, CodingKey {
        case title
        case partOfSpeech = "part_of_speech"
        case pronunciation
        case definition
        case example
        case context
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        partOfSpeech = try container.decodeIfPresent(
            String.self,
            forKey: .partOfSpeech
        ) ?? ""
        pronunciation = try container.decodeIfPresent(
            String.self,
            forKey: .pronunciation
        ) ?? ""
        definition = try container.decode(String.self, forKey: .definition)
        example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        context = try container.decodeIfPresent(String.self, forKey: .context) ?? ""
    }
}

private extension ContextualDefinitionResponse {
    var conceptDefinition: ConceptDefinition {
        ConceptDefinition(
            id: ConceptDefinition.stableID(forTerm: title),
            word: title,
            partOfSpeech: partOfSpeech,
            pronunciation: pronunciation,
            meaning: definition.removingContextLeadIn(),
            example: example,
            context: context
        )
    }
}

private struct BackendErrorResponse: Decodable {
    let detail: String

    static func decodeDetail(from data: Data) -> String? {
        try? JSONDecoder().decode(Self.self, from: data).detail
    }
}

private enum BackendModelError: LocalizedError {
    case invalidResponse
    case httpFailure(statusCode: Int, detail: String?)
    case invalidPayload(Error)
    case streamingFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The backend returned an invalid response."
        case .httpFailure(let statusCode, let detail):
            detail ?? "The backend request failed with status \(statusCode)."
        case .invalidPayload:
            "The backend returned data the app could not read."
        case .streamingFailure(let detail):
            detail
        }
    }
}

private extension String {
    func removingContextLeadIn() -> String {
        let patterns = [
            #"(?i)^\s*in\s+this\s+context,\s*"#,
            #"(?i)^\s*in\s+this\s+conversation,\s*"#,
            #"(?i)^\s*as\s+used\s+in\s+this\s+context,\s*"#,
            #"(?i)^\s*as\s+used\s+in\s+this\s+conversation,\s*"#
        ]
        var result = self
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression]
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
