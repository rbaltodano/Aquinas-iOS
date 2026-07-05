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
    var selectionRequest: Int = 0
    var clearSelectionRequest: Int = 0
    var dismissHoverRequest: Int = 0
    var createConceptRequest: Int = 0
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
    var onInquireConnectionConcepts: ((ConceptDefinition, ConceptDefinition) -> Void)? = nil
    var midpointEnterRequest: Int = 0
    var midpointCenterRequest: Int = 0
    var midpointPlaceRequest: Int = 0
    var highlightedInsightPair: (UUID, UUID)? = nil
    var highlightPairRequest: Int = 0
    var startsMidpointForHighlightedPair: Bool = false
    var onMidpointModeChange: ((Bool) -> Void)? = nil
    /// Reports whether a just-placed midpoint insight is currently "generating".
    var onMidpointGeneratingChange: ((Bool) -> Void)? = nil
    var onUndiscoveredInsightCountChange: ((Int) -> Void)? = nil
    var inputFont: ConversationFontOption = .serif
    var conversationFontSize: ConversationFontSizeOption = .small
    var showQuestionBar: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var viewModel: InsightTreeViewModel
    @State private var selectedInsight: InsightModel?
    @State private var selectedNode: NodeModel?
    @State private var hoveredConcept: ConceptDefinition?
    /// Insight id of a just-placed midpoint while it "loads" on the canvas.
    @State private var midpointPlacedInsightID: UUID?
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

    init(
        insights: [ConceptDefinition],
        selectionRequest: Int = 0,
        clearSelectionRequest: Int = 0,
        dismissHoverRequest: Int = 0,
        createConceptRequest: Int = 0,
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
        onInquireConnectionConcepts: ((ConceptDefinition, ConceptDefinition) -> Void)? = nil,
        midpointEnterRequest: Int = 0,
        midpointCenterRequest: Int = 0,
        midpointPlaceRequest: Int = 0,
        highlightedInsightPair: (UUID, UUID)? = nil,
        highlightPairRequest: Int = 0,
        startsMidpointForHighlightedPair: Bool = false,
        onMidpointModeChange: ((Bool) -> Void)? = nil,
        onMidpointGeneratingChange: ((Bool) -> Void)? = nil,
        onUndiscoveredInsightCountChange: ((Int) -> Void)? = nil,
        inputFont: ConversationFontOption = .serif,
        conversationFontSize: ConversationFontSizeOption = .small,
        showQuestionBar: Bool = true
    ) {
        self.insights              = insights
        self.selectionRequest      = selectionRequest
        self.clearSelectionRequest = clearSelectionRequest
        self.dismissHoverRequest   = dismissHoverRequest
        self.createConceptRequest  = createConceptRequest
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
        self.highlightedInsightPair        = highlightedInsightPair
        self.highlightPairRequest          = highlightPairRequest
        self.startsMidpointForHighlightedPair = startsMidpointForHighlightedPair
        self.onMidpointModeChange          = onMidpointModeChange
        self.onMidpointGeneratingChange    = onMidpointGeneratingChange
        self.onUndiscoveredInsightCountChange = onUndiscoveredInsightCountChange
        self.inputFont             = inputFont
        self.conversationFontSize  = conversationFontSize
        self.showQuestionBar       = showQuestionBar
        _viewModel = StateObject(wrappedValue: InsightTreeViewModel(insights: insights, promotedInsightIDs: promotedInsightIDs))
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
                pulsingInsightID: questionBarContextInsight?.id,
                pulsingNodeID: selectedNode?.id,
                selectedCanvasTargets: selectedCanvasTargets,
                selectionPulseRequest: selectionPulseRequest,
                makeNodeChildIDs: viewModel.makeNodeChildIDs,
                placedMidpointNodeIDs: viewModel.placedMidpointNodeIDs,
                placedMidpointSources: viewModel.placedMidpointSources,
                insightBondLengths: viewModel.insightBondLengths,
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
                        .offset(y: dockedCardDragY)
                        .gesture(dockedCardDismissGesture)
                        .transition(.scale(scale: 0.35, anchor: .bottom).combined(with: .opacity))
                        .padding(.horizontal, 10)
                    } else if let selectedInsight {
                        DockedInsightTreeCard(
                            insight: selectedInsight,
                            animateIn: animateMidpointCardText,
                            linkedInsights: makeNodeLinkInsights,
                            onRemove: { pendingRemoveInsight = selectedInsight },
                            onFork:   { performForkInsight(selectedInsight) },
                            onSelectLinkedInsight: { insight in
                                focusedInsightID = insight.id
                                showInsightCard(insight)
                            }
                        )
                        .offset(y: dockedCardDragY)
                        .gesture(dockedCardDismissGesture)
                        .transition(.scale(scale: 0.35, anchor: .bottom).combined(with: .opacity))
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
                        .offset(y: dockedCardDragY)
                        .gesture(dockedCardDismissGesture)
                        .transition(.scale(scale: 0.35, anchor: .bottom).combined(with: .opacity))
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
        .onChange(of: inquireConnectionRequest) { _, _ in
            performInquireConnection()
        }
        .onChange(of: midpointEnterRequest) { _, _ in
            enterMidpointMode()
        }
        .onChange(of: highlightPairRequest) { _, _ in
            highlightInsightPair()
        }
        .onAppear {
            if highlightedInsightPair != nil {
                highlightInsightPair()
            }
        }
        .alert("Remove bookmark?", isPresented: Binding(
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
            Text("This insight will be removed from your Insight Tree. You can undo this immediately after.")
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
        onInsightSelectionStateChange?(true)
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
        guard let concept = insights.first(where: { $0.id == insight.id }) else { return }
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
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
        // Keep this insight's card docked while its children generate; it grows an Insight
        // link per child, each appended in sync with the child's reveal haptic.
        makeNodeParentInsightID = selectedInsight.id
        makeNodeLinkInsightIDs = []
        makeNodeGenerating = true
        onPromotedInsightIDsChange?(promotedInsightIDs + [selectedInsight.id])
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
        let c1 = concept(for: selectedCanvasTargets[0])
        let c2 = concept(for: selectedCanvasTargets[1])
        guard let c1, let c2 else { return }
        clearSelectedCanvasTargets()
        dismissDockedInsight()
        onInquireConnectionConcepts?(c1, c2)
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

    /// Commits the placed midpoint: builds a "New Insight" concept, pins it on the
    /// canvas connected to the nearest selected insight, then exits midpoint mode.
    private func placeMidpointInsight(at worldPosition: CGPoint, nearestTarget: CanvasSelectionTarget, weights: [Double]) {
        let sourceConcepts = selectedCanvasTargets.compactMap { concept(for: $0) }
        // Connect the placed midpoint to every source it was spawned from — to the insight chip
        // for a selected insight, or the node center for a selected node concept.
        let sources: [MidpointSource] = selectedCanvasTargets.compactMap { target in
            guard let id = insightID(for: target) else { return nil }
            if case .node = target { return MidpointSource(insightID: id, isNode: true) }
            return MidpointSource(insightID: id, isNode: false)
        }
        let concept = makeMidpointConcept(weights: weights, targets: sourceConcepts)

        // The placed node and its single insight both share the concept id.
        midpointPlacedInsightID = concept.id
        onMidpointGeneratingChange?(true)
        viewModel.addPlacedMidpoint(concept: concept, at: worldPosition, sources: sources)

        exitMidpointMode()
        selectedCanvasTargets.removeAll()
        onSelectedCanvasItemCountChange?(0)
        // Keep the canvas hovering the new insight — the canvas runs its loading
        // sequence and calls back via revealPlacedMidpointCard to pop the card.
    }

    /// Called by the canvas once the placed midpoint insight has finished its simulated
    /// load (icon flash → title reveal → dot pulse). Pops the insight card with its body
    /// text animating in like a streamed model response.
    private func revealPlacedMidpointCard(_ insightID: UUID) {
        guard midpointPlacedInsightID == insightID else { return }
        midpointPlacedInsightID = nil
        onMidpointGeneratingChange?(false)
        // If the user navigated to another insight/node while it generated, don't hijack their card.
        let viewingOther = (selectedInsight != nil && selectedInsight?.id != insightID) || selectedNode != nil
        guard !viewingOther else { return }
        guard let insight = viewModel.nodes.flatMap(\.insights).first(where: { $0.id == insightID }) else { return }
        showInsightCard(insight, animateText: true, moveCamera: false)
    }

    /// Synchronous stub so the node appears pinned immediately. The placed concept is
    /// simply named "New Insight" for now; `requestMidpointDefinition` is the seam for
    /// the real model-generated blend.
    private func makeMidpointConcept(weights: [Double], targets: [ConceptDefinition]) -> ConceptDefinition {
        ConceptDefinition(
            word: "New Insight",
            partOfSpeech: "",
            pronunciation: "",
            meaning: "",            // DockedConceptCard shows placeholder copy when meaning is empty
            example: ""
        )
    }

    /// Seam for the real model call. Mirrors `requestDynamicDefinition` (CurrentConversation.swift).
    /// When wired, build a "blend these concepts at these weights" prompt and replace the placed
    /// concept's contents in place via the view model.
    private func requestMidpointDefinition(weights: [Double], targets: [ConceptDefinition]) async {
        // TODO: call the model with the weighted blend prompt and update the placed concept.
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
            return insights.first(where: { $0.id == id })
        case .node(let id):
            guard let node = viewModel.nodes.first(where: { $0.id == id }) else { return nil }
            return quoteTarget(for: node)
        }
    }

    private func concept(for insight: InsightModel) -> ConceptDefinition? {
        insights.first(where: { $0.id == insight.id })
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

enum CanvasSelectionTarget: Equatable {
    case node(UUID)
    case insight(UUID)
}

struct DockedInsightTreeCard: View {
    let insight: InsightModel

    /// When true, the body text fades/transforms/blurs in like a streamed model response.
    var animateIn: Bool = false
    /// Insight links grown under the card content while Make Node generates children — each
    /// appears in sync with its child's reveal haptic.
    var linkedInsights: [InsightModel] = []
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                ResponseButtons(
                    isSaved: true,
                    canCopy: true,
                    canFork: true,
                    copyText: insight.definition,
                    tintColor: AquinasTheme.Colors.placeholderText,
                    saveTintColor: AquinasTheme.Colors.accentRed,
                    onSave: { onRemove?() },
                    onFork: { onFork?() }
                )
            }

            let definitionText = insight.definition.isEmpty || insight.definition.lowercased() == insight.title.lowercased()
                ? "This is an example of what an Insight Card will look like, the definition as relates to subject will be here"
                : insight.definition
            Text(definitionText)
                .font(.figtreeParagraph)
                .lineSpacing(12)
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .fixedSize(horizontal: false, vertical: true)
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

            Text("Swipe up for more information")
                .font(.figtreeSmall)
                .foregroundColor(AquinasTheme.Colors.placeholderText)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

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

            Text(bodyText)
                .font(.figtreeParagraph)
                .lineSpacing(12)
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .fixedSize(horizontal: false, vertical: true)

            // Links to the concept's child / member insights.
            if !node.insights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(node.insights, id: \.id) { insight in
                        DockedInsightLinkRow(insight: insight, onTap: onSelectInsight)
                    }
                }
                .padding(.top, 4)
            }

            Text("Swipe up for more information")
                .font(.figtreeSmall)
                .foregroundColor(AquinasTheme.Colors.placeholderText)
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
                    copyText: concept.meaning,
                    tintColor: AquinasTheme.Colors.placeholderText,
                    saveTintColor: AquinasTheme.Colors.accentRed,
                    onSave: onToggleSaved,
                    onFork: onFork
                )
            }
            let meaningText = concept.meaning.isEmpty || concept.meaning.lowercased() == concept.word.lowercased()
                ? "This is an example of what an Insight Card will look like, the definition as relates to subject will be here"
                : concept.meaning
            Text(meaningText)
                .font(.figtreeParagraph)
                .lineSpacing(12)
                .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            if !concept.example.isEmpty {
                Text("\"\(concept.example)\"")
                    .font(.custom("LibreBaskerville-Italic", size: 13))
                    .lineSpacing(8)
                    .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Swipe up for more information")
                .font(.figtreeSmall)
                .foregroundColor(AquinasTheme.Colors.placeholderText)
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insightTreeInsightColor)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
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
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .sfSymbolDrawOn()

            Text("Insights will gather here")
                .font(.baskervilleHeading1)
                .foregroundColor(AquinasTheme.Colors.primaryReadable)

            Text("Save insights from conversations to begin forming Theo's map of connected ideas.")
                .font(.figtreeParagraph)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .frame(maxWidth: 280)
        }
        .padding(24)
    }
}
