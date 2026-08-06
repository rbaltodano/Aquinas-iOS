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
    var restoreSelectedInsightID: UUID? = nil
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

    @Environment(\.colorScheme) private var colorScheme

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

    init(
        insights: [ConceptDefinition],
        conversationID: UUID? = nil,
        selectionRequest: Int = 0,
        persistedTreeRefreshRequest: Int = 0,
        clearSelectionRequest: Int = 0,
        dismissHoverRequest: Int = 0,
        createConceptRequest: Int = 0,
        restoreSelectedInsightID: UUID? = nil,
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
        insightTreeService: InsightTreeService = BackendInsightTreeService()
    ) {
        self.insights              = insights
        self.conversationID        = conversationID
        self.model                 = model
        self.embeddingProvider     = embeddingProvider
        self.insightTreeService    = insightTreeService
        self.selectionRequest      = selectionRequest
        self.persistedTreeRefreshRequest = persistedTreeRefreshRequest
        self.clearSelectionRequest = clearSelectionRequest
        self.dismissHoverRequest   = dismissHoverRequest
        self.createConceptRequest  = createConceptRequest
        self.restoreSelectedInsightID = restoreSelectedInsightID
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
            localSeedAnchors: initialLocalSeedAnchors
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
        ZStack {
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
                }
            )
                .ignoresSafeArea()
                .background(insightTreeCanvasColor)

            if viewModel.nodes.isEmpty {
                EmptyInsightTreeView()
            }

            VStack {
                HStack {
                    if let onClose {
                        Button(action: onClose) {
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
        }
        // safeAreaInset moves with the keyboard automatically — no manual observation needed.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if undoInsight != nil {
                    undoButtonView
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                }

                if isMidpointMode {
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
                    if !showQuestionBar, let concept = hoveredConcept {
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
                        .offset(y: dockedCardDragY)
                        .gesture(dockedCardDismissGesture)
                        .transition(.bottomDockCard)
                        .padding(.horizontal, 10)
                    } else if let selectedInsight {
                        DockedInsightTreeCard(
                            insight: selectedInsight,
                            isSaved: savedConceptIDs.contains(selectedInsight.id),
                            animateIn: animateMidpointCardText,
                            linkedInsights: makeNodeLinkInsights,
                            onToggleSaved: {
                                let wasSaved = savedConceptIDs.contains(selectedInsight.id)
                                onToggleSavedConcept?(concept(for: selectedInsight))
                                // Midpoint blends are synthesized on the fly and auto-bookmarked
                                // (see placeMidpointInsight) — unlike a term saved from real
                                // conversation content, nothing else anchors it to the tree, so
                                // un-saving it IS "get rid of it": also remove the placed node.
                                if wasSaved, viewModel.placedMidpointNodeIDs.contains(selectedInsight.id) {
                                    viewModel.removePlacedMidpoint(id: selectedInsight.id)
                                    dismissDockedInsight()
                                }
                            },
                            onRemove: { pendingRemoveInsight = selectedInsight },
                            onFork:   { performForkInsight(selectedInsight) },
                            onSelectLinkedInsight: { insight in
                                focusedInsightID = insight.id
                                showInsightCard(insight)
                            }
                        )
                        .id(selectedInsight.id)
                        .offset(y: dockedCardDragY)
                        .gesture(dockedCardDismissGesture)
                        .transition(.bottomDockCard)
                        .padding(.horizontal, 10)
                    } else if let selectedNode {
                        DockedNodeTreeCard(
                            node: selectedNode,
                            onSelectInsight: { insight in
                                focusedInsightID = insight.id
                                showInsightCard(insight)
                            },
                            onFork: { performForkNode(selectedNode) }
                        )
                        .id(selectedNode.id)
                        .offset(y: dockedCardDragY)
                        .gesture(dockedCardDismissGesture)
                        .transition(.bottomDockCard)
                        .padding(.horizontal, 10)
                    }
                }

                // Insight chip — appears above the bar when keyboard is open, mirrors card dismiss animation
                if showQuestionBar, chipShouldShow, let insight = questionBarContextInsight {
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
                }
            }
            .padding(.bottom, 16)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedInsight?.id)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: selectedNode?.id)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: hoveredConcept?.id)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isMidpointMode)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: undoInsight != nil)
        }
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
        .onChange(of: restoreSelectedInsightID) { _, _ in
            restoreRequestedInsightSelection()
        }
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
            } catch {
                guard !Task.isCancelled else { return }
                cancelGeneration()
                presentModelActionError {
                    promoteHoveredInsightToConcept()
                }
            }
        }
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
        let sourceConcepts = sourceTargets.compactMap { concept(for: $0) }
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
            $0.kind == .refreshInsightTree && $0.phase != .completed
        }) else {
            return
        }
        modelTasks.enqueue(
            kind: .refreshInsightTree,
            originPage: modelTaskOriginPage,
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
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .padding(.bottom, 20)
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
