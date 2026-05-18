//
//  InsightTreeCanvasView.swift
//  Aquinas-iOS
//

import SwiftUI

// MARK: - Insight Tree Canvas

/// SwiftUI-native graph renderer for the insight tree.
/// Text and SF Symbols stay vector/crisp while the graph remains pannable and zoomable.
struct InsightTreeCanvasView: View {
    let nodes: [NodeModel]
    let edges: [EdgeModel]
    let restoreFocusedCameraRequest: Int
    let focusedInsightID: UUID?
    var onNodeTapped: (NodeModel) -> Void
    var onInsightTapped: (InsightModel) -> Void
    var onCanvasMoved: () -> Void
    var onSuggestConnection: (EdgeModel) -> Void
    var onDismissSuggestedNode: (NodeModel) -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var selectedEdgeID: UUID?
    @State private var isDraggingCanvas: Bool = false
    @State private var lastCanvasDragEndedAt: Date = .distantPast
    @State private var pinchStartScale: CGFloat?
    @State private var pinchStartOffset: CGSize?
    @State private var preFocusCamera: InsightTreeCameraSnapshot?
    @State private var rippleTrigger: RippleTrigger? = nil
    @GestureState private var dragOffset: CGSize = .zero

    private var activeScale: CGFloat {
        clamp(scale, lower: 0.28, upper: 2.6)
    }

    private var activeOffset: CGSize {
        CGSize(
            width: offset.width + dragOffset.width,
            height: offset.height + dragOffset.height
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let camera = InsightTreeCamera(scale: activeScale, offset: activeOffset)
            let labelOpacity = Self.labelOpacity(for: activeScale)

            ZStack {
                AquinasTheme.Colors.canvas.ignoresSafeArea()
                AnimatedDotGridBackground(
                    settledOffset: offset,
                    settledScale:  activeScale,
                    dragOffset:    dragOffset,
                    ripple:        rippleTrigger
                ).ignoresSafeArea()

                graphEdges(camera: camera, size: size)
                insightConnectors(camera: camera, size: size, labelOpacity: labelOpacity)
                edgeHitTargets(camera: camera, size: size)

                ForEach(nodes) { node in
                    nodeGroup(node, camera: camera, size: size, labelOpacity: labelOpacity)

                    ForEach(Array(node.insights.prefix(6).enumerated()), id: \.element.id) { index, insight in
                        insightLabel(
                            insight,
                            node: node,
                            index: index,
                            count: min(node.insights.count, 6),
                            camera: camera,
                            size: size,
                            labelOpacity: labelOpacity
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(panGesture)
            .simultaneousGesture(zoomGesture(in: size))
            .onTapGesture {
                selectedEdgeID = nil
            }
            .onChange(of: restoreFocusedCameraRequest) { oldValue, newValue in
                restorePreFocusCamera()
            }
            .onChange(of: focusedInsightID) { oldValue, newValue in
                guard let newValue,
                      let focusTarget = insightFocusTarget(for: newValue) else { return }

                focusInsight(at: focusTarget, in: size)
            }
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onChanged { value in
                if markCanvasDragIfNeeded(value.translation) {
                    onCanvasMoved()
                }
            }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height

                if hypot(value.translation.width, value.translation.height) > 8 {
                    lastCanvasDragEndedAt = Date()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    isDraggingCanvas = false
                }
            }
    }

    private func zoomGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if pinchStartScale == nil {
                    pinchStartScale = scale
                    pinchStartOffset = offset
                    onCanvasMoved()
                }

                let initialScale = pinchStartScale ?? scale
                let initialOffset = pinchStartOffset ?? offset
                let nextScale = clamp(initialScale * pow(value.magnification, 0.72), lower: 0.28, upper: 2.6)
                let anchor = CGPoint(
                    x: value.startAnchor.x * size.width,
                    y: value.startAnchor.y * size.height
                )

                scale = nextScale
                offset = offsetKeeping(anchor, fixedFrom: initialOffset, initialScale: initialScale, nextScale: nextScale, in: size)
            }
            .onEnded { value in
                let initialScale = pinchStartScale ?? scale
                let initialOffset = pinchStartOffset ?? offset
                let nextScale = clamp(initialScale * pow(value.magnification, 0.72), lower: 0.28, upper: 2.6)
                let anchor = CGPoint(
                    x: value.startAnchor.x * size.width,
                    y: value.startAnchor.y * size.height
                )

                scale = nextScale
                offset = offsetKeeping(anchor, fixedFrom: initialOffset, initialScale: initialScale, nextScale: nextScale, in: size)
                pinchStartScale = nil
                pinchStartOffset = nil
            }
    }

    private func offsetKeeping(
        _ anchor: CGPoint,
        fixedFrom initialOffset: CGSize,
        initialScale: CGFloat,
        nextScale: CGFloat,
        in size: CGSize
    ) -> CGSize {
        let centeredAnchorX = anchor.x - size.width / 2
        let centeredAnchorY = anchor.y - size.height / 2
        let worldX = (centeredAnchorX - initialOffset.width) / initialScale
        let worldY = (initialOffset.height - centeredAnchorY) / initialScale

        return CGSize(
            width: centeredAnchorX - (worldX * nextScale),
            height: centeredAnchorY + (worldY * nextScale)
        )
    }

    private var canAcceptTap: Bool {
        !isDraggingCanvas && Date().timeIntervalSince(lastCanvasDragEndedAt) > 0.16
    }

    private func focusInsight(at worldPosition: CGPoint, in size: CGSize) {
        rememberCameraBeforeFocusIfNeeded()
        let nextScale = clamp(max(scale, 1.15), lower: 0.28, upper: 2.6)
        let target = CGPoint(x: size.width / 2, y: size.height * 0.36)

        withAnimation(.spring(response: 0.58, dampingFraction: 0.64, blendDuration: 0.08)) {
            scale = nextScale
            offset = CGSize(
                width: target.x - size.width / 2 - (worldPosition.x * nextScale),
                height: target.y - size.height / 2 + (worldPosition.y * nextScale)
            )
        }
    }

    private func rememberCameraBeforeFocusIfNeeded() {
        guard preFocusCamera == nil else { return }

        preFocusCamera = InsightTreeCameraSnapshot(scale: scale, offset: offset)
    }

    private func restorePreFocusCamera() {
        guard let preFocusCamera else { return }

        withAnimation(.spring(response: 0.58, dampingFraction: 0.64, blendDuration: 0.08)) {
            scale = preFocusCamera.scale
            offset = preFocusCamera.offset
        }

        self.preFocusCamera = nil
    }

    @discardableResult
    private func markCanvasDragIfNeeded(_ translation: CGSize) -> Bool {
        guard hypot(translation.width, translation.height) > 8 else { return false }
        guard !isDraggingCanvas else { return false }
        isDraggingCanvas = true
        return true
    }

    @ViewBuilder
    private func graphEdges(camera: InsightTreeCamera, size: CGSize) -> some View {
        ForEach(displayGraphEdges()) { edge in
            if let from = nodes.first(where: { $0.id == edge.fromNodeID }),
               let to = nodes.first(where: { $0.id == edge.toNodeID }) {
                let start = camera.worldToScreen(from.position, in: size)
                let end = camera.worldToScreen(to.position, in: size)

                AnimatableLine(start: start, end: end)
                .stroke(
                    AquinasTheme.Colors.divider.opacity(edge.isSuggested ? 0.55 : 0.9),
                    style: StrokeStyle(
                        lineWidth: 1,
                        lineCap: .round,
                        dash: edge.isSuggested ? [6, 4] : []
                    )
                )
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func insightConnectors(camera: InsightTreeCamera, size: CGSize, labelOpacity: Double) -> some View {
        ForEach(nodes) { node in
            ForEach(Array(node.insights.prefix(6).enumerated()), id: \.element.id) { index, insight in
                let start = camera.worldToScreen(node.position, in: size)
                let end = camera.worldToScreen(
                    insightWorldPosition(for: node, index: index, count: min(node.insights.count, 6)),
                    in: size
                )

                AnimatableLine(start: start, end: end)
                .stroke(
                    AquinasTheme.Colors.divider.opacity(0.2 + (0.35 * labelOpacity)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func edgeHitTargets(camera: InsightTreeCamera, size: CGSize) -> some View {
        ForEach(edges) { edge in
            if edge.showSuggestButton,
               let from = nodes.first(where: { $0.id == edge.fromNodeID }),
               let to = nodes.first(where: { $0.id == edge.toNodeID }) {
                let midpoint = CGPoint(
                    x: (from.position.x + to.position.x) / 2,
                    y: (from.position.y + to.position.y) / 2
                )
                let position = camera.worldToScreen(midpoint, in: size)

                Button {
                    guard canAcceptTap else { return }
                    if selectedEdgeID == edge.id {
                        selectedEdgeID = nil
                        onSuggestConnection(edge)
                    } else {
                        selectedEdgeID = edge.id
                    }
                } label: {
                    ZStack {
                        if selectedEdgeID == edge.id {
                            Text("Suggest Connection")
                                .font(.figtreeHeading3)
                                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(AquinasTheme.Colors.surface)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
                                .transition(.scale(scale: 0.92).combined(with: .opacity))
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 170, height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(position)
            }
        }
    }

    @ViewBuilder
    private func nodeGroup(
        _ node: NodeModel,
        camera: InsightTreeCamera,
        size: CGSize,
        labelOpacity: Double
    ) -> some View {
        let position = camera.worldToScreen(node.position, in: size)

        ZStack(alignment: .topTrailing) {
            VStack(spacing: 18) {
                Image(systemName: node.isSuggested ? "sparkles" : "brain.head.profile")
                    .font(.system(size: node.isSuggested ? 20 : 24, weight: .semibold))
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .sfSymbolDrawOn()

                Text(node.conceptLabel)
                    .font(.custom("LibreBaskerville-Regular", size: 18))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .opacity(labelOpacity)
            }
            .padding(8)
            .background(AquinasTheme.Colors.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: AquinasTheme.Colors.canvas, radius: 36, x: 0, y: 0)
            .frame(width: node.isSuggested ? 220 : 260)
            .contentShape(Rectangle())
            .onTapGesture {
                guard canAcceptTap else { return }
                rippleTrigger = RippleTrigger(
                    worldOrigin: node.position,
                    startTime: Date().timeIntervalSinceReferenceDate
                )
                focusInsight(at: node.position, in: size)
                onNodeTapped(node)
            }

            if node.isSuggested {
                Button {
                    onDismissSuggestedNode(node)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: 20, y: -10)
            }
        }
        .position(position)
        .zIndex(node.isSuggested ? 20 : 10)
    }

    private func insightLabel(
        _ insight: InsightModel,
        node: NodeModel,
        index: Int,
        count: Int,
        camera: InsightTreeCamera,
        size: CGSize,
        labelOpacity: Double
    ) -> some View {
        let worldPosition = insightWorldPosition(for: node, index: index, count: count)
        let position = camera.worldToScreen(worldPosition, in: size)

        return HStack(spacing: 10) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .sfSymbolDrawOn()

            Text(insight.title)
                .font(.figtreeHeading2)
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .lineLimit(1)
                .opacity(labelOpacity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AquinasTheme.Colors.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: AquinasTheme.Colors.canvas, radius: 24, x: 0, y: 0)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canAcceptTap else { return }
            rippleTrigger = RippleTrigger(
                worldOrigin: worldPosition,
                startTime: Date().timeIntervalSinceReferenceDate
            )
            focusInsight(at: worldPosition, in: size)
            onInsightTapped(insight)
        }
        .position(position)
        .zIndex(30)
    }

    private func insightFocusTarget(for insightID: UUID) -> CGPoint? {
        for node in nodes {
            let visibleInsights = Array(node.insights.prefix(6))
            if let index = visibleInsights.firstIndex(where: { $0.id == insightID }) {
                return insightWorldPosition(for: node, index: index, count: min(node.insights.count, 6))
            }

            if node.insights.contains(where: { $0.id == insightID }) {
                return node.position
            }
        }

        return nil
    }

    private func displayGraphEdges() -> [RenderedGraphEdge] {
        if !edges.isEmpty {
            return edges.map {
                RenderedGraphEdge(
                    id: $0.id.uuidString,
                    fromNodeID: $0.fromNodeID,
                    toNodeID: $0.toNodeID,
                    isSuggested: $0.isSuggested
                )
            }
        }

        guard nodes.count > 1 else {
            return []
        }

        if nodes.count == 2 {
            return [
                RenderedGraphEdge(
                    id: "\(nodes[0].id.uuidString)-\(nodes[1].id.uuidString)",
                    fromNodeID: nodes[0].id,
                    toNodeID: nodes[1].id,
                    isSuggested: false
                )
            ]
        }

        return nodes.indices.map { index in
            let nextIndex = (index + 1) % nodes.count
            return EdgeModel(
                id: UUID(),
                fromNodeID: nodes[index].id,
                toNodeID: nodes[nextIndex].id,
                distance: 0.5,
                isSuggested: false,
                showSuggestButton: false
            )
        }.map {
            RenderedGraphEdge(
                id: "\($0.fromNodeID.uuidString)-\($0.toNodeID.uuidString)",
                fromNodeID: $0.fromNodeID,
                toNodeID: $0.toNodeID,
                isSuggested: $0.isSuggested
            )
        }
    }

    private func insightWorldPosition(for node: NodeModel, index: Int, count: Int) -> CGPoint {
        let clampedCount = max(count, 1)
        let angle = (CGFloat(index) / CGFloat(clampedCount)) * (.pi * 2) + .pi / 8
        let radius = CGFloat(node.isSuggested ? 118 : 190)
        return CGPoint(
            x: node.position.x + cos(angle) * radius,
            y: node.position.y + sin(angle) * radius
        )
    }

    private static func labelOpacity(for scale: CGFloat) -> Double {
        let startFade = CGFloat(0.44)
        let fullyVisible = CGFloat(0.78)
        let progress = (scale - startFade) / (fullyVisible - startFade)
        return Double(clamp(progress, lower: 0, upper: 1))
    }
}

private struct RenderedGraphEdge: Identifiable {
    let id: String
    let fromNodeID: UUID
    let toNodeID: UUID
    let isSuggested: Bool
}

private struct InsightTreeCameraSnapshot {
    let scale: CGFloat
    let offset: CGSize
}

private struct AnimatableLine: Shape {
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

// MARK: - Camera Projection

private struct InsightTreeCamera {
    var scale: CGFloat
    var offset: CGSize

    func worldToScreen(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + point.x * scale + offset.width,
            y: size.height / 2 - point.y * scale + offset.height
        )
    }

    func screenToWorld(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - size.width / 2 - offset.width) / scale,
            y: -(point.y - size.height / 2 - offset.height) / scale
        )
    }
}

private func clamp<T: Comparable>(_ value: T, lower: T, upper: T) -> T {
    min(max(value, lower), upper)
}
