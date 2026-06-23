//
//  AquinasNavButton.swift
//  Aquinas-iOS
//

import SwiftUI

// MARK: - Aquinas Nav Button

/// Top-left navigation button used across all pages.
///
/// In its default state it shows the hamburger menu icon and calls `onMenuTap`.
/// When `isDetailVisible` is `true` (e.g. inside a detail view) it morphs to a
/// pill containing a back-chevron and a "Back" label, and calls `onBackTap` instead.
///
/// Both icon switches and programmatic `isDetailVisible` changes trigger a tactile
/// pulse. Icons cross-fade through an 8 pt blur so the transition feels soft.
struct AquinasNavButton: View {
    /// When `true`, shows the chevron + back label instead of the hamburger.
    var isDetailVisible: Bool = false
    /// Label shown to the right of the chevron when `isDetailVisible` is `true`.
    var backLabel: String = "Back"
    var onMenuTap: () -> Void
    var onBackTap: () -> Void = {}

    @State private var pulseScale: CGFloat = 1.0
    @State private var suppressNextPulse = false

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 8) {
                // ZStack keeps the icon slot fixed-size; if/else gives SwiftUI
                // true insertion/removal identity so the blur-fade fires.
                ZStack {
                    if isDetailVisible {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AquinasTheme.Colors.darkGreen)
                            .transition(.blurFade)
                    } else {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AquinasTheme.Colors.darkGreen)
                            .transition(.blurFade)
                    }
                }
                .frame(width: 18, height: 18)

                if isDetailVisible {
                    Text(backLabel)
                        .font(.custom("Figtree-Bold", size: 14))
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                        .transition(.blurFade)
                }
            }
            // padding of 15 makes the capsule exactly 48×48 with no text
            // (15 + 18 + 15 = 48) so it renders as a perfect circle.
            .padding(.horizontal, 15)
            .frame(height: 48)
            .background(AquinasTheme.Colors.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
            )
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isDetailVisible)
        }
        .buttonStyle(.plain)
        .scaleEffect(pulseScale)
        .accessibilityLabel(isDetailVisible ? "Back" : "Open side menu")
        .onChange(of: isDetailVisible) { _, _ in
            if suppressNextPulse {
                suppressNextPulse = false
            } else {
                triggerPulse()
            }
        }
    }

    private func handleTap() {
        triggerPulse()
        suppressNextPulse = true
        if isDetailVisible { onBackTap() } else { onMenuTap() }
    }

    private func triggerPulse() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.42)) {
            pulseScale = 1.14
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.58)) {
                pulseScale = 1.0
            }
        }
    }
}

// MARK: - Blur-fade transition

private struct NavIconBlurFade: ViewModifier {
    let opacity: Double
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blur)
    }
}

extension AnyTransition {
    /// Fades in/out while blurring from 8 pt → 0 (insertion) and 0 → 8 pt (removal).
    static var blurFade: AnyTransition {
        .modifier(
            active:   NavIconBlurFade(opacity: 0, blur: 8),
            identity: NavIconBlurFade(opacity: 1, blur: 0)
        )
    }
}
