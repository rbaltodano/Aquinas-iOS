//
//  NavigationButtons.swift
//  Aquinas-iOS
//

import SwiftUI

/// Always-available top-left trigger for the conversation side panel.
struct SideMenuTriggerButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .sfSymbolDrawOn()
                .frame(width: 48, height: 48)
                .background(AquinasTheme.Colors.canvasSecondary)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open side menu")
    }
}

/// Grows beside the side-menu button while Study is open and returns to the Insight Tree.
/// Figma: source-of-truth 944:1098 (48 pt tall capsule, × icon, "Exit").
struct StudyExitButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AquinasTheme.Colors.darkGreen)
                    .frame(width: 14, height: 14)
                Text("Exit")
                    .font(AquinasTheme.Typography.uiSubheading)
                    .foregroundColor(AquinasTheme.Colors.paragraphText)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 19)
            .frame(height: 48)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Exit Study")
    }
}

/// Back capsule shown beside the side-menu button on detail screens (chevron + parent title),
/// styled like `StudyExitButton`.
struct NavBackCapsuleButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AquinasTheme.Colors.darkGreen)
                    .frame(width: 14, height: 14)
                Text(title)
                    .font(AquinasTheme.Typography.uiSubheading)
                    .foregroundColor(AquinasTheme.Colors.paragraphText)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 19)
            .frame(height: 48)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(title)")
    }
}

extension AnyTransition {
    /// The Exit capsule grows out of the side-menu button beside it.
    static var studyExitGrow: AnyTransition {
        .scale(scale: 0.4, anchor: .leading).combined(with: .blurFade)
    }
}

/// Top-right control for quickly moving between focused Branch mode and the wider Canvas view.
struct CanvasModeToggleButton: View {
    let isActive: Bool
    var updateSignal: Int = 0
    var action: () -> Void
    @State private var pulseScale: CGFloat = 1.0
    @State private var updatedTextWidth: CGFloat = 0
    @State private var animatedButtonWidth: CGFloat = 48
    @State private var animatedLabelGap: CGFloat = 0
    @State private var animatedLabelWidth: CGFloat = 0
    @State private var isShowingUpdated = false
    @State private var hapticTrigger = 0
    @State private var dismissalTask: Task<Void, Never>?
    @State private var updatedPulseTask: Task<Void, Never>?

    private static let collapsedWidth: CGFloat = 48
    private static let activeWidth: CGFloat = 93
    private static let labelGap: CGFloat = 8
    private static let updatedTransitionDuration: TimeInterval = 0.28

    private var showsUpdatedLabel: Bool {
        !isActive && isShowingUpdated
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 0) {
                ZStack {
                    if isActive {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AquinasTheme.Colors.darkGreen)
                            .transition(.blurFade)
                    } else {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AquinasTheme.Colors.lightGreen)
                            .sfSymbolDrawOn()
                            .transition(.blurFade)
                    }
                }
                .frame(width: 18, height: 18)

                if !isActive {
                    Color.clear
                        .frame(width: animatedLabelGap)

                    updatedText
                        .frame(width: animatedLabelWidth, alignment: .leading)
                        .opacity(showsUpdatedLabel && animatedLabelWidth > 0 ? 1 : 0)
                        .blur(radius: showsUpdatedLabel && animatedLabelWidth > 0 ? 0 : 8)
                        .clipped()
                }

                if isActive {
                    Text("Back")
                        .font(.custom("Figtree-Bold", size: 14))
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.blurFade)
                }
            }
            .padding(.horizontal, isActive ? 19 : 15)
            .frame(width: animatedButtonWidth, height: 48)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(Capsule())
            .clipped()
            .overlay(
                Capsule()
                    .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
            )
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isActive)
        }
        .background(updatedTextMeasurement)
        .buttonStyle(.plain)
        .scaleEffect(pulseScale)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .accessibilityLabel(isActive ? "Return to branch view" : "Open canvas view")
        .onAppear {
            updateButtonLayout(animated: false)
        }
        .onChange(of: isActive) { _, _ in
            updateButtonLayout(animated: true)
        }
        .onChange(of: updateSignal) { oldValue, newValue in
            guard newValue > oldValue, !isActive else { return }
            presentUpdatedFeedback()
        }
        .onDisappear {
            dismissalTask?.cancel()
            updatedPulseTask?.cancel()
        }
    }

    private var updatedText: some View {
        Text("Updated")
            .font(.figtreeChipLabel)
            .foregroundColor(AquinasTheme.Colors.headingText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var updatedTextMeasurement: some View {
        updatedText
            .hidden()
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: CanvasModeUpdatedWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(CanvasModeUpdatedWidthKey.self) { width in
                updatedTextWidth = width
                updateButtonLayout(animated: showsUpdatedLabel)
            }
    }

    private func targetButtonWidth(labelWidth: CGFloat) -> CGFloat {
        if isActive { return Self.activeWidth }
        if showsUpdatedLabel { return Self.collapsedWidth + Self.labelGap + labelWidth }
        return Self.collapsedWidth
    }

    private func updateButtonLayout(animated: Bool) {
        let nextLabelWidth = showsUpdatedLabel ? updatedTextWidth : 0
        let nextLabelGap = showsUpdatedLabel ? Self.labelGap : 0
        let nextButtonWidth = targetButtonWidth(labelWidth: nextLabelWidth)

        let updates = {
            animatedLabelWidth = nextLabelWidth
            animatedLabelGap = nextLabelGap
            animatedButtonWidth = nextButtonWidth
        }

        if animated {
            withAnimation(.easeInOut(duration: Self.updatedTransitionDuration), updates)
        } else {
            updates()
        }
    }

    private func presentUpdatedFeedback() {
        dismissalTask?.cancel()
        withAnimation(.easeInOut(duration: Self.updatedTransitionDuration)) {
            isShowingUpdated = true
            updateButtonLayout(animated: false)
        }
        hapticTrigger += 1
        triggerUpdatedTransitionPulse()
        dismissalTask = Task {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            await MainActor.run {
                triggerUpdatedTransitionPulse()
                withAnimation(.easeInOut(duration: Self.updatedTransitionDuration)) {
                    isShowingUpdated = false
                    updateButtonLayout(animated: false)
                }
            }
        }
    }

    private func handleTap() {
        triggerPulse()
        action()
    }

    private func triggerUpdatedTransitionPulse() {
        updatedPulseTask?.cancel()
        let halfDuration = Self.updatedTransitionDuration / 2
        updatedPulseTask = Task {
            withAnimation(.easeInOut(duration: halfDuration)) {
                pulseScale = 1.05
            }
            do {
                try await Task.sleep(for: .seconds(halfDuration))
            } catch {
                return
            }
            withAnimation(.easeInOut(duration: halfDuration)) {
                pulseScale = 1
            }
        }
    }

    private func triggerPulse() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.52)) {
            pulseScale = 1.05
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                pulseScale = 1.0
            }
        }
    }
}

private struct CanvasModeUpdatedWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
