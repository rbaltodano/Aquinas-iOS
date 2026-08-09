//
//  HomeBackendService.swift
//  Aquinas-iOS
//

import Foundation
import SwiftUI

struct LooseThreadCard: Equatable {
    let nodeID: UUID
    let nodeLabel: String
    let insightCount: Int
}

struct GlossedTermCard: Equatable {
    let termKey: String
    let requestedTerm: String
    let title: String
    let partOfSpeech: String
    let pronunciation: String
    let definition: String
    let example: String
    let context: String
}

struct TodayInHistoryCard: Equatable {
    let title: String
    let description: String
    let relatedEntity: String
    let linkedNodeID: UUID?

    /// Hidden context prepended to the first conversation started from the "Tell me more..."
    /// button, mirroring `HomeQuestionOfTheDay.taggedPromptContext`.
    var taggedPromptContext: String {
        """
        <today in history>
        <title>\(title.xmlEscaped)</title>
        <description>\(description.xmlEscaped)</description>
        <response_guidance>The user's next message is a question inspired by this historical \
        note. Answer it in light of the note above when relevant, without assuming the user has \
        already read it.</response_guidance>
        </today in history>
        """
    }
}

/// Tracks whether the user has already started a conversation from today's Today in History
/// card, mirroring `HomeQuestionOfTheDayStore`'s answered-state pattern -- once asked, the card
/// disappears from Home until the calendar day rolls over.
enum HomeTodayInHistoryStore {
    private static let key = "aquinas.home.todayInHistory.answeredDayKey.v1"

    static func markAnswered(at date: Date = Date()) {
        UserDefaults.standard.set(dayKey(for: date), forKey: key)
    }

    static func isAnswered(at date: Date = Date()) -> Bool {
        UserDefaults.standard.string(forKey: key) == dayKey(for: date)
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

struct YourQuoteCard: Equatable {
    let responseID: UUID
    let quoteText: String
    let source: String
    let reason: String?
}

protocol HomeBackendService {
    func looseThread(conversationID: UUID) async throws -> LooseThreadCard?
    func glossedTerm(conversationID: UUID) async throws -> GlossedTermCard?
    func todayInHistory(conversationID: UUID, overrideDate: String?) async throws -> TodayInHistoryCard?
    func yourQuote(conversationID: UUID) async throws -> YourQuoteCard?
}

struct BackendHomeService: HomeBackendService {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = AquinasBackendConfiguration.defaultBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func looseThread(conversationID: UUID) async throws -> LooseThreadCard? {
        let response: LooseThreadResponse? = try await request(
            path: "home/loose-thread",
            body: ConversationIDRequest(conversationID: conversationID.uuidString)
        )
        return try response?.domainValue
    }

    func glossedTerm(conversationID: UUID) async throws -> GlossedTermCard? {
        let response: GlossedTermResponse? = try await request(
            path: "home/glossed-terms",
            body: ConversationIDRequest(conversationID: conversationID.uuidString)
        )
        return response?.domainValue
    }

    func todayInHistory(conversationID: UUID, overrideDate: String?) async throws -> TodayInHistoryCard? {
        let response: TodayInHistoryResponse? = try await request(
            path: "home/today-in-history",
            body: TodayInHistoryRequest(
                conversationID: conversationID.uuidString,
                overrideDate: overrideDate
            )
        )
        return try response?.domainValue
    }

    func yourQuote(conversationID: UUID) async throws -> YourQuoteCard? {
        let response: YourQuoteResponse? = try await request(
            path: "home/your-quote",
            body: ConversationIDRequest(conversationID: conversationID.uuidString)
        )
        return try response?.domainValue
    }

    /// `Response` may be an `Optional` type -- callers that pass e.g. `LooseThreadResponse?` as
    /// the inferred type decode a JSON `null` body straight into `nil`, matching these routes'
    /// fail-quiet "nothing qualifies" contract.
    private func request<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        let endpoint = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HomeBackendServiceError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw HomeBackendServiceError.httpFailure(statusCode: httpResponse.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw HomeBackendServiceError.invalidPayload(error)
        }
    }
}

private struct ConversationIDRequest: Encodable {
    let conversationID: String

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
    }
}

private struct TodayInHistoryRequest: Encodable {
    let conversationID: String
    let overrideDate: String?

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case overrideDate = "override_date"
    }
}

private struct LooseThreadResponse: Decodable {
    let nodeID: String
    let nodeLabel: String
    let insightCount: Int

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case nodeLabel = "node_label"
        case insightCount = "insight_count"
    }

    var domainValue: LooseThreadCard {
        get throws {
            guard let nodeID = UUID(uuidString: nodeID) else {
                throw HomeBackendServiceError.invalidIdentifier
            }
            return LooseThreadCard(nodeID: nodeID, nodeLabel: nodeLabel, insightCount: insightCount)
        }
    }
}

private struct GlossedTermResponse: Decodable {
    let termKey: String
    let requestedTerm: String
    let title: String
    let partOfSpeech: String
    let pronunciation: String
    let definition: String
    let example: String
    let context: String

    enum CodingKeys: String, CodingKey {
        case termKey = "term_key"
        case requestedTerm = "requested_term"
        case title
        case partOfSpeech = "part_of_speech"
        case pronunciation
        case definition
        case example
        case context
    }

    var domainValue: GlossedTermCard {
        GlossedTermCard(
            termKey: termKey,
            requestedTerm: requestedTerm,
            title: title,
            partOfSpeech: partOfSpeech,
            pronunciation: pronunciation,
            definition: definition,
            example: example,
            context: context
        )
    }
}

private struct TodayInHistoryResponse: Decodable {
    let title: String
    let description: String
    let relatedEntity: String
    let linkedNodeID: String?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case relatedEntity = "related_entity"
        case linkedNodeID = "linked_node_id"
    }

    var domainValue: TodayInHistoryCard {
        get throws {
            var linkedID: UUID?
            if let linkedNodeID {
                guard let parsed = UUID(uuidString: linkedNodeID) else {
                    throw HomeBackendServiceError.invalidIdentifier
                }
                linkedID = parsed
            }
            return TodayInHistoryCard(
                title: title,
                description: description,
                relatedEntity: relatedEntity,
                linkedNodeID: linkedID
            )
        }
    }
}

private struct YourQuoteResponse: Decodable {
    let responseID: String
    let quoteText: String
    let source: String
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case responseID = "response_id"
        case quoteText = "quote_text"
        case source
        case reason
    }

    var domainValue: YourQuoteCard {
        get throws {
            guard let responseID = UUID(uuidString: responseID) else {
                throw HomeBackendServiceError.invalidIdentifier
            }
            return YourQuoteCard(
                responseID: responseID,
                quoteText: quoteText,
                source: source,
                reason: reason
            )
        }
    }
}

private enum HomeBackendServiceError: Error {
    case invalidResponse
    case httpFailure(statusCode: Int)
    case invalidPayload(Error)
    case invalidIdentifier
}

private let defaultHomeBackendService: HomeBackendService = BackendHomeService()

extension EnvironmentValues {
    @Entry var homeBackendService: HomeBackendService = defaultHomeBackendService
}
