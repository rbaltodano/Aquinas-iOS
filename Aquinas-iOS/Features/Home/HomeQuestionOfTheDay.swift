//
//  HomeQuestionOfTheDay.swift
//  Aquinas-iOS
//

import Foundation

func debugQuestionOfTheDayConsoleLog(_ message: String) {
#if DEBUG
    guard let data = "[QuestionOfTheDay] \(message)\n".data(using: .utf8) else { return }
    try? FileHandle.standardError.write(contentsOf: data)
#endif
}

struct DailyQuestionDraft: Equatable {
    let question: String
    let reasonForAsking: String
    let citedInsightTitle: String?
}

struct HomeQuestionOfTheDay: Codable, Equatable, Identifiable {
    let id: UUID
    let question: String
    let reasonForAsking: String
    let citedInsight: ConceptDefinition?
    let sourceConversationID: UUID?
    let sourceConversationTitle: String?
    let generatedAt: Date
    let expiresAt: Date
    let answeredAt: Date?

    init(
        id: UUID = UUID(),
        question: String,
        reasonForAsking: String = "",
        citedInsight: ConceptDefinition? = nil,
        sourceConversationID: UUID? = nil,
        sourceConversationTitle: String? = nil,
        generatedAt: Date = Date(),
        expiresAt: Date? = nil,
        answeredAt: Date? = nil
    ) {
        self.id = id
        self.question = question
        self.reasonForAsking = reasonForAsking
        self.citedInsight = citedInsight
        self.sourceConversationID = sourceConversationID
        self.sourceConversationTitle = sourceConversationTitle
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt ?? generatedAt.addingTimeInterval(24 * 60 * 60)
        self.answeredAt = answeredAt
    }

    func isPending(at date: Date = Date()) -> Bool {
        Self.isValidQuestionText(question)
            && answeredAt == nil
            && expiresAt > date
    }

    static func isValidQuestionText(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).last == "?"
    }

    func markingAnswered(at date: Date = Date()) -> HomeQuestionOfTheDay {
        HomeQuestionOfTheDay(
            id: id,
            question: question,
            reasonForAsking: reasonForAsking,
            citedInsight: citedInsight,
            sourceConversationID: sourceConversationID,
            sourceConversationTitle: sourceConversationTitle,
            generatedAt: generatedAt,
            expiresAt: expiresAt,
            answeredAt: date
        )
    }

    func nextEligibleRefreshDate(
        calendar: Calendar = .current
    ) -> Date {
        guard Self.isValidQuestionText(question) else {
            return .distantPast
        }
        guard let nextCalendarDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: generatedAt)
        ) else {
            return .distantFuture
        }
        if answeredAt != nil {
            return nextCalendarDay
        }
        return max(expiresAt, nextCalendarDay)
    }

    /// Hidden context prepended to the first conversation created from the card.
    /// The deliberately human-readable outer tag matches the product language.
    var taggedPromptContext: String {
        var lines = [
            "<question of the day>",
            "<question>\(question.xmlEscaped)</question>"
        ]
        if !reasonForAsking.isEmpty {
            lines.append(
                "<reason_for_asking>\(reasonForAsking.xmlEscaped)</reason_for_asking>"
            )
        }
        if let citedInsight {
            lines.append(
                "<relevant_insight title=\"\(citedInsight.word.xmlEscaped)\">"
                    + citedInsight.semanticDefinition.xmlEscaped
                    + "</relevant_insight>"
            )
        }
        lines.append(
            "<response_guidance>The user's next message answers this question. "
                + "Occasionally mention the reason for asking or relevant Insight when natural."
                + "</response_guidance>"
        )
        lines.append("</question of the day>")
        return lines.joined(separator: "\n")
    }
}

enum HomeQuestionOfTheDayStore {
    private static let key = "aquinas.home.questionOfTheDay.v1"

    static func load() -> HomeQuestionOfTheDay? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let question = try? JSONDecoder().decode(
                  HomeQuestionOfTheDay.self,
                  from: data
              ) else {
            return nil
        }
        return question
    }

    static func loadPending(at date: Date = Date()) -> HomeQuestionOfTheDay? {
        guard let question = load(), question.isPending(at: date) else {
            return nil
        }
        return question
    }

    static func isEligibleForRefresh(
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        nextEligibleRefreshDate(calendar: calendar) <= date
    }

    static func nextEligibleRefreshDate(
        calendar: Calendar = .current
    ) -> Date {
        guard let question = load() else { return .distantPast }
        return question.nextEligibleRefreshDate(calendar: calendar)
    }

    static func save(_ question: HomeQuestionOfTheDay) {
        guard let data = try? JSONEncoder().encode(question) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct DailyQuestionSource {
    let conversation: InquiryConversation
    let context: ConversationContext
    let insights: [ConceptDefinition]
}

enum DailyQuestionSourceSelector {
    static func select(
        conversations: [InquiryConversation],
        activeConversationID: UUID?,
        savedInsights: [ConceptDefinition]
    ) -> DailyQuestionSource? {
        let recentConversations = conversations
            .filter { !$0.isStudyTopic }
            .sorted { left, right in
                let leftIsActive = left.id == activeConversationID
                let rightIsActive = right.id == activeConversationID
                if leftIsActive != rightIsActive { return leftIsActive }
                return left.createdAt > right.createdAt
            }

        for conversation in recentConversations {
            for branch in conversation.branches.reversed() {
                var transcript: [ChatBlock] = []
                let topQuestion = branch.topQuestionText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if branch.topQuestionSubmitted, !topQuestion.isEmpty {
                    transcript.append(
                        .user(topQuestion, branch.branchContextConcept, branch.topQuestionUploads)
                    )
                }
                transcript.append(contentsOf: branch.activeChatBlocks)

                let hasQuestion = transcript.contains {
                    guard case .user(let text, _, _) = $0 else { return false }
                    return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                let hasAnswer = transcript.contains {
                    guard case .text(let text) = $0 else { return false }
                    return text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 80
                }
                guard hasQuestion, hasAnswer else { continue }

                return DailyQuestionSource(
                    conversation: conversation,
                    context: ConversationContext(
                        compactedContext: branch.compactedContext,
                        transcript: transcript
                    ),
                    insights: relevantInsights(
                        for: conversation,
                        savedInsights: savedInsights
                    )
                )
            }
        }
        return nil
    }

    private static func relevantInsights(
        for conversation: InquiryConversation,
        savedInsights: [ConceptDefinition]
    ) -> [ConceptDefinition] {
        var conceptWords = Set<String>()
        for branch in conversation.branches {
            for concept in [
                branch.startingConcept,
                branch.attachedConcept,
                branch.branchContextConcept,
            ].compactMap({ $0 }) {
                conceptWords.insert(concept.word.lowercased())
            }
            for block in branch.activeChatBlocks {
                if case .user(_, let concept?, _) = block {
                    conceptWords.insert(concept.word.lowercased())
                }
            }
        }

        var seenWords = Set<String>()
        return savedInsights.filter { insight in
            let key = insight.word.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased()
            guard !key.isEmpty,
                  conceptWords.contains(key),
                  !seenWords.contains(key) else {
                return false
            }
            seenWords.insert(key)
            return true
        }
    }
}

/// Picks a conversation to scope the four backend-fetched Home sections to (Loose Thread, Today
/// in History, Terms You Glossed Over, Your Quote). Reuses `DailyQuestionSourceSelector`'s
/// ordering -- Study Topics excluded, active conversation first, then most-recently-created --
/// without its `hasQuestion`/`hasAnswer` transcript requirement, since these routes don't need a
/// real Q&A exchange to scope to, just *a* conversation.
enum HomeSectionSourceSelector {
    static func selectConversationID(
        conversations: [InquiryConversation],
        activeConversationID: UUID?
    ) -> UUID? {
        conversations
            .filter { !$0.isStudyTopic }
            .sorted { left, right in
                let leftIsActive = left.id == activeConversationID
                let rightIsActive = right.id == activeConversationID
                if leftIsActive != rightIsActive { return leftIsActive }
                return left.createdAt > right.createdAt
            }
            .first?.id
    }
}

extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
