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
    let forceCollapsed: Bool
    let shouldAnimateOnAppear: Bool
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    var onDuplicateBranch: (() -> Void)? = nil
    var onFinish: (() -> Void)? = nil

    @State private var isThinking: Bool
    @State private var lineDrawn: Bool
    @State private var showTitle: Bool
    @State private var isCollapsed: Bool

    let brandBrown = AquinasTheme.Colors.primaryReadable
    let chatBubbleColor = AquinasTheme.Colors.background

    init(
        title: String,
        fullText: String,
        forceCollapsed: Bool,
        shouldAnimateOnAppear: Bool = true,
        responseFont: ConversationFontOption = .sans,
        conversationFontSize: ConversationFontSizeOption = .large,
        onDuplicateBranch: (() -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        self.title = title
        self.fullText = fullText
        self.forceCollapsed = forceCollapsed
        self.shouldAnimateOnAppear = shouldAnimateOnAppear
        self.responseFont = responseFont
        self.conversationFontSize = conversationFontSize
        self.onDuplicateBranch = onDuplicateBranch
        self.onFinish = onFinish
        _isThinking = State(initialValue: shouldAnimateOnAppear)
        _lineDrawn = State(initialValue: !shouldAnimateOnAppear)
        _showTitle = State(initialValue: !shouldAnimateOnAppear)
        _isCollapsed = State(initialValue: forceCollapsed)
    }

    var body: some View {
        VStack(spacing: 0) {

            // Vertical line connecting the previous question to this response.
            Rectangle()
                .fill(AquinasTheme.Colors.divider)
                .frame(width: 1, height: 30)
                .scaleEffect(y: lineDrawn ? 1.0 : 0.5, anchor: .top)
                .opacity(lineDrawn ? 1.0 : 0.0)
                .padding(.bottom, 16)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.35)) {
                        lineDrawn = true
                    }
                }

            // Single unified VStack — the "Thinking…" row is the SAME view instance
            // throughout. When isThinking flips false the spring carries it from the
            // centred pill position to left-aligned above the title, never disappearing.
            VStack(alignment: .leading, spacing: 16) {

                // ── "Thinking…" / "Show Thinking >" — always visible ──────────
                // Same structural node in both states; position animates via the spring.
                Button(action: { /* future: toggle thinking trace */ }) {
                    HStack(spacing: 6) {
                        Text(isThinking ? "Thinking..." : "Show Thinking")
                            .font(.figtreeParagraphLarge)
                            .fontWeight(.bold)
                            .modifier(ThinkingShimmer(isActive: isThinking, color: brandBrown))

                        if !isThinking {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AquinasTheme.Colors.placeholderText)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isThinking)

                // ── Title + response body (card state only) ───────────────────
                if !isThinking {
                    if showTitle {
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isCollapsed.toggle()
                            }
                        }) {
                            HStack(alignment: .center, spacing: 6) {
                                Text(title)
                                    .font(.figtreeHeading1)
                                    .foregroundColor(brandBrown)

                                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AquinasTheme.Colors.placeholderText)
                                    .padding(.top, 2)
                                    .sfSymbolDrawOn()
                            }
                        }
                        .buttonStyle(.plain)
                        .transition(.blurSlideUp)
                    }

                    StreamingMessageView(
                        fullText: fullText,
                        shouldStream: shouldAnimateOnAppear,
                        responseFont: responseFont,
                        conversationFontSize: conversationFontSize,
                        onBranch: onDuplicateBranch,
                        onFinish: onFinish
                    )
                    .opacity(isCollapsed ? 0 : 1)
                    .frame(height: isCollapsed ? 0 : nil)
                    .clipped()
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, isThinking ? 14 : 24)
            .frame(maxWidth: isThinking ? nil : .infinity, alignment: .leading)
            .background(chatBubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: isThinking ? 40 : AquinasTheme.Spacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: isThinking ? 40 : AquinasTheme.Spacing.cardRadius, style: .continuous)
                    .stroke(AquinasTheme.Colors.quietBorder, lineWidth: 1)
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.5)),
                removal: .modifier(
                    active: BlurFadeModifier(isActive: true),
                    identity: BlurFadeModifier(isActive: false)
                )
            ))
            .animation(.spring(response: 0.55, dampingFraction: 0.72), value: isThinking)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .task {
            guard shouldAnimateOnAppear else { return }
            // Prototype delay. Replace this with real model streaming state later.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                isThinking = false
            }
        }
        .onAppear {
            isCollapsed = forceCollapsed
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
        .onChange(of: forceCollapsed) { _, newValue in
            withAnimation(.easeInOut(duration: 0.18)) {
                isCollapsed = newValue
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
