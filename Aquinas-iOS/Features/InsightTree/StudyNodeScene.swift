//
//  StudyNodeScene.swift
//  Aquinas-iOS
//

import SwiftUI
import simd

/// The coordinate space shared by the Insight Tree canvas and the Study overlay, so the canvas
/// can frame a Node Concept into the Study slot laid out by the overlay.
enum InsightTreeStackSpace {
    static let name = "insightTreeStack"
}

/// Camera framing for studying a Node Concept in the tree canvas itself: the tree's camera
/// shifts from its own framing to this one, so the node the user tapped is the node they study.
///
/// Figma 944:1478 / 944:1480: a floor ring spans the 300 × 300 slot's full width as a
/// 300 × 42 ellipse. The Node Concept sits 160 pt below the slot's top, and the ring as low as
/// the space above the docked card allows (`ringCenterY`), both lower than the mockup to leave
/// more room around the node.
///
/// The camera is level with the node, so the ring's thickness comes only from looking down at
/// it: an angle α below the horizon with sin α = 39/297 (the ring's centerline height over its
/// width). For a screen drop d from node to ring, the floor sits d / zoom below the node and the
/// camera d / (zoom · tan α) away. Checked against `OrbitCamera` for drops of 160–420 pt: the
/// ring stays 297–299 × 39–40 and lands within 2 pt of `ringCenterY`. A lower ring puts the
/// camera farther away, so depth scaling between near and far chips gets gentler.
struct StudyFraming {
    /// The Node Concept's position on the graph plane.
    let nodeCenter: SIMD3<Double>
    /// Radius of the Insight sphere: the cluster's mean bond, so the sphere matches the tree.
    let radius: Double
    /// The Study slot, in the canvas's own coordinates.
    let slot: CGRect
    /// Where the ring's center should land, in the canvas's own coordinates.
    let ringCenterY: CGFloat

    static let studyPitch: Double = .pi / 2
    static let nodeOffsetFromSlotTop: CGFloat = 160
    static let ringRadiusRatio = 1.35
    /// Screen points per world unit, times the sphere radius, for a 300 pt slot.
    static let zoomTimesRadius = 110.0
    /// The ring's apparent thickness: its centerline ellipse is 39 pt tall for 297 pt wide.
    static let ringViewAngle = asin(39.0 / 297.0)
    /// Keeps the ring clear of the node's lower Insights when space is tight.
    static let minimumRingDrop: CGFloat = 160

    var nodeY: CGFloat { slot.minY + Self.nodeOffsetFromSlotTop }
    var ringDrop: CGFloat { max(ringCenterY - nodeY, Self.minimumRingDrop) }
    var ringRadius: Double { radius * Self.ringRadiusRatio }
    var studyZoom: Double { Self.zoomTimesRadius / radius * Double(min(slot.width, slot.height)) / 300 }
    var floorDepth: Double { Double(ringDrop) / studyZoom }
    var studyDistance: Double { floorDepth / tan(Self.ringViewAngle) }

    /// Study opens this much closer on the node than the framing (the ring is unaffected).
    static let entryZoom: CGFloat = 2
    /// Hovering zooms in to at least this: the tree's hover zoom (`focusHoveredTarget` zooms to
    /// at least 1.15) measured from Study's opening zoom. Already closer, it doesn't zoom.
    static let hoverZoom: CGFloat = entryZoom * 1.15

    /// The extra zoom a hover adds on top of the user's `zoom`.
    static func hoverZoomFactor(zoom: CGFloat) -> CGFloat {
        max(hoverZoom / max(zoom, 0.01), 1)
    }

    /// The tree's hover camera curve (`focusHoveredTarget`), so Study hovers move the same way.
    static let hoverSpring = Spring(response: 0.58, dampingRatio: 0.64)
    /// A focused Insight sits this far below where the node sits.
    static let pivotDrop: CGFloat = 70

    /// The camera `progress` of the way from `start` (the tree's framing) to Study. `yaw`,
    /// `pan`, and `zoom` are the user's Study adjustments and take full effect at progress 1.
    /// `pivot` is a focused Insight: `pivotBlend` of the way to it, the camera centers it where
    /// the node sat, zooms in, and turns around it instead of the node. `targetShift` moves what
    /// the camera looks at away from the axis of rotation, so a released focus can hand the axis
    /// back to the node without moving the view (`OrbitCamera.rotationCenter`).
    func camera(
        from start: OrbitCamera,
        progress p: Double,
        yaw: Double = 0,
        pan: CGSize = .zero,
        zoom: CGFloat = 1,
        pivot: SIMD3<Double>? = nil,
        pivotBlend: Double = 0,
        targetShift: SIMD3<Double> = .zero
    ) -> OrbitCamera {
        let blend = pivot == nil ? 0 : pivotBlend
        // A focused Insight is centered, so any pan eases out as the focus eases in.
        let end = CGPoint(
            x: slot.midX + pan.width * (1 - blend),
            y: nodeY + pan.height * (1 - blend) + Self.pivotDrop * blend
        )
        let fitZoom = studyZoom * Double(zoom) * (1 + (Double(Self.hoverZoomFactor(zoom: zoom)) - 1) * blend)
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * p }
        let nodeTarget = start.target + (nodeCenter - start.target) * p
        // Scaled by progress too, so Study can open already focused on an Insight and still
        // start exactly from the tree's view.
        let center = nodeTarget + ((pivot ?? nodeTarget) - nodeTarget) * blend * p
        return OrbitCamera(
            // A focused Insight is centered, so any shift eases out as the focus eases in.
            target: center + targetShift * (1 - blend) * p,
            yaw: yaw * p,
            pitch: lerp(start.pitch, Self.studyPitch),
            distance: lerp(start.distance, studyDistance),
            // Zoom interpolates geometrically so the move feels even at both ends.
            zoom: start.zoom * pow(fitZoom / max(start.zoom, 1e-6), p),
            principalPoint: CGPoint(
                x: lerp(start.principalPoint.x, end.x),
                y: lerp(start.principalPoint.y, end.y)
            ),
            rotationCenter: center
        )
    }

    /// The floor ring's outline through `camera`.
    func ringPoints(camera: OrbitCamera, segments: Int = 96) -> [CGPoint] {
        (0..<segments).compactMap { index in
            let angle = Double(index) / Double(segments) * 2 * .pi
            let point = nodeCenter + SIMD3(cos(angle) * ringRadius, sin(angle) * ringRadius, -floorDepth)
            return camera.project(point)?.position
        }
    }

    static let dashCount = 60
    /// The share of each dash's slot that is drawn.
    static let dashFill = 0.5

    /// The ring as dashes: arcs on the floor, turned by `yaw` with the node, so spinning the ring
    /// carries its dashes around and perspective shortens the far ones naturally.
    func ringDashes(camera: OrbitCamera, yaw: Double) -> [[CGPoint]] {
        let slot = 2 * Double.pi / Double(Self.dashCount)
        return (0..<Self.dashCount).map { index in
            let start = Double(index) * slot - yaw
            return (0...4).compactMap { step in
                let angle = start + slot * Self.dashFill * Double(step) / 4
                let point = nodeCenter + SIMD3(cos(angle) * ringRadius, sin(angle) * ringRadius, -floorDepth)
                return camera.project(point)?.position
            }
        }
    }

    /// Floor dots are this far apart on screen where the ring sits.
    static let floorDotSpacing: CGFloat = 20
    /// How far past the node the floor runs before it has faded out, in camera distances.
    static let floorReach = 1.5

    /// Floor dot spacing in world units.
    var floorSpacing: Double { Double(Self.floorDotSpacing) / studyZoom }

    struct FloorDot {
        let column: Int
        let row: Int
        let projection: OrbitCamera.Projection
    }

    /// The floor dots on screen through `camera`, within the floor's reach. Walks only the
    /// visible patch: in the camera's turned frame (u across, v away) it is a trapezoid, and
    /// each grid row is a line through it, so clipping the line against the trapezoid's four
    /// edges gives exactly its visible dots, at any rotation, pan, or zoom.
    func visibleFloorDots(camera: OrbitCamera, size: CGSize) -> [FloorDot] {
        let spacing = floorSpacing
        let pitchSine = sin(camera.pitch), pitchCosine = cos(camera.pitch)
        guard pitchSine > 0.2 else { return [] }   // too near overhead to be a floor yet

        let center = camera.rotationCenter ?? camera.target
        let floorOrigin = nodeCenter + SIMD3(0, 0, -floorDepth)
        let base = OrbitCamera.turn(floorOrigin - center, by: camera.yaw) + (center - camera.target)
        let stepI = OrbitCamera.turn(SIMD3(spacing, 0, 0), by: camera.yaw)
        let stepJ = OrbitCamera.turn(SIMD3(0, spacing, 0), by: camera.yaw)

        // depth = d0 + v·sin(pitch); screen x = pp.x + u·zoom·D / depth.
        let distance = camera.distance
        let d0 = distance - base.z * pitchCosine
        let reach = distance * Self.floorReach
        let vNear = (distance * 0.15 - d0) / pitchSine
        let vFar = (distance + reach - d0) / pitchSine
        let margin = 8.0
        let kMin = (-Double(camera.principalPoint.x) - margin) / (camera.zoom * distance)
        let kMax = (Double(size.width) - Double(camera.principalPoint.x) + margin) / (camera.zoom * distance)
        func depth(_ v: Double) -> Double { d0 + v * pitchSine }

        // Row range from the trapezoid's corners in grid coordinates.
        let determinant = stepI.x * stepJ.y - stepI.y * stepJ.x
        guard abs(determinant) > 1e-9 else { return [] }
        let corners = [(kMin * depth(vNear), vNear), (kMax * depth(vNear), vNear),
                       (kMin * depth(vFar), vFar), (kMax * depth(vFar), vFar)]
        let rows = corners.map { u, v in
            (stepI.x * (v - base.y) - stepI.y * (u - base.x)) / determinant
        }
        guard let firstRow = rows.min(), let lastRow = rows.max(),
              firstRow.isFinite, lastRow.isFinite else { return [] }

        var dots: [FloorDot] = []
        for row in Int(firstRow.rounded(.down))...Int(lastRow.rounded(.up)) {
            let cu = base.x + Double(row) * stepJ.x
            let cv = base.y + Double(row) * stepJ.y
            // i satisfies A·i ≤ B for each edge.
            var low = -Double.infinity, high = Double.infinity
            func clip(_ a: Double, _ b: Double) {
                if abs(a) < 1e-12 { if b < 0 { low = .infinity } }
                else if a > 0 { high = min(high, b / a) }
                else { low = max(low, b / a) }
            }
            clip(-stepI.y, cv - vNear)                                                     // v ≥ near
            clip(stepI.y, vFar - cv)                                                       // v ≤ far
            clip(stepI.x - kMax * pitchSine * stepI.y, kMax * (d0 + pitchSine * cv) - cu)  // u ≤ right
            clip(kMin * pitchSine * stepI.y - stepI.x, cu - kMin * (d0 + pitchSine * cv))  // u ≥ left
            // A row can cross the patch between two dots, leaving no column inside.
            guard low <= high, low.isFinite, high.isFinite else { continue }
            let firstColumn = Int(low.rounded(.up)), lastColumn = Int(high.rounded(.down))
            guard firstColumn <= lastColumn else { continue }

            for column in firstColumn...lastColumn {
                let point = floorOrigin + SIMD3(Double(column) * spacing, Double(row) * spacing, 0)
                guard let projected = camera.project(point),
                      projected.position.y > -4, projected.position.y < size.height + 4
                else { continue }
                dots.append(FloorDot(column: column, row: row, projection: projected))
            }
        }
        return dots
    }

    static func distance(from point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return .infinity }
        var best = CGFloat.infinity
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let lengthSquared = ab.x * ab.x + ab.y * ab.y
            let t = lengthSquared > 0
                ? min(max(((point.x - a.x) * ab.x + (point.y - a.y) * ab.y) / lengthSquared, 0), 1)
                : 0
            let closest = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
            best = min(best, hypot(point.x - closest.x, point.y - closest.y))
        }
        return best
    }
}

/// The Study floor ring (Figma 944:1480): a dashed 3 pt stroke with a vertical gradient over
/// its own bounds, 5% at the far edge to 40% at the near edge. While a finger is on it
/// (`activeAmount` 1) it is brighter and 5% larger; animate `activeAmount` for an eased press.
struct StudyFloorRing: View, Animatable {
    /// The full outline, for the ring's bounds.
    let points: [CGPoint]
    /// The dashes actually drawn (`StudyFraming.ringDashes`).
    let dashes: [[CGPoint]]
    var activeAmount: Double

    var animatableData: Double {
        get { activeAmount }
        set { activeAmount = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            guard points.count > 1,
                  let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                  let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return }
            // Grow about the ring's own center.
            let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            let scale = 1 + 0.05 * activeAmount
            func scaled(_ point: CGPoint) -> CGPoint {
                CGPoint(x: center.x + (point.x - center.x) * scale, y: center.y + (point.y - center.y) * scale)
            }
            var path = Path()
            for dash in dashes where dash.count > 1 {
                path.move(to: scaled(dash[0]))
                for point in dash.dropFirst() { path.addLine(to: scaled(point)) }
            }
            let top = center.y + (minY - center.y) * scale
            let bottom = center.y + (maxY - center.y) * scale
            // The gradient starts 37% of the way down the ring (Figma: y 15.5 of 42).
            let gradient = Gradient(colors: [
                AquinasTheme.Colors.primaryBrown.opacity(0.05 + 0.07 * activeAmount),
                AquinasTheme.Colors.primaryBrown.opacity(0.4 + 0.3 * activeAmount),
            ])
            let shading = GraphicsContext.Shading.linearGradient(
                gradient,
                startPoint: CGPoint(x: center.x, y: top + (bottom - top) * 0.37),
                endPoint: CGPoint(x: center.x, y: bottom)
            )
            context.stroke(path, with: shading, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

/// The tree's dot grid laid on the floor the ring rests on, receding toward the horizon: dots
/// shrink with distance and fade out as they near it. It is fixed to the world and drawn
/// through the node's camera, so it turns, zooms, and pans 1:1 with the node. Uses the tree
/// grid's color and drifting brightness, at half opacity, so it reads as the same grid tipped up.
struct StudyFloorGrid: View {
    let framing: StudyFraming
    let camera: OrbitCamera

    @Environment(\.colorScheme) private var colorScheme

    private static let opacity = 0.5

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(in: &context, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let color = AnimatedDotGridBackground.dotColor(for: colorScheme)
        let opacityScale = AnimatedDotGridBackground.dotOpacityScale(for: colorScheme)
        let spacing = framing.floorSpacing
        // Brightness drifts in grid units, 16 per dot like the tree's grid.
        let fieldScale = 16 / spacing
        let reach = camera.distance * StudyFraming.floorReach
        for dot in framing.visibleFloorDots(camera: camera, size: size) {
            // Fade out over the far 60% of the reach.
            let beyond = min(max((dot.projection.depth - camera.distance) / reach, 0), 1)
            let edge = min(max((beyond - 0.4) / 0.6, 0), 1)
            let fade = 1 - edge * edge * (3 - 2 * edge)
            guard fade > 0.01 else { continue }
            let opacity = min(
                AnimatedDotGridBackground.blobOpacity(
                    worldX: Double(dot.column) * spacing * fieldScale,
                    worldY: Double(dot.row) * spacing * fieldScale,
                    time: time
                ) * opacityScale,
                0.85
            ) * fade * Self.opacity
            let position = dot.projection.position
            let radius = min(max(0.9 * dot.projection.scale * camera.zoom / framing.studyZoom, 0.35), 2)
            context.fill(
                Path(ellipseIn: CGRect(x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(color.opacity(opacity))
            )
        }
    }
}
