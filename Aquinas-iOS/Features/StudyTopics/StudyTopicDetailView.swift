//
//  StudyTopicDetailView.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

struct StudyTopicDetailView: View {
    let topic: StudyTopic
    let conversations: [InquiryConversation]
    let activeConversationID: UUID?
    @Binding var savedInsights: [ConceptDefinition]
    let treeInsights: [ConceptDefinition]
    let restoredTreeInsightID: UUID?
    @Binding var isExistingConversationPickerOpen: Bool
    var onUpdateTopic: (StudyTopic) -> Void
    var onTopicTouched: () -> Void
    var onSelectConversation: (InquiryConversation) -> Void
    var onNewChat: () -> Void
    var onQuoteInsightIntoNewConversation: (ConceptDefinition) -> Void
    var onQuoteInsightIntoConversation: (InquiryConversation, ConceptDefinition) -> Void
    var onAttachConversation: (InquiryConversation) -> Void
    var onRenameConversation: (InquiryConversation, String) -> Void
    var onPinConversation: (InquiryConversation) -> Void
    var onUnpinConversation: (InquiryConversation) -> Void
    var onRemoveConversationFromStudyTopic: (InquiryConversation) -> Void
    var onDeleteConversation: (InquiryConversation) -> Void
    var onDeleteTopic: () -> Void
    var onRemoveTreeInsight: (ConceptDefinition) -> Void
    var onRestoreTreeInsight: (ConceptDefinition) -> Void
    var onBack: () -> Void
    /// Owned by the parent StudyTopicsView so its shared back button can close the
    /// Insight Tree before closing this detail view.
    let canvasMode: CanvasModeModel
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    let model: AquinasModel
    let embeddingProvider: EmbeddingProvider
    let insightTreeService: InsightTreeService

    @State private var activeInsight: ConceptDefinition? = nil
    @State private var pickerActiveInsight: ConceptDefinition? = nil
    @State private var quotePickerInsight: ConceptDefinition? = nil
    @State private var isInsightAskMode: Bool = false
    @State private var conversationBeingRenamed: InquiryConversation? = nil
    @State private var deletingConversationIDs: Set<UUID> = []
    @State private var renameDraft = ""
    @State private var titleDraft: String
    @State private var descriptionDraft: String
    @State private var topicSearchText = ""
    @State private var localFiles: [UploadedFile]
    @State private var isTitleFocused: Bool = false

    // MARK: Insight Tree (Canvas Mode, scoped to this topic's saved insights)
    @State private var insightSelectedPersonality = "Balanced"
    @State private var insightIsPersonalityMenuOpen = false
    @State private var insightShowFilePicker = false
    @State private var insightShowPhotoPicker = false
    @State private var insightShowCamera = false
    @State private var insightContextCardState = ContextCardState()
    @State private var persistedTreeRefreshRequest = 0

    init(
        topic: StudyTopic,
        conversations: [InquiryConversation],
        activeConversationID: UUID?,
        savedInsights: Binding<[ConceptDefinition]>,
        treeInsights: [ConceptDefinition],
        restoredTreeInsightID: UUID?,
        isExistingConversationPickerOpen: Binding<Bool>,
        canvasMode: CanvasModeModel,
        modelTasks: ModelTaskQueue,
        modelTasksPopupState: ModelTasksPopupState,
        model: AquinasModel,
        embeddingProvider: EmbeddingProvider,
        insightTreeService: InsightTreeService,
        autoFocusTitle: Bool = false,
        onUpdateTopic: @escaping (StudyTopic) -> Void,
        onTopicTouched: @escaping () -> Void = {},
        onSelectConversation: @escaping (InquiryConversation) -> Void,
        onNewChat: @escaping () -> Void,
        onQuoteInsightIntoNewConversation:
            @escaping (ConceptDefinition) -> Void,
        onQuoteInsightIntoConversation:
            @escaping (InquiryConversation, ConceptDefinition) -> Void,
        onAttachConversation: @escaping (InquiryConversation) -> Void,
        onRenameConversation: @escaping (InquiryConversation, String) -> Void,
        onPinConversation: @escaping (InquiryConversation) -> Void,
        onUnpinConversation: @escaping (InquiryConversation) -> Void,
        onRemoveConversationFromStudyTopic: @escaping (InquiryConversation) -> Void,
        onDeleteConversation: @escaping (InquiryConversation) -> Void,
        onDeleteTopic: @escaping () -> Void,
        onRemoveTreeInsight: @escaping (ConceptDefinition) -> Void,
        onRestoreTreeInsight: @escaping (ConceptDefinition) -> Void,
        onBack: @escaping () -> Void,
        onRequestPhotoPicker: @escaping () -> Void = {},
        onRequestFilePicker: @escaping () -> Void = {}
    ) {
        self.topic = topic
        self.conversations = conversations
        self.activeConversationID = activeConversationID
        self._savedInsights = savedInsights
        self.treeInsights = treeInsights
        self.restoredTreeInsightID = restoredTreeInsightID
        self._isExistingConversationPickerOpen = isExistingConversationPickerOpen
        self.canvasMode = canvasMode
        self.modelTasks = modelTasks
        self.modelTasksPopupState = modelTasksPopupState
        self.model = model
        self.embeddingProvider = embeddingProvider
        self.insightTreeService = insightTreeService
        self.autoFocusTitle = autoFocusTitle
        self.onUpdateTopic = onUpdateTopic
        self.onTopicTouched = onTopicTouched
        self.onSelectConversation = onSelectConversation
        self.onNewChat = onNewChat
        self.onQuoteInsightIntoNewConversation = onQuoteInsightIntoNewConversation
        self.onQuoteInsightIntoConversation = onQuoteInsightIntoConversation
        self.onAttachConversation = onAttachConversation
        self.onRenameConversation = onRenameConversation
        self.onPinConversation = onPinConversation
        self.onUnpinConversation = onUnpinConversation
        self.onRemoveConversationFromStudyTopic = onRemoveConversationFromStudyTopic
        self.onDeleteConversation = onDeleteConversation
        self.onDeleteTopic = onDeleteTopic
        self.onRemoveTreeInsight = onRemoveTreeInsight
        self.onRestoreTreeInsight = onRestoreTreeInsight
        self.onBack = onBack
        self.onRequestPhotoPicker = onRequestPhotoPicker
        self.onRequestFilePicker = onRequestFilePicker
        self._titleDraft = State(initialValue: topic.title)
        self._descriptionDraft = State(initialValue: topic.description)
        self._localFiles = State(initialValue: topic.files)
    }

    let autoFocusTitle: Bool
    let onRequestPhotoPicker: () -> Void
    let onRequestFilePicker: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AquinasTheme.Colors.canvas
                .ignoresSafeArea()

            let topicConversations = filteredTopicConversations

            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Spacer behind the floating hamburger button.
                        Color.clear.frame(height: 72)

                        VStack(alignment: .leading, spacing: 48) {
                            VStack(alignment: .leading, spacing: 8) {
                                StudyTopicTitleTextView(
                                    placeholder: "New Study Topic",
                                    text: $titleDraft,
                                    isFocused: $isTitleFocused,
                                    lineSpacing: 18
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onChange(of: titleDraft) { _, _ in persistDrafts() }

                                /*
                                Menu {
                                    Button("Rename", systemImage: "pencil.line") {
                                        isTitleFocused = true
                                    }
                                    Button("Upload Image", systemImage: "photo") {
                                        onRequestPhotoPicker()
                                    }
                                    Button("Upload File", systemImage: "doc") {
                                        onRequestFilePicker()
                                    }
                                    Divider()
                                    Button("Delete Topic", systemImage: "trash", role: .destructive) {
                                        onDeleteTopic()
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                                .padding(11)
                                .contentShape(Rectangle())
                                .padding(-11)
                                .accessibilityLabel("Topic options")
                                */

                                placeholderTextField(
                                    placeholder: "Briefly describe the topic of this study",
                                    text: $descriptionDraft,
                                    font: .custom("Figtree-Regular", size: 14),
                                    color: AquinasTheme.Colors.paragraphText,
                                    emptyOpacity: 0.5,
                                    lineLimit: 1...4,
                                    lineSpacing: 7
                                )
                                .onChange(of: descriptionDraft) { _, _ in persistDrafts() }

                                StudyTopicsSearchField(
                                    searchText: $topicSearchText,
                                    prompt: Text("Search in \(Text(displayTopicTitle).italic())")
                                )
                                .padding(.top, 8)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // Files section — only shown when at least one file has been uploaded.
                            if !localFiles.isEmpty {
                                StudyTopicFilesSection(
                                    files: localFiles,
                                    onRemove: { file in
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                            localFiles.removeAll { $0.id == file.id }
                                        }
                                        persistDrafts()
                                    }
                                )
                            }

                            if !topicConversations.isEmpty {
                                LazyVStack(spacing: 16) {
                                    ForEach(topicConversations) { conversation in
                                        OpenConversationCard(
                                            conversation: conversation,
                                            isActive: conversation.id == activeConversationID,
                                            latestAnswer: latestAnswer(in: conversation),
                                            insights: insights(for: conversation),
                                            onSelect: { onSelectConversation(conversation) },
                                            onOpenInsight: { insight in activeInsight = insight },
                                            onRename: { conv in
                                                renameDraft = conv.title
                                                conversationBeingRenamed = conv
                                            },
                                            onPin: { conv in
                                                onPinConversation(conv)
                                            },
                                            onUnpin: { conv in
                                                onUnpinConversation(conv)
                                            },
                                            onRemoveFromStudyTopic: { conv in
                                                onRemoveConversationFromStudyTopic(conv)
                                            },
                                            onDelete: { conv in
                                                deleteConversationCard(conv)
                                            }
                                        )
                                        .opacity(deletingConversationIDs.contains(conversation.id) ? 0 : 1)
                                        .blur(radius: deletingConversationIDs.contains(conversation.id) ? 12 : 0)
                                        .transition(
                                            .asymmetric(
                                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                                removal: .blurFade
                                            )
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: normalizedTopicSearchText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)

                        Color.clear.frame(height: 120)
                    }
                    .frame(width: max(0, geometry.size.width - 48), alignment: .leading)
                    .padding(.horizontal, 24)
                    .frame(width: geometry.size.width, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollClipDisabled()
            }

            // Insight Tree: saved insights from this topic's conversations.
            if canvasMode.isTopicCanvasVisible {
                topicInsightTreeLayer
            }

            // Top-right entry into the topic's Insight Tree. Fades/scales/blurs away once
            // inside — the shared back button (top-left) handles exiting, so there's no
            // second "back" affordance competing for the same corner.
            if !canvasMode.isTopicCanvasVisible {
                VStack {
                    HStack {
                        Spacer()
                        CanvasModeToggleButton(isActive: false, action: enterInsightTree)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    Spacer()
                }
                .zIndex(7)
                .transition(.canvasToggleFade)
            }

        }
        .task(id: autoFocusTitle) {
            guard autoFocusTitle else { return }
            // Wait for the slide-in transition to finish before stealing first responder.
            try? await Task.sleep(for: .milliseconds(550))
            isTitleFocused = true
        }
        // Swipe right to go back, swipe left to enter the Insight Tree.
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width > 60 {
                        if canvasMode.isTopicCanvasVisible {
                            closeInsightTree()
                        } else {
                            onBack()
                        }
                    } else if value.translation.width < -60 && !canvasMode.isTopicCanvasVisible {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        enterInsightTree()
                    }
                }
        )
        .safeAreaInset(edge: .bottom) {
            if canvasMode.isTopicCanvasVisible {
                insightControlDock
            }
        }
        .sheet(item: $activeInsight) { insight in
            ConceptSheetContent(concept: insight, collectedDefinitions: $savedInsights)
                .presentationDetents([.height(340), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AquinasTheme.Colors.canvas)
        }
        .sheet(item: $quotePickerInsight) { insight in
            InsightConversationPickerSheet(
                title: "Existing Conversations",
                searchPrompt: "Search in \(displayTopicTitle)",
                emptyMessage: "This Study Topic does not have a matching conversation.",
                conversations: topicConversationsForQuote,
                activeConversationID: activeConversationID,
                savedInsights: savedInsights,
                onSelect: { conversation in
                    quotePickerInsight = nil
                    onQuoteInsightIntoConversation(conversation, insight)
                },
                onCancel: {
                    quotePickerInsight = nil
                }
            )
            .presentationDetents([.height(520), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
        }
        .sheet(isPresented: $isExistingConversationPickerOpen) {
            ExistingConversationPickerSheet(
                // Only offer conversations that aren't already attached to a topic.
                conversations: conversations.filter { $0.studyTopicID == nil },
                activeConversationID: activeConversationID,
                savedInsights: $savedInsights,
                onSelectConversation: { conversation in
                    onAttachConversation(conversation)
                    isExistingConversationPickerOpen = false
                },
                onOpenInsight: { insight in
                    pickerActiveInsight = insight
                },
                onRenameConversation: { conversation, title in
                    onRenameConversation(conversation, title)
                },
                onPinConversation: onPinConversation,
                onUnpinConversation: onUnpinConversation,
                onRemoveConversationFromStudyTopic: onRemoveConversationFromStudyTopic,
                onDeleteConversation: onDeleteConversation
            )
            .presentationDetents([.height(420), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
        }
        .sheet(item: $pickerActiveInsight) { insight in
            ConceptSheetContent(concept: insight, collectedDefinitions: $savedInsights)
                .presentationDetents([.height(340), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AquinasTheme.Colors.canvas)
        }
        .alert("Rename Conversation", isPresented: renamePromptBinding) {
            TextField("Conversation name", text: $renameDraft)
            Button("Cancel", role: .cancel) {
                conversationBeingRenamed = nil
                renameDraft = ""
            }
            Button("Save") {
                guard let conversationBeingRenamed else { return }
                let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    onRenameConversation(conversationBeingRenamed, title)
                }
                self.conversationBeingRenamed = nil
                renameDraft = ""
            }
        }
        // Sync localFiles when the parent pushes new files in (e.g. after a photo/file pick).
        .onChange(of: topic.files) { _, newFiles in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                localFiles = newFiles
            }
        }
    }

    private var renamePromptBinding: Binding<Bool> {
        Binding(
            get: { conversationBeingRenamed != nil },
            set: { isPresented in
                if !isPresented {
                    conversationBeingRenamed = nil
                    renameDraft = ""
                }
            }
        )
    }

    private var displayTopicTitle: String {
        let trimmedDraft = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDraft.isEmpty { return trimmedDraft }

        let trimmedTitle = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Study Topic" : trimmedTitle
    }

    private var normalizedTopicSearchText: String {
        topicSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var topicConversationsForQuote: [InquiryConversation] {
        conversations
            .filter { $0.studyTopicID == topic.id }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.createdAt > $1.createdAt
            }
    }

    private var filteredTopicConversations: [InquiryConversation] {
        let topicConversations = conversations.filter { $0.studyTopicID == topic.id }
        guard !normalizedTopicSearchText.isEmpty else { return topicConversations }

        return topicConversations.filter { conversation in
            let insightWords = insights(for: conversation).map(\.word).joined(separator: " ")
            let text = [
                conversation.title,
                latestAnswer(in: conversation),
                insightWords,
                searchableText(conversation)
            ].joined(separator: " ").lowercased()

            return text.contains(normalizedTopicSearchText)
        }
    }

    private func deleteConversationCard(_ conversation: InquiryConversation) {
        guard !deletingConversationIDs.contains(conversation.id) else { return }

        deletingConversationIDs.insert(conversation.id)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                onDeleteConversation(conversation)
            }
            deletingConversationIDs.remove(conversation.id)
        }
    }

    private func placeholderTextField(
        placeholder: String,
        text: Binding<String>,
        font: Font,
        color: Color,
        emptyOpacity: Double,
        lineLimit: ClosedRange<Int>,
        lineSpacing: CGFloat = 0,
        minimumHeight: CGFloat? = nil,
        focusBinding: FocusState<Bool>.Binding? = nil
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                .font(font)
                .lineSpacing(lineSpacing)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .allowsHitTesting(false)

            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(font)
                    .lineSpacing(lineSpacing)
                    .foregroundColor(color.opacity(emptyOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
            }

            if let focusBinding {
                TextField("", text: text, axis: .vertical)
                    .font(font)
                    .foregroundColor(color)
                    .tint(AquinasTheme.Colors.secondaryMuted)
                    .lineSpacing(lineSpacing)
                    .lineLimit(lineLimit)
                    .scrollDisabled(true)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused(focusBinding)
                    .onChange(of: text.wrappedValue) { _, newValue in
                        guard newValue.contains("\n") else { return }
                        text.wrappedValue = newValue.replacingOccurrences(of: "\n", with: "")
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
            } else {
                TextField("", text: text, axis: .vertical)
                    .font(font)
                    .foregroundColor(color)
                    .tint(AquinasTheme.Colors.secondaryMuted)
                    .lineSpacing(lineSpacing)
                    .lineLimit(lineLimit)
                    .scrollDisabled(true)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: text.wrappedValue) { _, newValue in
                        guard newValue.contains("\n") else { return }
                        text.wrappedValue = newValue.replacingOccurrences(of: "\n", with: "")
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
            }
        }
        .frame(minHeight: minimumHeight, alignment: .topLeading)
    }

    private func persistDrafts() {
        onTopicTouched()
        onUpdateTopic(
            StudyTopic(
                id: topic.id,
                title: titleDraft,
                description: descriptionDraft,
                files: localFiles
            )
        )
    }

    private func latestAnswer(in conversation: InquiryConversation) -> String {
        for branch in conversation.branches.reversed() {
            for block in branch.activeChatBlocks.reversed() {
                if case .text(let answer) = block {
                    let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        for branch in conversation.branches.reversed() {
            let fallback = branch.bottomQuestionText.isEmpty
                ? branch.topQuestionText
                : branch.bottomQuestionText
            let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "Start a new line of inquiry."
    }

    private func insights(for conversation: InquiryConversation) -> [ConceptDefinition] {
        let text = searchableText(conversation).lowercased()
        return savedInsights.filter { text.contains($0.word.lowercased()) }.uniquedByWord()
    }

    private func searchableText(_ conversation: InquiryConversation) -> String {
        var text = conversation.title
        for branch in conversation.branches {
            text += " \(branch.topQuestionText) \(branch.bottomQuestionText) \(branch.duplicatedResponse ?? "")"
            for block in branch.activeChatBlocks {
                switch block {
                case .text(let t): text += " \(t)"
                case .user(let q, let c, _):
                    text += " \(q)"
                    if let c { text += " \(c.word) \(c.meaning)" }
                }
            }
        }
        return text
    }

    // MARK: Insight Tree

    private func enterInsightTree() {
        onTopicTouched()
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            canvasMode.isTopicCanvasVisible = true
        }
    }

    private func closeInsightTree() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            canvasMode.isTopicCanvasVisible = false
        }
    }

    /// Forking an insight from the topic canvas starts a new conversation in this topic.
    private func forkTopicInsight(_ concept: ConceptDefinition) {
        closeInsightTree()
        onNewChat()
    }

    private func toggleSavedInsight(_ concept: ConceptDefinition) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if savedInsights.contains(where: { $0.id == concept.id }) {
                removeTopicTreeInsight(concept)
            } else {
                restoreTopicTreeInsight(concept)
            }
        }
    }

    private func removeTopicTreeInsight(_ concept: ConceptDefinition) {
        onRemoveTreeInsight(concept)
        modelTasks.enqueue(
            kind: .refreshInsightTree,
            originPage: .studyTopics,
            conversationID: topic.id,
            priority: .background
        ) {
            guard AquinasBackendConfiguration.canRecoverFromCurrentDevice else { return }
            do {
                try await insightTreeService.remove(insightID: concept.id, from: topic.id)
                guard !Task.isCancelled else { return }
                persistedTreeRefreshRequest += 1
                await Task.yield()
            } catch {
                // The accepted topic snapshot is durable and will reconcile on the next load.
            }
        }
    }

    private func restoreTopicTreeInsight(_ concept: ConceptDefinition) {
        onRestoreTreeInsight(concept)
        modelTasks.enqueue(
            kind: .refreshInsightTree,
            originPage: .studyTopics,
            conversationID: topic.id,
            priority: .background
        ) {
            guard AquinasBackendConfiguration.canRecoverFromCurrentDevice else { return }
            do {
                let suggestedNodeLabel = try await model.labelSubject(
                    forTitles: ["\(concept.word): \(concept.semanticDefinition)"]
                )
                _ = try await insightTreeService.save(
                    concept,
                    to: topic.id,
                    suggestedNodeLabel: suggestedNodeLabel
                )
                guard !Task.isCancelled else { return }
                persistedTreeRefreshRequest += 1
                await Task.yield()
            } catch {
                // The accepted topic snapshot is durable and will reconcile on the next load.
            }
        }
    }

    @ViewBuilder
    private var topicInsightTreeLayer: some View {
        InsightTreeView(
            insights: treeInsights,
            conversationID: topic.id,
            selectionRequest: canvasMode.canvasSelectionRequest,
            persistedTreeRefreshRequest: persistedTreeRefreshRequest,
            clearSelectionRequest: canvasMode.canvasClearSelectionRequest,
            dismissHoverRequest: canvasMode.canvasDismissHoverRequest,
            createConceptRequest: canvasMode.canvasCreateConceptRequest,
            studyRequest: canvasMode.canvasStudyRequest,
            studyExitRequest: canvasMode.canvasStudyExitRequest,
            studyToolsToggleRequest: canvasMode.canvasStudyToolsToggleRequest,
            studyBranchCount: canvasMode.canvasStudyBranchCount,
            onStudyModeChange: { canvasMode.isCanvasStudyMode = $0 },
            onStudyToolsActiveChange: { canvasMode.isCanvasStudyToolsActive = $0 },
            onStudyBranchCountChange: { canvasMode.canvasStudyBranchCount = $0 },
            restoreSelectedInsightID: restoredTreeInsightID,
            promotedInsightIDs: canvasMode.promotedCanvasInsightIDs,
            onRemoveInsight: removeTopicTreeInsight,
            onRestoreInsight: restoreTopicTreeInsight,
            onForkInsight: forkTopicInsight,
            onQuoteInsight: { insight in
                canvasMode.canvasQuoteTarget = insight
                if insight == nil { isInsightAskMode = false }
            },
            onSelectionStateChange: { canvasMode.hasCanvasHover = $0 },
            onInsightSelectionStateChange: { canvasMode.hasHoveredCanvasInsight = $0 },
            onSelectedCanvasItemCountChange: { canvasMode.canvasSelectedItemCount = $0 },
            onPromotedInsightIDsChange: { canvasMode.promotedCanvasInsightIDs = $0 },
            savedConceptIDs: Set(treeInsights.map(\.id)),
            onToggleSavedConcept: toggleSavedInsight,
            onBookmarkConcepts: { concepts in
                for concept in concepts
                where !treeInsights.contains(where: { $0.id == concept.id }) {
                    restoreTopicTreeInsight(concept)
                }
            },
            inquireConnectionRequest: canvasMode.canvasInquireConnectionRequest,
            onInquireConnectionConcepts: { concepts in
                guard let first = concepts.first else { return }
                forkTopicInsight(first)
            },
            midpointEnterRequest: canvasMode.canvasMidpointEnterRequest,
            midpointCenterRequest: canvasMode.canvasMidpointCenterRequest,
            midpointPlaceRequest: canvasMode.canvasMidpointPlaceRequest,
            onMidpointModeChange: { canvasMode.isCanvasMidpointMode = $0 },
            onMidpointGeneratingChange: { canvasMode.isCanvasInsightGenerating = $0 },
            showQuestionBar: false,
            modelTasks: modelTasks,
            modelTaskOriginPage: .studyTopics,
            model: model,
            embeddingProvider: embeddingProvider,
            insightTreeService: insightTreeService,
            reconcilesPersistedSavedInsights: true
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .zIndex(5)
    }

    @ViewBuilder
    private var insightControlDock: some View {
        InquiryControlDock(
            isCanvasMode: true,
            showFilePicker: $insightShowFilePicker,
            showPhotoPicker: $insightShowPhotoPicker,
            showCamera: $insightShowCamera,
            selectedPersonality: $insightSelectedPersonality,
            isPersonalityMenuOpen: $insightIsPersonalityMenuOpen,
            isAtBottom: true,
            hasCanvasHover: canvasMode.hasCanvasHover,
            hasCanvasInsightHover: canvasMode.hasHoveredCanvasInsight,
            hasSelectedCanvasItems: canvasMode.canvasSelectedItemCount > 0,
            selectedCanvasItemCount: canvasMode.canvasSelectedItemCount,
            onScrollToBottom: {},
            onViewEntireCanvas: {},
            onOpenInsights: {},
            onSelectCanvasItem: { canvasMode.canvasSelectionRequest += 1 },
            onCreateCanvasConcept: { canvasMode.canvasCreateConceptRequest += 1 },
            onStudyCanvasInsight: { canvasMode.canvasStudyRequest += 1 },
            onInquireConnection: { canvasMode.canvasInquireConnectionRequest += 1 },
            onQuoteCanvasItem: {
                guard canvasMode.canvasQuoteTarget != nil else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    isInsightAskMode = true
                }
            },
            usesCanvasAskFlow: true,
            isCanvasAskMode: isInsightAskMode,
            onAskInNewConversation: {
                guard let insight = canvasMode.canvasQuoteTarget else { return }
                isInsightAskMode = false
                onQuoteInsightIntoNewConversation(insight)
            },
            onAskInExistingConversation: {
                guard let insight = canvasMode.canvasQuoteTarget else { return }
                quotePickerInsight = insight
            },
            onCancelCanvasAsk: {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    isInsightAskMode = false
                }
            },
            onMidpointConcepts: { canvasMode.canvasMidpointEnterRequest += 1 },
            isMidpointMode: canvasMode.isCanvasMidpointMode,
            isStudyMode: canvasMode.isCanvasStudyMode,
            isStudyToolsActive: canvasMode.isCanvasStudyToolsActive,
            onToggleStudyTools: { canvasMode.canvasStudyToolsToggleRequest += 1 },
            studyBranchCount: canvasMode.canvasStudyBranchCount,
            onStudyBranchCountChange: { canvasMode.canvasStudyBranchCount = $0 },
            isCanvasInsightLoading: canvasMode.isCanvasInsightGenerating,
            modelTasks: modelTasks,
            modelTasksPopupState: modelTasksPopupState,
            onMidpointCenter: { canvasMode.canvasMidpointCenterRequest += 1 },
            onMidpointPlace: { canvasMode.canvasMidpointPlaceRequest += 1 },
            onClearCanvasSelection: { canvasMode.canvasClearSelectionRequest += 1 },
            onContextWillOpen: {
                if canvasMode.isTopicCanvasVisible { canvasMode.canvasDismissHoverRequest += 1 }
            },
            contextCard: insightContextCardState
        )
    }
}

// MARK: - Files Section

/// Displays uploaded files for a study topic — shown above the conversations list.
private struct StudyTopicFilesSection: View {
    let files: [UploadedFile]
    var onRemove: (UploadedFile) -> Void

    /// Matches the UploadedFileThumbnail outer frame (76px image + 5px padding each side).
    private let thumbnailWidth: CGFloat = 86
    /// Width of the edge fade overlays. Leading padding is doubled so the first
    /// item sits fully past the gradient before scrolling begins.
    private let fadeWidth: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Files")
                .font(.custom("Figtree-Bold", size: 14))
                .foregroundColor(AquinasTheme.Colors.paragraphText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(files) { file in
                        VStack(spacing: 8) {
                            UploadedFileThumbnail(file: file, onRemove: {
                                onRemove(file)
                            })

                            Text(file.name)
                                .font(.custom("Figtree-Regular", size: 11))
                                .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.6))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: thumbnailWidth)
                        }
                    }
                }
                .padding(.vertical, 18)
                // Leading inset keeps the first item clear of the fade.
                .padding(.leading, fadeWidth * 2 - 12)
            }
            // Disable the scroll view's own clip rect so rotated thumbnails and
            // drop shadows render freely outside the container's frame.
            .scrollClipDisabled()
            // Edge fades: opaque canvas colour → transparent, drawn on top of the
            // scroll content. Using overlay (not mask) avoids re-clipping overflow.
            .overlay(alignment: .leading) {
                LinearGradient(
                    stops: [
                        .init(color: AquinasTheme.Colors.canvas, location: 0),
                        .init(color: AquinasTheme.Colors.canvas.opacity(0), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                LinearGradient(
                    stops: [
                        .init(color: AquinasTheme.Colors.canvas.opacity(0), location: 0),
                        .init(color: AquinasTheme.Colors.canvas, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
                .allowsHitTesting(false)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct StudyTopicTitleTextView: View {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var lineSpacing: CGFloat

    @State private var measuredHeight: CGFloat = 64

    var body: some View {
        ZStack(alignment: .topLeading) {
            AutoSizingStudyTopicTitleTextView(
                text: $text,
                isFocused: $isFocused,
                measuredHeight: $measuredHeight,
                lineSpacing: lineSpacing
            )
            .frame(height: measuredHeight)
            .frame(maxWidth: .infinity, alignment: .leading)

            if text.isEmpty {
                Text(placeholder)
                    .font(.baskervilleHeadingXLarge)
                    .lineSpacing(lineSpacing)
                    .foregroundColor(AquinasTheme.Colors.primaryReadable.opacity(0.5))
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: measuredHeight, alignment: .topLeading)
    }
}

private struct AutoSizingStudyTopicTitleTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var measuredHeight: CGFloat
    var lineSpacing: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let textView = StudyTopicSizingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.widthTracksTextView = true
        textView.returnKeyType = .done
        textView.tintColor = UIColor(AquinasTheme.Colors.secondaryMuted)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.onBoundsChange = { view in
            context.coordinator.parent.recalculateHeight(for: view)
        }
        applyTextStyle(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            textView.attributedText = attributedTitle(text)
        }
        textView.typingAttributes = typingAttributes()
        textView.textColor = .aquinasPrimaryReadable

        if isFocused, !textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        } else if !isFocused, textView.isFirstResponder {
            textView.resignFirstResponder()
        }

        recalculateHeight(for: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: UITextView, context: Context) -> CGSize? {
        guard let proposedWidth = proposal.width, proposedWidth > 8 else { return nil }
        let height = measuredHeight(for: textView, width: proposedWidth)
        updateMeasuredHeight(height)
        return CGSize(width: proposedWidth, height: height)
    }

    private func applyTextStyle(to textView: UITextView) {
        textView.attributedText = attributedTitle(text)
        textView.typingAttributes = typingAttributes()
    }

    private func attributedTitle(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: typingAttributes())
    }

    private func typingAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping

        return [
            .font: UIFont(name: "LibreBaskerville-Regular", size: 40) ?? UIFont.systemFont(ofSize: 40),
            .foregroundColor: UIColor.aquinasPrimaryReadable,
            .paragraphStyle: paragraph
        ]
    }

    private func recalculateHeight(for textView: UITextView) {
        guard textView.bounds.width > 8 else { return }
        let height = measuredHeight(for: textView, width: textView.bounds.width)
        updateMeasuredHeight(height)
    }

    private func measuredHeight(for textView: UITextView, width: CGFloat) -> CGFloat {
        textView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        return ceil(textView.sizeThatFits(targetSize).height)
    }

    private func updateMeasuredHeight(_ height: CGFloat) {
        guard abs(measuredHeight - height) > 0.5 else { return }
        DispatchQueue.main.async {
            measuredHeight = height
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoSizingStudyTopicTitleTextView

        init(parent: AutoSizingStudyTopicTitleTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text.replacingOccurrences(of: "\n", with: "")
            parent.recalculateHeight(for: textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            if replacement.contains("\n") {
                textView.resignFirstResponder()
                parent.isFocused = false
                return false
            }
            return true
        }
    }
}

private final class StudyTopicSizingTextView: UITextView {
    var onBoundsChange: ((UITextView) -> Void)?
    private var lastWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        guard abs(bounds.width - lastWidth) > 0.5 else { return }
        lastWidth = bounds.width
        onBoundsChange?(self)
    }
}
