import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Study Topic Insight Tree")
struct StudyTopicInsightTreeTests {
    @Test("Snapshot includes only saved Insights attached to conversations in the topic")
    func snapshotIsTopicScoped() {
        let topicID = UUID()
        let otherTopicID = UUID()
        let includedConversationID = UUID()
        let otherConversationID = UUID()
        let includedInsight = concept("Grace")
        let otherInsight = concept("Justice")

        let snapshot = StudyTopicInsightTreeBuilder.snapshot(
            topicID: topicID,
            conversations: [
                InquiryConversation(
                    id: includedConversationID,
                    studyTopicID: topicID
                ),
                InquiryConversation(
                    id: otherConversationID,
                    studyTopicID: otherTopicID
                )
            ],
            savedInsights: [otherInsight, includedInsight],
            insightIDs: { conversationID in
                conversationID == includedConversationID
                    ? [includedInsight.id]
                    : [otherInsight.id]
            }
        )

        #expect(snapshot.map(\.id) == [includedInsight.id])
    }

    @Test("Snapshot combines memberships, removes duplicate terms, and sorts by title")
    func snapshotCombinesMemberships() {
        let topicID = UUID()
        let firstConversationID = UUID()
        let secondConversationID = UUID()
        let grace = concept("Grace")
        let duplicateGrace = concept("grace")
        let beatitude = concept("Beatitude")

        let snapshot = StudyTopicInsightTreeBuilder.snapshot(
            topicID: topicID,
            conversations: [
                InquiryConversation(
                    id: firstConversationID,
                    studyTopicID: topicID
                ),
                InquiryConversation(
                    id: secondConversationID,
                    studyTopicID: topicID
                )
            ],
            savedInsights: [grace, duplicateGrace, beatitude],
            insightIDs: { conversationID in
                conversationID == firstConversationID
                    ? [grace.id, beatitude.id]
                    : [duplicateGrace.id]
            }
        )

        #expect(snapshot.map(\.word) == ["Beatitude", "Grace"])
    }

    private func concept(_ word: String) -> ConceptDefinition {
        ConceptDefinition(
            word: word,
            partOfSpeech: "noun",
            pronunciation: "",
            meaning: "A contextual definition of \(word).",
            example: ""
        )
    }
}
