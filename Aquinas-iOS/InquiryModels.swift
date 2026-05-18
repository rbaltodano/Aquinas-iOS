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

    init(
        id: UUID = UUID(),
        startingConcept: ConceptDefinition?,
        parentBranchID: UUID? = nil,
        parentResponseIndex: Int? = nil,
        duplicatedResponse: String? = nil,
        yOffset: CGFloat = 0
    ) {
        self.id = id
        self.startingConcept = startingConcept
        self.parentBranchID = parentBranchID
        self.parentResponseIndex = parentResponseIndex
        self.duplicatedResponse = duplicatedResponse
        self.yOffset = yOffset
    }
}

/// A saved top-level conversation canvas. This is in-memory prototype persistence.
struct InquiryConversation: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String = "New Conversation"
    var branches: [ChatBranch] = [ChatBranch(startingConcept: nil)]

    init(id: UUID = UUID(), title: String = "New Conversation", branches: [ChatBranch] = [ChatBranch(startingConcept: nil)]) {
        self.id = id
        self.title = title
        self.branches = branches
    }
}

enum ChatBlock: Hashable, Codable {
    /// A model-generated response card.
    case text(String)

    /// A submitted user question, including any locked insight chip and uploaded files.
    case user(String, ConceptDefinition?, [UploadedFile])
}
