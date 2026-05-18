//
//  AnimatedDotGridBackground.swift
//  Aquinas-iOS
//

import SwiftUI

// MARK: - Animated Dot Grid

/// Full-screen dot grid that drifts slowly in one direction, looping seamlessly
/// every time it advances by one grid cell (spacing = 24 pt).
struct AnimatedDotGridBackground: View {
    private let spacing: CGFloat = 24
    private let dotRadius: CGFloat = 1

    @State private var offset: CGFloat = 0

    var body: some View {
        // Canvas already provides `size` — no GeometryReader needed.
        Canvas { context, size in
            let col = Int((size.width  / spacing).rounded(.up)) + 2
            let row = Int((size.height / spacing).rounded(.up)) + 2

            // Shift start point so the grid scrolls diagonally and tiles seamlessly.
            let phase = offset.truncatingRemainder(dividingBy: spacing)
            let originX = phase - spacing
            let originY = phase - spacing

            // .primary resolves to near-black in light mode and near-white in dark mode,
            // giving visible but quiet dots on both the cream and near-black canvas colors.
            let dotColor = Color.primary.opacity(0.1)

            for c in 0...col {
                for r in 0...row {
                    let cx = originX + CGFloat(c) * spacing
                    let cy = originY + CGFloat(r) * spacing
                    let rect = CGRect(
                        x: cx - dotRadius,
                        y: cy - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 25).repeatForever(autoreverses: false)) {
                offset = spacing
            }
        }
        .allowsHitTesting(false)
    }
}
