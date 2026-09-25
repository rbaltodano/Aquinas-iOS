//
//  ContextUsageCard.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

/// Full shared input-and-output KV-cache of the deployed Gemma 4 E2B LiteRT checkpoint.
let aquinasContextWindowLimit = AquinasContextBudget.totalTokenLimit

/// Shared open/animation state for the Context row in the model-controls stack.
@Observable
final class ContextCardState {
    var isOpen = false
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

/// The Context card as a real row in the bottom model-controls stack.
struct ContextControlsStackCard: View {
    let contextCard: ContextCardState
    let wordCount: Int
    var wordLimit: Int = aquinasContextWindowLimit
    var canCompact: Bool = false
    var onCompactContext: () async -> Bool = { false }
    var onClearConversation: () -> Void = {}

    var body: some View {
        ContextUsageCard(
            wordCount: wordCount,
            wordLimit: wordLimit,
            canCompact: canCompact,
            isCompacting: contextCard.isCompacting,
            isCompactionComplete: contextCard.isCompactionComplete,
            onCompact: beginContextCompaction,
            onClear: clearConversation,
            onArrowAppear: contextArrowDidAppear
        )
        .offset(y: contextCard.dragY)
        .gesture(contextCardDismissGesture)
        .transition(.bottomDockCard)
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
        guard canCompact, !contextCard.isCompacting else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            contextCard.isCompacting = true
            contextCard.isCompactionComplete = false
        }
        contextCard.compactTask?.cancel()
        contextCard.compactTask = Task {
            let didCompact = await onCompactContext()
            guard !Task.isCancelled else { return }
            guard didCompact else {
                await MainActor.run {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        contextCard.isCompacting = false
                    }
                }
                return
            }
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

struct ContextUsageIcon: View {
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
                    .animation(.easeInOut(duration: 0.65), value: progress)
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
    let canCompact: Bool
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
                            Text("\(formatted(wordCount)) / \(formatted(wordLimit)) tokens")
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
                                    .frame(width: progress > 0 ? max(geometry.size.width * progress, 8) : 0)
                                    .animation(.easeInOut(duration: 0.65), value: progress)
                            }
                        }
                        .frame(height: 2)
                    }

                    HStack {
                        Button("Compact", action: onCompact)
                            .disabled(!canCompact)
                            .opacity(canCompact ? 1 : 0.35)
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
