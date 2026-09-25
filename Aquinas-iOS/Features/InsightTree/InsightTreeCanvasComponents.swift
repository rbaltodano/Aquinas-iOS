//
//  InsightTreeCanvasComponents.swift
//  Aquinas-iOS
//

import SwiftUI

struct AnimatableLine: Shape {
    var start: CGPoint
    var end: CGPoint

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(start.x, start.y),
                AnimatablePair(end.x, end.y)
            )
        }
        set {
            start = CGPoint(x: newValue.first.first, y: newValue.first.second)
            end = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
    }
}

/// A connector between a Node and one of its Insights. The parent controls when this view is
/// inserted, so the line itself stays stateless while the camera is moving its endpoints.
struct InsightConnectorLine: View {
    var start: CGPoint
    var end: CGPoint
    var color: Color
    /// A new Insight's connector draws itself out from the Node Concept to the chip.
    @State private var drawn: CGFloat

    init(start: CGPoint, end: CGPoint, color: Color, grows: Bool = false) {
        self.start = start
        self.end = end
        self.color = color
        _drawn = State(initialValue: grows ? 0 : 1)
    }

    /// Quick out of the node, then a long, soft settle into the chip (an ease-out quint).
    static let growAnimation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.55)

    var body: some View {
        AnimatableLine(start: start, end: end)
            .trim(from: 0, to: drawn)
            .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round))
            .onAppear {
                guard drawn < 1 else { return }
                withAnimation(Self.growAnimation) { drawn = 1 }
            }
    }
}

/// The selection-mode reticle: a small circle indicating where the next insight connects.
struct SelectionReticle: View {
    var body: some View {
        Circle()
            .stroke(AquinasTheme.Colors.lightGreen.opacity(0.8), lineWidth: 1.5)
            .frame(width: 18, height: 18)
    }
}

/// Draggable midpoint placement handle: a small circle with a bobbing text.bubble icon above it.
/// The bob uses a TimelineView so it never gets interrupted when the handle's position changes.
struct MidpointHandle: View {
    @State private var startTime: TimeInterval = 0

    private let circleSize: CGFloat = 18
    private let bottomGap: CGFloat = 4   // px above circle edge at the lowest point
    private let topGap: CGFloat = 12     // px above circle edge at the highest point
    private let period: Double = 1.0     // full cycle in seconds (1 oscillation/sec)

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = startTime > 0
                ? timeline.date.timeIntervalSinceReferenceDate - startTime
                : 0
            // Smooth cosine oscillation: 0 at bottom, 1 at top, back to 0.
            let t = elapsed.truncatingRemainder(dividingBy: period) / period
            let phase = CGFloat((1.0 - cos(t * .pi * 2.0)) / 2.0)

            let iconHalf: CGFloat = 7
            let bottomOffset = -(circleSize / 2 + bottomGap + iconHalf)
            let topOffset    = -(circleSize / 2 + topGap    + iconHalf)
            let yOffset = bottomOffset + (topOffset - bottomOffset) * phase

            ZStack(alignment: .bottom) {
                Circle()
                    .fill(AquinasTheme.Colors.lightGreen)
                    .frame(width: circleSize, height: circleSize)
                    .overlay(Circle().stroke(AquinasTheme.Colors.canvas, lineWidth: 2))
                    .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)

                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AquinasTheme.Colors.lightGreen)
                    .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)
                    .opacity(Double(1.0 - phase * 0.5))   // 100% at bottom, 50% at top
                    .offset(y: yOffset)
            }
            .frame(width: circleSize, height: circleSize)
        }
        .onAppear {
            startTime = Date().timeIntervalSinceReferenceDate
        }
    }
}

/// Insight chip contents: the bubble icon + the title. As `labelOpacity` fades with zoom, the
/// title's *width* animates to 0 (a true ease, not a discrete display:none), so the chip
/// smoothly collapses to just the icon.
struct RevealedInsightLabel: View {
    let title: String
    let labelOpacity: Double

    @State private var titleWidth: CGFloat = 0
    /// Animated width state — toggled (with an explicit ease) when the fade crosses 0, so the
    /// per-frame canvas re-render can't swallow an implicit animation.
    @State private var showTitle: Bool = true

    /// Title keeps full width through the whole fade; it only collapses once opacity hits 0.
    private var collapsed: Bool { labelOpacity <= 0.01 }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AquinasTheme.Colors.lightGreen)
            Text(title)
                .font(.figtreeHeading2)
                .foregroundStyle(AquinasTheme.Colors.lightGreen)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, 10)               // icon↔title gap, collapses with the width
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { titleWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in if w > 0 { titleWidth = w } }
                    }
                )
                .frame(width: titleWidth == 0 ? nil : (showTitle ? titleWidth : 0), alignment: .leading)
                .clipped()
                .opacity(showTitle ? labelOpacity : 0)
        }
        .onAppear { showTitle = !collapsed }
        .onChange(of: collapsed) { _, isCollapsed in
            // Defer to the next runloop tick so the animation escapes the pinch-gesture
            // transaction (which has animations disabled) — otherwise manual zoom wouldn't ease.
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showTitle = !isCollapsed
                }
            }
        }
    }
}

/// A title that reveals one letter at a time (blur + fade + drift), staggered left to right.
/// Used for the dramatic entrance of a placed-midpoint insight.
private struct LetterRevealText: View {
    let text: String
    let font: Font
    let color: Color
    var perLetterDelay: Double = 0.045

    @State private var revealed = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(character == " " ? "\u{00A0}" : String(character))
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize()
                    .opacity(revealed ? 1 : 0)
                    .blur(radius: revealed ? 0 : 6)
                    .offset(y: revealed ? 0 : 8)
                    .animation(
                        .easeOut(duration: 0.45).delay(Double(index) * perLetterDelay),
                        value: revealed
                    )
            }
        }
        .onAppear { revealed = true }
    }
}

/// Blur + fade + slight upward drift, used when a freshly-loaded insight title appears.
private struct BlurUpModifier: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let offsetY: CGFloat
    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .offset(y: offsetY)
    }
}

extension AnyTransition {
    static var blurUp: AnyTransition {
        .modifier(
            active: BlurUpModifier(blur: 8, opacity: 0, offsetY: 8),
            identity: BlurUpModifier(blur: 0, opacity: 1, offsetY: 0)
        )
    }

    /// Fade + blur, no transform — used to dissolve the hollow loading icon out.
    static var fadeBlur: AnyTransition {
        .modifier(
            active: BlurUpModifier(blur: 6, opacity: 0, offsetY: 0),
            identity: BlurUpModifier(blur: 0, opacity: 1, offsetY: 0)
        )
    }
}

/// A VectorArithmetic backing for an arbitrary-length list of coordinates, so a
/// polygon with N points can interpolate smoothly during camera animations.
struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    static var zero: AnimatableVector { AnimatableVector(values: []) }

    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        AnimatableVector(values: zipPadded(lhs.values, rhs.values, +))
    }

    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        AnimatableVector(values: zipPadded(lhs.values, rhs.values, -))
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    private static func zipPadded(_ a: [Double], _ b: [Double], _ op: (Double, Double) -> Double) -> [Double] {
        let count = Swift.max(a.count, b.count)
        return (0..<count).map { op($0 < a.count ? a[$0] : 0, $0 < b.count ? b[$0] : 0) }
    }
}

/// Animatable closed polygon through the given screen points.
struct PolygonShape: Shape {
    var points: [CGPoint]

    var animatableData: AnimatableVector {
        get { AnimatableVector(values: points.flatMap { [Double($0.x), Double($0.y)] }) }
        set {
            let v = newValue.values
            var pts: [CGPoint] = []
            var i = 0
            while i + 1 < v.count {
                pts.append(CGPoint(x: v[i], y: v[i + 1]))
                i += 2
            }
            points = pts
        }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for pt in points.dropFirst() { path.addLine(to: pt) }
            path.closeSubpath()
        }
    }
}

struct SelectedCanvasInsightBorder: View {
    @State private var drawProgress: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .inset(by: 0.5)
            .trim(from: 0, to: drawProgress)
            .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
            .onAppear {
                drawProgress = 0
                withAnimation(.easeOut(duration: 0.55).delay(0.05)) {
                    drawProgress = 1
                }
            }
    }
}
