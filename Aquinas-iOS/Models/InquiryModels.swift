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
    /// The literal question text pinned as this branch's big header title (e.g. the Question of
    /// the Day prompt), permanently — independent of the conversation's own title, which can be
    /// renamed or auto-generated afterward without changing what's shown here.
    var pinnedHeaderQuestion: String? = nil
    /// Persisted user-facing approach summaries for completed model responses. Optional so
    /// conversations saved before this metadata existed continue to decode.
    var responsePresentations: [ResponsePresentationMetadata]? = nil

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

    func responsePresentation(at responseIndex: Int) -> ResponsePresentationMetadata? {
        responsePresentations?.first { $0.responseIndex == responseIndex }
    }

    mutating func setResponsePresentation(
        _ presentation: ResponsePresentationMetadata
    ) {
        var presentations = responsePresentations ?? []
        presentations.removeAll { $0.responseIndex == presentation.responseIndex }
        presentations.append(presentation)
        responsePresentations = presentations
    }

    mutating func removeResponsePresentation(at responseIndex: Int) {
        responsePresentations?.removeAll { $0.responseIndex == responseIndex }
        if responsePresentations?.isEmpty == true {
            responsePresentations = nil
        }
    }
}

struct ResponsePresentationMetadata: Codable, Equatable {
    let responseIndex: Int
    let showsThinking: Bool
    let thinkingSummary: [String]
    /// The passages retrieval actually supplied for this answer, kept so **Show Thinking** can
    /// list them again after the fact. Optional because synthesized `Codable` decoding fails on a
    /// missing key rather than falling back to a property's default value, so presentations
    /// persisted before this field existed would otherwise stop decoding.
    var groundingSources: [GroundingSourceSummary]? = nil
    /// A small provenance disclosure for ordinary no-source answers. Optional so saved
    /// conversations written before this existed continue to decode.
    var evidenceBasis: ResponseEvidenceBasis? = nil
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

/// Decides whether an otherwise new conversation contains user work worth retaining.
/// Empty drafts are intentionally ephemeral, but text, uploads, Insight context, and explicit
/// organization choices all make a conversation meaningful.
enum ConversationDraftRetention {
    /// A conversation started from a pinned prompt (Question of the Day, Today in History) that
    /// the user left before typing anything. The card that started it stays on Home, so the draft
    /// is recreated on demand rather than restored as a special empty-prompt conversation.
    static func isUntouchedPromptDraft(_ conversation: InquiryConversation) -> Bool {
        guard !conversation.isStudyTopic,
              conversation.studyTopicID == nil,
              !conversation.isPinned,
              conversation.promotedInsightIDs.isEmpty,
              conversation.branches.count == 1,
              let branch = conversation.branches.first,
              let pinned = branch.pinnedHeaderQuestion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pinned.isEmpty,
              conversation.title == pinned || conversation.title == "New Conversation" else {
            return false
        }
        return branch.parentBranchID == nil
            && branch.startingConcept == nil
            && branch.duplicatedResponse == nil
            && !branch.topQuestionSubmitted
            && branch.activeChatBlocks.isEmpty
            && branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && branch.topQuestionUploads.isEmpty
            && branch.bottomQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && branch.attachedConcept == nil
            && branch.branchContextConcept == nil
            && branch.compactedContext == nil
    }

    static func shouldKeep(
        _ conversation: InquiryConversation,
        transientAttachedConcept: ConceptDefinition? = nil,
        hasSavedInsights: Bool = false
    ) -> Bool {
        guard transientAttachedConcept == nil else { return true }
        if !hasSavedInsights, isUntouchedPromptDraft(conversation) { return false }
        guard !conversation.isStudyTopic,
              conversation.studyTopicID == nil,
              !conversation.isPinned,
              conversation.title == "New Conversation",
              conversation.promotedInsightIDs.isEmpty,
              !hasSavedInsights else {
            return true
        }

        return conversation.branches.contains { branch in
            branch.startingConcept != nil ||
            branch.duplicatedResponse?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            !branch.topQuestionUploads.isEmpty ||
            branch.bottomQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            branch.attachedConcept != nil ||
            branch.branchContextConcept != nil ||
            branch.compactedContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            branch.hiddenPromptContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            branch.pinnedHeaderQuestion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            branch.activeChatBlocks.contains(where: hasMeaningfulContent)
        }
    }

    private static func hasMeaningfulContent(_ block: ChatBlock) -> Bool {
        switch block {
        case .text(let text):
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .user(let text, let concept, let uploads):
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            concept != nil ||
            !uploads.isEmpty
        }
    }
}

/// Atomic handoff from an Insight Tree into an existing conversation. A Study Topic origin is
/// retained when present so canceling the quote can reopen that tree and restore its selection.
struct InsightConversationQuoteRequest: Identifiable, Equatable {
    let id: UUID
    let topicID: UUID?
    let conversationID: UUID
    let insight: ConceptDefinition

    init(
        id: UUID = UUID(),
        topicID: UUID? = nil,
        conversationID: UUID,
        insight: ConceptDefinition
    ) {
        self.id = id
        self.topicID = topicID
        self.conversationID = conversationID
        self.insight = insight
    }
}

/// Starts a fresh conversation with an Insight already attached to its composer.
struct NewConversationInsightQuoteRequest: Equatable {
    let insight: ConceptDefinition
    let topicID: UUID?

    init(insight: ConceptDefinition, topicID: UUID? = nil) {
        self.insight = insight
        self.topicID = topicID
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
