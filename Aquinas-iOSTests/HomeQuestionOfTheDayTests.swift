import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Question of the Day lifecycle")
struct HomeQuestionOfTheDayTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("Answering hides the question and permits refresh the next calendar day")
    func answeredQuestionRefreshesNextDay() throws {
        let generatedAt = try #require(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 30,
                hour: 10
            ))
        )
        let answeredAt = generatedAt.addingTimeInterval(60 * 60)
        let question = HomeQuestionOfTheDay(
            question: "What follows?",
            generatedAt: generatedAt,
            answeredAt: answeredAt
        )
        let nextDay = try #require(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 31
            ))
        )

        #expect(!question.isPending(at: answeredAt))
        #expect(
            question.nextEligibleRefreshDate(calendar: calendar) == nextDay
        )
    }

    @Test("An unanswered question remains pending until its expiration")
    func unansweredQuestionWaitsForExpiration() {
        let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let expiration = generatedAt.addingTimeInterval(24 * 60 * 60)
        let question = HomeQuestionOfTheDay(
            question: "What follows?",
            generatedAt: generatedAt,
            expiresAt: expiration
        )

        #expect(question.isPending(at: expiration.addingTimeInterval(-1)))
        #expect(!question.isPending(at: expiration))
        #expect(
            question.nextEligibleRefreshDate(calendar: calendar) >= expiration
        )
    }

    @Test("An invalid cached value is hidden and can be replaced immediately")
    func invalidCachedValueIsImmediatelyEligibleForReplacement() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let question = HomeQuestionOfTheDay(
            question: "Failed to load",
            generatedAt: now,
            expiresAt: now.addingTimeInterval(24 * 60 * 60)
        )

        #expect(!question.isPending(at: now))
        #expect(question.nextEligibleRefreshDate(calendar: calendar) == .distantPast)
    }

    @Test("A generated one-line question is accepted without a JSON wrapper")
    func generatedPlainQuestionIsAccepted() {
        #expect(
            LiteRTAquinasModel.questionOfTheDayQuestion(
                from: "Question: What practical step would test this conclusion?"
            ) == "What practical step would test this conclusion?"
        )
        #expect(
            LiteRTAquinasModel.questionOfTheDayQuestion(
                from: "How might this distinction change the conclusion"
            ) == "How might this distinction change the conclusion?"
        )
        #expect(
            LiteRTAquinasModel.questionOfTheDayQuestion(
                from: "Here is an explanation without a question."
            ) == nil
        )
    }
}
