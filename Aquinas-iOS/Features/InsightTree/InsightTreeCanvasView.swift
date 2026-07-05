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
    var makeNodeChildIDs: Set<UUID> = []
    /// Nodes that are user-placed midpoints — rendered as a bare insight chip (no
    /// node-concept circle), pinned at the node position.
    var placedMidpointNodeIDs: Set<UUID> = []
    /// For each placed-midpoint node, the sources it connects to (insight chips / node concepts).
    var placedMidpointSources: [UUID: [MidpointSource]] = [:]
    /// Per-insight bond length (connector radius) from relatedness to the parent node.
    var insightBondLengths: [UUID: CGFloat] = [:]
    var isHoveringTarget: Bool = false
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
    /// The insight id of a just-placed midpoint, so it runs the loading-icon → text-reveal sequence.
    var midpointPlacedInsightID: UUID? = nil
    /// Fired once the placed midpoint insight has "loaded" (icon flash → text reveal → dot pulse),
    /// so the orchestration layer can pop its card.
    var onMidpointInsightLoaded: (UUID) -> Void = { _ in }
    /// True while Make Node children are generating, so the Context wheel spins.
    var onGeneratingChange: (Bool) -> Void = { _ in }
    /// Fired for each Make Node child at the instant it's revealed (as its haptic taps fire),
    /// so the parent's docked card can grow an Insight link for it in sync with the animation.
    var onMakeNodeChildRevealed: (UUID) -> Void = { _ in }
    /// Live simulated node positions, reported up for persistence (on disappear / background).
    var onPositionsSettled: ([UUID: CGPoint]) -> Void = { _ in }
    /// Fired to clear any currently hovered/docked insight or node card (e.g. before a
    /// generation zoom-out, so the previously hovered card doesn't linger).
    var onRequestDismissHover: () -> Void = {}
    /// Reports the current blue-dot count whenever insights become discovered or undiscovered.
    var onUndiscoveredInsightCountChange: (Int) -> Void = { _ in }

    @Environment(\.scenePhase) private var scenePhase

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
    /// Insights the user hasn't opened yet — they show a blue "new" dot until first hovered.
    @State private var undiscoveredInsightIDs: Set<UUID> = []
    @State private var entranceTask:       Task<Void, Never>? = nil
    @State private var pulseCycleStartedAt = Date().timeIntervalSinceReferenceDate
    @State private var connectorPulseDelayUntil = Date().timeIntervalSinceReferenceDate
    @State private var selectionPulseStartTime: TimeInterval?
    @State private var selectionFlashOpacity: CGFloat = 1
    @State private var loadingInsightIDs: Set<UUID> = []
    @State private var loadingFlashOpacity: CGFloat = 1
    @State private var unsplayedInsightIDs: Set<UUID> = []
    @State private var midpointHandleWorld: CGPoint?
    @State private var midpointHandleVisible: Bool = false
    @State private var dragStartHandleWorld: CGPoint?
    @State private var lastHandleHapticPercent: Int?
    /// Set when the user pans/zooms/taps after placing a midpoint, so the auto camera-hover
    /// stops chasing the generating insight and the user can look around freely.
    @State private var userMovedSincePlacement: Bool = false
    @GestureState private var dragOffset:  CGSize = .zero

    // MARK: - Live physics simulation
    /// Per-node simulated position + velocity. The canvas briefly relaxes these from the
    /// view model's seed positions after topology changes, then freezes to avoid passive drift.
    @State private var bodies: [UUID: SimBody] = [:]
    /// Per-insight free bond angle around its node; VSEPR repulsion spreads chips to maximize
    /// angular separation. Keyed by insight id.
    @State private var chipAngles: [UUID: ChipAngle] = [:]
    @State private var alpha: Double = 0
    @State private var displayLink: DisplayLinkDriver? = nil
    @State private var lastTickAt: CFTimeInterval = 0
    @State private var simFramesRemaining: Int = 0

    // Force constants — mirror InsightTreeViewModel.runForceLayout so the live sim matches the seed.
    private static let repulsionK: CGFloat = 3600
    private static let repulsionMinDist: CGFloat = 60
    private static let overlapPadding: CGFloat = 24
    private static let simDamping: CGFloat = 0.62       // lower = settles faster, less wobble
    private static let simMaxStep: CGFloat = 4          // per-frame move clamp (matches VM)
    private static let simMaxDt: CFTimeInterval = 1.0 / 30
    private static let constraintIterations = 4          // rigid edge-length projection passes
    private static let alphaDecay: Double = 0.08
    private static let alphaFloor: Double = 0
    private static let jitterAmplitude: CGFloat = 0
    private static let settleFrameBudget: Int = 150   // longer: node bonds rotate into VSEPR angles
    private static let settleVelocityThreshold: CGFloat = 0.02
    // Per-insight "inner tube": when two chips get within this radius they bounce apart.
    // Cross-node overlap also nudges the parent nodes apart.
    private static let insightBubbleRadius: CGFloat = 48
    private static let insightBubblePadding: CGFloat = 12
    private static let bubblePushK: CGFloat = 0.06
    private static let forceGain: CGFloat = 0.5          // scales summed force → velocity
    // VSEPR angular spread: every domain around a node — insight bonds AND bonds to neighbor
    // nodes — repels EQUALLY (`domainK`), settling to maximum separation (2 → 180° linear,
    // 3 → 120° trigonal, etc.). Both chip bonds AND node-to-node bonds rotate by a DIRECT
    // clamped angular step (not a force) — a force competes with the generic pairwise node
    // repulsion and gets drowned out, leaving node-node bond angles barely moving.
    private static let domainK: Double = 1.0
    private static let chipAngGain: Double = 0.4         // viscous angular response speed
    private static let chipMaxAngStep: Double = 0.05     // max radians a bond rotates per frame
    private static let chipAngleEps: Double = 0.12       // softens the 1/Δθ repulsion
    // Node-to-node bond spreading: a tangential force that swings a neighbor node around the
    // shared node, run through the damped velocity pipeline (converges, no fly-off/jitter).
    private static let edgeTorqueGain: CGFloat = 0.5
    private static let edgeTorqueMax: CGFloat = 2.5      // clamp the tangential force per bond

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

    /// While a selection exists and nothing is hovered, the unselected nodes/insights flash
    /// (mirroring the "Add concept to selection" button) to invite adding another. Hovering stops it.
    private var insightsFlashing: Bool {
        !selectedCanvasTargets.isEmpty && !isHoveringTarget && !isMidpointMode
    }

    private func itemFlashOpacity(selected: Bool) -> Double {
        guard insightsFlashing, !selected else { return 1 }
        return Double(selectionFlashOpacity)
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
            let nodeLabelOpacity = Self.nodeLabelOpacity(for: activeScale)

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
                    midpointConnectors(camera: camera, size: size)
                    insightConnectors(camera: camera, size: size)
                    connectorPulseOverlay(camera: camera, size: size)
                    selectionOverlay(camera: camera, size: size)
                    edgeHitTargets(camera: camera, size: size)

                    ForEach(displayNodes) { node in
                        // Placed-midpoint nodes render as just their insight chip — no concept circle.
                        if !placedMidpointNodeIDs.contains(node.id) {
                            nodeGroup(node, camera: camera, size: size, labelOpacity: nodeLabelOpacity)
                                .opacity(itemFlashOpacity(selected: selectedCanvasTargets.contains(.node(node.id))))
                        }

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
                            .opacity(itemFlashOpacity(selected: selectedCanvasTargets.contains(.insight(insight.id))))
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
                userMovedSincePlacement = true
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
                reconcileBodies()   // seed live physics bodies + start the tick
                let newInsights = computeNewInsights()
                undiscoveredInsightIDs = loadUndiscoveredInsightIDs()
                markUndiscovered(newInsights.map(\.id))   // new since last open → blue dot
                reportUndiscoveredInsightCount()
                saveAllInsightIDsAsSeen()
                entranceTask = Task {
                    await runEntranceSequence(newInsights: newInsights, in: size)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { persistLivePositions() }
            }
            .onChange(of: selectionPulseRequest) { _, newValue in
                guard newValue > 0 else { return }
                selectionPulseStartTime = Date().timeIntervalSinceReferenceDate
            }
            .onChange(of: insightsFlashing) { _, flashing in
                if flashing {
                    selectionFlashOpacity = 1
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        selectionFlashOpacity = 0.25
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { selectionFlashOpacity = 1 }
                }
            }
            .onChange(of: selectedCanvasTargets.count) { oldCount, newCount in
                // When the first insight is added, drift the whole camera in a random
                // direction (and stay there) to hint that the canvas can be panned.
                guard oldCount == 0, newCount == 1, !isMidpointMode else { return }
                let angle = Double.random(in: 0..<(2 * Double.pi))
                let distance: CGFloat = 90
                withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
                    offset.width += cos(angle) * distance
                    offset.height += sin(angle) * distance
                }
            }
            .onChange(of: nodes) { _, _ in
                // Seed/drop live physics bodies as the topology changes (preserving existing
                // bodies so the tree doesn't jump), then wake the sim.
                reconcileBodies()
                reportUndiscoveredInsightCount()
            }
            .onChange(of: nodes) { _, newNodes in
                // Insights added after the initial entrance (Make Node children, placed midpoints):
                // they start as a flashing icon at the node center, splay out to their orbit
                // staggered by 0.15s each, then once "loaded" the title blurs up.
                guard hasAppeared else { return }
                let known = revealedInsightIDs.union(loadingInsightIDs)
                var newOnes: [(id: UUID, orbitIndex: Int)] = []
                var plainNewIDs: [UUID] = []
                var placedMidpointID: UUID? = nil
                for node in newNodes {
                    for (i, insight) in Array(node.insights.prefix(6)).enumerated() where !known.contains(insight.id) {
                        if insight.id == midpointPlacedInsightID {
                            placedMidpointID = insight.id     // just-placed midpoint → simulated load + hover
                        } else if makeNodeChildIDs.contains(insight.id) {
                            newOnes.append((insight.id, i))   // Make Node child → loading mask + splay
                        } else {
                            plainNewIDs.append(insight.id)     // everything else → normal blur/transform pop-in
                        }
                    }
                }

                // Other new insights just appear with the standard blur + transform reveal.
                if !plainNewIDs.isEmpty {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                        for id in plainNewIDs { revealedInsightIDs.insert(id) }
                    }
                }

                // A freshly placed midpoint insight runs a generation sequence:
                //   1. hover/zoom on the hollow "Insight Loading Icon" while generating
                //   2. once complete, the hollow icon fades+blurs out while the solid icon+title
                //      cross-fade in (fade/transform/blur), AND a big shockwave radiates — together
                //   3. shortly after, the insight card pops up
                if let placedID = placedMidpointID {
                    loadingInsightIDs.insert(placedID)
                    userMovedSincePlacement = false
                    // Gets a blue "undiscovered" dot until first hovered, same as other new insights.
                    markUndiscovered([placedID])
                    if let pos = worldPosition(forInsightID: placedID) {
                        focusHoveredTarget(at: pos, in: size)
                    }
                    Task {
                        // Simulate the model generating this insight (loading icon flashes).
                        try? await Task.sleep(for: .seconds(3.5))
                        await MainActor.run {
                            // Re-center the hover on the icon the instant it's generated (unless
                            // the user has since moved), then draw on the solid icon + fire the
                            // big shockwave simultaneously.
                            if let pos = worldPosition(forInsightID: placedID) {
                                if !userMovedSincePlacement {
                                    focusHoveredTarget(at: pos, in: size)
                                }
                                rippleTrigger = RippleTrigger(
                                    worldOrigin: pos,
                                    startTime: Date().timeIntervalSinceReferenceDate,
                                    strength: 2.8,
                                    radiusScale: 0.5
                                )
                                // Two quick haptic taps as the shockwave bursts out.
                                playGeneratedHaptics()
                            }
                            // Cross-fade: hollow loading icon fades+blurs out as the solid
                            // icon+title fade/transform/blur in, together.
                            withAnimation(.easeOut(duration: 0.32)) {
                                loadingInsightIDs.remove(placedID)
                                revealedInsightIDs.insert(placedID)
                            }
                        }
                        // After the reveal settles, bring up the card.
                        try? await Task.sleep(for: .milliseconds(650))
                        await MainActor.run { onMidpointInsightLoaded(placedID) }
                    }
                }

                guard !newOnes.isEmpty else { return }

                for one in newOnes {
                    loadingInsightIDs.insert(one.id)
                    unsplayedInsightIDs.insert(one.id)
                }
                // Spin the Context wheel while these generate (same as the midpoint tool).
                onGeneratingChange(true)
                // New generated insights get a blue "undiscovered" dot until first hovered.
                markUndiscovered(newOnes.map(\.id))

                // Zoom out so the parent node and all its new children are visible together
                // before the per-child tour begins, centered on the node itself.
                onRequestDismissHover()
                let genNodeIDs = Set(newOnes.compactMap { one in
                    newNodes.first(where: { $0.insights.contains { $0.id == one.id } })?.id
                })
                let genNodePositions = genNodeIDs.compactMap { simPosition(of: $0) }
                let framePositions = genNodePositions
                    + newOnes.compactMap { worldPosition(forInsightID: $0.id) }
                if !framePositions.isEmpty {
                    zoomToFit(
                        worldPositions: framePositions, in: size,
                        padding: 90, fitFactor: 1.0,
                        center: genNodePositions.count == 1 ? genNodePositions.first : nil
                    )
                }

                // Splay each child out from the node center, staggered per orbit index.
                for one in newOnes {
                    let delay = Double(one.orbitIndex) * 0.15
                    Task {
                        try? await Task.sleep(for: .seconds(delay))
                        await MainActor.run {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                _ = unsplayedInsightIDs.remove(one.id)
                            }
                        }
                    }
                }

                // Generation completes after the same dwell the midpoint tool uses. Then the
                // camera pans to each new child in turn so the user can see what was made: as it
                // settles on each one, the hollow loading icon cross-fades to the solid icon+title,
                // a big shockwave bursts out from it, and two haptic taps fire. The Context wheel
                // stops once every child has been revealed.
                Task {
                    try? await Task.sleep(for: .seconds(3.5))
                    for (index, one) in newOnes.enumerated() {
                        guard !Task.isCancelled else { break }
                        await MainActor.run {
                            if let pos = worldPosition(forInsightID: one.id) {
                                // First child: zoom back to the default zoom level — the same
                                // one used for the normal new-insight entrance — while panning
                                // to it, as a single combined animation (not two in sequence).
                                focusInsight(at: pos, in: size, targetScale: index == 0 ? 1 : nil)
                            }
                        }
                        try? await Task.sleep(for: .milliseconds(900))   // camera spring settle
                        await MainActor.run {
                            if let pos = worldPosition(forInsightID: one.id) {
                                rippleTrigger = RippleTrigger(
                                    worldOrigin: pos,
                                    startTime: Date().timeIntervalSinceReferenceDate,
                                    strength: 2.8,
                                    radiusScale: 0.5
                                )
                            }
                            playGeneratedHaptics()
                            // Grow the parent's docked card with an Insight link for this child,
                            // in sync with the haptic taps.
                            onMakeNodeChildRevealed(one.id)
                            withAnimation(.easeOut(duration: 0.32)) {
                                loadingInsightIDs.remove(one.id)
                                revealedInsightIDs.insert(one.id)
                            }
                        }
                        try? await Task.sleep(for: .milliseconds(700))   // entrance settle before next
                    }
                    await MainActor.run { onGeneratingChange(false) }
                }
            }
            .onChange(of: loadingInsightIDs.isEmpty) { _, empty in
                if empty {
                    loadingFlashOpacity = 1
                } else {
                    loadingFlashOpacity = 1
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        loadingFlashOpacity = 0.35
                    }
                }
            }
            .onChange(of: isMidpointMode) { _, active in
                if active {
                    midpointHandleWorld = centeredMidpointHandle()
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
                    // On a placement we hand the camera to the new insight (the nodes onChange
                    // focuses it), so don't restore the pre-midpoint camera. Only restore on cancel.
                    if midpointPlacedInsightID == nil {
                        restorePreFocusCamera()
                    }
                }
            }
            .onChange(of: midpointCenterRequest) { _, newValue in
                guard newValue > 0, isMidpointMode else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    midpointHandleWorld = centeredMidpointHandle()
                }
                reportMidpointWeights()
            }
            .onChange(of: midpointPercentRequest) { _, newValue in
                guard newValue > 0, isMidpointMode else { return }
                applyMidpointTarget(index: midpointTargetIndex, weight: midpointTargetWeight)
            }
            .onChange(of: midpointPlaceRequest) { _, newValue in
                guard newValue > 0, isMidpointMode, let handle = effectiveMidpointHandle() else { return }
                guard let nearest = nearestSelectedTarget(to: handle) else { return }
                onMidpointPlaced(handle, nearest, midpointWeights(for: handle))
            }
            .onDisappear {
                entranceTask?.cancel()
                persistLivePositions()
                stopSim()
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
                    userMovedSincePlacement = true
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
                    userMovedSincePlacement = true
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

    /// Pans (and, if `targetScale` is supplied, simultaneously zooms) to center `worldPosition`
    /// — a single spring rather than two sequential ones when both need to change together.
    private func focusInsight(at worldPosition: CGPoint, in size: CGSize, targetScale: CGFloat? = nil) {
        rememberCameraBeforeFocusIfNeeded()
        let target = focusAnchor(in: size)
        let nextScale = targetScale ?? scale

        withAnimation(.spring(response: 0.58, dampingFraction: 0.64, blendDuration: 0.08)) {
            scale = nextScale
            offset = CGSize(
                width: target.x - size.width / 2 - (worldPosition.x * nextScale),
                height: target.y - size.height / 2 + (worldPosition.y * nextScale)
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
        ForEach(displayGraphEdges()) { edge in
            if let from = simPosition(of: edge.fromNodeID),
               let to = simPosition(of: edge.toNodeID) {
                let start = camera.worldToScreen(from, in: size)
                let end = camera.worldToScreen(to, in: size)

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

    /// World endpoint for a midpoint's source: the insight's chip, or the node center for a
    /// whole-node-concept source.
    private func midpointSourceEndpoint(_ source: MidpointSource) -> CGPoint? {
        if source.isNode {
            if let node = displayNodes.first(where: { $0.insights.contains { $0.id == source.insightID } }) {
                return node.position
            }
            return simPosition(of: source.insightID)
        }
        return worldPosition(forInsightID: source.insightID)
    }

    /// Lines from each placed midpoint to the insight chips / node concepts it was spawned from.
    @ViewBuilder
    private func midpointConnectors(camera: InsightTreeCamera, size: CGSize) -> some View {
        let hasSelection = !selectedCanvasTargets.isEmpty
        ForEach(Array(placedMidpointNodeIDs), id: \.self) { placedID in
            if let placedWorld = simPosition(of: placedID), let sources = placedMidpointSources[placedID] {
                let end = camera.worldToScreen(placedWorld, in: size)
                ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                    if let sourceWorld = midpointSourceEndpoint(source) {
                        AnimatableLine(start: camera.worldToScreen(sourceWorld, in: size), end: end)
                            .stroke(
                                AquinasTheme.Colors.divider.opacity(0.9),
                                style: StrokeStyle(lineWidth: 1, lineCap: .round)
                            )
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                            .opacity(hasSelection ? 0.5 : 1.0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func insightConnectors(camera: InsightTreeCamera, size: CGSize) -> some View {
        let hasSelection = !selectedCanvasTargets.isEmpty
        // Placed-midpoint chips sit on the node itself, so they have no orbit connectors.
        let connectorNodes = displayNodes.filter { !placedMidpointNodeIDs.contains($0.id) }
        ForEach(connectorNodes) { node in
            ForEach(Array(node.insights.prefix(6).enumerated()), id: \.element.id) { index, insight in
                let start = camera.worldToScreen(node.position, in: size)
                let end = camera.worldToScreen(
                    insightWorldPosition(for: node, index: index, count: min(node.insights.count, 6)),
                    in: size
                )
                // Connector lines stay at a constant opacity regardless of zoom — only the
                // chip label/background fade with `labelOpacity`, not the lines themselves.
                let baseOpacity = 0.55

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

                ForEach(displayNodes) { node in
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

                AnimatableLine(start: activePosition, end: center)
                    .stroke(
                        AquinasTheme.Colors.accentGreen.opacity(0.8),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .frame(width: size.width, height: size.height)

                SelectionReticle()
                    .position(center)

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
                                end: center,
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
                   let sourcePos = simPosition(of: sourceNodeID) {
                    let targetNodeID = edge.fromNodeID == sourceNodeID ? edge.toNodeID : edge.fromNodeID

                    if let targetPos = simPosition(of: targetNodeID) {
                        let start = camera.worldToScreen(sourcePos, in: size)
                        let end = camera.worldToScreen(targetPos, in: size)

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
            return simPosition(of: pulsingNodeID)
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
            return simPosition(of: nodeID)
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
        guard let handle = effectiveMidpointHandle() else { return }
        onMidpointWeightsChange(midpointWeights(for: handle))
    }

    private func centeredMidpointHandle() -> CGPoint? {
        midpointCenter().map(constrainHandle)
    }

    private func effectiveMidpointHandle() -> CGPoint? {
        midpointHandleWorld.map(constrainHandle)
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
            if let handle = effectiveMidpointHandle() {
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
            if let node = displayNodes.first(where: { $0.id == id }) {
                nodeGroup(node, camera: camera, size: size, labelOpacity: 1)
            }
        case .insight(let id):
            if let node = displayNodes.first(where: { $0.insights.contains { $0.id == id } }) {
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
               let from = simPosition(of: edge.fromNodeID),
               let to = simPosition(of: edge.toNodeID) {
                let midpoint = CGPoint(
                    x: (from.x + to.x) / 2,
                    y: (from.y + to.y) / 2
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
                                .foregroundStyle(AquinasTheme.Colors.primaryReadable)
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
                    .foregroundStyle(AquinasTheme.Colors.lightGreen)

                Text(node.conceptLabel)
                    .font(.custom("LibreBaskerville-Regular", size: 18))
                    .foregroundStyle(AquinasTheme.Colors.primaryReadable)
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
                        .foregroundStyle(AquinasTheme.Colors.primaryReadable)
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

    /// Two quick medium taps, fired as a generated insight's shockwave bursts out.
    private func playGeneratedHaptics() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred(intensity: 0.9)
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
        }
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
        // Placed-midpoint insights are pinned at the node position itself (no orbit).
        let isPinnedAtNode = placedMidpointNodeIDs.contains(node.id)
        let worldPosition = isPinnedAtNode ? node.position : insightWorldPosition(for: node, index: index, count: count)
        let isRevealed    = revealedInsightIDs.contains(insight.id)
        let isLoading     = loadingInsightIDs.contains(insight.id)
        let isSelected    = selectedCanvasTargets.contains(.insight(insight.id))
        // Pinned (placed-midpoint) chips stay visible from the moment they appear — even in
        // the brief gap between the icon turning solid and the title blurring in.
        let isVisible     = isRevealed || isLoading || isPinnedAtNode
        // While unsplayed, render at the node center so the child appears to splay out from it.
        let atCenter      = unsplayedInsightIDs.contains(insight.id)
        let renderWorld   = atCenter ? node.position : worldPosition
        let position      = camera.worldToScreen(renderWorld, in: size)
        // Stable per-chip delay (0.05–0.25s) so the title collapse/expand staggers across chips.

        return ZStack(alignment: .leading) {
            // While generating: the hollow loading bubble, flashing. On completion it fades
            // out and blurs as the solid content cross-fades in.
            if isLoading {
                Image(systemName: "text.bubble")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AquinasTheme.Colors.lightGreen)
                    .opacity(loadingFlashOpacity)
                    .transition(.fadeBlur)
            }
            // Icon + title appear together as one unit (fade + transform + blur), like a
            // streamed model response. The icon stays full opacity; only the title fades with zoom.
            if isRevealed {
                RevealedInsightLabel(title: insight.title, labelOpacity: labelOpacity)
                    .transition(.glideFadeUp)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        // Background + title fade with zoom, leaving just the floating icon.
        .background(insightTreeCanvasColor.opacity(labelOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if isSelected {
                SelectedCanvasInsightBorder()
                    .opacity(labelOpacity)
            }
        }
        // Blue "new / undiscovered" dot — disappears the first time the insight is hovered.
        .overlay(alignment: .topLeading) {
            if isVisible, undiscoveredInsightIDs.contains(insight.id) {
                Circle()
                    .fill(Color(red: 0.25, green: 0.55, blue: 1.0))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(insightTreeCanvasColor, lineWidth: 1.5))
                    .offset(x: 4, y: 4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .shadow(color: AquinasTheme.Colors.canvas.opacity(labelOpacity), radius: 24, x: 0, y: 0)
        .contentShape(Rectangle())
        .onTapGesture {
            // The placed-midpoint "Insight Loading Icon" stays hoverable even while generating;
            // other loading insights (Make Node children) are not tappable until revealed.
            guard canAcceptTap, !isLoading || isPinnedAtNode else { return }
            markDiscovered(insight.id)   // hovering clears its blue dot
            if selectedCanvasTargets.isEmpty {
                rippleTrigger = RippleTrigger(
                    worldOrigin: worldPosition,
                    startTime: Date().timeIntervalSinceReferenceDate
                )
            }
            focusHoveredTarget(at: worldPosition, in: size)
            onInsightTapped(insight)
        }
        .offset(y: isVisible ? 0 : 24)
        .opacity(isVisible ? 1 : 0)
        .blur(radius: isVisible ? 0 : 8)
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: isVisible)
        .transition(.scale(scale: 0.88, anchor: .center).combined(with: .opacity))
        .position(position)
        .zIndex(30)
    }

    private func insightFocusTarget(for insightID: UUID) -> CGPoint? {
        for node in displayNodes {
            if placedMidpointNodeIDs.contains(node.id), node.insights.contains(where: { $0.id == insightID }) {
                return node.position   // pinned chip sits on the node itself
            }
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

        // Placed midpoints only connect via their own source connectors — never the generic
        // 2-node / ring fallback, which would add a stray line to a neighbor node.
        let graphNodes = nodes.filter { !placedMidpointNodeIDs.contains($0.id) }
        guard graphNodes.count > 1 else {
            return []
        }

        if graphNodes.count == 2 {
            return [
                RenderedGraphEdge(
                    id: "\(graphNodes[0].id.uuidString)-\(graphNodes[1].id.uuidString)",
                    fromNodeID: graphNodes[0].id,
                    toNodeID: graphNodes[1].id,
                    isSuggested: false
                )
            ]
        }

        return graphNodes.indices.map { index in
            let nextIndex = (index + 1) % graphNodes.count
            return EdgeModel(
                id: UUID(),
                fromNodeID: graphNodes[index].id,
                toNodeID: graphNodes[nextIndex].id,
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

    /// Bond length (connector radius) for an insight chip — its relatedness to the parent node.
    private func bondLength(forInsightID id: UUID) -> CGFloat {
        insightBondLengths[id] ?? 190
    }

    /// Even starting angle for an insight before VSEPR repulsion spreads it.
    private func baseChipAngle(index: Int, count: Int) -> Double {
        Double(index) / Double(max(count, 1)) * (.pi * 2) + .pi / 8
    }

    /// Wraps an angle difference to [-π, π].
    private func wrapAngle(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 2 * .pi)
        if x > .pi { x -= 2 * .pi }
        if x < -.pi { x += 2 * .pi }
        return x
    }

    private func insightWorldPosition(for node: NodeModel, index: Int, count: Int) -> CGPoint {
        guard index < node.insights.count else { return node.position }
        let insightID = node.insights[index].id
        // Free VSEPR bond angle (falls back to the even base angle until the sim seeds it).
        let angle = chipAngles[insightID]?.angle ?? baseChipAngle(index: index, count: count)
        let radius = bondLength(forInsightID: insightID)
        return CGPoint(
            x: node.position.x + cos(angle) * radius,
            y: node.position.y + sin(angle) * radius
        )
    }

    // MARK: - Live Physics Simulation

    /// `nodes` with each position replaced by its live simulated position (falls back to the
    /// view model's position until a body is seeded). Everything renders off this.
    private var displayNodes: [NodeModel] {
        nodes.map { node in
            guard let body = bodies[node.id] else { return node }
            var copy = node
            copy.position = body.pos
            return copy
        }
    }

    /// Live simulated position for a node id (for by-id lookups).
    private func simPosition(of id: UUID) -> CGPoint? {
        bodies[id]?.pos ?? nodes.first(where: { $0.id == id })?.position
    }

    /// Mirrors `InsightTreeViewModel.mapDistanceToLength` — semantic distance → spring length.
    private func springTargetLength(_ distance: Double) -> CGFloat {
        80 + CGFloat(distance) * 320
    }

    /// Node footprint for the overlap-separation force — its longest bond plus chip extent.
    private func simFootprintRadius(_ node: NodeModel) -> CGFloat {
        if placedMidpointNodeIDs.contains(node.id) { return 70 }
        let maxBond = node.insights.prefix(6).map { bondLength(forInsightID: $0.id) }.max() ?? 190
        return maxBond + 64
    }

    private func startSim(frameBudget: Int = Self.settleFrameBudget) {
        simFramesRemaining = max(simFramesRemaining, frameBudget)
        alpha = 1.0
        lastTickAt = 0
        guard displayLink == nil else { return }
        let driver = DisplayLinkDriver()
        driver.onTick = { ts in stepSimulation(now: ts) }
        driver.start()
        displayLink = driver
    }

    private func stopSim() {
        displayLink?.stop()
        displayLink = nil
        simFramesRemaining = 0
        lastTickAt = 0
    }

    private func freezeSimulation(_ nextBodies: [UUID: SimBody]? = nil) {
        var frozen = nextBodies ?? bodies
        for (id, var body) in frozen {
            body.vel = .zero
            frozen[id] = body
        }
        bodies = frozen
        alpha = 0
        stopSim()
    }

    /// Seed bodies for new nodes, drop bodies for removed nodes, preserve the rest (no jump),
    /// and wake the sim. Called when the view model's topology changes.
    private func reconcileBodies() {
        let liveIDs = Set(nodes.map(\.id))
        var next = bodies.filter { liveIDs.contains($0.key) }
        for node in nodes where next[node.id] == nil {
            next[node.id] = SimBody(pos: node.position, vel: .zero)
        }
        bodies = next

        // Seed/drop per-insight bond angle; new chips start at their even base angle, then
        // VSEPR repulsion spreads them. Existing angles are preserved (no jump).
        let chipIDs = Set(nodes.flatMap { $0.insights.prefix(6).map(\.id) })
        var nextAngles = chipAngles.filter { chipIDs.contains($0.key) }
        for node in nodes {
            let count = min(node.insights.count, 6)
            for (index, insight) in node.insights.prefix(6).enumerated() where nextAngles[insight.id] == nil {
                nextAngles[insight.id] = ChipAngle(angle: baseChipAngle(index: index, count: count))
            }
        }
        chipAngles = nextAngles

        startSim()
    }

    /// One integration step. Reads live `bodies` positions, applies the same forces the view
    /// model's seed layout uses, holds pinned nodes fixed, and writes back once.
    private func stepSimulation(now: CFTimeInterval) {
        guard !bodies.isEmpty else { return }
        guard simFramesRemaining > 0 else {
            freezeSimulation()
            return
        }
        let dt = lastTickAt == 0 ? CGFloat(1.0 / 60) : CGFloat(min(now - lastTickAt, Self.simMaxDt))
        lastTickAt = now
        let dtScale = dt * 60   // ≈1 at 60fps; keeps motion frame-rate independent

        // Which nodes are held fixed this frame.
        var pinned = placedMidpointNodeIDs
        if isHoveringTarget, let focused = focusedNodeID() {
            pinned.insert(focused)   // keep the open-card node from sliding under its card
        }

        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let entries = bodies.map { ($0.key, $0.value) }
        var forces: [UUID: CGVector] = [:]
        var maxChipAngMotion: Double = 0   // keeps the sim awake while chips are still spreading

        // Live world positions of each visible chip (free VSEPR bond angle + relatedness radius),
        // used for cross-node node-push and the angular spread below.
        struct ChipInfo { let id: UUID; let nodeID: UUID; let angle: Double; let pos: CGPoint }
        var chipInfos: [ChipInfo] = []
        var chipByNode: [UUID: [CGPoint]] = [:]
        for (id, body) in bodies {
            if placedMidpointNodeIDs.contains(id) {
                chipByNode[id] = [body.pos]   // bare midpoint chip sits on the node
                continue
            }
            guard let node = nodeByID[id] else { continue }
            var pts: [CGPoint] = []
            for (index, insight) in node.insights.prefix(6).enumerated() {
                let theta = chipAngles[insight.id]?.angle ?? baseChipAngle(index: index, count: min(node.insights.count, 6))
                let radius = bondLength(forInsightID: insight.id)
                let pos = CGPoint(x: body.pos.x + cos(theta) * radius, y: body.pos.y + sin(theta) * radius)
                chipInfos.append(ChipInfo(id: insight.id, nodeID: id, angle: theta, pos: pos))
                pts.append(pos)
            }
            chipByNode[id] = pts
        }

        // Every domain around a node: its insight bonds AND its bonds to neighbor nodes. VSEPR
        // repels them all equally — chip bonds rotate the chip angle, edge bonds rotate the
        // neighbor node tangentially (at fixed bond length), so bond angles are maximized.
        enum BondKind { case insight(UUID); case edge(neighbor: UUID) }
        struct Bond { let angle: Double; let kind: BondKind }
        var bondsByNode: [UUID: [Bond]] = [:]
        for ci in chipInfos {
            bondsByNode[ci.nodeID, default: []].append(Bond(angle: ci.angle, kind: .insight(ci.id)))
        }
        // Use the SAME edges that are rendered (displayGraphEdges fabricates a line for the
        // 2-node / ring fallback), so every visible node-to-node line is a VSEPR domain too.
        for edge in displayGraphEdges() {
            guard let aPos = bodies[edge.fromNodeID]?.pos, let bPos = bodies[edge.toNodeID]?.pos else { continue }
            bondsByNode[edge.fromNodeID, default: []].append(Bond(angle: Double(atan2(bPos.y - aPos.y, bPos.x - aPos.x)), kind: .edge(neighbor: edge.toNodeID)))
            bondsByNode[edge.toNodeID, default: []].append(Bond(angle: Double(atan2(aPos.y - bPos.y, aPos.x - bPos.x)), kind: .edge(neighbor: edge.fromNodeID)))
        }

        // Repulsion (all pairs) + overlap separation + per-chip bubble collision.
        for i in entries.indices {
            let (idA, a) = entries[i]
            if pinned.contains(idA) { continue }
            var fx: CGFloat = 0, fy: CGFloat = 0
            for j in entries.indices where j != i {
                let (idB, b) = entries[j]
                var dx = a.pos.x - b.pos.x
                var dy = a.pos.y - b.pos.y
                var dist = hypot(dx, dy)
                if dist < 0.5 { dx = .random(in: -1...1); dy = .random(in: -1...1); dist = 1 }
                let clamped = max(Self.repulsionMinDist, dist)
                let f = Self.repulsionK / (clamped * clamped)
                fx += (dx / dist) * f
                fy += (dy / dist) * f

                if let na = nodeByID[idA], let nb = nodeByID[idB] {
                    let minDist = simFootprintRadius(na) + simFootprintRadius(nb) + Self.overlapPadding
                    if dist < minDist {
                        let push = (minDist - dist) * 0.05
                        fx += (dx / dist) * push
                        fy += (dy / dist) * push
                    }
                }

                // Per-chip bubbles: if any of A's chips overlaps any of B's chips, bump A away.
                if let chipsA = chipByNode[idA], let chipsB = chipByNode[idB] {
                    let minChip = Self.insightBubbleRadius * 2 + Self.insightBubblePadding
                    for ca in chipsA {
                        for cb in chipsB {
                            var cdx = ca.x - cb.x
                            var cdy = ca.y - cb.y
                            var cd = hypot(cdx, cdy)
                            if cd >= minChip { continue }
                            if cd < 0.5 { cdx = .random(in: -1...1); cdy = .random(in: -1...1); cd = 1 }
                            let push = (minChip - cd) * Self.bubblePushK
                            fx += (cdx / cd) * push
                            fy += (cdy / cd) * push
                        }
                    }
                }
            }
            // No idle jitter: once the short settling pass ends, nodes stay put.
            fx += CGFloat.random(in: -Self.jitterAmplitude...Self.jitterAmplitude) * CGFloat(alpha)
            fy += CGFloat.random(in: -Self.jitterAmplitude...Self.jitterAmplitude) * CGFloat(alpha)
            forces[idA] = CGVector(dx: fx, dy: fy)
        }

        // Unified VSEPR bond-angle spread: for every node, all incident domains (insight bonds +
        // bonds to neighbor nodes) repel each other equally toward maximum separation. Insight
        // bonds rotate the chip's free angle directly; node-to-node bonds apply a *tangential
        // force* that swings the neighbor around the shared node through the damped velocity
        // pipeline. The rigid edge constraint below re-fixes the bond length each frame.
        var chipTorque: [UUID: Double] = [:]
        for (_, bonds) in bondsByNode where bonds.count > 1 {
            for ii in bonds.indices {
                let bi = bonds[ii]
                var torque = 0.0
                for jj in bonds.indices where jj != ii {
                    var dθ = wrapAngle(bi.angle - bonds[jj].angle)
                    if abs(dθ) < 1e-4 { dθ = .random(in: -0.05...0.05) }
                    torque += Self.domainK * (dθ >= 0 ? 1 : -1) / (abs(dθ) + Self.chipAngleEps)
                }
                switch bi.kind {
                case .insight(let id):
                    chipTorque[id, default: 0] += torque
                case .edge(let neighbor):
                    guard !pinned.contains(neighbor) else { continue }
                    // Tangential direction (perpendicular to the bond) around the shared node.
                    let tx = CGFloat(-sin(bi.angle)), ty = CGFloat(cos(bi.angle))
                    var mag = CGFloat(torque) * Self.edgeTorqueGain
                    mag = max(-Self.edgeTorqueMax, min(Self.edgeTorqueMax, mag))
                    forces[neighbor, default: .zero].dx += tx * mag
                    forces[neighbor, default: .zero].dy += ty * mag
                }
            }
        }
        // Cooling factor (simulated annealing). The VSEPR angular repulsion and pairwise node
        // repulsion never vanish at equilibrium, so leaving motion uncooled makes bonds oscillate
        // around the ±π boundary and nodes creep — visible as jitter that only stops when the frame
        // budget expires. Scaling every frame's displacement by `alpha` (which decays to 0) lets the
        // layout converge and freeze smoothly.
        let cool = alpha
        let coolCG = CGFloat(alpha)

        if !chipTorque.isEmpty {
            var nextAngles = chipAngles
            for (id, torque) in chipTorque {
                guard var ch = nextAngles[id] else { continue }
                let rawStep = max(-Self.chipMaxAngStep, min(Self.chipMaxAngStep, torque * Self.chipAngGain * Double(dtScale)))
                let step = rawStep * cool
                ch.angle += step
                maxChipAngMotion = max(maxChipAngMotion, abs(step))
                nextAngles[id] = ch
            }
            chipAngles = nextAngles
        }

        // Integrate (semi-implicit Euler; force scaled into velocity so spacing is effective).
        var next = bodies
        var maxMove: CGFloat = 0
        for (id, force) in forces {
            guard var body = next[id], !pinned.contains(id) else { continue }
            let vx = (body.vel.dx + force.dx * Self.forceGain * dtScale) * Self.simDamping
            let vy = (body.vel.dy + force.dy * Self.forceGain * dtScale) * Self.simDamping
            // Clamp the per-frame move (matches the view model's ±4 clamp), then cool it.
            let stepX = max(-Self.simMaxStep, min(Self.simMaxStep, vx * dtScale)) * coolCG
            let stepY = max(-Self.simMaxStep, min(Self.simMaxStep, vy * dtScale)) * coolCG
            body.pos.x += stepX
            body.pos.y += stepY
            body.vel = CGVector(dx: vx, dy: vy)
            next[id] = body
            maxMove = max(maxMove, hypot(stepX, stepY))
        }

        // Rigid edge constraint: lines keep their fixed target length (no growing/shrinking).
        // A few projection iterations snap each connected pair back to its target distance.
        for _ in 0..<Self.constraintIterations {
            for edge in edges {
                guard var a = next[edge.fromNodeID], var b = next[edge.toNodeID] else { continue }
                let aPin = pinned.contains(edge.fromNodeID)
                let bPin = pinned.contains(edge.toNodeID)
                if aPin && bPin { continue }
                var dx = b.pos.x - a.pos.x
                var dy = b.pos.y - a.pos.y
                var d = hypot(dx, dy)
                if d < 0.001 { dx = .random(in: -1...1); dy = .random(in: -1...1); d = 1 }
                let target = springTargetLength(edge.distance)
                let corr = (d - target) / d
                if aPin {
                    b.pos.x -= dx * corr; b.pos.y -= dy * corr
                    next[edge.toNodeID] = b
                } else if bPin {
                    a.pos.x += dx * corr; a.pos.y += dy * corr
                    next[edge.fromNodeID] = a
                } else {
                    a.pos.x += dx * corr * 0.5; a.pos.y += dy * corr * 0.5
                    b.pos.x -= dx * corr * 0.5; b.pos.y -= dy * corr * 0.5
                    next[edge.fromNodeID] = a
                    next[edge.toNodeID] = b
                }
            }
        }

        // Pinned bodies track their authoritative view-model position.
        for id in pinned {
            if let node = nodeByID[id] { next[id]?.pos = node.position }
        }

        // Drift guard: with nothing pinned to anchor the graph, keep the centroid of all
        // bodies fixed frame-to-frame. This removes any net translation the bond-angle forces
        // introduce, so the tree spreads in place instead of flying off in one direction.
        if pinned.isEmpty, !next.isEmpty {
            var oldSum = CGPoint.zero, newSum = CGPoint.zero
            for (id, body) in next {
                newSum.x += body.pos.x; newSum.y += body.pos.y
                let prev = bodies[id]?.pos ?? body.pos
                oldSum.x += prev.x; oldSum.y += prev.y
            }
            let n = CGFloat(next.count)
            let shiftX = (oldSum.x - newSum.x) / n
            let shiftY = (oldSum.y - newSum.y) / n
            if abs(shiftX) > 0.0001 || abs(shiftY) > 0.0001 {
                for id in next.keys {
                    next[id]?.pos.x += shiftX
                    next[id]?.pos.y += shiftY
                }
            }
        }

        alpha = max(Self.alphaFloor, alpha * (1 - Self.alphaDecay))
        simFramesRemaining -= 1
        // Settle once the actual (cooled) per-frame motion is negligible — both node displacement
        // and chip-angle rotation. Because displacement is cooled by `alpha`, this is reached
        // smoothly instead of being cut off by the frame budget mid-jitter.
        let settled = maxMove <= Self.settleVelocityThreshold && maxChipAngMotion <= 0.002
        if simFramesRemaining <= 0 || (alpha <= 0.01 && settled) {
            freezeSimulation(next)
        } else {
            bodies = next
        }
    }

    /// The node id owning the currently focused/hovered target, if any.
    private func focusedNodeID() -> UUID? {
        if let nodeID = pulsingNodeID { return nodeID }
        if let insightID = focusedInsightID ?? pulsingInsightID {
            return nodes.first(where: { $0.insights.contains { $0.id == insightID } })?.id
        }
        return nil
    }

    /// Report live positions up for persistence.
    private func persistLivePositions() {
        guard !bodies.isEmpty else { return }
        onPositionsSettled(bodies.mapValues(\.pos))
    }

    // MARK: - New-Insight Entrance Sequence

    private func loadSeenInsightIDs() -> Set<UUID> {
        InsightDiscoveryStore.loadSeenInsightIDs()
    }

    private func saveAllInsightIDsAsSeen() {
        let ids = nodes.flatMap { $0.insights }.map(\.id)
        InsightDiscoveryStore.saveSeenInsightIDs(ids)
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

    // MARK: - Undiscovered (blue-dot) tracking

    private func loadUndiscoveredInsightIDs() -> Set<UUID> {
        InsightDiscoveryStore.loadUndiscoveredInsightIDs()
    }

    private func persistUndiscoveredInsightIDs() {
        InsightDiscoveryStore.saveUndiscoveredInsightIDs(undiscoveredInsightIDs)
    }

    private func reportUndiscoveredInsightCount() {
        let visibleInsightIDs = Set(nodes.flatMap { node in
            Array(node.insights.prefix(6)).map(\.id)
        })
        onUndiscoveredInsightCountChange(undiscoveredInsightIDs.intersection(visibleInsightIDs).count)
    }

    /// Flag newly appeared/generated insights as undiscovered (they get a blue dot).
    private func markUndiscovered(_ ids: [UUID]) {
        var changed = false
        for id in ids where !undiscoveredInsightIDs.contains(id) {
            undiscoveredInsightIDs.insert(id)
            changed = true
        }
        if changed {
            persistUndiscoveredInsightIDs()
            reportUndiscoveredInsightCount()
        }
    }

    /// The user hovered an insight — clear its blue dot (forever).
    private func markDiscovered(_ id: UUID) {
        guard undiscoveredInsightIDs.contains(id) else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            _ = undiscoveredInsightIDs.remove(id)
        }
        persistUndiscoveredInsightIDs()
        reportUndiscoveredInsightCount()
    }

    /// World position of an insight looked up by ID (nil if not visible on tree).
    private func worldPosition(forInsightID id: UUID) -> CGPoint? {
        for node in displayNodes {
            if placedMidpointNodeIDs.contains(node.id), node.insights.contains(where: { $0.id == id }) {
                return node.position   // pinned chip sits on the node itself
            }
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
    /// Pass `center` to anchor on a specific world point (e.g. a node) instead of the
    /// bounding-box centroid of `positions`.
    private func zoomToFit(
        worldPositions positions: [CGPoint],
        in size: CGSize,
        padding: CGFloat = 180,
        fitFactor: CGFloat = 0.88,
        center: CGPoint? = nil
    ) {
        guard positions.count >= 2 else {
            if let pos = positions.first { focusInsight(at: pos, in: size) }
            return
        }

        let minX = positions.map { $0.x }.min()!
        let maxX = positions.map { $0.x }.max()!
        let minY = positions.map { $0.y }.min()!
        let maxY = positions.map { $0.y }.max()!

        let worldWidth          = max(maxX - minX + padding * 2, 1)
        let worldHeight         = max(maxY - minY + padding * 2, 1)
        let targetScale         = clamp(
            min(size.width / worldWidth, size.height / worldHeight) * fitFactor,
            lower: 0.28, upper: 1.4
        )
        let centerX = center?.x ?? (minX + maxX) / 2
        let centerY = center?.y ?? (minY + maxY) / 2

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

    /// Node Concept labels fade at a lower zoom than insight chips, so they stay legible
    /// when zoomed further out (insight chips drop away first, concepts persist).
    private static func nodeLabelOpacity(for scale: CGFloat) -> Double {
        let startFade = CGFloat(0.30)
        let fullyVisible = CGFloat(0.40)
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

/// A simulated node: live position + velocity, integrated each frame.
struct SimBody {
    var pos: CGPoint
    var vel: CGVector
}

/// Per-insight bond angle around its node (free absolute angle in radians; VSEPR repulsion
/// spreads chips to maximize separation).
struct ChipAngle {
    var angle: Double
}

/// Drives a per-frame tick from a `CADisplayLink`. The callback fires as a run-loop event
/// OUTSIDE SwiftUI body evaluation, so the sim can safely assign `@State` each frame (doing
/// that inside a `TimelineView` closure would be "modifying state during view update").
@MainActor
final class DisplayLinkDriver {
    private var link: CADisplayLink?
    var onTick: ((CFTimeInterval) -> Void)?

    private final class Proxy: NSObject {
        let fire: (CFTimeInterval) -> Void
        init(_ fire: @escaping (CFTimeInterval) -> Void) { self.fire = fire }
        @objc func step(_ link: CADisplayLink) { fire(link.timestamp) }
    }

    func start() {
        guard link == nil else { return }
        let proxy = Proxy { [weak self] ts in self?.onTick?(ts) }
        let l = CADisplayLink(target: proxy, selector: #selector(Proxy.step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }
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

/// The selection-mode reticle: a small circle indicating where the next insight connects.
private struct SelectionReticle: View {
    var body: some View {
        Circle()
            .stroke(AquinasTheme.Colors.lightGreen.opacity(0.8), lineWidth: 1.5)
            .frame(width: 18, height: 18)
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
                    .foregroundStyle(AquinasTheme.Colors.accentGreen)
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
private struct RevealedInsightLabel: View {
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
                .opacity(labelOpacity)
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

private extension AnyTransition {
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
