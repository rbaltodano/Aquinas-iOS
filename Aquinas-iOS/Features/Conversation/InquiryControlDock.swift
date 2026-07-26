//
//  InquiryControlDock.swift
//  Aquinas-iOS
//

import SwiftUI

extension Notification.Name {
    static let aquinasMiniScrollButtonVisibilityChanged = Notification.Name("aquinasMiniScrollButtonVisibilityChanged")
}

/// Shared open/animation state for the Context popup, owned by whichever screen hosts
/// `InquiryControlDock` (not the dock itself) so the popup can be rendered as a plain
/// ZStack sibling instead of nested inside the dock's `.safeAreaInset` content — content
/// there gets visually clipped/occluded the moment it tries to bleed above its own strip,
/// which is why the popup silently failed to appear at all.
@Observable
final class ContextCardState {
    var isOpen = false
    /// The outside-tap dismiss catcher is armed a beat after the card opens, so the very tap that
    /// opened it isn't caught by the catcher and immediately closes it again.
    var dismissArmed = false
    var isCompacting = false
    var isCompactionComplete = false
    var dragY: CGFloat = 0
    var compactTask: Task<Void, Never>?

    func reset() {
        compactTask?.cancel()
        isOpen = false
        isCompacting = false
        isCompactionComplete = false
        dragY = 0
    }
}

@Observable
final class ModelTasksPopupState {
    var isOpen = false
    var dismissArmed = false

    func reset() {
        isOpen = false
        dismissArmed = false
    }
}

/// Reports the world-space top-center point of the dock's pill, measured via an
/// `anchorPreference` so `ContextCardPopover` can be positioned above the dock correctly
/// even though it renders as a sibling outside the dock's `.safeAreaInset` content.
struct DockPillTopAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>?
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = nextValue() ?? value
    }
}

/// The Context popup card, hosted as a direct ZStack sibling (via `.overlayPreferenceValue`)
/// rather than as an `.overlay()` inside the dock — see `ContextCardState` for why.
struct ContextCardPopover: View {
    let contextCard: ContextCardState
    let wordCount: Int
    var wordLimit: Int = 10_000
    var onClearConversation: () -> Void = {}
    /// Full screen size, measured by the hosting GeometryReader — the tap-catcher is sized to
    /// exactly this instead of an oversized guess, which was quietly corrupting this view's
    /// reported layout size and pushing the actual card off-position/off-screen.
    let screenSize: CGSize
    /// Distance from the top of the screen down to the dock's own top edge. The card is
    /// bottom-aligned inside a box exactly this tall, so it always sits flush above the dock
    /// regardless of the dock's real height — no hand-tuned offset needed.
    let dockTopY: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if contextCard.isOpen {
                if !contextCard.isCompacting {
                    Color.clear
                        .frame(width: screenSize.width, height: screenSize.height)
                        .contentShape(Rectangle())
                        .onTapGesture { if contextCard.dismissArmed { dismissContextCard() } }
                        .onAppear {
                            contextCard.dismissArmed = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                contextCard.dismissArmed = true
                            }
                        }
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ContextUsageCard(
                        wordCount: wordCount,
                        wordLimit: wordLimit,
                        isCompacting: contextCard.isCompacting,
                        isCompactionComplete: contextCard.isCompactionComplete,
                        onCompact: beginContextCompaction,
                        onClear: clearConversation,
                        onArrowAppear: contextArrowDidAppear
                    )
                    .offset(y: contextCard.dragY)
                    .gesture(contextCardDismissGesture)
                    .padding(.bottom, 16)
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .scale(scale: 0.35, anchor: .bottom).combined(with: .opacity)
                    ))
                }
                .frame(width: screenSize.width, height: max(dockTopY, 0), alignment: .bottom)
                .allowsHitTesting(true)
            }
        }
    }

    private func dismissContextCard() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            contextCard.isOpen = false
            contextCard.dragY = 0
        }
    }

    private var contextCardDismissGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !contextCard.isCompacting else { return }
                contextCard.dragY = max(0, value.translation.height)
            }
            .onEnded { value in
                guard !contextCard.isCompacting else { return }
                let height = value.translation.height
                let predicted = value.predictedEndTranslation.height
                if height > 100 || predicted > 180 {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        contextCard.isOpen = false
                        contextCard.dragY = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        contextCard.dragY = 0
                    }
                }
            }
    }

    private func beginContextCompaction() {
        guard !contextCard.isCompacting else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            contextCard.isCompacting = true
            contextCard.isCompactionComplete = false
        }
        contextCard.compactTask?.cancel()
        contextCard.compactTask = Task {
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            await MainActor.run {
                playContextCompactedHaptics()
                withAnimation(.easeInOut(duration: 0.18)) {
                    contextCard.isCompactionComplete = true
                }
            }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    contextCard.isOpen = false
                }
            }
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            await MainActor.run {
                contextCard.isCompacting = false
                contextCard.isCompactionComplete = false
            }
        }
    }

    private func contextArrowDidAppear() {
        guard contextCard.isCompacting, !contextCard.isCompactionComplete else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
    }

    private func playContextCompactedHaptics() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.75)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            generator.prepare()
            generator.impactOccurred(intensity: 0.75)
        }
    }

    private func clearConversation() {
        contextCard.compactTask?.cancel()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)
        onClearConversation()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            contextCard.isOpen = false
            contextCard.isCompacting = false
            contextCard.isCompactionComplete = false
        }
    }
}

/// Convenience wrapper: reads the dock's measured top anchor and positions the popover
/// correctly above it, regardless of the dock's actual height or bottom padding. Chain this
/// directly after `.safeAreaInset(edge: .bottom) { dock }` on the same view — NOT inside the
/// inset's own content closure.
extension View {
    func contextCardOverlay(
        _ contextCard: ContextCardState,
        wordCount: Int,
        wordLimit: Int = 10_000,
        onClearConversation: @escaping () -> Void = {}
    ) -> some View {
        overlayPreferenceValue(DockPillTopAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    ContextCardPopover(
                        contextCard: contextCard,
                        wordCount: wordCount,
                        wordLimit: wordLimit,
                        onClearConversation: onClearConversation,
                        screenSize: proxy.size,
                        dockTopY: proxy[anchor].y
                    )
                }
            }
        }
    }
}

private struct ModelTasksPopover: View {
    let popupState: ModelTasksPopupState
    let modelTasks: ModelTaskQueue
    let screenSize: CGSize
    let dockTopY: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if popupState.isOpen {
                Color.clear
                    .frame(width: screenSize.width, height: screenSize.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if popupState.dismissArmed {
                            dismiss()
                        }
                    }
                    .onAppear {
                        popupState.dismissArmed = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            popupState.dismissArmed = true
                        }
                    }
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if popupState.isOpen {
                    ModelTasksCard(modelTasks: modelTasks)
                        .frame(width: min(345, max(screenSize.width - 32, 0)))
                        .padding(.bottom, 16)
                        .transition(.bottomDockCard)
                }
            }
            .frame(
                width: screenSize.width,
                height: max(dockTopY, 0),
                alignment: .bottom
            )
        }
        .allowsHitTesting(popupState.isOpen)
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            popupState.reset()
        }
    }
}

private struct ModelTasksCard: View {
    let modelTasks: ModelTaskQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Model Tasks")
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.headingText)

                if !modelTasks.allTasks.isEmpty {
                    Spacer()

                    Text("\(modelTasks.completedTasks.count) of \(modelTasks.totalCount)")
                        .font(.custom("Figtree-Regular", size: 14))
                        .monospacedDigit()
                        .transition(.opacity)
                }
            }

            if modelTasks.allTasks.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 12, weight: .regular))
                        .frame(width: 12, height: 12)

                    Text("Model is current idle...")
                        .font(.custom("Figtree-Regular", size: 14))
                        .lineLimit(1)
                }
                .frame(minHeight: 28)
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(modelTasks.allTasks) { task in
                        ModelTaskRow(
                            task: task,
                            onStop: modelTasks.stopCurrent,
                            onRemove: {
                                modelTasks.removeUpcoming(id: task.id)
                            },
                            onMove: { draggedID, placeAfterTarget in
                                modelTasks.moveUpcoming(
                                    id: draggedID,
                                    relativeTo: task.id,
                                    placeAfterTarget: placeAfterTarget
                                )
                                UIImpactFeedbackGenerator(style: .light)
                                    .impactOccurred(intensity: 0.65)
                            }
                        )
                        .transition(.opacity)
                    }
                }
                .transition(.opacity)
            }
        }
        .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
        .animation(.easeInOut(duration: 0.24), value: modelTasks.allTasks)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AquinasTheme.Colors.darkBrown.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ModelTaskRow: View {
    let task: ModelTaskSnapshot
    let onStop: () -> Void
    let onRemove: () -> Void
    let onMove: (_ draggedID: UUID, _ placeAfterTarget: Bool) -> Void

    @ViewBuilder
    var body: some View {
        if task.phase == .upcoming {
            rowContent
                .draggable(task.id.uuidString)
                .dropDestination(for: String.self) { values, location in
                    guard let rawID = values.first,
                          let draggedID = UUID(uuidString: rawID),
                          draggedID != task.id else {
                        return false
                    }
                    onMove(draggedID, location.y > 14)
                    return true
                }
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                taskStatusIcon

                Text(task.title)
                    .font(.custom("Figtree-Regular", size: 14))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            taskAction
        }
        .frame(minHeight: 28)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var taskStatusIcon: some View {
        ZStack {
            switch task.phase {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AquinasTheme.Colors.headingText)
                    .transition(.opacity)
            case .current:
                ContextUsageIcon(
                    progress: 0,
                    color: AquinasTheme.Colors.paragraphText.opacity(0.75),
                    isSpinning: true
                )
                .transition(.opacity)
            case .upcoming:
                Image(systemName: "circle.dotted")
                    .font(.system(size: 14, weight: .regular))
                    .transition(.opacity)
            }
        }
        .frame(width: 14, height: 14)
        .animation(.easeInOut(duration: 0.2), value: task.phase)
    }

    @ViewBuilder
    private var taskAction: some View {
        ZStack {
            switch task.phase {
            case .completed:
                EmptyView()
            case .current:
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop current model task")
                .transition(.opacity)
            case .upcoming:
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.5))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove queued model task")
                .transition(.opacity)
            }
        }
        .frame(width: 14, height: 14)
        .animation(.easeInOut(duration: 0.2), value: task.phase)
    }
}

extension View {
    func modelTasksOverlay(
        _ popupState: ModelTasksPopupState,
        modelTasks: ModelTaskQueue
    ) -> some View {
        overlayPreferenceValue(DockPillTopAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    ModelTasksPopover(
                        popupState: popupState,
                        modelTasks: modelTasks,
                        screenSize: proxy.size,
                        dockTopY: proxy[anchor].y
                    )
                }
            }
        }
    }
}

// MARK: - Bottom Control Dock

private struct ModelStatusButton: View {
    let modelTasks: ModelTaskQueue
    let action: () -> Void

    private var isActive: Bool {
        modelTasks.isBusy
    }

    private var totalTaskCount: Int {
        modelTasks.totalCount
    }

    private var currentTaskNumber: Int {
        min(modelTasks.currentPosition, max(totalTaskCount, 1))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isActive && totalTaskCount > 1 {
                    Text("\(currentTaskNumber)/\(totalTaskCount)")
                        .monospacedDigit()
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                if isActive {
                    Text("Thinking")
                        .modifier(
                            ThinkingShimmer(
                                isActive: true,
                                color: AquinasTheme.Colors.lightGreen
                            )
                        )
                        .transition(.opacity)
                } else {
                    Text("Idle")
                        .foregroundColor(AquinasTheme.Colors.headingText)
                        .transition(.opacity)
                }
            }
            .font(.custom("Figtree-SemiBold", size: 14))
            .foregroundColor(AquinasTheme.Colors.lightGreen)
            .frame(minHeight: 21)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.25), value: isActive)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: totalTaskCount)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: currentTaskNumber)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityStatus)
    }

    private var accessibilityStatus: String {
        guard isActive else { return String(localized: "Model status: Idle") }
        guard totalTaskCount > 1 else { return String(localized: "Model status: Thinking") }
        return String(
            localized: "Model status: task \(currentTaskNumber) of \(totalTaskCount), Thinking"
        )
    }

}

/// A single persistent control surface whose contents adapt to Branch and Canvas mode.
struct InquiryControlDock: View {
    let isCanvasMode: Bool
    @Binding var showFilePicker: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var selectedPersonality: String
    @Binding var isPersonalityMenuOpen: Bool
    let isAtBottom: Bool
    var showsModelControlsInCanvasMode: Bool = false
    var isKeyboardOpen: Bool = false
    var showsSendButton: Bool = false
    var hasCanvasHover: Bool = false
    var hasCanvasInsightHover: Bool = false
    var hasSelectedCanvasItems: Bool = false
    var selectedCanvasItemCount: Int = 0
    var onScrollToBottom: () -> Void
    var onViewEntireCanvas: () -> Void
    var onOpenInsights: () -> Void
    var onSend: () -> Void = {}
    var onSelectCanvasItem: () -> Void = {}
    var onCreateCanvasConcept: () -> Void = {}
    var onInquireConnection: () -> Void = {}
    var onQuoteCanvasItem: () -> Void = {}
    var onMidpointConcepts: () -> Void = {}
    var isMidpointMode: Bool = false
    /// While a placed midpoint insight is generating, the dock hides its canvas actions.
    var isCanvasInsightLoading: Bool = false
    /// Shared serialized model work. Drives both the status control and its task popup.
    var modelTasks: ModelTaskQueue? = nil
    var onModelStatusTap: () -> Void = {}
    var onMidpointCenter: () -> Void = {}
    var onMidpointPlace: () -> Void = {}
    var onClearCanvasSelection: () -> Void = {}
    var contextWordCount: Int = 0
    // Prototype word-based capacity while the real token limit is unwired.
    var contextWordLimit: Int = 10_000
    var onClearConversation: () -> Void = {}
    var onContextWillOpen: () -> Void = {}
    /// Owned by the hosting screen; the popup itself renders elsewhere via `.contextCardOverlay(_:)`
    /// so it isn't clipped by this dock's `.safeAreaInset` content. See `ContextCardState`.
    let contextCard: ContextCardState

    @State private var canvasActionDrawID = UUID()
    @State private var isScrollButtonVisible = false
    @State private var controlScale: CGFloat = 1
    @State private var addFlashOpacity: CGFloat = 1

    /// Flash the Add button while in Select mode with an insight hovered, hinting it can be added.
    private var shouldFlashAdd: Bool {
        hasSelectedCanvasItems && hasCanvasHover
    }

    private func startAddFlashIfNeeded() {
        if shouldFlashAdd {
            addFlashOpacity = 1
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                addFlashOpacity = 0.5
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { addFlashOpacity = 1 }
        }
    }

    /// While a placed midpoint is generating AND nothing else is hovered/selected, canvas
    /// actions are hidden while Model Status and the context gauge remain visible.
    private var isLoadingCollapsed: Bool {
        isCanvasMode && isCanvasInsightLoading && !hasCanvasHover && !hasSelectedCanvasItems
    }

    private var showsAttachmentControl: Bool {
        !isCanvasMode || showsModelControlsInCanvasMode
    }

    private var showsModelStatusControl: Bool {
        modelTasks != nil && !(isCanvasMode && hasCanvasInsightHover)
    }

    private var controlCount: Int {
        if isLoadingCollapsed {
            return (showsModelStatusControl ? 1 : 0) + 1
        }
        if isCanvasMode && isMidpointMode {
            return (showsModelStatusControl ? 1 : 0) + 2 + 1
        }
        let attachmentCount = showsAttachmentControl ? 1 : 0
        let modelStatusCount = showsModelStatusControl ? 1 : 0
        let canvasActionCount: Int
        if !isCanvasMode {
            canvasActionCount = 0
        } else if hasSelectedCanvasItems {
            if selectedCanvasItemCount == 2 {
                canvasActionCount = 3 // Select + Quote + Midpoint
            } else if selectedCanvasItemCount > 2 {
                canvasActionCount = 2 // Select + Midpoint
            } else {
                canvasActionCount = 1 // Select only
            }
        } else if hasCanvasInsightHover {
            canvasActionCount = 3 // Select + Quote + Make Node
        } else if hasCanvasHover {
            canvasActionCount = 2 // Select + Quote
        } else {
            canvasActionCount = 0
        }
        return attachmentCount + modelStatusCount + canvasActionCount + 1 + (showsSendButton ? 1 : 0)
    }

    /// Captures everything that changes the dock's visible controls — including swaps that
    /// keep the same control count but change content width (e.g. the "Add" button ↔ the
    /// "Tap another Insight" hint) — so the capsule resizes with the same spring + scale bump.
    private var controlLayoutKey: String {
        "\(controlCount)|\(modelTasks?.pendingCount ?? 0)|\(isMidpointMode ? 1 : 0)|\(isCanvasInsightLoading ? 1 : 0)|\(hasCanvasHover ? 1 : 0)|\(hasCanvasInsightHover ? 1 : 0)|\(selectedCanvasItemCount)|\(showsSendButton ? 1 : 0)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .center, spacing: 24) {
                if showsAttachmentControl {
                    attachmentButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if showsModelStatusControl, let modelTasks {
                    ModelStatusButton(
                        modelTasks: modelTasks,
                        action: onModelStatusTap
                    )
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if isLoadingCollapsed {
                    // Generating a placed midpoint, nothing hovered — keep only status + context.
                    EmptyView()
                } else if isCanvasMode && isMidpointMode {
                    canvasActionButton(title: "Center", icon: "lines.measurement.horizontal", action: onMidpointCenter)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    canvasActionButton(title: "Place", icon: "arrow.down", action: onMidpointPlace)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else if isCanvasMode && (hasCanvasHover || hasSelectedCanvasItems) {
                    if hasSelectedCanvasItems && hasCanvasHover {
                        // Selection mode + hovering an addable insight/node:
                        // the Add button is the only control present.
                        selectCanvasActionButton
                            .opacity(shouldFlashAdd ? addFlashOpacity : 1)
                            .onAppear { startAddFlashIfNeeded() }
                            .onChange(of: shouldFlashAdd) { _, _ in startAddFlashIfNeeded() }
                    } else if hasSelectedCanvasItems {
                        // Selection mode, nothing hovered: hint (1 selected) or the
                        // selection actions (Quote + Midpoint for 2, Midpoint for 3+).
                        if selectedCanvasItemCount == 1 {
                            Text("Tap another Insight for actions")
                                .font(.custom("Figtree-Bold", size: 14))
                                .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                                .fixedSize()
                                .transition(.opacity)
                        } else if selectedCanvasItemCount == 2 {
                            canvasActionButton(title: "Quote", icon: "arrow.turn.down.right", action: onInquireConnection)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                            canvasActionButton(title: "Midpoint", icon: "graph.2d", action: onMidpointConcepts)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        } else {
                            canvasActionButton(title: "Midpoint", icon: "graph.2d", action: onMidpointConcepts)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    } else {
                        // No selection yet — entry point while hovering an insight/node.
                        selectCanvasActionButton
                        if hasCanvasInsightHover {
                            canvasActionButton(title: "Quote", icon: "arrow.turn.down.right", action: onQuoteCanvasItem)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                            canvasActionButton(title: "Make Node", icon: "move.3d", action: onCreateCanvasConcept)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        } else if hasCanvasHover {
                            canvasActionButton(title: "Quote", icon: "arrow.turn.down.right", action: onQuoteCanvasItem)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                }

                contextButton

                if showsSendButton {
                    sendButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .fixedSize(horizontal: true, vertical: true)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
            .scaleEffect(controlScale)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: controlLayoutKey)
            // Reports this pill's top-center point so the popup — rendered elsewhere via
            // `.contextCardOverlay(_:)` to escape this dock's `.safeAreaInset` clipping —
            // can still be positioned correctly above it.
            .anchorPreference(key: DockPillTopAnchorKey.self, value: .top) { $0 }

            if !isCanvasMode {
                scrollToBottomButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, isKeyboardOpen ? 8 : 24)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isKeyboardOpen)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showsSendButton)
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: AquinasTheme.Colors.canvas.opacity(0.95), location: 0),
                    .init(color: AquinasTheme.Colors.canvas.opacity(0), location: 1)
                ],
                startPoint: UnitPoint(x: 0.5, y: 0.52),
                endPoint: UnitPoint(x: 0.5, y: 0)
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
        .onAppear {
            isScrollButtonVisible = !isAtBottom
        }
        .onReceive(NotificationCenter.default.publisher(for: .aquinasMiniScrollButtonVisibilityChanged)) { notification in
            guard let isVisible = notification.userInfo?["isVisible"] as? Bool else { return }
            isScrollButtonVisible = isVisible
        }
        .onChange(of: controlLayoutKey) { _, _ in
            controlScale = 1.05
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                controlScale = 1
            }
        }
        .onChange(of: hasCanvasHover) { _, selected in
            if selected { canvasActionDrawID = UUID() }
        }
        .onChange(of: hasCanvasInsightHover) { _, isHoveringInsight in
            if isHoveringInsight { dismissContextPopup() }
        }
        .onDisappear {
            contextCard.compactTask?.cancel()
        }
    }

    private var attachmentButton: some View {
        Menu {
            Button {
                showCamera = true
            } label: {
                Label("Camera", systemImage: "camera")
            }

            Button {
                showPhotoPicker = true
            } label: {
                Label("Photo", systemImage: "photo")
            }

            Button {
                showFilePicker = true
            } label: {
                Label("File", systemImage: "doc")
            }

            Button {
                onOpenInsights()
            } label: {
                Label("Insights", systemImage: "text.bubble")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .frame(width: 16, height: 16)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var contextButton: some View {
        Button {
            if !contextCard.isCompacting {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
                contextCard.dragY = 0
                if !contextCard.isOpen { onContextWillOpen() }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    contextCard.isOpen.toggle()
                }
            }
        } label: {
            let contextColor = AquinasTheme.Colors.paragraphText.opacity(0.75)
            HStack(spacing: 8) {
                ContextUsageIcon(progress: contextProgress, color: contextColor)
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(contextColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Conversation context")
    }

    private var contextProgress: CGFloat {
        guard contextWordLimit > 0 else { return 0 }
        return min(max(CGFloat(contextWordCount) / CGFloat(contextWordLimit), 0), 1)
    }

    private func dismissContextPopup() {
        guard contextCard.isOpen else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            contextCard.reset()
        }
    }

    private func canvasActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .id("\(title)-\(canvasActionDrawID)")
                    .sfSymbolDrawOn()
                Text(title)
                    .font(.custom("Figtree-Bold", size: 14))
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(.plain)
    }

    private var selectCanvasActionButton: some View {
        Button(action: onSelectCanvasItem) {
            HStack(spacing: 8) {
                selectionCountIcon
                Text(selectedCanvasItemCount >= 1 ? "Add concept to selection" : "Select")
                    .font(.custom("Figtree-Bold", size: 14))
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(selectedCanvasItemCount >= 1 ? AquinasTheme.Colors.lightGreen : AquinasTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectionCountIcon: some View {
        if selectedCanvasItemCount > 0 {
            ZStack {
                Circle()
                    .fill(AquinasTheme.Colors.lightGreen)
                Text("\(min(selectedCanvasItemCount, 99))")
                    .font(.custom("Figtree-Bold", size: selectedCanvasItemCount > 9 ? 7 : 8))
                    .foregroundColor(AquinasTheme.Colors.canvasSecondary)
            }
            .frame(width: 14, height: 14)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
        } else {
            Image(systemName: "circle.dashed")
                .font(.system(size: 14, weight: .semibold))
                .id("select-\(canvasActionDrawID)")
                .sfSymbolDrawOn()
        }
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
    }

    private var scrollToBottomButton: some View {
        Button(action: onScrollToBottom) {
            Image(systemName: "arrow.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(Color(hex: 0xFFFAF0))
                .frame(width: 24, height: 24)
                .background(AquinasTheme.Colors.lightBrown)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(y: isScrollButtonVisible ? -36 : -28)
        .opacity(isScrollButtonVisible ? 1 : 0)
        .allowsHitTesting(isScrollButtonVisible)
        .animation(.easeInOut(duration: 0.16), value: isScrollButtonVisible)
    }
}

private struct ContextUsageIcon: View {
    let progress: CGFloat
    let color: Color
    var isSpinning: Bool = false

    private enum Phase { case idle, spinning, settling }

    @State private var phase: Phase = .idle
    @State private var startDate = Date()
    @State private var settleAngle: Double = 0   // angle (deg) used while not actively spinning
    @State private var arc: Double = 0           // 0 = progress ring, 1 = quarter spinner
    @State private var settleTask: Task<Void, Never>? = nil

    private let revDuration: Double = 1.1         // seconds per revolution
    private let settleDuration: Double = 1.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.35), lineWidth: 1.5)
            TimelineView(.animation(paused: phase == .idle)) { timeline in
                let angle = phase == .spinning
                    ? timeline.date.timeIntervalSince(startDate) * 360.0 / revDuration
                    : settleAngle
                let trimEnd = 0.25 * arc + Double(min(max(progress, 0), 1)) * (1 - arc)
                Circle()
                    .trim(from: 0, to: trimEnd)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90 + angle))
            }
        }
        .frame(width: 14, height: 14)
        .onAppear { if isSpinning { beginSpin() } }
        .onChange(of: isSpinning) { _, spinning in
            if spinning { beginSpin() } else { endSpin() }
        }
    }

    private func beginSpin() {
        settleTask?.cancel()
        startDate = Date()
        phase = .spinning
        withAnimation(.easeInOut(duration: 0.3)) { arc = 1 }
    }

    private func endSpin() {
        // Continue clockwise to the next upright position, then morph the arc back to the ring.
        let elapsed = Date().timeIntervalSince(startDate)
        let current = elapsed * 360.0 / revDuration
        let target = (current / 360.0).rounded(.up) * 360.0
        settleAngle = current
        phase = .settling
        withAnimation(.easeOut(duration: settleDuration)) {
            settleAngle = target
            arc = 0
        }
        settleTask = Task {
            try? await Task.sleep(for: .seconds(settleDuration))
            if !Task.isCancelled { phase = .idle }
        }
    }
}

private struct ContextUsageCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let wordCount: Int
    let wordLimit: Int
    let isCompacting: Bool
    let isCompactionComplete: Bool
    var onCompact: () -> Void
    var onClear: () -> Void
    var onArrowAppear: () -> Void

    @State private var hasAppeared = false
    @State private var showClearConfirmation = false

    private var progress: CGFloat {
        guard wordLimit > 0 else { return 0 }
        return min(max(CGFloat(wordCount) / CGFloat(wordLimit), 0), 1)
    }

    private var visualProgress: CGFloat {
        guard wordCount > 0 else { return 0 }
        // Prototype-only visual floor: the real word count stays accurate above,
        // but the 10k placeholder limit makes normal conversations look empty.
        return max(progress, 0.72)
    }

    private var progressTrackColor: Color {
        colorScheme == .dark
            ? Color(hex: 0x130F0C)
            : .white
    }

    private var progressTrackBorderColor: Color {
        colorScheme == .dark
            ? Color(hex: 0xFFFAF0, alpha: 0.08)
            : AquinasTheme.Colors.darkBrown.opacity(0.15)
    }

    private var progressFillColor: Color {
        colorScheme == .dark
            ? Color(hex: 0xFFFAF0, alpha: 0.55)
            : AquinasTheme.Colors.paragraphText.opacity(0.5)
    }

    var body: some View {
        Group {
            if isCompacting {
                if isCompactionComplete {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                            .sfSymbolDrawOn()
                        Text("Compacted")
                            .font(.custom("Figtree-SemiBold", size: 14))
                            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                    }
                    .transition(.opacity)
                } else {
                    HStack(spacing: 8) {
                        ContextCompactingIcon(onAppearCycle: onArrowAppear)
                        Text("Compacting")
                            .font(.custom("Figtree-SemiBold", size: 14))
                            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                    }
                    .transition(.opacity)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Context")
                                .font(.custom("Figtree-Bold", size: 18))
                                .foregroundColor(AquinasTheme.Colors.headingText)
                            Spacer()
                            Text("\(formatted(wordCount)) / \(formatted(wordLimit))")
                                .font(.custom("Figtree-Bold", size: 14))
                                .monospacedDigit()
                        }
                        .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(progressTrackColor)
                                    .overlay(Capsule().stroke(progressTrackBorderColor, lineWidth: 1))
                                Capsule()
                                    .fill(progressFillColor)
                                    .frame(width: visualProgress > 0 ? max(geometry.size.width * visualProgress, 8) : 0)
                                    .animation(.easeInOut(duration: 0.65), value: visualProgress)
                            }
                        }
                        .frame(height: 2)
                    }

                    HStack {
                        Button("Compact", action: onCompact)
                        Spacer()
                        Button("Clear") { showClearConfirmation = true }
                    }
                    .font(.custom("Figtree-Bold", size: 14))
                    .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .padding(isCompacting ? 14 : 32)
        .frame(width: isCompacting ? 126 : 355, height: isCompacting ? 44 : nil)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: isCompacting ? 22 : 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isCompacting ? 22 : 36, style: .continuous)
                .stroke(AquinasTheme.Colors.darkBrown.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.13, green: 0.06, blue: 0).opacity(0.15), radius: 24, x: 0, y: 16)
        .scaleEffect(hasAppeared ? 1 : 0.35, anchor: .bottom)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isCompacting)
        .onAppear {
            hasAppeared = false
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    hasAppeared = true
                }
            }
        }
        .alert("Clear conversation context?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive, action: onClear)
        } message: {
            Text("This removes every question and response in this conversation and starts it fresh, so the model no longer has any of the earlier context to build on. Insights you've saved are kept. This can't be undone.")
        }
    }

    private func formatted(_ count: Int) -> String {
        if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

private struct ContextCompactingIcon: View {
    var onAppearCycle: () -> Void

    @State private var rotation = Double([0, 45, 90, 135, 180, 225, 270].randomElement() ?? 0)
    @State private var iconOpacity: Double = 0
    @State private var iconScale: CGFloat = 0.86
    @State private var iconBlur: CGFloat = 4

    var body: some View {
        Image(systemName: "line.diagonal.trianglehead.up.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
            .rotationEffect(.degrees(rotation))
            .opacity(iconOpacity)
            .scaleEffect(iconScale)
            .blur(radius: iconBlur)
            .frame(width: 16, height: 16)
            .task {
                while !Task.isCancelled {
                    onAppearCycle()
                    withAnimation(.easeOut(duration: 0.15)) {
                        iconOpacity = 1
                        iconScale = 1
                        iconBlur = 0
                    }
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeIn(duration: 0.15)) {
                        iconOpacity = 0
                        iconScale = 0.86
                        iconBlur = 4
                    }
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    let directions = [0, 45, 90, 135, 180, 225, 270].map(Double.init)
                    rotation = directions.filter { $0 != rotation }.randomElement() ?? 0
                }
            }
    }
}
