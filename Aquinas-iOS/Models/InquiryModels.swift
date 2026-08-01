//
//  InquiryModels.swift
//  Aquinas-iOS
//

import Foundation
import SwiftUI

// MARK: - Inquiry Data

/// One vertical conversation lane. Branches can begin from an insight chip or a copied model response.
struct ChatBranch: Identifiable, Codable, Equatable {
    let id: UUID
    let startingConcept: ConceptDefinition?
    let parentBranchID: UUID?
    var parentResponseIndex: Int?
    let duplicatedResponse: String?
    var yOffset: CGFloat = 0
    var activeChatBlocks: [ChatBlock] = []
    var topQuestionText: String = ""
    var topQuestionUploads: [UploadedFile] = []
    var topQuestionSubmitted: Bool = false
    var bottomQuestionText: String = ""
    var showBottomInput: Bool = false
    var attachedConcept: ConceptDefinition? = nil
    var branchContextConcept: ConceptDefinition? = nil
    var generatedBranchTitle: String? = nil
    /// Hidden model context produced by `/compact`. The visible transcript remains untouched.
    var compactedContext: String? = nil
    /// Number of `activeChatBlocks` represented by `compactedContext`.
    /// Optional so conversations persisted before compaction support continue to decode.
    var compactedThroughBlockCount: Int? = nil
    /// Invisible product context attached to special entry points such as Question of the Day.
    var hiddenPromptContext: String? = nil

    init(
        id: UUID = UUID(),
        startingConcept: ConceptDefinition?,
        parentBranchID: UUID? = nil,
        parentResponseIndex: Int? = nil,
        duplicatedResponse: String? = nil,
        yOffset: CGFloat = 0,
        hiddenPromptContext: String? = nil
    ) {
        self.id = id
        self.startingConcept = startingConcept
        self.parentBranchID = parentBranchID
        self.parentResponseIndex = parentResponseIndex
        self.duplicatedResponse = duplicatedResponse
        self.yOffset = yOffset
        self.hiddenPromptContext = hiddenPromptContext
    }
}

/// A saved top-level conversation canvas. This is in-memory prototype persistence.
struct InquiryConversation: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String = "New Conversation"
    /// `true` for conversations that act as study topic containers.
    /// Study topics are distinct from regular conversations — they don't
    /// appear in Open Conversations and their detail view lists child
    /// conversations tagged with `studyTopicID`.
    /// Defaults to `false` so existing persisted data deserialises safely.
    var isStudyTopic: Bool = false
    /// Non-nil when this conversation lives inside a study topic.
    /// The value is the `id` of the parent topic (`InquiryConversation`).
    var studyTopicID: UUID? = nil
    /// Pinned conversations sort to the top of Recents and show a pin indicator.
    var isPinned: Bool = false
    var branches: [ChatBranch] = [ChatBranch(startingConcept: nil)]
    var promotedInsightIDs: [UUID] = []
    /// When this conversation was created — drives the "Date" filter's day-based grouping in
    /// Open Conversations. Defaults so existing persisted data without this field decodes safely.
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        isStudyTopic: Bool = false,
        studyTopicID: UUID? = nil,
        isPinned: Bool = false,
        branches: [ChatBranch] = [ChatBranch(startingConcept: nil)],
        promotedInsightIDs: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isStudyTopic = isStudyTopic
        self.studyTopicID = studyTopicID
        self.isPinned = isPinned
        self.branches = branches
        self.promotedInsightIDs = promotedInsightIDs
        self.createdAt = createdAt
    }
}

/// Atomic handoff from a Study Topic Insight Tree into one of that topic's conversations.
/// The origin is retained until the quoted Insight is either submitted or canceled.
struct StudyTopicInsightQuoteRequest: Identifiable, Equatable {
    let id: UUID
    let topicID: UUID
    let conversationID: UUID
    let insight: ConceptDefinition

    init(
        id: UUID = UUID(),
        topicID: UUID,
        conversationID: UUID,
        insight: ConceptDefinition
    ) {
        self.id = id
        self.topicID = topicID
        self.conversationID = conversationID
        self.insight = insight
    }
}

/// Requests reopening a Study Topic tree with a specific Insight selected.
struct StudyTopicTreeSelectionRequest: Identifiable, Equatable {
    let id: UUID
    let topicID: UUID
    let insightID: UUID

    init(id: UUID = UUID(), topicID: UUID, insightID: UUID) {
        self.id = id
        self.topicID = topicID
        self.insightID = insightID
    }
}

enum ChatBlock: Hashable, Codable {
    /// A model-generated response card.
    case text(String)

    /// A submitted user question, including any locked insight chip and uploaded files.
    case user(String, ConceptDefinition?, [UploadedFile])
}
