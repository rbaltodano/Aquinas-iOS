//
//  StudyToolPrototype.swift
//  Aquinas-iOS
//

import SwiftUI
import simd
import UIKit

// PROTOTYPE (prototype/study-tools branch, Lab builds only). Explores how Study tool results
// appear in 3D and flatten into the 2D tree. Results are clearly labeled placeholders, not
// model output, and live only for the app session; nothing is persisted or sent to the model.

/// One proposed or kept result of a Study tool.
struct StudyToolResult: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A nearby idea (Branch): around the source, on the sphere.
        case branch
        /// An earlier stage (Sequence): along a path receding from the source.
        case stage
        /// A component (Deconstruct): orbiting inside the source.
        case part
    }

    /// Where a proposal was before the hovered subject changed, so it can glide over.
    struct Origin: Equatable {
        let sourceInsightID: UUID?
        let direction: SIMD3<Double>
    }

    let id = UUID()
    let kind: Kind
    /// The studied Node Concept.
    let nodeID: UUID
    /// The hovered Insight the tool ran on; nil when it ran on the Node Concept itself.
    var sourceInsightID: UUID?
    /// Branch: order of discovery. Stage: 0 is just before the source, higher is earlier.
    let index: Int
    let count: Int
    let title: String
    /// Branch: a unit direction on the Study sphere. Stage: the horizontal direction the chain
    /// recedes in Study (away from the camera when it ran). Part: unused.
    var direction: SIMD3<Double>
    var isKept = false
    let createdAt = Date.timeIntervalSinceReferenceDate
    var origin: Origin?
    var movedAt: TimeInterval = 0
    /// A kept part promoted to its own Node Concept.
    var isNode = false

    var sourceKey: UUID { sourceInsightID ?? nodeID }

    /// This result where it was before its last move.
    var atOrigin: StudyToolResult? {
        guard let origin else { return nil }
        var copy = self
        copy.sourceInsightID = origin.sourceInsightID
        copy.direction = origin.direction
        copy.origin = nil
        return copy
    }
}

@Observable
final class StudyToolPrototypeStore {
    static let shared = StudyToolPrototypeStore()

    private(set) var results: [StudyToolResult] = []

    /// Previews `tool` on a source. One tool is active at a time, so this replaces every other
    /// proposal; proposals of the same tool are reused and glide over to the new source.
    func run(
        _ tool: StudyTool,
        nodeID: UUID,
        sourceInsightID: UUID?,
        sourceDirection: SIMD3<Double>?,
        occupiedDirections: [SIMD3<Double>],
        awayDirection: SIMD3<Double>,
        branchCount: Int
    ) {
        let kind = Self.kind(for: tool)
        let reusable = results
            .filter { !$0.isKept && $0.kind == kind && $0.nodeID == nodeID }
            .sorted { $0.index < $1.index }
        if !reusable.isEmpty, reusable.allSatisfy({ $0.sourceInsightID == sourceInsightID }),
           kind != .branch || reusable.count == branchCount {
            // Already previewing this tool here.
            results.removeAll { !$0.isKept && $0.kind != kind }
            return
        }
        let fresh = proposals(
            tool, nodeID: nodeID, sourceInsightID: sourceInsightID,
            sourceDirection: sourceDirection, occupiedDirections: occupiedDirections,
            awayDirection: awayDirection, branchCount: branchCount
        )
        let now = Date.timeIntervalSinceReferenceDate
        results.removeAll { !$0.isKept }
        for (index, proposal) in fresh.enumerated() {
            guard index < reusable.count else {
                results.append(proposal)
                continue
            }
            var moved = reusable[index]
            moved.origin = StudyToolResult.Origin(sourceInsightID: moved.sourceInsightID, direction: moved.direction)
            moved.movedAt = now
            moved.sourceInsightID = proposal.sourceInsightID
            moved.direction = proposal.direction
            results.append(moved)
        }
    }

    private func proposals(
        _ tool: StudyTool,
        nodeID: UUID,
        sourceInsightID: UUID?,
        sourceDirection: SIMD3<Double>?,
        occupiedDirections: [SIMD3<Double>],
        awayDirection: SIMD3<Double>,
        branchCount: Int
    ) -> [StudyToolResult] {
        switch tool {
        case .branch:
            let taken = occupiedDirections + results
                .filter { $0.nodeID == nodeID && $0.kind == .branch && $0.isKept }
                .map(\.direction)
            let directions = StudyToolGeometry.gapDirections(
                occupied: taken,
                near: sourceDirection,
                count: branchCount
            )
            return directions.enumerated().map { index, direction in
                StudyToolResult(
                    kind: .branch, nodeID: nodeID, sourceInsightID: sourceInsightID,
                    index: index, count: directions.count,
                    title: "Nearby idea \(index + 1)", direction: direction
                )
            }
        case .sequence:
            let titles = ["Just before", "Earlier", "Much earlier", "Origin"]
            return titles.enumerated().map { index, title in
                StudyToolResult(
                    kind: .stage, nodeID: nodeID, sourceInsightID: sourceInsightID,
                    index: index, count: titles.count, title: title, direction: awayDirection
                )
            }
        case .deconstruct:
            return (0..<3).map { index in
                StudyToolResult(
                    kind: .part, nodeID: nodeID, sourceInsightID: sourceInsightID,
                    index: index, count: 3,
                    title: "Part \(["A", "B", "C"][index])", direction: .zero
                )
            }
        }
    }

    private static func kind(for tool: StudyTool) -> StudyToolResult.Kind {
        switch tool {
        case .branch: .branch
        case .sequence: .stage
        case .deconstruct: .part
        }
    }

    func toggleKept(_ id: UUID) {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        results[index].isKept.toggle()
        if !results[index].isKept { results[index].isNode = false }
    }

    func makeNode(_ id: UUID) {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        results[index].isKept = true
        results[index].isNode = true
    }

    /// Leaving Study drops every proposal the user didn't keep.
    func discardProposals() {
        results.removeAll { !$0.isKept }
    }

    var proposalCount: Int { results.filter { !$0.isKept }.count }
}

enum StudyToolGeometry {
    /// Directions for new ideas in the sphere's gaps: each maximizes its angle from everything
    /// already there, pulled toward the source Insight when there is one. Deterministic.
    static func gapDirections(
        occupied: [SIMD3<Double>],
        near source: SIMD3<Double>?,
        count: Int
    ) -> [SIMD3<Double>] {
        let candidates = fibonacciSphere(count: 500)
        var taken = occupied.map { simd_normalize($0) }
        var chosen: [SIMD3<Double>] = []
        for _ in 0..<count {
            var best: (score: Double, direction: SIMD3<Double>)?
            for candidate in candidates {
                // Keep within the tree's ±45° so they flatten cleanly.
                guard abs(candidate.z) < 0.72 else { continue }
                let clearance = taken.map { angle(candidate, $0) }.min() ?? .pi
                let pull = source.map { angle(candidate, simd_normalize($0)) } ?? 0
                let score = clearance - 0.55 * pull
                if best == nil || score > best!.score { best = (score, candidate) }
            }
            guard let best else { break }
            chosen.append(best.direction)
            taken.append(best.direction)
        }
        return chosen
    }

    static func angle(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        acos(min(max(simd_dot(a, b), -1), 1))
    }

    private static func fibonacciSphere(count: Int) -> [SIMD3<Double>] {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0..<count).map { index in
            let z = 1 - 2 * (Double(index) + 0.5) / Double(count)
            let ring = (1 - z * z).squareRoot()
            let theta = golden * Double(index)
            return SIMD3(cos(theta) * ring, sin(theta) * ring, z)
        }
    }

    /// Where a result sits in the world. `source` and `node` are the source's and Node Concept's
    /// current 3D positions (already blended between tree and Study by the canvas); `progress`
    /// blends the result from its flat tree spot (0) to its Study spot (1). `rank` is its order
    /// among kept results of the same source and kind, which lays out the tree.
    static func position(
        of result: StudyToolResult,
        rank: Int,
        source: SIMD3<Double>,
        node: SIMD3<Double>,
        radius: Double,
        progress: Double,
        time: Double
    ) -> SIMD3<Double> {
        let outward = flatDirection(from: node, to: source, fallback: result.direction)
        let tree: SIMD3<Double>
        let study: SIMD3<Double>
        switch result.kind {
        case .branch:
            let flat = SIMD3(result.direction.x, result.direction.y, 0)
            let length = simd_length(flat)
            tree = node + (length > 1e-6 ? flat / length : SIMD3(1, 0, 0)) * radius
            study = node + result.direction * radius
        case .stage:
            // Tree: a trail leading straight out from the source. Study: a path receding from
            // the camera and sinking toward the floor, earlier stages farther away.
            tree = source + outward * radius * 0.95 * Double(rank + 1)
            let step = Double(result.index + 1)
            study = source + result.direction * radius * 0.75 * step
                + SIMD3(0, 0, -radius * 0.22 * step)
        case .part:
            if result.isNode {
                tree = node + outward * radius * 2.6
                let away = simd_length(source - node) > 1e-6 ? simd_normalize(source - node) : SIMD3(0, 0, 1)
                study = source + away * radius * 1.1
            } else {
                // Orbits the source like moons; flat in the tree (drawn as satellite dots).
                let theta = 2 * .pi * Double(result.index) / Double(max(result.count, 1)) + time * 0.45
                let orbit = radius * 0.48
                tree = source
                study = source + SIMD3(cos(theta) * orbit, sin(theta) * orbit, sin(theta + 1) * orbit * 0.3)
            }
        }
        return tree + (study - tree) * progress
    }

    static func flatDirection(from node: SIMD3<Double>, to point: SIMD3<Double>, fallback: SIMD3<Double>) -> SIMD3<Double> {
        let flat = SIMD3(point.x - node.x, point.y - node.y, 0)
        if simd_length(flat) > 1e-6 { return simd_normalize(flat) }
        let fallbackFlat = SIMD3(fallback.x, fallback.y, 0)
        return simd_length(fallbackFlat) > 1e-6 ? simd_normalize(fallbackFlat) : SIMD3(0, -1, 0)
    }
}

/// The source of a set of results, as the canvas currently places it.
struct StudyToolAnchor {
    let source: SIMD3<Double>
    let node: SIMD3<Double>
    let radius: Double
    /// 0 in the tree, 1 in Study.
    let progress: Double
    /// Fades everything from this anchor (e.g. other clusters while in Study).
    let opacity: Double
}

/// Draws Study tool results over the canvas: proposals (dashed) and kept results in 3D while
/// studying, and kept results with their relationship lines in the tree.
struct StudyToolResultsLayer: View {
    let results: [StudyToolResult]
    let anchors: [UUID: StudyToolAnchor]
    let project: (SIMD3<Double>) -> (position: CGPoint, scale: CGFloat)?
    let isInteractive: Bool

    @State private var expandedTrails: Set<UUID> = []

    private var store: StudyToolPrototypeStore { .shared }

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let placed = placedResults(time: time)
            ZStack {
                Canvas { context, _ in
                    drawLinks(placed, in: &context)
                }
                .allowsHitTesting(false)
                ForEach(placed, id: \.result.id) { item in
                    resultView(item)
                }
            }
        }
    }

    // MARK: Placement

    private struct Placed {
        let result: StudyToolResult
        let position: CGPoint
        let scale: CGFloat
        let depth: CGFloat
        let sourcePoint: CGPoint
        let nodePoint: CGPoint
        let progress: Double
        let opacity: Double
        /// Tree only: a trail's stages past the first two fold into a "+n" pill.
        let foldedCount: Int
        let isFolded: Bool
    }

    private func placedResults(time: Double) -> [Placed] {
        var placed: [Placed] = []
        let grouped = Dictionary(grouping: results) { "\($0.sourceKey)-\($0.kind)" }
        for (_, group) in grouped {
            let ordered = group.sorted { $0.index < $1.index }
            let keptOrder = ordered.filter(\.isKept)
            for result in ordered {
                guard let anchor = anchors[result.sourceKey] ?? anchors[result.nodeID] else { continue }
                // Proposals exist only in Study.
                if !result.isKept, anchor.progress < 0.01 { continue }
                let rank = keptOrder.firstIndex(where: { $0.id == result.id }) ?? result.index
                var world = StudyToolGeometry.position(
                    of: result, rank: rank, source: anchor.source, node: anchor.node,
                    radius: anchor.radius, progress: anchor.progress, time: time
                )
                var sourceWorld = anchor.source
                // A proposal whose subject changed glides over on the hover spring.
                let glide = Self.glide(since: result.movedAt, now: time)
                if glide < 1, let previous = result.atOrigin,
                   let from = anchors[previous.sourceKey] ?? anchors[previous.nodeID] {
                    let fromWorld = StudyToolGeometry.position(
                        of: previous, rank: rank, source: from.source, node: from.node,
                        radius: from.radius, progress: from.progress, time: time
                    )
                    world = fromWorld + (world - fromWorld) * glide
                    sourceWorld = from.source + (anchor.source - from.source) * glide
                }
                guard let projected = project(world),
                      let source = project(sourceWorld),
                      let node = project(anchor.node) else { continue }
                var position = projected.position
                // Kept parts fold into satellite dots under their source in the tree.
                if result.kind == .part, !result.isNode {
                    let satellite = CGPoint(
                        x: source.position.x - CGFloat(result.count - 1) * 6 + CGFloat(rank) * 12,
                        y: source.position.y + 30
                    )
                    let p = CGFloat(anchor.progress)
                    position = CGPoint(
                        x: satellite.x + (projected.position.x - satellite.x) * p,
                        y: satellite.y + (projected.position.y - satellite.y) * p
                    )
                }
                let foldedCount = result.kind == .stage && !expandedTrails.contains(result.sourceKey)
                    ? max(keptOrder.count - 2, 0) : 0
                let isFolded = anchor.progress < 0.5 && result.kind == .stage && result.isKept
                    && foldedCount > 1 && rank >= 2
                placed.append(Placed(
                    result: result,
                    position: position,
                    scale: projected.scale,
                    depth: projected.scale,
                    sourcePoint: source.position,
                    nodePoint: node.position,
                    progress: anchor.progress,
                    opacity: anchor.opacity * (result.isKept ? 1 : anchor.progress * Self.fadeIn(since: result.createdAt, now: time)),
                    foldedCount: foldedCount,
                    isFolded: isFolded
                ))
            }
        }
        return placed.sorted { $0.depth < $1.depth }
    }

    /// The Study hover spring (what the camera glides with), 0 → 1 since `start`.
    private static func glide(since start: TimeInterval, now: TimeInterval) -> Double {
        let elapsed = now - start
        let spring = StudyFraming.hoverSpring
        guard elapsed < spring.settlingDuration else { return 1 }
        return spring.value(target: 1.0, time: max(elapsed, 0))
    }

    private static func fadeIn(since start: TimeInterval, now: TimeInterval) -> Double {
        min(max((now - start) / 0.35, 0), 1)
    }

    /// Something is moving or fading in, or parts are orbiting.
    private var isAnimating: Bool {
        let now = Date.timeIntervalSinceReferenceDate
        return results.contains { result in
            (result.kind == .part && !result.isNode)
                || now - result.movedAt < 1.5
                || now - result.createdAt < 1
        }
    }

    // MARK: Links

    private func drawLinks(_ placed: [Placed], in context: inout GraphicsContext) {
        let accent = AquinasTheme.Colors.accentGreen
        let stem = AquinasTheme.Colors.paragraphText
        let bySource = Dictionary(grouping: placed) { "\($0.result.sourceKey)-\($0.result.kind)" }
        for item in placed where !item.isFolded {
            let result = item.result
            let inStudy = item.progress > 0.5
            var path = Path()
            switch result.kind {
            case .branch:
                // Belongs to the node: the tree's own stem.
                path.move(to: item.nodePoint)
                path.addLine(to: item.position)
                context.stroke(path, with: .color(stem.opacity(0.25 * item.opacity)), lineWidth: 1)
                // Branched from its source Insight: dotted.
                if result.sourceInsightID != nil {
                    var dotted = Path()
                    dotted.move(to: item.sourcePoint)
                    dotted.addLine(to: item.position)
                    context.stroke(
                        dotted,
                        with: .color(accent.opacity((inStudy ? 0.7 : 0.45) * item.opacity)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 5])
                    )
                }
            case .stage:
                // Led to: each stage points forward to the next one, ending at the source.
                let group = (bySource["\(result.sourceKey)-\(result.kind)"] ?? [])
                    .filter { !$0.isFolded && ($0.result.isKept || inStudy) }
                    .sorted { $0.result.index < $1.result.index }
                guard let at = group.firstIndex(where: { $0.result.id == result.id }) else { continue }
                let next = at == 0 ? item.sourcePoint : group[at - 1].position
                drawArrow(from: item.position, to: next, color: accent.opacity(0.8 * item.opacity), in: &context)
            case .part:
                if result.isNode {
                    // Part of, across clusters: a dashed curve.
                    let mid = CGPoint(x: (item.sourcePoint.x + item.position.x) / 2, y: (item.sourcePoint.y + item.position.y) / 2)
                    let control = CGPoint(x: mid.x, y: mid.y - 60)
                    path.move(to: item.sourcePoint)
                    path.addQuadCurve(to: item.position, control: control)
                    context.stroke(
                        path,
                        with: .color(accent.opacity(0.7 * item.opacity)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 4])
                    )
                } else if inStudy {
                    path.move(to: item.sourcePoint)
                    path.addLine(to: item.position)
                    context.stroke(
                        path,
                        with: .color(accent.opacity(0.35 * item.opacity * item.progress)),
                        lineWidth: 1
                    )
                }
            }
        }
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: Color, in context: inout GraphicsContext) {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 40 else { return }
        let ux = dx / length, uy = dy / length
        // Stop short of both chips.
        let from = CGPoint(x: start.x + ux * 22, y: start.y + uy * 22)
        let to = CGPoint(x: end.x - ux * 22, y: end.y - uy * 22)
        var line = Path()
        line.move(to: from)
        line.addLine(to: to)
        context.stroke(line, with: .color(color), lineWidth: 1.5)
        var head = Path()
        head.move(to: CGPoint(x: to.x - ux * 7 - uy * 5, y: to.y - uy * 7 + ux * 5))
        head.addLine(to: to)
        head.addLine(to: CGPoint(x: to.x - ux * 7 + uy * 5, y: to.y - uy * 7 - ux * 5))
        context.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    // MARK: Results

    @ViewBuilder
    private func resultView(_ item: Placed) -> some View {
        let result = item.result
        let inStudy = item.progress > 0.5
        Group {
            if item.isFolded {
                if item.foldedCount > 0,
                   result.id == firstFolded(for: result.sourceKey)?.id {
                    foldPill(count: item.foldedCount, sourceKey: result.sourceKey)
                }
            } else if result.kind == .part, !result.isNode, !inStudy {
                Circle()
                    .fill(AquinasTheme.Colors.accentGreen)
                    .frame(width: 7, height: 7)
            } else if result.isNode {
                nodeView(result)
            } else {
                chip(result, inStudy: inStudy)
            }
        }
        .scaleEffect(inStudy ? pow(max(item.scale, 0.01), 0.6) : 1)
        .opacity(item.opacity)
        .position(item.position)
        .allowsHitTesting(isInteractive && item.opacity > 0.3)
    }

    private func firstFolded(for sourceKey: UUID) -> StudyToolResult? {
        results.filter { $0.sourceKey == sourceKey && $0.kind == .stage && $0.isKept }
            .sorted { $0.index < $1.index }
            .dropFirst(2).first
    }

    private func chip(_ result: StudyToolResult, inStudy: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                store.toggleKept(result.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon(for: result.kind))
                    .font(.system(size: 12, weight: .semibold))
                Text(result.title)
                    .font(.figtreeHeading2)
                    .lineLimit(1)
                    .fixedSize()
                if inStudy, result.isKept {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(AquinasTheme.Colors.lightGreen.opacity(result.isKept ? 1 : 0.75))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                AquinasTheme.Colors.canvas.opacity(result.isKept ? 1 : 0.55),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                if !result.isKept {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            AquinasTheme.Colors.lightGreen.opacity(0.6),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                }
            }
            .overlay(alignment: .bottom) {
                if inStudy, result.kind == .part, result.isKept {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            store.makeNode(result.id)
                        }
                    } label: {
                        Label("Make it a node", systemImage: "arrow.up.right")
                            .font(.custom("Figtree-Bold", size: 12))
                            .foregroundStyle(AquinasTheme.Colors.accentGreen)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AquinasTheme.Colors.canvas, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .offset(y: 34)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(result.title), \(result.isKept ? "kept" : "proposal")")
        .accessibilityHint(result.isKept ? "Unkeep" : "Keep")
    }

    private func nodeView(_ result: StudyToolResult) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(AquinasTheme.Colors.canvas)
                .overlay(Circle().strokeBorder(AquinasTheme.Colors.accentGreen, lineWidth: 2))
                .frame(width: 26, height: 26)
            Text(result.title)
                .font(.custom("Figtree-Bold", size: 16))
                .foregroundStyle(AquinasTheme.Colors.headingText)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New Node Concept \(result.title)")
    }

    private func foldPill(count: Int, sourceKey: UUID) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                _ = expandedTrails.insert(sourceKey)
            }
        } label: {
            Text("+\(count) earlier")
                .font(.custom("Figtree-Bold", size: 13))
                .foregroundStyle(AquinasTheme.Colors.accentGreen)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AquinasTheme.Colors.canvas, in: Capsule())
                .overlay(Capsule().strokeBorder(AquinasTheme.Colors.accentGreen.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func icon(for kind: StudyToolResult.Kind) -> String {
        switch kind {
        case .branch: "arrow.triangle.branch"
        case .stage: "clock.arrow.circlepath"
        case .part: "circle.hexagongrid"
        }
    }
}
