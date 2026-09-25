//  Aquinas-iOS
//
//  Created by Ryan on 4/11/26.
//

import Combine
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - App Shell

struct ContentView: View {
    @Environment(\.aquinasModel) private var aquinasModel
    @Environment(\.embeddingProvider) private var embeddingProvider
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var questionText: String = ""
    @State private var isAtBottom: Bool = false
    @FocusState private var isKeyboardVisible: Bool
    @State private var uploadedFiles: [UploadedFile] = []
    @State private var showFilePicker: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showCamera: Bool = false
    @State private var collectedDefinitions: [ConceptDefinition] = []
    @State private var globalTreeInsights: [ConceptDefinition] =
        GlobalInsightTreeStore.load()
    @State private var isGlobalTreeUpdatePromptVisible: Bool = false
    @State private var isGlobalTreeReconciling: Bool = false
    /// After accepting an update, Global Insights stays quiet until model work originating on a
    /// different page completes. Global-page actions must not repeatedly re-offer the same sync.
    @State private var suppressGlobalTreePromptUntilExternalModelCompletion: Bool = false
    @State private var activePage: AppPage = .home
    @State private var displayedPage: AppPage = .home
    @State private var isLibraryReaderVisible = false
    @State private var libraryNavigationRequest: LibraryNavigationRequest?
    @State private var hasAppliedStartupDestination = false
    @State private var appLockController = AppLockController()
    @State private var isPageContentVisible: Bool = true
    @State private var pageContentOffsetY: CGFloat = 0
    @State private var pendingPageTransitionWorkItem: DispatchWorkItem? = nil
    @State private var isGlobalSideMenuOpen: Bool = false
    // Set while a Study Topic's detail view is open, so the global edge-swipe
    // gesture below yields to that screen's own swipe-to-go-back gesture.
    @State private var isStudyTopicDetailVisible: Bool = false
    @State private var isInsightLibraryVisible: Bool = false
    @State private var isSettingsDetailVisible: Bool = false
    @State private var isConversationCanvasMode: Bool = false
    @State private var globalInsightsContextCardState = ContextCardState()
    @State private var sideMenuConversations: [InquiryConversation] = []
    @State private var sideMenuActiveConversationID: UUID? = nil
    @State private var sideMenuCurrentTitle: String = "New Conversation"
    /// Changes only when sidebar content changes. The live drag offset must not
    /// force the menu's complete row hierarchy to be rebuilt every frame.
    @State private var sideMenuRenderVersion = 0
    @State private var requestedConversationID: UUID? = nil
    @State private var requestedTopicID: UUID? = nil
    @State private var insightConversationQuoteRequest: InsightConversationQuoteRequest? = nil
    @State private var newConversationInsightQuoteRequest: NewConversationInsightQuoteRequest? = nil
    @State private var studyTopicTreeSelectionRequest: StudyTopicTreeSelectionRequest? = nil
    @State private var newConversationRequest: Int = 0
    /// Must be owned here, not as local `@State` inside `CurrentConversationView` — that view
    /// gets torn down and recreated on every page switch, so a locally-reset "handled" counter
    /// would forget it had already handled a request. `newConversationRequest` itself lives at
    /// this same app-shell level and persists for the whole session; once it's been incremented
    /// even once, a freshly-reset local counter would never match it again, causing every later
    /// remount of the conversation page to spuriously fire `startNewConversation()` — discarding
    /// whatever conversation had just correctly loaded, including one still mid-generation.
    @State private var handledNewConversationRequest: Int = 0
    @State private var pendingNewConversationQuestion: String = ""
    @State private var pendingNewConversationEyebrow: String = ""
    @State private var pendingNewConversationPromptContext: String = ""
    @State private var pendingNewConversationSubtitle: String = ""
    @State private var newConversationTopicID: UUID? = nil
    @State private var newConversationIsStudyTopic: Bool = false
    @State private var deletedConversationID: UUID? = nil
    @State private var colorSchemeOverride: ColorScheme? = nil
    @State private var requestedForkConcept: ConceptDefinition? = nil
    @AppStorage("aquinas.settings.userName") private var userName: String = ""
    @AppStorage(SettingsStorageKey.customInstructions) private var customInstructions: String = ""
    @AppStorage(SettingsStorageKey.defaultStartScreen)
    private var defaultStartScreen: DefaultStartScreenOption = .home
    @AppStorage(SettingsStorageKey.appLock) private var appLockEnabled = false
    @AppStorage(SettingsStorageKey.appLockGracePeriod)
    private var appLockGracePeriod: AppLockGracePeriodOption = .immediately
    @AppStorage(SettingsStorageKey.conversationTitles)
    private var conversationTitlePolicy: ConversationTitleOption = .automatic
    @State private var globalInsightSelectionRequest: Int = 0
    /// Set when returning to the global Insight Tree after removing a quoted Insight's chip
    /// from a conversation's composer — the tree hovers/selects this Insight on appear.
    @State private var globalInsightRestoreSelectionID: UUID? = nil
    @State private var globalInsightClearSelectionRequest: Int = 0
    @State private var globalInsightDismissHoverRequest: Int = 0
    @State private var globalInsightCreateConceptRequest: Int = 0
    @State private var globalInsightStudyRequest: Int = 0
    @State private var globalInsightStudyExitRequest: Int = 0
    @State private var globalInsightIsStudyMode: Bool = false
    @State private var globalInsightStudyToolsToggleRequest: Int = 0
    @State private var globalInsightStudyToolsActive: Bool = false
    @State private var globalInsightStudyBranchCount: Int = 2
    @State private var globalInsightPromotedIDs: [UUID] =
        GlobalInsightPromotedIDsStore.load()
    @State private var globalInsightInquireConnectionRequest: Int = 0
    @State private var globalInsightMidpointEnterRequest: Int = 0
    @State private var globalInsightMidpointCenterRequest: Int = 0
    @State private var globalInsightMidpointPlaceRequest: Int = 0
    @State private var globalInsightHasCanvasHover: Bool = false
    @State private var globalInsightHasInsightHover: Bool = false
    @State private var globalInsightSelectedItemCount: Int = 0
    @State private var globalInsightQuoteTarget: ConceptDefinition? = nil
    @State private var isGlobalInsightAskMode: Bool = false
    @State private var globalInsightExistingConversationTarget: ConceptDefinition? = nil
    @State private var globalInsightIsMidpointMode: Bool = false
    @State private var globalInsightIsGenerating: Bool = false
    @State private var globalInsightSelectedPersonality: String = "Balanced"
    @State private var globalInsightIsPersonalityMenuOpen: Bool = false
    @State private var globalInsightHighlightedBridge: (UUID, UUID)? = nil
    @State private var globalInsightHighlightRequest: Int = 0
    @State private var globalInsightHighlightedNodeID: UUID? = nil
    @State private var globalInsightNodeFocusRequest: Int = 0
    @State private var globalInsightIsSearchActive: Bool = false
    @State private var globalInsightSearchQuery: String = ""
    @State private var globalInsightSearchResultIndex: Int = 0
    @State private var globalInsightSearchResultCount: Int = 0
    @State private var globalInsightSearchPreviousRequest: Int = 0
    @State private var globalInsightSearchNextRequest: Int = 0
    /// Shell-owned so model work and its popup survive page navigation.
    @State private var modelTasks: ModelTaskQueue
    @State private var modelTasksPopupState = ModelTasksPopupState()
    /// Reported up by `StudyTopicsView` so the global Model Controls bar can render its pill
    /// while that page's own selection/canvas/confirmation state stays owned locally there.
    @State private var studyTopicsControls = StudyTopicsPageControls()
    @State private var modelCompletionNotifications = ModelCompletionNotificationCenter()
    @State private var questionOfTheDay = HomeQuestionOfTheDayStore.loadPending()
    @State private var dailyQuestionRefreshTask: Task<Void, Never>? = nil
    @State private var dailyQuestionGenerationRetryNotBefore = Date.distantPast
    @State private var isDailyQuestionGenerationErrorPresented: Bool = false
    @State private var homeLooseThread: LooseThreadCard? = nil
    @State private var homeTodayInHistory: TodayInHistoryCard? = nil
    @State private var homeGlossedTerm: GlossedTermCard? = nil
    @State private var homeYourQuote: YourQuoteCard? = nil
    @Environment(\.homeBackendService) private var homeBackendService
    @AppStorage("aquinas.settings.conversationFontSize") private var conversationFontSize: ConversationFontSizeOption = .small
    @AppStorage(SettingsStorageKey.conversationTextAlignment) private var conversationTextAlignment: ConversationTextAlignmentOption = .center
    @AppStorage("aquinas.settings.inputFont") private var inputFont: ConversationFontOption = .serif
    @AppStorage("aquinas.settings.responseFont") private var responseFont: ConversationFontOption = .sans
    @AppStorage("aquinas.settings.conversationPersonality") private var conversationPersonality: ConversationPersonality = .balanced

    let canvasColor = AquinasTheme.Colors.canvas
    private let pageFadeDuration: TimeInterval = 0.25
    private let pageFadePauseDuration: TimeInterval = 0.15
    private let pageTransitionOffset: CGFloat = 8

    init() {
        Self.migrateConversationTextAlignmentPreferenceIfNeeded()
        _modelTasks = State(initialValue: ModelTaskQueue())
    }

    init(modelTasks: ModelTaskQueue) {
        Self.migrateConversationTextAlignmentPreferenceIfNeeded()
        _modelTasks = State(initialValue: modelTasks)
    }

    private static func migrateConversationTextAlignmentPreferenceIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SettingsStorageKey.conversationTextAlignment) == nil,
              let legacyRawValue = defaults.string(forKey: SettingsStorageKey.legacyResponseTextAlignment),
              let legacyAlignment = ConversationTextAlignmentOption(rawValue: legacyRawValue) else {
            return
        }
        defaults.set(legacyAlignment.rawValue, forKey: SettingsStorageKey.conversationTextAlignment)
    }

    private var rootSafeAreaColor: Color {
        activePage == .conversation && isConversationCanvasMode
            ? AquinasTheme.Colors.canvas
            : canvasColor
    }

    private var newInsightsCount: Int {
        guard let strings = UserDefaults.standard.stringArray(forKey: "AquinasSeenInsightIDs"),
              !strings.isEmpty else { return 0 }
        let seenIDs = Set(strings.compactMap { UUID(uuidString: $0) })
        return collectedDefinitions.filter { !seenIDs.contains($0.id) }.count
    }

    private var globalInsightContextWordCount: Int {
        let text = globalTreeInsights
            .flatMap { [$0.word, $0.meaning, $0.example] }
            .joined(separator: " ")
        return AquinasContextBudget.estimatedTokenCount(in: text)
    }

    private var usesLandscapeInsightSplit: Bool {
        displayedPage == .insights && verticalSizeClass == .compact
    }

    private func presentGlobalSideMenu() {
        dismissKeyboard()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            isGlobalSideMenuOpen = true
        }
    }

    private func openModelTaskPage(_ task: ModelTaskSnapshot) {
        let page: AppPage
        switch task.originPage {
        case .home:
            page = .home
        case .conversation:
            page = .conversation
        case .openConversations:
            page = .openConversations
        case .settings:
            page = .settings
        case .insights:
            page = .insights
        case .studyTopics:
            page = .studyTopics
        }

        modelTasksPopupState.reset()
        if page == .conversation, let conversationID = task.conversationID {
            requestedConversationID = conversationID
        }
        guard activePage != page else { return }
        activePage = page
    }

    private func postConversationCompletionNotificationIfNeeded(
        for task: ModelTaskSnapshot
    ) {
        guard case .userQuestion(let branchID, let responseIndex) = task.kind,
              let conversationID = task.conversationID else {
            return
        }

        let isViewingCompletedConversation = activePage == .conversation
            && sideMenuActiveConversationID == conversationID
        guard !isViewingCompletedConversation else { return }

        let conversation = CurrentConversationsStore.load()?.conversations.first(where: {
            $0.id == conversationID
        }) ?? sideMenuConversations.first(where: { $0.id == conversationID })
        let completedQuestion = conversation?
            .branches
            .first(where: { $0.id == branchID })
            .flatMap { branch in
                branch.activeChatBlocks
                    .prefix(min(responseIndex, branch.activeChatBlocks.count))
                    .reversed()
                    .compactMap { block -> String? in
                        guard case .user(let question, _, _) = block else { return nil }
                        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    }
                    .first
                    ?? {
                        let trimmed = branch.topQuestionText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        return trimmed.isEmpty ? nil : trimmed
                    }()
            }
        let fallbackTitle = conversation?.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let notificationTitle = completedQuestion
            ?? fallbackTitle.flatMap { $0.isEmpty ? nil : $0 }
            ?? "Answer ready"

        modelCompletionNotifications.post(title: notificationTitle) {
            requestedConversationID = conversationID
            activePage = .conversation
        }
    }

    /// The single, persistent Model Controls bar shown across every non-conversation page.
    /// Anchored via `.safeAreaInset` outside the page-content fade/offset transition, so it stays
    /// in place while page content animates behind it — its own content simply swaps (with an
    /// implicit crossfade) to match `displayedPage`, mirroring the button-swap feel already used
    /// when switching between internal conversation pages. The conversation page keeps its own
    /// composer dock (`InquiryControlDock`), which is far more than a status/action pill and stays
    /// owned by `CurrentConversationView`.
    @ViewBuilder private func globalModelControlsBar(
        usesLandscapeInsightSplit: Bool
    ) -> some View {
        switch displayedPage {
        case .home:
            PageModelControls(
                modelTasks: modelTasks,
                popupState: modelTasksPopupState,
                actionTitle: "New Conversation",
                action: {
                    newConversationRequest += 1
                    activePage = .conversation
                }
            )
            .background(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        AquinasTheme.Colors.canvas.opacity(0),
                        AquinasTheme.Colors.canvas
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 350)
                .allowsHitTesting(false)
            }
        case .conversation:
            EmptyView()
        case .library:
            if !isLibraryReaderVisible {
                PageModelControls(
                    modelTasks: modelTasks,
                    popupState: modelTasksPopupState,
                    alwaysShowModelStatus: true
                )
            }
        case .openConversations:
            PageModelControls(
                modelTasks: modelTasks,
                popupState: modelTasksPopupState,
                actionTitle: "New Conversation",
                action: {
                    newConversationRequest += 1
                    activePage = .conversation
                }
            )
        case .settings:
            PageModelControls(
                modelTasks: modelTasks,
                popupState: modelTasksPopupState
            )
        case .insights:
            GlobalInsightsModelControls(
                showFilePicker: $showFilePicker,
                showPhotoPicker: $showPhotoPicker,
                showCamera: $showCamera,
                selectedPersonality: $globalInsightSelectedPersonality,
                isPersonalityMenuOpen: $globalInsightIsPersonalityMenuOpen,
                hasCanvasHover: globalInsightHasCanvasHover,
                hasCanvasInsightHover: globalInsightHasInsightHover,
                hasSelectedCanvasItems: globalInsightSelectedItemCount > 0,
                selectedCanvasItemCount: globalInsightSelectedItemCount,
                isMidpointMode: globalInsightIsMidpointMode,
                isStudyMode: globalInsightIsStudyMode,
                isStudyToolsActive: globalInsightStudyToolsActive,
                onToggleStudyTools: { globalInsightStudyToolsToggleRequest += 1 },
                studyBranchCount: globalInsightStudyBranchCount,
                onStudyBranchCountChange: { globalInsightStudyBranchCount = $0 },
                isCanvasInsightLoading: globalInsightIsGenerating,
                modelStatusOverride: isGlobalTreeReconciling
                    ? String(localized: "Mapping...")
                    : nil,
                contextWordCount: globalInsightContextWordCount,
                modelTasks: modelTasks,
                modelTasksPopupState: modelTasksPopupState,
                searchText: $globalInsightSearchQuery,
                isSearchActive: $globalInsightIsSearchActive,
                searchResultIndex: globalInsightSearchResultIndex,
                searchResultCount: globalInsightSearchResultCount,
                onSelectCanvasItem: { globalInsightSelectionRequest += 1 },
                onCreateCanvasConcept: { globalInsightCreateConceptRequest += 1 },
                onStudyCanvasInsight: { globalInsightStudyRequest += 1 },
                onInquireConnection: { globalInsightInquireConnectionRequest += 1 },
                onQuoteCanvasItem: {
                    guard globalInsightQuoteTarget != nil else { return }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        isGlobalInsightAskMode = true
                    }
                },
                usesCanvasAskFlow: true,
                isCanvasAskMode: isGlobalInsightAskMode,
                onAskInNewConversation: askGlobalInsightInNewConversation,
                onAskInExistingConversation: {
                    guard let target = globalInsightQuoteTarget else { return }
                    globalInsightExistingConversationTarget = target
                },
                onCancelCanvasAsk: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        isGlobalInsightAskMode = false
                    }
                },
                onMidpointConcepts: { globalInsightMidpointEnterRequest += 1 },
                onMidpointCenter: { globalInsightMidpointCenterRequest += 1 },
                onMidpointPlace: { globalInsightMidpointPlaceRequest += 1 },
                onSearchPrevious: { globalInsightSearchPreviousRequest += 1 },
                onSearchNext: { globalInsightSearchNextRequest += 1 },
                onSearchActivated: {
                    globalInsightsContextCardState.reset()
                    modelTasksPopupState.reset()
                    globalInsightDismissHoverRequest += 1
                },
                onClearCanvasSelection: { globalInsightClearSelectionRequest += 1 },
                onContextWillOpen: { globalInsightDismissHoverRequest += 1 },
                confirmationTitle: isGlobalTreeUpdatePromptVisible
                    ? "Update Global Insights Tree?"
                    : nil,
                onConfirmUpdate: updateGlobalInsightTree,
                onDeclineUpdate: dismissGlobalInsightTreeUpdate,
                contextCard: globalInsightsContextCardState
            )
            .frame(maxWidth: usesLandscapeInsightSplit ? 420 : .infinity)
            .frame(
                maxWidth: .infinity,
                alignment: usesLandscapeInsightSplit ? .trailing : .center
            )
        case .studyTopics:
            if studyTopicsControls.isVisible {
                PageModelControls(
                    modelTasks: modelTasks,
                    popupState: modelTasksPopupState,
                    actionTitle: studyTopicsControls.actionTitle,
                    secondaryActionTitle: studyTopicsControls.secondaryActionTitle,
                    secondaryAction: studyTopicsControls.secondaryAction,
                    confirmationTitle: studyTopicsControls.confirmationTitle,
                    onConfirm: studyTopicsControls.onConfirm,
                    onDecline: studyTopicsControls.onDecline,
                    action: studyTopicsControls.action
                )
            }
        }
    }

    /// Kept out of `body`'s modifier chain, which is at the type checker's limit.
    private func handleGlobalInsightHoverChange(_ isHoveringInsight: Bool) {
        guard isHoveringInsight else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            modelTasksPopupState.reset()
        }
    }

    /// The Insights page's side-menu button; in Study it grows an Exit back to the tree.
    private var globalInsightMenuControls: some View {
        HStack(spacing: 8) {
            SideMenuTriggerButton {
                dismissKeyboard()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    isGlobalSideMenuOpen = true
                }
            }
            if globalInsightIsStudyMode {
                StudyExitButton { globalInsightStudyExitRequest += 1 }
                    .transition(.studyExitGrow)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: globalInsightIsStudyMode)
    }

    @ViewBuilder private var insightTreePage: some View {
        InsightTreeView(
            insights: globalTreeInsights,
            selectionRequest: globalInsightSelectionRequest,
            clearSelectionRequest: globalInsightClearSelectionRequest,
            dismissHoverRequest: globalInsightDismissHoverRequest,
            createConceptRequest: globalInsightCreateConceptRequest,
            studyRequest: globalInsightStudyRequest,
            studyExitRequest: globalInsightStudyExitRequest,
            studyToolsToggleRequest: globalInsightStudyToolsToggleRequest,
            studyBranchCount: globalInsightStudyBranchCount,
            onStudyModeChange: { globalInsightIsStudyMode = $0 },
            onStudyToolsActiveChange: { globalInsightStudyToolsActive = $0 },
            onStudyBranchCountChange: { globalInsightStudyBranchCount = $0 },
            restoreSelectedInsightID: globalInsightRestoreSelectionID,
            restoreSelectedNodeID: globalInsightHighlightedNodeID,
            nodeSelectionRequest: globalInsightNodeFocusRequest,
            promotedInsightIDs: globalInsightPromotedIDs,
            onRemoveInsight: { def in
                withAnimation {
                    collectedDefinitions.removeAll { $0.id == def.id }
                    globalTreeInsights.removeAll { $0.id == def.id }
                }
                GlobalInsightTreeStore.save(globalTreeInsights)
            },
            onRestoreInsight: { def in
                withAnimation {
                    if !collectedDefinitions.contains(where: { $0.id == def.id }) {
                        collectedDefinitions.append(def)
                    }
                    if !globalTreeInsights.contains(where: { $0.id == def.id }) {
                        globalTreeInsights.append(def)
                    }
                }
                GlobalInsightTreeStore.save(globalTreeInsights)
            },
            onForkInsight: { def in
                requestedForkConcept = def
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    activePage = .conversation
                }
            },
            onQuoteInsight: { insight in
                globalInsightQuoteTarget = insight
                if insight == nil { isGlobalInsightAskMode = false }
            },
            onSelectionStateChange: { globalInsightHasCanvasHover = $0 },
            onInsightSelectionStateChange: { globalInsightHasInsightHover = $0 },
            onSelectedCanvasItemCountChange: { globalInsightSelectedItemCount = $0 },
            onPromotedInsightIDsChange: {
                globalInsightPromotedIDs = $0
                GlobalInsightPromotedIDsStore.save($0)
            },
            // Every item in the Global Insight Tree is, by definition, something the user chose
            // to save. Keep the bookmark state tied to the tree snapshot rather than the broader
            // collected-definition cache, which can also contain pending updates.
            savedConceptIDs: Set(globalTreeInsights.map(\.id)),
            onToggleSavedConcept: { concept in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    collectedDefinitions.removeAll { $0.id == concept.id }
                    // Un-saving must disappear from the global tree's persisted snapshot too;
                    // otherwise relaunching reloads the stale insight and the bookmark returns.
                    globalTreeInsights.removeAll { $0.id == concept.id }
                }
                GlobalInsightTreeStore.save(globalTreeInsights)
            },
            onBookmarkConcepts: { concepts in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    for concept in concepts {
                        if !collectedDefinitions.contains(where: { $0.id == concept.id }) {
                            collectedDefinitions.append(concept)
                        }
                        if !globalTreeInsights.contains(where: { $0.id == concept.id }) {
                            globalTreeInsights.append(concept)
                        }
                    }
                }
                GlobalInsightTreeStore.save(globalTreeInsights)
            },
            inquireConnectionRequest: globalInsightInquireConnectionRequest,
            onInquireConnectionConcepts: { concepts in
                guard let first = concepts.first else { return }
                requestedForkConcept = first
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    activePage = .conversation
                }
            },
            midpointEnterRequest: globalInsightMidpointEnterRequest,
            midpointCenterRequest: globalInsightMidpointCenterRequest,
            midpointPlaceRequest: globalInsightMidpointPlaceRequest,
            searchQuery: globalInsightSearchQuery,
            searchPreviousRequest: globalInsightSearchPreviousRequest,
            searchNextRequest: globalInsightSearchNextRequest,
            onSearchResultsChange: { current, total in
                globalInsightSearchResultIndex = current
                globalInsightSearchResultCount = total
            },
            highlightedInsightPair: globalInsightHighlightedBridge,
            highlightPairRequest: globalInsightHighlightRequest,
            startsMidpointForHighlightedPair: true,
            onMidpointModeChange: { globalInsightIsMidpointMode = $0 },
            onMidpointGeneratingChange: { globalInsightIsGenerating = $0 },
            inputFont: inputFont,
            conversationFontSize: conversationFontSize,
            showQuestionBar: false,
            modelTasks: modelTasks,
            model: aquinasModel,
            embeddingProvider: embeddingProvider
        )
        .background(canvasColor)
        // Top/side notch bleed only — keyboard safe area and the global Model Controls bar's
        // bottom inset (applied on an ancestor container) must still be respected, or the
        // docked Insight card renders behind the bar instead of stacking above it.
        .ignoresSafeArea(.container, edges: [.top, .horizontal])
        .sheet(item: $globalInsightExistingConversationTarget) { insight in
            InsightConversationPickerSheet(
                title: "Existing Conversations",
                searchPrompt: "Search Conversations",
                emptyMessage: "There are no matching conversations yet.",
                conversations: sideMenuConversations,
                activeConversationID: sideMenuActiveConversationID,
                savedInsights: collectedDefinitions,
                onSelect: { conversation in
                    globalInsightExistingConversationTarget = nil
                    isGlobalInsightAskMode = false
                    insightConversationQuoteRequest = InsightConversationQuoteRequest(
                        conversationID: conversation.id,
                        insight: insight
                    )
                    activePage = .conversation
                },
                onCancel: {
                    globalInsightExistingConversationTarget = nil
                }
            )
            .presentationDetents([.height(520), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
        }
    }

    /// Extracted so the compiler doesn't time out type-checking a single large expression.
    @ViewBuilder private var conversationView: some View {
        CurrentConversationView(
            onOpenMenu: presentGlobalSideMenu,
            onCanvasModeChange: { isConversationCanvasMode = $0 },
            onInsightLibraryVisibilityChange: { isInsightLibraryVisible = $0 },
            onRequestConversationPage: {
                activePage = .conversation
            },
            onReturnToStudyTopicTree: { request in
                requestedTopicID = request.topicID
                studyTopicTreeSelectionRequest = request
                activePage = .studyTopics
            },
            onReturnToGlobalInsights: { insight in
                globalInsightRestoreSelectionID = insight.id
                activePage = .insights
            },
            onQuestionOfTheDayAnswered: markQuestionOfTheDayAnswered,
            onTodayInHistoryAnswered: markTodayInHistoryAnswered,
            collectedDefinitions: $collectedDefinitions,
            sideMenuConversations: $sideMenuConversations,
            sideMenuCurrentTitle: $sideMenuCurrentTitle,
            sideMenuActiveConversationID: $sideMenuActiveConversationID,
            requestedConversationID: $requestedConversationID,
            newConversationRequest: $newConversationRequest,
            handledNewConversationRequest: $handledNewConversationRequest,
            pendingNewConversationQuestion: $pendingNewConversationQuestion,
            pendingNewConversationEyebrow: $pendingNewConversationEyebrow,
            pendingNewConversationPromptContext: $pendingNewConversationPromptContext,
            pendingNewConversationSubtitle: $pendingNewConversationSubtitle,
            newConversationTopicID: $newConversationTopicID,
            newConversationIsStudyTopic: $newConversationIsStudyTopic,
            deletedConversationID: $deletedConversationID,
            requestedForkConcept: $requestedForkConcept,
            insightConversationQuoteRequest: $insightConversationQuoteRequest,
            newConversationInsightQuoteRequest: $newConversationInsightQuoteRequest,
            conversationFontSize: conversationFontSize,
            conversationTextAlignment: conversationTextAlignment,
            inputFont: inputFont,
            responseFont: responseFont,
            conversationTitlePolicy: conversationTitlePolicy,
            conversationPersonality: $conversationPersonality,
            userName: userName,
            isPageVisible: activePage == .conversation,
            modelTasks: modelTasks,
            modelTasksPopupState: modelTasksPopupState,
            uploadedFiles: $uploadedFiles,
            showFilePicker: $showFilePicker
        )
    }

    private var globalSideMenu: AnyView {
        AnyView(AquinasSideMenu(
            currentTitle: sideMenuCurrentTitle,
            conversations: sideMenuConversations,
            activeConversationID: sideMenuActiveConversationID,
            activePage: activePage,
            modelTasks: modelTasks,
            selectedPersonality: conversationPersonality.displayName,
            isPresented: isGlobalSideMenuOpen,
            renderVersion: sideMenuRenderVersion,
            onNewChat: { dismissGlobalSideMenu { newConversationRequest += 1; activePage = .conversation } },
            onSelectConversation: { conversation in dismissGlobalSideMenu { requestedConversationID = conversation.id; activePage = .conversation } },
            onRenameConversation: { conversation, title in renameConversation(conversation, to: title) },
            onPinConversation: { pinConversation($0) },
            onUnpinConversation: { unpinConversation($0) },
            onAddConversationToStudyTopic: { attachConversation($0, toStudyTopic: $1) },
            onRemoveConversationFromStudyTopic: { detachConversationFromStudyTopic($0) },
            onDeleteConversation: { deleteConversation($0) },
            newInsightsCount: newInsightsCount,
            onOpenHome: { dismissGlobalSideMenu { activePage = .home } },
            onOpenLibrary: { dismissGlobalSideMenu { activePage = .library } },
            onOpenConversations: { dismissGlobalSideMenu { activePage = .openConversations } },
            onOpenInsights: { dismissGlobalSideMenu { activePage = .insights } },
            onOpenStudyTopics: { dismissGlobalSideMenu { requestedTopicID = nil; activePage = .studyTopics } },
            onSelectStudyTopic: { topic in dismissGlobalSideMenu { requestedTopicID = topic.id; activePage = .studyTopics } },
            onOpenSettings: { dismissGlobalSideMenu { activePage = .settings } },
            onClose: { dismissGlobalSideMenu() }
        )
        .equatable())
    }

    var body: some View {
        shellObservers(shellBody)
    }

    /// The trailing observers, split out of the main modifier chain, which is past the type
    /// checker's limit in one piece.
    private func shellObservers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in handleScenePhaseChange(phase) }
            .onChange(of: appLockEnabled) { _, isEnabled in
                appLockController.settingDidChange(isEnabled: isEnabled)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didReceiveMemoryWarningNotification
                )
            ) { _ in
                modelTasks.handleMemoryPressure()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: ProcessInfo.thermalStateDidChangeNotification
                )
            ) { _ in
                modelTasks.updateThermalPressure(
                    ProcessInfo.processInfo.thermalState.modelRuntimePressure
                )
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .aquinasConversationStoreDidImport
                )
            ) { _ in
                loadShellConversationState()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .openGroundingSourceInLibrary)
                    .compactMap { $0.object as? LibraryNavigationRequest }
            ) { request in
                libraryNavigationRequest = request
                activePage = .library
            }
            .onChange(of: collectedDefinitions) { _, newValue in handleCollectedDefinitionsChange(newValue) }
    }

    private var shellBody: some View {
        AnyView(GeometryReader { _ in
            ZStack(alignment: .top) {
                rootSafeAreaColor
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.2), value: isConversationCanvasMode)

                VStack(spacing: 0) {
                    ZStack {
                        // Do not keep the UIKit-backed editor and its geometry preferences in the
                        // layout tree while another page is visible. An opacity-only hiding path
                        // left that tree active and could drive a runaway AttributeGraph update
                        // loop on device. Model work itself is owned by the shell-level queue.
                        if displayedPage == .conversation {
                            conversationView
                            .opacity(isPageContentVisible ? 1 : 0)
                            .offset(y: pageContentOffsetY)
                        }

                        Group {
                            switch displayedPage {
                            case .home:
                                HomeDashboardView(
                                    conversations: sideMenuConversations,
                                    activeConversationID: sideMenuActiveConversationID,
                                    savedInsights: collectedDefinitions,
                                    userName: userName,
                                    questionOfTheDay: questionOfTheDay,
                                    looseThread: homeLooseThread,
                                    todayInHistory: homeTodayInHistory,
                                    glossedTerm: homeGlossedTerm,
                                    yourQuote: homeYourQuote,
                                    onOpenMenu: presentGlobalSideMenu,
                                    onSelectConversation: { conversation in
                                        requestedConversationID = conversation.id
                                        activePage = .conversation
                                    },
                                    onStartQuestion: { dailyQuestion in
                                        pendingNewConversationQuestion = dailyQuestion.question
                                        pendingNewConversationEyebrow = "QUESTION OF THE DAY"
                                        pendingNewConversationPromptContext =
                                            dailyQuestion.taggedPromptContext
                                        newConversationRequest += 1
                                        activePage = .conversation
                                    },
                                    onOpenInsightBridge: { firstID, secondID in
                                        globalInsightHighlightedBridge = (firstID, secondID)
                                        globalInsightHighlightRequest += 1
                                        activePage = .insights
                                    },
                                    onFocusNode: { nodeID in
                                        globalInsightHighlightedNodeID = nodeID
                                        globalInsightNodeFocusRequest += 1
                                        activePage = .insights
                                    },
                                    onStartTodayInHistory: { card in
                                        pendingNewConversationQuestion = card.title
                                        pendingNewConversationEyebrow = "TODAY IN HISTORY"
                                        pendingNewConversationPromptContext = card.taggedPromptContext
                                        pendingNewConversationSubtitle = card.description
                                        newConversationRequest += 1
                                        activePage = .conversation
                                    },
                                    onRefresh: refreshPersistedContent,
                                    onLoadHomeSections: {
                                        Task { await refreshHomeSections() }
                                    }
                                )
                            case .conversation:
                                Color.clear
                                    .allowsHitTesting(false)
                            case .library:
                                libraryPage
                            case .openConversations:
                                OpenConversationsView(
                                    conversations: sideMenuConversations,
                                    activeConversationID: sideMenuActiveConversationID,
                                    savedInsights: $collectedDefinitions,
                                    modelTasks: modelTasks,
                                    modelTasksPopupState: modelTasksPopupState,
                                    onOpenMenu: presentGlobalSideMenu,
                                    onSelectConversation: { conversation in
                                        requestedConversationID = conversation.id
                                        activePage = .conversation
                                    },
                                    onNewChat: {
                                        newConversationRequest += 1
                                        activePage = .conversation
                                    },
                                    onRenameConversation: { conversation, title in
                                        renameConversation(conversation, to: title)
                                    },
                                    onPinConversation: { conversation in
                                        pinConversation(conversation)
                                    },
                                    onUnpinConversation: { conversation in
                                        unpinConversation(conversation)
                                    },
                                    onAddConversationToStudyTopic: { conversation, topicID in
                                        attachConversation(conversation, toStudyTopic: topicID)
                                    },
                                    onRemoveConversationFromStudyTopic: { conversation in
                                        detachConversationFromStudyTopic(conversation)
                                    },
                                    onDeleteConversation: { conversation in
                                        deleteConversation(conversation)
                                    },
                                    onRefresh: refreshPersistedContent
                                )
                            case .settings:
                                SettingsView(
                                    colorSchemeOverride: $colorSchemeOverride,
                                    userName: $userName,
                                    customInstructions: $customInstructions,
                                    conversationFontSize: $conversationFontSize,
                                    conversationTextAlignment: $conversationTextAlignment,
                                    inputFont: $inputFont,
                                    responseFont: $responseFont,
                                    conversationPersonality: $conversationPersonality,
                                    onOpenMenu: presentGlobalSideMenu,
                                    onDetailVisibilityChange: { isSettingsDetailVisible = $0 },
                                    onClearInsightTree: clearInsightTree
                                )
                            case .insights:
                                insightTreePage
                            case .studyTopics:
                                StudyTopicsView(
                                    conversations: sideMenuConversations,
                                    activeConversationID: sideMenuActiveConversationID,
                                    savedInsights: $collectedDefinitions,
                                    modelTasks: modelTasks,
                                    modelTasksPopupState: modelTasksPopupState,
                                    onOpenMenu: presentGlobalSideMenu,
                                    onSelectConversation: { conversation in
                                        requestedConversationID = conversation.id
                                        activePage = .conversation
                                    },
                                    onNewChat: {
                                        newConversationRequest += 1
                                        activePage = .conversation
                                    },
                                    onNewChatInTopic: { topicID in
                                        newConversationTopicID = topicID
                                        newConversationRequest += 1
                                        activePage = .conversation
                                    },
                                    onQuoteInsightIntoNewConversation: { insight, topicID in
                                        newConversationTopicID = topicID
                                        newConversationInsightQuoteRequest =
                                            NewConversationInsightQuoteRequest(
                                                insight: insight,
                                                topicID: topicID
                                            )
                                        newConversationRequest += 1
                                        activePage = .conversation
                                    },
                                    onQuoteInsightIntoConversation: { conversation, insight, topicID in
                                        insightConversationQuoteRequest = InsightConversationQuoteRequest(
                                            topicID: topicID,
                                            conversationID: conversation.id,
                                            insight: insight
                                        )
                                        activePage = .conversation
                                    },
                                    onAttachConversationToTopic: { conversation, topicID in
                                        attachConversation(conversation, toStudyTopic: topicID)
                                    },
                                    onRenameConversation: { conversation, title in
                                        renameConversation(conversation, to: title)
                                    },
                                    onPinConversation: { conversation in
                                        pinConversation(conversation)
                                    },
                                    onUnpinConversation: { conversation in
                                        unpinConversation(conversation)
                                    },
                                    onRemoveConversationFromStudyTopic: { conversation in
                                        detachConversationFromStudyTopic(conversation)
                                    },
                                    onDeleteConversation: { conversation in
                                        deleteConversation(conversation)
                                    },
                                    requestedTopicID: requestedTopicID,
                                    requestedTreeSelection: studyTopicTreeSelectionRequest,
                                    onConsumeTreeSelectionRequest: {
                                        studyTopicTreeSelectionRequest = nil
                                    },
                                    onRefresh: refreshPersistedContent,
                                    onDetailVisibilityChange: { isVisible in
                                        isStudyTopicDetailVisible = isVisible
                                    },
                                    onControlsChange: { studyTopicsControls = $0 }
                                )
                            }
                        }
                        .opacity(displayedPage == .conversation ? 0 : 1)
                        .allowsHitTesting(displayedPage != .conversation)
                        .accessibilityHidden(displayedPage == .conversation)
                        .opacity(isPageContentVisible ? 1 : 0)
                        .offset(y: pageContentOffsetY)
                    }
                    // Matches the pages' canvas so the slide offset during page transitions
                    // doesn't reveal a differently tinted strip behind the page.
                    .background(canvasColor)
                    // Rendered here — outside the fade/offset applied to the two branches above —
                    // so the Model Controls bar stays put and simply swaps its own content while
                    // page transitions play, instead of animating (and briefly disappearing) with
                    // the page itself. `.safeAreaInset` also gives every page's scroll content the
                    // same automatic bottom clearance it always had, without hand-measuring heights.
                    .safeAreaInset(edge: .bottom) {
                        globalModelControlsBar(usesLandscapeInsightSplit: usesLandscapeInsightSplit)
                            .animation(.easeInOut(duration: 0.22), value: displayedPage)
                    }
                    .eraseToAnyView()
                }
                .sideMenuDragPresentation(
                    isPresented: $isGlobalSideMenuOpen,
                    activePage: activePage,
                    isStudyTopicDetailVisible: isStudyTopicDetailVisible,
                    isSettingsDetailVisible: isSettingsDetailVisible,
                    isBlocked: isInsightLibraryVisible,
                    onBeginDrag: dismissKeyboard,
                    onDismiss: { dismissGlobalSideMenu() },
                    menu: globalSideMenu
                )

                // Shared document picker used by the bottom plus button.
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [.image, .pdf, .audio, .plainText],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            for url in urls {
                                let hasAccess = url.startAccessingSecurityScopedResource()
                                defer {
                                    if hasAccess {
                                        url.stopAccessingSecurityScopedResource()
                                    }
                                }

                                let data = try? Data(contentsOf: url)
                                let imageData = data.flatMap { UploadedFile.isImageData($0) ? $0 : nil }

                                uploadedFiles.append(
                                    UploadedFile(
                                        name: url.lastPathComponent,
                                        imageData: imageData,
                                        rotationDegrees: Double.random(in: -5...5)
                                    )
                                )
                            }
                        }
                    case .failure(let error):
                        print("Failed to select file: \(error.localizedDescription)")
                    }
                }
                // Shared photo picker used by the attachment menu.
                .photosPicker(
                    isPresented: $showPhotoPicker,
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 8,
                    matching: .images
                )
                .onChange(of: selectedPhotoItems) { oldValue, newValue in
                    guard !newValue.isEmpty else { return }

                    Task {
                        for item in newValue {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               UploadedFile.isImageData(data) {
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

                        await MainActor.run {
                            selectedPhotoItems.removeAll()
                        }
                    }
                }
                // Camera capture flow. Falls back gracefully if a camera is unavailable.
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

                // ── Side-menu trigger, backdrop, and panel ────────────────────
                // These are direct ZStack siblings (not nested `.overlay()` calls)
                // so their zIndex is compared against the page content directly —
                // guarantees the panel renders above everything, including page
                // content that ignores the safe area (e.g. fade gradients).
                if activePage == .insights && !isGlobalSideMenuOpen {
                    globalInsightMenuControls
                    .padding(.leading, 24)
                    .padding(.top, 24)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .zIndex(2)
                }

                if appLockEnabled,
                   appLockController.isLocked || scenePhase != .active {
                    AppLockGate(
                        isAuthenticating: appLockController.isAuthenticating,
                        errorMessage: appLockController.errorMessage,
                        onUnlock: appLockController.lockAndAuthenticate
                    )
                    .zIndex(2000)
                }

            }
            .ignoresSafeArea(.container, edges: .bottom)
        })
        .environment(
            \.modelCompletionNotifications,
            modelCompletionNotifications
        )
        .environment(\.openModelTaskPage, openModelTaskPage)
        .preferredColorScheme(colorSchemeOverride)
        .eraseToAnyView()
        .dailyQuestionGenerationAlert(
            isPresented: $isDailyQuestionGenerationErrorPresented,
            retry: {
                dailyQuestionGenerationRetryNotBefore = .distantPast
                scheduleDailyQuestionRefreshIfNeeded(minimumDelay: 0)
            }
        )
        .onAppear {
            modelTasks.setPersonality(conversationPersonality)
            modelTasks.setApplicationActive(scenePhase == .active)
            modelTasks.updateThermalPressure(
                ProcessInfo.processInfo.thermalState.modelRuntimePressure
            )
            loadShellConversationState()
            applyStartupDestinationIfNeeded()
            displayedPage = activePage
            isPageContentVisible = true
            pageContentOffsetY = 0
            appLockController.prepare(isEnabled: appLockEnabled)
            let savedInsights = InsightLibraryStore.load()
            if !savedInsights.isEmpty {
                collectedDefinitions = savedInsights
            }
            questionOfTheDay = HomeQuestionOfTheDayStore.loadPending()
            Task { @MainActor in
                await Task.yield()
                scheduleDailyQuestionRefreshIfNeeded()
            }
        }
        .onChange(of: activePage) { oldValue, newValue in handleActivePageChange(from: oldValue, to: newValue) }
        .onChange(of: modelTasks.isBusy) { _, _ in
            scheduleDailyQuestionRefreshIfNeeded()
        }
        // Mirrors CurrentConversationView's identical interlock for its own per-conversation
        // Insight Tree — the Global tree had the same "both open at once" gap since nothing here
        // reacted to a hover starting after the Model Tasks popup was already open.
        .onChange(of: globalInsightHasInsightHover) { _, isHoveringInsight in
            handleGlobalInsightHoverChange(isHoveringInsight)
        }
        .onChange(of: modelTasks.latestCompletedTask) { _, task in handleCompletedModelTask(task) }
        .onChange(of: conversationPersonality) { _, personality in
            modelTasks.setPersonality(personality)
        }
        .onChange(of: sideMenuConversations) { _, _ in handleSideMenuConversationsChange() }
        .onChange(of: collectedDefinitions) { _, _ in
            scheduleDailyQuestionRefreshIfNeeded()
        }
    }

    private var libraryPage: some View {
        LibraryView(
            onOpenMenu: presentGlobalSideMenu,
            modelTasks: modelTasks,
            modelTasksPopupState: modelTasksPopupState,
            onReaderVisibilityChange: { isLibraryReaderVisible = $0 },
            navigationRequest: libraryNavigationRequest
        )
    }

    /// Closes the panel before changing the view behind it, so its contents
    /// remain visually stable for the full slide-out animation.
    private func dismissGlobalSideMenu(then action: @escaping () -> Void = {}) {
        guard isGlobalSideMenuOpen else {
            action()
            return
        }

        withAnimation(
            .spring(response: 0.42, dampingFraction: 0.84),
            completionCriteria: .logicallyComplete
        ) {
            isGlobalSideMenuOpen = false
        } completion: {
            action()
        }
    }

    private func markQuestionOfTheDayAnswered() {
        guard let questionOfTheDay else { return }
        HomeQuestionOfTheDayStore.save(questionOfTheDay.markingAnswered())
        withAnimation(.easeInOut(duration: 0.25)) {
            self.questionOfTheDay = nil
        }
        scheduleDailyQuestionRefreshIfNeeded()
    }

    private func markTodayInHistoryAnswered() {
        guard homeTodayInHistory != nil else { return }
        HomeTodayInHistoryStore.markAnswered()
        withAnimation(.easeInOut(duration: 0.25)) {
            homeTodayInHistory = nil
        }
    }

    private func scheduleDailyQuestionRefreshIfNeeded(
        minimumDelay: TimeInterval = 15
    ) {
        guard activePage != .conversation else {
            dailyQuestionRefreshTask?.cancel()
            dailyQuestionRefreshTask = nil
            return
        }
        guard scenePhase == .active,
              !modelTasks.isBusy else {
            dailyQuestionRefreshTask?.cancel()
            dailyQuestionRefreshTask = nil
            return
        }
        guard dailyQuestionRefreshTask == nil,
              !modelTasks.contains(where: {
                  $0.kind == .refreshQuestionOfTheDay
              }) else {
            return
        }

        let eligibilityDate = HomeQuestionOfTheDayStore.nextEligibleRefreshDate()
        let delay = max(
            minimumDelay,
            max(
                eligibilityDate.timeIntervalSinceNow,
                dailyQuestionGenerationRetryNotBefore.timeIntervalSinceNow
            )
        )
        dailyQuestionRefreshTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  activePage != .conversation,
                  scenePhase == .active,
                  !modelTasks.isBusy else {
                dailyQuestionRefreshTask = nil
                return
            }

            questionOfTheDay = HomeQuestionOfTheDayStore.loadPending()
            guard questionOfTheDay == nil,
                  HomeQuestionOfTheDayStore.isEligibleForRefresh() else {
                dailyQuestionRefreshTask = nil
                debugQuestionOfTheDayConsoleLog("refresh no longer eligible")
                return
            }
            guard let source = DailyQuestionSourceSelector.select(
                      conversations: sideMenuConversations,
                      activeConversationID: sideMenuActiveConversationID,
                      savedInsights: collectedDefinitions
                  ) else {
                dailyQuestionRefreshTask = nil
                debugQuestionOfTheDayConsoleLog("no eligible source conversation")
                return
            }

            dailyQuestionRefreshTask = nil
            debugQuestionOfTheDayConsoleLog("enqueuing generation")
            modelTasks.enqueue(
                kind: .refreshQuestionOfTheDay,
                originPage: .home,
                priority: .background
            ) {
                let draft: DailyQuestionDraft
                do {
                    draft = try await aquinasModel.generateQuestionOfTheDay(
                        from: source.context,
                        conversationTitle: source.conversation.title,
                        insights: Array(source.insights.prefix(4))
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    dailyQuestionGenerationRetryNotBefore = Date().addingTimeInterval(60 * 60)
                    debugQuestionOfTheDayConsoleLog(
                        "model boundary failed: \(String(reflecting: error))"
                    )
                    isDailyQuestionGenerationErrorPresented = true
                    return
                }
                guard !Task.isCancelled else { return }
                let trimmedQuestion = draft.question.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard HomeQuestionOfTheDay.isValidQuestionText(trimmedQuestion) else {
                    dailyQuestionGenerationRetryNotBefore = Date().addingTimeInterval(60 * 60)
                    isDailyQuestionGenerationErrorPresented = true
                    return
                }

                let citedInsight = draft.citedInsightTitle.flatMap { citedTitle in
                    source.insights.first {
                        $0.word.compare(
                            citedTitle,
                            options: [.caseInsensitive, .diacriticInsensitive]
                        ) == .orderedSame
                    }
                }
                let generated = HomeQuestionOfTheDay(
                    question: trimmedQuestion,
                    reasonForAsking: draft.reasonForAsking.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    citedInsight: citedInsight,
                    sourceConversationID: source.conversation.id,
                    sourceConversationTitle: source.conversation.title
                )
                dailyQuestionGenerationRetryNotBefore = .distantPast
                HomeQuestionOfTheDayStore.save(generated)
                withAnimation(.easeInOut(duration: 0.35)) {
                    questionOfTheDay = generated
                }
            }
        }
    }

    private func transitionDisplayedPage(to nextPage: AppPage) {
        guard displayedPage != nextPage else {
            withAnimation(.easeInOut(duration: pageFadeDuration)) {
                isPageContentVisible = true
                pageContentOffsetY = 0
            }
            return
        }

        pendingPageTransitionWorkItem?.cancel()
        let startDelay: TimeInterval = isGlobalSideMenuOpen ? pageFadeDuration : 0

        let fadeOutWork = DispatchWorkItem {
            withAnimation(.easeInOut(duration: pageFadeDuration)) {
                isPageContentVisible = false
                pageContentOffsetY = pageTransitionOffset
            }

            let fadeInWork = DispatchWorkItem {
                displayedPage = nextPage
                pageContentOffsetY = pageTransitionOffset
                withAnimation(.easeInOut(duration: pageFadeDuration)) {
                    isPageContentVisible = true
                    pageContentOffsetY = 0
                }
            }

            pendingPageTransitionWorkItem = fadeInWork
            DispatchQueue.main.asyncAfter(deadline: .now() + pageFadeDuration + pageFadePauseDuration, execute: fadeInWork)
        }

        pendingPageTransitionWorkItem = fadeOutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay, execute: fadeOutWork)
    }

    private func dismissKeyboard() {
        isKeyboardVisible = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        appLockController.scenePhaseDidChange(
            phase,
            isEnabled: appLockEnabled,
            gracePeriod: appLockGracePeriod.duration
        )
        modelTasks.setApplicationActive(phase == .active)
        if phase == .background {
            InquiryPersistenceStore.flush()
        }
        scheduleDailyQuestionRefreshIfNeeded()
    }

    private func handleActivePageChange(from oldValue: AppPage, to newValue: AppPage) {
        modelTasksPopupState.reset()
        if oldValue == .insights, newValue != .insights {
            isGlobalTreeUpdatePromptVisible = false
            globalInsightIsSearchActive = false
            globalInsightSearchQuery = ""
            globalInsightSearchResultIndex = 0
            globalInsightSearchResultCount = 0
        }
        if newValue == .insights {
            refreshGlobalInsightTreeUpdatePrompt()
        }
        transitionDisplayedPage(to: newValue)
        scheduleDailyQuestionRefreshIfNeeded()
    }

    /// Clears in-memory state first so the change observers persist empty values, then wipes
    /// every stored Insight Tree artifact.
    private func clearInsightTree() {
        isGlobalTreeUpdatePromptVisible = false
        globalInsightPromotedIDs = []
        globalTreeInsights = []
        collectedDefinitions = []
        InsightTreeReset.clearPersistedData()
    }

    private func handleCollectedDefinitionsChange(_ definitions: [ConceptDefinition]) {
        InsightLibraryStore.save(definitions)
        guard activePage == .insights,
              !suppressGlobalTreePromptUntilExternalModelCompletion else { return }
        isGlobalTreeUpdatePromptVisible = globalTreeNeedsUpdate
    }

    private func handleSideMenuConversationsChange() {
        sideMenuRenderVersion &+= 1
        scheduleDailyQuestionRefreshIfNeeded()
    }

    private func handleCompletedModelTask(_ task: ModelTaskSnapshot?) {
        guard let task else { return }
        postConversationCompletionNotificationIfNeeded(for: task)
        guard task.originPage != .insights else { return }
        suppressGlobalTreePromptUntilExternalModelCompletion = false
        guard activePage == .insights else { return }
        refreshGlobalInsightTreeUpdatePrompt()
    }

    private func loadShellConversationState() {
        guard let snapshot = CurrentConversationsStore.load(),
              !snapshot.conversations.isEmpty else { return }

        sideMenuConversations = snapshot.conversations
        let activeID = snapshot.activeConversationID ?? snapshot.conversations.first?.id
        sideMenuActiveConversationID = activeID
        sideMenuCurrentTitle = activeID.flatMap { id in
            snapshot.conversations.first { $0.id == id }?.title
        } ?? snapshot.conversations.first?.title ?? "New Conversation"
    }

    private func applyStartupDestinationIfNeeded() {
        guard !hasAppliedStartupDestination else { return }
        hasAppliedStartupDestination = true

        let action = AppStartupPolicy.resolve(
            preference: defaultStartScreen,
            conversationIDs: sideMenuConversations.map(\.id),
            activeConversationID: sideMenuActiveConversationID
        )
        switch action {
        case .home:
            activePage = .home
        case .openConversation(let conversationID):
            requestedConversationID = conversationID
            activePage = .conversation
        case .newConversation:
            newConversationRequest += 1
            activePage = .conversation
        }
    }

    private func refreshPersistedContent() {
        if let snapshot = CurrentConversationsStore.load() {
            sideMenuConversations = snapshot.conversations
            let activeID = snapshot.activeConversationID ?? snapshot.conversations.first?.id
            sideMenuActiveConversationID = activeID
            sideMenuCurrentTitle = activeID.flatMap { id in
                snapshot.conversations.first { $0.id == id }?.title
            } ?? snapshot.conversations.first?.title ?? "New Conversation"
        }

        collectedDefinitions = InsightLibraryStore.load()
    }

    /// Fetches the four backend-driven Home sections. Fail-quiet like every other background
    /// fetch in this codebase: a `nil` result (whether from a backend "nothing qualifies" `null`
    /// or a network failure) simply means that section doesn't render -- no error state, no retry.
    private func refreshHomeSections() async {
        guard AquinasBackendConfiguration.canRecoverFromCurrentDevice,
              let conversationID = HomeSectionSourceSelector.selectConversationID(
                conversations: sideMenuConversations,
                activeConversationID: sideMenuActiveConversationID
              ) else {
            return
        }

        async let looseThread = try? homeBackendService.looseThread(conversationID: conversationID)
        async let todayInHistory = try? homeBackendService.todayInHistory(
            conversationID: conversationID,
            overrideDate: nil
        )
        async let glossedTerm = try? homeBackendService.glossedTerm(conversationID: conversationID)
        async let yourQuote = try? homeBackendService.yourQuote(conversationID: conversationID)

        let (resolvedLooseThread, resolvedTodayInHistory, resolvedGlossedTerm, resolvedYourQuote) =
            await (looseThread, todayInHistory, glossedTerm, yourQuote)

        withAnimation(.easeInOut(duration: 0.35)) {
            homeLooseThread = resolvedLooseThread ?? nil
            homeTodayInHistory = HomeTodayInHistoryStore.isAnswered() ? nil : (resolvedTodayInHistory ?? nil)
            homeGlossedTerm = resolvedGlossedTerm ?? nil
            homeYourQuote = resolvedYourQuote ?? nil
        }
    }

    private func askGlobalInsightInNewConversation() {
        guard let insight = globalInsightQuoteTarget else { return }
        isGlobalInsightAskMode = false
        newConversationInsightQuoteRequest = NewConversationInsightQuoteRequest(insight: insight)
        newConversationRequest += 1
        activePage = .conversation
    }

    private var globalTreeNeedsUpdate: Bool {
        Set(globalTreeInsights.uniquedByWord())
            != Set(collectedDefinitions.uniquedByWord())
    }

    private func refreshGlobalInsightTreeUpdatePrompt() {
        isGlobalTreeUpdatePromptVisible = !suppressGlobalTreePromptUntilExternalModelCompletion
            && globalTreeNeedsUpdate
    }

    private func updateGlobalInsightTree() {
        let existingSnapshot = globalTreeInsights
        let incomingSnapshot = collectedDefinitions

        // Reconciliation calls into NaturalLanguage for every unique Insight. Keep that CPU work
        // outside the main actor so the canvas remains responsive to panning and zooming.
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isGlobalTreeUpdatePromptVisible = false
            suppressGlobalTreePromptUntilExternalModelCompletion = true
            isGlobalTreeReconciling = true
        }

        Task { @MainActor in
            let reconciledInsights = await Task.detached(priority: .userInitiated) {
                Self.reconcileGlobalInsights(
                    existing: existingSnapshot,
                    incoming: incomingSnapshot
                )
            }.value

            // Do not let a completed background pass overwrite edits made while it was running.
            guard globalTreeInsights == existingSnapshot,
                  collectedDefinitions == incomingSnapshot else {
                isGlobalTreeReconciling = false
                suppressGlobalTreePromptUntilExternalModelCompletion = false
                refreshGlobalInsightTreeUpdatePrompt()
                return
            }

            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                globalTreeInsights = reconciledInsights
                isGlobalTreeReconciling = false
            }
            GlobalInsightTreeStore.save(reconciledInsights)
            globalInsightsContextCardState.reset()
            modelTasksPopupState.reset()
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
        }
    }

    /// Reconciles newly collected Insights against the existing global library without doing an
    /// all-pairs comparison. Only the nearest existing candidate is considered, and only a very
    /// high similarity is treated as the same underlying Insight. Unrelated Insights are retained
    /// unchanged; parent/child and merely related concepts remain separate.
    private nonisolated static func reconcileGlobalInsights(
        existing: [ConceptDefinition],
        incoming: [ConceptDefinition]
    ) -> [ConceptDefinition] {
        var result: [ConceptDefinition] = []
        var resultIDs = Set<UUID>()
        for insight in existing where resultIDs.insert(insight.id).inserted {
            result.append(insight)
        }
        let threshold = 0.86
        var embeddingsByID: [UUID: [Double]] = [:]
        for insight in result {
            embeddingsByID[insight.id] = computeEmbedding(
                for: "\(insight.word). \(insight.semanticDefinition)"
            )
        }

        for candidate in incoming.uniquedByWord() {
            guard let candidateEmbedding = computeEmbedding(
                for: "\(candidate.word). \(candidate.semanticDefinition)"
            ) else { continue }

            let nearest = result.compactMap { saved -> (ConceptDefinition, Double)? in
                guard let savedEmbedding = embeddingsByID[saved.id] else { return nil }
                return (saved, cosineSimilarity(candidateEmbedding, savedEmbedding))
            }.max { $0.1 < $1.1 }

            guard let (saved, similarity) = nearest, similarity >= threshold else {
                if resultIDs.insert(candidate.id).inserted {
                    result.append(candidate)
                    embeddingsByID[candidate.id] = candidateEmbedding
                }
                continue
            }

            // Keep the shorter title as the canonical display name. Prefer the more informative
            // definition when one is clearly longer, avoiding duplicate chips while retaining the
            // existing Insight's stable identity.
            let canonicalTitle = candidate.word.split(separator: " ").count < saved.word.split(separator: " ").count
                ? candidate.word : saved.word
            let canonicalDefinitions = candidate.semanticDefinition.count > saved.semanticDefinition.count
                ? candidate.contextualDefinitions : saved.contextualDefinitions
            let merged = ConceptDefinition(
                id: saved.id,
                word: canonicalTitle,
                partOfSpeech: saved.partOfSpeech,
                pronunciation: saved.pronunciation,
                meaning: canonicalDefinitions.first?.meaning ?? saved.meaning,
                example: saved.example,
                definitions: canonicalDefinitions
            )
            if let index = result.firstIndex(where: { $0.id == saved.id }) {
                result[index] = merged
                embeddingsByID[saved.id] = computeEmbedding(
                    for: "\(merged.word). \(merged.semanticDefinition)"
                )
            }
        }
        return result
    }

    private func dismissGlobalInsightTreeUpdate() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isGlobalTreeUpdatePromptVisible = false
        }
    }

    private func deleteConversation(_ conversation: InquiryConversation) {
        // Remove from the side menu list immediately for snappy feedback.
        sideMenuConversations.removeAll { $0.id == conversation.id }

        if sideMenuActiveConversationID == conversation.id {
            sideMenuActiveConversationID = sideMenuConversations.first?.id
            sideMenuCurrentTitle = sideMenuConversations.first?.title ?? "New Conversation"
        }

        // Signal the canvas to remove the thread (and any forks).
        deletedConversationID = conversation.id
        CurrentConversationsStore.save(
            InquiryPersistenceSnapshot(
                conversations: sideMenuConversations,
                activeConversationID: sideMenuActiveConversationID
            )
        )

        // Stay on Open Conversations and let it show its own empty state — don't bounce
        // back to the canvas, since that auto-seeds a fresh blank conversation on appear.
    }

    private func renameConversation(_ conversation: InquiryConversation, to title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        if let index = sideMenuConversations.firstIndex(where: { $0.id == conversation.id }) {
            sideMenuConversations[index].title = trimmedTitle
        }

        if sideMenuActiveConversationID == conversation.id {
            sideMenuCurrentTitle = trimmedTitle
        }

        if var snapshot = InquiryPersistenceStore.load(),
           let index = snapshot.conversations.firstIndex(where: { $0.id == conversation.id }) {
            snapshot.conversations[index].title = trimmedTitle
            InquiryPersistenceStore.save(snapshot)
        }
    }

    private func pinConversation(_ conversation: InquiryConversation) {
        if let index = sideMenuConversations.firstIndex(where: { $0.id == conversation.id }) {
            sideMenuConversations[index].isPinned = true
        }
        if var snapshot = CurrentConversationsStore.load(),
           let index = snapshot.conversations.firstIndex(where: { $0.id == conversation.id }) {
            snapshot.conversations[index].isPinned = true
            CurrentConversationsStore.save(snapshot)
        }
    }

    private func unpinConversation(_ conversation: InquiryConversation) {
        if let index = sideMenuConversations.firstIndex(where: { $0.id == conversation.id }) {
            sideMenuConversations[index].isPinned = false
        }
        if var snapshot = CurrentConversationsStore.load(),
           let index = snapshot.conversations.firstIndex(where: { $0.id == conversation.id }) {
            snapshot.conversations[index].isPinned = false
            CurrentConversationsStore.save(snapshot)
        }
    }

    private func detachConversationFromStudyTopic(_ conversation: InquiryConversation) {
        if let index = sideMenuConversations.firstIndex(where: { $0.id == conversation.id }) {
            sideMenuConversations[index].studyTopicID = nil
        }
        if var snapshot = CurrentConversationsStore.load(),
           let index = snapshot.conversations.firstIndex(where: { $0.id == conversation.id }) {
            snapshot.conversations[index].studyTopicID = nil
            CurrentConversationsStore.save(snapshot)
        }
    }

    private func attachConversation(_ conversation: InquiryConversation, toStudyTopic topicID: UUID) {
        // Update in-memory — CurrentConversationView's onChange will pick this up
        // and call persistConversations() if it is currently mounted.
        if let index = sideMenuConversations.firstIndex(where: { $0.id == conversation.id }) {
            sideMenuConversations[index].studyTopicID = topicID
        }

        // Write directly to CurrentConversationsStore so the attachment survives the
        // next app launch even when CurrentConversationView is not mounted (e.g. the
        // user is on the Study Topics page). InquiryPersistenceStore uses a different
        // UserDefaults key and is never read by CurrentConversationView, so writing
        // only to that store was silently losing the attachment.
        if var snapshot = CurrentConversationsStore.load(),
           let index = snapshot.conversations.firstIndex(where: { $0.id == conversation.id }) {
            snapshot.conversations[index].studyTopicID = topicID
            CurrentConversationsStore.save(snapshot)
        }
    }
}

private extension ProcessInfo.ThermalState {
    var modelRuntimePressure: ModelRuntimeThermalPressure {
        switch self {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .serious
        }
    }
}

private extension View {
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }

    func dailyQuestionGenerationAlert(
        isPresented: Binding<Bool>,
        retry: @escaping () -> Void
    ) -> some View {
        modifier(DailyQuestionGenerationAlert(
            isPresented: isPresented,
            retry: retry
        ))
    }
}

private struct DailyQuestionGenerationAlert: ViewModifier {
    @Binding var isPresented: Bool
    let retry: () -> Void

    func body(content: Content) -> some View {
        content.alert("Couldn’t generate Question of the Day", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Try Again", action: retry)
        } message: {
            Text("No placeholder question was created. Check that the Aquinas backend is available and try again.")
        }
    }
}

#Preview {
    ContentView()
}
