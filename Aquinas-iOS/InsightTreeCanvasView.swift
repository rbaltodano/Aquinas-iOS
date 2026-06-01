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
    let pulsingInsightID: UUID?
    let pulsingNodeID: UUID?
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
    @State private var rippleTrigger:      RippleTrigger? = nil
    @State private var hasAppeared:        Bool = false
    @State private var revealedInsightIDs: Set<UUID> = []
    @State private var entranceTask:       Task<Void, Never>? = nil
    @State private var pulseCycleStartedAt = Date().timeIntervalSinceReferenceDate
    @State private var connectorPulseDelayUntil = Date().timeIntervalSinceReferenceDate
    @GestureState private var dragOffset:  CGSize = .zero

    private var activeScale: CGFloat {
        clamp(scale, lower: 0.28, upper: 2.6)
    }

    private var activeOffset: CGSize {
        CGSize(
            width: offset.width + dragOffset.width,
            height: offset.height + dragOffset.height
        )
    }

    private var insightTreeCanvasColor: Color {
        Color(hex: 0x130F0C)
    }

    private var insightTreeInsightColor: Color {
        Color(light: 0xFFFAF0, dark: 0x0A0602)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let camera = InsightTreeCamera(scale: activeScale, offset: activeOffset)
            let labelOpacity = Self.labelOpacity(for: activeScale)

            ZStack {
                insightTreeCanvasColor.ignoresSafeArea()
                AnimatedDotGridBackground(
                    settledOffset: offset,
                    settledScale:  activeScale,
                    dragOffset:    dragOffset,
                    ripple:        rippleTrigger
                )
                .ignoresSafeArea()
                .opacity(hasAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.6), value: hasAppeared)

                graphEdges(camera: camera, size: size)
                insightConnectors(camera: camera, size: size, labelOpacity: labelOpacity)
                connectorPulseOverlay(camera: camera, size: size)
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
            .onAppear {
                hasAppeared = true
                let newInsights = computeNewInsights()
                saveAllInsightIDsAsSeen()
                entranceTask = Task {
                    await runEntranceSequence(newInsights: newInsights, in: size)
                }
            }
            .onDisappear {
                entranceTask?.cancel()
            }
            .task(id: pulseSourceKey) {
                guard pulseSourceKey != nil else { return }
                let now = Date().timeIntervalSinceReferenceDate
                connectorPulseDelayUntil = now + 0.58
                pulseCycleStartedAt = connectorPulseDelayUntil

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled,
                          let worldPosition = pulsingWorldPosition() else { continue }

                    rippleTrigger = RippleTrigger(
                        worldOrigin: worldPosition,
                        startTime: Date().timeIntervalSinceReferenceDate
                    )
                }
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
                    .frame(width: size.width, height: size.height)
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
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func connectorPulseOverlay(camera: InsightTreeCamera, size: CGSize) -> some View {
        TimelineView(.animation) { timeline in
            let pulseProgress = connectorPulseProgress(at: timeline.date)
            let sourceNodeID = pulsingNodeID ?? pulsingInsightNodeID()

            ZStack {
                graphEdgePulseOverlay(sourceNodeID: sourceNodeID, camera: camera, size: size, progress: pulseProgress)

                ForEach(nodes) { node in
                    let visibleInsights = Array(node.insights.prefix(6))
                    let isPulsingNode = pulsingNodeID == node.id
                    let selectedInsightIndex = pulsingInsightID.flatMap { pulsingID in
                        visibleInsights.firstIndex { $0.id == pulsingID }
                    }

                    ForEach(Array(visibleInsights.enumerated()), id: \.element.id) { index, insight in
                        let nodePosition = camera.worldToScreen(node.position, in: size)
                        let insightPosition = camera.worldToScreen(
                            insightWorldPosition(for: node, index: index, count: min(node.insights.count, 6)),
                            in: size
                        )

                        if let selectedInsightIndex {
                            connectorPulseLine(
                                nodePosition: nodePosition,
                                insightPosition: insightPosition,
                                isSelectedInsight: index == selectedInsightIndex,
                                isSelectedNodeConcept: false,
                                progress: pulseProgress
                            )
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                        } else if isPulsingNode {
                            connectorPulseLine(
                                nodePosition: nodePosition,
                                insightPosition: insightPosition,
                                isSelectedInsight: false,
                                isSelectedNodeConcept: true,
                                progress: pulseProgress
                            )
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func graphEdgePulseOverlay(
        sourceNodeID: UUID?,
        camera: InsightTreeCamera,
        size: CGSize,
        progress: Double
    ) -> some View {
        if let sourceNodeID {
            ForEach(displayGraphEdges()) { edge in
                if edge.fromNodeID == sourceNodeID || edge.toNodeID == sourceNodeID,
                   let sourceNode = nodes.first(where: { $0.id == sourceNodeID }) {
                    let targetNodeID = edge.fromNodeID == sourceNodeID ? edge.toNodeID : edge.fromNodeID

                    if let targetNode = nodes.first(where: { $0.id == targetNodeID }) {
                        let start = camera.worldToScreen(sourceNode.position, in: size)
                        let end = camera.worldToScreen(targetNode.position, in: size)

                        travelingPulseLine(start: start, end: end, progress: progress, lineWidth: 2.2)
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func connectorPulseLine(
        nodePosition: CGPoint,
        insightPosition: CGPoint,
        isSelectedInsight: Bool,
        isSelectedNodeConcept: Bool,
        progress: Double
    ) -> some View {
        if isSelectedInsight {
            travelingPulseLine(start: insightPosition, end: nodePosition, progress: progress, lineWidth: 2.2)
        } else if isSelectedNodeConcept {
            travelingPulseLine(start: insightPosition, end: nodePosition, progress: progress, lineWidth: 1.8)
        }
    }

    @ViewBuilder
    private func travelingPulseLine(
        start: CGPoint,
        end: CGPoint,
        progress: Double,
        lineWidth: CGFloat
    ) -> some View {
        let segmentWidth = 0.22
        let segmentStart = max(0, progress - segmentWidth)
        let segmentEnd = min(progress, 1)

        if segmentEnd > segmentStart {
            pulseSegment(start: start, end: end, from: segmentStart, to: segmentEnd, lineWidth: lineWidth)
        }
    }

    private func pulseSegment(
        start: CGPoint,
        end: CGPoint,
        from segmentStart: Double,
        to segmentEnd: Double,
        lineWidth: CGFloat
    ) -> some View {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        let centerProgress = (segmentStart + segmentEnd) / 2
        let segmentLength = max(distance * CGFloat(segmentEnd - segmentStart), 1)
        let center = CGPoint(
            x: start.x + dx * CGFloat(centerProgress),
            y: start.y + dy * CGFloat(centerProgress)
        )
        let angle = Angle(radians: Double(atan2(dy, dx)))

        return Capsule()
            .fill(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.53, green: 0.49, blue: 0.31).opacity(0), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.53, green: 0.49, blue: 0.31), location: 0.50),
                        Gradient.Stop(color: Color(red: 0.53, green: 0.49, blue: 0.31).opacity(0), location: 1.00)
                    ],
                    startPoint: UnitPoint(x: 0, y: 0.5),
                    endPoint: UnitPoint(x: 1, y: 0.5)
                )
            )
            .frame(width: segmentLength, height: lineWidth)
            .rotationEffect(angle)
            .opacity(0.5)
            .position(center)
    }

    private func connectorPulseProgress(at date: Date) -> Double {
        let cycleDuration = 2.0
        guard date.timeIntervalSinceReferenceDate >= connectorPulseDelayUntil else { return 0 }

        return max(0, date.timeIntervalSinceReferenceDate - pulseCycleStartedAt)
            .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
    }

    private var pulseSourceKey: String? {
        if let pulsingInsightID {
            return "insight-\(pulsingInsightID.uuidString)"
        }

        if let pulsingNodeID {
            return "node-\(pulsingNodeID.uuidString)"
        }

        return nil
    }

    private func pulsingWorldPosition() -> CGPoint? {
        if let pulsingInsightID {
            return insightFocusTarget(for: pulsingInsightID)
        }

        if let pulsingNodeID {
            return nodes.first(where: { $0.id == pulsingNodeID })?.position
        }

        return nil
    }

    private func pulsingInsightNodeID() -> UUID? {
        guard let pulsingInsightID else { return nil }

        return nodes.first { node in
            node.insights.contains { $0.id == pulsingInsightID }
        }?.id
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
                    .blur(radius: hasAppeared ? 0 : 8)
                    .animation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1), value: hasAppeared)
            }
            .padding(8)
            .background(insightTreeCanvasColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: insightTreeCanvasColor, radius: 36, x: 0, y: 0)
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
        .offset(y: hasAppeared ? 0 : 24)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1), value: hasAppeared)
        .transition(.scale(scale: 0.88, anchor: .center).combined(with: .opacity))
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
        let position      = camera.worldToScreen(worldPosition, in: size)
        let isRevealed    = revealedInsightIDs.contains(insight.id)

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
                .blur(radius: isRevealed ? 0 : 8)
                .animation(.spring(response: 0.6, dampingFraction: 0.75), value: isRevealed)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(insightTreeCanvasColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: insightTreeCanvasColor, radius: 24, x: 0, y: 0)
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
        .offset(y: isRevealed ? 0 : 24)
        .opacity(isRevealed ? 1 : 0)
        .blur(radius: isRevealed ? 0 : 8)
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: isRevealed)
        .transition(.scale(scale: 0.88, anchor: .center).combined(with: .opacity))
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

    // MARK: - New-Insight Entrance Sequence

    private static let seenInsightIDsKey = "AquinasSeenInsightIDs"

    private func loadSeenInsightIDs() -> Set<UUID> {
        guard let strings = UserDefaults.standard.stringArray(forKey: Self.seenInsightIDsKey) else {
            return []
        }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    private func saveAllInsightIDsAsSeen() {
        let ids = nodes.flatMap { $0.insights }.map { $0.id.uuidString }
        UserDefaults.standard.set(ids, forKey: Self.seenInsightIDsKey)
    }

    /// Returns insights that weren't present the last time InsightTree was opened.
    /// Returns empty on the very first open (no persisted state yet).
    private func computeNewInsights() -> [InsightModel] {
        let seenIDs = loadSeenInsightIDs()
        guard !seenIDs.isEmpty else { return [] }
        return nodes.flatMap { node in
            Array(node.insights.prefix(6)).filter { !seenIDs.contains($0.id) }
        }
    }

    /// World position of an insight looked up by ID (nil if not visible on tree).
    private func worldPosition(forInsightID id: UUID) -> CGPoint? {
        for node in nodes {
            let visible = Array(node.insights.prefix(6))
            if let idx = visible.firstIndex(where: { $0.id == id }) {
                return insightWorldPosition(for: node, index: idx, count: min(node.insights.count, 6))
            }
        }
        return nil
    }

    /// Zoom camera to a single insight (reuses focusInsight so camera memory is saved).
    private func zoomToInsight(_ insight: InsightModel, in size: CGSize) {
        guard let worldPos = worldPosition(forInsightID: insight.id) else { return }
        focusInsight(at: worldPos, in: size)
    }

    /// Zoom out so that all supplied insights fit in the viewport with padding.
    private func zoomToFitInsights(_ insights: [InsightModel], in size: CGSize) {
        let positions = insights.compactMap { worldPosition(forInsightID: $0.id) }
        guard positions.count >= 2 else {
            if let pos = positions.first { focusInsight(at: pos, in: size) }
            return
        }

        let minX = positions.map { $0.x }.min()!
        let maxX = positions.map { $0.x }.max()!
        let minY = positions.map { $0.y }.min()!
        let maxY = positions.map { $0.y }.max()!

        let padding: CGFloat    = 180
        let worldWidth          = max(maxX - minX + padding * 2, 1)
        let worldHeight         = max(maxY - minY + padding * 2, 1)
        let targetScale         = clamp(
            min(size.width / worldWidth, size.height / worldHeight) * 0.88,
            lower: 0.28, upper: 1.4
        )
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        rememberCameraBeforeFocusIfNeeded()
        withAnimation(.spring(response: 0.58, dampingFraction: 0.64, blendDuration: 0.08)) {
            scale  = targetScale
            offset = CGSize(width: -(centerX * targetScale), height: centerY * targetScale)
        }
    }

    /// Orchestrates the full entrance sequence based on how many new insights there are.
    private func runEntranceSequence(newInsights: [InsightModel], in size: CGSize) async {
        let allIDs    = Set(nodes.flatMap { Array($0.insights.prefix(6)).map { $0.id } })
        let newIDs    = Set(newInsights.map { $0.id })
        let nonNewIDs = allIDs.subtracting(newIDs)

        // All non-new insights animate in with the standard 0.25 s stagger.
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        revealedInsightIDs = nonNewIDs.isEmpty ? allIDs : nonNewIDs

        if newInsights.isEmpty {
            // Nothing new — reveal everything at the stagger point and we're done.
            revealedInsightIDs = allIDs
            return
        }

        // Small pause so the user can register the overview before we start zooming.
        try? await Task.sleep(nanoseconds: 200_000_000)

        if newInsights.count <= 3 {
            // Zoom to each new insight in turn, wait for the spring to settle,
            // then reveal it with its entrance animation.
            for insight in newInsights {
                guard !Task.isCancelled else { return }
                zoomToInsight(insight, in: size)
                try? await Task.sleep(nanoseconds: 950_000_000)   // spring settle ~0.95 s
                guard !Task.isCancelled else { return }
                revealedInsightIDs.insert(insight.id)
                // Fire a ripple from this insight's world position as it springs in.
                if let worldPos = worldPosition(forInsightID: insight.id) {
                    rippleTrigger = RippleTrigger(worldOrigin: worldPos,
                                                  startTime: Date().timeIntervalSinceReferenceDate)
                }
                try? await Task.sleep(nanoseconds: 700_000_000)   // entrance anim + brief pause
            }
        } else {
            // 4+ new — zoom out so all are visible at once, then reveal them together.
            guard !Task.isCancelled else { return }
            zoomToFitInsights(newInsights, in: size)
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            for id in newIDs { revealedInsightIDs.insert(id) }
            // Single ripple at the centroid of all new insights.
            let positions = newInsights.compactMap { worldPosition(forInsightID: $0.id) }
            if !positions.isEmpty {
                let cx = positions.map { $0.x }.reduce(0, +) / CGFloat(positions.count)
                let cy = positions.map { $0.y }.reduce(0, +) / CGFloat(positions.count)
                rippleTrigger = RippleTrigger(worldOrigin: CGPoint(x: cx, y: cy),
                                              startTime: Date().timeIntervalSinceReferenceDate)
            }
        }
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
