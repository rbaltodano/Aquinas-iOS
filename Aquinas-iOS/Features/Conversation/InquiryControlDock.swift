//
//  InquiryControlDock.swift
//  Aquinas-iOS
//

import SwiftUI

extension Notification.Name {
    static let aquinasMiniScrollButtonVisibilityChanged = Notification.Name("aquinasMiniScrollButtonVisibilityChanged")
}

// MARK: - Bottom Control Dock

/// A single persistent control surface whose contents adapt to Branch and Canvas mode.
struct InquiryControlDock: View {
    let isCanvasMode: Bool
    @Binding var showFilePicker: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var isThinkingEnabled: Bool
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
    /// While a placed midpoint insight is generating, the dock collapses to just the
    /// context control, which spins and reads "Loading".
    var isCanvasInsightLoading: Bool = false
    /// While a Branch-Mode response is generating; spins the context wheel (no "Loading" text).
    var isResponseLoading: Bool = false
    var onMidpointCenter: () -> Void = {}
    var onMidpointPlace: () -> Void = {}
    var onClearCanvasSelection: () -> Void = {}
    var contextWordCount: Int = 0
    // Prototype word-based capacity while the real token limit is unwired.
    var contextWordLimit: Int = 10_000
    var onClearConversation: () -> Void = {}
    var onContextWillOpen: () -> Void = {}

    @State private var thinkingIconDrawID = UUID()
    @State private var canvasActionDrawID = UUID()
    @State private var isScrollButtonVisible = false
    @State private var controlScale: CGFloat = 1
    @State private var isContextCardOpen = false
    @State private var isContextCompacting = false
    @State private var isContextCompactionComplete = false
    @State private var contextCardDragY: CGFloat = 0
    @State private var contextCompactTask: Task<Void, Never>?
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

    /// While a placed midpoint is generating AND nothing else is hovered/selected, the dock
    /// collapses to just the spinning "Loading" context control. Hovering another insight
    /// breaks the collapse so its card + the normal controls return (wheel keeps spinning).
    private var isLoadingCollapsed: Bool {
        isCanvasMode && isCanvasInsightLoading && !hasCanvasHover && !hasSelectedCanvasItems
    }

    private var showsAttachmentControl: Bool {
        !isCanvasMode || showsModelControlsInCanvasMode
    }

    private var showsThinkingControl: Bool {
        !isCanvasMode || showsModelControlsInCanvasMode
    }

    private var controlCount: Int {
        if isLoadingCollapsed {
            return 1 // just the context control (spinning, "Loading")
        }
        if isCanvasMode && isMidpointMode {
            return 2 + 1 // Center + Place + context
        }
        let attachmentCount = showsAttachmentControl ? 1 : 0
        let thinkingCount = showsThinkingControl ? 1 : 0
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
        return attachmentCount + thinkingCount + canvasActionCount + 1 + (showsSendButton ? 1 : 0)
    }

    /// Captures everything that changes the dock's visible controls — including swaps that
    /// keep the same control count but change content width (e.g. the "Add" button ↔ the
    /// "Tap another Insight" hint) — so the capsule resizes with the same spring + scale bump.
    private var controlLayoutKey: String {
        "\(controlCount)|\(isMidpointMode ? 1 : 0)|\(isCanvasInsightLoading ? 1 : 0)|\(hasCanvasHover ? 1 : 0)|\(hasCanvasInsightHover ? 1 : 0)|\(selectedCanvasItemCount)|\(showsSendButton ? 1 : 0)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .center, spacing: 24) {
                if showsAttachmentControl {
                    attachmentButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if showsThinkingControl {
                    thinkingButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if isLoadingCollapsed {
                    // Generating a placed midpoint, nothing hovered — just the spinning context.
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

            if !isCanvasMode {
                scrollToBottomButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // An overlay does not participate in layout, so presenting the card never
        // changes the dock's height or moves the model controls.
        .overlay(alignment: .top) {
            if isContextCardOpen {
                ContextUsageCard(
                    wordCount: contextWordCount,
                    wordLimit: contextWordLimit,
                    isCompacting: isContextCompacting,
                    isCompactionComplete: isContextCompactionComplete,
                    onCompact: beginContextCompaction,
                    onClear: clearConversation,
                    onArrowAppear: contextArrowDidAppear
                )
                // Keep the popup's bottom edge parked just above the dock while
                // its height animates from the full card down to the compact pill.
                .offset(y: (isContextCompacting ? -52 : -146) + contextCardDragY)
                .gesture(contextCardDismissGesture)
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: .scale(scale: 0.35, anchor: .bottom).combined(with: .opacity)
                ))
                .zIndex(20)
            }
        }
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
            contextCompactTask?.cancel()
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

    private var thinkingButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isThinkingEnabled.toggle()
                if isThinkingEnabled { thinkingIconDrawID = UUID() }
            }
        } label: {
            let inactiveThinkingColor = AquinasTheme.Colors.paragraphText.opacity(0.75)
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .semibold))
                    .id(thinkingIconDrawID)
                    .sfSymbolDrawOn()
                Text("Thinking")
                    .font(.custom("Figtree-Bold", size: 14))
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(isThinkingEnabled ? AquinasTheme.Colors.accentGreen : inactiveThinkingColor)
        }
        .buttonStyle(.plain)
    }

    private var contextButton: some View {
        Button {
            if hasSelectedCanvasItems {
                onClearCanvasSelection()
            } else if !isContextCompacting {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
                contextCardDragY = 0
                if !isContextCardOpen { onContextWillOpen() }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    isContextCardOpen.toggle()
                }
            }
        } label: {
            let contextColor = AquinasTheme.Colors.paragraphText.opacity(0.75)
            // Hover/selection are Canvas-Mode concepts — ignore them in Branch Mode so the
            // "Context" label isn't suppressed by stray canvas hover state.
            let canvasHover = isCanvasMode && hasCanvasHover
            let canvasSelected = isCanvasMode && hasSelectedCanvasItems
            // "Loading" only shows in the collapsed state. Hovering another insight (or Branch
            // Mode) drops the label; the wheel itself keeps spinning regardless.
            let showLoadingText = isLoadingCollapsed
            // The wheel spins for canvas insight generation OR a Branch-Mode response.
            let isWheelSpinning = isCanvasInsightLoading || isResponseLoading
            HStack(spacing: 8) {
                // While generating, "Loading" sits on the opposite side of the context symbol.
                if showLoadingText {
                    Text("Loading")
                        .font(.custom("Figtree-Bold", size: 14))
                        .transition(.offset(x: 12).combined(with: .opacity))
                }
                if canvasSelected && !showLoadingText {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    ContextUsageIcon(progress: contextProgress, color: contextColor, isSpinning: isWheelSpinning)
                }
                if !canvasHover && !canvasSelected && !showLoadingText {
                    Text("Context")
                        .font(.custom("Figtree-Bold", size: 14))
                        .transition(.offset(x: -12).combined(with: .opacity))
                }
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(contextColor)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: canvasHover)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: canvasSelected)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showLoadingText)
        }
        .buttonStyle(.plain)
    }

    private var contextProgress: CGFloat {
        guard contextWordLimit > 0 else { return 0 }
        return min(max(CGFloat(contextWordCount) / CGFloat(contextWordLimit), 0), 1)
    }

    private func clearConversation() {
        contextCompactTask?.cancel()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)
        onClearConversation()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isContextCardOpen = false
            isContextCompacting = false
            isContextCompactionComplete = false
        }
    }

    private var contextCardDismissGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !isContextCompacting else { return }
                contextCardDragY = max(0, value.translation.height)
            }
            .onEnded { value in
                guard !isContextCompacting else { return }
                let height = value.translation.height
                let predicted = value.predictedEndTranslation.height
                if height > 100 || predicted > 180 {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        isContextCardOpen = false
                        contextCardDragY = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        contextCardDragY = 0
                    }
                }
            }
    }

    private func beginContextCompaction() {
        guard !isContextCompacting else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isContextCompacting = true
            isContextCompactionComplete = false
        }
        contextCompactTask?.cancel()
        contextCompactTask = Task {
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            await MainActor.run {
                playContextCompactedHaptics()
                withAnimation(.easeInOut(duration: 0.18)) {
                    isContextCompactionComplete = true
                }
            }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    isContextCardOpen = false
                }
            }
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            await MainActor.run {
                isContextCompacting = false
                isContextCompactionComplete = false
            }
        }
    }

    private func contextArrowDidAppear() {
        guard isContextCompacting, !isContextCompactionComplete else { return }
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

    private func dismissContextPopup() {
        guard isContextCardOpen else { return }
        contextCompactTask?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isContextCardOpen = false
            isContextCompacting = false
            isContextCompactionComplete = false
            contextCardDragY = 0
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
            .foregroundColor(selectedCanvasItemCount >= 1 ? AquinasTheme.Colors.accentGreen : AquinasTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectionCountIcon: some View {
        if selectedCanvasItemCount > 0 {
            ZStack {
                Circle()
                    .fill(AquinasTheme.Colors.accentGreen)
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
                        Button("Clear", action: onClear)
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
