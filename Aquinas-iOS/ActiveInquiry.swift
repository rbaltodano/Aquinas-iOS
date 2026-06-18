//
//  ActiveInquiry.swift
//  Aquinas-iOS
//
//  Created by Ryan on 4/14/26.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Active Inquiry Screen

struct ActiveInquiryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var activePage: AppPage
    @Binding var sideMenuConversations: [InquiryConversation]
    @Binding var sideMenuActiveConversationID: UUID?
    @Binding var sideMenuCurrentTitle: String
    @Binding var requestedConversationID: UUID?
    @Binding var newConversationRequest: Int
    @Binding var requestedForkConcept: ConceptDefinition?
    @Binding var colorSchemeOverride: ColorScheme?
    @Binding var isAtBottom: Bool
    @Binding var showFilePicker: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool

    @Binding var questionText: String
    @Binding var uploadedFiles: [UploadedFile]
    @Binding var collectedDefinitions: [ConceptDefinition]

    let brandGreen = AquinasTheme.Colors.secondaryMuted
    let backgroundColor = AquinasTheme.Colors.canvas

    @State private var conversations: [InquiryConversation] = [InquiryConversation()]
    @State private var activeConversationID: UUID? = nil
    @State private var activeBranches: [ChatBranch] = [ChatBranch(startingConcept: nil)]
    @State private var isZoomedOut: Bool = false
    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasZoomOffset: CGSize = .zero
    @State private var focusedBranchID: UUID? = nil
    @State private var isViewingEntireCanvas: Bool = false
    @State private var viewportSize: CGSize = .zero
    @State private var isThinkingEnabled: Bool = false
    @State private var selectedPersonality: String = "Friendly"
    @State private var isPersonalityMenuOpen: Bool = false
    @State private var isSideMenuOpen: Bool = false
    @State private var isInsightLibraryOpen: Bool = false
    @State private var insightLibraryPopupHeight: CGFloat = 520
    @State private var areResponsesCollapsed: Bool = false
    @State private var scrollToBottomRequest: Int = 0
    @State private var viewEntireCanvasRequest: Int = 0
    @State private var pendingPersistenceWorkItem: DispatchWorkItem? = nil
    @State private var hasRestoredPersistedConversations: Bool = false
    @State private var handledNewConversationRequest: Int = 0
    @State private var pendingFocusBranchID: UUID? = nil

    // Latest measured center Y of the response card that can spawn the next branch.
    @State private var targetSpawnY: CGFloat = 300
    @State private var targetSpawnResponseIndex: Int? = nil

    struct TriggerWord: Identifiable {
        let id = UUID()
        let text: String
    }

    @State private var activeSheetWord: TriggerWord? = nil
    @State private var dynamicDefinition: ConceptDefinition? = nil
    @State private var attachedConcept: ConceptDefinition? = nil
    @State private var insightSheetContentHeight: CGFloat = 178

    // MARK: Editable Layout Constants
    // branchSpacing: distance between lanes in focused Branch mode.
    // canvasBranchSpacing: distance between lanes in free Canvas mode.
    // overviewBranchSpacing: distance between lanes in "View Entire Canvas".
    private let branchSpacing: CGFloat = 64
    private let canvasBranchSpacing: CGFloat = 88
    private let overviewBranchSpacing: CGFloat = 88
    private let bottomAnchorID = "inquiry-bottom-anchor"

    private func branchAnchor(for branch: ChatBranch) -> String {
        "branch-anchor-\(branch.id)"
    }

    private func bottomInputAnchor(for branch: ChatBranch) -> String {
        "bottom-input-anchor-\(branch.id)"
    }

    private func currentConversationTitle() -> String {
        conversations.first { $0.id == activeConversationID }?.title ?? "New Conversation"
    }

    private func publishShellMenuState() {
        let snapshot = persistenceSnapshot()
        sideMenuConversations = snapshot.conversations
        sideMenuActiveConversationID = snapshot.activeConversationID
        sideMenuCurrentTitle = currentConversationTitle()
    }

    private func handleRequestedConversationIfNeeded() {
        guard let requestedConversationID,
              let conversation = conversations.first(where: { $0.id == requestedConversationID }) else {
            return
        }

        self.requestedConversationID = nil
        switchToConversation(conversation)
    }

    /// Number of saved insights not yet seen on the Insight Tree.
    /// Reactive: recomputes whenever collectedDefinitions changes.
    private var newInsightsCount: Int {
        guard let strings = UserDefaults.standard.stringArray(forKey: "AquinasSeenInsightIDs"),
              !strings.isEmpty else { return 0 }
        let seenIDs = Set(strings.compactMap { UUID(uuidString: $0) })
        return collectedDefinitions.filter { !seenIDs.contains($0.id) }.count
    }

    private func handleNewConversationRequestIfNeeded() {
        guard newConversationRequest != handledNewConversationRequest else { return }

        handledNewConversationRequest = newConversationRequest
        startNewConversation()
    }

    private func currentConversationInsights() -> [ConceptDefinition] {
        var conversationText = ""

        for branch in activeBranches {
            conversationText += " \(branch.topQuestionText) \(branch.bottomQuestionText) \(branch.duplicatedResponse ?? "")"

            for block in branch.activeChatBlocks {
                switch block {
                case .text(let text):
                    conversationText += " \(text)"
                case .user(let text, _, _):
                    conversationText += " \(text)"
                }
            }
        }

        let lowercasedConversationText = conversationText.lowercased()
        let savedInsightsInConversation = collectedDefinitions.filter { insight in
            lowercasedConversationText.contains(insight.word.lowercased())
        }

        return savedInsightsInConversation.uniquedByWord()
    }

    private func quoteInsightIntoCurrentThread(_ concept: ConceptDefinition) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            attachedConcept = concept
            if focusedBranchID == nil {
                focusedBranchID = activeBranches.first?.id
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            scrollToBottomRequest += 1
        }
    }

    private func forkInsightIntoNewBranch(_ concept: ConceptDefinition) {
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
    }

    private func toggleSavedInsight(_ concept: ConceptDefinition) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if collectedDefinitions.contains(where: { $0.word.caseInsensitiveCompare(concept.word) == .orderedSame }) {
                collectedDefinitions.removeAll { $0.word.caseInsensitiveCompare(concept.word) == .orderedSame }
            } else {
                collectedDefinitions.append(concept)
                collectedDefinitions = collectedDefinitions.uniquedByWord()
            }
        }
    }

    private func activeConversationIDForStorage() -> UUID? {
        activeConversationID ?? conversations.first?.id
    }

    private func persistenceSnapshot(title: String? = nil) -> InquiryPersistenceSnapshot {
        var savedConversations = conversations.isEmpty ? [InquiryConversation()] : conversations
        let conversationID = activeConversationIDForStorage()

        if let conversationID,
           let index = savedConversations.firstIndex(where: { $0.id == conversationID }) {
            savedConversations[index].branches = activeBranches
            if let title {
                savedConversations[index].title = title
            }
        }

        return InquiryPersistenceSnapshot(
            conversations: savedConversations,
            activeConversationID: conversationID ?? savedConversations.first?.id
        )
    }

    private func saveConversationMemory(title: String? = nil) {
        guard hasRestoredPersistedConversations else { return }
        InquiryPersistenceStore.save(persistenceSnapshot(title: title))
    }

    private func restoreConversationMemoryIfNeeded() {
        guard !hasRestoredPersistedConversations else { return }

        if let snapshot = InquiryPersistenceStore.load(), !snapshot.conversations.isEmpty {
            conversations = snapshot.conversations
            let restoredID = snapshot.activeConversationID.flatMap { id in
                snapshot.conversations.contains(where: { $0.id == id }) ? id : nil
            } ?? snapshot.conversations.first?.id

            activeConversationID = restoredID
            activeBranches = snapshot.conversations.first(where: { $0.id == restoredID })?.branches ?? snapshot.conversations[0].branches
            if activeBranches.isEmpty {
                activeBranches = [ChatBranch(startingConcept: nil)]
            }
            focusedBranchID = activeBranches.first?.id
        } else {
            activeConversationID = conversations.first?.id
            focusedBranchID = activeBranches.first?.id
        }

        hasRestoredPersistedConversations = true
        saveConversationMemory()
        publishShellMenuState()
    }

    private func persistActiveConversation(title: String? = nil) {
        let conversationID = activeConversationID ?? conversations.first?.id
        guard let conversationID,
              let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }

        conversations[index].branches = activeBranches
        if let title {
            conversations[index].title = title
        }
        saveConversationMemory(title: title)
    }

    private func renameActiveConversation(to title: String) {
        guard let conversationID = activeConversationID ?? conversations.first?.id,
              let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }

        conversations[index].title = title
        saveConversationMemory(title: title)
        publishShellMenuState()
    }

    private func renameConversation(_ conversation: InquiryConversation, to title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else {
            return
        }

        conversations[index].title = title
        saveConversationMemory(title: conversation.id == activeConversationID ? title : nil)
        publishShellMenuState()
    }

    private func switchToConversation(_ conversation: InquiryConversation) {
        persistActiveConversation()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            activeConversationID = conversation.id
            activeBranches = conversation.branches
            focusedBranchID = conversation.branches.first?.id
            isZoomedOut = false
            isViewingEntireCanvas = false
            canvasScale = 1.0
            canvasZoomOffset = .zero
            attachedConcept = nil
            uploadedFiles.removeAll()
            isSideMenuOpen = false
        }
        saveConversationMemory()
        publishShellMenuState()
    }

    private func pinConversation(_ conversation: InquiryConversation) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        let pinnedConversation = conversations.remove(at: index)
        conversations.insert(pinnedConversation, at: 0)
        saveConversationMemory()
        publishShellMenuState()
    }

    private func deleteConversation(_ conversation: InquiryConversation) {
        guard conversations.count > 1 else {
            startNewConversation()
            conversations = conversations.suffix(1)
            saveConversationMemory()
            publishShellMenuState()
            return
        }

        let deletedActiveConversation = conversation.id == (activeConversationID ?? conversations.first?.id)
        conversations.removeAll { $0.id == conversation.id }

        if deletedActiveConversation, let nextConversation = conversations.first {
            activeConversationID = nextConversation.id
            activeBranches = nextConversation.branches
            focusedBranchID = nextConversation.branches.first?.id
            isZoomedOut = false
            isViewingEntireCanvas = false
            canvasScale = 1.0
            canvasZoomOffset = .zero
        }
        saveConversationMemory()
        publishShellMenuState()
    }

    private func focusedBranchIndex() -> Int {
        guard let focusedBranchID,
              let index = activeBranches.firstIndex(where: { $0.id == focusedBranchID }) else {
            return 0
        }
        return index
    }

    private func branchIDsToRemove(startingAt branchID: UUID) -> Set<UUID> {
        var idsToRemove: Set<UUID> = [branchID]
        var didAddChild = true

        while didAddChild {
            didAddChild = false
            for branch in activeBranches where branch.parentBranchID.map(idsToRemove.contains) == true {
                if idsToRemove.insert(branch.id).inserted {
                    didAddChild = true
                }
            }
        }

        return idsToRemove
    }

    /// Inserts a fork directly to the right of its parent lane instead of appending it to the far end.
    private func insertBranch(_ branch: ChatBranch, after parentID: UUID?) {
        pendingFocusBranchID = branch.id

        guard let parentID,
              let parentIndex = activeBranches.firstIndex(where: { $0.id == parentID }) else {
            activeBranches.append(branch)
            return
        }

        let insertionIndex = min(parentIndex + 1, activeBranches.count)
        activeBranches.insert(branch, at: insertionIndex)
    }

    /// Calculates the max-fit zoom for the "View Entire Canvas" button.
    private func fitCanvasScale(for size: CGSize) -> CGFloat {
        guard !activeBranches.isEmpty, size.width > 0 else { return 0.8 }
        let branchCount = CGFloat(activeBranches.count)
        let spacingCount = CGFloat(max(activeBranches.count - 1, 0))
        let availableWidth = max(size.width - 24, 1)
        let worldWidth = (branchCount * size.width) + (spacingCount * overviewBranchSpacing)
        let widthScale = availableWidth / max(worldWidth, 1)
        return min(1.0, max(0.18, widthScale))
    }

    private func canvasOffsetForFocusedBranch(in size: CGSize, scale: CGFloat) -> CGSize {
        canvasOffsetForBranch(at: focusedBranchIndex(), in: size, scale: scale)
    }

    private func canvasOffsetForBranch(at index: Int, in size: CGSize, scale: CGFloat) -> CGSize {
        let index = CGFloat(index)
        let laneStep = (size.width + canvasBranchSpacing) * scale
        return CGSize(width: -index * laneStep, height: 0)
    }

    private func fitCanvasOffset(for size: CGSize, scale: CGFloat) -> CGSize {
        let branchCount = CGFloat(activeBranches.count)
        let spacingCount = CGFloat(max(activeBranches.count - 1, 0))
        let scaledContentWidth = ((branchCount * size.width) + (spacingCount * overviewBranchSpacing)) * scale
        let horizontalInset = max(12, (size.width - scaledContentWidth) / 2)
        return CGSize(width: horizontalInset, height: 40)
    }

    private func clampedCanvasScale(_ proposedScale: CGFloat, in size: CGSize) -> CGFloat {
        let minimumScale = min(0.12, fitCanvasScale(for: size))
        return min(1.0, max(minimumScale, proposedScale))
    }

    private func canvasOffsetKeeping(
        _ anchor: CGPoint,
        fixedFrom initialOffset: CGSize,
        initialScale: CGFloat,
        nextScale: CGFloat
    ) -> CGSize {
        let worldX = (anchor.x - initialOffset.width) / initialScale
        let worldY = (anchor.y - initialOffset.height) / initialScale

        return CGSize(
            width: anchor.x - worldX * nextScale,
            height: anchor.y - worldY * nextScale
        )
    }

    /// Updates the stored yOffset on child branches so Canvas Mode connector lines stay attached.
    private func updateChildren(of parentID: UUID, responseIndex: Int, to yOffset: CGFloat) {
        for index in activeBranches.indices
        where activeBranches[index].parentBranchID == parentID
            && activeBranches[index].parentResponseIndex == responseIndex {
            activeBranches[index].yOffset = yOffset
        }
    }

    /// Animates the camera to fully focus the given branch (scale = 1, offset centred on branch).
    private func focusBranch(_ branch: ChatBranch) {
        let idx = activeBranches.firstIndex(where: { $0.id == branch.id }) ?? 0
        let laneStep = viewportSize.width + canvasBranchSpacing
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
            focusedBranchID = branch.id
            isZoomedOut = false
            isViewingEntireCanvas = false
            canvasScale = 1.0
            canvasZoomOffset = CGSize(width: -CGFloat(idx) * laneStep, height: 0)
        }
    }

    /// Resets the current prototype thread without leaving the active inquiry surface.
    private func startNewConversation() {
        persistActiveConversation()
        let newConversation = InquiryConversation()

        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            conversations.append(newConversation)
            activeConversationID = newConversation.id
            activeBranches = newConversation.branches
            focusedBranchID = newConversation.branches.first?.id
            isZoomedOut = false
            isViewingEntireCanvas = false
            canvasScale = 1.0
            canvasZoomOffset = .zero
            areResponsesCollapsed = false
            attachedConcept = nil
            uploadedFiles.removeAll()
            questionText = ""
            isSideMenuOpen = false
        }
        saveConversationMemory()
        publishShellMenuState()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func toggleCanvasMode() {
        dismissKeyboard()
        if isZoomedOut {
            guard let focused = activeBranches.first(where: { $0.id == focusedBranchID }) ?? activeBranches.first else { return }
            focusBranch(focused)
        } else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                isZoomedOut = true
                isViewingEntireCanvas = false
                canvasScale = 0.80
                canvasZoomOffset = canvasOffsetForFocusedBranch(in: viewportSize, scale: 0.80)
            }
        }
    }

    /// Horizontal swipe anywhere on the focused branch zooms the camera out to canvas mode.
    private var canvasActivationGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                guard canvasScale >= ConversationCanvasCameraView<AnyView>.focusedScaleThreshold else { return }
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.4
                guard isHorizontal && abs(value.translation.width) > 60 else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    isZoomedOut = true
                    isViewingEntireCanvas = false
                    canvasScale = 0.80
                    canvasZoomOffset = canvasOffsetForFocusedBranch(in: viewportSize, scale: 0.80)
                }
            }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundColor.ignoresSafeArea()

            GeometryReader { geo in
                ConversationCanvasCameraView(
                    branches: $activeBranches,
                    scale: $canvasScale,
                    offset: $canvasZoomOffset,
                    isViewingEntireCanvas: $isViewingEntireCanvas,
                    size: geo.size,
                    focusedBranchID: focusedBranchID ?? activeBranches.first?.id,
                    branchSpacing: canvasBranchSpacing,
                    areResponsesCollapsed: areResponsesCollapsed,
                    makeFullBranch: { $branch, size in
                        // Each branch renders its own ScrollView so vertical scroll
                        // stays native when the camera is fully zoomed in.
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                ChatThreadColumn(
                                    branchData: $branch,
                                    branchAnchor: branchAnchor(for: branch),
                                    targetSpawnY: $targetSpawnY,
                                    uploadedFiles: $uploadedFiles,
                                    showsPendingUploads: branch.id == (focusedBranchID ?? activeBranches.first?.id),
                                    quotedConcept: branch.id == (focusedBranchID ?? activeBranches.first?.id) ? attachedConcept : nil,
                                    areResponsesCollapsed: areResponsesCollapsed,
                                    targetSpawnResponseIndex: $targetSpawnResponseIndex,
                                    onSpawnYChange: { responseIndex, yOffset in
                                        updateChildren(of: branch.id, responseIndex: responseIndex, to: yOffset)
                                    },
                                    onDuplicateResponse: { responseText, responseIndex in
                                        let newBranch = ChatBranch(
                                            startingConcept: nil,
                                            parentBranchID: branch.id,
                                            parentResponseIndex: responseIndex,
                                            duplicatedResponse: responseText,
                                            yOffset: targetSpawnY
                                        )
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                            insertBranch(newBranch, after: branch.id)
                                        }
                                    },
                                    onDeleteBranch: {
                                        guard let parentID = branch.parentBranchID else { return }
                                        let fallback = activeBranches.first { $0.id == parentID } ?? activeBranches.first
                                        let toRemove = branchIDsToRemove(startingAt: branch.id)
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                            activeBranches.removeAll { toRemove.contains($0.id) }
                                        }
                                        if let fallback {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                                focusBranch(fallback)
                                            }
                                        }
                                    },
                                    onConversationTitleChange: { title in renameActiveConversation(to: title) },
                                    onBottomInputFocused: {
                                        guard canvasScale >= ConversationCanvasCameraView<AnyView>.focusedScaleThreshold else { return }
                                        let anchor = bottomInputAnchor(for: branch)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                                                proxy.scrollTo(anchor, anchor: .top)
                                            }
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                                            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                                                proxy.scrollTo(anchor, anchor: .top)
                                            }
                                        }
                                    },
                                    onQuoteHandled: { attachedConcept = nil }
                                )

                                Color.clear.frame(width: 1, height: 1)
                                    .id("branch-bottom-\(branch.id)")
                                    .background(
                                        GeometryReader { bg in
                                            Color.clear
                                                .onAppear {
                                                    if branch.id == (focusedBranchID ?? activeBranches.first?.id) {
                                                        isAtBottom = bg.frame(in: .named("BranchScroll-\(branch.id)")).maxY <= geo.size.height + 32
                                                    }
                                                }
                                                .onChange(of: bg.frame(in: .named("BranchScroll-\(branch.id)")).maxY) { _, newY in
                                                    if branch.id == (focusedBranchID ?? activeBranches.first?.id) {
                                                        isAtBottom = newY <= geo.size.height + 32
                                                    }
                                                }
                                        }
                                    )
                            }
                            .coordinateSpace(name: "BranchScroll-\(branch.id)")
                            .onChange(of: scrollToBottomRequest) { _, _ in
                                guard branch.id == (focusedBranchID ?? activeBranches.first?.id),
                                      canvasScale >= ConversationCanvasCameraView<AnyView>.focusedScaleThreshold
                                else { return }
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                    proxy.scrollTo("branch-bottom-\(branch.id)", anchor: .bottom)
                                }
                            }
                            .onChange(of: focusedBranchID) { _, newID in
                                guard newID == branch.id else { return }
                                // Scroll to top when camera re-focuses this branch.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        proxy.scrollTo(branchAnchor(for: branch), anchor: .top)
                                    }
                                }
                            }
                        }
                    },
                    onFocusBranch: { branch in
                        focusBranch(branch)
                    }
                )
                .simultaneousGesture(canvasActivationGesture)
                .onAppear { viewportSize = geo.size }
                .onChange(of: geo.size) { _, newSize in viewportSize = newSize }
                .onChange(of: activeBranches.count) { oldCount, newCount in
                    guard newCount > oldCount else { return }
                    let target = pendingFocusBranchID.flatMap { id in
                        activeBranches.first { $0.id == id }
                    } ?? activeBranches.last
                    pendingFocusBranchID = nil
                    guard let target else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusBranch(target)
                    }
                }
                .onChange(of: viewEntireCanvasRequest) { _, _ in
                    if isViewingEntireCanvas {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            isZoomedOut = true
                            isViewingEntireCanvas = false
                            canvasScale = 0.80
                            canvasZoomOffset = canvasOffsetForFocusedBranch(in: geo.size, scale: 0.80)
                        }
                    } else {
                        let fitScale = fitCanvasScale(for: geo.size)
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            isZoomedOut = true
                            isViewingEntireCanvas = true
                            canvasScale = fitScale
                            canvasZoomOffset = fitCanvasOffset(for: geo.size, scale: fitScale)
                        }
                    }
                }
            }

        }
        .safeAreaInset(edge: .bottom) {
            InquiryControlDock(
                isCanvasMode: isZoomedOut,
                showFilePicker: $showFilePicker,
                showPhotoPicker: $showPhotoPicker,
                showCamera: $showCamera,
                isThinkingEnabled: $isThinkingEnabled,
                selectedPersonality: $selectedPersonality,
                isPersonalityMenuOpen: $isPersonalityMenuOpen,
                areResponsesCollapsed: $areResponsesCollapsed,
                isAtBottom: isAtBottom,
                onScrollToBottom: {
                    scrollToBottomRequest += 1
                },
                onViewEntireCanvas: {
                    viewEntireCanvasRequest += 1
                },
                onOpenInsights: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isInsightLibraryOpen = true
                    }
                }
            )
        }
        .overlay(alignment: .topLeading) {
            if !isSideMenuOpen {
                SideMenuTriggerButton {
                    dismissKeyboard()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        isSideMenuOpen = true
                    }
                }
                .padding(.leading, 24)
                .padding(.top, 24)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isSideMenuOpen {
                CanvasModeToggleButton(isActive: isZoomedOut, action: toggleCanvasMode)
                    .padding(.trailing, 24)
                    .padding(.top, 24)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .overlay {
            if isSideMenuOpen {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                            isSideMenuOpen = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .overlay(alignment: .leading) {
            AquinasSideMenu(
                currentTitle: currentConversationTitle(),
                conversations: conversations,
                activeConversationID: activeConversationID ?? conversations.first?.id,
                activePage: .conversation,
                selectedPersonality: selectedPersonality,
                isPresented: isSideMenuOpen,
                onNewChat: startNewConversation,
                onSelectConversation: switchToConversation,
                onRenameConversation: { conversation, title in
                    renameConversation(conversation, to: title)
                },
                onPinConversation: pinConversation,
                onAddConversationToStudyTopic: { conversation, topicID in
                    if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                        conversations[index].studyTopicID = topicID
                        saveConversationMemory()
                        publishShellMenuState()
                    }
                },
                onDeleteConversation: deleteConversation,
                newInsightsCount: newInsightsCount,
                onOpenConversations: {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        isSideMenuOpen = false
                    }
                    activePage = .openConversations
                },
                onOpenInsights: {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        isSideMenuOpen = false
                    }
                    activePage = .insights
                },
                onOpenStudyTopics: {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        isSideMenuOpen = false
                    }
                    activePage = .studyTopics
                },
                onOpenSettings: {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        isSideMenuOpen = false
                    }
                    activePage = .settings
                },
                onClose: {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        isSideMenuOpen = false
                    }
                }
            )
            .frame(width: 325)
            .offset(x: isSideMenuOpen ? 0 : -345)
            .opacity(isSideMenuOpen ? 1 : 0.96)
            .zIndex(4)
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isSideMenuOpen)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            restoreConversationMemoryIfNeeded()
            handleRequestedConversationIfNeeded()
            handleNewConversationRequestIfNeeded()
            publishShellMenuState()
        }
        .onDisappear {
            saveConversationMemory()
        }
        .onChange(of: scenePhase) { oldValue, newValue in
            if newValue != .active {
                saveConversationMemory()
            }
        }
        .onChange(of: activeBranches) { _, _ in
            publishShellMenuState()
            pendingPersistenceWorkItem?.cancel()
            let work = DispatchWorkItem { saveConversationMemory() }
            pendingPersistenceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
        .onChange(of: activeConversationID) { oldValue, newValue in
            saveConversationMemory()
            publishShellMenuState()
        }
        .onChange(of: conversations) { oldValue, newValue in
            publishShellMenuState()
        }
        .onChange(of: requestedConversationID) { oldValue, newValue in
            handleRequestedConversationIfNeeded()
        }
        .onChange(of: newConversationRequest) { oldValue, newValue in
            handleNewConversationRequestIfNeeded()
        }
        .onChange(of: requestedForkConcept) { _, concept in
            guard let concept else { return }
            forkInsightIntoNewBranch(concept)
            requestedForkConcept = nil
        }
        .sheet(isPresented: $isInsightLibraryOpen) {
            InsightLibraryPopup(
                currentConversationInsights: currentConversationInsights(),
                allInsights: collectedDefinitions,
                savedInsights: $collectedDefinitions,
                onQuote: { concept in
                    quoteInsightIntoCurrentThread(concept)
                    isInsightLibraryOpen = false
                },
                onFork: { concept in
                    forkInsightIntoNewBranch(concept)
                    isInsightLibraryOpen = false
                },
                onToggleSaved: toggleSavedInsight
            )
            .onPreferenceChange(InsightLibraryPopupHeightKey.self) { height in
                insightLibraryPopupHeight = height
            }
            .presentationDetents([.height(insightLibrarySheetHeight)])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
        }
        // MARK: Insight Link Handling
        // Markdown links formatted as aq://word open the generated Insight sheet.
        .tint(brandGreen)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "aq", let tappedWord = url.host {
                let cleanWord = tappedWord.removingPercentEncoding ?? tappedWord
                dynamicDefinition = nil
                insightSheetContentHeight = 178
                activeSheetWord = TriggerWord(text: cleanWord)
                Task { await requestDynamicDefinition(for: cleanWord) }
                return .handled
            }
            return .systemAction
        })

        // MARK: Insight Sheet
        // Quote returns the insight chip to the current branch; fork creates a new branch from that insight.
        .sheet(item: $activeSheetWord) { sheetData in
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
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                scrollToBottomRequest += 1
                            }
                        },
                        onNewConversation: {
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
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .onPreferenceChange(InsightSheetContentHeightKey.self) { height in
                        insightSheetContentHeight = height
                    }
                } else {
                    VStack(spacing: 16) {
                        ProgressView().tint(brandGreen).scaleEffect(1.2)
                        Text("Generating insight for \"\(sheetData.text.capitalized)\"...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(brandGreen)
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
    }

    private var insightSheetHeight: CGFloat {
        let measuredContent = max(insightSheetContentHeight, 178)
        let availableHeight = max(viewportSize.height, 1)
        return min(measuredContent + 24, availableHeight * 0.82)
    }

    private var insightLibrarySheetHeight: CGFloat {
        let availableHeight = max(viewportSize.height, 1)
        return min(max(insightLibraryPopupHeight, 220), availableHeight * 0.86)
    }

    private func requestDynamicDefinition(for word: String) async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let generatedCard = ConceptDefinition(
            word: word.capitalized, partOfSpeech: "noun", pronunciation: "| generated |",
            meaning: "Thomism is the philosophical and theological school of thought that arose as a legacy of the work of St. Thomas Aquinas (1225–1274). It is characterized by its rigorous logic and its attempt to harmonize Christian revelation with Aristotelian philosophy.",
            example: "The model detected that '\(word)' was a relevant term and created this on the fly."
        )
        await MainActor.run { self.dynamicDefinition = generatedCard }
    }
}

// MARK: - Lightweight Canvas Map

/// Canvas Mode view: static full-column previews of every branch, with connector lines.
struct LightweightCanvasMapView: View {
    let branches: [ChatBranch]
    let branchWidth: CGFloat
    let branchSpacing: CGFloat
    let areResponsesCollapsed: Bool
    let topPadding: (ChatBranch) -> CGFloat
    var onSelectBranch: (ChatBranch) -> Void

    private func laneX(for index: Int) -> CGFloat {
        CGFloat(index) * (branchWidth + branchSpacing)
    }

    private func previewHeight(for branch: ChatBranch) -> CGFloat {
        let blockCount = CGFloat(branch.activeChatBlocks.count)
        let responseHeight: CGFloat = areResponsesCollapsed ? 84 : 236
        let questionHeight: CGFloat = branch.topQuestionSubmitted ? 82 : 56
        return 150 + questionHeight + (blockCount * responseHeight) + 140
    }

    private func connectorY(for branch: ChatBranch) -> CGFloat {
        branch.yOffset > 0 ? branch.yOffset : topPadding(branch) + 150
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                var path = Path()

                for childIndex in branches.indices {
                    let child = branches[childIndex]
                    guard let parentID = child.parentBranchID,
                          let parentIndex = branches.firstIndex(where: { $0.id == parentID }) else {
                        continue
                    }

                    let y = connectorY(for: child)
                    let startX = laneX(for: parentIndex) + branchWidth - 24
                    let endX = laneX(for: childIndex) + 24

                    path.move(to: CGPoint(x: startX, y: y))
                    path.addLine(to: CGPoint(x: endX, y: y))
                }

                context.stroke(path, with: .color(AquinasTheme.Colors.divider), lineWidth: 1)
            }
            .allowsHitTesting(false)

            ForEach(Array(branches.enumerated()), id: \.element.id) { index, branch in
                LightweightCanvasBranchPreview(
                    branch: branch,
                    areResponsesCollapsed: areResponsesCollapsed
                )
                .frame(width: branchWidth - 24)
                .frame(height: previewHeight(for: branch), alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelectBranch(branch)
                }
                .position(
                    x: laneX(for: index) + (branchWidth / 2),
                    y: topPadding(branch) + (previewHeight(for: branch) / 2)
                )
            }
        }
    }
}

private struct LightweightCanvasBranchPreview: View {
    let branch: ChatBranch
    let areResponsesCollapsed: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var title: String {
        branch.generatedBranchTitle ?? (branch.parentBranchID == nil ? "New Conversation" : "New Branch")
    }

    private var contextTitle: String? {
        if let concept = branch.branchContextConcept ?? branch.startingConcept {
            return concept.word.capitalized
        }

        if let duplicatedResponse = branch.duplicatedResponse {
            return generatedContextTitle(from: duplicatedResponse)
        }

        return nil
    }

    private var contextIcon: String {
        (branch.branchContextConcept ?? branch.startingConcept) == nil ? "arrow.triangle.branch" : "text.bubble.fill"
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                Image("cross-1")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundColor(AquinasTheme.Colors.accent)

                Text(title)
                    .font(.custom("LibreBaskerville-Regular", size: 28))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
            }
            .padding(.top, 24)

            if let contextTitle {
                HStack(spacing: 8) {
                    Image(systemName: contextIcon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(contextTitle)
                        .font(.baskervilleSmall)
                        .lineLimit(1)
                }
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(AquinasTheme.Colors.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AquinasTheme.Colors.border, lineWidth: 1)
                }
            }

            if branch.topQuestionSubmitted, !branch.topQuestionText.isEmpty {
                Text(branch.topQuestionText)
                    .font(.custom("LibreBaskerville-Regular", size: 16))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
            } else {
                Text("Ask Theo a question...")
                    .font(.custom("LibreBaskerville-Regular", size: 16))
                    .foregroundColor(colorScheme == .dark ? Color(hex: 0xFFFAF0, alpha: 0.50) : Color(hex: 0x4A321C, alpha: 0.50))
                    .lineLimit(1)
            }

            VStack(spacing: 18) {
                ForEach(Array(branch.activeChatBlocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let text):
                        LightweightCanvasResponseCard(text: text, isCollapsed: areResponsesCollapsed)
                    case .user(let question, let concept, let attachments):
                        LightweightCanvasUserQuestion(text: question, concept: concept, attachments: attachments)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func generatedContextTitle(from response: String) -> String {
        let stopWords: Set<String> = ["the", "a", "an", "and", "or", "but", "is", "are", "was", "were", "of", "to", "in", "for", "with", "as", "on"]
        let words = response
            .replacingOccurrences(of: "[^A-Za-z0-9\\s]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map { String($0) }
            .filter { !stopWords.contains($0.lowercased()) }
            .prefix(3)
            .map { $0.capitalized }

        return words.isEmpty ? "Response Branch" : words.joined(separator: " ")
    }
}

private struct LightweightCanvasResponseCard: View {
    let text: String
    let isCollapsed: Bool

    private var previewTitle: String {
        let stopWords: Set<String> = ["the","a","an","and","or","but","is","are","was","were","of","to","in","for","with","as","on"]
        let words = text
            .replacingOccurrences(of: "[^A-Za-z0-9\\s]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map { String($0) }
            .filter { !stopWords.contains($0.lowercased()) }
            .prefix(4)
            .map { $0.capitalized }
        return words.isEmpty ? "Response" : words.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(previewTitle)
                    .font(.figtreeHeading1)
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .lineLimit(1)

                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AquinasTheme.Colors.responseButton)
            }

            if !isCollapsed {
                Text(cleanPreviewText(text))
                    .font(.figtreeParagraphLarge)
                    .lineSpacing(8)
                    .foregroundColor(AquinasTheme.Colors.paragraphText)
                    .lineLimit(9)
            }

            HStack(spacing: 12) {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(AquinasTheme.Colors.accent)
                Image(systemName: "square.on.square")
                Image(systemName: "arrow.triangle.branch")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(AquinasTheme.Colors.responseButton)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AquinasTheme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AquinasTheme.Colors.border, lineWidth: 1)
        }
    }
}

private struct LightweightCanvasUserQuestion: View {
    let text: String
    let concept: ConceptDefinition?
    let attachments: [UploadedFile]

    var body: some View {
        VStack(spacing: 12) {
            if !attachments.isEmpty {
                HStack(spacing: -8) {
                    ForEach(attachments.prefix(3)) { file in
                        if let imageData = file.imageData,
                           let image = UIImage(data: imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AquinasTheme.Colors.uploadBorder, lineWidth: 3)
                                }
                        }
                    }
                }
            }

            if let concept {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                    Text(concept.word.capitalized)
                }
                .font(.baskervilleSmall)
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(AquinasTheme.Colors.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AquinasTheme.Colors.border, lineWidth: 1)
                }
            }

            Text(text)
                .font(.baskervilleBody)
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .lineLimit(3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private func cleanPreviewText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
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
    let areResponsesCollapsed: Bool
    @Binding var targetSpawnResponseIndex: Int?
    var externalSubmitTrigger: Int = 0
    var conversationFontSize: ConversationFontSizeOption = .large
    var inputTextAlignment: InputTextAlignmentOption = .center
    var inputFont: ConversationFontOption = .serif
    var responseFont: ConversationFontOption = .sans
    var onSpawnYChange: (Int, CGFloat) -> Void
    var onDuplicateResponse: (String, Int) -> Void
    var onDeleteBranch: () -> Void
    var onConversationTitleChange: (String) -> Void
    var onTopInputFocused: () -> Void = {}
    var onBottomInputFocused: () -> Void
    var onActiveInputTextChange: (String) -> Void = { _ in }
    var onQuoteHandled: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var branchHeadHeight: CGFloat = 0
    @State private var animatedResponseIndices: Set<Int> = []
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

    /// Placeholder text color resolved directly from the SwiftUI color-scheme environment,
    /// bypassing the Color(UIColor(dynamicProvider:)) conversion which can freeze to the
    /// light-mode value inside UIViewRepresentable-hosted view hierarchies.
    private var placeholderColor: Color {
        colorScheme == .dark
            ? Color(hex: 0xFFFAF0, alpha: 0.50)
            : Color(hex: 0x4A321C, alpha: 0.50)
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
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                branchData.activeChatBlocks.append(.text(simulatedResponse))
            }
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
        if branchData.generatedBranchTitle == nil {
            let title = generatedTitle(from: submittedQuestion)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                branchData.generatedBranchTitle = title
            }
            if branchData.parentBranchID == nil {
                onConversationTitleChange(title)
            }
        }
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
        branchData.bottomQuestionText = ""
        appendSimulatedResponse()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {

            // MARK: Branch Header
            // Cross, branch title, starting context chip, and the first editable/locked question.
            Color.clear
                .frame(height: 1)
                .id(branchAnchor)

            VStack(spacing: 18) {
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
                    }
                }
                .frame(maxWidth: .infinity)

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

                inputContainer {
                    ZStack {
                        if topFieldIsEmpty && !branchData.topQuestionSubmitted {
                            Text("Ask Theo a question...")
                                .font(inputFont.textFont(size: conversationFontSize))
                                .foregroundColor(placeholderColor)
                                .multilineTextAlignment(inputTextAlignment.textAlignment)
                                .frame(maxWidth: .infinity, alignment: inputTextAlignment.frameAlignment)
                                .allowsHitTesting(false)
                        }

                        ListAwareTextField(
                            text: $branchData.topQuestionText,
                            font: inputFont.uiFont(size: conversationFontSize),
                            isLocked: branchData.topQuestionSubmitted,
                            textColor: .aquinasPrimaryReadable,
                            textAlignment: inputTextAlignment.nsTextAlignment,
                            onFocusChange: { focused in
                                if focused { onTopInputFocused() }
                            },
                            relay: topFieldRelay,
                            onTextChange: { text in
                                topFieldIsEmpty = text.isEmpty
                                onActiveInputTextChange(text)
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: inputTextAlignment.frameAlignment)
                    }
                }
                .id("top-input-anchor-\(branchData.id)")
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
            .padding(.top, readingTopPadding)

            // MARK: Conversation Blocks
            // Alternates between user questions and model response cards.
            VStack(alignment: .center, spacing: 0) {
                ForEach(Array(branchData.activeChatBlocks.enumerated()), id: \.offset) { index, block in
                    switch block {
                    case .text(let textContent):

                        TrackedResponseCard(
                            textContent: textContent,
                            responseIndex: index,
                            shouldAnimateOnAppear: animatedResponseIndices.contains(index),
                            targetSpawnY: $targetSpawnY,
                            targetSpawnResponseIndex: $targetSpawnResponseIndex,
                            columnSpaceName: "ColumnContent-\(branchData.id)",
                            areResponsesCollapsed: areResponsesCollapsed,
                            responseFont: responseFont,
                            conversationFontSize: conversationFontSize,
                            onCenterChange: onSpawnYChange,
                            onDuplicateBranch: {
                                onDuplicateResponse(textContent, index)
                            },
                            onFinish: {
                                animatedResponseIndices.remove(index)
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { branchData.showBottomInput = true }
                            }
                        )
                        .id("\(branchData.id)-response-\(index)")
                        .transition(
                            animatedResponseIndices.contains(index)
                            ? .opacity.combined(with: .scale(scale: 0.5))
                            : .identity
                        )

                    case .user(let questionText, let quotedConcept, let attachments):
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(AquinasTheme.Colors.divider)
                                .frame(width: 1, height: 25)
                                .padding(.vertical, 16)

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
                                        textAlignment: inputTextAlignment.nsTextAlignment
                                    )
                                    .frame(maxWidth: .infinity, alignment: inputTextAlignment.frameAlignment)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity).padding(.bottom, 16)
                    }
                }
            }

            // MARK: Follow-up Input
            // Appears after the latest model response finishes.
            if branchData.showBottomInput {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(AquinasTheme.Colors.divider)
                        .frame(width: 1, height: 25)
                        .padding(.vertical, 16)

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

                        inputContainer {
                            ZStack {
                                if bottomFieldIsEmpty {
                                    Text("Ask Theo a question...")
                                        .font(inputFont.textFont(size: conversationFontSize))
                                        .foregroundColor(placeholderColor)
                                        .multilineTextAlignment(inputTextAlignment.textAlignment)
                                        .frame(maxWidth: .infinity, alignment: inputTextAlignment.frameAlignment)
                                        .allowsHitTesting(false)
                                }

                                ListAwareTextField(
                                    text: $branchData.bottomQuestionText,
                                    font: inputFont.uiFont(size: conversationFontSize),
                                    textColor: .aquinasPrimaryReadable,
                                    textAlignment: inputTextAlignment.nsTextAlignment,
                                    onFocusChange: { focused in
                                        if focused { onBottomInputFocused() }
                                    },
                                    relay: bottomFieldRelay,
                                    onTextChange: { text in
                                        bottomFieldIsEmpty = text.isEmpty
                                        onActiveInputTextChange(text)
                                    }
                                )
                                .frame(maxWidth: .infinity, alignment: inputTextAlignment.frameAlignment)
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
    }
}

// MARK: - Response Geometry Tracker

/// Wraps a response card and reports its visual center Y so child branch connector lines stay attached.
struct TrackedResponseCard: View {
    let textContent: String
    let responseIndex: Int
    let shouldAnimateOnAppear: Bool
    @Binding var targetSpawnY: CGFloat
    @Binding var targetSpawnResponseIndex: Int?
    let columnSpaceName: String
    let areResponsesCollapsed: Bool
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
            forceCollapsed: areResponsesCollapsed,
            shouldAnimateOnAppear: shouldAnimateOnAppear,
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
        .padding(.top, 16)
        .padding(.bottom, 12)
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
