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

struct ConceptDefinition: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let word: String
    let partOfSpeech: String
    let pronunciation: String
    let meaning: String
    let example: String

    init(
        id: UUID = UUID(),
        word: String,
        partOfSpeech: String,
        pronunciation: String,
        meaning: String,
        example: String
    ) {
        self.id = id
        self.word = word
        self.partOfSpeech = partOfSpeech
        self.pronunciation = pronunciation
        self.meaning = meaning
        self.example = example
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
    @State private var questionText: String = ""
    @State private var isAtBottom: Bool = false
    @FocusState private var isKeyboardVisible: Bool
    @State private var uploadedFiles: [UploadedFile] = []
    @State private var showFilePicker: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showCamera: Bool = false
    @State private var collectedDefinitions: [ConceptDefinition] = []
    @State private var activePage: AppPage = .home
    @State private var displayedPage: AppPage = .home
    @State private var isPageContentVisible: Bool = true
    @State private var pageContentOffsetY: CGFloat = 0
    @State private var pendingPageTransitionWorkItem: DispatchWorkItem? = nil
    @State private var isGlobalSideMenuOpen: Bool = false
    @State private var isConversationCanvasMode: Bool = false
    // Live drag state for the pull-from-left-edge gesture.
    @State private var sideMenuDragOffset: CGFloat = 0
    @State private var isDraggingToOpenMenu: Bool = false
    @State private var menuOpenHapticFired: Bool = false
    @State private var sideMenuConversations: [InquiryConversation] = []
    @State private var sideMenuActiveConversationID: UUID? = nil
    @State private var sideMenuCurrentTitle: String = "New Conversation"
    @State private var requestedConversationID: UUID? = nil
    @State private var requestedTopicID: UUID? = nil
    @State private var newConversationRequest: Int = 0
    @State private var pendingNewConversationQuestion: String = ""
    @State private var pendingNewConversationEyebrow: String = ""
    @State private var newConversationTopicID: UUID? = nil
    @State private var newConversationIsStudyTopic: Bool = false
    @State private var deletedConversationID: UUID? = nil
    @State private var colorSchemeOverride: ColorScheme? = nil
    @State private var requestedForkConcept: ConceptDefinition? = nil
    @AppStorage("aquinas.settings.userName") private var userName: String = ""
    @State private var customInstructions: String = ""
    @State private var globalInsightSelectionRequest: Int = 0
    @State private var globalInsightClearSelectionRequest: Int = 0
    @State private var globalInsightDismissHoverRequest: Int = 0
    @State private var globalInsightCreateConceptRequest: Int = 0
    @State private var globalInsightPromotedIDs: [UUID] = []
    @State private var globalInsightInquireConnectionRequest: Int = 0
    @State private var globalInsightMidpointEnterRequest: Int = 0
    @State private var globalInsightMidpointCenterRequest: Int = 0
    @State private var globalInsightMidpointPlaceRequest: Int = 0
    @State private var globalInsightHasCanvasHover: Bool = false
    @State private var globalInsightHasInsightHover: Bool = false
    @State private var globalInsightSelectedItemCount: Int = 0
    @State private var globalInsightQuoteTarget: ConceptDefinition? = nil
    @State private var globalInsightIsMidpointMode: Bool = false
    @State private var globalInsightIsGenerating: Bool = false
    @State private var globalInsightIsThinkingEnabled: Bool = false
    @State private var globalInsightSelectedPersonality: String = "Scholarly"
    @State private var globalInsightIsPersonalityMenuOpen: Bool = false
    @State private var globalInsightHighlightedBridge: (UUID, UUID)? = nil
    @State private var globalInsightHighlightRequest: Int = 0
    @AppStorage("aquinas.settings.conversationFontSize") private var conversationFontSize: ConversationFontSizeOption = .small
    @State private var inputTextAlignment: InputTextAlignmentOption = .center
    @State private var inputFont: ConversationFontOption = .serif
    @AppStorage("aquinas.settings.responseTextAlignment") private var responseTextAlignment: ResponseTextAlignmentOption = .center
    @State private var responseFont: ConversationFontOption = .sans


    let canvasColor = AquinasTheme.Colors.canvasSecondary
    private let pageFadeDuration: TimeInterval = 0.25
    private let pageFadePauseDuration: TimeInterval = 0.15
    private let pageTransitionOffset: CGFloat = 8

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
        collectedDefinitions
            .flatMap { [$0.word, $0.meaning, $0.example] }
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
    }

    @ViewBuilder private var insightTreePage: some View {
        InsightTreeView(
            insights: collectedDefinitions,
            selectionRequest: globalInsightSelectionRequest,
            clearSelectionRequest: globalInsightClearSelectionRequest,
            dismissHoverRequest: globalInsightDismissHoverRequest,
            createConceptRequest: globalInsightCreateConceptRequest,
            promotedInsightIDs: globalInsightPromotedIDs,
            onRemoveInsight: { def in
                withAnimation { collectedDefinitions.removeAll { $0.id == def.id } }
            },
            onRestoreInsight: { def in
                withAnimation { collectedDefinitions.append(def) }
            },
            onForkInsight: { def in
                requestedForkConcept = def
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    activePage = .conversation
                }
            },
            onQuoteInsight: { globalInsightQuoteTarget = $0 },
            onSelectionStateChange: { globalInsightHasCanvasHover = $0 },
            onInsightSelectionStateChange: { globalInsightHasInsightHover = $0 },
            onSelectedCanvasItemCountChange: { globalInsightSelectedItemCount = $0 },
            onPromotedInsightIDsChange: { globalInsightPromotedIDs = $0 },
            savedConceptIDs: Set(collectedDefinitions.map(\.id)),
            onToggleSavedConcept: { concept in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if collectedDefinitions.contains(where: { $0.id == concept.id }) {
                        collectedDefinitions.removeAll { $0.id == concept.id }
                    } else {
                        collectedDefinitions.append(concept)
                    }
                }
            },
            inquireConnectionRequest: globalInsightInquireConnectionRequest,
            onInquireConnectionConcepts: { first, _ in
                requestedForkConcept = first
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    activePage = .conversation
                }
            },
            midpointEnterRequest: globalInsightMidpointEnterRequest,
            midpointCenterRequest: globalInsightMidpointCenterRequest,
            midpointPlaceRequest: globalInsightMidpointPlaceRequest,
            highlightedInsightPair: globalInsightHighlightedBridge,
            highlightPairRequest: globalInsightHighlightRequest,
            startsMidpointForHighlightedPair: true,
            onMidpointModeChange: { globalInsightIsMidpointMode = $0 },
            onMidpointGeneratingChange: { globalInsightIsGenerating = $0 },
            inputFont: inputFont,
            conversationFontSize: conversationFontSize,
            showQuestionBar: false
        )
        .safeAreaInset(edge: .bottom) {
            GlobalInsightsModelControls(
                showFilePicker: $showFilePicker,
                showPhotoPicker: $showPhotoPicker,
                showCamera: $showCamera,
                isThinkingEnabled: $globalInsightIsThinkingEnabled,
                selectedPersonality: $globalInsightSelectedPersonality,
                isPersonalityMenuOpen: $globalInsightIsPersonalityMenuOpen,
                hasCanvasHover: globalInsightHasCanvasHover,
                hasCanvasInsightHover: globalInsightHasInsightHover,
                hasSelectedCanvasItems: globalInsightSelectedItemCount > 0,
                selectedCanvasItemCount: globalInsightSelectedItemCount,
                isMidpointMode: globalInsightIsMidpointMode,
                isCanvasInsightLoading: globalInsightIsGenerating,
                contextWordCount: globalInsightContextWordCount,
                onSelectCanvasItem: { globalInsightSelectionRequest += 1 },
                onCreateCanvasConcept: { globalInsightCreateConceptRequest += 1 },
                onInquireConnection: { globalInsightInquireConnectionRequest += 1 },
                onQuoteCanvasItem: {
                    guard let target = globalInsightQuoteTarget else { return }
                    requestedForkConcept = target
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        activePage = .conversation
                    }
                },
                onMidpointConcepts: { globalInsightMidpointEnterRequest += 1 },
                onMidpointCenter: { globalInsightMidpointCenterRequest += 1 },
                onMidpointPlace: { globalInsightMidpointPlaceRequest += 1 },
                onClearCanvasSelection: { globalInsightClearSelectionRequest += 1 },
                onContextWillOpen: { globalInsightDismissHoverRequest += 1 }
            )
        }
        .background(canvasColor)
        .ignoresSafeArea(.container)  // edges/notch only — keyboard safe area is respected
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
            collectedDefinitions: $collectedDefinitions,
            sideMenuConversations: $sideMenuConversations,
            sideMenuCurrentTitle: $sideMenuCurrentTitle,
            sideMenuActiveConversationID: $sideMenuActiveConversationID,
            requestedConversationID: $requestedConversationID,
            newConversationRequest: $newConversationRequest,
            pendingNewConversationQuestion: $pendingNewConversationQuestion,
            pendingNewConversationEyebrow: $pendingNewConversationEyebrow,
            newConversationTopicID: $newConversationTopicID,
            newConversationIsStudyTopic: $newConversationIsStudyTopic,
            deletedConversationID: $deletedConversationID,
            requestedForkConcept: $requestedForkConcept,
            conversationFontSize: conversationFontSize,
            inputTextAlignment: inputTextAlignment,
            inputFont: inputFont,
            responseTextAlignment: responseTextAlignment,
            responseFont: responseFont,
            userName: userName,
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
                    VStack(spacing: 0) {
                        Group {
                            switch displayedPage {
                            case .home:
                                HomeDashboardView(
                                    conversations: sideMenuConversations,
                                    activeConversationID: sideMenuActiveConversationID,
                                    savedInsights: collectedDefinitions,
                                    userName: userName,
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
                                    onStartQuestion: { question in
                                        pendingNewConversationQuestion = question
                                        pendingNewConversationEyebrow = "QUESTION OF THE DAY"
                                        newConversationRequest += 1
                                        activePage = .conversation
                                    },
                                    onOpenInsightBridge: { firstID, secondID in
                                        globalInsightHighlightedBridge = (firstID, secondID)
                                        globalInsightHighlightRequest += 1
                                        activePage = .insights
                                    }
                                )
                            case .conversation:
                                conversationView
                                // ActiveInquiryView(
                                //     activePage: $activePage,
                                //     sideMenuConversations: $sideMenuConversations,
                                //     sideMenuActiveConversationID: $sideMenuActiveConversationID,
                                //     sideMenuCurrentTitle: $sideMenuCurrentTitle,
                                //     requestedConversationID: $requestedConversationID,
                                //     newConversationRequest: $newConversationRequest,
                                //     requestedForkConcept: $requestedForkConcept,
                                //     colorSchemeOverride: $colorSchemeOverride,
                                //     isAtBottom: $isAtBottom,
                                //     showFilePicker: $showFilePicker,
                                //     showPhotoPicker: $showPhotoPicker,
                                //     showCamera: $showCamera,
                                //     questionText: $questionText,
                                //     uploadedFiles: $uploadedFiles,
                                //     collectedDefinitions: $collectedDefinitions
                                // )
                            case .openConversations:
                                OpenConversationsView(
                                    conversations: sideMenuConversations,
                                    activeConversationID: sideMenuActiveConversationID,
                                    savedInsights: $collectedDefinitions,
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
                                    }
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
                                    onOpenMenu: {
                                        dismissKeyboard()
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                            isGlobalSideMenuOpen = true
                                        }
                                    }
                                )
                            case .insights:
                                insightTreePage
                            case .studyTopics:
                                StudyTopicsView(
                                    conversations: sideMenuConversations,
                                    activeConversationID: sideMenuActiveConversationID,
                                    savedInsights: $collectedDefinitions,
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
                                    onAttachConversationToTopic: { conversation, topicID in
                                        attachConversation(conversation, toStudyTopic: topicID)
                                    },
                                    onRenameConversation: { conversation, title in
                                        renameConversation(conversation, to: title)
                                    },
                                    requestedTopicID: requestedTopicID
                                )
                            }
                        }
                        .opacity(isPageContentVisible ? 1 : 0)
                        .offset(y: pageContentOffsetY)
                    }
                    .background(AquinasTheme.Colors.activeInquiryChrome)
                }
                .overlay(alignment: .topLeading) {
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
                        .zIndex(2)
                    }
                }
                .overlay {
                    // Opacity scales from 0→0.16 as the menu is dragged out, so
                    // the backdrop feels physical rather than binary snap-in.
                    let dragProgress = min(345, max(0, sideMenuDragOffset)) / 345
                    let progress: Double = isGlobalSideMenuOpen ? 1.0 : Double(dragProgress)
                    Color.black.opacity(0.16 * progress)
                        .ignoresSafeArea()
                        .allowsHitTesting(progress > 0.02)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                isGlobalSideMenuOpen = false
                                sideMenuDragOffset = 0
                            }
                        }
                        .animation(.easeInOut(duration: 0.22), value: isGlobalSideMenuOpen)
                        .zIndex(3)
                }
                .overlay(alignment: .leading) {
                    AquinasSideMenu(
                            currentTitle: sideMenuCurrentTitle,
                            conversations: sideMenuConversations,
                            activeConversationID: sideMenuActiveConversationID,
                            activePage: activePage,
                            selectedPersonality: "Friendly",
                            isPresented: isGlobalSideMenuOpen,
                            onNewChat: {
                                newConversationRequest += 1
                                activePage = .conversation
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
                                }
                            },
                            onSelectConversation: { conversation in
                                requestedConversationID = conversation.id
                                activePage = .conversation
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
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
                                activePage = .home
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
                                }
                            },
                            onOpenConversations: {
                                activePage = .openConversations
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
                                }
                            },
                            onOpenInsights: {
                                activePage = .insights
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
                                }
                            },
                            onOpenStudyTopics: {
                                requestedTopicID = nil
                                activePage = .studyTopics
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
                                }
                            },
                            onSelectStudyTopic: { topic in
                                requestedTopicID = topic.id
                                activePage = .studyTopics
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
                                }
                            },
                            onOpenSettings: {
                                activePage = .settings
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
                                }
                            },
                            onClose: {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
                                }
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
                        .zIndex(4)
                        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isGlobalSideMenuOpen)
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

            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .preferredColorScheme(colorSchemeOverride)
        .onAppear {
            loadShellConversationState()
            displayedPage = activePage
            isPageContentVisible = true
            pageContentOffsetY = 0
            let savedInsights = InsightLibraryStore.load()
            if !savedInsights.isEmpty {
                collectedDefinitions = savedInsights
            }
        }
        .onChange(of: activePage) { oldValue, newValue in
            transitionDisplayedPage(to: newValue)
        }
        .onChange(of: collectedDefinitions) { oldValue, newValue in
            InsightLibraryStore.save(newValue)
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

        // If we were on the open-conversations page and nothing's left, go back.
        if activePage == .openConversations && sideMenuConversations.isEmpty {
            activePage = .conversation
        }
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

private struct GlobalInsightsModelControls: View {
    @Binding var showFilePicker: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var isThinkingEnabled: Bool
    @Binding var selectedPersonality: String
    @Binding var isPersonalityMenuOpen: Bool
    let hasCanvasHover: Bool
    let hasCanvasInsightHover: Bool
    let hasSelectedCanvasItems: Bool
    let selectedCanvasItemCount: Int
    let isMidpointMode: Bool
    let isCanvasInsightLoading: Bool
    let contextWordCount: Int
    var onSelectCanvasItem: () -> Void
    var onCreateCanvasConcept: () -> Void
    var onInquireConnection: () -> Void
    var onQuoteCanvasItem: () -> Void
    var onMidpointConcepts: () -> Void
    var onMidpointCenter: () -> Void
    var onMidpointPlace: () -> Void
    var onClearCanvasSelection: () -> Void
    var onContextWillOpen: () -> Void

    var body: some View {
        InquiryControlDock(
            isCanvasMode: true,
            showFilePicker: $showFilePicker,
            showPhotoPicker: $showPhotoPicker,
            showCamera: $showCamera,
            isThinkingEnabled: $isThinkingEnabled,
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
            onMidpointConcepts: onMidpointConcepts,
            isMidpointMode: isMidpointMode,
            isCanvasInsightLoading: isCanvasInsightLoading,
            onMidpointCenter: onMidpointCenter,
            onMidpointPlace: onMidpointPlace,
            onClearCanvasSelection: onClearCanvasSelection,
            contextWordCount: contextWordCount,
            onClearConversation: {},
            onContextWillOpen: onContextWillOpen
        )
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
    @Binding var isThinking: Bool
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

            // Thinking toggle.
            Button(action: { isThinking.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .sfSymbolDrawOn()
                    Text("Thinking")
                        .font(.system(size: 15, weight: .medium))
                }
                .padding(.horizontal, 16)
                .aquinasCapsuleControl(isSelected: isThinking)
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
