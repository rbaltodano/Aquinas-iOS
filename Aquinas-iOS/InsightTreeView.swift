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
    var inputFont: ConversationFontOption = .serif
    var conversationFontSize: ConversationFontSizeOption = .small
    var showQuestionBar: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var viewModel: InsightTreeViewModel
    @State private var selectedInsight: InsightModel?
    @State private var selectedNode: NodeModel?
    @State private var dockedCardDragY: CGFloat = 0
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

    init(
        insights: [ConceptDefinition],
        selectionRequest: Int = 0,
        clearSelectionRequest: Int = 0,
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
        inputFont: ConversationFontOption = .serif,
        conversationFontSize: ConversationFontSizeOption = .small,
        showQuestionBar: Bool = true
    ) {
        self.insights              = insights
        self.selectionRequest      = selectionRequest
        self.clearSelectionRequest = clearSelectionRequest
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
        self.onPromotedInsightIDsChange = onPromotedInsightIDsChange
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

                if !cardShouldHide {
                    if let selectedInsight {
                        DockedInsightTreeCard(
                            insight: selectedInsight,
                            onRemove: { pendingRemoveInsight = selectedInsight },
                            onFork:   { performForkInsight(selectedInsight) }
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
                            }
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
        .onChange(of: createConceptRequest) { _, _ in
            promoteHoveredInsightToConcept()
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

    private func showInsightCard(_ insight: InsightModel) {
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
        focusedInsightID = insight.id
        onQuoteInsight?(concept(for: insight))

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            dockedCardDragY = 0
            selectedNode = nil
            selectedInsight = insight
            questionBarContextInsight = insight
        }
    }

    private func showNodeCard(_ node: NodeModel) {
        playDockedCardHaptic()
        onSelectionStateChange?(true)
        onInsightSelectionStateChange?(false)
        onQuoteInsight?(quoteTarget(for: node))

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = node
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

    private func dismissDockedInsight() {
        guard selectedInsight != nil || selectedNode != nil else { return }

        playDockedCardHaptic()
        onSelectionStateChange?(false)
        onInsightSelectionStateChange?(false)
        onQuoteInsight?(nil)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = nil
            questionBarContextInsight = nil
        }
    }

    // Dismisses the docked card without clearing the question bar chip.
    // Called when the question bar keyboard opens so the card slides away
    // but the quoted insight remains available in the bar.
    private func dismissDockedCard() {
        guard selectedInsight != nil || selectedNode != nil else { return }

        playDockedCardHaptic()
        onSelectionStateChange?(false)
        onInsightSelectionStateChange?(false)
        onQuoteInsight?(nil)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = nil
        }
    }

    private func clearCanvasSelectionSilently() {
        guard selectedInsight != nil || selectedNode != nil || questionBarContextInsight != nil else { return }

        onSelectionStateChange?(false)
        onInsightSelectionStateChange?(false)
        onQuoteInsight?(nil)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = nil
            questionBarContextInsight = nil
        }
    }

    private func clearSelectedCanvasTargets() {
        guard !selectedCanvasTargets.isEmpty else { return }
        selectedCanvasTargets.removeAll()
        onSelectedCanvasItemCountChange?(0)
    }

    private func playDockedCardHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.65)
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
        if selectedCanvasTargets.count > 1 {
            selectionPulseRequest += 1
        }
        onSelectedCanvasItemCountChange?(selectedCanvasTargets.count)
    }

    private func promoteHoveredInsightToConcept() {
        guard let selectedInsight else { return }
        guard !promotedInsightIDs.contains(selectedInsight.id) else { return }
        onPromotedInsightIDsChange?(promotedInsightIDs + [selectedInsight.id])
    }

    private func concept(for insight: InsightModel) -> ConceptDefinition? {
        insights.first(where: { $0.id == insight.id })
    }

    private func quoteTarget(for node: NodeModel) -> ConceptDefinition? {
        for insight in node.insights {
            if let concept = concept(for: insight) {
                return concept
            }
        }
        return nil
    }
}

enum CanvasSelectionTarget: Equatable {
    case node(UUID)
    case insight(UUID)
}

struct DockedInsightTreeCard: View {
    let insight: InsightModel

    var onRemove: (() -> Void)? = nil
    var onFork:   (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

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

            Text(insight.definition)
                .font(.figtreeParagraph)
                .lineSpacing(12)
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insightTreeInsightColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
        .shadow(color: Color(red: 0.13, green: 0.06, blue: 0).opacity(0.15), radius: 24, x: 0, y: 16)
    }
}

private struct DockedNodeTreeCard: View {
    let node: NodeModel

    var onSelectInsight: (InsightModel) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var summaryText: String {
        let titles = node.insights.prefix(3).map(\.title)
        guard !titles.isEmpty else {
            return "\(node.conceptLabel) is a developing subject in this insight map."
        }

        return "\(node.conceptLabel) gathers related insights around \(titles.joined(separator: ", "))."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(node.conceptLabel)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)

                Spacer()

                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AquinasTheme.Colors.placeholderText)
            }

            Text(summaryText)
                .font(.figtreeParagraph)
                .lineSpacing(8)
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .lineLimit(3)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(node.insights.enumerated()), id: \.element.id) { index, insight in
                    Button {
                        onSelectInsight(insight)
                    } label: {
                        HStack(spacing: 12) {
                            DockedCardTextBubbleIcon(size: 14, delay: 0.18 + (Double(index) * 0.04), color: AquinasTheme.Colors.darkGreen)

                            Text(insight.title)
                                .font(.custom("Figtree-Bold", size: 16))
                                .foregroundColor(AquinasTheme.Colors.darkGreen)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insightTreeInsightColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
        .shadow(color: Color(red: 0.13, green: 0.06, blue: 0).opacity(0.15), radius: 24, x: 0, y: 16)
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
