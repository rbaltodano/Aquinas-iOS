//
//  InsightQuestionBar.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit
import Combine

// MARK: - Ephemeral Message

struct EphemeralMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var isComplete: Bool
    var contextInsight: InsightModel? = nil
}

// MARK: - ViewModel

@MainActor
final class InsightQuestionBarViewModel: ObservableObject {
    @Published var messages: [EphemeralMessage] = []
    @Published var isThinking: Bool = false
    @Published var inputText: String = ""

    private var pendingAssistantID: UUID?
    private(set) var streamingTask: Task<Void, Never>?

    var hasResponse: Bool {
        messages.contains { $0.role == .assistant && $0.isComplete }
    }

    // Prototype response — replace with real API call when backend is wired.
    private static let simulatedResponse = """
    Thomas Aquinas is one of the most influential figures in western thought. Often referred to as the Doctor Angelicus (the Angelic Doctor), he is the primary architect of [Thomism](aq://thomism), a philosophical system that synthesized Aristotelian logic with Christian doctrine. The Didache (pronounced DID-ah-kay), also known as "The Teaching of the Twelve Apostles," is one of the most significant documents from the early Christian era. It's essentially the first church manual — a concise guide on ethics, rituals, and organizational hierarchy. It comes from the same root as the English word "didactic."
    """

    func send(contextInsight: InsightModel?) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        inputText = ""

        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            messages.append(EphemeralMessage(role: .user, text: text, isComplete: true, contextInsight: contextInsight))
        }
        isThinking = true

        let assistantMsg = EphemeralMessage(role: .assistant, text: "", isComplete: false)
        pendingAssistantID = assistantMsg.id
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            messages.append(assistantMsg)
        }

        let pendingID = assistantMsg.id
        streamingTask?.cancel()
        streamingTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            self.isThinking = false
            if let idx = self.messages.firstIndex(where: { $0.id == pendingID }) {
                self.messages[idx].text = Self.simulatedResponse
                self.messages[idx].isComplete = true
            }
            self.pendingAssistantID = nil
        }
    }

    func reset() {
        streamingTask?.cancel()
        streamingTask = nil
        messages = []
        isThinking = false
        inputText = ""
        pendingAssistantID = nil
    }
}

// MARK: - Insight Question Bar

struct InsightQuestionBar: View {
    @Binding var contextInsight: InsightModel?
    var inputFont: ConversationFontOption = .serif
    var conversationFontSize: ConversationFontSizeOption = .small
    var onSaveThread: (([EphemeralMessage]) -> Void)? = nil
    var onOpen: (() -> Void)? = nil
    var onKeyboardActiveChange: ((Bool) -> Void)? = nil
    var onCollapse: (() -> Void)? = nil
    var focusTrigger: Int = 0
    var expandTrigger: Int = 0

    @StateObject private var viewModel = InsightQuestionBarViewModel()
    @State private var isExpanded: Bool = false
    @State private var isBarOpen: Bool = false      // drives layout; focus fires after render
    @FocusState private var isInputFocused: Bool
    @FocusState private var isFollowUpFocused: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var streamedMessageIDs: Set<UUID> = []
    @State private var isScrolledToBottom: Bool = true
    @State private var swipeUpDrag: CGFloat = 0
    @State private var swipeHapticFired: Bool = false

    private var expandedHeight: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.height ?? 800) * 0.80
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isExpanded {
                expandedDrawer
                    .transition(.move(edge: .bottom))
            } else {
                collapsedBar
                    .offset(y: -swipeUpDrag)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: isExpanded)
        .onChange(of: expandTrigger) { _, _ in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                isExpanded = true
            }
        }
    }

    // MARK: - Collapsed Bar

    // Single view tree — layout direction animates row → column via VStack spacing.
    // The TextField is always present so focus works without timing tricks.
    // cornerRadius: 1000 renders like Capsule() but is animatable → smooth morph to 24.
    private var collapsedBar: some View {
        VStack(alignment: isBarOpen ? .center : .leading, spacing: isBarOpen ? 8 : 0) {


            // Input row — always rendered
            HStack(spacing: 12) {
                ZStack(alignment: isBarOpen ? .center : .leading) {
                    // Thinking shimmer overlays the (hidden) TextField in collapsed+thinking state
                    if !isBarOpen && viewModel.isThinking {
                        Text("Thinking...")
                            .font(inputFont.textFont(size: conversationFontSize))
                            .modifier(ThinkingShimmer(isActive: true, color: AquinasTheme.Colors.primaryReadable))
                    }

                    TextField("Ask Theo a question...", text: $viewModel.inputText, axis: .vertical)
                        .focused($isInputFocused)
                        .font(inputFont.textFont(size: conversationFontSize))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .multilineTextAlignment(isBarOpen ? .center : .leading)
                        .lineLimit(1...6)
                        .frame(maxWidth: .infinity)
                        .tint(AquinasTheme.Colors.primaryReadable)
                        .submitLabel(.send)
                        .onSubmit { submitQuestion() }
                        .onChange(of: viewModel.inputText) { _, newValue in
                            if newValue.last == "\n" {
                                viewModel.inputText = String(newValue.dropLast())
                                submitQuestion()
                            }
                        }
                        .disabled(viewModel.isThinking && !isBarOpen)
                        .opacity((!isBarOpen && viewModel.isThinking) ? 0 : 1)
                }
                .frame(maxWidth: .infinity)

                // Chip on the right in idle — shows icon + title, transitions to top row when focused
                if !isBarOpen, let insight = contextInsight {
                    insightChip(title: insight.title)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isBarOpen ? .center : .leading)
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
        .background(AquinasTheme.Colors.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isBarOpen)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: contextInsight?.id)
        // Focus state drives isBarOpen — TextField handles taps natively
        .onChange(of: isInputFocused) { _, focused in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                isBarOpen = focused
            }
            if focused { onOpen?() }
            onKeyboardActiveChange?(focused)
        }
        // Tap while thinking (TextField is disabled) → re-expand drawer
        .onTapGesture {
            if viewModel.isThinking && !isBarOpen {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { isExpanded = true }
            }
        }
        // External focus request from card swipe-down gesture
        .onChange(of: focusTrigger) { _, _ in
            isInputFocused = true
        }
        // Swipe down → dismiss keyboard; swipe up → open mini conversation (with live drag + haptic)
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    let isVertical = abs(value.translation.width) < abs(value.translation.height)
                    guard isVertical, !viewModel.messages.isEmpty else { return }
                    let upAmount = max(0, -value.translation.height)
                    guard upAmount > 0 else { return }
                    // Rubber-band the bar upward as the finger drags
                    swipeUpDrag = upAmount * 0.45
                    // Fire haptic exactly once when crossing the threshold
                    if upAmount > 50 && !swipeHapticFired {
                        swipeHapticFired = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } else if upAmount <= 50 {
                        swipeHapticFired = false
                    }
                }
                .onEnded { value in
                    let isVertical = abs(value.translation.width) < abs(value.translation.height)
                    defer {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { swipeUpDrag = 0 }
                        swipeHapticFired = false
                    }
                    guard isVertical else { return }
                    if value.translation.height > 60 {
                        isInputFocused = false
                    } else if swipeHapticFired {
                        // Past threshold — open conversation thread
                        isInputFocused = false
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            isExpanded = true
                        }
                    }
                }
        )
    }

    // MARK: - Expanded Drawer

    private var expandedDrawer: some View {
        VStack(spacing: 8) {

            // Drag handle — outside the container
            RoundedRectangle(cornerRadius: 3)
                .fill(AquinasTheme.Colors.brownBorder.opacity(0.5))
                .frame(width: 36, height: 5)
                .gesture(collapseGesture)
                .contentShape(Rectangle().inset(by: -16))

            // Conversation thread
            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                                messageRow(message, index: index)
                                    .id(message.id)
                                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                            }

                            // Inline follow-up — chained below the last response bubble
                            if viewModel.hasResponse && !viewModel.isThinking {
                                inlineFollowUpField
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                    .id("q-bar-follow-up")
                            }

                            Color.clear
                                .frame(height: 32)
                                .id("q-bar-bottom")
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: QBarBottomFrameKey.self,
                                            value: geo.frame(in: .named("q-bar-scroll")).maxY
                                        )
                                    }
                                )
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 16)
                        .padding(.bottom, 248)
                    }
                    .coordinateSpace(name: "q-bar-scroll")
                    .onAppear {
                        proxy.scrollTo("q-bar-bottom", anchor: .bottom)
                    }
                    .onPreferenceChange(QBarBottomFrameKey.self) { maxY in
                        // maxY ≤ 0 means the spacer has scrolled above the visible area
                        isScrolledToBottom = maxY > 0
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        isScrolledToBottom = true
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo("q-bar-bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.isThinking) { _, _ in
                        withAnimation { proxy.scrollTo("q-bar-bottom", anchor: .bottom) }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                        if isFollowUpFocused {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                proxy.scrollTo("q-bar-bottom", anchor: .bottom)
                            }
                        }
                    }

                    // Scroll-to-bottom arrow — mirrors CurrentConversation style
                    if !isScrolledToBottom {
                        Button {
                            isScrolledToBottom = true
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                proxy.scrollTo("q-bar-bottom", anchor: .bottom)
                            }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(Color(hex: 0xFFFAF0))
                                .frame(width: 24, height: 24)
                                .background(AquinasTheme.Colors.lightBrown)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 12)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.16), value: isScrolledToBottom)
            }
            .frame(maxWidth: .infinity)
            .background(AquinasTheme.Colors.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
            )

        }
        .frame(height: expandedHeight + max(0, -dragOffset), alignment: .top)
        .frame(maxWidth: .infinity)
        .offset(y: max(0, dragOffset))
        .gesture(collapseGesture)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: viewModel.hasResponse)
    }

    // MARK: - Message Row

    @ViewBuilder
    private func messageRow(_ message: EphemeralMessage, index: Int) -> some View {
        switch message.role {
        case .user:
            VStack(spacing: 0) {
                // Connector line for all messages after the first
                if index > 0 {
                    Rectangle()
                        .fill(AquinasTheme.Colors.divider)
                        .frame(width: 1, height: 25)
                        .padding(.vertical, 16)
                }
                // Insight chip — shown if this question had a context insight
                if let insight = message.contextInsight {
                    BranchContextChip(
                        title: insight.title,
                        icon: "text.bubble.fill",
                        isFilled: true,
                        fillColor: AquinasTheme.Colors.canvasSecondary,
                        animatesAppearance: false
                    )
                    .padding(.bottom, 12)
                }
                Text(message.text)
                    .font(inputFont.textFont(size: conversationFontSize))
                    .lineSpacing(8)
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)

        case .assistant:
            EphemeralResponseCard(
                message: message,
                shouldStream: !streamedMessageIDs.contains(message.id),
                onStreamFinished: { streamedMessageIDs.insert(message.id) }
            )
            .onAppear {
                // Already complete when drawer reopens = already streamed → skip animation
                if message.isComplete { streamedMessageIDs.insert(message.id) }
            }
        }
    }

    // MARK: - Ephemeral Response Card

    /// Replicates the ModelResponseCard thinking-pill → full-card transition
    /// for the mini ephemeral conversation inside the drawer.
    private struct EphemeralResponseCard: View {
        let message: EphemeralMessage
        var shouldStream: Bool = true
        var onStreamFinished: (() -> Void)? = nil

        private let brandBrown = AquinasTheme.Colors.primaryReadable
        private let chatBubbleColor = AquinasTheme.Colors.card

        var body: some View {
            VStack(spacing: 0) {
                // Connector line above every assistant message
                Rectangle()
                    .fill(AquinasTheme.Colors.divider)
                    .frame(width: 1, height: 30)
                    .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 0) {
                    // "Thinking…" shimmer → "Show Thinking >" when done
                    HStack(spacing: 6) {
                        Text("Thinking...")
                            .font(.figtreeParagraphLarge)
                            .fontWeight(.bold)
                            .modifier(ThinkingShimmer(isActive: !message.isComplete, color: brandBrown))

                        if message.isComplete {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AquinasTheme.Colors.placeholderText)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }

                    // Response body — slides in after thinking finishes
                    if message.isComplete {
                        StreamingMessageView(
                            fullText: message.text,
                            shouldStream: shouldStream,
                            onFinish: onStreamFinished
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, message.isComplete ? 24 : 14)
                .frame(maxWidth: message.isComplete ? .infinity : nil, alignment: .leading)
                .background(chatBubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: message.isComplete ? 24 : 40, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: message.isComplete ? 24 : 40, style: .continuous)
                        .stroke(AquinasTheme.Colors.quietBorder, lineWidth: 1)
                )
                .animation(.spring(response: 0.55, dampingFraction: 0.72), value: message.isComplete)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Inline Follow-up Field

    /// Chained below the last response bubble: connector line → optional insight chip → centered "Ask Theo" field.
    private var inlineFollowUpField: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AquinasTheme.Colors.divider)
                .frame(width: 1, height: 25)
                .padding(.vertical, 16)

            // Insight chip — shown when one is in the pocket for this follow-up
            if let insight = contextInsight {
                BranchContextChip(
                    title: insight.title,
                    icon: "text.bubble.fill",
                    isFilled: true,
                    fillColor: Color(light: 0xFBF4E7, dark: 0x1B1714),
                    animatesAppearance: true
                )
                .padding(.bottom, 12)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            ZStack {
                if viewModel.inputText.isEmpty && !isFollowUpFocused {
                    Text("Ask Theo a question...")
                        .font(inputFont.textFont(size: conversationFontSize))
                        .foregroundColor(AquinasTheme.Colors.placeholderText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                }
                TextField("", text: $viewModel.inputText, axis: .vertical)
                    .focused($isFollowUpFocused)
                    .font(inputFont.textFont(size: conversationFontSize))
                    .lineSpacing(8)
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .multilineTextAlignment(.center)
                    .lineLimit(1...6)
                    .tint(AquinasTheme.Colors.primaryReadable)
                    .submitLabel(.send)
                    .onSubmit { submitQuestion() }
                    .onChange(of: viewModel.inputText) { _, newValue in
                        if newValue.last == "\n" {
                            viewModel.inputText = String(newValue.dropLast())
                            submitQuestion()
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chip

    @ViewBuilder
    private func insightChip(title: String, showRemove: Bool = false, onRemove: (() -> Void)? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.darkGreen)
            Text(title)
                .font(.figtreeChipLabel)
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .lineLimit(1)
            if showRemove, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.darkGreen)
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
            }
        }
    }

    // MARK: - Gestures & Actions

    private var collapseGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 60 || value.predictedEndTranslation.height > 120 {
                    collapse()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func submitQuestion() {
        guard !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isInputFocused = false
        isFollowUpFocused = false
        isBarOpen = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            isExpanded = true
            dragOffset = 0
        }
        viewModel.send(contextInsight: contextInsight)
        // Clear the pocket so follow-up questions don't inherit this insight
        contextInsight = nil
    }

    private func collapse() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
            isExpanded = false
            dragOffset = 0
        }
        onCollapse?()
    }
}

// MARK: - Preference Key

private struct QBarBottomFrameKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
