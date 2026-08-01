import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Home conversation resume")
struct HomeConversationResumeTests {
    @Test("A blank conversation does not appear as where you left off")
    func blankConversationIsNotFeatured() {
        let blankConversation = InquiryConversation()

        let featuredConversation = HomeConversationResume.featuredConversation(
            in: [blankConversation],
            activeConversationID: blankConversation.id
        )

        #expect(featuredConversation == nil)
    }

    @Test("A blank active conversation falls back to a previous conversation")
    func blankActiveConversationFallsBackToPreviousConversation() {
        let blankConversation = InquiryConversation()
        var previousConversation = InquiryConversation(title: "Grace and Nature")
        previousConversation.branches[0].activeChatBlocks = [
            .user("How does grace perfect nature?", nil, [])
        ]

        let featuredConversation = HomeConversationResume.featuredConversation(
            in: [blankConversation, previousConversation],
            activeConversationID: blankConversation.id
        )

        #expect(featuredConversation?.id == previousConversation.id)
    }

    @Test("Whitespace-only drafts remain blank")
    func whitespaceOnlyDraftIsNotContent() {
        var conversation = InquiryConversation()
        conversation.branches[0].topQuestionText = " \n\t "
        conversation.branches[0].bottomQuestionText = "   "

        #expect(!HomeConversationResume.hasContent(conversation))
    }
}
