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
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    var onDuplicateBranch: (() -> Void)? = nil
    var onInsightTap: ((String, String) -> Void)? = nil
    var onFinish: (() -> Void)? = nil

    @State private var isThinking: Bool
    @State private var isThinkingDocked: Bool
    @State private var isShowingWritingStatus: Bool
    @State private var showTitle: Bool
    @State private var showResponseContent: Bool
    @State private var isThinkingExpanded: Bool = false
    @State private var visibleThinkingLineCount: Int = 0
    @State private var isThinkingRuleVisible: Bool = false
    @State private var isThinkingCollapsing: Bool = false
    @State private var hasStartedFinishThinking: Bool = false
    @State private var thinkingStartedAt: Date

    let brandBrown = AquinasTheme.Colors.primaryReadable
    private var thinkingSummaryLines: [String] {
        thinkingSummary.isEmpty
            ? ["No reasoning summary was returned for this response."]
            : thinkingSummary
    }
    private var canShowThinkingSummaryButton: Bool {
        showsThinkingIntro && !isThinking && !isAwaitingResponse
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
        responseTextAlignment: ResponseTextAlignmentOption = .center,
        responseFont: ConversationFontOption = .sans,
        conversationFontSize: ConversationFontSizeOption = .large,
        loadingInsightKey: String? = nil,
        queuedInsightKeys: Set<String> = [],
        onDuplicateBranch: (() -> Void)? = nil,
        onInsightTap: ((String, String) -> Void)? = nil,
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
        self.responseTextAlignment = responseTextAlignment
        self.responseFont = responseFont
        self.conversationFontSize = conversationFontSize
        self.loadingInsightKey = loadingInsightKey
        self.queuedInsightKeys = queuedInsightKeys
        self.onDuplicateBranch = onDuplicateBranch
        self.onInsightTap = onInsightTap
        self.onFinish = onFinish
        let shouldShowThinking = showsThinkingIntro
            && (isAwaitingResponse || shouldAnimateOnAppear)
        _isThinking = State(initialValue: shouldShowThinking)
        _isThinkingDocked = State(initialValue: !shouldShowThinking)
        _isShowingWritingStatus = State(initialValue: isReceivingStream)
        _showTitle = State(initialValue: !shouldAnimateOnAppear)
        _showResponseContent = State(initialValue: !shouldAnimateOnAppear)
        _thinkingStartedAt = State(initialValue: Date())
    }

    var body: some View {
        VStack(spacing: 0) {

            // Single unified VStack — the "Thinking…" row is the SAME view instance
            // throughout. When isThinking flips false the spring carries it from the
            // centred pill position to left-aligned above the title, never disappearing.
            VStack(alignment: .center, spacing: 16) {

                if showsThinkingIntro {
                    // ── "Thinking…" / expandable thinking summary ─────────────
                    if isThinking {
                        LiveThinkingProgressView(
                            summaryLines: thinkingSummary,
                            isWritingResponse: isShowingWritingStatus,
                            isQueuedForModel: isQueuedForModel,
                            font: responseFont.textFont(size: conversationFontSize),
                            color: brandBrown
                        )
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        Button(action: {
                            guard canShowThinkingSummaryButton else { return }
                            if isThinkingExpanded {
                                collapseThinking()
                            } else {
                                isThinkingCollapsing = false
                                visibleThinkingLineCount = 0
                                isThinkingRuleVisible = false
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
                        .disabled(!canShowThinkingSummaryButton)
                        .accessibilityLabel(isThinkingExpanded ? "Hide Thinking" : "Show Thinking")
                        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                if showsThinkingIntro && !isThinking && isThinkingExpanded {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(thinkingSummaryLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(responseFont.textFont(size: conversationFontSize))
                                    .lineSpacing(8)
                                    .foregroundColor(AquinasTheme.Colors.placeholderText)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .opacity(index < visibleThinkingLineCount ? 1 : 0)
                            }
                        }
                        .padding(.leading, 24)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(AquinasTheme.Colors.quietBorder)
                                .frame(width: 2)
                                .opacity(isThinkingRuleVisible ? 1 : 0)
                        }

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
                    .task {
                        try? await Task.sleep(for: .milliseconds(425))
                        guard !Task.isCancelled, !isThinkingCollapsing else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isThinkingRuleVisible = true
                        }
                    }
                }

                // ── Title + response body (card state only) ───────────────────
                if !isThinking && !isAwaitingResponse && showResponseContent {
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
                        onBranch: onDuplicateBranch,
                        onInsightTap: onInsightTap,
                        onFinish: onFinish
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
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
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    showTitle = true
                    showResponseContent = true
                }
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
                    try? await Task.sleep(for: .milliseconds(80))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.22)) {
                        showTitle = true
                        showResponseContent = true
                    }
                }
            }
        }
        .onChange(of: isReceivingStream) { _, isReceiving in
            guard isReceiving else { return }
            if shouldBeginThinking {
                startThinking()
            }
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
        isThinkingRuleVisible = false
        isThinkingCollapsing = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isThinking = true
            isThinkingDocked = false
            isShowingWritingStatus = isReceivingStream
            showTitle = false
            showResponseContent = false
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

        // Let the progress stack finish collapsing into "Show Thinking"
        // before the title and response begin their own entrance.
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
            isThinkingRuleVisible = false
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
    let font: Font
    let color: Color

    private var showsDetailedProgress: Bool {
        !summaryLines.isEmpty || isWritingResponse
    }

    var body: some View {
        Group {
            if showsDetailedProgress {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(summaryLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(font)
                            .lineSpacing(8)
                            .multilineTextAlignment(.leading)
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
                        Text("Writing response...")
                            .font(font)
                            .fontWeight(.bold)
                            .lineSpacing(8)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .modifier(ThinkingShimmer(isActive: true, color: color))
                            .transition(.glideFadeUp)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
            } else {
                if isQueuedForModel {
                    Text("Question queued")
                        .font(font)
                        .fontWeight(.bold)
                        .modifier(QueuedWorkBreatheModifier(isQueued: true))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    Text("Thinking...")
                        .font(font)
                        .fontWeight(.bold)
                        .modifier(ThinkingShimmer(isActive: true, color: color))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: summaryLines.count)
        .animation(.easeOut(duration: 0.3), value: isWritingResponse)
        .animation(.easeInOut(duration: 0.25), value: isQueuedForModel)
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
                // for the pause portion before the next sweep begins.
                let cycle: Double  = 2.0
                let sweepSpan: Double = 1.0
                let tMod  = t.truncatingRemainder(dividingBy: cycle)
                let phase = CGFloat(min(tMod / sweepSpan, 1.0))
                let sweep = phase * 1.6 - 0.3
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
