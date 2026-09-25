//
//  InsightTreeView.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

// MARK: - Insight Tree View

private let insightTreeCanvasColor = AquinasTheme.Colors.canvas
private let insightTreeInsightColor = AquinasTheme.Colors.canvasSecondary

struct InsightTreeView: View {
    let insights: [ConceptDefinition]
    let conversationID: UUID?
    var selectionRequest: Int = 0
    var persistedTreeRefreshRequest: Int = 0
    var clearSelectionRequest: Int = 0
    var dismissHoverRequest: Int = 0
    var createConceptRequest: Int = 0
    /// Monotonically increasing request from the shared canvas controls to study the hovered Insight.
    var studyRequest: Int = 0
    var studyExitRequest: Int = 0
    /// Toggles Study's tool card (the dock's Tools button).
    var studyToolsToggleRequest: Int = 0
    var studyBranchCount: Int = 2
    var onStudyModeChange: ((Bool) -> Void)? = nil
    /// Whether Study's tools are open, so the dock can color its Tools button.
    var onStudyToolsActiveChange: ((Bool) -> Void)? = nil
    var onStudyBranchCountChange: ((Int) -> Void)? = nil
    var restoreSelectedInsightID: UUID? = nil
    var restoreSelectedNodeID: UUID? = nil
    var nodeSelectionRequest: Int = 0
    var promotedInsightIDs: [UUID] = []
    var onClose: (() -> Void)?
    var onRemoveInsight:  ((ConceptDefinition) -> Void)? = nil
    var onRestoreInsight: ((ConceptDefinition) -> Void)? = nil
    var onForkInsight:    ((ConceptDefinition) -> Void)? = nil
    var onQuoteInsight:   ((ConceptDefinition?) -> Void)? = nil
    var onSelectionStateChange: ((Bool) -> Void)? = nil
    var onInsightSelectionStateChange: ((Bool) -> Void)? = nil
    var onSelectedCanvasItemCountChange: ((Int) -> Void)? = nil
    var onPromotedInsightIDsChange: (([UUID]) -> Void)? = nil
    var savedConceptIDs: Set<UUID> = []
    var onToggleSavedConcept: ((ConceptDefinition) -> Void)? = nil
    var onBookmarkConcepts: (([ConceptDefinition]) -> Void)? = nil
    var inquireConnectionRequest: Int = 0
    var onInquireConnectionConcepts: (([ConceptDefinition]) -> Void)? = nil
    var midpointEnterRequest: Int = 0
    var midpointCenterRequest: Int = 0
    var midpointPlaceRequest: Int = 0
    var searchQuery: String = ""
    var searchPreviousRequest: Int = 0
    var searchNextRequest: Int = 0
    var onSearchResultsChange: ((_ current: Int, _ total: Int) -> Void)? = nil
    var highlightedInsightPair: (UUID, UUID)? = nil
    var highlightPairRequest: Int = 0
    var startsMidpointForHighlightedPair: Bool = false
    var onMidpointModeChange: ((Bool) -> Void)? = nil
    /// Reports whether a just-placed midpoint insight is currently "generating".
    var onMidpointGeneratingChange: ((Bool) -> Void)? = nil
    var onUndiscoveredInsightCountChange: ((Int) -> Void)? = nil
    /// Fires after a mutation-triggered persisted snapshot is fully reconciled and applied.
    var onPersistedTreeRefreshCompleted: (() -> Void)? = nil
    var inputFont: ConversationFontOption = .serif
    var conversationFontSize: ConversationFontSizeOption = .small
    var showQuestionBar: Bool = true
    let modelTasks: ModelTaskQueue?
    let modelTaskOriginPage: ModelTaskOriginPage
    let model: AquinasModel
    let embeddingProvider: EmbeddingProvider
    let insightTreeService: InsightTreeService
    let reconcilesPersistedSavedInsights: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// On a landscape phone the tree becomes a true left-hand workspace. The detail dock and
    /// shared model controls use the matching right-hand pane instead of floating over the map.
    private var usesLandscapeSplitLayout: Bool {
        verticalSizeClass == .compact
    }

    @StateObject private var viewModel: InsightTreeViewModel
    @State private var selectedInsight: InsightModel?
    @State private var selectedNode: NodeModel?
    @State private var hoveredConcept: ConceptDefinition?
    /// Insight id of a just-placed midpoint while it "loads" on the canvas.
    @State private var midpointPlacedInsightID: UUID?
    /// Matches the placed id only after its generated content has replaced the loading
    /// placeholder. The canvas waits for this signal before revealing the title and card.
    @State private var midpointGeneratedInsightID: UUID?
    @State private var midpointGenerationTask: Task<Void, Never>?
    /// True only for the card that pops after a midpoint placement, so its body text
    /// animates in like a streamed model response.
    @State private var animateMidpointCardText: Bool = false
    @State private var dockedCardDragY: CGFloat = 0
    /// While Make Node generates children from a docked insight, its card stays up and grows an
    /// Insight link per child. `makeNodeParentInsightID` is the insight whose card is growing;
    /// `makeNodeLinkInsightIDs` are the child ids revealed so far (each appended on its haptic).
    @State private var makeNodeParentInsightID: UUID?
    @State private var makeNodeLinkInsightIDs: [UUID] = []
    /// True from the Make Node tap until generation finishes, so the generation zoom-out doesn't
    /// dismiss the parent card we're growing.
    @State private var makeNodeGenerating: Bool = false
    @State private var restoreFocusedCameraRequest: Int = 0
    @State private var focusedInsightID: UUID?
    @State private var focusedNodeID: UUID?
    @State private var undoInsight: ConceptDefinition? = nil
    @State private var undoTask: Task<Void, Never>? = nil
    @State private var pendingRemoveInsight: InsightModel? = nil
    @State private var pendingUnbookmarkMakeNode: NodeModel? = nil
    @State private var questionBarContextInsight: InsightModel? = nil
    @State private var questionBarKeyboardActive: Bool = false
    @State private var cardShouldHide: Bool = false
    @State private var chipShouldShow: Bool = false
    @State private var questionBarFocusTrigger: Int = 0
    @State private var selectedCanvasTargets: [CanvasSelectionTarget] = []
    @State private var selectionPulseRequest: Int = 0
    @State private var isMidpointMode: Bool = false
    @State private var midpointWeights: [Double] = []
    @State private var midpointTargetIndex: Int = 0
    @State private var midpointTargetWeight: Double = 0.5
    @State private var midpointPercentRequest: Int = 0
    @State private var searchResults: [CanvasSelectionTarget] = []
    @State private var searchResultIndex: Int = 0
    /// Advances only after a backend snapshot has been fully reconciled and applied.
    /// The canvas uses this—not its own appearance—to decide when a persisted update may animate.
    @State private var persistedTreePresentationRevision: Int = 0
    /// Equals `persistedTreePresentationRevision` only for refreshes caused by a completed
    /// mutation. Initial loads establish a baseline without touring the camera.
    @State private var animatedPersistedTreePresentationRevision: Int = 0
    /// Prevents a slower initial fetch from overwriting a newer mutation-triggered refresh.
    @State private var persistedTreeLoadGeneration: Int = 0
    @State private var isModelActionErrorPresented: Bool = false
    @State private var pendingModelActionRetry: (() -> Void)? = nil
    /// The selected Insight stays selected beneath this overlay, so Exit can restore the exact
    /// hover state the user entered from.
    @State private var studySubject: StudySubject?
    @State private var isExitingStudy: Bool = false
    /// The canvas's origin in `InsightTreeStackSpace`, to hand it the Study slot in its own
    /// coordinates.
    @State private var canvasOriginInStack: CGPoint = .zero
    /// The Node Concept Study slot in `InsightTreeStackSpace`, laid out by `StudyModeView`.
    @State private var studySlotInStack: CGRect?
    /// Study's tool card replaces the docked card while Study is open. Kept for the next
    /// Study session, like the last selected tool.
    /// Study's tools are open: the tool card replaces the hover card and previews run. Opened
    /// and closed by the dock's Tools button or by swiping the card down; moving around the
    /// node doesn't close it.
    @State private var showsStudyToolCard = false
    @State private var studyToolCardDragY: CGFloat = 0
    /// The last Study tool, remembered across launches.
    @AppStorage("study.lastSelectedTool") private var studyToolRawValue = StudyTool.branch.rawValue
    @State private var studyToolDirection = 1
    /// Kept separate from `studySubject` so the hovered card is reinserted with its normal
    /// dock transition after Study clears, rather than merely becoming visible underneath it.
    @State private var showsDockedCardAfterStudy: Bool = true

    init(
        insights: [ConceptDefinition],
        conversationID: UUID? = nil,
        selectionRequest: Int = 0,
        persistedTreeRefreshRequest: Int = 0,
        clearSelectionRequest: Int = 0,
        dismissHoverRequest: Int = 0,
        createConceptRequest: Int = 0,
        studyRequest: Int = 0,
        studyExitRequest: Int = 0,
        studyToolsToggleRequest: Int = 0,
        studyBranchCount: Int = 2,
        onStudyModeChange: ((Bool) -> Void)? = nil,
        onStudyToolsActiveChange: ((Bool) -> Void)? = nil,
        onStudyBranchCountChange: ((Int) -> Void)? = nil,
        restoreSelectedInsightID: UUID? = nil,
        restoreSelectedNodeID: UUID? = nil,
        nodeSelectionRequest: Int = 0,
        promotedInsightIDs: [UUID] = [],
        onClose: (() -> Void)? = nil,
        onRemoveInsight:  ((ConceptDefinition) -> Void)? = nil,
        onRestoreInsight: ((ConceptDefinition) -> Void)? = nil,
        onForkInsight:    ((ConceptDefinition) -> Void)? = nil,
        onQuoteInsight:   ((ConceptDefinition?) -> Void)? = nil,
        onSelectionStateChange: ((Bool) -> Void)? = nil,
        onInsightSelectionStateChange: ((Bool) -> Void)? = nil,
        onSelectedCanvasItemCountChange: ((Int) -> Void)? = nil,
        onPromotedInsightIDsChange: (([UUID]) -> Void)? = nil,
        savedConceptIDs: Set<UUID> = [],
        onToggleSavedConcept: ((ConceptDefinition) -> Void)? = nil,
        onBookmarkConcepts: (([ConceptDefinition]) -> Void)? = nil,
        inquireConnectionRequest: Int = 0,
        onInquireConnectionConcepts: (([ConceptDefinition]) -> Void)? = nil,
        midpointEnterRequest: Int = 0,
        midpointCenterRequest: Int = 0,
        midpointPlaceRequest: Int = 0,
        searchQuery: String = "",
        searchPreviousRequest: Int = 0,
        searchNextRequest: Int = 0,
        onSearchResultsChange: ((_ current: Int, _ total: Int) -> Void)? = nil,
        highlightedInsightPair: (UUID, UUID)? = nil,
        highlightPairRequest: Int = 0,
        startsMidpointForHighlightedPair: Bool = false,
        onMidpointModeChange: ((Bool) -> Void)? = nil,
        onMidpointGeneratingChange: ((Bool) -> Void)? = nil,
        onUndiscoveredInsightCountChange: ((Int) -> Void)? = nil,
        onPersistedTreeRefreshCompleted: (() -> Void)? = nil,
        inputFont: ConversationFontOption = .serif,
        conversationFontSize: ConversationFontSizeOption = .small,
        showQuestionBar: Bool = true,
        modelTasks: ModelTaskQueue? = nil,
        modelTaskOriginPage: ModelTaskOriginPage = .insights,
        model: AquinasModel = MockAquinasModel(),
        embeddingProvider: EmbeddingProvider = NLEmbeddingProvider(),
        insightTreeService: InsightTreeService = BackendInsightTreeService(),
        reconcilesPersistedSavedInsights: Bool = false
    ) {
        self.insights              = insights
        self.conversationID        = conversationID
        self.model                 = model
        self.embeddingProvider     = embeddingProvider
        self.insightTreeService    = insightTreeService
        self.reconcilesPersistedSavedInsights = reconcilesPersistedSavedInsights
        self.selectionRequest      = selectionRequest
        self.persistedTreeRefreshRequest = persistedTreeRefreshRequest
        self.clearSelectionRequest = clearSelectionRequest
        self.dismissHoverRequest   = dismissHoverRequest
        self.createConceptRequest  = createConceptRequest
        self.studyRequest          = studyRequest
        self.studyExitRequest      = studyExitRequest
        self.studyToolsToggleRequest = studyToolsToggleRequest
        self.onStudyToolsActiveChange = onStudyToolsActiveChange
        self.studyBranchCount      = studyBranchCount
        self.onStudyModeChange     = onStudyModeChange
        self.onStudyBranchCountChange = onStudyBranchCountChange
        self.restoreSelectedInsightID = restoreSelectedInsightID
        self.restoreSelectedNodeID = restoreSelectedNodeID
        self.nodeSelectionRequest  = nodeSelectionRequest
        self.promotedInsightIDs    = promotedInsightIDs
        self.onClose               = onClose
        self.onRemoveInsight       = onRemoveInsight
        self.onRestoreInsight      = onRestoreInsight
        self.onForkInsight         = onForkInsight
        self.onQuoteInsight        = onQuoteInsight
        self.onSelectionStateChange = onSelectionStateChange
        self.onInsightSelectionStateChange = onInsightSelectionStateChange
        self.onSelectedCanvasItemCountChange = onSelectedCanvasItemCountChange
        self.onPromotedInsightIDsChange    = onPromotedInsightIDsChange
        self.savedConceptIDs               = savedConceptIDs
        self.onToggleSavedConcept          = onToggleSavedConcept
        self.onBookmarkConcepts            = onBookmarkConcepts
        self.inquireConnectionRequest      = inquireConnectionRequest
        self.onInquireConnectionConcepts   = onInquireConnectionConcepts
        self.midpointEnterRequest          = midpointEnterRequest
        self.midpointCenterRequest         = midpointCenterRequest
        self.midpointPlaceRequest          = midpointPlaceRequest
        self.searchQuery                   = searchQuery
        self.searchPreviousRequest         = searchPreviousRequest
        self.searchNextRequest             = searchNextRequest
        self.onSearchResultsChange         = onSearchResultsChange
        self.highlightedInsightPair        = highlightedInsightPair
        self.highlightPairRequest          = highlightPairRequest
        self.startsMidpointForHighlightedPair = startsMidpointForHighlightedPair
        self.onMidpointModeChange          = onMidpointModeChange
        self.onMidpointGeneratingChange    = onMidpointGeneratingChange
        self.onUndiscoveredInsightCountChange = onUndiscoveredInsightCountChange
        self.onPersistedTreeRefreshCompleted = onPersistedTreeRefreshCompleted
        self.inputFont             = inputFont
        self.conversationFontSize  = conversationFontSize
        self.showQuestionBar       = showQuestionBar
        self.modelTasks            = modelTasks
        self.modelTaskOriginPage   = modelTaskOriginPage
        // A synchronous UserDefaults read, not something that needs to wait for the async
        // `.task`-driven load — passing it in at construction avoids a guaranteed blank-then-
        // populated flash on every tree open (the view model otherwise builds its first tree
        // with zero anchors, then rebuilds moments later once `setLocalSeedAnchors` runs).
        let initialLocalSeedAnchors = conversationID.map(LocalInsightTreeSeedStore.seeds(for:)) ?? []
        _viewModel = StateObject(wrappedValue: InsightTreeViewModel(
            insights: insights,
            promotedInsightIDs: promotedInsightIDs,
            showsAllClusterInsights: conversationID == nil,
            model: model,
            embeddingProvider: embeddingProvider,
            localSeedAnchors: initialLocalSeedAnchors,
            midpointStoreScope: conversationID
        ))
    }

    private var canvasTertiary: Color {
        colorScheme == .dark
            ? Color(hex: 0x130F0C)
            : Color(red: 32/255, green: 28/255, blue: 24/255)   // #201C18
    }

    @ViewBuilder
    private var undoButtonView: some View {
        Button {
            guard let concept = undoInsight else { return }
            undoTask?.cancel()
            onRestoreInsight?(concept)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                undoInsight = nil
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Text("Undo")
                    .font(.custom("Figtree-Bold", size: 16))
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(canvasTertiary)
            .cornerRadius(12)
            .shadow(color: canvasTertiary.opacity(0.2), radius: 8, x: 0, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .inset(by: 0.5)
                    .stroke(canvasTertiary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        treeAlerts(treeRequestObservers(treeScreen))
    }

    /// The tree, its overlays, and the docked bottom area. The observers and alerts are split
    /// out so `body`'s modifier chain stays within the type checker's limits on older toolchains.
    private var treeScreen: some View {
        GeometryReader { geometry in
            let treePaneWidth = usesLandscapeSplitLayout ? geometry.size.width / 2 : geometry.size.width
            ZStack(alignment: .leading) {
                if usesLandscapeSplitLayout {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: treePaneWidth)

                        AquinasTheme.Colors.canvas
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(AquinasTheme.Colors.quietBorder)
                                    .frame(width: 1)
                            }
                    }
                    .ignoresSafeArea()
                }

            InsightTreeCanvasView(
                nodes: viewModel.nodes,
                edges: viewModel.edges,
                restoreFocusedCameraRequest: restoreFocusedCameraRequest,
                focusedInsightID: focusedInsightID,
                focusedSearchNodeID: focusedNodeID,
                pulsingInsightID: questionBarContextInsight?.id,
                pulsingNodeID: selectedNode?.id,
                selectedCanvasTargets: selectedCanvasTargets,
                selectionPulseRequest: selectionPulseRequest,
                makeNodeChildIDs: viewModel.makeNodeChildIDs,
                generatedMakeNodeChildIDs: viewModel.generatedMakeNodeChildIDs,
                placedMidpointNodeIDs: viewModel.placedMidpointNodeIDs,
                placedMidpointSources: viewModel.placedMidpointSources,
                insightBondLengths: viewModel.insightBondLengths,
                layoutTargets: viewModel.layoutTargets,
                nodeDepths: viewModel.nodeDepths,
                showsAllClusterInsights: conversationID == nil,
                defersEntranceUntilPersistedTree: conversationID != nil,
                persistedTreePresentationRevision: persistedTreePresentationRevision,
                animatedPersistedTreePresentationRevision:
                    animatedPersistedTreePresentationRevision,
                isHoveringTarget: selectedInsight != nil || selectedNode != nil || hoveredConcept != nil,
                isMidpointMode: isMidpointMode,
                midpointCenterRequest: midpointCenterRequest,
                midpointPlaceRequest: midpointPlaceRequest,
                midpointTargetIndex: midpointTargetIndex,
                midpointTargetWeight: midpointTargetWeight,
                midpointPercentRequest: midpointPercentRequest,
                onMidpointWeightsChange: { midpointWeights = $0 },
                onNodeTapped: { node in
                    showNodeCard(node)
                },
                onInsightTapped: { insight in
                    showInsightCard(insight)
                },
                onCanvasMoved: {
                    dismissDockedInsight()
                },
                onSuggestConnection: { edge in
                    viewModel.suggestConnection(for: edge)
                },
                onDismissSuggestedNode: { node in
                    viewModel.dismissSuggestedNode(node)
                },
                onMidpointPlaced: { worldPosition, nearestTarget, weights in
                    placeMidpointInsight(at: worldPosition, nearestTarget: nearestTarget, weights: weights)
                },
                midpointPlacedInsightID: midpointPlacedInsightID,
                midpointGeneratedInsightID: midpointGeneratedInsightID,
                onMidpointInsightLoaded: { insightID in
                    revealPlacedMidpointCard(insightID)
                },
                onGeneratingChange: { generating in
                    onMidpointGeneratingChange?(generating)
                    // Once every child has been revealed, unlock the parent card (its Insight
                    // links remain until the user dismisses or navigates away).
                    if !generating { makeNodeGenerating = false }
                },
                onMakeNodeChildRevealed: { childID in
                    appendMakeNodeChildLink(childID)
                },
                onPositionsSettled: { positions in
                    viewModel.commitLivePositions(positions)
                },
                onRequestDismissHover: {
                    // Keep the parent card up while its Make Node children generate — it's
                    // growing an Insight link per child.
                    guard !makeNodeGenerating else { return }
                    dismissDockedInsight()
                },
                onUndiscoveredInsightCountChange: { count in
                    onUndiscoveredInsightCountChange?(count)
                },
                studyNodeID: studiedNodeID,
                studyInitialHoverInsightID: studyInitialHoverID,
                studySelectionIDs: studiedSelectionIDs,
                studySlot: studySlotInStack?.offsetBy(dx: -canvasOriginInStack.x, dy: -canvasOriginInStack.y),
                studyToolRequestTool: studyTool,
                studyToolsActive: showsStudyToolCard,
                studyToolBranchCount: 3
            )
            .frame(width: treePaneWidth, height: geometry.size.height, alignment: .leading)
            .background(insightTreeCanvasColor)
            .onGeometryChange(for: CGPoint.self) { proxy in
                proxy.frame(in: .named(InsightTreeStackSpace.name)).origin
            } action: { origin in
                canvasOriginInStack = origin
            }
            // A studied Node Concept stays in the canvas, which handles Study's gestures.
            .allowsHitTesting(studySubject == nil || studiedNodeID != nil)

            if viewModel.nodes.isEmpty {
                EmptyInsightTreeView()
            }

            VStack {
                HStack {
                    if let onClose {
                        Button(action: { studySubject == nil ? onClose() : exitStudy() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .sfSymbolDrawOn()
                                .aquinasIconControl()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close insights")
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Spacer()
            }
            .zIndex(11)

            if let studySubject {
                StudyModeView(
                    subject: studySubject,
                    tool: studyTool,
                    branchCount: studyBranchCount,
                    isExiting: isExitingStudy,
                    animatesCenterIconEntrance: false,
                    onBranchCountChange: onStudyBranchCountChange ?? { _ in },
                    onNodeSlotChange: { studySlotInStack = $0 }
                )
                    .transition(.opacity)
                    .zIndex(10)
            }
            }
            // Shared by the canvas and the Study overlay so a Node Concept can leave the tree
            // from exactly where the canvas drew it.
            .coordinateSpace(.named(InsightTreeStackSpace.name))
        }
        // safeAreaInset moves with the keyboard automatically — no manual observation needed.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if undoInsight != nil {
                    undoButtonView
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                        .opacity(studySubject == nil ? 1 : 0)
                }

                if showsStudyToolCard {
                    StudyToolCard(
                        tool: studyTool,
                        transitionDirection: studyToolDirection,
                        onPrevious: { selectStudyTool(studyTool.previous, direction: -1) },
                        onNext: { selectStudyTool(studyTool.next, direction: 1) }
                    )
                    .offset(y: studyToolCardDragY)
                    .simultaneousGesture(studyToolCardDismissGesture)
                    .transition(.bottomDockCard)
                    .padding(.horizontal, 10)
                } else if isMidpointMode {
                    MidpointPercentCard(
                        concepts: selectedCanvasTargets.compactMap { concept(for: $0) },
                        weights: midpointWeights,
                        onSetPercent: { index, percent in
                            midpointTargetIndex = index
                            midpointTargetWeight = Double(percent) / 100.0
                            midpointPercentRequest += 1
                        }
                    )
                    .transition(.scale(scale: 0.35, anchor: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 10)
                } else if !cardShouldHide {
                    if !showQuestionBar, showsDockedCardAfterStudy, let concept = hoveredConcept {
                        DockedConceptCard(
                            concept: concept,
                            isSaved: savedConceptIDs.contains(concept.id),
                            onToggleSaved: { onToggleSavedConcept?(concept) },
                            onFork: {
                                dismissDockedInsight()
                                onForkInsight?(concept)
                            }
                        )
                        .id(concept.id)
                        .growsWhileTouched()
                        .offset(y: dockedCardDragY)
                        .gesture(dockedCardDismissGesture)
                        .transition(.bottomDockCard)
                        .padding(.horizontal, 10)
                    } else if showsDockedCardAfterStudy, let selectedInsight {
                        DockedInsightTreeCard(
                            insight: selectedInsight,
                            isSaved: savedConceptIDs.contains(selectedInsight.id),
                            animateIn: animateMidpointCardText,
                            linkedInsights: makeNodeLinkInsights,
                            onToggleSaved: {
                                onToggleSavedConcept?(concept(for: selectedInsight))
                            },
                            onRemove: { pendingRemoveInsight = selectedInsight },
                            onFork:   { performForkInsight(selectedInsight) },
                            onSelectLinkedInsight: { insight in
                                focusedInsightID = insight.id
                                showInsightCard(insight)
                            }
                        )
                        .id(selectedInsight.id)
                        .growsWhileTouched()
                        .offset(y: dockedCardDragY)
                        .gesture(dockedCardDismissGesture)
                        .transition(.bottomDockCard)
                        .padding(.horizontal, 10)
                    } else if showsDockedCardAfterStudy, let selectedNode {
                        let makeNodeSourceID = viewModel.promotedSourceInsightID(
                            forNodeID: selectedNode.id
                        )
                        DockedNodeTreeCard(
                            node: selectedNode,
                            isSaved: makeNodeSourceID.map(savedConceptIDs.contains) ?? false,
                            onSelectInsight: { insight in
                                focusedInsightID = insight.id
                                showInsightCard(insight)
                            },
                            onToggleSaved: makeNodeSourceID == nil ? nil : {
                                toggleMakeNodeBookmark(selectedNode)
                            },
                            onFork: { performForkNode(selectedNode) }
                        )
                        .id(selectedNode.id)
                        .growsWhileTouched()
                        .offset(y: dockedCardDragY)
                        .gesture(dockedCardDismissGesture)
                        .transition(.bottomDockCard)
                        .padding(.horizontal, 10)
                    }
                }

                // Insight chip — appears above the bar when keyboard is open, mirrors card dismiss animation
                if showQuestionBar, chipShouldShow, studySubject == nil, let insight = questionBarContextInsight {
                    BranchContextChip(
                        title: insight.title,
                        icon: "text.bubble.fill",
                        isFilled: true,
                        fillColor: AquinasTheme.Colors.canvasSecondary,
                        animatesAppearance: false,
                        showRemove: true,
                        onRemove: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                chipShouldShow = false
                                questionBarContextInsight = nil
                            }
                        }
                    )
                    .transition(.scale(scale: 0.35, anchor: .bottom).combined(with: .opacity))
                    // Swipe up → dismiss keyboard → card reappears
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                let isUpward = value.translation.height < -20
                                let isVertical = abs(value.translation.width) < abs(value.translation.height)
                                if isUpward && isVertical {
                                    UIApplication.shared.sendAction(
                                        #selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil
                                    )
                                }
                            }
                    )
                }

                if showQuestionBar {
                    InsightQuestionBar(
                        contextInsight: $questionBarContextInsight,
                        inputFont: inputFont,
                        conversationFontSize: conversationFontSize,
                        onOpen: {},
                        onKeyboardActiveChange: { active in
                            questionBarKeyboardActive = active
                            if active {
                                if let insight = selectedInsight {
                                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                        questionBarContextInsight = insight
                                    }
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    guard questionBarKeyboardActive else { return }
                                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                        cardShouldHide = true
                                        chipShouldShow = true
                                    }
                                }
                            } else {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                    chipShouldShow = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    guard !questionBarKeyboardActive else { return }
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                        cardShouldHide = false
                                    }
                                }
                            }
                        },
                        onCollapse: {
                            questionBarKeyboardActive = false
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                cardShouldHide = false
                                chipShouldShow = false
                            }
                        },
                        focusTrigger: questionBarFocusTrigger
                    )
                    .padding(.horizontal, 16)
                    .opacity(studySubject == nil ? 1 : 0)
                }
            }
            .padding(.bottom, 16)
            .frame(maxWidth: usesLandscapeSplitLayout ? 420 : .infinity)
            .frame(maxWidth: .infinity, alignment: usesLandscapeSplitLayout ? .trailing : .center)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedInsight?.id)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedNode?.id)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: hoveredConcept?.id)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isMidpointMode)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: undoInsight != nil)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showsStudyToolCard)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showsDockedCardAfterStudy)
        }
    }

    private func treeRequestObservers<Content: View>(_ content: Content) -> some View {
        treeNavigationObservers(treeContentObservers(content))
    }

    /// Insight, bookmark, and selection-request observers (half of `treeRequestObservers`,
    /// split again for Xcode 26.6's type checker).
    private func treeContentObservers<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: insights) { oldValue, newValue in
            viewModel.updateInsights(newValue, promotedInsightIDs: promotedInsightIDs)
            restoreRequestedInsightSelection()
            if let selectedInsight,
               !newValue.contains(where: { $0.id == selectedInsight.id }) {
                dismissDockedInsight()
            }
        }
        .onChange(of: promotedInsightIDs) { _, newValue in
            viewModel.updateInsights(insights, promotedInsightIDs: newValue)
        }
        // A placed Midpoint is auto-bookmarked and has nothing else anchoring it to the tree, so
        // un-saving it from ANY bookmark toggle — not just the docked card on this canvas — must
        // remove its node too. `savedConceptIDs` is fed by whatever saved-insights store the host
        // (global tree or a conversation) owns, so this reacts uniformly regardless of where the
        // un-save happened (e.g. the Insight Library popup, which mutates that store directly).
        //
        // Must only react to an actual save -> unsave transition (present in `oldValue`, gone
        // from `newValue`) rather than "just not currently saved" — a Midpoint's placeholder
        // node exists and is generating for a few seconds *before* it gets auto-bookmarked, so
        // it's legitimately absent from `savedConceptIDs` during that window. Reacting to mere
        // absence tore down still-generating placeholders out from under their own generation
        // task the moment anything else touched the saved-insights set.
        .onChange(of: savedConceptIDs) { oldValue, newValue in
            for placedID in viewModel.placedMidpointNodeIDs
            where oldValue.contains(placedID) && !newValue.contains(placedID) {
                viewModel.removePlacedMidpoint(id: placedID)
                if selectedInsight?.id == placedID {
                    dismissDockedInsight()
                }
            }
            for childID in viewModel.generatedMakeNodeChildIDs
            where oldValue.contains(childID) && !newValue.contains(childID) {
                viewModel.removeMakeNodeChild(id: childID)
                if selectedInsight?.id == childID {
                    dismissDockedInsight()
                }
            }
        }
        .onChange(of: selectionRequest) { _, _ in
            selectHoveredCanvasTarget()
        }
        .onChange(of: clearSelectionRequest) { _, _ in
            clearSelectedCanvasTargets()
        }
        .onChange(of: dismissHoverRequest) { _, _ in
            dismissDockedInsight()
        }
        .onChange(of: createConceptRequest) { _, _ in
            promoteHoveredInsightToConcept()
        }
        .onChange(of: studyRequest) { _, _ in
            enterStudy()
        }
        .onChange(of: studyToolsToggleRequest) { _, _ in
            guard studySubject != nil, !isExitingStudy else { return }
            setStudyToolsOpen(!showsStudyToolCard)
        }
        .onChange(of: showsStudyToolCard) { _, isOpen in
            onStudyToolsActiveChange?(isOpen)
        }
        .onChange(of: studyExitRequest) { _, _ in
            guard studySubject != nil else { return }
            exitStudy()
        }
        .onChange(of: restoreSelectedInsightID) { _, _ in
            restoreRequestedInsightSelection()
        }
        .onChange(of: nodeSelectionRequest) { _, _ in
            restoreRequestedNodeSelection()
        }
    }

    /// Search, persistence, and lifecycle observers (the other half).
    private func treeNavigationObservers<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: inquireConnectionRequest) { _, _ in
            performInquireConnection()
        }
        .onChange(of: midpointEnterRequest) { _, _ in
            enterMidpointMode()
        }
        .onChange(of: searchQuery) { _, _ in
            refreshSearchResults(resetIndex: true)
        }
        .onChange(of: searchPreviousRequest) { _, _ in
            stepSearchResult(by: -1)
        }
        .onChange(of: searchNextRequest) { _, _ in
            stepSearchResult(by: 1)
        }
        .onChange(of: persistedTreePresentationRevision) { _, _ in
            guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            refreshSearchResults(resetIndex: false)
        }
        .onChange(of: highlightPairRequest) { _, _ in
            highlightInsightPair()
        }
        .onAppear {
            if highlightedInsightPair != nil {
                highlightInsightPair()
            }
            restoreRequestedInsightSelection()
            restoreRequestedNodeSelection()
        }
        .task(id: conversationID) {
            enqueuePersistedTreeLoad(animateChanges: false)
        }
        .onChange(of: persistedTreeRefreshRequest) { _, _ in
            enqueuePersistedTreeLoad(animateChanges: true)
        }
        .onDisappear {
            midpointGenerationTask?.cancel()
            if midpointPlacedInsightID != nil {
                onMidpointGeneratingChange?(false)
            }
        }
    }

    private func treeAlerts<Content: View>(_ content: Content) -> some View {
        content
        .alert("Remove from conversation?", isPresented: Binding(
            get: { pendingRemoveInsight != nil },
            set: { if !$0 { pendingRemoveInsight = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let insight = pendingRemoveInsight {
                    performRemoveInsight(insight)
                }
                pendingRemoveInsight = nil
            }
        } message: {
            Text("This insight will be removed from this conversation’s tree. Its global bookmark is unchanged.")
        }
        .alert("Unbookmark attached Insights?", isPresented: Binding(
            get: { pendingUnbookmarkMakeNode != nil },
            set: { if !$0 { pendingUnbookmarkMakeNode = nil } }
        )) {
            Button("No") {
                resolveMakeNodeUnbookmark(removingAttachedInsights: false)
            }
            Button("Yes", role: .destructive) {
                resolveMakeNodeUnbookmark(removingAttachedInsights: true)
            }
        } message: {
            Text("Would you also like to unbookmark the Insights attached to this node?")
        }
        .alert(
            "Couldn’t complete that model action",
            isPresented: $isModelActionErrorPresented
        ) {
            Button("Cancel", role: .cancel) {
                pendingModelActionRetry = nil
            }
            Button("Try Again") {
                let retry = pendingModelActionRetry
                pendingModelActionRetry = nil
                retry?()
            }
        } message: {
            Text("The Insight Tree was left unchanged. Check that the Aquinas backend is available and try again.")
        }
        .sheet(item: $viewModel.selectedSuggestedNode) { node in
            SuggestedInsightSheet(node: node) {
                viewModel.dismissSuggestedNode(node)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
        }
    }

    private func restoreRequestedInsightSelection() {
        guard let restoreSelectedInsightID,
              selectedInsight?.id != restoreSelectedInsightID,
              let insight = viewModel.nodes
                .lazy
                .flatMap(\.insights)
                .first(where: { $0.id == restoreSelectedInsightID }) else {
            return
        }
        showInsightCard(insight)
    }

    private func restoreRequestedNodeSelection() {
        guard let restoreSelectedNodeID,
              let node = viewModel.nodes.first(where: { $0.id == restoreSelectedNodeID }) else {
            return
        }
        showNodeCard(node)
        if let firstInsight = node.insights.first {
            focusedInsightID = firstInsight.id
        }
    }

    private func showInsightCard(_ insight: InsightModel, animateText: Bool = false, moveCamera: Bool = true) {
        // Navigating to any other insight ends the Make Node card growth.
        if insight.id != makeNodeParentInsightID { clearMakeNodeCardGrowth() }
        animateMidpointCardText = animateText
        // Keyboard is open — update the chip and ensure it's visible
        if questionBarKeyboardActive {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                questionBarContextInsight = insight
                chipShouldShow = true
            }
            return
        }

        playDockedCardHaptic()
        onSelectionStateChange?(true)
        onInsightSelectionStateChange?(true)
        // The placed-midpoint reveal lets the canvas own the camera (so user input can cancel
        // it); other taps recenter on the insight as usual.
        if moveCamera {
            focusedInsightID = insight.id
        }
        onQuoteInsight?(concept(for: insight))

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            dockedCardDragY = 0
            selectedNode = nil
            selectedInsight = insight
            hoveredConcept = showQuestionBar ? nil : concept(for: insight)
            questionBarContextInsight = insight
        }
    }

    private var studyTool: StudyTool {
        StudyTool(rawValue: studyToolRawValue) ?? .branch
    }

    private func selectStudyTool(_ tool: StudyTool, direction: Int) {
        guard tool != studyTool else { return }
        studyToolDirection = direction
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            studyToolRawValue = tool.rawValue
        }
    }

    /// The Node Concept being studied, until its exit begins, so the canvas shifts back in
    /// time for the tree to be whole when Study closes.
    private var studiedNodeID: UUID? {
        guard !isExitingStudy, case .node(let node, _) = studySubject else { return nil }
        return node.id
    }

    /// Selected Insights being studied together, until the exit begins (like `studiedNodeID`).
    private var studiedSelectionIDs: [UUID]? {
        guard !isExitingStudy, case .selection(let insights) = studySubject else { return nil }
        return insights.map(\.id)
    }

    /// The Insight a node Study opens hovered, if Study was pressed on one.
    private var studyInitialHoverID: UUID? {
        guard case .node(_, let insightID) = studySubject else { return nil }
        return insightID
    }

    private func enterStudy() {
        // The dock offers Study again as soon as an exit starts; wait for the exit to finish.
        guard !isMidpointMode, !isExitingStudy else { return }
        let subject: StudySubject
        if !selectedCanvasTargets.isEmpty {
            // Study on a selection studies just its Insights. The selection stays, so leaving
            // Study returns to it (ready to Midpoint).
            let insights = selectedCanvasTargets.compactMap { target -> InsightModel? in
                guard case .insight(let id) = target else { return nil }
                return viewModel.nodes.lazy.flatMap(\.insights).first { $0.id == id }
            }
            guard !insights.isEmpty else { return }
            subject = .selection(insights)
        } else if let selectedInsight {
            // Study on an Insight opens its Node Concept with the Insight hovered. The dot
            // matrix Study remains for Insights without an ordinary parent (placed midpoints).
            if let parent = viewModel.nodes.first(where: { node in
                !viewModel.placedMidpointNodeIDs.contains(node.id)
                    && node.insights.contains { $0.id == selectedInsight.id }
            }) {
                subject = .node(parent, hoveredInsightID: selectedInsight.id)
            } else {
                subject = .insight(selectedInsight)
            }
        } else if let selectedNode {
            subject = .node(selectedNode)
        } else {
            return
        }
        isExitingStudy = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.72)
        // The hovered Insight's card stays up; the tools open from the dock's Tools button.
        withAnimation(.easeOut(duration: 0.3)) {
            studySubject = subject
        }
        setStudyToolsOpen(false)
        onStudyModeChange?(true)
    }

    private func exitStudy() {
        guard studySubject != nil, !isExitingStudy else { return }
        withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
            isExitingStudy = true
        }
        // Tell the host now, so the dock and Exit change back while the camera moves.
        onStudyModeChange?(false)
        // Leaving a selection's Study returns to the selection itself, not an Insight hovered
        // in Study, so the dock offers the selection's actions (Midpoint) again.
        if case .selection = studySubject { dismissDockedInsight() }
        setStudyToolsOpen(false)
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                showsDockedCardAfterStudy = true
            }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                studySubject = nil
                isExitingStudy = false
            }
        }
    }

    private func showNodeCard(_ node: NodeModel) {
        clearMakeNodeCardGrowth()
        playDockedCardHaptic()
        onSelectionStateChange?(true)
        onInsightSelectionStateChange?(false)
        onQuoteInsight?(quoteTarget(for: node))

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = node
            hoveredConcept = showQuestionBar ? nil : quoteTarget(for: node)
            questionBarContextInsight = nil
        }
    }

    private func setStudyToolsOpen(_ isOpen: Bool) {
        studyToolCardDragY = 0
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            showsStudyToolCard = isOpen
        }
    }

    /// Swiping the tool card down closes the tools, like swiping an Insight card away.
    private var studyToolCardDismissGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Horizontal swipes page between tools.
                guard value.translation.height > abs(value.translation.width) || studyToolCardDragY > 0 else { return }
                studyToolCardDragY = max(0, value.translation.height)
            }
            .onEnded { value in
                guard studyToolCardDragY > 0 else { return }
                if value.translation.height > 100 || value.predictedEndTranslation.height > 180 {
                    setStudyToolsOpen(false)
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        studyToolCardDragY = 0
                    }
                }
            }
    }

    private var dockedCardDismissGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dockedCardDragY = max(0, value.translation.height)
            }
            .onEnded { value in
                let h = value.translation.height
                let predicted = value.predictedEndTranslation.height
                if h > 100 || predicted > 180 {
                    // Large swipe → full dismiss
                    dismissDockedInsight()
                } else if h > 28 {
                    // Small swipe down → collapse to chip (focus question bar)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        dockedCardDragY = 0
                    }
                    questionBarFocusTrigger += 1
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        dockedCardDragY = 0
                    }
                }
            }
    }

    private func performRemoveInsight(_ insight: InsightModel) {
        let concept = concept(for: insight)
        onRemoveInsight?(concept)   // triggers onChange → dismissDockedInsight
        undoTask?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            undoInsight = concept
        }
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                undoInsight = nil
            }
        }
    }

    private func performForkInsight(_ insight: InsightModel) {
        guard let concept = insights.first(where: { $0.id == insight.id }) else { return }
        dismissDockedInsight()
        onForkInsight?(concept)
    }

    /// Branches a new inquiry from a node concept. Prefers a member insight's saved concept, else
    /// synthesizes one from the node's own label + definition.
    private func performForkNode(_ node: NodeModel) {
        let concept = node.insights.compactMap { insight in insights.first(where: { $0.id == insight.id }) }.first
            ?? ConceptDefinition(
                word: node.conceptLabel,
                partOfSpeech: "",
                pronunciation: "",
                meaning: node.definition,
                example: ""
            )
        dismissDockedInsight()
        onForkInsight?(concept)
    }

    private func dismissDockedInsight() {
        guard selectedInsight != nil || selectedNode != nil || hoveredConcept != nil else { return }

        clearMakeNodeCardGrowth()
        playDockedCardHaptic()
        onSelectionStateChange?(false)
        onInsightSelectionStateChange?(false)
        onQuoteInsight?(nil)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = nil
            hoveredConcept = nil
            questionBarContextInsight = nil
        }
    }

    // Dismisses the docked card without clearing the question bar chip.
    // Called when the question bar keyboard opens so the card slides away
    // but the quoted insight remains available in the bar.
    private func dismissDockedCard() {
        guard selectedInsight != nil || selectedNode != nil || hoveredConcept != nil else { return }

        clearMakeNodeCardGrowth()
        playDockedCardHaptic()
        onSelectionStateChange?(false)
        onInsightSelectionStateChange?(false)
        onQuoteInsight?(nil)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = nil
            hoveredConcept = nil
        }
    }

    private func clearCanvasSelectionSilently() {
        guard selectedInsight != nil || selectedNode != nil || questionBarContextInsight != nil || hoveredConcept != nil else { return }

        clearMakeNodeCardGrowth()
        onSelectionStateChange?(false)
        onInsightSelectionStateChange?(false)
        onQuoteInsight?(nil)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = nil
            hoveredConcept = nil
            questionBarContextInsight = nil
        }
    }

    private func clearSelectedCanvasTargets() {
        guard !selectedCanvasTargets.isEmpty else {
            if isMidpointMode { exitMidpointMode() }
            return
        }
        let firstTarget = selectedCanvasTargets[0]
        if isMidpointMode { exitMidpointMode() }
        selectedCanvasTargets.removeAll()
        onSelectedCanvasItemCountChange?(0)
        rehoverTarget(firstTarget)
    }

    private func rehoverTarget(_ target: CanvasSelectionTarget) {
        // Clear the focus id first, then re-hover on the next runloop. Canceling a selection
        // often re-targets the insight that's *already* focused (e.g. a single-item selection),
        // and the canvas only re-centers on a genuine focusedInsightID change — so without the
        // nil→id transition the camera wouldn't return to hovering the first selected item.
        focusedInsightID = nil
        DispatchQueue.main.async {
            switch target {
            case .insight(let id):
                guard let insight = viewModel.nodes.flatMap(\.insights).first(where: { $0.id == id }) else { return }
                showInsightCard(insight)
            case .node(let id):
                guard let node = viewModel.nodes.first(where: { $0.id == id }) else { return }
                showNodeCard(node)
                if let firstInsight = node.insights.first {
                    focusedInsightID = firstInsight.id
                }
            }
        }
    }

    private func refreshSearchResults(resetIndex: Bool) {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            let hadResults = !searchResults.isEmpty
            searchResults = []
            searchResultIndex = 0
            focusedInsightID = nil
            focusedNodeID = nil
            onSearchResultsChange?(0, 0)
            if hadResults {
                restoreFocusedCameraRequest += 1
            }
            return
        }

        let rankedInsights = viewModel.nodes
            .flatMap(\.insights)
            .compactMap { insight -> (target: CanvasSelectionTarget, title: String, score: Double)? in
                guard let score = searchScore(query: query, title: insight.title) else {
                    return nil
                }
                return (.insight(insight.id), insight.title, score)
            }

        let rankedNodes = viewModel.nodes.compactMap {
            node -> (target: CanvasSelectionTarget, title: String, score: Double)? in
            guard !viewModel.placedMidpointNodeIDs.contains(node.id),
                  let score = searchScore(
                    query: query,
                    title: node.conceptLabel
                  ) else {
                return nil
            }
            return (.node(node.id), node.conceptLabel, score)
        }

        let ranked = (rankedInsights + rankedNodes)
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

        let previousResult = searchResults.indices.contains(searchResultIndex)
            ? searchResults[searchResultIndex]
            : nil
        searchResults = ranked.map(\.target)
        if resetIndex {
            searchResultIndex = 0
        } else if let previousResult,
                  let retainedIndex = searchResults.firstIndex(of: previousResult) {
            searchResultIndex = retainedIndex
        } else {
            searchResultIndex = min(searchResultIndex, max(searchResults.count - 1, 0))
        }
        focusCurrentSearchResult()
    }

    private func stepSearchResult(by offset: Int) {
        guard !searchResults.isEmpty else { return }
        searchResultIndex =
            (searchResultIndex + offset + searchResults.count)
            % searchResults.count
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
        focusCurrentSearchResult()
    }

    private func focusCurrentSearchResult() {
        guard searchResults.indices.contains(searchResultIndex) else {
            focusedInsightID = nil
            focusedNodeID = nil
            onSearchResultsChange?(0, 0)
            return
        }
        let result = searchResults[searchResultIndex]
        onSearchResultsChange?(searchResultIndex + 1, searchResults.count)

        switch result {
        case .insight(let insightID):
            focusedNodeID = nil
            if focusedInsightID == insightID {
                focusedInsightID = nil
                DispatchQueue.main.async {
                    focusedInsightID = insightID
                }
            } else {
                focusedInsightID = insightID
            }

        case .node(let nodeID):
            focusedInsightID = nil
            if focusedNodeID == nodeID {
                focusedNodeID = nil
                DispatchQueue.main.async {
                    focusedNodeID = nodeID
                }
            } else {
                focusedNodeID = nodeID
            }
        }
    }

    private func searchScore(query: String, title: String) -> Double? {
        let needle = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let haystack = title.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        guard !needle.isEmpty else { return nil }

        if haystack == needle { return 10_000 }
        if haystack.hasPrefix(needle) {
            return 8_000 - Double(haystack.count - needle.count)
        }
        if let range = haystack.range(of: needle) {
            return 6_000 - Double(haystack.distance(from: haystack.startIndex, to: range.lowerBound))
        }

        let queryTokens = needle.split(whereSeparator: \.isWhitespace)
        if !queryTokens.isEmpty, queryTokens.allSatisfy({ haystack.contains($0) }) {
            return 4_000 + Double(queryTokens.count * 10)
        }

        let similarity = normalizedEditSimilarity(needle, haystack)
        guard similarity >= 0.45 else { return nil }
        return similarity * 1_000
    }

    private func normalizedEditSimilarity(_ left: String, _ right: String) -> Double {
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)
        guard !leftCharacters.isEmpty || !rightCharacters.isEmpty else { return 1 }

        var previous = Array(0...rightCharacters.count)
        for (leftIndex, leftCharacter) in leftCharacters.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in rightCharacters.enumerated() {
                current.append(
                    min(
                        current[rightIndex] + 1,
                        previous[rightIndex + 1] + 1,
                        previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                    )
                )
            }
            previous = current
        }
        let distance = previous[rightCharacters.count]
        return 1 - (Double(distance) / Double(max(leftCharacters.count, rightCharacters.count)))
    }

    private func playDockedCardHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.65)
    }

    private func playSelectionHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            generator.impactOccurred(intensity: 0.8)
        }
    }

    private func selectHoveredCanvasTarget() {
        guard selectedCanvasTargets.count < CanvasSelectionPolicy.maximumCount else { return }

        let target: CanvasSelectionTarget?
        if let selectedInsight {
            target = .insight(selectedInsight.id)
        } else if let selectedNode {
            target = .node(selectedNode.id)
        } else {
            target = nil
        }

        guard let target else { return }

        guard !selectedCanvasTargets.contains(target) else { return }

        selectedCanvasTargets.append(target)
        playSelectionHaptic()
        if selectedCanvasTargets.count > 1 {
            selectionPulseRequest += 1
        }
        onSelectedCanvasItemCountChange?(selectedCanvasTargets.count)
        // Clear the hover so the dock immediately reflects the selection state
        // (e.g. shows the "Tap another Insight" hint) instead of waiting for a tap/drag.
        clearCanvasSelectionSilently()
    }

    private func highlightInsightPair() {
        guard let highlightedInsightPair else { return }
        let firstTarget = CanvasSelectionTarget.insight(highlightedInsightPair.0)
        let secondTarget = CanvasSelectionTarget.insight(highlightedInsightPair.1)
        let availableInsightIDs = Set(viewModel.nodes.flatMap(\.insights).map(\.id))
        guard availableInsightIDs.contains(highlightedInsightPair.0),
              availableInsightIDs.contains(highlightedInsightPair.1) else {
            return
        }

        if isMidpointMode { exitMidpointMode() }
        dismissDockedInsight()
        selectedCanvasTargets = [firstTarget, secondTarget]
        selectionPulseRequest += 1
        onSelectedCanvasItemCountChange?(selectedCanvasTargets.count)
        focusedInsightID = nil
        DispatchQueue.main.async {
            focusedInsightID = highlightedInsightPair.1
            if startsMidpointForHighlightedPair {
                enterMidpointMode()
            }
        }
    }

    private func promoteHoveredInsightToConcept() {
        guard let selectedInsight else { return }
        guard !promotedInsightIDs.contains(selectedInsight.id) else { return }

        let insightID = selectedInsight.id
        let beginGeneration = {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
            // Keep this insight's card docked while its children generate; it grows an Insight
            // link per child, each appended in sync with the child's reveal haptic.
            makeNodeParentInsightID = insightID
            makeNodeLinkInsightIDs = []
            makeNodeGenerating = true
            viewModel.reserveMakeNodeGeneration(for: insightID)
            onPromotedInsightIDsChange?(promotedInsightIDs + [insightID])
        }
        let cancelGeneration = {
            viewModel.cancelMakeNodeGeneration(for: insightID)
            onPromotedInsightIDsChange?(
                promotedInsightIDs.filter { $0 != insightID }
            )
            if makeNodeParentInsightID == insightID {
                clearMakeNodeCardGrowth()
                onMidpointGeneratingChange?(false)
            }
        }

        guard let modelTasks else {
            beginGeneration()
            Task {
                do {
                    try await viewModel.generateReservedMakeNodeChildren(
                        for: selectedInsight
                    )
                    bookmarkMakeNodeOutput(for: insightID)
                } catch {
                    guard !Task.isCancelled else { return }
                    cancelGeneration()
                    presentModelActionError {
                        promoteHoveredInsightToConcept()
                    }
                }
            }
            return
        }

        modelTasks.enqueue(
            kind: .makeNode,
            originPage: modelTaskOriginPage,
            onStart: beginGeneration,
            onCancel: cancelGeneration
        ) {
            do {
                try await viewModel.generateReservedMakeNodeChildren(
                    for: selectedInsight
                )
                bookmarkMakeNodeOutput(for: insightID)
            } catch {
                guard !Task.isCancelled else { return }
                cancelGeneration()
                presentModelActionError {
                    promoteHoveredInsightToConcept()
                }
            }
        }
    }

    private func bookmarkMakeNodeOutput(for insightID: UUID) {
        let concepts = viewModel.makeNodeBookmarkConcepts(for: insightID)
        guard !concepts.isEmpty else { return }
        if let onBookmarkConcepts {
            onBookmarkConcepts(concepts)
        } else {
            for concept in concepts where !savedConceptIDs.contains(concept.id) {
                onToggleSavedConcept?(concept)
            }
        }
    }

    private func toggleMakeNodeBookmark(_ node: NodeModel) {
        guard let sourceID = viewModel.promotedSourceInsightID(forNodeID: node.id),
              let nodeConcept = viewModel.makeNodeBookmarkConcepts(for: sourceID).first else {
            return
        }
        if savedConceptIDs.contains(sourceID) {
            pendingUnbookmarkMakeNode = node
        } else if let onBookmarkConcepts {
            onBookmarkConcepts([nodeConcept])
        } else {
            onToggleSavedConcept?(nodeConcept)
        }
    }

    private func resolveMakeNodeUnbookmark(removingAttachedInsights: Bool) {
        guard let node = pendingUnbookmarkMakeNode,
              let sourceID = viewModel.promotedSourceInsightID(forNodeID: node.id) else {
            pendingUnbookmarkMakeNode = nil
            return
        }
        let bookmarks = viewModel.makeNodeBookmarkConcepts(for: sourceID)
        viewModel.removeMakeNode(
            for: sourceID,
            keepingChildren: !removingAttachedInsights
        )
        onPromotedInsightIDsChange?(promotedInsightIDs.filter { $0 != sourceID })

        let conceptsToRemove = removingAttachedInsights ? bookmarks : Array(bookmarks.prefix(1))
        for concept in conceptsToRemove where savedConceptIDs.contains(concept.id) {
            onToggleSavedConcept?(concept)
        }
        pendingUnbookmarkMakeNode = nil
        dismissDockedInsight()
    }

    private func presentModelActionError(retry: @escaping () -> Void) {
        pendingModelActionRetry = retry
        isModelActionErrorPresented = true
    }

    /// Called by the canvas as each Make Node child is revealed (on its haptic). Appends an
    /// Insight link for it to the docked parent card, animated in with the reveal.
    private func appendMakeNodeChildLink(_ childID: UUID) {
        guard let parentID = makeNodeParentInsightID,
              selectedInsight?.id == parentID,
              !makeNodeLinkInsightIDs.contains(childID) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            makeNodeLinkInsightIDs.append(childID)
        }
    }

    /// Resolved child insights for the links currently growing on the docked parent card.
    private var makeNodeLinkInsights: [InsightModel] {
        guard selectedInsight?.id == makeNodeParentInsightID else { return [] }
        let all = viewModel.nodes.flatMap(\.insights)
        return makeNodeLinkInsightIDs.compactMap { id in all.first(where: { $0.id == id }) }
    }

    private func clearMakeNodeCardGrowth() {
        makeNodeParentInsightID = nil
        makeNodeLinkInsightIDs = []
        makeNodeGenerating = false
    }

    private func performInquireConnection() {
        guard selectedCanvasTargets.count >= 2 else { return }
        let concepts = selectedCanvasTargets.compactMap { concept(for: $0) }
        guard concepts.count == selectedCanvasTargets.count else { return }
        clearSelectedCanvasTargets()
        dismissDockedInsight()
        onInquireConnectionConcepts?(concepts)
    }

    // MARK: - Midpoint Mode

    private func enterMidpointMode() {
        guard !showQuestionBar else { return }
        guard selectedCanvasTargets.count >= 2 else { return }
        dismissDockedInsight()
        isMidpointMode = true
        onMidpointModeChange?(true)
    }

    private func exitMidpointMode() {
        guard isMidpointMode else { return }
        isMidpointMode = false
        onMidpointModeChange?(false)
    }

    /// Commits the placed midpoint immediately so the loading icon can appear at the chosen
    /// position, then generates and swaps in its real content without changing its identity.
    private func placeMidpointInsight(at worldPosition: CGPoint, nearestTarget: CanvasSelectionTarget, weights: [Double]) {
        let sourceTargets = selectedCanvasTargets
        // `self.` because a local `concept` later in this function shadows the method on
        // older Swift toolchains.
        let sourceConcepts = sourceTargets.compactMap { self.concept(for: $0) }
        guard sourceConcepts.count >= 2, sourceConcepts.count == weights.count else { return }
        let cachedSourceEmbeddings = sourceTargets.map { cachedEmbedding(for: $0) }
        // Connect the placed midpoint to every source it was spawned from — to the insight chip
        // for a selected insight, or the node center for a selected node concept.
        let sources: [MidpointSource] = selectedCanvasTargets.compactMap { target in
            guard let id = insightID(for: target) else { return nil }
            if case .node = target { return MidpointSource(insightID: id, isNode: true) }
            return MidpointSource(insightID: id, isNode: false)
        }
        let concept = makeMidpointLoadingConcept()

        // The placed node and its single insight both share the concept id.
        midpointPlacedInsightID = concept.id
        midpointGeneratedInsightID = nil
        onMidpointGeneratingChange?(true)
        viewModel.addPlacedMidpoint(concept: concept, at: worldPosition, sources: sources)

        exitMidpointMode()
        selectedCanvasTargets.removeAll()
        onSelectedCanvasItemCountChange?(0)

        let placedID = concept.id
        midpointGenerationTask?.cancel()
        let generateMidpoint = {
            do {
                let generated = try await requestMidpointDefinition(
                    weights: weights,
                    targets: sourceConcepts,
                    cachedSourceEmbeddings: cachedSourceEmbeddings
                )
                guard !Task.isCancelled, midpointPlacedInsightID == placedID else { return }
                viewModel.replacePlacedMidpoint(id: placedID, with: generated)
                midpointGeneratedInsightID = placedID
                // Midpoint blends aren't the user's own saved research — they're synthesized on
                // the spot from sources the user already selected, so save it automatically
                // rather than making them separately hunt down and bookmark their own creation.
                // `onToggleSavedConcept` only adds (this id can't already be saved — it's fresh),
                // so this is the easy "unbookmark to get rid of it" the user asked for: the normal
                // save toggle already removes it from the tree like any other bookmark.
                if !savedConceptIDs.contains(placedID) {
                    onToggleSavedConcept?(
                        ConceptDefinition(
                            id: placedID,
                            word: generated.word,
                            partOfSpeech: generated.partOfSpeech,
                            pronunciation: generated.pronunciation,
                            meaning: generated.meaning,
                            example: generated.example
                        )
                    )
                }
            } catch {
                guard !Task.isCancelled, midpointPlacedInsightID == placedID else { return }
                viewModel.removePlacedMidpoint(id: placedID)
                midpointPlacedInsightID = nil
                midpointGeneratedInsightID = nil
                onMidpointGeneratingChange?(false)
                presentModelActionError {
                    selectedCanvasTargets = sourceTargets
                    placeMidpointInsight(
                        at: worldPosition,
                        nearestTarget: nearestTarget,
                        weights: weights
                    )
                }
            }
        }

        guard let modelTasks else {
            midpointGenerationTask = Task { @MainActor in
                await generateMidpoint()
            }
            return
        }

        modelTasks.enqueue(
            kind: .createMidpoint,
            originPage: modelTaskOriginPage,
            onCancel: {
                guard midpointPlacedInsightID == placedID else { return }
                viewModel.removePlacedMidpoint(id: placedID)
                midpointPlacedInsightID = nil
                midpointGeneratedInsightID = nil
                onMidpointGeneratingChange?(false)
            }
        ) {
            await generateMidpoint()
        }
    }

    /// Called by the canvas after generation and the loading-icon reveal sequence. Pops the
    /// generated Insight card with its body text animating in like a streamed model response.
    private func revealPlacedMidpointCard(_ insightID: UUID) {
        guard midpointPlacedInsightID == insightID else { return }
        midpointPlacedInsightID = nil
        midpointGeneratedInsightID = nil
        midpointGenerationTask = nil
        onMidpointGeneratingChange?(false)
        // If the user navigated to another insight/node while it generated, don't hijack their card.
        let viewingOther = (selectedInsight != nil && selectedInsight?.id != insightID) || selectedNode != nil
        guard !viewingOther else { return }
        guard let insight = viewModel.nodes.flatMap(\.insights).first(where: { $0.id == insightID }) else { return }
        showInsightCard(insight, animateText: true, moveCamera: false)
    }

    /// Empty, identity-bearing content used only while the loading icon is visible. It is never
    /// revealed as an Insight title; the generated definition replaces it in place first.
    private func makeMidpointLoadingConcept() -> ConceptDefinition {
        ConceptDefinition(
            word: "",
            partOfSpeech: "",
            pronunciation: "",
            meaning: "",
            example: ""
        )
    }

    private func requestMidpointDefinition(
        weights: [Double],
        targets: [ConceptDefinition],
        cachedSourceEmbeddings: [[Double]?]
    ) async throws -> ConceptDefinition {
        let candidates = try await model.blendConceptCandidates(
            targets,
            weights: weights
        )
        guard let fallback = candidates.first else {
            throw AquinasModelActionError.invalidResponse
        }

        var sourceEmbeddings: [[Double]] = []
        for index in targets.indices {
            if index < cachedSourceEmbeddings.count,
               let cached = cachedSourceEmbeddings[index],
               !cached.isEmpty {
                sourceEmbeddings.append(cached)
                continue
            }
            let target = targets[index]
            guard let embedded = await embeddingProvider.embed(
                "\(target.word). \(target.semanticDefinition)"
            ) else {
                return fallback
            }
            sourceEmbeddings.append(embedded)
        }
        guard let targetCentroid = normalizedWeightedCentroid(
            sourceEmbeddings,
            weights: weights
        ) else {
            return fallback
        }

        var nearest = fallback
        var nearestDistance = Double.infinity
        for candidate in candidates {
            guard let candidateEmbedding = await embeddingProvider.embed(
                "\(candidate.word). \(candidate.semanticDefinition)"
            ) else {
                continue
            }
            let distance = semanticDistance(candidateEmbedding, targetCentroid)
            if distance < nearestDistance {
                nearest = candidate
                nearestDistance = distance
            }
        }
        return nearest
    }

    private func cachedEmbedding(for target: CanvasSelectionTarget) -> [Double]? {
        switch target {
        case .insight(let id):
            return viewModel.nodes
                .flatMap(\.insights)
                .first(where: {
                    $0.id == id && $0.embeddingVersion == embeddingProvider.version
                })?
                .embedding
        case .node(let id):
            guard let embedding = viewModel.nodes
                .first(where: { $0.id == id })?
                .embedding,
                !embedding.isEmpty else {
                return nil
            }
            return embedding
        }
    }

    private func insightID(for target: CanvasSelectionTarget) -> UUID? {
        switch target {
        case .insight(let id):
            return id
        case .node(let id):
            return viewModel.nodes.first(where: { $0.id == id })?.insights.first?.id
        }
    }

    private func concept(for target: CanvasSelectionTarget) -> ConceptDefinition? {
        switch target {
        case .insight(let id):
            guard let insight = viewModel.nodes
                .flatMap(\.insights)
                .first(where: { $0.id == id }) else {
                return nil
            }
            return concept(for: insight)
        case .node(let id):
            guard let node = viewModel.nodes.first(where: { $0.id == id }) else { return nil }
            return quoteTarget(for: node)
        }
    }

    private func concept(for insight: InsightModel) -> ConceptDefinition {
        if let placedMidpoint = viewModel.placedMidpointConcept(for: insight.id) {
            return placedMidpoint
        }

        // A persisted tree Insight already carries the definition scoped to this conversation.
        // Resolving it through the global library can return the same term with definitions merged
        // from other conversations, which makes the tree card show unrelated meanings.
        if conversationID != nil {
            return ConceptDefinition(
                id: insight.id,
                word: insight.title,
                partOfSpeech: "",
                pronunciation: "",
                meaning: insight.definition,
                example: ""
            )
        }

        return insights.first(where: { $0.id == insight.id })
            ?? ConceptDefinition(
                id: insight.id,
                word: insight.title,
                partOfSpeech: "",
                pronunciation: "",
                meaning: insight.definition,
                example: ""
            )
    }

    private func loadPersistedTree(animateChanges: Bool) async {
        guard let conversationID else { return }
        persistedTreeLoadGeneration += 1
        let loadGeneration = persistedTreeLoadGeneration

        // No point spending a 120s-timeout-capable network request on a URL that's loopback
        // from the phone's own perspective — go straight to the local-seed path every other
        // failure of this call already falls back to. Every duplicate `.refreshInsightTree` job
        // that piled up from repeatedly opening the tree (see `enqueuePersistedTreeLoad`, now
        // deduplicated) used to each pay that doomed request serially, which is what made the
        // tree look permanently stuck rather than just briefly loading.
        guard AquinasBackendConfiguration.canRecoverFromCurrentDevice else {
            applyLocalSeedTreeIfAvailable(conversationID: conversationID)
            persistedTreePresentationRevision += 1
            if animateChanges {
                onPersistedTreeRefreshCompleted?()
            }
            return
        }

        do {
            var tree = try await insightTreeService.tree(for: conversationID)
            guard !Task.isCancelled,
                  loadGeneration == persistedTreeLoadGeneration else { return }

            if reconcilesPersistedSavedInsights {
                let staleInsightIDs = Set(
                    tree.nodes
                        .flatMap(\.insights)
                        .filter {
                            $0.sourceType == "saved_definition"
                                && !savedConceptIDs.contains($0.id)
                        }
                        .map(\.id)
                )
                for insightID in staleInsightIDs {
                    try await insightTreeService.remove(
                        insightID: insightID,
                        from: conversationID
                    )
                }
                if !staleInsightIDs.isEmpty {
                    tree = try await insightTreeService.tree(for: conversationID)
                    guard !Task.isCancelled,
                          loadGeneration == persistedTreeLoadGeneration else { return }
                }
            }

            var didRepairNodeLabel = false
            for node in tree.nodes where node.needsGeneratedLabel {
                let descriptions = node.insights.map {
                    "\($0.title): \($0.definition)"
                }
                let label: String
                do {
                    label = try await model.labelSubject(forTitles: descriptions)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    continue
                }
                let labelKey = canonicalTreeTitle(label)
                let duplicatesInsightTitle = node.insights.contains {
                    canonicalTreeTitle($0.title) == labelKey
                }
                guard !label.isEmpty, !duplicatesInsightTitle else { continue }
                do {
                    try await insightTreeService.labelNode(
                        nodeID: node.id,
                        in: conversationID,
                        label: label
                    )
                    didRepairNodeLabel = true
                } catch {
                    continue
                }
            }
            if didRepairNodeLabel {
                tree = try await insightTreeService.tree(for: conversationID)
                guard !Task.isCancelled,
                      loadGeneration == persistedTreeLoadGeneration else { return }
            }

            // One-time/back-online reconciliation for saved concepts already associated with
            // this conversation before persistent tree consumption was introduced.
            let storedIDs = Set(tree.nodes.flatMap(\.insights).map(\.id))
            let missingSavedInsights = insights.filter {
                savedConceptIDs.contains($0.id) && !storedIDs.contains($0.id)
            }
            var didSaveMissingInsight = false
            for concept in missingSavedInsights {
                do {
                    let suggestedNodeLabel = try await model.labelSubject(
                        forTitles: ["\(concept.word): \(concept.semanticDefinition)"]
                    )
                    let assignment = try await insightTreeService.save(
                        concept,
                        to: conversationID,
                        suggestedNodeLabel: suggestedNodeLabel
                    )
                    let addedNodeIDs = assignment.didCreateNode ? [assignment.nodeID] : []
                    InsightDiscoveryStore.markUndiscovered([concept.id])
                    InsightDiscoveryStore.markNodesUndiscovered(addedNodeIDs)
                    InsightDiscoveryStore.markPendingTreePresentation(
                        insightIDs: [concept.id],
                        nodeIDs: addedNodeIDs
                    )
                    didSaveMissingInsight = true
                } catch {
                    continue
                }
            }
            if didSaveMissingInsight {
                tree = try await insightTreeService.tree(for: conversationID)
                guard !Task.isCancelled,
                      loadGeneration == persistedTreeLoadGeneration else { return }
            }

            // Apply exactly one fully reconciled snapshot. Publishing an intermediate tree here
            // used to let the canvas consume its entrance animation before the real update landed.
            guard loadGeneration == persistedTreeLoadGeneration else { return }
            viewModel.applyPersistedTree(tree)
            persistedTreePresentationRevision += 1
            if animateChanges {
                animatedPersistedTreePresentationRevision =
                    persistedTreePresentationRevision
                onPersistedTreeRefreshCompleted?()
            }
        } catch {
            // The backend is optional during local-only use. Release the entrance gate so the
            // already-built in-memory tree is visible instead of leaving a blank star field.
            guard loadGeneration == persistedTreeLoadGeneration else { return }
            applyLocalSeedTreeIfAvailable(conversationID: conversationID)
            persistedTreePresentationRevision += 1
            if animateChanges {
                onPersistedTreeRefreshCompleted?()
            }
        }
    }

    /// Not MiniLM parity — on-device-labeled Nodes, one per turn the model judged as seeding or
    /// materially extending the subject (see `insightTreeSeedCandidate`), fed into the view
    /// model's own on-device clustering pass as pre-existing anchor clusters (see
    /// `InsightTreeViewModel.setLocalSeedAnchors`) rather than a separate `applyPersistedTree`
    /// snapshot. That earlier approach put the seed and the clustering fallback in two mutually
    /// exclusive rendering modes — whichever last wrote to the view model won, so saving an
    /// Insight would make the seeded Node disappear rather than the two coexisting. Feeding both
    /// into the same clustering pass lets a saved Insight attach under the seeded subject when
    /// related, exactly like a real backend Node would.
    private func applyLocalSeedTreeIfAvailable(conversationID: UUID) {
        let localSeeds = LocalInsightTreeSeedStore.seeds(for: conversationID)
#if DEBUG
        print("Aquinas InsightTreeView: applyLocalSeedTreeIfAvailable found \(localSeeds.count) seed(s) for \(conversationID)")
#endif
        viewModel.setLocalSeedAnchors(localSeeds)
    }

    /// Persisted-tree fetches may also repair labels or reconcile saved Insights, so they are
    /// model work rather than an untracked view refresh. Keeping them in the shared queue prevents
    /// the status control from returning to Idle before the fully reconciled snapshot is applied.
    ///
    /// Deduplicated: without this guard, every appearance of the tree canvas (and every
    /// `persistedTreeRefreshRequest` bump) queued a brand-new `.refreshInsightTree` job with no
    /// check for one already pending — repeatedly opening the tree piled up duplicate jobs, each
    /// serially paying the same (120s-timeout-capable, on-device always-unreachable) network
    /// request, which is what made the tree look permanently stuck rather than briefly loading.
    private func enqueuePersistedTreeLoad(animateChanges: Bool) {
        guard conversationID != nil else { return }
        guard let modelTasks else {
            Task { await loadPersistedTree(animateChanges: animateChanges) }
            return
        }
        guard !modelTasks.contains(where: {
            $0.kind == .refreshInsightTree
                && $0.conversationID == conversationID
                && $0.phase != .completed
        }) else {
            return
        }
        modelTasks.enqueue(
            kind: .refreshInsightTree,
            originPage: modelTaskOriginPage,
            conversationID: conversationID,
            priority: .background
        ) {
            await loadPersistedTree(animateChanges: animateChanges)
        }
    }

    private func canonicalTreeTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func quoteTarget(for node: NodeModel) -> ConceptDefinition? {
        // Quote the Node Concept itself (its label + definition), so the whole grouping can be
        // pulled back into a conversation — not just one member insight. Promoted nodes carry
        // their own definition; auto-clustered nodes fall back to a summary of their members.
        let label = node.conceptLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return nil }

        let ownDefinition = node.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning: String
        if !ownDefinition.isEmpty {
            meaning = ownDefinition
        } else {
            let titles = node.insights.prefix(6).map(\.title).filter { !$0.isEmpty }
            meaning = titles.isEmpty ? "" : "A grouping of related insights: " + titles.joined(separator: ", ") + "."
        }

        return ConceptDefinition(
            id: node.id,
            word: label,
            partOfSpeech: "",
            pronunciation: "",
            meaning: meaning,
            example: ""
        )
    }
}

/// A literal weighted centroid in the active cosine-embedding space. Source vectors are first
/// normalized so their magnitudes cannot distort the percentages, then the centroid is normalized
/// for direct cosine-distance comparison with generated candidates.
func normalizedWeightedCentroid(
    _ vectors: [[Double]],
    weights: [Double]
) -> [Double]? {
    guard let first = vectors.first,
          !first.isEmpty,
          vectors.count == weights.count,
          vectors.allSatisfy({ $0.count == first.count }),
          weights.allSatisfy(\.isFinite) else {
        return nil
    }

    let clippedWeights = weights.map { max($0, 0) }
    let totalWeight = clippedWeights.reduce(0, +)
    guard totalWeight > 0 else { return nil }

    var center = Array(repeating: 0.0, count: first.count)
    for (vector, weight) in zip(vectors, clippedWeights) where weight > 0 {
        let magnitude = sqrt(vector.map { $0 * $0 }.reduce(0, +))
        guard magnitude > 0 else { return nil }
        let normalizedWeight = weight / totalWeight
        for index in vector.indices {
            center[index] += vector[index] / magnitude * normalizedWeight
        }
    }

    let centerMagnitude = sqrt(center.map { $0 * $0 }.reduce(0, +))
    guard centerMagnitude > 0 else { return nil }
    return center.map { $0 / centerMagnitude }
}

enum CanvasSelectionTarget: Equatable {
    case node(UUID)
    case insight(UUID)
}

enum CanvasSelectionPolicy {
    static let maximumCount = 8
}

struct DockedInsightTreeCard: View {
    let insight: InsightModel
    var isSaved: Bool = false

    /// When true, the body text fades/transforms/blurs in like a streamed model response.
    var animateIn: Bool = false
    /// Insight links grown under the card content while Make Node generates children — each
    /// appears in sync with its child's reveal haptic.
    var linkedInsights: [InsightModel] = []
    var onToggleSaved: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var onFork:   (() -> Void)? = nil
    var onSelectLinkedInsight: ((InsightModel) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var textRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                DockedCardTextBubbleIcon(size: 12, delay: 0.18, color: AquinasTheme.Colors.darkGreen)

                Text(insight.title)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                ResponseButtons(
                    isSaved: isSaved,
                    canCopy: true,
                    canFork: true,
                    copyText: insight.definition,
                    tintColor: AquinasTheme.Colors.placeholderText,
                    saveTintColor: isSaved ? AquinasTheme.Colors.accentRed : nil,
                    onSave: onToggleSaved,
                    onFork: { onFork?() }
                )

                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AquinasTheme.Colors.placeholderText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove from conversation")
                }
            }

            let definitionText = insight.definition.isEmpty || insight.definition.lowercased() == insight.title.lowercased()
                ? "This is an example of what an Insight Card will look like, the definition as relates to subject will be here"
                : insight.definition
            TruncatableParagraph(text: definitionText)
                .modifier(GlideFadeModifier(isActive: animateIn && !textRevealed))

            // Insight links grown one-by-one as Make Node reveals each child (on its haptic).
            if !linkedInsights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(linkedInsights, id: \.id) { linked in
                        DockedInsightLinkRow(insight: linked) { onSelectLinkedInsight?($0) }
                    }
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            // The border + background fade in with the card; 0.15s later the body text
            // animates in (blur/fade/transform), like a streamed model response.
            guard animateIn else { return }
            textRevealed = false
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                textRevealed = true
            }
        }
        // Trim the bottom: the definition's .lineSpacing(12) leaves trailing space below the
        // last line, so a full 32 there reads as noticeably more space than the 32 up top.
        .dockedCardChrome(bottomPadding: 20)
    }
}

extension View {
    /// The docked Insight card's chrome: padding, full width, fill, 36 pt continuous corners,
    /// hairline border, and soft shadow. Shared so other docked cards match it exactly.
    /// `clipsContent` false lets content move past the card's edge (the Study tool card's
    /// sliding copy); the card itself looks the same.
    func dockedCardChrome(bottomPadding: CGFloat, clipsContent: Bool = true) -> some View {
        self
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(insightTreeInsightColor, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            .modifier(DockedCardClip(isEnabled: clipsContent))
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
            )
            .shadow(color: Color(red: 0.13, green: 0.06, blue: 0).opacity(0.15), radius: 24, x: 0, y: 0)
    }
}

private struct DockedCardClip: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        } else {
            content
        }
    }
}

/// A node concept's docked card. Renders identically to `DockedInsightTreeCard` (icon + title +
/// action buttons + definition), then lists links to its child/member insights underneath.
private struct DockedNodeTreeCard: View {
    let node: NodeModel

    var isSaved: Bool = false
    var onSelectInsight: (InsightModel) -> Void
    var onToggleSaved: (() -> Void)? = nil
    var onFork: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    /// Fallback body when a node carries no definition of its own (auto clustered concepts).
    private var summaryText: String {
        let titles = node.insights.prefix(3).map(\.title)
        guard !titles.isEmpty else {
            return "\(node.conceptLabel) is a developing subject in this insight map."
        }

        return "\(node.conceptLabel) gathers related insights around \(titles.joined(separator: ", "))."
    }

    private var bodyText: String {
        node.definition.isEmpty ? summaryText : node.definition
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                DockedCardTextBubbleIcon(size: 12, delay: 0.18, color: AquinasTheme.Colors.darkGreen)

                Text(node.conceptLabel)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                ResponseButtons(
                    isSaved: isSaved,
                    canCopy: true,
                    canFork: onFork != nil,
                    copyText: bodyText,
                    tintColor: AquinasTheme.Colors.placeholderText,
                    saveTintColor: AquinasTheme.Colors.accentRed,
                    onSave: onToggleSaved,
                    onFork: onFork
                )
            }

            TruncatableParagraph(text: bodyText)

            // Links to the concept's child / member insights.
            if !node.insights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(node.insights, id: \.id) { insight in
                        DockedInsightLinkRow(insight: insight, onTap: onSelectInsight)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insightTreeInsightColor)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
        .shadow(color: Color(red: 0.13, green: 0.06, blue: 0).opacity(0.15), radius: 24, x: 0, y: 0)
    }
}

/// One tappable Insight link row — shared under both the insight and node concept cards for
/// child/member insights (bubble icon + underlined title in the muted link color). Appears with a
/// fade/rise/scale insertion so links added mid-animation (Make Node) glide in one at a time.
private struct DockedInsightLinkRow: View {
    let insight: InsightModel
    var onTap: (InsightModel) -> Void

    var body: some View {
        Button {
            onTap(insight)
        } label: {
            HStack(spacing: 8) {
                DockedCardTextBubbleIcon(size: 14, delay: 0, color: AquinasTheme.Colors.darkGreen)

                // No minimumScaleFactor: it interacts with the insertion transition below and
                // locks later-inserted rows at a slightly reduced scale. Fixed size + truncation
                // keeps every link identical.
                Text(insight.title)
                    .font(.figtreeParagraph)
                    .bold()
                    .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Glide in with a fade + gentle rise. No .scale here — scaling the row makes the text's
        // layout resolve at a smaller size and it stays shrunk after the transition settles.
        .transition(.opacity.combined(with: .offset(y: 10)))
    }
}

private struct DockedConceptCard: View {
    let concept: ConceptDefinition
    let isSaved: Bool
    var onToggleSaved: () -> Void
    var onFork: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                DockedCardTextBubbleIcon(size: 12, delay: 0.18, color: AquinasTheme.Colors.darkGreen)
                Text(concept.word.capitalized)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                ResponseButtons(
                    isSaved: isSaved,
                    canCopy: true,
                    canFork: true,
                    copyText: concept.semanticDefinition,
                    tintColor: AquinasTheme.Colors.placeholderText,
                    saveTintColor: AquinasTheme.Colors.accentRed,
                    onSave: onToggleSaved,
                    onFork: onFork
                )
            }
            InsightDefinitionsContent(
                definitions: concept.contextualDefinitions
            )
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insightTreeInsightColor)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
    }
}

/// Docked card shown during Midpoint Selection mode: lists the selected insights and the
/// blend percentage of the new insight. For two insights the percentage is editable
/// (tap to type, drag to scrub); for 3+ the weights are shown read-only.
private struct MidpointPercentCard: View {
    let concepts: [ConceptDefinition]
    let weights: [Double]
    var onSetPercent: (Int, Int) -> Void

    private var percents: [Int] {
        guard weights.count == concepts.count, !weights.isEmpty else { return [] }
        return weights.map { Int(($0 * 100).rounded()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Midpoint")
                .font(.custom("Figtree-Bold", size: 18))
                .foregroundColor(AquinasTheme.Colors.headingText)

            ForEach(Array(concepts.enumerated()), id: \.offset) { index, concept in
                row(index: index, concept: concept)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insightTreeInsightColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func row(index: Int, concept: ConceptDefinition) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
            Text(concept.word.capitalized)
                .font(.custom("Figtree-Bold", size: 14))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .lineLimit(1)
                .layoutPriority(1)

            DottedConnector()

            if let percent = index < percents.count ? percents[index] : nil {
                PercentStepper(
                    percent: percent,
                    onChange: { newValue in onSetPercent(index, newValue) }
                )
            }
        }
    }
}

/// `‹ XX% ›` percentage control: chevrons step by 1%, the number itself can be tapped to type
/// or dragged to scrub. Fires a light haptic for every 1% change.
private struct PercentStepper: View {
    let percent: Int
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            chevron("chevron.left") { step(-1) }
            EditablePercent(percent: percent, onChange: onChange)
            chevron("chevron.right") { step(1) }
        }
    }

    private func chevron(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.headingText)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func step(_ delta: Int) {
        let newValue = min(100, max(0, percent + delta))
        guard newValue != percent else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
        onChange(newValue)
    }
}

/// A faint dotted line that fills the available horizontal space.
private struct DottedConnector: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(
                AquinasTheme.Colors.paragraphText.opacity(0.3),
                style: StrokeStyle(lineWidth: 1, dash: [1.5, 4])
            )
        }
        .frame(height: 1)
        .frame(maxWidth: .infinity)
    }
}

/// A percentage value that can be tapped to type an exact number or dragged horizontally to
/// scrub. Fires a light haptic for every 1% change while scrubbing.
private struct EditablePercent: View {
    let percent: Int
    var onChange: (Int) -> Void

    @State private var isEditing = false
    @State private var text = ""
    @State private var dragStartPercent: Int? = nil
    @State private var lastHapticPercent: Int = 0
    @State private var flashOpacity: CGFloat = 1.0
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .font(.custom("Figtree-Bold", size: 16))
                    .foregroundColor(AquinasTheme.Colors.headingText)
                    .fixedSize()
                    .opacity(flashOpacity)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() }
                    }
                    .onAppear {
                        flashOpacity = 1.0
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            flashOpacity = 0.5
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(action: commit) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                            }
                        }
                    }
            } else {
                Text("\(percent)%")
                    .font(.custom("Figtree-Bold", size: 16))
                    .foregroundColor(AquinasTheme.Colors.headingText)
                    .monospacedDigit()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        text = "\(percent)"
                        isEditing = true
                        focused = true
                    }
                    .gesture(scrubGesture)
            }
        }
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStartPercent == nil {
                    dragStartPercent = percent
                    lastHapticPercent = percent
                }
                let base = dragStartPercent ?? percent
                let delta = Int((value.translation.width / 4).rounded())
                let newValue = min(100, max(0, base + delta))
                if newValue != lastHapticPercent {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred(intensity: 0.55)
                    lastHapticPercent = newValue
                }
                if newValue != percent { onChange(newValue) }
            }
            .onEnded { _ in dragStartPercent = nil }
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false
        focused = false
        let digits = text.filter(\.isNumber)
        guard let value = Int(digits) else { return }
        onChange(min(100, max(0, value)))
    }
}

private struct DockedCardTextBubbleIcon: View {
    let size: CGFloat
    var delay: TimeInterval = 0
    var color: Color = AquinasTheme.Colors.darkGreenDarkMode
    @State private var isVisible = false

    var body: some View {
        Image(systemName: "text.bubble.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(color)
            .scaleEffect(isVisible ? 1 : 0.86)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                isVisible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                        isVisible = true
                    }
                }
            }
    }
}

private struct EmptyInsightTreeView: View {
    var body: some View {
        AquinasEmptyState(
            systemImage: "brain.head.profile",
            title: "Insights will gather here",
            message: "Save insights from conversations to begin forming Theo's map of connected ideas."
        )
    }
}
