//  Aquinas-iOS
//
//  Created by Ryan on 4/11/26.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI

// MARK: - Shared Models

/// File/image selected before submitting a question.
struct UploadedFile: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let name: String
    let imageData: Data?
    let rotationDegrees: Double

    init(id: UUID = UUID(), name: String, imageData: Data?, rotationDegrees: Double) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.rotationDegrees = rotationDegrees
    }

    static func == (lhs: UploadedFile, rhs: UploadedFile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct InsightDefinition: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let context: String
    let meaning: String

    init(id: UUID? = nil, context: String, meaning: String) {
        let cleanedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedMeaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id ?? stableUUID(
            from: "insight-definition:\(cleanedContext.lowercased()):\(cleanedMeaning.lowercased())"
        )
        self.context = cleanedContext
        self.meaning = cleanedMeaning
    }

    fileprivate var deduplicationKey: String {
        "\(context.lowercased())\u{1f}\(meaning.lowercased())"
    }
}

struct ConceptDefinition: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let word: String
    let partOfSpeech: String
    let pronunciation: String
    let meaning: String
    let example: String
    let definitions: [InsightDefinition]

    init(
        id: UUID = UUID(),
        word: String,
        partOfSpeech: String,
        pronunciation: String,
        meaning: String,
        example: String,
        context: String = "",
        definitions: [InsightDefinition]? = nil
    ) {
        self.id = id
        self.word = word
        self.partOfSpeech = partOfSpeech
        self.pronunciation = pronunciation
        self.meaning = meaning
        self.example = example
        self.definitions = definitions ?? (
            meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? []
                : [InsightDefinition(context: context, meaning: meaning)]
        )
    }

    var contextualDefinitions: [InsightDefinition] {
        definitions.isEmpty && !meaning.isEmpty
            ? [InsightDefinition(context: "", meaning: meaning)]
            : definitions
    }

    var semanticDefinition: String {
        contextualDefinitions.map { definition in
            definition.context.isEmpty
                ? definition.meaning
                : "\(definition.context): \(definition.meaning)"
        }
        .joined(separator: "\n")
    }

    func containsDefinitions(from other: ConceptDefinition) -> Bool {
        let savedKeys = Set(contextualDefinitions.map(\.deduplicationKey))
        let incoming = other.contextualDefinitions
        return !incoming.isEmpty
            && incoming.allSatisfy { savedKeys.contains($0.deduplicationKey) }
    }

    func mergingDefinitions(from other: ConceptDefinition) -> ConceptDefinition {
        var merged = contextualDefinitions
        var seen = Set(merged.map(\.deduplicationKey))
        for definition in other.contextualDefinitions
        where seen.insert(definition.deduplicationKey).inserted {
            merged.append(definition)
        }
        return ConceptDefinition(
            id: id,
            word: word,
            partOfSpeech: "",
            pronunciation: "",
            meaning: merged.first?.meaning ?? meaning,
            example: "",
            definitions: merged
        )
    }

    /// A stable id derived from the term's canonical text, so re-defining/re-saving the same term
    /// (tapping it again in a different message, or after removing and re-saving it) always
    /// resolves to the same Insight instead of a duplicate with a fresh random id. Use this rather
    /// than the default random `id` whenever a concept originates from a highlighted term.
    static func stableID(forTerm term: String) -> UUID {
        stableUUID(from: "term:\(term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case word
        case partOfSpeech
        case pronunciation
        case meaning
        case example
        case definitions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        partOfSpeech = try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? ""
        pronunciation = try container.decodeIfPresent(String.self, forKey: .pronunciation) ?? ""
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        definitions = try container.decodeIfPresent(
            [InsightDefinition].self,
            forKey: .definitions
        ) ?? (
            meaning.isEmpty ? [] : [InsightDefinition(context: "", meaning: meaning)]
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(word, forKey: .word)
        try container.encode(partOfSpeech, forKey: .partOfSpeech)
        try container.encode(pronunciation, forKey: .pronunciation)
        try container.encode(meaning, forKey: .meaning)
        try container.encode(example, forKey: .example)
        try container.encode(definitions, forKey: .definitions)
    }
}

enum AppPage: Equatable {
    case home
    case conversation
    case openConversations
    case settings
    case insights
    case studyTopics
}

// MARK: - App Shell

struct ContentView: View {
    @Environment(\.aquinasModel) private var aquinasModel
    @Environment(\.embeddingProvider) private var embeddingProvider
    @Environment(\.scenePhase) private var scenePhase

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
    /// After accepting an update, Global Insights stays quiet until model work originating on a
    /// different page completes. Global-page actions must not repeatedly re-offer the same sync.
    @State private var suppressGlobalTreePromptUntilExternalModelCompletion: Bool = false
    @State private var activePage: AppPage = .home
    @State private var displayedPage: AppPage = .home
    @State private var isPageContentVisible: Bool = true
    @State private var pageContentOffsetY: CGFloat = 0
    @State private var pendingPageTransitionWorkItem: DispatchWorkItem? = nil
    @State private var isGlobalSideMenuOpen: Bool = false
    // Set while a Study Topic's detail view is open, so the global edge-swipe
    // gesture below yields to that screen's own swipe-to-go-back gesture.
    @State private var isStudyTopicDetailVisible: Bool = false
    @State private var isSettingsDetailVisible: Bool = false
    @State private var isConversationCanvasMode: Bool = false
    @State private var globalInsightsContextCardState = ContextCardState()
    // Live drag state for the pull-from-left-edge gesture.
    @State private var sideMenuDragOffset: CGFloat = 0
    @State private var isDraggingToOpenMenu: Bool = false
    @State private var menuOpenHapticFired: Bool = false
    @State private var sideMenuConversations: [InquiryConversation] = []
    @State private var sideMenuActiveConversationID: UUID? = nil
    @State private var sideMenuCurrentTitle: String = "New Conversation"
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
    @State private var globalInsightSelectionRequest: Int = 0
    /// Set when returning to the global Insight Tree after removing a quoted Insight's chip
    /// from a conversation's composer — the tree hovers/selects this Insight on appear.
    @State private var globalInsightRestoreSelectionID: UUID? = nil
    @State private var globalInsightClearSelectionRequest: Int = 0
    @State private var globalInsightDismissHoverRequest: Int = 0
    @State private var globalInsightCreateConceptRequest: Int = 0
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
    @State private var modelCompletionNotifications = ModelCompletionNotificationCenter()
    @State private var questionOfTheDay = HomeQuestionOfTheDayStore.loadPending()
    @State private var dailyQuestionRefreshTask: Task<Void, Never>? = nil
    @State private var isDailyQuestionGenerationErrorPresented: Bool = false
    @State private var homeLooseThread: LooseThreadCard? = nil
    @State private var homeTodayInHistory: TodayInHistoryCard? = nil
    @State private var homeGlossedTerm: GlossedTermCard? = nil
    @State private var homeYourQuote: YourQuoteCard? = nil
    @Environment(\.homeBackendService) private var homeBackendService
    @AppStorage("aquinas.settings.conversationFontSize") private var conversationFontSize: ConversationFontSizeOption = .small
    @AppStorage("aquinas.settings.inputTextAlignment") private var inputTextAlignment: InputTextAlignmentOption = .center
    @AppStorage("aquinas.settings.inputFont") private var inputFont: ConversationFontOption = .serif
    @AppStorage("aquinas.settings.responseTextAlignment") private var responseTextAlignment: ResponseTextAlignmentOption = .center
    @AppStorage("aquinas.settings.responseFont") private var responseFont: ConversationFontOption = .sans
    @AppStorage("aquinas.settings.conversationPersonality") private var conversationPersonality: ConversationPersonality = .balanced


    let canvasColor = AquinasTheme.Colors.canvas
    private let pageFadeDuration: TimeInterval = 0.25
    private let pageFadePauseDuration: TimeInterval = 0.15
    private let pageTransitionOffset: CGFloat = 8

    init() {
        _modelTasks = State(initialValue: ModelTaskQueue())
    }

    init(modelTasks: ModelTaskQueue) {
        _modelTasks = State(initialValue: modelTasks)
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
        globalTreeInsights
            .flatMap { [$0.word, $0.meaning, $0.example] }
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
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

    @ViewBuilder private var insightTreePage: some View {
        InsightTreeView(
            insights: globalTreeInsights,
            selectionRequest: globalInsightSelectionRequest,
            clearSelectionRequest: globalInsightClearSelectionRequest,
            dismissHoverRequest: globalInsightDismissHoverRequest,
            createConceptRequest: globalInsightCreateConceptRequest,
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
            savedConceptIDs: Set(collectedDefinitions.map(\.id)),
            onToggleSavedConcept: { concept in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if collectedDefinitions.contains(where: { $0.id == concept.id }) {
                        collectedDefinitions.removeAll { $0.id == concept.id }
                        // Un-saving must disappear from the global tree's own persisted
                        // snapshot too, not just the bookmark list — otherwise relaunching
                        // reloads the stale snapshot and the "removed" insight comes back.
                        // Mirrors onRemoveInsight's immediate removal+persist above; only the
                        // add direction is deliberately gated behind the "Update Tree" prompt.
                        globalTreeInsights.removeAll { $0.id == concept.id }
                        GlobalInsightTreeStore.save(globalTreeInsights)
                    } else {
                        collectedDefinitions.append(concept)
                    }
                }
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
        .safeAreaInset(edge: .bottom) {
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
                isCanvasInsightLoading: globalInsightIsGenerating,
                contextWordCount: globalInsightContextWordCount,
                modelTasks: modelTasks,
                modelTasksPopupState: modelTasksPopupState,
                searchText: $globalInsightSearchQuery,
                isSearchActive: $globalInsightIsSearchActive,
                searchResultIndex: globalInsightSearchResultIndex,
                searchResultCount: globalInsightSearchResultCount,
                onSelectCanvasItem: { globalInsightSelectionRequest += 1 },
                onCreateCanvasConcept: { globalInsightCreateConceptRequest += 1 },
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
        }
        .background(canvasColor)
        .ignoresSafeArea(.container)  // edges/notch only — keyboard safe area is respected
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
            onOpenMenu: {
                dismissKeyboard()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    isGlobalSideMenuOpen = true
                }
            },
            onCanvasModeChange: { isConversationCanvasMode = $0 },
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
            inputTextAlignment: inputTextAlignment,
            inputFont: inputFont,
            responseTextAlignment: responseTextAlignment,
            responseFont: responseFont,
            conversationPersonality: $conversationPersonality,
            userName: userName,
            isPageVisible: activePage == .conversation,
            modelTasks: modelTasks,
            modelTasksPopupState: modelTasksPopupState,
            uploadedFiles: $uploadedFiles,
            showFilePicker: $showFilePicker
        )
    }

    var body: some View {
        GeometryReader { _ in
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
                                    onOpenMenu: {
                                        dismissKeyboard()
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                            isGlobalSideMenuOpen = true
                                        }
                                    },
                                    onSelectConversation: { conversation in
                                        requestedConversationID = conversation.id
                                        activePage = .conversation
                                    },
                                    onNewConversation: {
                                        newConversationRequest += 1
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
                                .safeAreaInset(edge: .bottom) {
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
                                }
                            case .conversation:
                                Color.clear
                                    .allowsHitTesting(false)
                            case .openConversations:
                                OpenConversationsView(
                                    conversations: sideMenuConversations,
                                    activeConversationID: sideMenuActiveConversationID,
                                    savedInsights: $collectedDefinitions,
                                    modelTasks: modelTasks,
                                    modelTasksPopupState: modelTasksPopupState,
                                    onOpenMenu: {
                                        dismissKeyboard()
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                            isGlobalSideMenuOpen = true
                                        }
                                    },
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
                                    inputTextAlignment: $inputTextAlignment,
                                    inputFont: $inputFont,
                                    responseTextAlignment: $responseTextAlignment,
                                    responseFont: $responseFont,
                                    conversationPersonality: $conversationPersonality,
                                    onOpenMenu: {
                                        dismissKeyboard()
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                            isGlobalSideMenuOpen = true
                                        }
                                    },
                                    onDetailVisibilityChange: { isSettingsDetailVisible = $0 }
                                )
                                .safeAreaInset(edge: .bottom) {
                                    PageModelControls(
                                        modelTasks: modelTasks,
                                        popupState: modelTasksPopupState
                                    )
                                }
                            case .insights:
                                insightTreePage
                            case .studyTopics:
                                StudyTopicsView(
                                    conversations: sideMenuConversations,
                                    activeConversationID: sideMenuActiveConversationID,
                                    savedInsights: $collectedDefinitions,
                                    modelTasks: modelTasks,
                                    modelTasksPopupState: modelTasksPopupState,
                                    onOpenMenu: {
                                        dismissKeyboard()
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                            isGlobalSideMenuOpen = true
                                        }
                                    },
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
                                    }
                                )
                            }
                        }
                        .opacity(displayedPage == .conversation ? 0 : 1)
                        .allowsHitTesting(displayedPage != .conversation)
                        .accessibilityHidden(displayedPage == .conversation)
                        .opacity(isPageContentVisible ? 1 : 0)
                        .offset(y: pageContentOffsetY)
                    }
                    .background(AquinasTheme.Colors.activeInquiryChrome)
                }
                // ── Full-screen pull-to-open gesture ──────────────────────────
                // Runs simultaneously with canvas/scroll gestures so it doesn't
                // intercept taps or vertical scrolls. Horizontal-bias guard
                // (|x| > |y|) and rightward-only check keep it from firing
                // during normal vertical scrolling or leftward swipes.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .local)
                        .onChanged { value in
                            guard !isGlobalSideMenuOpen else { return }
                            // A Study Topic's detail view owns the swipe-to-go-back gesture
                            // while it's open — don't compete with it for the same drag.
                            guard !(activePage == .studyTopics && isStudyTopicDetailVisible) else { return }
                            // Settings submenus use the same leading-edge gesture to navigate
                            // back within their own NavigationStack.
                            guard !(activePage == .settings && isSettingsDetailVisible) else { return }
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            if !isDraggingToOpenMenu {
                                guard value.translation.width > 0 else { return }
                                // Require an edge start anywhere in the conversation page (canvas
                                // OR reading) so dragging a text-selection handle mid-screen
                                // doesn't open the menu. Other pages keep the full-screen swipe.
                                let needsEdgeOnly = activePage == .insights
                                    || activePage == .conversation
                                if needsEdgeOnly {
                                    guard value.startLocation.x < 30 else { return }
                                }
                                isDraggingToOpenMenu = true
                                dismissKeyboard()
                            }
                            let clamped = min(345, max(0, value.translation.width))
                            sideMenuDragOffset = clamped
                            if clamped >= 175 && !menuOpenHapticFired {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                menuOpenHapticFired = true
                            } else if clamped < 175 {
                                menuOpenHapticFired = false
                            }
                        }
                        .onEnded { value in
                            guard isDraggingToOpenMenu else { return }
                            menuOpenHapticFired = false
                            let shouldOpen = value.translation.width > 175
                                || value.predictedEndTranslation.width > 250
                            if shouldOpen {
                                isDraggingToOpenMenu = false
                                isGlobalSideMenuOpen = true
                                sideMenuDragOffset = 0
                            } else {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isDraggingToOpenMenu = false
                                    sideMenuDragOffset = 0
                                }
                            }
                        }
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
                                let imageData = data.flatMap { UIImage(data: $0) == nil ? nil : $0 }

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
                    SideMenuTriggerButton {
                        dismissKeyboard()
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                            isGlobalSideMenuOpen = true
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.top, 24)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .zIndex(2)
                }

                // Opacity scales from 0→0.16 as the menu is dragged out, so
                // the backdrop feels physical rather than binary snap-in.
                let dragProgress = min(345, max(0, sideMenuDragOffset)) / 345
                let progress: Double = isGlobalSideMenuOpen ? 1.0 : Double(dragProgress)
                Color.black.opacity(0.16 * progress)
                    .ignoresSafeArea()
                    .allowsHitTesting(progress > 0.02)
                    .onTapGesture {
                        dismissGlobalSideMenu()
                    }
                    .animation(.easeInOut(duration: 0.22), value: isGlobalSideMenuOpen)
                    .zIndex(3)

                AquinasSideMenu(
                        currentTitle: sideMenuCurrentTitle,
                        conversations: sideMenuConversations,
                        activeConversationID: sideMenuActiveConversationID,
                        activePage: activePage,
                        modelTasks: modelTasks,
                        selectedPersonality: conversationPersonality.displayName,
                        isPresented: isGlobalSideMenuOpen,
                        onNewChat: {
                            dismissGlobalSideMenu {
                                newConversationRequest += 1
                                activePage = .conversation
                            }
                        },
                        onSelectConversation: { conversation in
                            dismissGlobalSideMenu {
                                requestedConversationID = conversation.id
                                activePage = .conversation
                            }
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
                        newInsightsCount: newInsightsCount,
                        onOpenHome: {
                            dismissGlobalSideMenu {
                                activePage = .home
                            }
                        },
                        onOpenConversations: {
                            dismissGlobalSideMenu {
                                activePage = .openConversations
                            }
                        },
                        onOpenInsights: {
                            dismissGlobalSideMenu {
                                activePage = .insights
                            }
                        },
                        onOpenStudyTopics: {
                            dismissGlobalSideMenu {
                                requestedTopicID = nil
                                activePage = .studyTopics
                            }
                        },
                        onSelectStudyTopic: { topic in
                            dismissGlobalSideMenu {
                                requestedTopicID = topic.id
                                activePage = .studyTopics
                            }
                        },
                        onOpenSettings: {
                            dismissGlobalSideMenu {
                                activePage = .settings
                            }
                        },
                        onClose: {
                            dismissGlobalSideMenu()
                        }
                    )
                    .frame(width: 325)
                    // When closed, add the live drag offset so the panel follows
                    // the finger.  The implicit spring animation only fires when
                    // isGlobalSideMenuOpen changes, so drag updates are instant
                    // (finger-tracked) while snap-open/close use the spring.
                    .offset(x: isGlobalSideMenuOpen
                        ? 0
                        : (-345 + min(345, max(0, sideMenuDragOffset))))
                    .opacity(isGlobalSideMenuOpen || isDraggingToOpenMenu ? 1 : 0.96)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    // The outer alignment frame covers the whole screen even while the panel is
                    // translated offscreen. Disable it while closed so it cannot swallow taps
                    // intended for the visible page underneath.
                    .allowsHitTesting(isGlobalSideMenuOpen || isDraggingToOpenMenu)
                    // Guaranteed topmost: a direct ZStack sibling (not a nested
                    // .overlay()) so this zIndex is actually compared against the
                    // page content's zIndex, rather than being the sole child of
                    // its own separate overlay layer.
                    .zIndex(1000)
                    .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isGlobalSideMenuOpen)

            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .environment(
            \.modelCompletionNotifications,
            modelCompletionNotifications
        )
        .environment(\.openModelTaskPage, openModelTaskPage)
        .preferredColorScheme(colorSchemeOverride)
        .alert(
            "Couldn’t generate Question of the Day",
            isPresented: $isDailyQuestionGenerationErrorPresented
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Try Again") {
                scheduleDailyQuestionRefreshIfNeeded(minimumDelay: 0)
            }
        } message: {
            Text("No placeholder question was created. Check that the Aquinas backend is available and try again.")
        }
        .onAppear {
            modelTasks.setPersonality(conversationPersonality)
            modelTasks.setApplicationActive(scenePhase == .active)
            modelTasks.updateThermalPressure(
                ProcessInfo.processInfo.thermalState.modelRuntimePressure
            )
            loadShellConversationState()
            displayedPage = activePage
            isPageContentVisible = true
            pageContentOffsetY = 0
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
        .onChange(of: activePage) { oldValue, newValue in
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
        .onChange(of: modelTasks.isBusy) { _, _ in
            scheduleDailyQuestionRefreshIfNeeded()
        }
        // Mirrors CurrentConversationView's identical interlock for its own per-conversation
        // Insight Tree — the Global tree had the same "both open at once" gap since nothing here
        // reacted to a hover starting after the Model Tasks popup was already open.
        .onChange(of: globalInsightHasInsightHover) { _, isHoveringInsight in
            guard isHoveringInsight else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                modelTasksPopupState.reset()
            }
        }
        .onChange(of: modelTasks.latestCompletedTask) { _, completedTask in
            guard let completedTask, completedTask.originPage != .insights else { return }
            suppressGlobalTreePromptUntilExternalModelCompletion = false
            guard activePage == .insights else { return }
            refreshGlobalInsightTreeUpdatePrompt()
        }
        .onChange(of: conversationPersonality) { _, personality in
            modelTasks.setPersonality(personality)
        }
        .onChange(of: sideMenuConversations) { _, _ in
            scheduleDailyQuestionRefreshIfNeeded()
        }
        .onChange(of: collectedDefinitions) { _, _ in
            scheduleDailyQuestionRefreshIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            modelTasks.setApplicationActive(phase == .active)
            scheduleDailyQuestionRefreshIfNeeded()
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
        .onChange(of: collectedDefinitions) { oldValue, newValue in
            InsightLibraryStore.save(newValue)
            guard activePage == .insights,
                  !suppressGlobalTreePromptUntilExternalModelCompletion else { return }
            isGlobalTreeUpdatePromptVisible = globalTreeNeedsUpdate
        }
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
            sideMenuDragOffset = 0
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
        let delay = max(minimumDelay, eligibilityDate.timeIntervalSinceNow)
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
                  HomeQuestionOfTheDayStore.isEligibleForRefresh(),
                  let source = DailyQuestionSourceSelector.select(
                      conversations: sideMenuConversations,
                      activeConversationID: sideMenuActiveConversationID,
                      savedInsights: collectedDefinitions
                  ) else {
                dailyQuestionRefreshTask = nil
                scheduleDailyQuestionRefreshIfNeeded()
                return
            }

            dailyQuestionRefreshTask = nil
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
                    isDailyQuestionGenerationErrorPresented = true
                    return
                }
                guard !Task.isCancelled else { return }
                let trimmedQuestion = draft.question.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !trimmedQuestion.isEmpty else { return }

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
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            globalTreeInsights = collectedDefinitions.uniquedByWord()
            isGlobalTreeUpdatePromptVisible = false
            suppressGlobalTreePromptUntilExternalModelCompletion = true
        }
        GlobalInsightTreeStore.save(globalTreeInsights)
        globalInsightsContextCardState.reset()
        modelTasksPopupState.reset()
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
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

private struct GlobalInsightsModelControls: View {
    @Binding var showFilePicker: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var selectedPersonality: String
    @Binding var isPersonalityMenuOpen: Bool
    let hasCanvasHover: Bool
    let hasCanvasInsightHover: Bool
    let hasSelectedCanvasItems: Bool
    let selectedCanvasItemCount: Int
    let isMidpointMode: Bool
    let isCanvasInsightLoading: Bool
    let contextWordCount: Int
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    @Binding var searchText: String
    @Binding var isSearchActive: Bool
    let searchResultIndex: Int
    let searchResultCount: Int
    var onSelectCanvasItem: () -> Void
    var onCreateCanvasConcept: () -> Void
    var onInquireConnection: () -> Void
    var onQuoteCanvasItem: () -> Void
    let usesCanvasAskFlow: Bool
    let isCanvasAskMode: Bool
    var onAskInNewConversation: () -> Void
    var onAskInExistingConversation: () -> Void
    var onCancelCanvasAsk: () -> Void
    var onMidpointConcepts: () -> Void
    var onMidpointCenter: () -> Void
    var onMidpointPlace: () -> Void
    var onSearchPrevious: () -> Void
    var onSearchNext: () -> Void
    var onSearchActivated: () -> Void
    var onClearCanvasSelection: () -> Void
    var onContextWillOpen: () -> Void
    let confirmationTitle: String?
    var onConfirmUpdate: () -> Void
    var onDeclineUpdate: () -> Void
    let contextCard: ContextCardState

    var body: some View {
        InquiryControlDock(
            isCanvasMode: true,
            showFilePicker: $showFilePicker,
            showPhotoPicker: $showPhotoPicker,
            showCamera: $showCamera,
            selectedPersonality: $selectedPersonality,
            isPersonalityMenuOpen: $isPersonalityMenuOpen,
            isAtBottom: true,
            hasCanvasHover: hasCanvasHover,
            hasCanvasInsightHover: hasCanvasInsightHover,
            hasSelectedCanvasItems: hasSelectedCanvasItems,
            selectedCanvasItemCount: selectedCanvasItemCount,
            onScrollToBottom: {},
            onViewEntireCanvas: {},
            onOpenInsights: {},
            onSelectCanvasItem: onSelectCanvasItem,
            onCreateCanvasConcept: onCreateCanvasConcept,
            onInquireConnection: onInquireConnection,
            onQuoteCanvasItem: onQuoteCanvasItem,
            usesCanvasAskFlow: usesCanvasAskFlow,
            isCanvasAskMode: isCanvasAskMode,
            onAskInNewConversation: onAskInNewConversation,
            onAskInExistingConversation: onAskInExistingConversation,
            onCancelCanvasAsk: onCancelCanvasAsk,
            onMidpointConcepts: onMidpointConcepts,
            isMidpointMode: isMidpointMode,
            isCanvasInsightLoading: isCanvasInsightLoading,
            modelTasks: modelTasks,
            modelTasksPopupState: modelTasksPopupState,
            canvasSearchText: $searchText,
            isCanvasSearchActive: $isSearchActive,
            canvasSearchResultIndex: searchResultIndex,
            canvasSearchResultCount: searchResultCount,
            onCanvasSearchPrevious: onSearchPrevious,
            onCanvasSearchNext: onSearchNext,
            onCanvasSearchActivated: onSearchActivated,
            onModelStatusTap: {
                globalModelStatusTap()
            },
            confirmationTitle: confirmationTitle,
            onConfirm: onConfirmUpdate,
            onDecline: onDeclineUpdate,
            onMidpointCenter: onMidpointCenter,
            onMidpointPlace: onMidpointPlace,
            onClearCanvasSelection: onClearCanvasSelection,
            contextWordCount: contextWordCount,
            onClearConversation: {},
            onContextWillOpen: {
                modelTasksPopupState.reset()
                onContextWillOpen()
            },
            contextCard: contextCard
        )
    }

    private func globalModelStatusTap() {
        contextCard.reset()
        if !modelTasksPopupState.isOpen {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred(intensity: 0.65)
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            modelTasksPopupState.isOpen.toggle()
        }
    }
}

// MARK: - Camera Capture

struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

// MARK: - Legacy Floating Model Controls

/// Older standalone toolbar kept for reference. The active dock now lives in ActiveInquiry.swift.
struct ModelControlsToolbar: View {
    @Binding var showFilePicker: Bool
    @Binding var personality: String

    // Controls the visibility of the jump-to-bottom button.
    @Binding var isAtBottom: Bool
    var onScrollToBottom: () -> Void

    let brandGreen = AquinasTheme.Colors.secondaryMuted

    var body: some View {
        HStack(spacing: 12) {

            // Attachment button.
            Button(action: { showFilePicker = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .sfSymbolDrawOn()
                    .aquinasIconControl()
            }

            // Personality toggle.
            Button(action: {
                personality = personality == "Friendly" ? "Scholarly" : "Friendly"
            }) {
                HStack(spacing: 8) {
                    Image(systemName: personality == "Friendly" ? "brain.head.profile.fill" : "book.pages.fill")
                        .sfSymbolDrawOn()
                    Text(personality)
                        .font(.system(size: 15, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .sfSymbolDrawOn()
                }
                .padding(.horizontal, 16)
                .aquinasCapsuleControl()
            }

            Spacer()

            // Scroll-to-bottom appears only when needed.
            if !isAtBottom {
                Button(action: {
                    onScrollToBottom()
                }) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 16, weight: .bold))
                        .sfSymbolDrawOn()
                        .aquinasIconControl(isPrimary: true)
                        .shadow(color: AquinasTheme.Colors.floatingShadow, radius: 4, y: 2)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isAtBottom)
    }
}

#Preview {
    ContentView()
}
