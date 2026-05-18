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
    var ripple:        RippleTrigger? = nil

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

    private let worldSpacing:  CGFloat = 18
    private let baseDotRadius: CGFloat = 1.0

    @Environment(\.colorScheme) private var colorScheme

    private var effectiveOffset: CGSize {
        CGSize(
            width:  settledOffset.width  + dragOffset.width,
            height: settledOffset.height + dragOffset.height
        )
    }

    private var baseColor: Color {
        colorScheme == .dark
            ? Color(red: 0.85, green: 0.80, blue: 0.65)
            : Color(red: 0.44, green: 0.41, blue: 0.27)
    }

    var body: some View {
        // TimelineView drives the noise field at display refresh rate.
        // Animatable drives the camera interpolation at the same rate during springs.
        TimelineView(.animation) { timeline in
            let t  = timeline.date.timeIntervalSinceReferenceDate
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

                // Pre-compute ripple screen origin once per frame (world → screen).
                // The ripple tracks the tapped node as the camera springs to it.
                var rippleOX: Double = 0
                var rippleOY: Double = 0
                var rippleDt: Double = -1
                let rippleDuration = 2.4
                if let ripple {
                    rippleDt = t - ripple.startTime
                    if rippleDt >= 0 && rippleDt < rippleDuration {
                        rippleOX = Double(size.width  / 2)
                                 + Double(ripple.worldOrigin.x) * Double(es)
                                 + Double(eo.width)
                        rippleOY = Double(size.height / 2)
                                 - Double(ripple.worldOrigin.y) * Double(es)
                                 + Double(eo.height)
                    } else {
                        rippleDt = -1   // expired — skip per-dot math
                    }
                }

                for c in 0...col {
                    for r in 0...row {
                        let sx = startX + CGFloat(c) * screenSpacing
                        let sy = startY + CGFloat(r) * screenSpacing

                        // Convert to world coords so the noise field is world-anchored.
                        let wx = (sx - size.width  / 2 - eo.width)  / es
                        let wy = (sy - size.height / 2 - eo.height) / es

                        var boost = 0.0
                        if rippleDt >= 0 {
                            let dist     = hypot(Double(sx) - rippleOX, Double(sy) - rippleOY)
                            let progress = rippleDt / rippleDuration            // 0 → 1

                            // Quartic ease-out: bursts fast then crawls to ~400 px.
                            let waveRadius    = 400.0 * (1.0 - pow(1.0 - progress, 4.0))
                            let waveWidth     = 95.0
                            let distFromFront = dist - waveRadius

                            if distFromFront > -waveWidth && distFromFront < 8 {
                                let norm  = max(-1.0, distFromFront / waveWidth)
                                let bump  = cos(norm * Double.pi / 2)
                                // Ease-in fade: holds brightness then drops off at end.
                                let decay = 1.0 - pow(progress, 2.2)
                                boost = bump * bump * decay * 0.12
                            }
                        }

                        let opacity = min(blobOpacity(worldX: Double(wx),
                                                      worldY: Double(wy),
                                                      t: t) + boost, 0.85)

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

    /// Three overlapping sine waves produce smooth organic blob regions.
    /// Opacity range ≈ 0.02–0.23 (subtle but visible).
    private func blobOpacity(worldX: Double, worldY: Double, t: Double) -> Double {
        let x = worldX * 0.022
        let y = worldY * 0.022

        let v1 = sin(x * 1.1  + t * 0.22) * cos(y * 0.95 + t * 0.17)
        let v2 = sin(x * 0.65 - y * 0.75  + t * 0.31) * 0.55
        let v3 = cos(x * 1.4  + y * 1.05  - t * 0.19) * 0.38

        let raw        = (v1 + v2 + v3) / 1.93
        let normalised = (raw + 1.0) / 2.0
        let shaped     = normalised * normalised   // soft-knee: peaks bloom, base stays dark

        return 0.02 + shaped * 0.21
    }
}
