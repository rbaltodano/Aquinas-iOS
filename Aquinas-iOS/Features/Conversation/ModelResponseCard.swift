//
//  ModelResponse.swift
//  Aquinas-iOS
//
//  Created by Ryan on 4/30/26.
//

import Foundation
import SwiftUI

// MARK: - Model Response Card

/// Response bubble with a temporary thinking state, collapsible title, streamed body, and action icons.
struct ModelResponseCard: View {
    let title: String
    let fullText: String
    let shouldAnimateOnAppear: Bool
    let showsThinkingIntro: Bool
    let isAwaitingResponse: Bool
    let isReceivingStream: Bool
    let isQueuedForModel: Bool
    let usesNetworkStream: Bool
    let thinkingSummary: [String]
    let funStatusText: String?
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    let savedInsightIDs: Set<UUID>
    var onRegenerate: (() -> Void)? = nil
    var onDuplicateBranch: (() -> Void)? = nil
    var onInsightTap: ((String, String) -> Void)? = nil
    var onInlineInsightQuote: ((ConceptDefinition) -> Void)? = nil
    var onInlineInsightFork: ((ConceptDefinition) -> Void)? = nil
    var onInlineInsightToggleSaved: ((ConceptDefinition) -> Void)? = nil
    var showsResponseActions: Bool = true
    var onRevealStart: (() -> Void)? = nil
    var onFinish: (() -> Void)? = nil

    @State private var isThinking: Bool
    @State private var isThinkingDocked: Bool
    @State private var isShowingWritingStatus: Bool
    @State private var showTitle: Bool
    @State private var showResponseContent: Bool
    @State private var isThinkingExpanded: Bool = false
    @State private var visibleThinkingLineCount: Int = 0
    @State private var isThinkingCollapsing: Bool = false
    @State private var hasStartedFinishThinking: Bool = false
    @State private var thinkingStartedAt: Date
    @State private var revealedResponseWordCount: Int = 0
    @State private var isResponseFullyRevealed: Bool = false

    let brandBrown = AquinasTheme.Colors.primaryReadable
    private var thinkingSummaryLines: [String] {
        thinkingSummary
    }
    private var presentsThinkingUI: Bool {
        showsThinkingIntro || !thinkingSummary.isEmpty
    }
    /// Continues the thinking phase's word-based token estimate (see `LiveThinkingProgressView`)
    /// into the actual response streaming, so the count keeps climbing as words are revealed
    /// instead of freezing once the initial thinking/chain-of-thought phase ends.
    private var totalEstimatedTokenCount: Int {
        let thinkingWordCount = thinkingSummary.joined(separator: " ").split(separator: " ").count
        return Int(Double(thinkingWordCount + revealedResponseWordCount) * 1.3)
    }
    private var canShowThinkingSummaryButton: Bool {
        !thinkingSummary.isEmpty
            && !isThinking
            && !isAwaitingResponse
            && showResponseContent
    }

    init(
        title: String,
        fullText: String,
        shouldAnimateOnAppear: Bool = true,
        showsThinkingIntro: Bool = true,
        isAwaitingResponse: Bool = false,
        isReceivingStream: Bool = false,
        isQueuedForModel: Bool = false,
        usesNetworkStream: Bool = false,
        thinkingSummary: [String] = [],
        funStatusText: String? = nil,
        responseTextAlignment: ResponseTextAlignmentOption = .center,
        responseFont: ConversationFontOption = .sans,
        conversationFontSize: ConversationFontSizeOption = .large,
        loadingInsightKey: String? = nil,
        queuedInsightKeys: Set<String> = [],
        savedInsightIDs: Set<UUID> = [],
        onRegenerate: (() -> Void)? = nil,
        onDuplicateBranch: (() -> Void)? = nil,
        onInsightTap: ((String, String) -> Void)? = nil,
        onInlineInsightQuote: ((ConceptDefinition) -> Void)? = nil,
        onInlineInsightFork: ((ConceptDefinition) -> Void)? = nil,
        onInlineInsightToggleSaved: ((ConceptDefinition) -> Void)? = nil,
        showsResponseActions: Bool = true,
        onRevealStart: (() -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        self.title = title
        self.fullText = fullText
        self.shouldAnimateOnAppear = shouldAnimateOnAppear
        self.showsThinkingIntro = showsThinkingIntro
        self.isAwaitingResponse = isAwaitingResponse
        self.isReceivingStream = isReceivingStream
        self.isQueuedForModel = isQueuedForModel
        self.usesNetworkStream = usesNetworkStream
        self.thinkingSummary = thinkingSummary
        self.funStatusText = funStatusText
        self.responseTextAlignment = responseTextAlignment
        self.responseFont = responseFont
        self.conversationFontSize = conversationFontSize
        self.loadingInsightKey = loadingInsightKey
        self.queuedInsightKeys = queuedInsightKeys
        self.savedInsightIDs = savedInsightIDs
        self.onRegenerate = onRegenerate
        self.onDuplicateBranch = onDuplicateBranch
        self.onInsightTap = onInsightTap
        self.onInlineInsightQuote = onInlineInsightQuote
        self.onInlineInsightFork = onInlineInsightFork
        self.onInlineInsightToggleSaved = onInlineInsightToggleSaved
        self.showsResponseActions = showsResponseActions
        self.onRevealStart = onRevealStart
        self.onFinish = onFinish
        let shouldShowThinking = showsThinkingIntro
            && (isAwaitingResponse || shouldAnimateOnAppear)
        _isThinking = State(initialValue: shouldShowThinking)
        _isThinkingDocked = State(initialValue: !shouldShowThinking)
        _isShowingWritingStatus = State(initialValue: isReceivingStream)
        _showTitle = State(initialValue: !shouldAnimateOnAppear)
        _showResponseContent = State(initialValue: !shouldAnimateOnAppear)
        _thinkingStartedAt = State(initialValue: Date())
        // A restored response is already fully presented. Its StreamingMessageView starts with
        // every word visible and therefore does not run the reveal task or call `onFinish`.
        // Treat it as finished up front so a timer/token footer from the interrupted renderer
        // cannot survive a navigate-away / navigate-back cycle.
        _isResponseFullyRevealed = State(initialValue: !shouldAnimateOnAppear)
    }

    var body: some View {
        VStack(spacing: 0) {

            // Single unified VStack — the "Thinking…" row is the SAME view instance
            // throughout. When isThinking flips false the spring carries it from the
            // centred pill position to left-aligned above the title, never disappearing.
            VStack(alignment: .center, spacing: 16) {

                if presentsThinkingUI {
                    // ── "Thinking…" / expandable thinking summary ─────────────
                    if isThinking {
                        LiveThinkingProgressView(
                            summaryLines: thinkingSummary,
                            isWritingResponse: isShowingWritingStatus,
                            isQueuedForModel: isQueuedForModel,
                            funStatusText: funStatusText,
                            font: responseFont.textFont(size: conversationFontSize),
                            color: brandBrown,
                            startedAt: thinkingStartedAt,
                            responseTextAlignment: responseTextAlignment
                        )
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else if canShowThinkingSummaryButton {
                        Button(action: {
                            if isThinkingExpanded {
                                collapseThinking()
                            } else {
                                isThinkingCollapsing = false
                                visibleThinkingLineCount = 0
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                    isThinkingExpanded = true
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Text("Show Thinking")
                                    .font(
                                        .custom(
                                            "Figtree-Bold",
                                            size: conversationFontSize.pointSize
                                        )
                                    )

                                Image(systemName: isThinkingExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            }
                            .foregroundColor(AquinasTheme.Colors.headingText)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isThinkingExpanded ? "Hide Thinking" : "Show Thinking")
                        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                if presentsThinkingUI && !isThinking && isThinkingExpanded {
                    VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 16) {
                        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 8) {
                            ForEach(Array(thinkingSummaryLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(responseFont.textFont(size: conversationFontSize))
                                    .lineSpacing(8)
                                    .multilineTextAlignment(responseTextAlignment.textAlignment)
                                    .foregroundColor(AquinasTheme.Colors.placeholderText)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .opacity(index < visibleThinkingLineCount ? 1 : 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)

                        Button(action: {
                            collapseThinking()
                        }) {
                            HStack(spacing: 6) {
                                Text("Hide Thinking")
                                    .font(.figtreeParagraphLarge)
                                    .fontWeight(.bold)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(brandBrown.opacity(0.5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                    }
                    .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                    .padding(.bottom, 40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .task {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled, !isThinkingCollapsing else { return }

                        for lineCount in 1...thinkingSummaryLines.count {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                visibleThinkingLineCount = lineCount
                            }
                            try? await Task.sleep(for: .milliseconds(50))
                            guard !Task.isCancelled, !isThinkingCollapsing else { return }
                        }
                    }
                }

                // ── Title + response body (card state only) ───────────────────
                if !isThinking
                    && !isAwaitingResponse
                    && showResponseContent {
                    if showTitle, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(title)
                            .font(.baskervilleDisplay)
                            .foregroundColor(brandBrown)
                            .multilineTextAlignment(responseTextAlignment.textAlignment)
                            .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                            .transition(.glideFadeUp)
                    }

                    StreamingMessageView(
                        fullText: fullText,
                        shouldStream: shouldAnimateOnAppear,
                        isReceivingStream: isReceivingStream,
                        usesNetworkStream: usesNetworkStream,
                        responseTextAlignment: responseTextAlignment,
                        responseFont: responseFont,
                        conversationFontSize: conversationFontSize,
                        loadingInsightKey: loadingInsightKey,
                        queuedInsightKeys: queuedInsightKeys,
                        savedInsightIDs: savedInsightIDs,
                        showsResponseActions: showsResponseActions,
                        onRegenerate: onRegenerate,
                        onBranch: onDuplicateBranch,
                        onInsightTap: onInsightTap,
                        onInlineInsightQuote: onInlineInsightQuote,
                        onInlineInsightFork: onInlineInsightFork,
                        onInlineInsightToggleSaved: onInlineInsightToggleSaved,
                        onRevealStart: onRevealStart,
                        onFinish: {
                            withAnimation(.easeOut(duration: 0.25)) {
                                isResponseFullyRevealed = true
                            }
                            onFinish?()
                        },
                        onRevealedWordCountChange: { count in
                            revealedResponseWordCount = count
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))

                    if !isResponseFullyRevealed {
                        ThinkingMetricsFooter(
                            startedAt: thinkingStartedAt,
                            estimatedTokenCount: totalEstimatedTokenCount,
                            color: brandBrown
                        )
                        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                        .transition(.opacity)
                    }
                }
            }
            .frame(
                maxWidth: isThinkingDocked ? .infinity : nil,
                alignment: .center
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.5)),
                removal: .modifier(
                    active: BlurFadeModifier(isActive: true),
                    identity: BlurFadeModifier(isActive: false)
                )
            ))
            .animation(.spring(response: 0.55, dampingFraction: 0.72), value: isThinking)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isThinkingDocked)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .task {
            if shouldBeginThinking {
                startThinking()
            }
            guard shouldAnimateOnAppear else { return }
            guard !isAwaitingResponse else { return }
            guard showsThinkingIntro else {
                await revealContentWithoutThinking()
                return
            }
            await finishThinking()
        }
        .onChange(of: isAwaitingResponse) { _, isAwaiting in
            if isAwaiting, shouldBeginThinking {
                startThinking()
                return
            }
            guard !isAwaiting else { return }
            Task { @MainActor in
                if showsThinkingIntro {
                    await finishThinking()
                } else {
                    await revealContentWithoutThinking()
                }
            }
        }
        .onChange(of: isReceivingStream) { _, isReceiving in
            guard isReceiving, isThinking else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isShowingWritingStatus = true
                isThinkingDocked = true
            }
        }
        .onChange(of: thinkingSummary.count) { _, count in
            guard count > 0, isThinking else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isThinkingDocked = true
            }
        }
    }

    private var shouldBeginThinking: Bool {
        showsThinkingIntro
            && shouldAnimateOnAppear
            && (isAwaitingResponse || isReceivingStream || fullText.isEmpty)
            && !hasStartedFinishThinking
    }

    private func startThinking() {
        thinkingStartedAt = Date()
        hasStartedFinishThinking = false
        isThinkingExpanded = false
        visibleThinkingLineCount = 0
        isThinkingCollapsing = false
        revealedResponseWordCount = 0
        isResponseFullyRevealed = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isThinking = true
            isThinkingDocked = false
            isShowingWritingStatus = isReceivingStream
            showTitle = false
            showResponseContent = false
        }
    }

    /// Used when `showsThinkingIntro` is false (e.g. a cancelled response, which swaps in plain
    /// text and suppresses the thinking UI) — reveals content directly. Must still reset
    /// `isThinking`/`hasStartedFinishThinking`/the elapsed-time clock, or a thinking state left
    /// over from before the cancellation keeps `LiveThinkingProgressView` (and its live timer)
    /// mounted and ticking indefinitely, even though nothing is actually being generated anymore.
    @MainActor
    private func revealContentWithoutThinking() async {
        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }
        hasStartedFinishThinking = true
        withAnimation(.easeOut(duration: 0.22)) {
            isThinking = false
            isThinkingDocked = true
            isShowingWritingStatus = false
            showTitle = true
            showResponseContent = true
        }
    }

    @MainActor
    private func finishThinking() async {
        guard isThinking, !hasStartedFinishThinking else { return }
        hasStartedFinishThinking = true
        let minimumVisibleDuration: TimeInterval = 1.15
        let elapsed = Date().timeIntervalSince(thinkingStartedAt)
        if elapsed < minimumVisibleDuration {
            try? await Task.sleep(for: .milliseconds(Int((minimumVisibleDuration - elapsed) * 1_000)))
            guard !Task.isCancelled else { return }
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isThinkingDocked = true
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            isThinking = false
        }

        // Let the progress stack finish collapsing before the response and its
        // persistent "Show Thinking" disclosure enter together.
        try? await Task.sleep(for: .milliseconds(420))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            isShowingWritingStatus = false
            showTitle = true
            showResponseContent = true
        }
    }

    private func collapseThinking() {
        isThinkingCollapsing = true
        withAnimation(.easeOut(duration: 0.1)) {
            visibleThinkingLineCount = 0
        }

        Task {
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                isThinkingExpanded = false
            }
        }
    }
}

private struct LiveThinkingProgressView: View {
    let summaryLines: [String]
    let isWritingResponse: Bool
    let isQueuedForModel: Bool
    let funStatusText: String?
    let font: Font
    let color: Color
    let startedAt: Date
    var responseTextAlignment: ResponseTextAlignmentOption = .left

    private var showsDetailedProgress: Bool {
        !summaryLines.isEmpty || isWritingResponse
    }

    /// Rough word-count-based proxy for tokens spent so far — this build has no live model API
    /// wired in (responses are simulated), so there's no real token count to report. This gives
    /// the user a live-feeling number without claiming it's an authoritative usage count.
    private var estimatedTokenCount: Int {
        var text = summaryLines.joined(separator: " ")
        if isWritingResponse { text += " " + (funStatusText ?? "Writing response...") }
        let wordCount = text.split(separator: " ").count
        return Int(Double(wordCount) * 1.3)
    }

    var body: some View {
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 8) {
            Group {
                if showsDetailedProgress {
                    VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 8) {
                        ForEach(Array(summaryLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(font)
                                .lineSpacing(8)
                                .multilineTextAlignment(responseTextAlignment.textAlignment)
                                .fixedSize(horizontal: false, vertical: true)
                                .modifier(
                                    ThinkingShimmer(
                                        isActive: !isWritingResponse && index == summaryLines.count - 1,
                                        color: color
                                    )
                                )
                                .transition(.glideFadeUp)
                        }

                        if isWritingResponse {
                            Text(funStatusText ?? "Writing response...")
                                .font(font)
                                .fontWeight(.bold)
                                .lineSpacing(8)
                                .multilineTextAlignment(responseTextAlignment.textAlignment)
                                .fixedSize(horizontal: false, vertical: true)
                                .modifier(ThinkingShimmer(isActive: true, color: color))
                                .transition(.glideFadeUp)
                                .accessibilityLabel("Writing response")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                } else {
                    if isQueuedForModel {
                        Text(funStatusText ?? "Question queued")
                            .font(font)
                            .fontWeight(.bold)
                            .modifier(QueuedWorkBreatheModifier(isQueued: true))
                            .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            .accessibilityLabel("Question queued")
                    } else {
                        Text(funStatusText ?? "Thinking...")
                            .font(font)
                            .fontWeight(.bold)
                            .modifier(ThinkingShimmer(isActive: true, color: color))
                            .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            .accessibilityLabel("Thinking")
                    }
                }
            }

            // Waits for the initial "Thinking..." line to give way to the actual chain-of-thought
            // (or "Writing response...") before showing — not present during the plain intro line.
            if showsDetailedProgress {
                ThinkingMetricsFooter(
                    startedAt: startedAt,
                    estimatedTokenCount: estimatedTokenCount,
                    color: color
                )
                .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: summaryLines.count)
        .animation(.easeOut(duration: 0.3), value: isWritingResponse)
        .animation(.easeInOut(duration: 0.25), value: isQueuedForModel)
    }
}

/// Persistent readout pinned below the thinking/writing text — elapsed time always reflects
/// reality (driven by wall-clock time via `TimelineView`), while the token count is a rough
/// word-based estimate since responses in this build are simulated, not fetched from a live
/// model API that would report real usage.
private struct ThinkingMetricsFooter: View {
    let startedAt: Date
    let estimatedTokenCount: Int
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsedSeconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
            HStack(spacing: 4) {
                Text(formattedDuration(elapsedSeconds))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(elapsedSeconds)))
                    // Fixed width (not just monospacedDigit) so the footer doesn't reflow
                    // every second as the digit count changes, e.g. "9s" → "10s" → "1:00".
                    .frame(width: 28, alignment: .leading)

                Text("·")
                    .font(.custom("Figtree-Regular", size: 18))

                Text("~\(estimatedTokenCount) tokens")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(estimatedTokenCount)))
            }
            .font(.custom("Figtree-Regular", size: 12))
            .foregroundColor(color.opacity(0.4))
            .animation(.easeOut(duration: 0.35), value: elapsedSeconds)
            .animation(.easeOut(duration: 0.35), value: estimatedTokenCount)
        }
    }

    private func formattedDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return minutes > 0 ? String(format: "%d:%02d", minutes, seconds) : "\(seconds)s"
    }
}

// MARK: - Thinking shimmer

/// Sweeps a bright wave left-to-right across text while the model is thinking.
/// Uses TimelineView(.animation) so phase is derived from wall-clock time —
/// guaranteed per-frame updates, no @State animation batching issues.
struct ThinkingShimmer: ViewModifier {
    let isActive: Bool
    let color: Color

    func body(content: Content) -> some View {
        if isActive {
            TimelineView(.animation) { context in
                let t  = context.date.timeIntervalSinceReferenceDate
                // Total cycle: 1.0 s sweep + 1.0 s pause = 2.0 s.
                // `phase` only reaches 1.0 at the sweep midpoint; after that it
                // clamps at 1.0 so the band sits off the right edge (invisible)
                // for the pause portion before the next sweep begins. The sweep
                // range clears the band (half-width 0.4) fully past x = 1.0 by
                // the time phase reaches 1.0, so the fade-out happens gradually
                // as part of the sweep itself instead of leaving a bright tail
                // resting on the last character that then snaps away when the
                // next cycle starts.
                let cycle: Double  = 2.0
                let sweepSpan: Double = 1.0
                let tMod  = t.truncatingRemainder(dividingBy: cycle)
                let phase = CGFloat(min(tMod / sweepSpan, 1.0))
                let sweep = phase * 1.9 - 0.4
                content
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                color.opacity(0.25),
                                color.opacity(0.95),
                                color.opacity(0.25),
                            ],
                            startPoint: UnitPoint(x: sweep - 0.4, y: 0.5),
                            endPoint:   UnitPoint(x: sweep + 0.4, y: 0.5)
                        )
                    )
            }
        } else {
            content.foregroundColor(color.opacity(0.5))
        }
    }
}

extension View {
    /// Clips the view only when `active` is true; otherwise leaves overflow visible.
    @ViewBuilder
    func clipped(when active: Bool) -> some View {
        if active {
            self.clipped()
        } else {
            self
        }
    }
}
