//
//  InsightTreeCanvasView.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

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
    let selectedCanvasTargets: [CanvasSelectionTarget]
    let selectionPulseRequest: Int
    var isMidpointMode: Bool = false
    var midpointCenterRequest: Int = 0
    var midpointPlaceRequest: Int = 0
    var midpointTargetIndex: Int = 0            // which selected insight's weight to set
    var midpointTargetWeight: Double = 0.5      // desired weight (0–1) for that insight
    var midpointPercentRequest: Int = 0
    var onMidpointWeightsChange: ([Double]) -> Void = { _ in }
    var onNodeTapped: (NodeModel) -> Void
    var onInsightTapped: (InsightModel) -> Void
    var onCanvasMoved: () -> Void
    var onSuggestConnection: (EdgeModel) -> Void
    var onDismissSuggestedNode: (NodeModel) -> Void
    var onMidpointPlaced: (CGPoint, CanvasSelectionTarget, [Double]) -> Void = { _, _, _ in }

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var selectedEdgeID: UUID?
    @State private var isDraggingCanvas: Bool = false
    @State private var lastCanvasDragEndedAt: Date = .distantPast
    @State private var pinchStartScale: CGFloat?
    @State private var pinchStartOffset: CGSize?
    @State private var preFocusCamera: InsightTreeCameraSnapshot?
    @State private var rippleTrigger:      RippleTrigger? = nil
    @State private var selectionRipples:   [RippleTrigger] = []
    @State private var hasAppeared:        Bool = false
    @State private var revealedInsightIDs: Set<UUID> = []
    @State private var entranceTask:       Task<Void, Never>? = nil
    @State private var pulseCycleStartedAt = Date().timeIntervalSinceReferenceDate
    @State private var connectorPulseDelayUntil = Date().timeIntervalSinceReferenceDate
    @State private var selectionPulseStartTime: TimeInterval?
    @State private var reticleNudge: CGSize = .zero
    @State private var midpointHandleWorld: CGPoint?
    @State private var midpointHandleVisible: Bool = false
    @State private var dragStartHandleWorld: CGPoint?
    @State private var lastHandleHapticPercent: Int?
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
        AquinasTheme.Colors.canvas
    }

    private var insightTreeInsightColor: Color {
        Color(light: 0xFFFAF0, dark: 0x0A0602)
    }

    private func focusAnchor(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * 0.36)
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
                    ripples:       (rippleTrigger.map { [$0] } ?? []) + selectionRipples
                )
                .ignoresSafeArea()
                .opacity(hasAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.6), value: hasAppeared)

                ZStack {
                    graphEdges(camera: camera, size: size)
                    insightConnectors(camera: camera, size: size, labelOpacity: labelOpacity)
                    connectorPulseOverlay(camera: camera, size: size)
                    selectionOverlay(camera: camera, size: size)
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
                .opacity(isMidpointMode ? 0 : 1)
                .allowsHitTesting(!isMidpointMode)
                .animation(.easeInOut(duration: 0.3), value: isMidpointMode)

                if isMidpointMode {
                    midpointOverlay(camera: camera, size: size, labelOpacity: labelOpacity)
                }
            }
            .contentShape(Rectangle())
            .coordinateSpace(name: Self.canvasSpace)
            .simultaneousGesture(panGesture(camera: camera, size: size))
            .simultaneousGesture(zoomGesture(in: size))  // always available for precision zooming
            .onTapGesture {
                selectedEdgeID = nil
            }
            .onChange(of: restoreFocusedCameraRequest) { oldValue, newValue in
                restorePreFocusCamera()
            }
            .onChange(of: focusedInsightID) { oldValue, newValue in
                guard let newValue,
                      let focusTarget = insightFocusTarget(for: newValue) else { return }

                focusHoveredTarget(at: focusTarget, in: size)
            }
            .onAppear {
                hasAppeared = true
                let newInsights = computeNewInsights()
                saveAllInsightIDsAsSeen()
                entranceTask = Task {
                    await runEntranceSequence(newInsights: newInsights, in: size)
                }
            }
            .onChange(of: selectionPulseRequest) { _, newValue in
                guard newValue > 0 else { return }
                selectionPulseStartTime = Date().timeIntervalSinceReferenceDate
            }
            .onChange(of: selectedCanvasTargets.count) { oldCount, newCount in
                // When the first insight is added, pop the reticle in a random direction
                // to hint that you can pan the canvas around.
                guard oldCount == 0, newCount == 1, !isMidpointMode else { return }
                let angle = Double.random(in: 0..<(2 * Double.pi))
                let distance: CGFloat = 28
                withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) {
                    reticleNudge = CGSize(width: cos(angle) * distance, height: sin(angle) * distance)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                        reticleNudge = .zero
                    }
                }
            }
            .onChange(of: nodes) { _, newNodes in
                // Reveal labels of nodes added after the initial entrance (e.g. placed midpoints).
                guard hasAppeared else { return }
                let allIDs = Set(newNodes.flatMap { Array($0.insights.prefix(6)).map(\.id) })
                let missing = allIDs.subtracting(revealedInsightIDs)
                guard !missing.isEmpty else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                    for id in missing { revealedInsightIDs.insert(id) }
                }
            }
            .onChange(of: isMidpointMode) { _, active in
                if active {
                    midpointHandleWorld = midpointCenter()
                    midpointHandleVisible = false
                    reportMidpointWeights()
                    let positions = selectedWorldPositions()
                    zoomToFit(worldPositions: positions, in: size)
                    // Delay the handle entrance until after the zoom spring settles (~0.7s).
                    Task {
                        try? await Task.sleep(for: .milliseconds(680))
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                            midpointHandleVisible = true
                        }
                    }
                } else {
                    midpointHandleVisible = false
                    midpointHandleWorld = nil
                    restorePreFocusCamera()
                }
            }
            .onChange(of: midpointCenterRequest) { _, newValue in
                guard newValue > 0, isMidpointMode else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    midpointHandleWorld = midpointCenter()
                }
                reportMidpointWeights()
            }
            .onChange(of: midpointPercentRequest) { _, newValue in
                guard newValue > 0, isMidpointMode else { return }
                applyMidpointTarget(index: midpointTargetIndex, weight: midpointTargetWeight)
            }
            .onChange(of: midpointPlaceRequest) { _, newValue in
                guard newValue > 0, isMidpointMode, let handle = midpointHandleWorld else { return }
                guard let nearest = nearestSelectedTarget(to: handle) else { return }
                onMidpointPlaced(handle, nearest, midpointWeights(for: handle))
            }
            .onDisappear {
                entranceTask?.cancel()
            }
            .task(id: selectionRippleKey) {
                // All selected items pulse the dot grid together, faster than the hover cadence.
                guard selectionRippleKey != nil else { return }
                while !Task.isCancelled {
                    let positions = selectedWorldPositions()
                    if !positions.isEmpty {
                        let now = Date().timeIntervalSinceReferenceDate
                        selectionRipples = positions.map { RippleTrigger(worldOrigin: $0, startTime: now) }
                    }
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }
            }
            .onChange(of: selectionRippleKey) { _, key in
                if key == nil { selectionRipples = [] }
            }
            .task(id: pulseSourceKey) {
                guard pulseSourceKey != nil else { return }
                let now = Date().timeIntervalSinceReferenceDate
                connectorPulseDelayUntil = now + 0.58
                pulseCycleStartedAt = connectorPulseDelayUntil

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled,
                          selectedCanvasTargets.isEmpty,   // selected items run their own faster ripple
                          let worldPosition = pulsingWorldPosition() else { continue }

                    rippleTrigger = RippleTrigger(
                        worldOrigin: worldPosition,
                        startTime: Date().timeIntervalSinceReferenceDate
                    )
                }
            }
        }
    }

    /// Single drag gesture that routes to handle movement when the drag starts near the
    /// midpoint handle, otherwise falls through to normal canvas panning.
    private func panGesture(camera: InsightTreeCamera, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragOffset) { value, state, _ in
                // Lock the handle-vs-pan decision to the gesture's start so it can't
                // flip to panning as the handle moves away from the finger.
                guard !isHandleDragStart(value.startLocation, camera: camera, size: size) else { return }
                state = value.translation
            }
            .onChanged { value in
                if dragStartHandleWorld == nil {
                    dragStartHandleWorld = midpointHandleWorld   // capture once at gesture start
                }
                if isHandleDragStart(value.startLocation, camera: camera, size: size) {
                    let newHandle = constrainHandle(camera.screenToWorld(value.location, in: size))
                    midpointHandleWorld = newHandle
                    reportMidpointWeights()
                    // Light haptic for every 1% change while dragging the dot.
                    let pct = Int(((midpointWeights(for: newHandle).first ?? 0) * 100).rounded())
                    if pct != lastHandleHapticPercent {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
                        lastHandleHapticPercent = pct
                    }
                    return
                }
                if markCanvasDragIfNeeded(value.translation) {
                    onCanvasMoved()
                }
            }
            .onEnded { value in
                let wasHandleDrag = isHandleDragStart(value.startLocation, camera: camera, size: size)
                dragStartHandleWorld = nil
                lastHandleHapticPercent = nil
                guard !wasHandleDrag else { return }
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

    /// Whether the gesture began on the handle. Uses the handle position captured at the
    /// gesture's start (falling back to the live position on the very first event) so the
    /// decision stays stable as the handle is dragged.
    private func isHandleDragStart(_ startLocation: CGPoint, camera: InsightTreeCamera, size: CGSize) -> Bool {
        guard isMidpointMode, let handle = dragStartHandleWorld ?? midpointHandleWorld else { return false }
        let screen = camera.worldToScreen(handle, in: size)
        // Generous grab zone, biased upward to cover the bobbing icon that sits above the circle.
        let center = CGPoint(x: screen.x, y: screen.y - 16)
        return hypot(startLocation.x - center.x, startLocation.y - center.y) <= 64
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
        let target = focusAnchor(in: size)

        withAnimation(.spring(response: 0.58, dampingFraction: 0.64, blendDuration: 0.08)) {
            offset = CGSize(
                width: target.x - size.width / 2 - (worldPosition.x * scale),
                height: target.y - size.height / 2 + (worldPosition.y * scale)
            )
        }
    }

    private func focusHoveredTarget(at worldPosition: CGPoint, in size: CGSize) {
        rememberCameraBeforeFocusIfNeeded()
        let nextScale = clamp(max(scale, 1.15), lower: 0.28, upper: 2.6)
        let target = focusAnchor(in: size)

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
        let hasSelection = !selectedCanvasTargets.isEmpty
        return ForEach(displayGraphEdges()) { edge in
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
                    .opacity(hasSelection ? 0.5 : 1.0)
                    .animation(.easeInOut(duration: 0.22), value: hasSelection)
            }
        }
    }

    @ViewBuilder
    private func insightConnectors(camera: InsightTreeCamera, size: CGSize, labelOpacity: Double) -> some View {
        let hasSelection = !selectedCanvasTargets.isEmpty
        ForEach(nodes) { node in
            ForEach(Array(node.insights.prefix(6).enumerated()), id: \.element.id) { index, insight in
                let start = camera.worldToScreen(node.position, in: size)
                let end = camera.worldToScreen(
                    insightWorldPosition(for: node, index: index, count: min(node.insights.count, 6)),
                    in: size
                )
                let baseOpacity = 0.2 + (0.35 * labelOpacity)

                AnimatableLine(start: start, end: end)
                    .stroke(
                        AquinasTheme.Colors.divider.opacity(baseOpacity * (hasSelection ? 0.5 : 1.0)),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.22), value: hasSelection)
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
    private func selectionOverlay(camera: InsightTreeCamera, size: CGSize) -> some View {
        if !isMidpointMode,
           let activeTarget = selectedCanvasTargets.last,
           let activeWorldPosition = worldPosition(for: activeTarget) {
            let activePosition = camera.worldToScreen(activeWorldPosition, in: size)
            let center = focusAnchor(in: size)
            let reticleCenter = CGPoint(x: center.x + reticleNudge.width, y: center.y + reticleNudge.height)

            ZStack {
                ForEach(Array(selectedCanvasTargets.indices.dropFirst()), id: \.self) { index in
                    if let previousWorldPosition = worldPosition(for: selectedCanvasTargets[index - 1]),
                       let currentWorldPosition = worldPosition(for: selectedCanvasTargets[index]) {
                        AnimatableLine(
                            start: camera.worldToScreen(previousWorldPosition, in: size),
                            end: camera.worldToScreen(currentWorldPosition, in: size)
                        )
                        .stroke(
                            AquinasTheme.Colors.accentGreen.opacity(0.8),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                        .frame(width: size.width, height: size.height)
                    }
                }

                AnimatableLine(start: activePosition, end: reticleCenter)
                    .stroke(
                        AquinasTheme.Colors.accentGreen.opacity(0.8),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .frame(width: size.width, height: size.height)

                SelectionReticle()
                    .position(reticleCenter)

                if let selectionPulseStartTime,
                   selectedCanvasTargets.count > 1,
                   let previousTarget = selectedCanvasTargets.dropLast().last,
                   let previousWorldPosition = worldPosition(for: previousTarget) {
                    let previousPosition = camera.worldToScreen(previousWorldPosition, in: size)
                    TimelineView(.animation) { timeline in
                        let progress = min(max((timeline.date.timeIntervalSinceReferenceDate - selectionPulseStartTime) / 0.8, 0), 1)
                        if progress < 1 {
                            travelingPulseLine(start: previousPosition, end: activePosition, progress: progress, lineWidth: 2.4)
                                .frame(width: size.width, height: size.height)
                        }
                    }
                }

                // Fast repeating green pulses along all selection lines
                TimelineView(.animation) { fastTimeline in
                    let fastCycle = 0.55
                    let fastProgress = fastTimeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: fastCycle) / fastCycle
                    let segWidth = 0.38
                    let segStart = max(0, fastProgress - segWidth)
                    let segEnd = min(fastProgress, 1)

                    ZStack {
                        // Pulses between each pair of selected targets
                        ForEach(Array(selectedCanvasTargets.indices.dropFirst()), id: \.self) { index in
                            if let prevWorld = worldPosition(for: selectedCanvasTargets[index - 1]),
                               let currWorld = worldPosition(for: selectedCanvasTargets[index]),
                               segEnd > segStart {
                                pulseSegment(
                                    start: camera.worldToScreen(prevWorld, in: size),
                                    end: camera.worldToScreen(currWorld, in: size),
                                    from: segStart, to: segEnd,
                                    lineWidth: 4,
                                    color: AquinasTheme.Colors.accentGreen,
                                    opacity: 0.9
                                )
                                .frame(width: size.width, height: size.height)
                            }
                        }

                        // Pulse from most recent selection to center circle
                        if segEnd > segStart {
                            pulseSegment(
                                start: activePosition,
                                end: reticleCenter,
                                from: segStart, to: segEnd,
                                lineWidth: 4,
                                color: AquinasTheme.Colors.accentGreen,
                                opacity: 0.9
                            )
                            .frame(width: size.width, height: size.height)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                }
                .frame(width: size.width, height: size.height)
            }
            .allowsHitTesting(false)
        }
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
        lineWidth: CGFloat,
        color: Color = Color(red: 0.53, green: 0.49, blue: 0.31),
        opacity: Double = 0.5
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
                        Gradient.Stop(color: color.opacity(0), location: 0.00),
                        Gradient.Stop(color: color, location: 0.50),
                        Gradient.Stop(color: color.opacity(0), location: 1.00)
                    ],
                    startPoint: UnitPoint(x: 0, y: 0.5),
                    endPoint: UnitPoint(x: 1, y: 0.5)
                )
            )
            .frame(width: segmentLength, height: lineWidth)
            .rotationEffect(angle)
            .opacity(opacity)
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

    private var selectionRippleKey: String? {
        guard !selectedCanvasTargets.isEmpty else { return nil }
        return selectedCanvasTargets.map { target -> String in
            switch target {
            case .node(let id): return "n\(id.uuidString)"
            case .insight(let id): return "i\(id.uuidString)"
            }
        }.joined(separator: "|")
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

    private func worldPosition(for target: CanvasSelectionTarget) -> CGPoint? {
        switch target {
        case .node(let nodeID):
            return nodes.first(where: { $0.id == nodeID })?.position
        case .insight(let insightID):
            return insightFocusTarget(for: insightID)
        }
    }

    // MARK: - Midpoint Mode

    static let canvasSpace = "treeCanvas"

    private func selectedWorldPositions() -> [CGPoint] {
        selectedCanvasTargets.compactMap { worldPosition(for: $0) }
    }

    private func reportMidpointWeights() {
        guard let handle = midpointHandleWorld else { return }
        onMidpointWeightsChange(midpointWeights(for: handle))
    }

    /// Moves the handle so that the given selected insight has the target weight.
    /// Two insights: lerp along the A→B segment. Three+: search along the centroid→vertex
    /// ray (the other weights redistribute automatically as the handle recomputes).
    private func applyMidpointTarget(index: Int, weight target: Double) {
        let positions = selectedWorldPositions()
        guard index >= 0, index < positions.count else { return }
        let t = min(max(target, 0), 1)
        let newHandle: CGPoint

        if positions.count == 2 {
            let a = positions[0], b = positions[1]
            // weight[0] = 1 - frac, weight[1] = frac
            let frac = CGFloat(index == 0 ? (1 - t) : t)
            newHandle = CGPoint(x: a.x + (b.x - a.x) * frac, y: a.y + (b.y - a.y) * frac)
        } else if let center = midpointCenter() {
            let v = positions[index]
            // weight[index] increases monotonically with s along center→vertex.
            var lo: CGFloat = -1.2, hi: CGFloat = 1.0
            for _ in 0..<26 {
                let mid = (lo + hi) / 2
                let h = CGPoint(x: center.x + (v.x - center.x) * mid, y: center.y + (v.y - center.y) * mid)
                if midpointWeights(for: h)[index] < t { lo = mid } else { hi = mid }
            }
            let s = (lo + hi) / 2
            newHandle = CGPoint(x: center.x + (v.x - center.x) * s, y: center.y + (v.y - center.y) * s)
        } else {
            return
        }

        withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.9)) {
            midpointHandleWorld = constrainHandle(newHandle)
        }
        reportMidpointWeights()
    }

    /// Geometric center of the selection (exact midpoint for two, centroid for 3+).
    private func midpointCenter() -> CGPoint? {
        let positions = selectedWorldPositions()
        guard !positions.isEmpty else { return nil }
        let sum = positions.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(positions.count), y: sum.y / CGFloat(positions.count))
    }

    /// The selected target whose world position is closest to a point.
    private func nearestSelectedTarget(to point: CGPoint) -> CanvasSelectionTarget? {
        selectedCanvasTargets.min { a, b in
            let pa = worldPosition(for: a) ?? .zero
            let pb = worldPosition(for: b) ?? .zero
            return hypot(pa.x - point.x, pa.y - point.y) < hypot(pb.x - point.x, pb.y - point.y)
        }
    }

    /// Blend weights for each selected target given the handle position.
    /// Two targets: linear along the segment. Three+: normalized inverse-distance.
    private func midpointWeights(for handle: CGPoint) -> [Double] {
        let positions = selectedWorldPositions()
        guard positions.count >= 2 else { return positions.map { _ in 1.0 } }

        if positions.count == 2 {
            let a = positions[0], b = positions[1]
            let abx = b.x - a.x, aby = b.y - a.y
            let denom = abx * abx + aby * aby
            let t = denom > 0 ? clamp(((handle.x - a.x) * abx + (handle.y - a.y) * aby) / denom, lower: 0, upper: 1) : 0.5
            return [Double(1 - t), Double(t)]
        }

        let epsilon: CGFloat = 0.0001
        let inverse = positions.map { 1.0 / Double(max(hypot($0.x - handle.x, $0.y - handle.y), epsilon)) }
        let total = inverse.reduce(0, +)
        return total > 0 ? inverse.map { $0 / total } : positions.map { _ in 1.0 / Double(positions.count) }
    }

    /// Clamps a handle position to the valid region: the segment (two targets)
    /// or the selection polygon (3+ targets).
    private func constrainHandle(_ point: CGPoint) -> CGPoint {
        let positions = selectedWorldPositions()
        if positions.count == 2 {
            return closestPointOnSegment(point, positions[0], positions[1])
        }
        if positions.count >= 3 {
            return pointInPolygon(point, positions) ? point : closestPointOnPolygon(point, positions)
        }
        return point
    }

    private func closestPointOnSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let abx = b.x - a.x, aby = b.y - a.y
        let denom = abx * abx + aby * aby
        guard denom > 0 else { return a }
        let t = clamp(((p.x - a.x) * abx + (p.y - a.y) * aby) / denom, lower: 0, upper: 1)
        return CGPoint(x: a.x + abx * t, y: a.y + aby * t)
    }

    private func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let pi = poly[i], pj = poly[j]
            if (pi.y > p.y) != (pj.y > p.y),
               p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private func closestPointOnPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> CGPoint {
        guard poly.count >= 2 else { return p }
        var best = poly[0]
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let candidate = closestPointOnSegment(p, a, b)
            let dist = hypot(candidate.x - p.x, candidate.y - p.y)
            if dist < bestDist {
                bestDist = dist
                best = candidate
            }
        }
        return best
    }

    @ViewBuilder
    private func midpointOverlay(camera: InsightTreeCamera, size: CGSize, labelOpacity: Double) -> some View {
        let positions = selectedWorldPositions()
        let screenPts = positions.map { camera.worldToScreen($0, in: size) }

        ZStack {
            // Connecting region: filled polygon for 3+, single segment for 2.
            // PolygonShape is animatable so it follows the camera's zoom-out spring.
            if screenPts.count >= 3 {
                PolygonShape(points: screenPts)
                    .fill(AquinasTheme.Colors.accentGreen.opacity(0.25))
                    .allowsHitTesting(false)

                PolygonShape(points: screenPts)
                    .stroke(AquinasTheme.Colors.accentGreen.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .allowsHitTesting(false)
            } else if screenPts.count == 2 {
                AnimatableLine(start: screenPts[0], end: screenPts[1])
                    .stroke(AquinasTheme.Colors.accentGreen.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }

            // Re-draw the selected items at full opacity so they "pop" above the dimmed canvas.
            ForEach(Array(selectedCanvasTargets.enumerated()), id: \.offset) { _, target in
                midpointSelectedItem(target, camera: camera, size: size, labelOpacity: labelOpacity)
            }
            .allowsHitTesting(false)

            // Draggable handle.
            if let handle = midpointHandleWorld {
                let handleScreen = camera.worldToScreen(handle, in: size)
                MidpointHandle()
                    .scaleEffect(midpointHandleVisible ? 1 : 0.3)
                    .opacity(midpointHandleVisible ? 1 : 0)
                    .position(handleScreen)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func midpointSelectedItem(
        _ target: CanvasSelectionTarget,
        camera: InsightTreeCamera,
        size: CGSize,
        labelOpacity: Double
    ) -> some View {
        // Selected items stay fully legible while the rest dims — ignore the
        // zoom-driven label fade by forcing full label opacity.
        switch target {
        case .node(let id):
            if let node = nodes.first(where: { $0.id == id }) {
                nodeGroup(node, camera: camera, size: size, labelOpacity: 1)
            }
        case .insight(let id):
            if let node = nodes.first(where: { $0.insights.contains { $0.id == id } }) {
                let visible = Array(node.insights.prefix(6))
                if let index = visible.firstIndex(where: { $0.id == id }) {
                    insightLabel(
                        visible[index],
                        node: node,
                        index: index,
                        count: min(node.insights.count, 6),
                        camera: camera,
                        size: size,
                        labelOpacity: 1
                    )
                }
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
                if selectedCanvasTargets.isEmpty {
                    rippleTrigger = RippleTrigger(
                        worldOrigin: node.position,
                        startTime: Date().timeIntervalSinceReferenceDate
                    )
                }
                focusHoveredTarget(at: node.position, in: size)
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
        let isSelected    = selectedCanvasTargets.contains(.insight(insight.id))

        return HStack(spacing: 10) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)

            Text(insight.title)
                .font(.figtreeHeading2)
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .lineLimit(1)
                .opacity(labelOpacity)
                .blur(radius: isRevealed ? 0 : 8)
                .animation(.spring(response: 0.6, dampingFraction: 0.75), value: isRevealed)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(insightTreeCanvasColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if isSelected {
                SelectedCanvasInsightBorder()
            }
        }
        .shadow(color: AquinasTheme.Colors.canvas, radius: 24, x: 0, y: 0)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canAcceptTap else { return }
            if selectedCanvasTargets.isEmpty {
                rippleTrigger = RippleTrigger(
                    worldOrigin: worldPosition,
                    startTime: Date().timeIntervalSinceReferenceDate
                )
            }
            focusHoveredTarget(at: worldPosition, in: size)
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
        zoomToFit(worldPositions: positions, in: size)
    }

    /// Zoom/pan so that all supplied world points fit in the viewport with padding.
    private func zoomToFit(worldPositions positions: [CGPoint], in size: CGSize) {
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

/// The selection-mode reticle: a small circle with four outward chevrons indicating that the
/// canvas can be panned to bring the next insight toward it.
private struct SelectionReticle: View {
    private var color: Color { AquinasTheme.Colors.lightGreen.opacity(0.8) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 1.5)
                .frame(width: 18, height: 18)

            arrow("chevron.up").offset(y: -18)
            arrow("chevron.down").offset(y: 18)
            arrow("chevron.left").offset(x: -18)
            arrow("chevron.right").offset(x: 18)
        }
        .frame(width: 54, height: 54)
    }

    private func arrow(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
    }
}

/// Draggable midpoint placement handle: a small circle with a bobbing text.bubble icon above it.
/// The bob uses a TimelineView so it never gets interrupted when the handle's position changes.
private struct MidpointHandle: View {
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
                    .fill(AquinasTheme.Colors.accentGreen)
                    .frame(width: circleSize, height: circleSize)
                    .overlay(Circle().stroke(AquinasTheme.Colors.canvas, lineWidth: 2))
                    .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)

                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AquinasTheme.Colors.accentGreen)
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

/// A VectorArithmetic backing for an arbitrary-length list of coordinates, so a
/// polygon with N points can interpolate smoothly during camera animations.
private struct AnimatableVector: VectorArithmetic {
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
private struct PolygonShape: Shape {
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

private struct SelectedCanvasInsightBorder: View {
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
