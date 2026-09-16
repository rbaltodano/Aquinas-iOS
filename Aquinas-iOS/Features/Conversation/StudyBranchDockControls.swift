//
//  StudyBranchDockControls.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

/// The persistent dock content shown while Branch is the active Study tool.
struct StudyBranchDockControls: View {
    private enum Layout {
        static let controlHeight: CGFloat = 68
        static let countPillWidth: CGFloat = 230
        static let placePillWidth: CGFloat = 118
        static let interPillSpacing: CGFloat = 8
    }

    let count: Int
    let onCountChange: (Int) -> Void

    @State private var showsPlaceAction = false

    var body: some View {
        HStack(spacing: Layout.interPillSpacing) {
            HStack(spacing: 14) {
                Button(action: increment) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 14, height: 24)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle().inset(by: -15))
                .disabled(count >= 6)
                .opacity(count >= 6 ? 0.4 : 1)
                .accessibilityLabel("Add an Insight")

                Text("\(count)", comment: "Number of Insights to create.")
                    .font(.custom("Figtree-Bold", size: 14, relativeTo: .subheadline))
                Text("New Insights")
                    .font(.custom("Figtree-SemiBold", size: 14, relativeTo: .subheadline))

                Button(action: decrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 14, height: 24)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle().inset(by: -15))
                .disabled(count <= 2)
                .opacity(count <= 2 ? 0.4 : 1)
                .accessibilityLabel("Remove an Insight")
            }
            .foregroundStyle(AquinasTheme.Colors.paragraphText.opacity(0.75))
            .padding(.horizontal, 32)
            .frame(
                width: showsPlaceAction
                    ? Layout.countPillWidth
                    : Layout.countPillWidth + Layout.placePillWidth + Layout.interPillSpacing,
                height: Layout.controlHeight
            )
            .background(AquinasTheme.Colors.canvasSecondary, in: Capsule())
            .overlay {
                Capsule().stroke(AquinasTheme.Colors.paragraphText.opacity(0.04), lineWidth: 1)
            }

            Button(action: place) {
                Label("Place", systemImage: "arrow.down")
                    .font(.custom("Figtree-Bold", size: 14, relativeTo: .subheadline))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AquinasTheme.Colors.lightGreen)
            .frame(width: Layout.placePillWidth, height: Layout.controlHeight)
            .background(AquinasTheme.Colors.canvasSecondary, in: Capsule())
            .overlay {
                Capsule().stroke(AquinasTheme.Colors.paragraphText.opacity(0.04), lineWidth: 1)
            }
            .frame(width: showsPlaceAction ? Layout.placePillWidth : 0)
            .clipped()
            .opacity(showsPlaceAction ? 1 : 0)
            .blur(radius: showsPlaceAction ? 0 : 8)
            .scaleEffect(showsPlaceAction ? 1 : 1.05)
            .allowsHitTesting(showsPlaceAction)
            .accessibilityLabel("Place \(count) new Insights")
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: showsPlaceAction)
        .onAppear {
            showsPlaceAction = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82).delay(0.18)) {
                showsPlaceAction = true
            }
        }
    }

    private func increment() {
        guard count < 6 else { return }
        onCountChange(count + 1)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.62)
    }

    private func decrement() {
        guard count > 2 else { return }
        onCountChange(count - 1)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.62)
    }

    private func place() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
    }
}
