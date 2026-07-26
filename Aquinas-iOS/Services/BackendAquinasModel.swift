//
//  BackendAquinasModel.swift
//  Aquinas-iOS
//

import Foundation

/// The live model boundary. Implemented backend tasks use the local FastAPI service; tasks whose
/// backend contracts are not ready yet deliberately retain the mock behavior so the current UI
/// remains usable while the integration proceeds one seam at a time.
struct BackendAquinasModel: AquinasModel {
    private let baseURL: URL
    private let session: URLSession
    private let fallback: MockAquinasModel

    init(
        baseURL: URL = AquinasBackendConfiguration.defaultBaseURL,
        session: URLSession = .shared,
        fallback: MockAquinasModel = MockAquinasModel()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.fallback = fallback
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
            let response = await fallback.respond(to: context)
            return response.withThinkingEnabled(thinkingEnabled)
        }

        do {
            let response: StructuredConversationResponse = try await post(
                path: "conversation/respond",
                body: ConversationResponseRequest(
                    recentMessages: messages,
                    compactedContext: context.compactedContext,
                    thinkingEnabled: thinkingEnabled
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
                }
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
            return await fallback.respond(
                to: context,
                thinkingEnabled: thinkingEnabled,
                onUpdate: onUpdate
            )
        }

        do {
            return try await streamConversationResponse(
                messages: messages,
                compactedContext: context.compactedContext,
                thinkingEnabled: thinkingEnabled,
                onUpdate: onUpdate
            )
        } catch {
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

    func defineTerm(_ term: String, in context: ConversationContext) async -> ConceptDefinition {
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
                example: response.example
            )
        } catch {
            logFailure(error, operation: "define term")
            return await fallback.defineTerm(term, in: context)
        }
    }

    func defineTerm(
        _ term: String,
        in context: ConversationContext,
        conversationID: UUID?
    ) async -> ConceptDefinition {
        guard let conversationID else {
            return await defineTerm(term, in: context)
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
                example: response.example
            )
        } catch {
            logFailure(error, operation: "define cached term")
            return await defineTerm(term, in: context)
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
                example: response.example
            )
        } catch {
            logFailure(error, operation: "look up cached term")
            return nil
        }
    }

    func labelSubject(forTitles titles: [String]) async -> String {
        do {
            let response: BackendNodeSubjectResponse = try await post(
                path: "insight-tree/label-node",
                body: BackendNodeSubjectRequest(insightDescriptions: titles)
            )
            return response.label
        } catch {
            return await fallback.labelSubject(forTitles: titles)
        }
    }

    func blendConcepts(
        _ concepts: [ConceptDefinition],
        weights: [Double]
    ) async -> ConceptDefinition {
        await fallback.blendConcepts(concepts, weights: weights)
    }

    func generateChildren(for concept: ConceptDefinition) async -> [ConceptDefinition] {
        await fallback.generateChildren(for: concept)
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
                thinkingEnabled: thinkingEnabled
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
                    }
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
    let summary: String
}

private extension ModelResponse {
    func withThinkingEnabled(_ isEnabled: Bool) -> ModelResponse {
        guard !isEnabled else {
            return self
        }
        return ModelResponse(
            text: text,
            thinkingSummary: [],
            keyTerms: keyTerms
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
}

// MARK: - Conversation Mapping

private extension ConversationContext {
    var backendMessages: [BackendConversationMessage] {
        transcript.compactMap { block in
            switch block {
            case .text(let text):
                return BackendConversationMessage(role: "assistant", text: text)
            case .user(let text, _, _):
                return BackendConversationMessage(role: "user", text: text)
            }
        }
        .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .suffix(20)
        .map { $0 }
    }

    func sourceExcerpt(for term: String) -> String {
        for block in transcript.reversed() {
            guard case .text(let text) = block,
                  let termRange = text.range(
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
}

private struct ConversationResponseRequest: Encodable {
    let recentMessages: [BackendConversationMessage]
    let compactedContext: String?
    let thinkingEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case recentMessages = "recent_messages"
        case compactedContext = "compacted_context"
        case thinkingEnabled = "thinking_enabled"
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

private struct StructuredConversationResponse: Decodable {
    let response: String
    let thinkingSummary: [String]?
    let keyTerms: [GeneratedKeyTermResponse]

    enum CodingKeys: String, CodingKey {
        case response
        case thinkingSummary = "thinking_summary"
        case keyTerms = "key_terms"
    }
}

private struct ConversationStreamEvent: Decodable {
    let type: String
    let delta: String?
    let response: String?
    let thinkingSummary: [String]?
    let keyTerms: [GeneratedKeyTermResponse]?
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case response
        case thinkingSummary = "thinking_summary"
        case keyTerms = "key_terms"
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

private struct ContextualDefinitionResponse: Decodable {
    let title: String
    let partOfSpeech: String
    let pronunciation: String
    let definition: String
    let example: String

    enum CodingKeys: String, CodingKey {
        case title
        case partOfSpeech = "part_of_speech"
        case pronunciation
        case definition
        case example
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
