//
//  AnimatedDotGridBackground.swift
//  Aquinas-iOS
//

import SwiftUI

// MARK: - Ripple Trigger

/// Carries the world-space origin and start time of a tap ripple.
/// World-space so the origin tracks the node as the camera springs to it.
struct RippleTrigger {
    let worldOrigin: CGPoint
    let startTime:   Double   // Date().timeIntervalSinceReferenceDate
}

// MARK: - Animated Dot Grid

/// Dense dot grid rendered in world space (pan + zoom with the canvas camera).
/// Dot opacity is driven by a layered sine-wave blob field drifting over time.
///
/// Conforms to Animatable so SwiftUI's spring engine interpolates settledOffset
/// and settledScale frame-by-frame during focusInsight — the same way it animates
/// Shapes — instead of the value jumping to its final position on frame 1.
///
/// dragOffset is NOT in animatableData: it applies immediately so panning
/// feels instant with no spring lag.
struct AnimatedDotGridBackground: View, Animatable {

    var settledOffset: CGSize
    var settledScale:  CGFloat
    var dragOffset:    CGSize = .zero
    var ripples:       [RippleTrigger] = []

    // Tells SwiftUI which values to interpolate during withAnimation.
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get {
            AnimatablePair(
                AnimatablePair(settledOffset.width, settledOffset.height),
                settledScale
            )
        }
        set {
            settledOffset = CGSize(width: newValue.first.first,
                                   height: newValue.first.second)
            settledScale  = newValue.second
        }
    }

    private let worldSpacing:  CGFloat = 16
    private let baseDotRadius: CGFloat = 0.8

    @Environment(\.colorScheme) private var colorScheme

    private var effectiveOffset: CGSize {
        CGSize(
            width:  settledOffset.width  + dragOffset.width,
            height: settledOffset.height + dragOffset.height
        )
    }

    private var baseColor: Color {
        colorScheme == .dark
            ? Color(hex: 0xB7AE78)
            : Color(hex: 0x4A321C)
    }

    private var opacityScale: Double {
        colorScheme == .dark ? 1.0 : 1.6
    }

    private var rippleBoostScale: Double {
        colorScheme == .dark ? 0.15 : 0.25
    }

    var body: some View {
        // TimelineView drives the noise field at display refresh rate.
        // Animatable drives the camera interpolation at the same rate during springs.
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let eo = effectiveOffset
            let es = settledScale

            Canvas { context, size in
                let screenSpacing = worldSpacing * es
                guard screenSpacing > 1 else { return }

                let dotRadius = min(max(baseDotRadius * es, 0.4), 3.0)

                // Grid anchored to world origin so it tracks pan + zoom.
                let originScreenX = size.width  / 2 + eo.width
                let originScreenY = size.height / 2 + eo.height

                let phaseX = originScreenX.truncatingRemainder(dividingBy: screenSpacing)
                let phaseY = originScreenY.truncatingRemainder(dividingBy: screenSpacing)

                let startX = phaseX - screenSpacing
                let startY = phaseY - screenSpacing

                let col = min(Int((size.width  / screenSpacing).rounded(.up)) + 2, 120)
                let row = min(Int((size.height / screenSpacing).rounded(.up)) + 2, 120)

                let rippleDuration = 2.4

                // Precompute the active ripples (screen origin + elapsed time) once per frame.
                let activeRipples: [(ox: Double, oy: Double, dt: Double)] = ripples.compactMap { ripple in
                    let dt = t - ripple.startTime
                    guard dt >= 0 && dt < rippleDuration else { return nil }
                    let ox = Double(size.width / 2)
                        + Double(ripple.worldOrigin.x) * Double(es)
                        + Double(eo.width)
                    let oy = Double(size.height / 2)
                        - Double(ripple.worldOrigin.y) * Double(es)
                        + Double(eo.height)
                    return (ox, oy, dt)
                }

                for c in 0...col {
                    for r in 0...row {
                        let sx = startX + CGFloat(c) * screenSpacing
                        let sy = startY + CGFloat(r) * screenSpacing

                        let wx = (sx - size.width / 2 - eo.width) / es
                        let wy = (sy - size.height / 2 - eo.height) / es

                        var boost = 0.0
                        for ar in activeRipples {
                            let distance = hypot(Double(sx) - ar.ox, Double(sy) - ar.oy)
                            let progress = ar.dt / rippleDuration
                            let waveRadius = 400 * (1 - pow(1 - progress, 4))
                            let waveWidth = 95.0
                            let distanceFromFront = distance - waveRadius

                            if distanceFromFront > -waveWidth && distanceFromFront < 8 {
                                let normalizedDistance = max(-1, distanceFromFront / waveWidth)
                                let bump = cos(normalizedDistance * Double.pi / 2)
                                let decay = 1 - pow(progress, 2.2)
                                boost += bump * bump * decay * rippleBoostScale
                            }
                        }

                        let opacity = min(
                            (blobOpacity(
                                worldX: Double(wx),
                                worldY: Double(wy),
                                time: t
                            ) + boost) * opacityScale,
                            0.85
                        )

                        let rect = CGRect(
                            x: sx - dotRadius, y: sy - dotRadius,
                            width: dotRadius * 2, height: dotRadius * 2
                        )
                        context.fill(Path(ellipseIn: rect),
                                     with: .color(baseColor.opacity(opacity)))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private func blobOpacity(worldX: Double, worldY: Double, time: Double) -> Double {
        let x = worldX * 0.022
        let y = worldY * 0.022

        let wave1 = sin(x * 1.1 + time * 0.22) * cos(y * 0.95 + time * 0.17)
        let wave2 = sin(x * 0.65 - y * 0.75 + time * 0.31) * 0.55
        let wave3 = cos(x * 1.4 + y * 1.05 - time * 0.19) * 0.38

        let normalized = ((wave1 + wave2 + wave3) / 1.93 + 1) / 2
        return 0.01 + pow(normalized, 4) * 0.28
    }
}
