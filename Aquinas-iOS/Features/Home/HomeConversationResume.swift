//
//  HomeConversationResume.swift
//  Aquinas-iOS
//

import Foundation

enum HomeConversationResume {
    nonisolated static func featuredConversation(
        in conversations: [InquiryConversation],
        activeConversationID: UUID?
    ) -> InquiryConversation? {
        let resumableConversations = conversations.filter(hasContent)

        if let activeConversationID,
           let activeConversation = resumableConversations.first(where: {
               $0.id == activeConversationID
           }) {
            return activeConversation
        }

        return resumableConversations.first
    }

    nonisolated static func hasContent(_ conversation: InquiryConversation) -> Bool {
        if !conversation.promotedInsightIDs.isEmpty {
            return true
        }

        return conversation.branches.contains { branch in
            if branch.startingConcept != nil
                || branch.attachedConcept != nil
                || branch.branchContextConcept != nil
                || !branch.topQuestionUploads.isEmpty {
                return true
            }

            if containsText(branch.duplicatedResponse)
                || containsText(branch.topQuestionText)
                || containsText(branch.bottomQuestionText) {
                return true
            }

            return branch.activeChatBlocks.contains { block in
                switch block {
                case .text(let response):
                    return containsText(response)
                case .user(let question, let concept, let uploads):
                    return containsText(question) || concept != nil || !uploads.isEmpty
                }
            }
        }
    }

    nonisolated private static func containsText(_ text: String?) -> Bool {
        guard let text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
