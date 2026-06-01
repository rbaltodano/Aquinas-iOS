//
//  CurrentConversation.swift
//  Aquinas-iOS
//
//  Conversation tab — horizontal branch layout.
//  Each branch is a full-screen vertical ScrollView of ChatThreadColumn.
//  Swipe left / right to move between branches (TabView pager).
//  No canvas mode — branch mode only for now.
//

import SwiftUI
import UIKit
import PhotosUI

private final class MiniScrollButtonVisibilityRelay {
    var isAtBottom: Bool = true
}

struct CurrentConversationView: View {
    var onOpenMenu: () -> Void = {}
    @Binding var collectedDefinitions:         [ConceptDefinition]
    @Binding var sideMenuConversations:        [InquiryConversation]
    @Binding var sideMenuCurrentTitle:         String
    @Binding var sideMenuActiveConversationID: UUID?
    @Binding var requestedConversationID:      UUID?
    @Binding var newConversationRequest:       Int
    /// Set by ContentView before incrementing `newConversationRequest` when the
    /// user taps "New Conversation" inside a study topic. The new conversation
    /// is tagged with this ID, then the binding is cleared.
    @Binding var newConversationTopicID:       UUID?
    /// Set to `true` by ContentView before incrementing `newConversationRequest`
    /// when the user taps "New Study Topic". The created conversation is marked
    /// as a topic container, then this binding is cleared.
    @Binding var newConversationIsStudyTopic:  Bool
    @Binding var deletedConversationID:        UUID?
    @Binding var requestedForkConcept:         ConceptDefinition?
    let conversationFontSize: ConversationFontSizeOption
    let inputTextAlignment: InputTextAlignmentOption
    let inputFont: ConversationFontOption
    let responseFont: ConversationFontOption

    // MARK: Conversation list (source of truth for side menu)
    @State private var conversations: [InquiryConversation] = []
    @State private var activeConversationID: UUID? = nil
    @State private var handledNewConversationRequest: Int = 0

    // MARK: Branch state (working copy of the active conversation's branches)
    @State private var activeBranches: [ChatBranch] = [ChatBranch(startingConcept: nil)]
    @State private var focusedBranchID: UUID? = nil
    @State private var pendingFocusBranchID: UUID? = nil

    // MARK: Quoted insight chip
    @State private var attachedConcept: ConceptDefinition? = nil

    // MARK: Scroll / upload helpers
    @State private var externalSubmitTrigger: Int = 0
    @State private var scrollToBottomRequest: Int = 0
    // Stores the scroll anchor that was most recently focused so the
    // keyboardDidShow handler can re-scroll after the system auto-scroll fires.
    @State private var lastFocusedAnchor: String? = nil
    @State private var miniScrollButtonVisibilityRelay = MiniScrollButtonVisibilityRelay()
    @State private var isKeyboardOpen: Bool = false
    @Binding var uploadedFiles: [UploadedFile]
    @State private var targetSpawnY: CGFloat = 300
    @State private var targetSpawnResponseIndex: Int? = nil
    @State private var viewportSize: CGSize = .zero

    @State private var persistenceTask: Task<Void, Never>? = nil

    // MARK: Model controls
    @State private var areResponsesCollapsed: Bool = false
    @State private var isThinkingEnabled: Bool = false
    @State private var selectedPersonality: String = "Scholarly"
    @State private var isPersonalityMenuOpen: Bool = false
    @Binding var showFilePicker: Bool
    @State private var showPhotoPicker: Bool = false
    @State private var showCamera: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    // MARK: Insight library sheet
    @State private var isInsightLibraryOpen: Bool = false
    @State private var insightLibraryPopupHeight: CGFloat = 520

    // MARK: Insight word sheet (aq:// links)
    struct InsightWord: Identifiable { let id = UUID(); let text: String }
    @State private var activeSheetWord: InsightWord? = nil
    @State private var dynamicDefinition: ConceptDefinition? = nil
    @State private var insightSheetContentHeight: CGFloat = 178

    // MARK: Helpers
    private var effectiveFocusedID: UUID? {
        focusedBranchID ?? activeBranches.first?.id
    }

    private var insightSheetHeight: CGFloat {
        let measured   = max(insightSheetContentHeight, 178)
        let available  = max(viewportSize.height, 1)
        return min(measured + 24, available * 0.82)
    }

    // MARK: Body
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                AquinasTheme.Colors.canvas.ignoresSafeArea()

                // Horizontal branch pager
                TabView(selection: Binding(
                    get: { effectiveFocusedID },
                    set: { id in if let id { focusedBranchID = id } }
                )) {
                    ForEach($activeBranches) { $branch in
                        branchPage(branch: $branch, geo: geo)
                            .tag(branch.id as UUID?)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .bottom)

                // Menu button (top-left)
                HStack {
                    AquinasNavButton(onMenuTap: { onOpenMenu() })
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .onAppear {
                viewportSize = geo.size
                if focusedBranchID == nil {
                    focusedBranchID = activeBranches.first?.id
                }
            }
            .onChange(of: geo.size) { _, s in viewportSize = s }
        }
        .safeAreaInset(edge: .bottom) {
            InquiryControlDock(
                isCanvasMode: false,
                showFilePicker: $showFilePicker,
                showPhotoPicker: $showPhotoPicker,
                showCamera: $showCamera,
                isThinkingEnabled: $isThinkingEnabled,
                selectedPersonality: $selectedPersonality,
                isPersonalityMenuOpen: $isPersonalityMenuOpen,
                areResponsesCollapsed: $areResponsesCollapsed,
                isAtBottom: true,
                onScrollToBottom: { scrollToBottomRequest += 1 },
                onViewEntireCanvas: { },
                onOpenInsights: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isInsightLibraryOpen = true
                    }
                },
                onSend: { externalSubmitTrigger += 1 }
            )
        }
        .scrollDismissesKeyboard(.interactively)
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification
        )) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isKeyboardOpen = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification
        )) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isKeyboardOpen = false
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 8,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task {
                for item in newValue {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       UIImage(data: data) != nil {
                        await MainActor.run {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                uploadedFiles.append(
                                    UploadedFile(
                                        name: "Photo",
                                        imageData: data,
                                        rotationDegrees: Double.random(in: -5...5)
                                    )
                                )
                            }
                        }
                    }
                }
                await MainActor.run { selectedPhotoItems.removeAll() }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                if let data = image.jpegData(compressionQuality: 0.86) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        uploadedFiles.append(
                            UploadedFile(
                                name: "Camera Photo",
                                imageData: data,
                                rotationDegrees: Double.random(in: -5...5)
                            )
                        )
                    }
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: activeBranches.count) { oldCount, newCount in
            guard newCount > oldCount else { return }
            let target = pendingFocusBranchID
                .flatMap { id in activeBranches.first { $0.id == id } }
                ?? activeBranches.last
            pendingFocusBranchID = nil
            guard let target else { return }
            let targetID = target.id
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                    focusedBranchID = targetID
                }
            }
        }
        // MARK: - Persistence / conversation management
        .onAppear {
            if let snapshot = CurrentConversationsStore.load(), !snapshot.conversations.isEmpty {
                conversations = snapshot.conversations
                let targetID = snapshot.activeConversationID ?? snapshot.conversations.first?.id
                if let id = targetID, let convo = snapshot.conversations.first(where: { $0.id == id }) {
                    activeConversationID = id
                    activeBranches = convo.branches.isEmpty ? [ChatBranch(startingConcept: nil)] : convo.branches
                } else if let first = snapshot.conversations.first {
                    activeConversationID = first.id
                    activeBranches = first.branches.isEmpty ? [ChatBranch(startingConcept: nil)] : first.branches
                }
            } else {
                let initial = InquiryConversation()
                conversations = [initial]
                activeConversationID = initial.id
                activeBranches = [ChatBranch(startingConcept: nil)]
            }
            focusedBranchID = activeBranches.first?.id
            publishShellMenuState()
            scrollToBottomAfterLayout()

            // A new-conversation request may have been fired while this view was
            // unmounted (e.g. from the Study Topics page). Handle it now so the
            // correct topic-tagged conversation is created instead of showing the
            // most-recently saved one.
            if newConversationRequest != handledNewConversationRequest {
                handledNewConversationRequest = newConversationRequest
                startNewConversation()
            }
        }
        // Save branches back into the active conversation on every change, then persist.
        // saveCurrentConversation + publishShellMenuState are cheap (memory only).
        // persistConversations is debounced so UserDefaults isn't hit on every keystroke.
        .onChange(of: activeBranches) { _, _ in
            saveCurrentConversation()
            // publishShellMenuState() intentionally omitted — side menu data doesn't
            // change while typing, so calling it here causes a full AquinasSideMenu +
            // StreamingMessageView re-render on every keystroke (the source of lag).
            // It is called from onConversationTitleChange (post-submit), switchToConversation,
            // startNewConversation, and .onAppear instead.
            persistenceTask?.cancel()
            persistenceTask = Task {
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                persistConversations()
            }
        }
        // Side menu selected a conversation.
        .onChange(of: requestedConversationID) { _, id in
            guard let id, let convo = conversations.first(where: { $0.id == id }) else { return }
            requestedConversationID = nil
            switchToConversation(convo)
        }
        // "New Conversation" button in side menu.
        .onChange(of: newConversationRequest) { _, new in
            guard new != handledNewConversationRequest else { return }
            handledNewConversationRequest = new
            startNewConversation()
        }
        // Conversation deleted from side menu / Conversations page.
        .onChange(of: deletedConversationID) { _, id in
            guard let id else { return }
            deletedConversationID = nil
            conversations.removeAll { $0.id == id }
            if activeConversationID == id {
                if let first = conversations.first {
                    switchToConversation(first)
                } else {
                    startNewConversation()
                }
            }
            persistConversations()
        }
        // Sync title renames that ContentView applies directly to the sideMenuConversations binding.
        .onChange(of: sideMenuConversations) { _, updated in
            var changed = false
            for mc in updated {
                if let idx = conversations.firstIndex(where: { $0.id == mc.id }) {
                    if conversations[idx].title != mc.title {
                        conversations[idx].title = mc.title
                        changed = true
                    }
                    if conversations[idx].studyTopicID != mc.studyTopicID {
                        conversations[idx].studyTopicID = mc.studyTopicID
                        changed = true
                    }
                }
            }
            if changed { persistConversations() }
        }
        .onDisappear {
            persistenceTask?.cancel()
            saveCurrentConversation()
            persistConversations()
        }
        // aq:// insight links
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "aq", let host = url.host else { return .systemAction }
            let word = host.removingPercentEncoding ?? host
            dynamicDefinition = nil
            insightSheetContentHeight = 178
            activeSheetWord = InsightWord(text: word)
            Task { await requestDynamicDefinition(for: word) }
            return .handled
        })
        // aq:// word insight sheet
        .sheet(item: $activeSheetWord) { sheetData in
            insightSheet(for: sheetData)
        }
        // Insight library sheet (opened from "Insights" in the + menu)
        .sheet(isPresented: $isInsightLibraryOpen) {
            InsightLibraryPopup(
                currentConversationInsights: currentConversationInsights(),
                allInsights: collectedDefinitions,
                savedInsights: $collectedDefinitions,
                onQuote: { concept in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        attachedConcept = concept
                        if focusedBranchID == nil {
                            focusedBranchID = activeBranches.first?.id
                        }
                    }
                    isInsightLibraryOpen = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(180))
                        scrollToBottomRequest += 1
                    }
                },
                onFork: { concept in
                    let parentID = focusedBranchID ?? activeBranches.first?.id
                    let newBranch = ChatBranch(
                        startingConcept: concept,
                        parentBranchID: parentID,
                        parentResponseIndex: targetSpawnResponseIndex,
                        yOffset: targetSpawnY
                    )
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        insertBranch(newBranch, after: parentID)
                    }
                    isInsightLibraryOpen = false
                },
                onToggleSaved: { concept in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if collectedDefinitions.contains(where: { $0.word.caseInsensitiveCompare(concept.word) == .orderedSame }) {
                            collectedDefinitions.removeAll { $0.word.caseInsensitiveCompare(concept.word) == .orderedSame }
                        } else {
                            collectedDefinitions.append(concept)
                        }
                    }
                }
            )
            .onPreferenceChange(InsightLibraryPopupHeightKey.self) { height in
                insightLibraryPopupHeight = height
            }
            .presentationDetents([.height(insightLibrarySheetHeight)])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
        }
    }

    // MARK: - Insight library helpers

    private var insightLibrarySheetHeight: CGFloat {
        let available = max(viewportSize.height, 1)
        return min(max(insightLibraryPopupHeight, 220), available * 0.86)
    }

    private func currentConversationInsights() -> [ConceptDefinition] {
        var parts: [String] = []
        for branch in activeBranches {
            parts.append(branch.topQuestionText)
            parts.append(branch.bottomQuestionText)
            if let dup = branch.duplicatedResponse { parts.append(dup) }
            for block in branch.activeChatBlocks {
                switch block {
                case .text(let t), .user(let t, _, _): parts.append(t)
                }
            }
        }
        let lower = parts.joined(separator: " ").lowercased()
        return collectedDefinitions
            .filter { lower.contains($0.word.lowercased()) }
            .uniquedByWord()
    }

    // MARK: - Branch page

    @ViewBuilder
    private func branchPage(branch: Binding<ChatBranch>, geo: GeometryProxy) -> some View {
        let b = branch.wrappedValue
        let stableViewportHeight = max(geo.size.height, viewportSize.height)
        let bottomRunwayHeight = stableViewportHeight * (isKeyboardOpen ? 0.85 : 0.35)
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
	                ChatThreadColumn(
                    branchData: branch,
                    branchAnchor: "branch-top-\(b.id)",
                    targetSpawnY: $targetSpawnY,
                    uploadedFiles: $uploadedFiles,
                    showsPendingUploads: b.id == effectiveFocusedID,
                    quotedConcept: b.id == effectiveFocusedID ? attachedConcept : nil,
                    areResponsesCollapsed: areResponsesCollapsed,
                    targetSpawnResponseIndex: $targetSpawnResponseIndex,
                    externalSubmitTrigger: b.id == effectiveFocusedID ? externalSubmitTrigger : 0,
                    conversationFontSize: conversationFontSize,
                    inputTextAlignment: inputTextAlignment,
                    inputFont: inputFont,
                    responseFont: responseFont,
                    onSpawnYChange: { _, _ in },
                    onDuplicateResponse: { text, index in
                        let newBranch = ChatBranch(
                            startingConcept: nil,
                            parentBranchID: b.id,
                            parentResponseIndex: index,
                            duplicatedResponse: text,
                            yOffset: targetSpawnY
                        )
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            insertBranch(newBranch, after: b.id)
                        }
                    },
                    onDeleteBranch: { deleteBranch(b) },
                    onConversationTitleChange: { newTitle in
                        if let idx = conversations.firstIndex(where: { $0.id == activeConversationID }) {
                            conversations[idx].title = newTitle
                        }
                        publishShellMenuState()
                    },
                    onTopInputFocused: {
                        lastFocusedAnchor = "top-input-anchor-\(b.id)"
                    },
                    onBottomInputFocused: {
                        lastFocusedAnchor = "bottom-input-anchor-\(b.id)"
                    },
	                    onQuoteHandled: { attachedConcept = nil }
	                )
	                .padding(.horizontal, 16)

                // Extra scroll runway lets focused question fields sit higher on screen,
                // leaving room to see recent responses above the keyboard.
                Color.clear.frame(width: 1, height: bottomRunwayHeight)
                    .animation(.easeInOut(duration: 0.2), value: isKeyboardOpen)
                Color.clear
                    .frame(width: 1, height: 1)
                    .id("branch-bottom-\(b.id)")
                    .background(
                        GeometryReader { bottomGeo in
                            Color.clear
                                .onAppear {
                                    updateBottomState(for: b.id, maxY: bottomGeo.frame(in: .named("BranchScroll-\(b.id)")).maxY, viewportHeight: geo.size.height)
                                }
                                .onChange(of: bottomGeo.frame(in: .named("BranchScroll-\(b.id)")).maxY) { _, newMaxY in
                                    updateBottomState(for: b.id, maxY: newMaxY, viewportHeight: geo.size.height)
                                }
                        }
                    )
            }
            // Explicit bottom content margin larger than the dock (76 pt) so the
            // system keyboard auto-scroll places the field above the dock even when
            // TabView fails to propagate the parent's .safeAreaInset inward.
            .contentMargins(.bottom, 120, for: .scrollContent)
            .coordinateSpace(name: "BranchScroll-\(b.id)")
            .onChange(of: scrollToBottomRequest) { _, _ in
                guard b.id == effectiveFocusedID else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    proxy.scrollTo("branch-bottom-\(b.id)", anchor: .bottom)
                }
            }
            // keyboardDidShow fires AFTER the system's own auto-scroll completes,
            // so this override always wins and places the field at the top.
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardDidShowNotification
            )) { _ in
                guard b.id == effectiveFocusedID,
                      let anchor = lastFocusedAnchor else { return }
                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
        }
    }

    private func updateBottomState(for branchID: UUID, maxY: CGFloat, viewportHeight: CGFloat) {
        guard branchID == effectiveFocusedID else { return }
        let atBottom = maxY <= viewportHeight + 32
        guard miniScrollButtonVisibilityRelay.isAtBottom != atBottom else { return }
        miniScrollButtonVisibilityRelay.isAtBottom = atBottom
        NotificationCenter.default.post(
            name: .aquinasMiniScrollButtonVisibilityChanged,
            object: nil,
            userInfo: ["isVisible": !atBottom]
        )
    }

    // MARK: - Insight sheet

    @ViewBuilder
    private func insightSheet(for sheetData: InsightWord) -> some View {
        VStack(spacing: 0) {
            if let concept = dynamicDefinition {
                ConceptSheetContent(
                    concept: concept,
                    collectedDefinitions: $collectedDefinitions,
                    onInquireFurther: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            attachedConcept = concept
                            if focusedBranchID == nil {
                                focusedBranchID = activeBranches.first?.id
                            }
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(180))
                            scrollToBottomRequest += 1
                        }
                    },
                    onNewConversation: {
                        let newBranch = ChatBranch(
                            startingConcept: concept,
                            parentBranchID: effectiveFocusedID,
                            parentResponseIndex: targetSpawnResponseIndex,
                            yOffset: targetSpawnY
                        )
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            insertBranch(newBranch, after: effectiveFocusedID)
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .onPreferenceChange(InsightSheetContentHeightKey.self) { h in
                    insightSheetContentHeight = h
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(AquinasTheme.Colors.secondaryMuted)
                        .scaleEffect(1.2)
                    Text("Generating insight for \"\(sheetData.text.capitalized)\"…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AquinasTheme.Colors.canvas)
            }
        }
        .frame(maxWidth: .infinity)
        .background(AquinasTheme.Colors.canvas)
        .presentationDetents([.height(dynamicDefinition == nil ? 150 : insightSheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(AquinasTheme.Colors.canvas)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: dynamicDefinition != nil)
    }

    // MARK: - Branch management

    private func insertBranch(_ branch: ChatBranch, after parentID: UUID?) {
        pendingFocusBranchID = branch.id
        guard let parentID,
              let parentIndex = activeBranches.firstIndex(where: { $0.id == parentID }) else {
            activeBranches.append(branch)
            return
        }
        activeBranches.insert(branch, at: min(parentIndex + 1, activeBranches.count))
    }

    private func deleteBranch(_ branch: ChatBranch) {
        guard let parentID = branch.parentBranchID,
              let parent = activeBranches.first(where: { $0.id == parentID }) else { return }

        var toRemove: Set<UUID> = [branch.id]
        var queue: [UUID] = [branch.id]
        while let current = queue.popLast() {
            for b in activeBranches where b.parentBranchID == current {
                if toRemove.insert(b.id).inserted { queue.append(b.id) }
            }
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            activeBranches.removeAll { toRemove.contains($0.id) }
        }
        let returnID = parent.id
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                focusedBranchID = returnID
            }
        }
    }

    // MARK: - Conversation management

    /// Copy activeBranches back into the conversations array for the active conversation.
    private func saveCurrentConversation() {
        guard let id = activeConversationID,
              let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].branches = activeBranches
    }

    /// Update the sideMenu bindings from the current conversations list.
    private func publishShellMenuState() {
        sideMenuConversations = conversations
        sideMenuActiveConversationID = activeConversationID
        sideMenuCurrentTitle = conversations.first { $0.id == activeConversationID }?.title ?? "New Conversation"
    }

    /// Save activeBranches → conversations, then switch to a different conversation.
    private func switchToConversation(_ conversation: InquiryConversation) {
        saveCurrentConversation()
        activeConversationID = conversation.id
        activeBranches = conversation.branches.isEmpty
            ? [ChatBranch(startingConcept: nil)]
            : conversation.branches
        focusedBranchID = activeBranches.first?.id
        publishShellMenuState()
        persistConversations()
        scrollToBottomAfterLayout()
    }

    /// Save current work, then create a fresh conversation and make it active.
    private func startNewConversation() {
        saveCurrentConversation()
        // Consume any pending topic tag set by a "New Conversation inside topic" action.
        let topicID = newConversationTopicID
        newConversationTopicID = nil
        // Consume any study-topic flag set by a "New Study Topic" action.
        let isStudyTopic = newConversationIsStudyTopic
        newConversationIsStudyTopic = false
        let fresh = InquiryConversation(isStudyTopic: isStudyTopic, studyTopicID: topicID)
        conversations.insert(fresh, at: 0)
        activeConversationID = fresh.id
        activeBranches = [ChatBranch(startingConcept: nil)]
        focusedBranchID = activeBranches.first?.id
        publishShellMenuState()
        persistConversations()
        scrollToBottomAfterLayout()
    }

    private func scrollToBottomAfterLayout() {
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            scrollToBottomRequest += 1
        }
    }

    /// Encode the current conversations list to UserDefaults.
    private func persistConversations() {
        CurrentConversationsStore.save(
            InquiryPersistenceSnapshot(conversations: conversations, activeConversationID: activeConversationID)
        )
    }

    // MARK: - Insight definition (prototype)

    private func requestDynamicDefinition(for word: String) async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        dynamicDefinition = ConceptDefinition(
            word: word.capitalized,
            partOfSpeech: "noun",
            pronunciation: "| \(word) |",
            meaning: "This concept appears in the response as a key theological or philosophical term. A full definition will be generated by the model in the connected version of the app.",
            example: "Tap 'Inquire Further' to explore \(word.capitalized) in a new conversation."
        )
    }
}

// MARK: - Conversation persistence store

/// UserDefaults store for CurrentConversationView's full conversation list.
/// Uses a key separate from ActiveInquiryView's store to avoid collisions.
enum CurrentConversationsStore {
    private static let key = "aquinas.current.conversations.v1"

    static func load() -> InquiryPersistenceSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(InquiryPersistenceSnapshot.self, from: data)
    }

    static func save(_ snapshot: InquiryPersistenceSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
