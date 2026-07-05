//
//  ActiveInquiry.swift
//  Aquinas-iOS
//
//  Created by Ryan on 4/14/26.
//

import Foundation
import SwiftUI
import UIKit

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
    var emptyStateUserName: String = "Ryan"
    var emptyStateEyebrow: String = ""
    var emptyStatePromptQuestion: String = ""
    var showsThinkingIntro: Bool = true
    var onSpawnYChange: (Int, CGFloat) -> Void
    var onDuplicateResponse: (String, Int) -> Void
    var onDeleteBranch: () -> Void
    var onConversationTitleChange: (String) -> Void
    var onTopInputFocused: () -> Void = {}
    var onBottomInputFocused: () -> Void
    var onActiveInputTextChange: (String) -> Void = { _ in }
    /// Incremented by the parent to request inserting `commandToInsert` into whichever
    /// question field is currently focused (used by the slash-command picker).
    var insertCommandRequest: Int = 0
    var commandToInsert: String = ""
    var showsSlashCommandMenu: Bool = false
    var slashCommandQuery: SlashCommandQuery? = nil
    var onSelectSlashCommand: (SlashCommand) -> Void = { _ in }
    var onQuoteHandled: () -> Void
    var connectionConcepts: (ConceptDefinition, ConceptDefinition)? = nil
    var onConnectionHandled: (() -> Void)? = nil
    var onResponseCompleted: () -> Void = {}
    var onResponseStarted: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    @State private var branchHeadHeight: CGFloat = 0
    @State private var animatedResponseIndices: Set<Int> = []
    @State private var responseThinkingIntroByIndex: [Int: Bool] = [:]
    @State private var pendingGeneratedTitleQuestion: String? = nil
    @State private var localConnectionConcepts: (ConceptDefinition, ConceptDefinition)?
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

    /// Placeholder text color resolved directly from the SwiftUI color-scheme environment,
    /// bypassing the Color(UIColor(dynamicProvider:)) conversion which can freeze to the
    /// light-mode value inside UIViewRepresentable-hosted view hierarchies.
    private var placeholderColor: Color {
        colorScheme == .dark
            ? Color(hex: 0xFFFAF0, alpha: 0.50)
            : Color(hex: 0x4A321C, alpha: 0.50)
    }

    private var inputAlignmentAnimation: Animation {
        .spring(response: 0.36, dampingFraction: 0.86)
    }

    private var inputPlacementAnimation: Animation {
        .easeInOut(duration: 0.28)
    }

    private var activeInputFrameAlignment: Alignment {
        inputTextAlignment == .center ? .leading : inputTextAlignment.frameAlignment
    }

    private var activeInputTextAlignment: NSTextAlignment {
        inputTextAlignment == .center ? .natural : inputTextAlignment.nsTextAlignment
    }

    private func inputFieldIsActive(isFocused: Bool, isEmpty: Bool) -> Bool {
        isFocused || !isEmpty
    }

    private func inputFieldMaxWidth(isFocused: Bool, isEmpty: Bool) -> CGFloat? {
        inputFieldIsActive(isFocused: isFocused, isEmpty: isEmpty) ? .infinity : nil
    }

    private func inputFieldPlacementAlignment(isFocused: Bool, isEmpty: Bool) -> Alignment {
        inputFieldIsActive(isFocused: isFocused, isEmpty: isEmpty) ? .leading : .center
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
    // simulatedResponse is temporary prototype content; replace this when the real model is connected.
    private let readingTopPadding: CGFloat = 30
    private let simulatedResponse = "Thomas Aquinas is one of the most influential figures in western thought. Often referred to as the Doctor Angelicus, he is the primary architect of [Thomism](aq://thomism) THE DIDACHE: THE TEACHING OF THE TWELVE APOSTLES The [Didache](aq://didache) (pronounced DID-ah-kay) is essentially the first-century 'user manual' for the early Christian church. Derived from the Greek word for 'teaching,' this document was written between 50 AD and 100 AD, providing a rare look at how the earliest Christian communities organized their lives. I. THE TWO WAYS The document opens with a moral framework called '[The Two Ways](aq://the-two-ways),' contrasting the Way of Life with the Way of Death. It outlines a strict ethical code, covering everything from communal love to specific social prohibitions. II. RITUAL AND LITURGY The Didache provides the earliest 'how-to' instructions for Christian rituals: • [Baptism](aq://baptism): Prefers 'living' (running) water, but allows for pouring if necessary. • [Fasting](aq://fasting): Suggests specific days of the week (Wednesdays and Fridays). • THE [Eucharist](aq://eucharist): Contains some of the oldest recorded prayers for communion. III. CHURCH STRUCTURE It outlines the qualifications for bishops and deacons and provides a fascinating guide on how to distinguish between genuine [traveling prophets](aq://traveling-prophets) and those seeking personal gain. HISTORICAL IMPACT Lost for centuries and rediscovered in 1873, the Didache serves as a vital bridge between the New Testament era and the formalized Church of later centuries."

    // Branch title shown above the first question.
    private var displayBranchTitle: String {
        branchData.generatedBranchTitle ?? (branchData.parentBranchID == nil ? "New Conversation" : "New Branch")
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

    // Prototype model response. Replace with async model call when backend is ready.
    private func appendSimulatedResponse() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Insert into animatedResponseIndices BEFORE appending the block.
            // Both mutations live in different @State owners (ChatThreadColumn vs
            // the @Binding source in ActiveInquiryView), so SwiftUI can process
            // them in separate render passes. Committing the index first guarantees
            // that when the ForEach creates the new card, animatedResponseIndices
            // already contains it → shouldAnimateOnAppear = true.
            let responseIndex = branchData.activeChatBlocks.count
            animatedResponseIndices.insert(responseIndex)
            responseThinkingIntroByIndex[responseIndex] = showsThinkingIntro
            onResponseStarted()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                branchData.activeChatBlocks.append(.text(simulatedResponse))
            }
        }
    }

    private func responseShowsThinkingIntro(at index: Int) -> Bool {
        responseThinkingIntroByIndex[index] ?? true
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

    private func inputContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(inputTextAlignment.inputContainerPadding)
            .background(AquinasTheme.Colors.canvas)
            .clipShape(RoundedRectangle(cornerRadius: inputTextAlignment.inputContainerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: inputTextAlignment.inputContainerRadius, style: .continuous)
                    .stroke(
                        AquinasTheme.Colors.darkBrown.opacity(inputTextAlignment.inputContainerBorderOpacity),
                        lineWidth: 1
                    )
            )
            .animation(.spring(response: 0.34, dampingFraction: 0.84), value: inputTextAlignment)
    }

    // Locks the first branch question, uploads, and context chip.
    private func submitTopQuestionIfNeeded() {
        // Flush the UITextView's live buffer into the binding synchronously.
        // Because we stopped per-keystroke binding writes, the relay is the only
        // way to read text that was typed but not yet blurred.
        branchData.topQuestionText = topFieldRelay.currentText()
        let submittedQuestion = branchData.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            branchData.topQuestionSubmitted = true
        }
        appendSimulatedResponse()
    }

    // Adds a follow-up question lower in the thread and locks its attachments/context.
    private func submitBottomQuestionIfNeeded() {
        // Flush live UITextView text to binding before reading (relay avoids per-keystroke writes).
        branchData.bottomQuestionText = bottomFieldRelay.currentText()
        let submittedQuestion = branchData.bottomQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedQuestion.isEmpty else {
            branchData.bottomQuestionText = submittedQuestion
            return
        }

        let quotedConcept = branchData.attachedConcept
        let submittedUploads = visibleUploads
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            branchData.showBottomInput = false
            branchData.activeChatBlocks.append(.user(submittedQuestion, quotedConcept, submittedUploads))
        }
        if showsPendingUploads {
            uploadedFiles.removeAll()
        }
        branchData.attachedConcept = nil
        localConnectionConcepts = nil
        branchData.bottomQuestionText = ""
        appendSimulatedResponse()
    }

    private var newConversationPromptHeader: some View {
        VStack(alignment: .center, spacing: 48) {
            VStack(alignment: .center, spacing: 8) {
                Text(trimmedEmptyStateEyebrow.isEmpty ? "NEW CONVERSATION" : trimmedEmptyStateEyebrow.uppercased())
                    .font(AquinasTheme.Typography.uiLabel)
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(newConversationHeaderTitle)
                    .font(.custom("LibreBaskerville-Regular", size: 28))
                    .foregroundColor(AquinasTheme.Colors.headingText)
                    .lineSpacing(14)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .id(newConversationHeaderTitle)
                    .transition(.blurredTitleReplacement)
            }
            .allowsHitTesting(false)

            ConversationSeparator(verticalPadding: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var newConversationPrompt: some View {
        VStack(spacing: 48) {
            Color.clear
                .frame(height: 1)
                .id(branchAnchor)

            newConversationPromptHeader
                .padding(.top, 84)

            newConversationQuestionField
        }
        .frame(maxWidth: .infinity)
    }

    private var newConversationQuestionField: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .leading) {
                AnimatedQuestionPlaceholder(
                    text: "Type / for commands",
                    font: .custom("LibreBaskerville-Regular", size: 14),
                    color: AquinasTheme.Colors.placeholderText,
                    isEmpty: topFieldIsEmpty && !branchData.topQuestionSubmitted,
                    isFocused: isTopQuestionFocused && !branchData.topQuestionSubmitted,
                    emptyAlignment: .leading,
                    filledAlignment: .leading,
                    animation: inputAlignmentAnimation
                )

                ListAwareTextField(
                    text: $branchData.topQuestionText,
                    font: UIFont(name: "LibreBaskerville-Regular", size: 14) ?? .systemFont(ofSize: 14),
                    isLocked: branchData.topQuestionSubmitted,
                    textColor: .aquinasPrimaryReadable,
                    textAlignment: .natural,
                    onFocusChange: { focused in
                        isTopQuestionFocused = focused
                        if focused {
                            bottomFieldIsActive = false
                            isBottomQuestionFocused = false
                            onTopInputFocused()
                        }
                    },
                    relay: topFieldRelay,
                    onTextChange: { text in
                        topFieldIsEmpty = text.isEmpty
                        onActiveInputTextChange(text)
                    }
                )
                .frame(
                    maxWidth: inputFieldMaxWidth(isFocused: isTopQuestionFocused, isEmpty: topFieldIsEmpty),
                    minHeight: 22,
                    alignment: .leading
                )
                .animation(inputAlignmentAnimation, value: topFieldIsEmpty)
                .animation(inputAlignmentAnimation, value: isTopQuestionFocused)
            }
            .frame(
                maxWidth: inputFieldMaxWidth(isFocused: isTopQuestionFocused, isEmpty: topFieldIsEmpty),
                alignment: .leading
            )
            .frame(
                maxWidth: .infinity,
                alignment: inputFieldPlacementAlignment(isFocused: isTopQuestionFocused, isEmpty: topFieldIsEmpty)
            )
            .animation(inputPlacementAnimation, value: isTopQuestionFocused)
            .animation(inputPlacementAnimation, value: topFieldIsEmpty)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !branchData.topQuestionSubmitted else { return }
                bottomFieldIsActive = false
                isTopQuestionFocused = true
                isBottomQuestionFocused = false
                topFieldRelay.focus()
            }
            .overlay(alignment: .top) {
                slashCommandMenuOverlay(forBottomField: false, yOffset: 34)
            }
        }
        .zIndex(showsSlashCommandMenu && !bottomFieldIsActive ? 50 : 0)
    }

    var body: some View {
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
                        onRemove: onDeleteBranch
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
                        inputContainer {
                            ZStack(alignment: .leading) {
                                AnimatedQuestionPlaceholder(
                                    text: "Ask a question...",
                                    font: inputFont.textFont(size: conversationFontSize),
                                    color: placeholderColor,
                                    isEmpty: topFieldIsEmpty && !branchData.topQuestionSubmitted,
                                    isFocused: isTopQuestionFocused && !branchData.topQuestionSubmitted,
                                    emptyAlignment: .leading,
                                    filledAlignment: activeInputFrameAlignment,
                                    animation: inputAlignmentAnimation
                                )

                                ListAwareTextField(
                                    text: $branchData.topQuestionText,
                                    font: inputFont.uiFont(size: conversationFontSize),
                                    isLocked: branchData.topQuestionSubmitted,
                                    textColor: .aquinasPrimaryReadable,
                                    textAlignment: .natural,
                                    onFocusChange: { focused in
                                        isTopQuestionFocused = focused
                                        if focused {
                                            bottomFieldIsActive = false
                                            isBottomQuestionFocused = false
                                            onTopInputFocused()
                                        }
                                    },
                                    relay: topFieldRelay,
                                    onTextChange: { text in
                                        topFieldIsEmpty = text.isEmpty
                                        onActiveInputTextChange(text)
                                    }
                                )
                                .frame(
                                    maxWidth: inputFieldMaxWidth(isFocused: isTopQuestionFocused, isEmpty: topFieldIsEmpty),
                                    alignment: .leading
                                )
                                .animation(inputAlignmentAnimation, value: topFieldIsEmpty)
                            }
                        }
                        .frame(
                            maxWidth: inputFieldMaxWidth(isFocused: isTopQuestionFocused, isEmpty: topFieldIsEmpty),
                            alignment: .leading
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: inputFieldPlacementAlignment(isFocused: isTopQuestionFocused, isEmpty: topFieldIsEmpty)
                        )
                        .animation(inputPlacementAnimation, value: isTopQuestionFocused)
                        .animation(inputPlacementAnimation, value: topFieldIsEmpty)
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

                        TrackedResponseCard(
                            textContent: textContent,
                            responseIndex: index,
                            shouldAnimateOnAppear: animatedResponseIndices.contains(index),
                            showsThinkingIntro: responseShowsThinkingIntro(at: index),
                            targetSpawnY: $targetSpawnY,
                            targetSpawnResponseIndex: $targetSpawnResponseIndex,
                            columnSpaceName: "ColumnContent-\(branchData.id)",
                            responseTextAlignment: responseTextAlignment,
                            responseFont: responseFont,
                            conversationFontSize: conversationFontSize,
                            onCenterChange: onSpawnYChange,
                            onDuplicateBranch: {
                                onDuplicateResponse(textContent, index)
                            },
                            onFinish: {
                                animatedResponseIndices.remove(index)
                                finalizePendingGeneratedTitleIfNeeded()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { branchData.showBottomInput = true }
                                onResponseCompleted()
                            }
                        )
                        .id("\(branchData.id)-response-\(index)")
                        .transition(
                            animatedResponseIndices.contains(index)
                            ? .opacity.combined(with: .scale(scale: 0.5))
                            : .identity
                        )

                    case .user(let questionText, let quotedConcept, let attachments):
                        VStack(spacing: 48) {
                            ConversationSeparator()

                            VStack(spacing: 16) {
                                UploadedFileStrip(files: attachments)

                                if let concept = quotedConcept {
                                    BranchContextChip(
                                        title: concept.word.capitalized,
                                        icon: "text.bubble.fill",
                                        isFilled: true,
                                        animatesAppearance: false,
                                        showRemove: false
                                    )
                                    .matchedGeometryEffect(id: concept.id, in: quotedContextChipNamespace)
                                }
                                inputContainer {
                                    ListAwareTextField(
                                        text: .constant(questionText),
                                        font: inputFont.uiFont(size: conversationFontSize),
                                        isLocked: true,
                                        textColor: .aquinasPrimaryReadable,
                                        textAlignment: .natural
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
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
                                onRemove: {
                                    withAnimation {
                                        branchData.attachedConcept = nil
                                    }
                                }
                            )
                            .matchedGeometryEffect(id: concept.id, in: quotedContextChipNamespace)
                            .transition(.scale.combined(with: .opacity))
                        }

                        if let (c1, c2) = localConnectionConcepts {
                            ConnectionContextChip(
                                conceptA: c1,
                                conceptB: c2,
                                onRemove: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        localConnectionConcepts = nil
                                    }
                                }
                            )
                            .transition(.scale.combined(with: .opacity))
                        }

                        VStack(spacing: 12) {
                            inputContainer {
                                ZStack(alignment: .leading) {
                                    AnimatedQuestionPlaceholder(
                                        text: "Ask a follow-up question...",
                                        font: inputFont.textFont(size: conversationFontSize),
                                        color: placeholderColor,
                                        isEmpty: bottomFieldIsEmpty,
                                        isFocused: isBottomQuestionFocused,
                                        emptyAlignment: .leading,
                                        filledAlignment: activeInputFrameAlignment,
                                        animation: inputAlignmentAnimation
                                    )

                                    ListAwareTextField(
                                        text: $branchData.bottomQuestionText,
                                        font: inputFont.uiFont(size: conversationFontSize),
                                        textColor: .aquinasPrimaryReadable,
                                        textAlignment: .natural,
                                        onFocusChange: { focused in
                                            isBottomQuestionFocused = focused
                                            if focused {
                                                bottomFieldIsActive = true
                                                isTopQuestionFocused = false
                                                onBottomInputFocused()
                                            }
                                        },
                                        relay: bottomFieldRelay,
                                        onTextChange: { text in
                                            bottomFieldIsEmpty = text.isEmpty
                                            onActiveInputTextChange(text)
                                        }
                                    )
                                    .frame(
                                        maxWidth: inputFieldMaxWidth(isFocused: isBottomQuestionFocused, isEmpty: bottomFieldIsEmpty),
                                        alignment: .leading
                                    )
                                    .animation(inputAlignmentAnimation, value: bottomFieldIsEmpty)
                                }
                            }
                            .frame(
                                maxWidth: inputFieldMaxWidth(isFocused: isBottomQuestionFocused, isEmpty: bottomFieldIsEmpty),
                                alignment: .leading
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: inputFieldPlacementAlignment(isFocused: isBottomQuestionFocused, isEmpty: bottomFieldIsEmpty)
                            )
                            .animation(inputPlacementAnimation, value: isBottomQuestionFocused)
                            .animation(inputPlacementAnimation, value: bottomFieldIsEmpty)
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
        .onChange(of: connectionConcepts?.0.id) { _, _ in
            guard let pair = connectionConcepts else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                localConnectionConcepts = pair
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

private struct AnimatedQuestionPlaceholder: View {
    let text: String
    let font: Font
    let color: Color
    let isEmpty: Bool
    let isFocused: Bool
    let emptyAlignment: Alignment
    let filledAlignment: Alignment
    let animation: Animation

    private var focusedEmptyOffset: CGFloat {
        0
    }

    private var currentAlignment: Alignment {
        isEmpty && !isFocused ? emptyAlignment : filledAlignment
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .frame(alignment: currentAlignment)
            .offset(x: focusedEmptyOffset)
            .opacity(isEmpty ? 1 : 0)
            .allowsHitTesting(false)
            .animation(animation, value: isEmpty)
            .animation(animation, value: isFocused)
    }
}

// MARK: - Response Geometry Tracker

/// Wraps a response card and reports its visual center Y so child branch connector lines stay attached.
struct TrackedResponseCard: View {
    let textContent: String
    let responseIndex: Int
    let shouldAnimateOnAppear: Bool
    let showsThinkingIntro: Bool
    @Binding var targetSpawnY: CGFloat
    @Binding var targetSpawnResponseIndex: Int?
    let columnSpaceName: String
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    var onCenterChange: (Int, CGFloat) -> Void = { _, _ in }
    var onDuplicateBranch: () -> Void = {}
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
            title: "Are Some Lies Acceptable?",
            fullText: textContent,
            shouldAnimateOnAppear: shouldAnimateOnAppear,
            showsThinkingIntro: showsThinkingIntro,
            responseTextAlignment: responseTextAlignment,
            responseFont: responseFont,
            conversationFontSize: conversationFontSize,
            onDuplicateBranch: onDuplicateBranch,
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
