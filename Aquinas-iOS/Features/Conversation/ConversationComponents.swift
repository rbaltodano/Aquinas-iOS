//
//  ActiveInquiry.swift
//  Aquinas-iOS
//
//  Created by Ryan on 4/14/26.
//

import Foundation
import SwiftUI
import UIKit

private let questionCanceledResponseText = "Question canceled"

/// Keeps a model task current until its response actually begins revealing in the UI.
/// Backend completion alone is not the user-visible completion boundary.
@MainActor
private final class ResponseRevealGate {
    private(set) var hasStarted = false
    private var continuation: CheckedContinuation<Void, Never>?

    func markStarted() {
        guard !hasStarted else { return }
        hasStarted = true
        continuation?.resume()
        continuation = nil
    }

    func waitUntilStarted() async {
        guard !hasStarted, !Task.isCancelled else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !hasStarted, !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                self.continuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resumeWaiter()
            }
        }
    }

    private func resumeWaiter() {
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - Chat Thread Column

/// The actual vertical conversation: branch title, locked questions, model responses, and next input.
struct ChatThreadColumn: View {
    @Binding var branchData: ChatBranch
    let branchAnchor: String
    @Binding var targetSpawnY: CGFloat
    @Binding var uploadedFiles: [UploadedFile]
    let showsPendingUploads: Bool
    let quotedConcept: ConceptDefinition?
    @Binding var targetSpawnResponseIndex: Int?
    var externalSubmitTrigger: Int = 0
    var conversationFontSize: ConversationFontSizeOption = .large
    var inputTextAlignment: InputTextAlignmentOption = .center
    var inputFont: ConversationFontOption = .serif
    var responseTextAlignment: ResponseTextAlignmentOption = .center
    var responseFont: ConversationFontOption = .sans
    var personality: ConversationPersonality = .balanced
    var loadingInsightKey: String? = nil
    var queuedInsightKeys: Set<String> = []
    var savedInsightIDs: Set<UUID> = []
    let modelTasks: ModelTaskQueue
    /// True when another serialized model task is already running at submit time.
    var isModelBusy: Bool = false
    /// Prevents a restored queued draft from focusing its hidden UIKit editor while the user
    /// is browsing another page. The draft remains ready when they return.
    var isPageVisible: Bool = true
    var emptyStateUserName: String = "Ryan"
    var emptyStateEyebrow: String = ""
    /// Height available above the bottom model controls. The pristine new-conversation
    /// prompt uses this to center its heading and composer as one unit.
    var newConversationViewportHeight: CGFloat = 0
    /// The conversation's study topic name, if it belongs to one — takes priority over
    /// `emptyStateEyebrow` in the header eyebrow, and makes it tappable to change the topic.
    var studyTopicTitle: String? = nil
    var onTapEyebrow: () -> Void = {}
    var emptyStatePromptQuestion: String = ""
    var showsThinkingIntro: Bool = true
    /// Live conversation title, shown as the root branch's heading (updates on rename).
    var conversationTitle: String = ""
    var onSpawnYChange: (Int, CGFloat) -> Void
    var onDuplicateResponse: (String, Int) -> Void
    var onDeleteBranch: () -> Void
    var onConversationTitleChange: (String) -> Void
    var onTopInputFocused: () -> Void = {}
    var onTopQuestionSubmitted: () -> Void = {}
    var onBottomInputFocused: () -> Void
    var onActiveInputTextChange: (String) -> Void = { _ in }
    /// Incremented by the parent to request inserting `commandToInsert` into whichever
    /// question field is currently focused (used by the slash-command picker).
    var insertCommandRequest: Int = 0
    var commandToInsert: String = ""
    var showsSlashCommandMenu: Bool = false
    var slashCommandQuery: SlashCommandQuery? = nil
    var onSelectSlashCommand: (SlashCommand) -> Void = { _ in }
    var onExecuteSlashCommand: (SlashCommandInvocation) -> Void = { _ in }
    var onQuoteHandled: () -> Void
    var onQuotedConceptRemoved: () -> Void = {}
    var onQuotedConceptSubmitted: () -> Void = {}
    var onQuotedConceptTap: (ConceptDefinition) -> Void = { _ in }
    var connectionConcepts: [ConceptDefinition]? = nil
    var onConnectionHandled: (() -> Void)? = nil
    var onResponseGenerated: (Int) -> Void = { _ in }
    var onResponseCompleted: (Int) -> Void = { _ in }
    var onResponseStarted: () -> Void = {}
    var onResponseCancelled: () -> Void = {}
    var onInsightTap: (String, String) -> Void = { _, _ in }
    var onInlineInsightQuote: (ConceptDefinition) -> Void = { _ in }
    var onInlineInsightFork: (ConceptDefinition, Int) -> Void = { _, _ in }
    var onInlineInsightToggleSaved: (ConceptDefinition) -> Void = { _ in }

    private var modelResponseLineHeight: CGFloat {
        let fontName = responseFont == .sans
            ? "Figtree-Regular"
            : "LibreBaskerville-Regular"
        let font = UIFont(name: fontName, size: conversationFontSize.pointSize)
            ?? .systemFont(ofSize: conversationFontSize.pointSize)
        return ceil(font.lineHeight + 8)
    }

    private func funStatusText(for responseIndex: Int) -> String? {
        modelTasks.allTasks.first { task in
            guard case .userQuestion(let branchID, let taskResponseIndex) = task.kind else {
                return false
            }
            return branchID == branchData.id && taskResponseIndex == responseIndex
        }?.funStatusText
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aquinasModel) private var aquinasModel

    @State private var branchHeadHeight: CGFloat = 0
    @State private var animatedResponseIndices: Set<Int> = []
    @State private var pendingResponseIndices: Set<Int> = []
    @State private var streamingResponseIndices: Set<Int> = []
    @State private var modelQueuedResponseIndices: Set<Int> = []
    @State private var responseThinkingIntroByIndex: [Int: Bool] = [:]
    @State private var responseThinkingSummaryByIndex: [Int: [String]] = [:]
    @State private var responseRevealGatesByIndex: [Int: ResponseRevealGate] = [:]
    @State private var pendingGeneratedTitleQuestion: String? = nil
    @State private var localConnectionConcepts: [ConceptDefinition]?
    @Namespace private var quotedContextChipNamespace
    @FocusState private var isTopQuestionFocused: Bool
    @FocusState private var isBottomQuestionFocused: Bool
    /// Tracks UITextView buffer emptiness for placeholder visibility (not tied to binding).
    @State private var topFieldIsEmpty: Bool = true
    @State private var bottomFieldIsEmpty: Bool = true
    /// Relay references for reading live UITextView text at submit time without
    /// requiring per-keystroke binding writes (which would re-render the whole tree).
    @State private var topFieldRelay = TextInputRelay()
    @State private var bottomFieldRelay = TextInputRelay()
    /// Which question field last became focused — the target for command insertion.
    @State private var bottomFieldIsActive = false
    /// Measured single-line width of the submitted top-question text, captured once at submit
    /// time (not live per-keystroke) — lets `QuestionInputField` hug it afterward, if it fits on
    /// one line. Shared by whichever top-field variant is showing (they're mutually exclusive).
    @State private var topFieldSubmittedWidth: CGFloat = 0
    /// Manually crossfaded copy of `eyebrowDisplayText` — driven by `withAnimation` directly
    /// rather than `.id()` + `.transition()`, which doesn't reliably fire here (the Text sits
    /// inside a Button's label, and Button appears to swallow the transition on its content).
    @State private var displayedEyebrowText: String = ""
    @State private var isEyebrowTextHidden = false
    /// Inline rename of the big conversation title shown at the top of the root branch's VStack.
    @State private var isEditingBigTitle = false
    @State private var bigTitleDraft = ""
    @FocusState private var isBigTitleFocused: Bool

    /// Placeholder text color resolved directly from the SwiftUI color-scheme environment,
    /// bypassing the Color(UIColor(dynamicProvider:)) conversion which can freeze to the
    /// light-mode value inside UIViewRepresentable-hosted view hierarchies.
    private var placeholderColor: Color {
        colorScheme == .dark
            ? Color(hex: 0xFFFAF0, alpha: 0.50)
            : Color(hex: 0x4A321C, alpha: 0.50)
    }

    @ViewBuilder
    private func slashCommandMenuOverlay(forBottomField: Bool, yOffset: CGFloat) -> some View {
        if showsSlashCommandMenu,
           bottomFieldIsActive == forBottomField,
           let slashCommandQuery {
            SlashCommandMenu(query: slashCommandQuery, maxHeight: nil, onSelect: onSelectSlashCommand)
                .fixedSize(horizontal: false, vertical: true)
                .offset(y: yOffset)
                .zIndex(50)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    let chatBubbleColor = AquinasTheme.Colors.background
    private var bottomInputAnchor: String {
        "bottom-input-anchor-\(branchData.id)"
    }

    // MARK: Editable Thread Values=
    // readingTopPadding controls how far the branch title sits from the top in Branch mode.
    private let readingTopPadding: CGFloat = 30

    // Branch title shown above the first question.
    private var displayBranchTitle: String {
        // The root branch's heading mirrors the live conversation title, so renaming the
        // conversation (or its auto-generated title) updates this in place. Child branches keep
        // their own generated branch title.
        if branchData.parentBranchID == nil {
            let title = conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "New Conversation" : title
        }
        return branchData.generatedBranchTitle ?? "New Branch"
    }

    // Pending uploads only appear in the focused branch.
    private var visibleUploads: [UploadedFile] {
        showsPendingUploads ? uploadedFiles : []
    }

    // Title for a branch forked from an existing response.
    private var branchResponseTitle: String? {
        guard let response = branchData.duplicatedResponse else {
            return nil
        }
        return generatedContextTitle(from: response)
    }

    private var branchKeyword: String? {
        nil
    }

    private var usesNewConversationPromptHeader: Bool {
        branchData.parentBranchID == nil
            && branchData.startingConcept == nil
            && branchData.duplicatedResponse == nil
    }

    private var usesOnlyNewConversationPrompt: Bool {
        usesNewConversationPromptHeader
            && !branchData.topQuestionSubmitted
            && branchData.activeChatBlocks.isEmpty
            && !branchData.showBottomInput
            && visibleUploads.isEmpty
            && quotedConcept == nil
            && localConnectionConcepts == nil
    }

    private var emptyPromptName: String {
        let trimmedName = emptyStateUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Ryan" : trimmedName
    }

    private var trimmedEmptyStateEyebrow: String {
        emptyStateEyebrow.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var eyebrowDisplayText: String {
        if let studyTopicTitle {
            let trimmed = studyTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed.uppercased() }
        }
        // "Question of the Day" conversations get the same "add to study topic" eyebrow as
        // any other new conversation — no separate eyebrow copy for that state.
        return "ADD TO STUDY TOPIC"
    }

    private var emptyPromptQuestion: String {
        let trimmedQuestion = emptyStatePromptQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedQuestion.isEmpty ? "What Should We Study Today \(emptyPromptName)?" : trimmedQuestion
    }

    private var isQuestionOfTheDayPrompt: Bool {
        trimmedEmptyStateEyebrow.caseInsensitiveCompare("QUESTION OF THE DAY") == .orderedSame
    }

    private var newConversationHeaderTitle: String {
        if !isQuestionOfTheDayPrompt, branchData.generatedBranchTitle != nil {
            return displayBranchTitle
        }
        return emptyPromptQuestion
    }

    // Temporary local title generator. Replace with the model summary later.
    private func generatedTitle(from question: String) -> String {
        let words = question
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .split(separator: " ")
            .prefix(5)
            .map { String($0).capitalized }

        guard !words.isEmpty else {
            return "New Inquiry"
        }

        return words.joined(separator: " ")
    }

    // Temporary branch-chip title generator for response forks.
    private func generatedContextTitle(from response: String) -> String {
        let stopWords: Set<String> = ["the", "a", "an", "and", "or", "but", "is", "are", "was", "were", "of", "to", "in", "for", "with", "as", "on"]
        let words = response
            .replacingOccurrences(of: "[^A-Za-z0-9\\s]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map { String($0) }
            .filter { !stopWords.contains($0.lowercased()) }
            .prefix(3)
            .map { $0.capitalized }

        guard !words.isEmpty else {
            return "Response Branch"
        }

        return words.joined(separator: " ")
    }

    // Routes through BackendAquinasModel for structured prose and tappable key terms.
    private func appendSimulatedResponse(
        connectionConcepts: [ConceptDefinition]? = nil,
        restoreQueuedQuestion: @escaping () -> Void
    ) {
        let context = ConversationContext(
            compactedContext: branchData.compactedContext,
            transcript: modelTranscriptForResponse(
                connectionConcepts: connectionConcepts
            ),
            personality: personality
        )
        let responseIndex = branchData.activeChatBlocks.count
        let thinkingEnabled = showsThinkingIntro
        let revealGate = ResponseRevealGate()

        animatedResponseIndices.insert(responseIndex)
        pendingResponseIndices.insert(responseIndex)
        responseRevealGatesByIndex[responseIndex] = revealGate
        if isModelBusy || !pendingResponseIndices.subtracting([responseIndex]).isEmpty {
            modelQueuedResponseIndices.insert(responseIndex)
        }
        responseThinkingIntroByIndex[responseIndex] = thinkingEnabled
        onResponseStarted()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            branchData.activeChatBlocks.append(.text(""))
        }

        modelTasks.enqueue(
            kind: .userQuestion(
                branchID: branchData.id,
                responseIndex: responseIndex
            ),
            originPage: .conversation,
            onStart: {
                _ = withAnimation(.easeInOut(duration: 0.25)) {
                    modelQueuedResponseIndices.remove(responseIndex)
                }
            },
            onCancel: {
                cancelResponse(
                    at: responseIndex,
                    restoreQueuedQuestion: restoreQueuedQuestion
                )
            }
        ) {
            let response = await aquinasModel.respond(
                to: context,
                thinkingEnabled: thinkingEnabled
            ) { update in
                guard !Task.isCancelled,
                      branchData.activeChatBlocks.indices.contains(responseIndex) else {
                    return
                }
                _ = withAnimation(.easeInOut(duration: 0.25)) {
                    modelQueuedResponseIndices.remove(responseIndex)
                }
                switch update {
                case .generationStarted:
                    break
                case .thinkingSummary(let summary):
                    responseThinkingSummaryByIndex[responseIndex] = summary
                case .responseText(let streamedText):
                    // Keep the network stream buffered until the backend returns the
                    // fully annotated response. This prevents unannotated text from
                    // flashing before its Insight links are ready, while still letting
                    // the thinking UI transition to "Writing response...".
                    guard !streamedText.isEmpty else { return }
                    streamingResponseIndices.insert(responseIndex)
                }
            }
            guard !Task.isCancelled,
                  branchData.activeChatBlocks.indices.contains(responseIndex) else {
                return
            }
            modelQueuedResponseIndices.remove(responseIndex)
            responseThinkingSummaryByIndex[responseIndex] = thinkingEnabled
                ? response.thinkingSummary
                : []
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                branchData.activeChatBlocks[responseIndex] = .text(response.annotatedText)
                pendingResponseIndices.remove(responseIndex)
                streamingResponseIndices.remove(responseIndex)
                // The composer is functional state, so it must not depend on the
                // response's ornamental word/underline animation completing without
                // cancellation. The response reserves its final height while animating.
                branchData.showBottomInput = true
            }
            onResponseGenerated(responseIndex)
            if response.annotatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                revealGate.markStarted()
            }
            await revealGate.waitUntilStarted()
            responseRevealGatesByIndex.removeValue(forKey: responseIndex)
        }
    }

    private func cancelResponse(
        at responseIndex: Int,
        restoreQueuedQuestion: () -> Void
    ) {
        // Upcoming questions keep the existing draft-restoration behavior. Once a question
        // is current, cancellation leaves a durable transcript marker and opens a fresh composer.
        let wasStillQueued = modelQueuedResponseIndices.contains(responseIndex)
        responseRevealGatesByIndex.removeValue(forKey: responseIndex)
        modelQueuedResponseIndices.remove(responseIndex)
        pendingResponseIndices.remove(responseIndex)
        streamingResponseIndices.remove(responseIndex)
        responseThinkingIntroByIndex.removeValue(forKey: responseIndex)
        responseThinkingSummaryByIndex.removeValue(forKey: responseIndex)

        guard branchData.activeChatBlocks.indices.contains(responseIndex) else {
            if wasStillQueued {
                restoreQueuedQuestion()
            } else {
                showFollowUpComposerAfterCancellation()
            }
            onResponseCancelled()
            return
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
            if wasStillQueued {
                if responseIndex == branchData.activeChatBlocks.count - 1 {
                    branchData.activeChatBlocks.removeLast()
                } else {
                    branchData.activeChatBlocks[responseIndex] = .text("Response stopped.")
                }
            } else {
                animatedResponseIndices.remove(responseIndex)
                responseThinkingIntroByIndex[responseIndex] = false
                branchData.activeChatBlocks[responseIndex] = .text(questionCanceledResponseText)
                branchData.showBottomInput = true
            }
        }
        if wasStillQueued {
            restoreQueuedQuestion()
        } else {
            showFollowUpComposerAfterCancellation()
            finalizePendingGeneratedTitleIfNeeded()
        }
        onResponseCancelled()
    }

    private func showFollowUpComposerAfterCancellation() {
        bottomFieldIsEmpty = true
        branchData.bottomQuestionText = ""
        branchData.showBottomInput = true
        bottomFieldRelay.replaceAll("")
        onActiveInputTextChange("")
    }

    private func restoreQueuedTopQuestion(
        _ question: String,
        uploads: [UploadedFile]
    ) {
        pendingGeneratedTitleQuestion = nil
        topFieldSubmittedWidth = 0
        topFieldIsEmpty = question.isEmpty
        if showsPendingUploads {
            uploadedFiles = uploads
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
            branchData.topQuestionText = question
            branchData.topQuestionUploads = []
            branchData.topQuestionSubmitted = false
        }
        onActiveInputTextChange(question)

        guard isPageVisible else { return }
        Task { @MainActor in
            await Task.yield()
            topFieldRelay.replaceAll(question)
            bottomFieldIsActive = false
            isBottomQuestionFocused = false
            isTopQuestionFocused = true
            topFieldRelay.focus()
        }
    }

    private func restoreQueuedBottomQuestion(
        _ question: String,
        quotedConcept: ConceptDefinition?,
        uploads: [UploadedFile],
        connectionConcepts: [ConceptDefinition]?
    ) {
        if showsPendingUploads {
            uploadedFiles = uploads
        }
        bottomFieldIsEmpty = question.isEmpty

        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
            if case .user(let text, _, _) = branchData.activeChatBlocks.last,
               text == question {
                branchData.activeChatBlocks.removeLast()
            }
            branchData.bottomQuestionText = question
            branchData.attachedConcept = quotedConcept
            localConnectionConcepts = connectionConcepts
            branchData.showBottomInput = true
        }
        onActiveInputTextChange(question)

        guard isPageVisible else { return }
        Task { @MainActor in
            await Task.yield()
            bottomFieldRelay.replaceAll(question)
            bottomFieldIsActive = true
            isTopQuestionFocused = false
            isBottomQuestionFocused = true
            bottomFieldRelay.focus()
        }
    }

    private func modelTranscriptForResponse(
        connectionConcepts: [ConceptDefinition]? = nil
    ) -> [ChatBlock] {
        var transcript: [ChatBlock] = []
        if let hiddenPromptContext = branchData.hiddenPromptContext?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !hiddenPromptContext.isEmpty {
            transcript.append(.user(hiddenPromptContext, nil, []))
        }
        if branchData.compactedContext == nil {
            let topQuestion = branchData.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if branchData.topQuestionSubmitted, !topQuestion.isEmpty {
                transcript.append(.user(topQuestion, branchData.branchContextConcept, branchData.topQuestionUploads))
            }
        }
        let compactedBlockCount = min(
            branchData.compactedThroughBlockCount ?? 0,
            branchData.activeChatBlocks.count
        )
        transcript.append(
            contentsOf: branchData.activeChatBlocks
                .dropFirst(compactedBlockCount)
                .filter { block in
                    guard case .text(let text) = block else { return true }
                    return text != questionCanceledResponseText
                }
        )
        if let connectionConcepts,
           connectionConcepts.count >= 2,
           let userIndex = transcript.lastIndex(where: { block in
               if case .user = block { return true }
               return false
           }),
           case .user(let question, let concept, let uploads) = transcript[userIndex] {
            transcript[userIndex] = .user(
                connectionInquiryPrompt(
                    concepts: connectionConcepts,
                    question: question
                ),
                concept,
                uploads
            )
        }
        return transcript
    }

    private func connectionInquiryPrompt(
        concepts: [ConceptDefinition],
        question: String
    ) -> String {
        let conceptLines = concepts.map { concept in
            let title = concept.word.replacingOccurrences(of: "<", with: "‹")
            let definition = concept.semanticDefinition
                .replacingOccurrences(of: "<", with: "‹")
            return "- \(title): \(definition)"
        }
        return """
        <inquire_connection>
        Selected concepts:
        \(conceptLines.joined(separator: "\n"))
        </inquire_connection>

        User's connection inquiry:
        \(question)
        """
    }

    private func responseShowsThinkingIntro(at index: Int, text: String) -> Bool {
        guard text != questionCanceledResponseText else { return false }
        return responseThinkingIntroByIndex[index] ?? true
    }

    private func responseThinkingSummary(at index: Int) -> [String] {
        responseThinkingSummaryByIndex[index] ?? []
    }

    private func quotedConceptMatchID(
        _ conceptID: UUID,
        responseIndex: Int
    ) -> String {
        "\(branchData.id)-quoted-concept-\(responseIndex)-\(conceptID)"
    }

    private func finalizePendingGeneratedTitleIfNeeded() {
        guard branchData.generatedBranchTitle == nil,
              let pendingQuestion = pendingGeneratedTitleQuestion else { return }
        let title = generatedTitle(from: pendingQuestion)
        pendingGeneratedTitleQuestion = nil
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            branchData.generatedBranchTitle = title
        }
        if branchData.parentBranchID == nil {
            onConversationTitleChange(title)
        }
    }

    /// Matches the Open Conversations search bar's chrome (canvas fill, 12pt radius, the same
    /// hairline border) — but hugs the text field's own height instead of the search bar's fixed
    /// 52pt, since the question field grows with wrapped/multi-line text.
    private func inputContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AquinasTheme.Colors.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AquinasTheme.Colors.sideMenuSearchBorder, lineWidth: 1)
            )
    }

    // Locks the first branch question, uploads, and context chip.
    private func submitTopQuestionIfNeeded() {
        // Flush the UITextView's live buffer into the binding synchronously.
        // Because we stopped per-keystroke binding writes, the relay is the only
        // way to read text that was typed but not yet blurred.
        branchData.topQuestionText = topFieldRelay.currentText()
        let submittedQuestion = branchData.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let command = SlashCommand.invocation(for: submittedQuestion) {
            topFieldRelay.replaceAll("")
            branchData.topQuestionText = ""
            topFieldIsEmpty = true
            onActiveInputTextChange("")
            onExecuteSlashCommand(command)
            return
        }
        guard !submittedQuestion.isEmpty, !branchData.topQuestionSubmitted else {
            branchData.topQuestionText = submittedQuestion
            return
        }

        let submittedUploads = visibleUploads
        branchData.topQuestionText = submittedQuestion
        branchData.topQuestionUploads = submittedUploads
        if showsPendingUploads {
            uploadedFiles.removeAll()
        }
        pendingGeneratedTitleQuestion = submittedQuestion
        topFieldSubmittedWidth = QuestionInputField.measuredWidth(for: submittedQuestion)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            branchData.topQuestionSubmitted = true
        }
        onTopQuestionSubmitted()
        appendSimulatedResponse {
            restoreQueuedTopQuestion(
                submittedQuestion,
                uploads: submittedUploads
            )
        }
    }

    // Adds a follow-up question lower in the thread and locks its attachments/context.
    private func submitBottomQuestionIfNeeded() {
        // Flush live UITextView text to binding before reading (relay avoids per-keystroke writes).
        branchData.bottomQuestionText = bottomFieldRelay.currentText()
        let submittedQuestion = branchData.bottomQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let command = SlashCommand.invocation(for: submittedQuestion) {
            bottomFieldRelay.replaceAll("")
            branchData.bottomQuestionText = ""
            bottomFieldIsEmpty = true
            onActiveInputTextChange("")
            onExecuteSlashCommand(command)
            return
        }
        guard !submittedQuestion.isEmpty else {
            branchData.bottomQuestionText = submittedQuestion
            return
        }

        let quotedConcept = branchData.attachedConcept
        let submittedUploads = visibleUploads
        let submittedConnectionConcepts = localConnectionConcepts
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            branchData.showBottomInput = false
            branchData.activeChatBlocks.append(.user(submittedQuestion, quotedConcept, submittedUploads))
        }
        if quotedConcept != nil {
            onQuotedConceptSubmitted()
        }
        if showsPendingUploads {
            uploadedFiles.removeAll()
        }
        branchData.attachedConcept = nil
        localConnectionConcepts = nil
        branchData.bottomQuestionText = ""
        appendSimulatedResponse(connectionConcepts: submittedConnectionConcepts) {
            restoreQueuedBottomQuestion(
                submittedQuestion,
                quotedConcept: quotedConcept,
                uploads: submittedUploads,
                connectionConcepts: submittedConnectionConcepts
            )
        }
    }

    private var newConversationPromptHeader: some View {
        VStack(alignment: .center, spacing: 48) {
            VStack(alignment: .center, spacing: 8) {
                Button(action: onTapEyebrow) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack")
                            .font(AquinasTheme.Typography.uiLabel)
                        Text(displayedEyebrowText)
                            .font(AquinasTheme.Typography.uiLabel)
                            .opacity(isEyebrowTextHidden ? 0 : 1)
                            .blur(radius: isEyebrowTextHidden ? 4 : 0)
                    }
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.plain)
                .onAppear { displayedEyebrowText = eyebrowDisplayText }
                .onChange(of: eyebrowDisplayText) { _, newValue in
                    withAnimation(.easeIn(duration: 0.2)) {
                        isEyebrowTextHidden = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        // Animate the text swap together with the reveal, so the icon
                        // (repositioned by the HStack re-centering on the new width)
                        // glides into place instead of snapping.
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            displayedEyebrowText = newValue
                            isEyebrowTextHidden = false
                        }
                    }
                }

                if isEditingBigTitle {
                    TextField("Conversation title", text: $bigTitleDraft, axis: .vertical)
                        .font(.custom("LibreBaskerville-Regular", size: 28))
                        .foregroundColor(AquinasTheme.Colors.headingText)
                        .lineSpacing(14)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fixedSize(horizontal: false, vertical: true)
                        .focused($isBigTitleFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isEditingBigTitle = false
                            onConversationTitleChange(bigTitleDraft)
                        }
                } else {
                    Text(newConversationHeaderTitle)
                        .font(.custom("LibreBaskerville-Regular", size: 28))
                        .foregroundColor(AquinasTheme.Colors.headingText)
                        .lineSpacing(14)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .id(newConversationHeaderTitle)
                        .transition(.blurredTitleReplacement)
                        .onTapGesture {
                            bigTitleDraft = newConversationHeaderTitle
                            isEditingBigTitle = true
                            isBigTitleFocused = true
                        }
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var newConversationQuestionField: some View {
        VStack(spacing: 12) {
            QuestionInputField(
                placeholder: "Ask a question...",
                text: $branchData.topQuestionText,
                isLocked: branchData.topQuestionSubmitted,
                isSubmitted: branchData.topQuestionSubmitted,
                submittedWidth: topFieldSubmittedWidth,
                isEmpty: topFieldIsEmpty && !branchData.topQuestionSubmitted,
                isFocused: isTopQuestionFocused && !branchData.topQuestionSubmitted,
                lineHeight: modelResponseLineHeight,
                showsChrome: false,
                relay: topFieldRelay,
                onFocusChange: { focused in
                    isTopQuestionFocused = focused
                    if focused {
                        bottomFieldIsActive = false
                        isBottomQuestionFocused = false
                        onTopInputFocused()
                    }
                },
                onTextChange: { text in
                    topFieldIsEmpty = text.isEmpty
                    onActiveInputTextChange(text)
                },
                onSubmit: {
                    submitTopQuestionIfNeeded()
                },
                onTapToFocus: {
                    guard !branchData.topQuestionSubmitted else { return }
                    bottomFieldIsActive = false
                    isTopQuestionFocused = true
                    isBottomQuestionFocused = false
                    topFieldRelay.focus()
                }
            )
            .overlay(alignment: .top) {
                slashCommandMenuOverlay(forBottomField: false, yOffset: 34)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .zIndex(showsSlashCommandMenu && !bottomFieldIsActive ? 50 : 0)
    }

    var body: some View {
        Group {
            if usesOnlyNewConversationPrompt {
                ZStack(alignment: .top) {
                    Color.clear
                        .frame(height: 1)
                        .id(branchAnchor)

                    VStack(alignment: .center, spacing: 48) {
                        newConversationPromptHeader

                        newConversationQuestionField
                            .id("top-input-anchor-\(branchData.id)")
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: max(newConversationViewportHeight, 1),
                        alignment: .center
                    )
                }
            } else {
                VStack(alignment: .center, spacing: 48) {
            // MARK: Branch Header
            // Cross, branch title, starting context chip, and the first editable/locked question.
            Color.clear
                .frame(height: 1)
                .id(branchAnchor)

            VStack(spacing: 18) {
                if usesNewConversationPromptHeader {
                    newConversationPromptHeader
                } else {
                    VStack(spacing: 16) {
                        Image("cross-1")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundColor(AquinasTheme.Colors.accent)

                        if let branchKeyword {
                            Text(createEditorialTitle(
                                fullText: displayBranchTitle,
                                keyword: branchKeyword,
                                fontSize: 34,
                                baseColor: AquinasTheme.Colors.primaryReadable,
                                keywordColor: AquinasTheme.Colors.linkGreen
                            ))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        } else {
                            Text(displayBranchTitle)
                                .font(.custom("LibreBaskerville-Regular", size: 34))
                                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .id(displayBranchTitle)
                                .transition(.blurredTitleReplacement)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                UploadedFileStrip(
                    files: branchData.topQuestionSubmitted ? branchData.topQuestionUploads : visibleUploads,
                    onRemove: branchData.topQuestionSubmitted ? nil : { file in
                        uploadedFiles.removeAll { $0.id == file.id }
                    }
                )

                if let concept = branchData.branchContextConcept {
                    BranchContextChip(
                        title: concept.word.capitalized,
                        icon: branchData.topQuestionSubmitted ? "text.bubble.fill" : "text.bubble",
                        animationKey: branchData.topQuestionSubmitted ? "submitted" : "pending",
                        isFilled: branchData.topQuestionSubmitted,
                        appearDelay: 0.25,
                        showRemove: branchData.parentBranchID != nil && !branchData.topQuestionSubmitted,
                        onTap: { onQuotedConceptTap(concept) },
                        onRemove: onDeleteBranch
                    )
                    .matchedGeometryEffect(
                        id: quotedConceptMatchID(concept.id, responseIndex: 0),
                        in: quotedContextChipNamespace
                    )
                } else if let branchResponseTitle {
                    BranchContextChip(
                        title: branchResponseTitle,
                        icon: "arrow.triangle.branch",
                        animationKey: branchData.topQuestionSubmitted ? "submitted" : "pending",
                        isFilled: branchData.topQuestionSubmitted,
                        appearDelay: 0.25,
                        showRemove: branchData.parentBranchID != nil && !branchData.topQuestionSubmitted,
                        onRemove: onDeleteBranch
                    )
                }

                Group {
                    if usesNewConversationPromptHeader {
                        newConversationQuestionField
                    } else {
                        VStack(spacing: 12) {
                            QuestionInputField(
                                placeholder: "Ask a question...",
                                text: $branchData.topQuestionText,
                                isLocked: branchData.topQuestionSubmitted,
                                isSubmitted: branchData.topQuestionSubmitted,
                                submittedWidth: topFieldSubmittedWidth,
                                isEmpty: topFieldIsEmpty && !branchData.topQuestionSubmitted,
                                isFocused: isTopQuestionFocused && !branchData.topQuestionSubmitted,
                                lineHeight: modelResponseLineHeight,
                                placeholderColor: placeholderColor,
                                relay: topFieldRelay,
                                onFocusChange: { focused in
                                    isTopQuestionFocused = focused
                                    if focused {
                                        bottomFieldIsActive = false
                                        isBottomQuestionFocused = false
                                        onTopInputFocused()
                                    }
                                },
                                onTextChange: { text in
                                    topFieldIsEmpty = text.isEmpty
                                    onActiveInputTextChange(text)
                                },
                                onSubmit: {
                                    submitTopQuestionIfNeeded()
                                },
                                onTapToFocus: {
                                    guard !branchData.topQuestionSubmitted else { return }
                                    bottomFieldIsActive = false
                                    isTopQuestionFocused = true
                                    isBottomQuestionFocused = false
                                    topFieldRelay.focus()
                                }
                            )
                            .overlay(alignment: .top) {
                                slashCommandMenuOverlay(forBottomField: false, yOffset: 72)
                            }
                        }
                    }
                }
                .id("top-input-anchor-\(branchData.id)")

                if branchData.topQuestionSubmitted {
                    ConversationSeparator()
                        .padding(.top, 30)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                }
            }
            .frame(maxWidth: .infinity)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            branchHeadHeight = geo.size.height
                        }
                        .onChange(of: geo.size.height) { oldValue, newValue in
                            branchHeadHeight = newValue
                        }
                }
            )
            .padding(.top, usesNewConversationPromptHeader ? 84 : readingTopPadding)

            // MARK: Conversation Blocks
            // Alternates between user questions and model response cards.
            VStack(alignment: .center, spacing: 48) {
                ForEach(Array(branchData.activeChatBlocks.enumerated()), id: \.offset) { index, block in
                    switch block {
                    case .text(let textContent):
                        VStack(spacing: 16) {
                            TrackedResponseCard(
                                textContent: textContent,
                                responseIndex: index,
                                shouldAnimateOnAppear: animatedResponseIndices.contains(index),
                                showsThinkingIntro: responseShowsThinkingIntro(at: index, text: textContent),
                                isAwaitingResponse: pendingResponseIndices.contains(index),
                                isReceivingStream: streamingResponseIndices.contains(index),
                                isQueuedForModel: modelQueuedResponseIndices.contains(index),
                                usesNetworkStream: false,
                                thinkingSummary: responseThinkingSummary(at: index),
                                funStatusText: funStatusText(for: index),
                                targetSpawnY: $targetSpawnY,
                                targetSpawnResponseIndex: $targetSpawnResponseIndex,
                                columnSpaceName: "ColumnContent-\(branchData.id)",
                                responseTextAlignment: responseTextAlignment,
                                responseFont: responseFont,
                                conversationFontSize: conversationFontSize,
                                loadingInsightKey: loadingInsightKey,
                                queuedInsightKeys: queuedInsightKeys,
                                savedInsightIDs: savedInsightIDs,
                                onCenterChange: onSpawnYChange,
                                onDuplicateBranch: {
                                    onDuplicateResponse(textContent, index)
                                },
                                onInsightTap: onInsightTap,
                                onInlineInsightQuote: onInlineInsightQuote,
                                onInlineInsightFork: { insight in
                                    onInlineInsightFork(insight, index)
                                },
                                onInlineInsightToggleSaved: onInlineInsightToggleSaved,
                                showsResponseActions: textContent != questionCanceledResponseText,
                                onRevealStart: {
                                    responseRevealGatesByIndex[index]?.markStarted()
                                },
                                onFinish: {
                                    animatedResponseIndices.remove(index)
                                    finalizePendingGeneratedTitleIfNeeded()
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { branchData.showBottomInput = true }
                                    onResponseCompleted(index)
                                }
                            )
                            .id(
                                "\(branchData.id)-response-\(index)-"
                                    + (textContent == questionCanceledResponseText ? "canceled" : "standard")
                            )
                        }
                        .transition(
                            animatedResponseIndices.contains(index)
                            ? .opacity.combined(with: .scale(scale: 0.5))
                            : .identity
                        )

                    case .user(let questionText, let concept, let attachments):
                        VStack(spacing: 48) {
                            ConversationSeparator()

                            VStack(spacing: 16) {
                                UploadedFileStrip(files: attachments)

                                if let concept {
                                    BranchContextChip(
                                        title: concept.word.capitalized,
                                        icon: "text.bubble.fill",
                                        isFilled: true,
                                        animatesAppearance: false,
                                        showRemove: false,
                                        onTap: { onQuotedConceptTap(concept) }
                                    )
                                    .matchedGeometryEffect(
                                        id: quotedConceptMatchID(
                                            concept.id,
                                            responseIndex: index + 1
                                        ),
                                        in: quotedContextChipNamespace
                                    )
                                }

                                // Same component the top field uses post-submit (locked,
                                // isSubmitted), not a plain Text — so a follow-up question
                                // renders and behaves identically to the branch's first question.
                                QuestionInputField(
                                    placeholder: "",
                                    text: .constant(questionText),
                                    isLocked: true,
                                    isSubmitted: true,
                                    submittedWidth: QuestionInputField.measuredWidth(for: questionText),
                                    isEmpty: false,
                                    isFocused: false,
                                    lineHeight: modelResponseLineHeight,
                                    showsChrome: false,
                                    relay: TextInputRelay(),
                                    onFocusChange: { _ in },
                                    onTextChange: { _ in }
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            // MARK: Follow-up Input
            // Appears after the latest model response finishes.
            if branchData.showBottomInput {
                VStack(spacing: 48) {
                    ConversationSeparator()

                    VStack(spacing: 16) {
                        UploadedFileStrip(files: visibleUploads) { file in
                            uploadedFiles.removeAll { $0.id == file.id }
                        }

                        if let concept = branchData.attachedConcept {
                            BranchContextChip(
                                title: concept.word.capitalized,
                                icon: "text.bubble",
                                isFilled: false,
                                showRemove: true,
                                onTap: { onQuotedConceptTap(concept) },
                                onRemove: {
                                    withAnimation {
                                        branchData.attachedConcept = nil
                                    }
                                    onQuotedConceptRemoved()
                                }
                            )
                            .matchedGeometryEffect(
                                id: quotedConceptMatchID(
                                    concept.id,
                                    responseIndex:
                                        branchData.activeChatBlocks.count + 1
                                ),
                                in: quotedContextChipNamespace
                            )
                            .transition(.scale.combined(with: .opacity))
                        }

                        if let concepts = localConnectionConcepts {
                            ConnectionContextChip(
                                concepts: concepts,
                                onRemove: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        localConnectionConcepts = nil
                                    }
                                }
                            )
                            .transition(.scale.combined(with: .opacity))
                        }

                        VStack(spacing: 12) {
                            QuestionInputField(
                                placeholder: "Ask a question...",
                                text: $branchData.bottomQuestionText,
                                isEmpty: bottomFieldIsEmpty,
                                isFocused: isBottomQuestionFocused,
                                lineHeight: modelResponseLineHeight,
                                placeholderColor: placeholderColor,
                                showsChrome: false,
                                relay: bottomFieldRelay,
                                onFocusChange: { focused in
                                    isBottomQuestionFocused = focused
                                    if focused {
                                        bottomFieldIsActive = true
                                        isTopQuestionFocused = false
                                        onBottomInputFocused()
                                    }
                                },
                                onTextChange: { text in
                                    bottomFieldIsEmpty = text.isEmpty
                                    onActiveInputTextChange(text)
                                },
                                onSubmit: {
                                    submitBottomQuestionIfNeeded()
                                },
                                onTapToFocus: { bottomFieldRelay.focus() }
                            )
                            .overlay(alignment: .top) {
                                slashCommandMenuOverlay(forBottomField: true, yOffset: 72)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .id(bottomInputAnchor)
                .frame(maxWidth: .infinity)
                .onAppear {
                    // Reset placeholder state every time this section reappears.
                    // bottomFieldIsEmpty is driven by onTextChange callbacks, so it
                    // stays stale at `false` when showBottomInput cycles false→true
                    // (the UITextView is destroyed and recreated with empty text, but
                    // no change event fires). Re-syncing here restores the placeholder.
                    bottomFieldIsEmpty = branchData.bottomQuestionText.isEmpty
                }
                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
            }
                }
            }
        }
        .padding(.bottom, 40)
        .coordinateSpace(name: "ColumnContent-\(branchData.id)")
        .onAppear {
            if let concept = branchData.startingConcept {
                branchData.branchContextConcept = concept
            }
            // Sync placeholder visibility with any pre-filled text (e.g. restored branch)
            topFieldIsEmpty    = branchData.topQuestionText.isEmpty
            bottomFieldIsEmpty = branchData.bottomQuestionText.isEmpty
        }
        .onChange(of: quotedConcept) { oldValue, newValue in
            if let concept = newValue {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    branchData.attachedConcept = concept
                    branchData.showBottomInput = true
                }
                onQuoteHandled()
            }
        }
        .onChange(of: connectionConcepts?.map(\.id)) { _, _ in
            guard let concepts = connectionConcepts else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                localConnectionConcepts = concepts
                branchData.showBottomInput = true
            }
            onConnectionHandled?()
        }
        // Top field focus → notify parent so it can scroll the field to the top.
        .onChange(of: isTopQuestionFocused) { _, focused in
            if focused { onTopInputFocused() }
        }
        // Dock arrow button fires externalSubmitTrigger → submit whichever input is active.
        .onChange(of: externalSubmitTrigger) { _, _ in
            if branchData.showBottomInput {
                submitBottomQuestionIfNeeded()
            } else {
                submitTopQuestionIfNeeded()
            }
        }
        // Slash-command picker tapped → insert the command into the focused field.
        .onChange(of: insertCommandRequest) { _, _ in
            insertCommandIntoActiveField()
        }
    }

    /// Writes `commandToInsert` into whichever question field is currently focused,
    /// keeping the field first responder, and bubbles the change up so the placeholder
    /// and send-button state track it.
    private func insertCommandIntoActiveField() {
        guard !commandToInsert.isEmpty else { return }
        if bottomFieldIsActive {
            bottomFieldRelay.replaceAll(commandToInsert)
            bottomFieldIsEmpty = commandToInsert.isEmpty
        } else {
            topFieldRelay.replaceAll(commandToInsert)
            topFieldIsEmpty = commandToInsert.isEmpty
        }
        onActiveInputTextChange(commandToInsert)
    }
}

private struct ConversationSeparator: View {
    var verticalPadding: CGFloat = 0
    @State private var isExpanded = false

    var body: some View {
        Rectangle()
            .fill(AquinasTheme.Colors.brownBorder)
            .frame(width: 84, height: 1)
            .scaleEffect(x: isExpanded ? 1 : 0.5, y: 1, anchor: .center)
            .padding(.vertical, verticalPadding)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    isExpanded = true
                }
            }
    }
}

/// Reports a question field's true ambient available width, measured via an unconstrained
/// sibling probe (see `QuestionInputField`) so the field can be given a concrete number instead
/// of `nil`/`.infinity` — required for the fill→hug width change to actually animate on submit.
private struct QuestionInputWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Placeholder text for a question field, fading out once the field has focus or text. Tapping
/// into the field also briefly swaps the placeholder for a "Type / for a list of commands" hint,
/// which lingers a couple seconds before fading back to the normal placeholder.
private struct AnimatedQuestionPlaceholder: View {
    private static let commandHintText = "Type / for a list of commands"
    private static let hintLinger: Duration = .seconds(2.5)

    let text: String
    let font: Font
    let color: Color
    let isEmpty: Bool
    let isFocused: Bool
    let emptyAlignment: Alignment
    let filledAlignment: Alignment
    let animation: Animation
    var textAlignment: TextAlignment = .leading

    @State private var isShowingCommandHint = false
    @State private var hintDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Text(text)
                .opacity(isShowingCommandHint ? 0 : 1)
            Text(Self.commandHintText)
                .opacity(isShowingCommandHint ? 1 : 0)
        }
        .font(font)
        .foregroundColor(color)
        .frame(
            maxWidth: .infinity,
            alignment: isEmpty ? emptyAlignment : filledAlignment
        )
        .multilineTextAlignment(textAlignment)
        .opacity(isEmpty ? 1 : 0)
        .allowsHitTesting(false)
        .animation(animation, value: isEmpty)
        .animation(.easeInOut(duration: 0.3), value: isShowingCommandHint)
        .onChange(of: isFocused) { _, focused in
            guard focused else { return }
            hintDismissTask?.cancel()
            isShowingCommandHint = true
            hintDismissTask = Task {
                do { try await Task.sleep(for: Self.hintLinger) } catch { return }
                await MainActor.run { isShowingCommandHint = false }
            }
        }
        .onDisappear {
            hintDismissTask?.cancel()
        }
    }
}

/// Draws a magnifying glass on when it appears and off when it's removed, matching the SF Symbol
/// "Draw On"/"Draw Off" pair on iOS 26+ (with an opacity/scale fallback on earlier versions).
private struct QuestionInputIcon: View {
    var body: some View {
        let icon = Image(systemName: "magnifyingglass")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AquinasTheme.Colors.lightGreen)
            .frame(width: 12, height: 12)

        if #available(iOS 26.0, *) {
            // A single .drawOn transition plays forward on insertion and reverses (draws off)
            // on removal — no separate .drawOff needed.
            icon.transition(.symbolEffect(.drawOn))
        } else {
            icon.transition(.opacity.combined(with: .scale(scale: 0.7)))
        }
    }
}

/// The single "Ask a question" input box shared by every question field in the thread (the
/// brand-new-conversation prompt, a forked/continuing branch's top question, and the follow-up
/// field) — one place to change icon, chrome, sizing, or width behavior instead of three.
///
/// Sized to fill its ambient available width while editable. Once `isSubmitted` (for fields that
/// stay visible, locked, after submitting — the follow-up field never sets this since it's
/// removed from view on submit instead), it hugs the submitted question if that rendered on a
/// single line, or holds at `maxWidth` if it wrapped to more than one line.
private struct QuestionInputField: View {
    static let maxWidth: CGFloat = 250
    static let plainMaxWidth: CGFloat = 321
    static let fontSize: CGFloat = 14

    /// Exact pixel width UIKit renders `text` at in the field's font — measure once, at submit
    /// time, to decide whether the submitted question fits on one line.
    static func measuredWidth(for text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = UIFont(name: "Figtree-Regular", size: fontSize) ?? .systemFont(ofSize: fontSize)
        let measuredSize = (text as NSString).size(withAttributes: [.font: font])
        return ceil(measuredSize.width)
    }

    let placeholder: String
    @Binding var text: String
    var isLocked: Bool = false
    var isSubmitted: Bool = false
    var submittedWidth: CGFloat = 0
    let isEmpty: Bool
    let isFocused: Bool
    let lineHeight: CGFloat
    var placeholderColor: Color = AquinasTheme.Colors.placeholderText
    var showsChrome: Bool = true
    /// Which edge the boxed field hugs to within its available width.
    var boxAlignment: Alignment = .leading
    let relay: TextInputRelay
    var onFocusChange: (Bool) -> Void
    var onTextChange: (String) -> Void
    var onSubmit: (() -> Void)? = nil
    var onTapToFocus: (() -> Void)? = nil

    @State private var availableWidth: CGFloat = 0

    private var inputFont: UIFont {
        UIFont(name: "Figtree-Regular", size: Self.fontSize) ?? .systemFont(ofSize: Self.fontSize)
    }

    private var placeholderFont: Font {
        .custom("Figtree-Regular", size: Self.fontSize)
    }

    /// Always a concrete number (never nil/`.infinity`), so the fill→hug transition on submit is
    /// a genuine numeric interpolation SwiftUI can animate.
    private var boxWidth: CGFloat {
        guard isSubmitted else { return availableWidth > 0 ? availableWidth : Self.maxWidth }
        let singleLineWidth = submittedWidth + 40   // + this box's own 20×2 horizontal padding
        guard singleLineWidth <= Self.maxWidth else { return Self.maxWidth }
        return max(singleLineWidth, 60)
    }

    private var plainQuestionEditor: some View {
        ZStack(alignment: .center) {
            AnimatedQuestionPlaceholder(
                text: placeholder,
                font: placeholderFont,
                color: placeholderColor,
                isEmpty: isEmpty,
                isFocused: isFocused,
                emptyAlignment: .center,
                filledAlignment: .center,
                animation: .spring(response: 0.36, dampingFraction: 0.86),
                textAlignment: .center
            )

            ListAwareTextField(
                text: $text,
                font: inputFont,
                lineHeight: lineHeight,
                isLocked: isLocked,
                textColor: .aquinasPrimaryReadable,
                textAlignment: .center,
                onFocusChange: onFocusChange,
                relay: relay,
                onTextChange: onTextChange,
                onSubmit: onSubmit
            )
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: isEmpty)
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: isFocused)
        }
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)
        .frame(maxWidth: Self.plainMaxWidth, alignment: .center)
    }

    var body: some View {
        ZStack(alignment: showsChrome ? boxAlignment : .center) {
            // Invisible probe: `.frame(maxWidth: .infinity)` makes it want the full width its
            // ambient parent can offer, which — since it's the ZStack's widest child — forces
            // the ZStack itself to that true available width, independent of how narrow the
            // actual box below gets once hugged. Its GeometryReader reports that true width.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: 0)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: QuestionInputWidthKey.self, value: geo.size.width)
                    }
                )

            if showsChrome {
                HStack(spacing: 16) {
                    if isEmpty {
                        QuestionInputIcon()
                    }

                    ZStack(alignment: .leading) {
                        AnimatedQuestionPlaceholder(
                            text: placeholder,
                            font: placeholderFont,
                            color: placeholderColor,
                            isEmpty: isEmpty,
                            isFocused: isFocused,
                            emptyAlignment: .leading,
                            filledAlignment: .leading,
                            animation: .spring(response: 0.36, dampingFraction: 0.86)
                        )

                        ListAwareTextField(
                            text: $text,
                            font: inputFont,
                            lineHeight: lineHeight,
                            isLocked: isLocked,
                            textColor: .aquinasPrimaryReadable,
                            textAlignment: .natural,
                            onFocusChange: onFocusChange,
                            relay: relay,
                            onTextChange: onTextChange,
                            onSubmit: onSubmit
                        )
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: isEmpty)
                        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: isFocused)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(AquinasTheme.Colors.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AquinasTheme.Colors.sideMenuSearchBorder, lineWidth: 1)
                )
                .frame(width: boxWidth, alignment: .leading)
            } else {
                plainQuestionEditor
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onPreferenceChange(QuestionInputWidthKey.self) { width in
            guard width.isFinite,
                  width > 0,
                  abs(availableWidth - width) > 0.5 else {
                return
            }
            availableWidth = width
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: boxWidth)
        .contentShape(Rectangle())
        .onTapGesture { onTapToFocus?() }
    }
}

// MARK: - Response Geometry Tracker

/// Wraps a response card and reports its visual center Y so child branch connector lines stay attached.
struct TrackedResponseCard: View {
    let textContent: String
    let responseIndex: Int
    let shouldAnimateOnAppear: Bool
    let showsThinkingIntro: Bool
    let isAwaitingResponse: Bool
    let isReceivingStream: Bool
    let isQueuedForModel: Bool
    let usesNetworkStream: Bool
    let thinkingSummary: [String]
    let funStatusText: String?
    @Binding var targetSpawnY: CGFloat
    @Binding var targetSpawnResponseIndex: Int?
    let columnSpaceName: String
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    let savedInsightIDs: Set<UUID>
    var onCenterChange: (Int, CGFloat) -> Void = { _, _ in }
    var onDuplicateBranch: () -> Void = {}
    var onInsightTap: (String, String) -> Void = { _, _ in }
    var onInlineInsightQuote: (ConceptDefinition) -> Void = { _ in }
    var onInlineInsightFork: (ConceptDefinition) -> Void = { _ in }
    var onInlineInsightToggleSaved: (ConceptDefinition) -> Void = { _ in }
    var showsResponseActions: Bool = true
    var onRevealStart: () -> Void = {}
    var onFinish: () -> Void

    @State private var myYCenter: CGFloat = 0
    @State private var hasFinishedStreaming: Bool = false
    @Environment(\.openURL) var parentOpenURL
    private let responseChromeHeight: CGFloat = 46

    private func updateCenter(from geo: GeometryProxy, notifyParent: Bool) {
        let localY = geo.frame(in: .named(columnSpaceName)).minY
        let responseBodyHeight = max(0, geo.size.height - responseChromeHeight)
        myYCenter = localY + responseChromeHeight + (responseBodyHeight / 2)
        if notifyParent {
            let center = myYCenter
            DispatchQueue.main.async { onCenterChange(responseIndex, center) }
        }
    }

    var body: some View {
        ModelResponseCard(
            title: "",
            fullText: textContent,
            shouldAnimateOnAppear: shouldAnimateOnAppear,
            showsThinkingIntro: showsThinkingIntro,
            isAwaitingResponse: isAwaitingResponse,
            isReceivingStream: isReceivingStream,
            isQueuedForModel: isQueuedForModel,
            usesNetworkStream: usesNetworkStream,
            thinkingSummary: thinkingSummary,
            funStatusText: funStatusText,
            responseTextAlignment: responseTextAlignment,
            responseFont: responseFont,
            conversationFontSize: conversationFontSize,
            loadingInsightKey: loadingInsightKey,
            queuedInsightKeys: queuedInsightKeys,
            savedInsightIDs: savedInsightIDs,
            onDuplicateBranch: onDuplicateBranch,
            onInsightTap: onInsightTap,
            onInlineInsightQuote: onInlineInsightQuote,
            onInlineInsightFork: { insight in
                targetSpawnY = myYCenter
                targetSpawnResponseIndex = responseIndex
                onInlineInsightFork(insight)
            },
            onInlineInsightToggleSaved: onInlineInsightToggleSaved,
            showsResponseActions: showsResponseActions,
            onRevealStart: onRevealStart,
            onFinish: {
                hasFinishedStreaming = true
                onCenterChange(responseIndex, myYCenter)
                onFinish()
            }
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: .named(columnSpaceName)).minY) { _, _ in
                        updateCenter(from: geo, notifyParent: hasFinishedStreaming || !shouldAnimateOnAppear)
                    }
                    .onChange(of: geo.size.height) { _, _ in
                        updateCenter(from: geo, notifyParent: hasFinishedStreaming || !shouldAnimateOnAppear)
                    }
                    .onAppear { updateCenter(from: geo, notifyParent: true) }
            }
        )
        .environment(\.openURL, OpenURLAction { url in
            targetSpawnY = myYCenter
            targetSpawnResponseIndex = responseIndex
            parentOpenURL(url)
            return .handled
        })
    }
}

// MARK: - Insight Sheet Content

struct InsightSheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Bottom sheet shown when a generated insight link is tapped.
struct ConceptSheetContent: View {
    let concept: ConceptDefinition
    @Binding var collectedDefinitions: [ConceptDefinition]
    var onInquireFurther: (() -> Void)? = nil
    var onNewConversation: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    let brandDarkText = AquinasTheme.Colors.primaryReadable

    var body: some View {
        let isSaved = collectedDefinitions.contains(where: { $0.word == concept.word })

        InsightLibraryCard(
            insight: concept,
            isSaved: isSaved,
            maxWidth: .infinity,
            onQuote: {
                onInquireFurther?()
                dismiss()
            },
            onFork: {
                onNewConversation?()
                dismiss()
            },
            onToggleSaved: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if isSaved { collectedDefinitions.removeAll(where: { $0.word == concept.word }) }
                    else { collectedDefinitions.append(concept) }
                }
            }
        )
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(AquinasTheme.Colors.canvas)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: InsightSheetContentHeightKey.self,
                    value: geometry.size.height
                )
            }
        )
    }

}
