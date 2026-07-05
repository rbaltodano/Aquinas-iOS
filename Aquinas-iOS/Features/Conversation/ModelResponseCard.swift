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
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    var onDuplicateBranch: (() -> Void)? = nil
    var onFinish: (() -> Void)? = nil

    @State private var isThinking: Bool
    @State private var isThinkingDocked: Bool
    @State private var showTitle: Bool
    @State private var isThinkingExpanded: Bool = false
    @State private var visibleThinkingLineCount: Int = 0
    @State private var isThinkingRuleVisible: Bool = false
    @State private var isThinkingCollapsing: Bool = false

    let brandBrown = AquinasTheme.Colors.primaryReadable
    private let thinkingSummaryLines = [
        "I identified the central ideas in the question,",
        "considered the relevant historical and theological context,",
        "and organized the response around the clearest supporting details."
    ]

    init(
        title: String,
        fullText: String,
        shouldAnimateOnAppear: Bool = true,
        showsThinkingIntro: Bool = true,
        responseTextAlignment: ResponseTextAlignmentOption = .center,
        responseFont: ConversationFontOption = .sans,
        conversationFontSize: ConversationFontSizeOption = .large,
        onDuplicateBranch: (() -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        self.title = title
        self.fullText = fullText
        self.shouldAnimateOnAppear = shouldAnimateOnAppear
        self.showsThinkingIntro = showsThinkingIntro
        self.responseTextAlignment = responseTextAlignment
        self.responseFont = responseFont
        self.conversationFontSize = conversationFontSize
        self.onDuplicateBranch = onDuplicateBranch
        self.onFinish = onFinish
        let shouldShowThinking = shouldAnimateOnAppear && showsThinkingIntro
        _isThinking = State(initialValue: shouldShowThinking)
        _isThinkingDocked = State(initialValue: !shouldShowThinking)
        _showTitle = State(initialValue: !shouldAnimateOnAppear)
    }

    var body: some View {
        VStack(spacing: 0) {

            // Single unified VStack — the "Thinking…" row is the SAME view instance
            // throughout. When isThinking flips false the spring carries it from the
            // centred pill position to left-aligned above the title, never disappearing.
            VStack(alignment: .center, spacing: 16) {

                if showsThinkingIntro {
                    // ── "Thinking…" / expandable thinking summary ─────────────
                    Button(action: {
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
                            Text(isThinking ? "Thinking..." : "Show Thinking")
                                .font(.figtreeParagraphLarge)
                                .fontWeight(.bold)
                                .modifier(ThinkingShimmer(isActive: isThinking, color: brandBrown))
                                .contentTransition(.opacity)
                                .animation(.easeInOut(duration: 0.2), value: isThinking)

                            if !isThinking {
                                Image(systemName: isThinkingExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AquinasTheme.Colors.placeholderText)
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isThinking)
                    .accessibilityLabel(isThinkingExpanded ? "Hide Thinking" : "Show Thinking")
                    .frame(
                        maxWidth: isThinkingDocked ? .infinity : nil,
                        alignment: isThinkingDocked ? responseTextAlignment.frameAlignment : .center
                    )
                }

                if showsThinkingIntro && !isThinking && isThinkingExpanded {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(thinkingSummaryLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.figtreeParagraphLarge)
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
                if !isThinking {
                    if showTitle {
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
                        responseTextAlignment: responseTextAlignment,
                        responseFont: responseFont,
                        conversationFontSize: conversationFontSize,
                        onBranch: onDuplicateBranch,
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
            guard shouldAnimateOnAppear else { return }
            guard showsThinkingIntro else {
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(.easeOut(duration: 0.22)) {
                    showTitle = true
                }
                return
            }
            // Prototype delay. Replace this with real model streaming state later.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                isThinkingDocked = true
            }

            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeInOut(duration: 0.2)) {
                isThinking = false
            }
        }
        .onChange(of: isThinking) { _, newValue in
            if !newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showTitle = true
                    }
                }
            }
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
