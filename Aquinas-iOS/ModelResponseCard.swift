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
    var onDuplicateBranch: (() -> Void)? = nil
    var onFinish: (() -> Void)? = nil

    @State private var isThinking: Bool
    @State private var rotation: Double = 0
    @State private var lineDrawn: Bool
    @State private var showTitle: Bool
    @State private var isCollapsed: Bool

    let brandBrown = AquinasTheme.Colors.primaryReadable
    let brandRed = AquinasTheme.Colors.accent
    let chatBubbleColor = AquinasTheme.Colors.background

    init(
        title: String,
        fullText: String,
        forceCollapsed: Bool,
        shouldAnimateOnAppear: Bool = true,
        onDuplicateBranch: (() -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        self.title = title
        self.fullText = fullText
        self.forceCollapsed = forceCollapsed
        self.shouldAnimateOnAppear = shouldAnimateOnAppear
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

            // The bubble begins as a compact "Thinking..." pill and expands into a full response card.
            ZStack(alignment: .top) {
                if isThinking {
                    HStack(spacing: 12) {
                        Image("cross-1")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundColor(brandRed)
                            .rotationEffect(.degrees(rotation))
                            .onAppear {
                                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                    rotation = 360
                                }
                            }

                        Text("Thinking...")
                            .font(.figtreeHeading2)
                            .foregroundColor(brandBrown)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .transition(.opacity)

                } else {
                    // Finished response: title row plus streamed text/actions.
                    VStack(alignment: .leading, spacing: 16) {
                        if showTitle {
                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isCollapsed.toggle()
                                }
                            }) {
                                HStack(alignment: .center) {
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
                            onBranch: onDuplicateBranch,
                            onFinish: onFinish
                        )
                            .opacity(isCollapsed ? 0 : 1)
                            .frame(height: isCollapsed ? 0 : nil)
                            .clipped()
                    }
                    .padding(24)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .background(chatBubbleColor)
            // Corner radius morphs from thinking pill to response card.
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
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: isThinking)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .task {
            guard shouldAnimateOnAppear else { return }
            // Prototype delay. Replace this with real model streaming state later.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            isThinking = false
        }
        .onAppear {
            isCollapsed = forceCollapsed
        }
        .onChange(of: isThinking) { oldValue, newValue in
            if !newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showTitle = true
                    }
                }
            }
        }
        .onChange(of: forceCollapsed) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.18)) {
                isCollapsed = newValue
            }
        }
    }
}
