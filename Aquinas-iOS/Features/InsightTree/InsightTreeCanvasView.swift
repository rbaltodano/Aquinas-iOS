//
//  InsightTreeCanvasView.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit
import Observation
import simd

@MainActor
@Observable
private final class InsightTreeCanvasCameraState {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var isDragging = false
    var lastDragEndedAt: Date = .distantPast
    var pinchStartScale: CGFloat?
    var pinchStartOffset: CGSize?
    var preFocusSnapshot: InsightTreeCameraSnapshot?
    var userMovedSincePlacement = false
}

// MARK: - Insight Tree Canvas

/// SwiftUI-native graph renderer for the insight tree.
/// Text and SF Symbols stay vector/crisp while the graph remains pannable and zoomable.
struct InsightTreeCanvasView: View {
    let nodes: [NodeModel]
    let edges: [EdgeModel]
    let restoreFocusedCameraRequest: Int
    let focusedInsightID: UUID?
    let focusedSearchNodeID: UUID?
    let pulsingInsightID: UUID?
    let pulsingNodeID: UUID?
    let selectedCanvasTargets: [CanvasSelectionTarget]
    let selectionPulseRequest: Int
    var makeNodeChildIDs: Set<UUID> = []
    var generatedMakeNodeChildIDs: Set<UUID> = []
    /// Nodes that are user-placed midpoints — rendered as a bare insight chip (no
    /// node-concept circle), pinned at the node position.
    var placedMidpointNodeIDs: Set<UUID> = []
    /// For each placed-midpoint node, the sources it connects to (insight chips / node concepts).
    var placedMidpointSources: [UUID: [MidpointSource]] = [:]
    /// Per-insight bond length (connector radius) from relatedness to the parent node.
    var insightBondLengths: [UUID: CGFloat] = [:]
    /// Semantic (MDS) target position per node. The sim anchors each node here with a weak
    /// spring so overlap cleanup can't destroy the embedding-driven layout.
    var layoutTargets: [UUID: CGPoint] = [:]
    /// Normalized [0,1] depth per node (1 = nearest) from the third MDS component,
    /// driving the 2.5D depth cues. Missing entries render at full depth.
    var nodeDepths: [UUID: Double] = [:]
    /// Global Insights renders every member in each cluster. Conversation trees remain compact.
    var showsAllClusterInsights: Bool = false
    /// Conversation trees begin with an in-memory fallback and replace it asynchronously with
    /// backend-owned topology. Their entrance must wait for that persisted snapshot.
    var defersEntranceUntilPersistedTree: Bool = false
    /// Advances after a fully reconciled persisted snapshot is applied.
    var persistedTreePresentationRevision: Int = 0
    /// Matches the presentation revision only when that snapshot follows a real mutation.
    var animatedPersistedTreePresentationRevision: Int = 0
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
    /// Matches the placed id after generated content has replaced the loading placeholder.
    var midpointGeneratedInsightID: UUID? = nil
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
    /// Reports the current blue-dot count whenever Insights or Node Concepts change discovery.
    var onUndiscoveredInsightCountChange: (Int) -> Void = { _ in }
    /// The Node Concept being studied. The canvas camera shifts from the tree's framing into
    /// `studySlot` while the rest of the tree fades; nil shifts it back. The studied node is
    /// the tree's own node, never a copy.
    var studyNodeID: UUID? = nil
    /// An Insight of the studied node to open Study already hovered on.
    var studyInitialHoverInsightID: UUID? = nil
    /// The Study slot, in this canvas's coordinates.
    var studySlot: CGRect? = nil

    @Environment(\.scenePhase) private var scenePhase

    @State private var cameraState = InsightTreeCanvasCameraState()
    @State private var selectedEdgeID: UUID?
    @State private var rippleTrigger:      RippleTrigger? = nil
    @State private var selectionRipples:   [RippleTrigger] = []
    @State private var hasAppeared:        Bool = false
    @State private var revealedInsightIDs: Set<UUID> = []
    /// Connector lines for newly inserted Insights are intentionally staged after the chip
    /// reveal. Existing lines are seeded here immediately; new lines are added by the entrance
    /// sequence once the Insight's own animation has completed.
    @State private var revealedInsightConnectorIDs: Set<UUID> = []
    @State private var revealedGraphEdgeIDs: Set<String> = []
    @State private var animatedGraphEdgeIDs: Set<String> = []
    @State private var revealedNodeIDs: Set<UUID> = []
    /// Stable topology baselines for live (non-persisted) trees. Reveal state is deliberately
    /// separate: an Insight can already belong to the tree while remaining hidden during its
    /// camera/reveal sequence, so using `revealedInsightIDs` to detect additions can replay an
    /// entrance whenever an unrelated node update arrives mid-animation.
    @State private var observedLiveInsightIDs: Set<UUID> = []
    @State private var observedLiveNodeIDs: Set<UUID> = []
    /// Insights the user hasn't opened yet — they show a blue "new" dot until first hovered.
    @State private var undiscoveredInsightIDs: Set<UUID> = []
    /// New Node Concepts keep their own discovery state and clear it when first opened.
    @State private var undiscoveredNodeIDs: Set<UUID> = []
    @State private var entranceTask:       Task<Void, Never>? = nil
    @State private var midpointRevealTask: Task<Void, Never>? = nil
    @State private var midpointLoadingStartedAt: [UUID: TimeInterval] = [:]
    @State private var makeNodeRevealTask: Task<Void, Never>? = nil
    @State private var makeNodeLoadingStartedAt: TimeInterval?
    @State private var pendingMakeNodeChildren: [PendingMakeNodeChild] = []
    /// Baseline for detecting Insights and Node Concepts added by a persisted tree mutation.
    @State private var confirmedPersistedInsightIDs: Set<UUID> = []
    @State private var confirmedPersistedNodeIDs: Set<UUID> = []
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
    @GestureState private var dragOffset:  CGSize = .zero

    private struct PendingMakeNodeChild: Equatable {
        let id: UUID
        let orbitIndex: Int
    }

    /// The narrow slice of node state that actually changes graph geometry.
    /// Labels, definitions, embeddings, and refreshed snapshots with identical membership
    /// must not wake the physics simulation.
    private struct PhysicsNodeSignature: Equatable {
        let id: UUID
        let visibleInsightIDs: [UUID]
    }

    // MARK: - Live physics simulation
    /// Per-node simulated position + velocity. The canvas briefly relaxes these from the
    /// view model's seed positions after topology changes, then freezes to avoid passive drift.
    @State private var bodies: [UUID: SimBody] = [:]
    /// Per-insight free bond angle around its node; VSEPR repulsion spreads chips to maximize
    /// angular separation. Keyed by insight id.
    @State private var chipAngles: [UUID: ChipAngle] = [:]
    /// Per-insight elevation angle (radians, within ±45°) above or below the plane. Seeded at
    /// its cluster's spread target (`InsightClusterSpatialLayout.elevationTargets`) in
    /// `reconcileBodies`; the sim eases each toward updated targets as the cluster changes.
    @State private var chipElevationAngles: [UUID: CGFloat] = [:]

    // MARK: Node Concept Study
    /// The node being studied; kept through the shift back so it lands in place.
    @State private var studyFocusNodeID: UUID?
    /// 0 = the tree's framing, 1 = the Study framing.
    @State private var studyProgress: Double = 0
    /// Each studied Insight's offset from its Node Concept in the tree, and its Study direction
    /// (spread over the whole sphere; the ±45° limit only applies in the tree).
    @State private var studyTreeOffsets: [UUID: SIMD3<Double>] = [:]
    @State private var studySpread: [UUID: SIMD3<Double>] = [:]
    @State private var studyRadius: Double = 190
    @State private var studyYaw: Double = 0
    @State private var studyPan: CGSize = .zero
    @State private var studyZoom: CGFloat = 1
    @State private var studyPinchStartZoom: CGFloat?
    @State private var studyDragMode: StudyDragMode?
    @State private var studyLastDragLocation: CGPoint?
    @State private var studyLastDetentYaw: Double = 0
    /// 0 → 1 while a finger is on the ring; eased, so the ring brightens and grows smoothly.
    @State private var studyRingActive: Double = 0
    /// A tapped Insight in Study: centered, zoomed in on, and the axis of rotation.
    /// `studyPivotBlend` eases 0 ↔ 1; the id is kept while easing back to the node.
    @State private var studyPivotID: UUID?
    @State private var studyPivotBlend: Double = 0
    @State private var studyPivotLink: DisplayLinkDriver?
    /// When the focus moves from one Insight to another, the camera glides from the previous
    /// one's position (`studyPivotSwitch` 0 → 1).
    @State private var studyPivotFrom: SIMD3<Double>?
    @State private var studyPivotSwitch: Double = 1
    @State private var studyPivotSwitchLink: DisplayLinkDriver?
    /// Set when a focused Insight is released, so the axis returns to the node without the
    /// view moving (see `releaseStudyPivot`).
    @State private var studyTargetShift: SIMD3<Double> = .zero
    @State private var lastCanvasSize: CGSize = .zero
    /// Ring momentum: yaw keeps turning after release and eases to a stop.
    @State private var studySpinLink: DisplayLinkDriver?
    @State private var studyRingHalfWidth: CGFloat = 150
    /// A plain touch becomes a pan (and lets go of a focused Insight) only past this distance,
    /// so a tap never releases it.
    private static let studyTapSlop: CGFloat = 6
    @State private var studyLink: DisplayLinkDriver?
    /// Measured label footprints by title. A reference type so filling it never invalidates the
    /// view; the simulation reads every chip's footprint on every frame.
    @State private var collisionSizeCache = InsightCollisionSizeCache()
    @State private var alpha: Double = 0
    @State private var displayLink: DisplayLinkDriver? = nil
    @State private var lastTickAt: CFTimeInterval = 0
    @State private var simFramesRemaining: Int = 0
    @State private var simAlphaDecay: Double = 0.08
    @State private var breezeStartedAt: CFTimeInterval?
    @State private var breezeDirection = CGVector(dx: 0.92, dy: -0.38)

    // MARK: - Chip rotate-drag
    /// The Insight chip currently being press-and-dragged around its parent Node. While set,
    /// `insightWorldPosition` reports the live drag point instead of the (angle, bond length)
    /// pair, so the chip and its connector line follow the finger anywhere — including stretching
    /// past the chip's normal orbit radius.
    @State private var draggingChipID: UUID? = nil
    @State private var draggingChipWorldPosition: CGPoint? = nil
    /// Where the dragged chip started, captured once when the drag is promoted. Any placed
    /// Midpoint it's a source of leans toward it by a fraction of `live - start` (see
    /// `stepSimulation`'s pinned-body loop) — the delta, not the raw drag point, is what that
    /// Midpoint follows.
    @State private var draggingChipStartWorldPosition: CGPoint? = nil
    /// Insight chip angles the user (or a Midpoint connection) has deliberately pointed somewhere
    /// specific — the ongoing VSEPR angular-spread simulation must never overwrite these, or the
    /// very torque that keeps siblings from overlapping quietly rotates a chosen angle right back
    /// out from under it a few frames later.
    @State private var pinnedChipAngleIDs: Set<UUID> = []
    /// Sticky for one `panGesture` lifetime: set as soon as a chip rotate-drag is seen to be in
    /// progress, so `.onEnded` — which fires with the gesture's full raw translation regardless of
    /// what `.onChanged`/`.updating` did — knows not to commit that translation as a canvas pan.
    @State private var panGestureBlockedByChipDrag = false
    /// The chip a touch-down is currently pending a long-press timer for (see
    /// `chipRotateDragGesture`). Kept as plain state rather than `LongPressGesture.sequenced` —
    /// composed with the always-simultaneous root pan gesture, the sequenced form dropped its own
    /// `.onEnded` on release often enough in practice to leave `draggingChipID` stuck, freezing
    /// the whole canvas at half opacity. A single `DragGesture` has none of that ambiguity.
    @State private var chipPressCandidateID: UUID? = nil
    @State private var chipPressStartLocation: CGPoint? = nil
    @State private var chipPressLastLocation: CGPoint? = nil

    // Cleanup-pass constants. Global structure comes from the view model's semantic (MDS)
    // layout; the sim only anchors nodes to those targets, separates overlaps, and spreads
    // chip labels — it never invents structure of its own.
    private static let anchorSpringK: CGFloat = 0.04    // weak pull toward the MDS target
    private static let overlapPadding: CGFloat = 24
    private static let simDamping: CGFloat = 0.62       // lower = settles faster, less wobble
    private static let simMaxStep: CGFloat = 4          // per-frame move clamp
    private static let simMaxDt: CFTimeInterval = 1.0 / 30
    private static let alphaDecay: Double = 0.045
    private static let updateAlphaDecay: Double = 0.05
    private static let updateIntensity: Double = 0.14
    private static let breezeDuration: CFTimeInterval = 1.5
    private static let breezeForce: CGFloat = 0.9
    private static let alphaFloor: Double = 0
    private static let jitterAmplitude: CGFloat = 0
    private static let settleFrameBudget: Int = 150   // longer: chip bonds rotate into place
    private static let settleVelocityThreshold: CGFloat = 0.02
    // Insight collision uses the chip's measured horizontal label footprint, not a fixed circle.
    // Cross-node contact both separates parent nodes and rotates each free Insight bond.
    private static let insightCollisionPadding: CGFloat = 24
    private static let bubblePushK: CGFloat = 0.08
    private static let crossNodeChipTorqueK: Double = 2.4
    private static let forceGain: CGFloat = 0.5          // scales summed force → velocity
    // Chip-label angular spread: every bond domain around a Node Concept has equal angular
    // weight, including both Insight bonds and fixed node-to-node lines. Only chip angles move;
    // node positions remain anchored to the semantic MDS targets.
    private static let bondDomainK: Double = 1.4
    private static let chipAngGain: Double = 0.45        // viscous angular response speed
    private static let chipMaxAngStep: Double = 0.07     // max radians a bond rotates per frame
    private static let elevationEaseRate: CGFloat = 0.2  // fraction of the way to target per frame
    private static let chipAngleEps: Double = 0.12       // softens the 1/Δθ repulsion
    // The uniform VSEPR spread above maximizes angular separation equally across every bond, but
    // has no notion of how WIDE any one chip's label actually is — a long title next to a short
    // one can still settle at an angular gap that's fine on average yet too tight for their real
    // footprints, especially at a small orbit radius (arc length = radius × angle, so the same
    // angular gap is a smaller physical gap closer in). This adds an extra, targeted push whenever
    // two same-node Insight chips' angular gap is below what their combined half-widths need at
    // their shared orbit radius — same-node counterpart to the cross-node bounding-box collision.
    private static let chipWidthAngularPadding: CGFloat = 20   // desired gap between chip edges
    private static let chipWidthRepulsionK: Double = 2.2
    private static let insightCollisionFont =
        UIFont(name: "Figtree-Bold", size: 14) ?? .boldSystemFont(ofSize: 14)
    // 2.5D depth cues from the third MDS component. One switch: false → pure 2D rendering.
    private static let depthCuesEnabled = true
    private static let depthMinScale: CGFloat = 0.85     // farthest node's scale
    private static let depthMinOpacity: Double = 0.75    // farthest node's dimming

    /// One visible Insight's resolved geometry for the current render.
    fileprivate struct InsightPlacement {
        let insight: InsightModel
        let nodeID: UUID
        let index: Int
        let count: Int
        let isPinnedAtNode: Bool
        /// Footprint on the graph plane (the live drag point while this chip is dragged).
        let world: CGPoint
        /// World units above (+) or below (−) the graph plane; 0 for pinned midpoints.
        let elevation: CGFloat
        /// Normalized local elevation in [-1, 1]; 0 for pinned midpoints.
        let localDepth: CGFloat
    }

    fileprivate struct CanvasInsightLayout {
        var nodes: [NodeModel]
        var insightsByNode: [UUID: [InsightModel]] = [:]
        var placements: [UUID: InsightPlacement] = [:]
    }

    private var activeScale: CGFloat {
        clamp(cameraState.scale, lower: 0.28, upper: 2.6)
    }

    private var activeOffset: CGSize {
        CGSize(
            width: cameraState.offset.width + dragOffset.width,
            height: cameraState.offset.height + dragOffset.height
        )
    }

    private var physicsTopologySignature: [PhysicsNodeSignature] {
        nodes.map {
            PhysicsNodeSignature(
                id: $0.id,
                visibleInsightIDs: canvasInsights(for: $0).map(\.id)
            )
        }
    }

    private var insightTreeCanvasColor: Color {
        AquinasTheme.Colors.canvas
    }

    /// While a selection exists and nothing is hovered, the unselected nodes/insights flash
    /// (mirroring the "Add concept to selection" button) to invite adding another. Hovering stops it.
    private var insightsFlashing: Bool {
        !selectedCanvasTargets.isEmpty
            && selectedCanvasTargets.count < CanvasSelectionPolicy.maximumCount
            && !isHoveringTarget
            && !isMidpointMode
    }

    private func itemFlashOpacity(selected: Bool) -> Double {
        guard insightsFlashing, !selected else { return 1 }
        return Double(selectionFlashOpacity)
    }

    private var insightTreeInsightColor: Color {
        Color(light: 0xFFFAF0, dark: 0x0A0602)
    }

    private func focusAnchor(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let studyFraming = makeStudyFraming(in: size)
            let treeCamera = InsightTreeCamera(scale: activeScale, offset: activeOffset)
            let camera = studyCamera(treeCamera, framing: studyFraming, in: size)
            // The ring stays put while the user pans or zooms the node in Study; its dashes turn
            // with the node.
            let studyRingCamera = studyFraming.map { framing in
                framing.camera(from: treeCamera.currentOrbitCamera(in: size), progress: studyProgress)
            }
            let studyRing = studyFraming.flatMap { framing in
                studyRingCamera.map { framing.ringPoints(camera: $0) }
            } ?? []
            let studyRingDashes = studyFraming.flatMap { framing in
                studyRingCamera.map { framing.ringDashes(camera: $0, yaw: studyYaw * studyProgress) }
            } ?? []
            let restFade = studyFocusNodeID == nil ? 1 : 1 - studyProgress
            let studyReady = studyNodeID != nil && studyFocusNodeID != nil && studyProgress > 0.99
            let labelOpacity = Self.labelOpacity(for: activeScale)
            let nodeLabelOpacity = Self.nodeLabelOpacity(for: activeScale)
            let layout = makeInsightLayout()
            let studyChipTargets = studyReady ? studyTapTargets(layout: layout, camera: camera, size: size) : []
            let studyNodeTarget = studyReady ? studyNodeTapTarget(camera: camera, size: size) : nil

            ZStack {
                insightTreeCanvasColor.ignoresSafeArea()
                AnimatedDotGridBackground(
                    settledOffset: cameraState.offset,
                    settledScale:  activeScale,
                    dragOffset:    dragOffset,
                    ripples:       (rippleTrigger.map { [$0] } ?? []) + selectionRipples
                )
                // Keep the grid's Canvas in the exact same coordinate frame as the graph.
                // Expanding it independently into the safe area shifts ripple origins away
                // from the focused chip even though both use the same camera transform.
                .frame(width: size.width, height: size.height)
                .opacity(hasAppeared ? restFade : 0)
                .animation(.easeOut(duration: 0.6), value: hasAppeared)

                // In Study the grid tips up into a floor under the ring, moving with the node.
                if let studyFraming, let studyOrbit = camera.orbit {
                    StudyFloorGrid(framing: studyFraming, camera: studyOrbit)
                        .frame(width: size.width, height: size.height)
                        .opacity(studyProgress)
                }

                ZStack {
                    if studyFocusNodeID != nil {
                        StudyFloorRing(points: studyRing, dashes: studyRingDashes, activeAmount: studyRingActive)
                            .frame(width: size.width, height: size.height)
                            .opacity(studyProgress)
                    }
                    Group {
                        graphEdges(camera: camera, size: size)
                        midpointConnectors(layout: layout, camera: camera, size: size)
                    }
                    .opacity(restFade)
                    insightConnectors(layout: layout, camera: camera, size: size)
                    // Hover pulses stay in Study: they only ever run along the hovered item's
                    // connectors, which in Study belong to the studied cluster.
                    connectorPulseOverlay(layout: layout, camera: camera, size: size)
                    Group {
                        selectionOverlay(layout: layout, camera: camera, size: size)
                        edgeHitTargets(camera: camera, size: size)
                    }
                    .opacity(restFade)

                    ForEach(layout.nodes) { node in
                        let visibleInsights = layout.insightsByNode[node.id] ?? []
                        // Placed-midpoint nodes render as just their insight chip — no concept circle.
                        if !placedMidpointNodeIDs.contains(node.id),
                           revealedNodeIDs.contains(node.id) {
                            nodeGroup(node, camera: camera, size: size, labelOpacity: nodeLabelOpacity)
                                .opacity(itemFlashOpacity(selected: selectedCanvasTargets.contains(.node(node.id))))
                                .opacity(studyOpacity(forNodeID: node.id))
                        }

                        ForEach(visibleInsights) { insight in
                            if let placement = layout.placements[insight.id] {
                                insightLabel(
                                    placement,
                                    node: node,
                                    camera: camera,
                                    size: size,
                                    labelOpacity: labelOpacity
                                )
                                .opacity(itemFlashOpacity(selected: selectedCanvasTargets.contains(.insight(insight.id))))
                            }
                        }
                    }
                }
                .opacity(isMidpointMode ? 0 : 1)
                // In Study only the Study gestures below respond.
                .allowsHitTesting(!isMidpointMode && studyFocusNodeID == nil)
                .animation(.easeInOut(duration: 0.3), value: isMidpointMode)

                if isMidpointMode {
                    midpointOverlay(layout: layout, camera: camera, size: size, labelOpacity: labelOpacity)
                }
            }
            .contentShape(Rectangle())
            .coordinateSpace(name: Self.canvasSpace)
            .simultaneousGesture(panGesture(camera: camera, size: size), including: studyFocusNodeID == nil ? .all : .none)
            // Always available for precision zooming, except in Study, which has its own pinch.
            .simultaneousGesture(zoomGesture(in: size), including: studyFocusNodeID == nil ? .all : .none)
            .simultaneousGesture(studyDragGesture(ring: studyRing, chips: studyChipTargets, nodeFrame: studyNodeTarget, size: size), including: studyReady ? .all : .none)
            .onChange(of: size, initial: true) { _, newSize in lastCanvasSize = newSize }
            .simultaneousGesture(studyPinchGesture, including: studyReady ? .all : .none)
            .onTapGesture {
                guard studyFocusNodeID == nil else { return }
                selectedEdgeID = nil
                cameraState.userMovedSincePlacement = true
            }
            .onChange(of: studyNodeID) { _, nodeID in
                if let nodeID {
                    beginStudy(of: nodeID)
                } else {
                    endStudy()
                }
            }
            .onChange(of: restoreFocusedCameraRequest) { oldValue, newValue in
                restorePreFocusCamera()
            }
            .onChange(of: focusedInsightID) { oldValue, newValue in
                guard let newValue,
                      let focusTarget = insightFocusTarget(for: newValue) else { return }

                focusHoveredTarget(
                    at: focusTarget,
                    elevation: insightElevation(forInsightID: newValue),
                    in: size
                )
            }
            .onChange(of: focusedSearchNodeID) { _, newValue in
                guard let newValue,
                      let focusTarget = simPosition(of: newValue) else { return }

                focusHoveredTarget(at: focusTarget, in: size)
            }
            .onAppear {
                hasAppeared = true
                reconcileBodies()   // seed live physics bodies + start the tick
                undiscoveredInsightIDs = loadUndiscoveredInsightIDs()
                undiscoveredNodeIDs = loadUndiscoveredNodeIDs()
                revealedNodeIDs = Set(nodes.map(\.id))
                revealedGraphEdgeIDs = Set(displayGraphEdges().map(\.id))
                observedLiveInsightIDs = visibleInsightIDs(in: nodes)
                observedLiveNodeIDs = Set(nodes.map(\.id))
                if defersEntranceUntilPersistedTree {
                    // Show the fallback tree without moving the camera or marking it as the
                    // persisted baseline. A completed backend load will do both.
                    revealedInsightIDs = visibleInsightIDs(in: nodes)
                    revealedInsightConnectorIDs = visibleInsightIDs(in: nodes)
                    revealedGraphEdgeIDs = Set(displayGraphEdges().map(\.id))
                    reportUndiscoveredInsightCount()
                } else {
                    let newInsights = computeNewInsights()
                    revealedInsightConnectorIDs.subtract(Set(newInsights.map(\.id)))
                    markUndiscovered(newInsights.map(\.id))   // new since last open → blue dot
                    reportUndiscoveredInsightCount()
                    saveAllInsightIDsAsSeen()
                    entranceTask = Task {
                        await runEntranceSequence(newInsights: newInsights, in: size)
                    }
                }
            }
            .onChange(of: persistedTreePresentationRevision) { _, revision in
                guard defersEntranceUntilPersistedTree, revision > 0 else { return }
                presentPersistedTree(
                    animated: animatedPersistedTreePresentationRevision == revision,
                    in: size
                )
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
            .onChange(of: physicsTopologySignature) { _, _ in
                // Only membership changes wake the layout. Content-only updates such as
                // generated labels and definitions leave the settled tree completely still.
                reconcileBodies()
                reportUndiscoveredInsightCount()
            }
            .onChange(of: layoutTargets) { _, _ in
                // New semantic targets (re-solve after a topology change): wake the sim so
                // the anchor springs glide nodes to their new positions.
                startSim(
                    intensity: Self.updateIntensity,
                    alphaDecay: Self.updateAlphaDecay,
                    frameBudget: 90
                )
            }
            .onChange(of: nodes) { _, newNodes in
                // Insights added after the initial entrance (Make Node children, placed midpoints):
                // they start as a flashing icon at the node center, splay out to their orbit
                // staggered by 0.15s each, then once "loaded" the title blurs up.
                guard hasAppeared else { return }
                let currentInsightIDs = visibleInsightIDs(in: newNodes)
                let currentNodeIDs = Set(newNodes.map(\.id))
                let addedLiveInsightIDs = currentInsightIDs.subtracting(observedLiveInsightIDs)
                let addedLiveNodeIDs = currentNodeIDs.subtracting(observedLiveNodeIDs)
                if !defersEntranceUntilPersistedTree {
                    observedLiveInsightIDs = currentInsightIDs
                    observedLiveNodeIDs = currentNodeIDs
                }
                let known = revealedInsightIDs.union(loadingInsightIDs)
                var newOnes: [(id: UUID, orbitIndex: Int)] = []
                var plainNewInsights: [InsightModel] = []
                var placedMidpointID: UUID? = nil
                for node in newNodes {
                    for (i, insight) in canvasInsights(for: node).enumerated()
                    where defersEntranceUntilPersistedTree
                        ? !known.contains(insight.id)
                        : addedLiveInsightIDs.contains(insight.id) {
                        if insight.id == midpointPlacedInsightID {
                            placedMidpointID = insight.id     // just-placed midpoint → simulated load + hover
                        } else if makeNodeChildIDs.contains(insight.id) {
                            newOnes.append((insight.id, i))   // Make Node child → loading mask + splay
                        } else {
                            plainNewInsights.append(insight)   // accepted Global Insights → camera tour + reveal
                        }
                    }
                }

                // Newly accepted Global Insights use the same staged camera/reveal sequence as
                // persisted tree updates. Waiting one layout beat lets their simulated positions
                // settle before the camera pans to them.
                if !plainNewInsights.isEmpty && !defersEntranceUntilPersistedTree {
                    entranceTask?.cancel()
                    let plainNewIDs = Set(plainNewInsights.map(\.id))
                    markUndiscovered(Array(plainNewIDs))
                    markNodesUndiscovered(Array(addedLiveNodeIDs))
                    reportUndiscoveredInsightCount()
                    entranceTask = Task {
                        await Task.yield()
                        try? await Task.sleep(for: .milliseconds(50))
                        guard !Task.isCancelled else { return }
                        await runPersistedUpdateSequence(
                            newInsights: plainNewInsights,
                            newNodeIDs: addedLiveNodeIDs,
                            in: size
                        )
                        guard !Task.isCancelled else { return }
                        saveAllInsightIDsAsSeen()
                    }
                } else if !addedLiveNodeIDs.isEmpty && !defersEntranceUntilPersistedTree {
                    // Make Node and other node-only additions own their Insight animation below,
                    // but their parent concept still needs to become visible immediately.
                    withAnimation(.easeOut(duration: 0.22)) {
                        revealedNodeIDs.formUnion(addedLiveNodeIDs)
                    }
                }

                // A freshly placed midpoint insight runs a generation sequence:
                //   1. hover/zoom on the hollow "Insight Loading Icon" while generating
                //   2. once complete, the hollow icon fades+blurs out while the solid icon+title
                //      cross-fade in (fade/transform/blur), AND a big shockwave radiates — together
                //   3. shortly after, the insight card pops up
                if let placedID = placedMidpointID {
                    beginMidpointLoading(placedID, in: size)
                }

                guard !newOnes.isEmpty else { return }
                beginMakeNodeLoading(newOnes, in: newNodes, size: size)
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
            .onChange(of: midpointGeneratedInsightID) { _, generatedID in
                guard let generatedID else { return }
                scheduleMidpointReveal(generatedID, in: size)
            }
            .onChange(of: generatedMakeNodeChildIDs) { _, _ in
                scheduleMakeNodeRevealIfReady(in: size)
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
            // A freshly placed Midpoint's own two source chips haven't been manually angled by
            // anyone yet — point both of them at it immediately so the new connector doesn't
            // start out crossing some other line by default.
            .onChange(of: placedMidpointSources) { _, newValue in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    for midpointID in newValue.keys {
                        reangleMidpointSources(of: midpointID)
                    }
                }
            }
            .onDisappear {
                entranceTask?.cancel()
                midpointRevealTask?.cancel()
                makeNodeRevealTask?.cancel()
                if !pendingMakeNodeChildren.isEmpty {
                    onGeneratingChange(false)
                }
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
                // An Insight chip's own press-and-hold rotate-drag (see `chipRotateDragGesture`)
                // is attached lower in the hierarchy as merely `.simultaneousGesture`, which does
                // NOT stop this root-level pan gesture from also recognizing the same touch once
                // it moves — so panning the whole canvas would otherwise hijack every chip drag.
                // The hold itself doesn't move enough to trip `minimumDistance: 2`, so this guard
                // only ever needs to catch the drag phase, which starts after `draggingChipID` is
                // already set.
                guard draggingChipID == nil else {
                    panGestureBlockedByChipDrag = true
                    return
                }
                // Lock the handle-vs-pan decision to the gesture's start so it can't
                // flip to panning as the handle moves away from the finger.
                guard !isHandleDragStart(value.startLocation, camera: camera, size: size) else { return }
                state = flatTranslation(value, camera: camera, size: size)
            }
            .onChanged { value in
                guard draggingChipID == nil else {
                    panGestureBlockedByChipDrag = true
                    return
                }
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
                    cameraState.userMovedSincePlacement = true
                    onCanvasMoved()
                }
            }
            .onEnded { value in
                let wasHandleDrag = isHandleDragStart(value.startLocation, camera: camera, size: size)
                dragStartHandleWorld = nil
                lastHandleHapticPercent = nil
                guard !wasHandleDrag else { return }
                guard !panGestureBlockedByChipDrag else {
                    panGestureBlockedByChipDrag = false
                    return
                }
                let translation = flatTranslation(value, camera: camera, size: size)
                cameraState.offset.width += translation.width
                cameraState.offset.height += translation.height

                if hypot(value.translation.width, value.translation.height) > 8 {
                    cameraState.lastDragEndedAt = Date()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    cameraState.isDragging = false
                }
            }
    }

    /// A screen drag converted to the flat pan offset that keeps the grabbed point of the
    /// perspective plane under the finger. Independent of the current offset.
    private func flatTranslation(_ value: DragGesture.Value, camera: InsightTreeCamera, size: CGSize) -> CGSize {
        let projection = camera.projection(in: size)
        let start = projection.unproject(value.startLocation)
        let current = projection.unproject(value.location)
        return CGSize(width: current.x - start.x, height: current.y - start.y)
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

    /// Press-and-hold an Insight chip, then drag it anywhere — the connector line stretches to
    /// follow (see `insightWorldPosition`'s `draggingChipID` check). On release the bond length
    /// eases back to what it was before (relatedness to the parent Node is unchanged), but the
    /// angle you dragged to sticks. Any placed Midpoint this chip is a source of gets its other
    /// source re-aimed at the same time, so the two ends of that connection keep facing each
    /// other instead of drifting back into a crossing line.
    private func chipRotateDragGesture(
        insight: InsightModel,
        node: NodeModel,
        index: Int,
        count: Int,
        isPinnedAtNode: Bool,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                if draggingChipID == insight.id {
                    // Unproject at the chip's own elevation so the chip stays exactly under the finger.
                    draggingChipWorldPosition = isPinnedAtNode
                        ? camera.screenToWorld(value.location, in: size)
                        : draggedChipFootprint(under: value.location, insight: insight, node: node, camera: camera, size: size)
                    // Top up the frame budget every move so a long drag never lets the sim
                    // expire mid-gesture — but WITHOUT re-boosting `alpha` (startSim's own
                    // `max(alpha, intensity)` would do that on every single move event). Alpha
                    // scales both the repulsion force and its random per-frame jitter term, so
                    // continuously re-flooring it near the drag's initial intensity kept the
                    // whole layout visibly trembling for as long as the drag lasted; letting it
                    // decay on its own settles the jitter while collision avoidance stays live.
                    simFramesRemaining = max(simFramesRemaining, Self.settleFrameBudget)
                    return
                }
                guard draggingChipID == nil else { return }   // some other chip owns the drag
                chipPressLastLocation = value.location
                guard chipPressCandidateID != insight.id else { return }   // timer already armed
                chipPressCandidateID = insight.id
                chipPressStartLocation = value.location
                chipPressLastLocation = value.location
                let capturedID = insight.id
                // A placed Midpoint's chip sits ON its node — nothing to orbit, so its "start"
                // is just its own current position, and dragging repositions it freely instead
                // of picking a new angle.
                let startWorld = isPinnedAtNode ? node.position : insightWorldPosition(for: node, index: index, count: count)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    guard chipPressCandidateID == capturedID, draggingChipID == nil else { return }
                    // Cancelled if the finger drifted too far during the hold — that's a pan,
                    // not a rotate-drag, and the root pan gesture is already handling it.
                    if let start = chipPressStartLocation, let last = chipPressLastLocation,
                       hypot(last.x - start.x, last.y - start.y) > 14 {
                        chipPressCandidateID = nil
                        return
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        draggingChipID = capturedID
                        draggingChipWorldPosition = startWorld
                        draggingChipStartWorldPosition = startWorld
                    }
                    // Keep the sim actively stepping for the whole drag — nearby chips/nodes
                    // need live collision forces reacting every frame to make room, not just a
                    // one-shot settle once the finger lifts. A modest starting intensity (rather
                    // than a full topology-change jolt) keeps that initial nudge from reading as
                    // a jitter itself.
                    startSim(intensity: 0.22, alphaDecay: Self.updateAlphaDecay, frameBudget: Self.settleFrameBudget)
                }
            }
            .onEnded { value in
                let wasDragging = draggingChipID == insight.id
                if chipPressCandidateID == insight.id {
                    chipPressCandidateID = nil
                }
                guard wasDragging else { return }   // released before the hold armed: a plain tap
                // Commit whatever position the drag settled at (either this Midpoint's own free
                // reposition, or a followed Midpoint's drift — see `stepSimulation`'s pinned-body
                // loop) into the view model BEFORE clearing the drag state below — otherwise the
                // very next simulation tick's "pinned bodies track their authoritative
                // view-model position" sync would read the OLD, uncommitted position and snap
                // straight back.
                persistLivePositions()
                if isPinnedAtNode {
                    // Free reposition: wherever it was dropped IS the new position — no angle or
                    // bond length to compute (there's no orbit to compute them around).
                    withAnimation(.spring(response: 0.75, dampingFraction: 0.8)) {
                        draggingChipID = nil
                        draggingChipWorldPosition = nil
                        draggingChipStartWorldPosition = nil
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                    return
                }
                // Unproject at the chip's elevation: the drop point is its footprint on the plane,
                // so raised or lowered chips keep the angle they were released at.
                let releasePoint = draggedChipFootprint(
                    under: value.location, insight: insight, node: node, camera: camera, size: size
                )
                let finalAngle = Double(atan2(
                    releasePoint.y - node.position.y,
                    releasePoint.x - node.position.x
                ))
                withAnimation(.spring(response: 0.75, dampingFraction: 0.8)) {
                    chipAngles[insight.id] = ChipAngle(angle: finalAngle)
                    pinnedChipAngleIDs.insert(insight.id)
                    draggingChipID = nil
                    draggingChipWorldPosition = nil
                    draggingChipStartWorldPosition = nil
                    for midpointID in midpointIDs(sourcedBy: insight.id) {
                        reangleMidpointSources(of: midpointID, excluding: insight.id)
                    }
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }
    }

    private func zoomGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if cameraState.pinchStartScale == nil {
                    cameraState.pinchStartScale = cameraState.scale
                    cameraState.pinchStartOffset = cameraState.offset
                    cameraState.userMovedSincePlacement = true
                    onCanvasMoved()
                }

                let initialScale = cameraState.pinchStartScale ?? cameraState.scale
                let initialOffset = cameraState.pinchStartOffset ?? cameraState.offset
                let nextScale = clamp(initialScale * pow(value.magnification, 0.72), lower: 0.28, upper: 2.6)
                let anchor = InsightTreeCamera(scale: initialScale, offset: initialOffset)
                    .projection(in: size)
                    .unproject(CGPoint(
                        x: value.startAnchor.x * size.width,
                        y: value.startAnchor.y * size.height
                    ))

                cameraState.scale = nextScale
                cameraState.offset = offsetKeeping(anchor, fixedFrom: initialOffset, initialScale: initialScale, nextScale: nextScale, in: size)
            }
            .onEnded { value in
                let initialScale = cameraState.pinchStartScale ?? cameraState.scale
                let initialOffset = cameraState.pinchStartOffset ?? cameraState.offset
                let nextScale = clamp(initialScale * pow(value.magnification, 0.72), lower: 0.28, upper: 2.6)
                let anchor = InsightTreeCamera(scale: initialScale, offset: initialOffset)
                    .projection(in: size)
                    .unproject(CGPoint(
                        x: value.startAnchor.x * size.width,
                        y: value.startAnchor.y * size.height
                    ))

                cameraState.scale = nextScale
                cameraState.offset = offsetKeeping(anchor, fixedFrom: initialOffset, initialScale: initialScale, nextScale: nextScale, in: size)
                cameraState.pinchStartScale = nil
                cameraState.pinchStartOffset = nil
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
        !cameraState.isDragging && Date().timeIntervalSince(cameraState.lastDragEndedAt) > 0.16
    }

    /// Pans (and, if `targetScale` is supplied, simultaneously zooms) to center `worldPosition`
    /// — a single spring rather than two sequential ones when both need to change together.
    private func focusInsight(at worldPosition: CGPoint, in size: CGSize, targetScale: CGFloat? = nil) {
        rememberCameraBeforeFocusIfNeeded()
        let nextScale = targetScale ?? cameraState.scale
        let target = focusFlatTarget(elevation: 0, scale: nextScale, in: size)

        withAnimation(.spring(response: 0.58, dampingFraction: 0.64, blendDuration: 0.08)) {
            cameraState.scale = nextScale
            cameraState.offset = CGSize(
                width: target.x - size.width / 2 - (worldPosition.x * nextScale),
                height: target.y - size.height / 2 + (worldPosition.y * nextScale)
            )
        }
    }

    /// Centers a hovered target on screen. An Insight passes its elevation so the chip itself —
    /// not its footprint on the plane — lands under the selection reticle.
    /// Returns the zoom scale the camera is animating to.
    @discardableResult
    private func focusHoveredTarget(at worldPosition: CGPoint, elevation: CGFloat = 0, in size: CGSize) -> CGFloat {
        rememberCameraBeforeFocusIfNeeded()
        let nextScale = clamp(max(cameraState.scale, 1.15), lower: 0.28, upper: 2.6)
        let target = focusFlatTarget(elevation: elevation, scale: nextScale, in: size)

        withAnimation(.spring(response: 0.58, dampingFraction: 0.64, blendDuration: 0.08)) {
            cameraState.scale = nextScale
            cameraState.offset = CGSize(
                width: target.x - size.width / 2 - (worldPosition.x * nextScale),
                height: target.y - size.height / 2 + (worldPosition.y * nextScale)
            )
        }
        return nextScale
    }

    /// The flat (pre-perspective) point a target must occupy to project onto the focus anchor.
    private func focusFlatTarget(elevation: CGFloat, scale: CGFloat, in size: CGSize) -> CGPoint {
        InsightTreeCamera(scale: scale, offset: .zero)
            .flatPointCentering(elevation: elevation, in: size)
    }

    private func rememberCameraBeforeFocusIfNeeded() {
        guard cameraState.preFocusSnapshot == nil else { return }

        cameraState.preFocusSnapshot = InsightTreeCameraSnapshot(
            scale: cameraState.scale,
            offset: cameraState.offset
        )
    }

    private func restorePreFocusCamera() {
        guard let snapshot = cameraState.preFocusSnapshot else { return }

        withAnimation(.spring(response: 0.58, dampingFraction: 0.64, blendDuration: 0.08)) {
            cameraState.scale = snapshot.scale
            cameraState.offset = snapshot.offset
        }

        cameraState.preFocusSnapshot = nil
    }

    @discardableResult
    private func markCanvasDragIfNeeded(_ translation: CGSize) -> Bool {
        guard hypot(translation.width, translation.height) > 8 else { return false }
        guard !cameraState.isDragging else { return false }
        cameraState.isDragging = true
        return true
    }

    @ViewBuilder
    private func graphEdges(camera: InsightTreeCamera, size: CGSize) -> some View {
        let hasSelection = !selectedCanvasTargets.isEmpty
        ForEach(displayGraphEdges()) { edge in
            if revealedGraphEdgeIDs.contains(edge.id),
               let from = simPosition(of: edge.fromNodeID),
               let to = simPosition(of: edge.toNodeID) {
                let start = camera.worldToScreen(from, in: size)
                let end = camera.worldToScreen(to, in: size)

                Group {
                    if animatedGraphEdgeIDs.contains(edge.id) {
                        InsightConnectorLine(
                            start: start,
                            end: end,
                            color: AquinasTheme.Colors.divider.opacity(edge.isSuggested ? 0.55 : 0.9)
                        )
                    } else {
                        AnimatableLine(start: start, end: end)
                            .stroke(
                                AquinasTheme.Colors.divider.opacity(edge.isSuggested ? 0.55 : 0.9),
                                style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: edge.isSuggested ? [6, 4] : [])
                            )
                    }
                }
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

    /// Screen endpoint for a midpoint's source. Insight sources end exactly where their chip is
    /// drawn (including local elevation and perspective); node sources use the node's depth.
    private func midpointSourceScreenPosition(
        _ source: MidpointSource,
        layout: CanvasInsightLayout,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> CGPoint? {
        if !source.isNode, let placement = layout.placements[source.insightID] {
            return insightScreenPosition(placement, camera: camera, size: size)
        }
        guard let sourceWorld = midpointSourceEndpoint(source) else { return nil }
        return camera.worldToScreen(sourceWorld, in: size)
    }

    /// Lines from each placed midpoint to the insight chips / node concepts it was spawned from.
    @ViewBuilder
    private func midpointConnectors(layout: CanvasInsightLayout, camera: InsightTreeCamera, size: CGSize) -> some View {
        let hasSelection = !selectedCanvasTargets.isEmpty
        ForEach(Array(placedMidpointNodeIDs), id: \.self) { placedID in
            if let placedWorld = simPosition(of: placedID), let sources = placedMidpointSources[placedID] {
                let end = camera.worldToScreen(placedWorld, in: size)
                ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                    if let start = midpointSourceScreenPosition(source, layout: layout, camera: camera, size: size) {
                        AnimatableLine(start: start, end: end)
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
    private func insightConnectors(layout: CanvasInsightLayout, camera: InsightTreeCamera, size: CGSize) -> some View {
        let hasSelection = !selectedCanvasTargets.isEmpty
        // Placed-midpoint chips sit on the node itself, so they have no orbit connectors.
        let connectorNodes = layout.nodes.filter { !placedMidpointNodeIDs.contains($0.id) }
        ForEach(connectorNodes, id: \.id) { node in
            let visibleInsights = layout.insightsByNode[node.id] ?? []
            ForEach(visibleInsights) { insight in
                if revealedInsightConnectorIDs.contains(insight.id),
                   let placement = layout.placements[insight.id] {
                    let start = camera.worldToScreen(node.position, in: size)
                    let end = insightScreenPosition(placement, camera: camera, size: size)
                    // Connector lines stay at a constant opacity regardless of zoom — only the
                    // chip label/background fade with `labelOpacity`, not the lines themselves.
                    let baseOpacity = 0.55

                    InsightConnectorLine(
                        start: start,
                        end: end,
                        color: AquinasTheme.Colors.divider.opacity(
                            baseOpacity * (hasSelection ? 0.5 : 1.0) * studyOpacity(forNodeID: node.id)
                        )
                    )
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.22), value: hasSelection)

                }
            }
        }
    }

    private struct ConnectorPulseEndpoints: Identifiable {
        let id: String
        let start: CGPoint
        let end: CGPoint
        let lineWidth: CGFloat
    }

    /// Screen endpoints of every connector that should pulse, resolved once per render from the
    /// same placements the chips and connectors use. Empty when nothing is hovered, so the
    /// per-frame timeline below draws nothing and scans nothing.
    private func connectorPulseEndpoints(
        layout: CanvasInsightLayout,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> [ConnectorPulseEndpoints] {
        guard pulsingInsightID != nil || pulsingNodeID != nil else { return [] }
        var lines: [ConnectorPulseEndpoints] = []

        let sourceNodeID = pulsingNodeID ?? pulsingInsightNodeID()
        if let sourceNodeID, let sourcePos = simPosition(of: sourceNodeID) {
            let start = camera.worldToScreen(sourcePos, in: size)
            for edge in displayGraphEdges()
            where edge.fromNodeID == sourceNodeID || edge.toNodeID == sourceNodeID {
                let targetNodeID = edge.fromNodeID == sourceNodeID ? edge.toNodeID : edge.fromNodeID
                guard let targetPos = simPosition(of: targetNodeID) else { continue }
                lines.append(ConnectorPulseEndpoints(
                    id: "edge-\(edge.id)",
                    start: start,
                    end: camera.worldToScreen(targetPos, in: size),
                    lineWidth: 2.2
                ))
            }
        }

        for node in layout.nodes {
            let visibleInsights = layout.insightsByNode[node.id] ?? []
            let pulsed: [InsightModel]
            let lineWidth: CGFloat
            if let pulsingInsightID, let insight = visibleInsights.first(where: { $0.id == pulsingInsightID }) {
                pulsed = [insight]
                lineWidth = 2.2
            } else if pulsingNodeID == node.id {
                pulsed = visibleInsights
                lineWidth = 1.8
            } else {
                continue
            }
            let nodePosition = camera.worldToScreen(node.position, in: size)
            for insight in pulsed {
                guard let placement = layout.placements[insight.id] else { continue }
                lines.append(ConnectorPulseEndpoints(
                    id: "insight-\(insight.id.uuidString)",
                    start: insightScreenPosition(placement, camera: camera, size: size),
                    end: nodePosition,
                    lineWidth: lineWidth
                ))
            }
        }
        return lines
    }

    @ViewBuilder
    private func connectorPulseOverlay(layout: CanvasInsightLayout, camera: InsightTreeCamera, size: CGSize) -> some View {
        let lines = connectorPulseEndpoints(layout: layout, camera: camera, size: size)
        // Paused while idle: an always-running `.animation` timeline re-evaluated this overlay
        // every display frame even when no connector was pulsing.
        TimelineView(.animation(minimumInterval: nil, paused: lines.isEmpty)) { timeline in
            let pulseProgress = connectorPulseProgress(at: timeline.date)

            ZStack {
                ForEach(lines) { line in
                    travelingPulseLine(start: line.start, end: line.end, progress: pulseProgress, lineWidth: line.lineWidth)
                        .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func selectionOverlay(layout: CanvasInsightLayout, camera: InsightTreeCamera, size: CGSize) -> some View {
        // Selection lines end where each target is drawn, including an Insight's elevation and
        // perspective, rather than at its bare world point.
        let screenPosition = { (target: CanvasSelectionTarget) in
            selectionScreenPosition(for: target, layout: layout, camera: camera, size: size)
        }
        if !isMidpointMode,
           let activeTarget = selectedCanvasTargets.last,
           let activePosition = screenPosition(activeTarget) {
            let center = focusAnchor(in: size)

            ZStack {
                ForEach(Array(selectedCanvasTargets.indices.dropFirst()), id: \.self) { index in
                    if let previousPosition = screenPosition(selectedCanvasTargets[index - 1]),
                       let currentPosition = screenPosition(selectedCanvasTargets[index]) {
                        AnimatableLine(start: previousPosition, end: currentPosition)
                        .stroke(
                            AquinasTheme.Colors.lightGreen.opacity(0.8),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                        .frame(width: size.width, height: size.height)
                    }
                }

                AnimatableLine(start: activePosition, end: center)
                    .stroke(
                        AquinasTheme.Colors.lightGreen.opacity(0.8),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .frame(width: size.width, height: size.height)

                SelectionReticle()
                    .position(center)

                if let selectionPulseStartTime,
                   selectedCanvasTargets.count > 1,
                   let previousTarget = selectedCanvasTargets.dropLast().last,
                   let previousPosition = screenPosition(previousTarget) {
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
                            if let previousPosition = screenPosition(selectedCanvasTargets[index - 1]),
                               let currentPosition = screenPosition(selectedCanvasTargets[index]),
                               segEnd > segStart {
                                pulseSegment(
                                    start: previousPosition,
                                    end: currentPosition,
                                    from: segStart, to: segEnd,
                                    lineWidth: 4,
                                    color: AquinasTheme.Colors.lightGreen,
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
                                color: AquinasTheme.Colors.lightGreen,
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

    /// Node targets keep their existing unshifted camera position; Insight targets use the
    /// position their chip is actually drawn at.
    private func selectionScreenPosition(
        for target: CanvasSelectionTarget,
        layout: CanvasInsightLayout,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> CGPoint? {
        if case .insight(let insightID) = target, let placement = layout.placements[insightID] {
            return insightScreenPosition(placement, camera: camera, size: size)
        }
        return worldPosition(for: target).map { camera.worldToScreen($0, in: size) }
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

    /// Installs the three stable loading children, frames their promoted Node Concept, and splays
    /// them into place. Their text remains hidden until the model publishes all three as ready.
    private func beginMakeNodeLoading(
        _ children: [(id: UUID, orbitIndex: Int)],
        in newNodes: [NodeModel],
        size: CGSize
    ) {
        guard pendingMakeNodeChildren.isEmpty else { return }
        let pending = children
            .sorted { $0.orbitIndex < $1.orbitIndex }
            .map {
                PendingMakeNodeChild(id: $0.id, orbitIndex: $0.orbitIndex)
            }
        pendingMakeNodeChildren = pending
        makeNodeLoadingStartedAt = Date().timeIntervalSinceReferenceDate

        for child in pending {
            loadingInsightIDs.insert(child.id)
            unsplayedInsightIDs.insert(child.id)
        }
        onGeneratingChange(true)
        markUndiscovered(pending.map(\.id))

        // Frame the promoted Node Concept and all three loading children before touring them.
        onRequestDismissHover()
        let generatedNodeIDs = Set(pending.compactMap { child in
            newNodes.first(where: {
                $0.insights.contains { $0.id == child.id }
            })?.id
        })
        let generatedNodePositions = generatedNodeIDs.compactMap { simPosition(of: $0) }
        let framePositions = generatedNodePositions
            + pending.compactMap { worldPosition(forInsightID: $0.id) }
        if !framePositions.isEmpty {
            zoomToFit(
                worldPositions: framePositions,
                in: size,
                padding: 90,
                fitFactor: 1.0,
                center: generatedNodePositions.count == 1
                    ? generatedNodePositions.first
                    : nil
            )
        }

        for child in pending {
            let delay = Double(child.orbitIndex) * 0.15
            Task {
                try? await Task.sleep(for: .seconds(delay))
                await MainActor.run {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        _ = unsplayedInsightIDs.remove(child.id)
                    }
                }
            }
        }

        // Covers the fast-response race where generation and the node rebuild arrive in one
        // SwiftUI update; the readiness onChange path covers the normal slower response.
        scheduleMakeNodeRevealIfReady(in: size)
    }

    /// Starts the existing three-stop camera tour only when all child titles and definitions have
    /// replaced their loading content. The former 3.5-second simulated dwell remains a minimum.
    private func scheduleMakeNodeRevealIfReady(in size: CGSize) {
        guard !pendingMakeNodeChildren.isEmpty, makeNodeRevealTask == nil else { return }
        let childIDs = Set(pendingMakeNodeChildren.map(\.id))
        guard childIDs.isSubset(of: generatedMakeNodeChildIDs) else { return }

        let children = pendingMakeNodeChildren
        let startedAt = makeNodeLoadingStartedAt
            ?? Date().timeIntervalSinceReferenceDate
        let elapsed = Date().timeIntervalSinceReferenceDate - startedAt
        let remainingDelay = max(3.5 - elapsed, 0)

        makeNodeRevealTask = Task {
            try? await Task.sleep(for: .seconds(remainingDelay))
            guard !Task.isCancelled else { return }
            for (index, child) in children.enumerated() {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let position = worldPosition(forInsightID: child.id) {
                        // The first stop restores the default zoom while panning; later stops
                        // retain it, matching the existing Make Node choreography.
                        focusInsight(
                            at: position,
                            in: size,
                            targetScale: index == 0 ? 1 : nil
                        )
                    }
                }
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let position = worldPosition(forInsightID: child.id) {
                        rippleTrigger = RippleTrigger(
                            worldOrigin: position,
                            startTime: Date().timeIntervalSinceReferenceDate,
                            strength: 2.8,
                            radiusScale: 0.5
                        )
                    }
                    playGeneratedHaptics()
                    onMakeNodeChildRevealed(child.id)
                    withAnimation(.easeOut(duration: 0.32)) {
                        loadingInsightIDs.remove(child.id)
                        revealedInsightIDs.insert(child.id)
                    }
                }
                try? await Task.sleep(for: .milliseconds(700))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                pendingMakeNodeChildren = []
                makeNodeLoadingStartedAt = nil
                makeNodeRevealTask = nil
                onGeneratingChange(false)
            }
        }
    }

    /// Starts the existing loading presentation as soon as the placed identity enters the tree.
    /// Generation completion is signaled separately, so a slow model never reveals blank text.
    private func beginMidpointLoading(_ insightID: UUID, in size: CGSize) {
        guard midpointLoadingStartedAt[insightID] == nil else { return }
        midpointLoadingStartedAt[insightID] = Date().timeIntervalSinceReferenceDate
        loadingInsightIDs.insert(insightID)
        cameraState.userMovedSincePlacement = false
        markUndiscovered([insightID])
        if let position = worldPosition(forInsightID: insightID) {
            focusHoveredTarget(at: position, in: size)
        }
    }

    /// Preserves the existing 3.5-second minimum loading animation but waits longer when real
    /// generation takes longer. The generated title and definition are already in `nodes`.
    private func scheduleMidpointReveal(_ insightID: UUID, in size: CGSize) {
        beginMidpointLoading(insightID, in: size)
        let startedAt = midpointLoadingStartedAt[insightID]
            ?? Date().timeIntervalSinceReferenceDate
        let elapsed = Date().timeIntervalSinceReferenceDate - startedAt
        let remainingDelay = max(3.5 - elapsed, 0)

        midpointRevealTask?.cancel()
        midpointRevealTask = Task {
            try? await Task.sleep(for: .seconds(remainingDelay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let position = worldPosition(forInsightID: insightID) {
                    if !cameraState.userMovedSincePlacement {
                        focusHoveredTarget(at: position, in: size)
                    }
                    rippleTrigger = RippleTrigger(
                        worldOrigin: position,
                        startTime: Date().timeIntervalSinceReferenceDate,
                        strength: 2.8,
                        radiusScale: 0.5
                    )
                    playGeneratedHaptics()
                }
                withAnimation(.easeOut(duration: 0.32)) {
                    loadingInsightIDs.remove(insightID)
                    revealedInsightIDs.insert(insightID)
                }
                midpointLoadingStartedAt[insightID] = nil
            }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            await MainActor.run { onMidpointInsightLoaded(insightID) }
        }
    }

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
    /// Two targets interpolate along their segment. For larger selections, the geometric
    /// centroid is defined as the exact equal-weight position; moving away from it uses
    /// normalized inverse-distance weights.
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

        let center = positions.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }
        let centroid = CGPoint(
            x: center.x / CGFloat(positions.count),
            y: center.y / CGFloat(positions.count)
        )
        let selectionScale = positions.reduce(CGFloat.zero) {
            max($0, hypot($1.x - centroid.x, $1.y - centroid.y))
        }
        let centerTolerance = max(selectionScale * 0.000_001, 0.000_1)
        if hypot(handle.x - centroid.x, handle.y - centroid.y) <= centerTolerance {
            return positions.map { _ in 1.0 / Double(positions.count) }
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
            let boundary = convexHull(of: positions)
            if boundary.count == 2 {
                return closestPointOnSegment(point, boundary[0], boundary[1])
            }
            return pointInPolygon(point, boundary) ? point : closestPointOnPolygon(point, boundary)
        }
        return point
    }

    /// Returns the selection's convex boundary in winding order. Selection order reflects tap
    /// order, so using it directly can create a self-intersecting polygon that incorrectly
    /// pushes the true centroid outside the draggable region.
    private func convexHull(of points: [CGPoint]) -> [CGPoint] {
        let sorted = points
            .sorted { lhs, rhs in
                lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
            }
            .reduce(into: [CGPoint]()) { unique, point in
                if unique.last != point { unique.append(point) }
            }
        guard sorted.count > 2 else { return sorted }

        func cross(_ origin: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - origin.x) * (b.y - origin.y)
                - (a.y - origin.y) * (b.x - origin.x)
        }

        var lower: [CGPoint] = []
        for point in sorted {
            while lower.count >= 2,
                  cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [CGPoint] = []
        for point in sorted.reversed() {
            while upper.count >= 2,
                  cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        lower.removeLast()
        upper.removeLast()
        return lower + upper
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
    private func midpointOverlay(layout: CanvasInsightLayout, camera: InsightTreeCamera, size: CGSize, labelOpacity: Double) -> some View {
        let positions = selectedWorldPositions()
        let boundaryPositions = positions.count >= 3 ? convexHull(of: positions) : positions
        let screenPts = boundaryPositions.map { camera.worldToScreen($0, in: size) }

        ZStack {
            // Connecting region: filled polygon for 3+, single segment for 2.
            // PolygonShape is animatable so it follows the camera's zoom-out spring.
            if screenPts.count >= 3 {
                PolygonShape(points: screenPts)
                    .fill(AquinasTheme.Colors.lightGreen.opacity(0.25))
                    .allowsHitTesting(false)

                PolygonShape(points: screenPts)
                    .stroke(AquinasTheme.Colors.lightGreen.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .allowsHitTesting(false)
            } else if screenPts.count == 2 {
                AnimatableLine(start: screenPts[0], end: screenPts[1])
                    .stroke(AquinasTheme.Colors.lightGreen.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }

            // Re-draw the selected items at full opacity so they "pop" above the dimmed canvas.
            ForEach(Array(selectedCanvasTargets.enumerated()), id: \.offset) { _, target in
                midpointSelectedItem(target, layout: layout, camera: camera, size: size, labelOpacity: labelOpacity)
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
        layout: CanvasInsightLayout,
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
            if let placement = layout.placements[id],
               let node = layout.nodes.first(where: { $0.id == placement.nodeID }) {
                insightLabel(placement, node: node, camera: camera, size: size, labelOpacity: 1)
            }
        }
    }

    @ViewBuilder
    private func edgeHitTargets(camera: InsightTreeCamera, size: CGSize) -> some View {
        ForEach(edges) { edge in
            if edge.showSuggestButton,
               let from = simPosition(of: edge.fromNodeID),
               let to = simPosition(of: edge.toNodeID) {
                // Midpoint of the depth-parallaxed endpoints, so the button tracks the line.
                let fromScreen = camera.worldToScreen(from, in: size)
                let toScreen = camera.worldToScreen(to, in: size)
                let position = CGPoint(
                    x: (fromScreen.x + toScreen.x) / 2,
                    y: (fromScreen.y + toScreen.y) / 2
                )

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
        let projection = camera.project(node.position, in: size)
        let position = projection.position

        ZStack(alignment: .topTrailing) {
            VStack(spacing: 18) {
                // Shares the label's own blur+animation treatment (instead of relying only on
                // the outer ZStack's transition) so the icon and label always move together —
                // previously the icon had no entrance treatment of its own and stayed static
                // while the label blurred/faded in.
                Image(systemName: node.isSuggested ? "sparkles" : "brain.head.profile")
                    .font(.system(size: node.isSuggested ? 20 : 24, weight: .semibold))
                    .foregroundStyle(AquinasTheme.Colors.lightGreen)
                    .blur(radius: hasAppeared ? 0 : 8)
                    .animation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1), value: hasAppeared)

                Text(node.conceptLabel)
                    .font(.custom("Figtree-Bold", size: 18))
                    .lineSpacing(8)
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
            .overlay(alignment: .topLeading) {
                if undiscoveredNodeIDs.contains(node.id) {
                    Circle()
                        .fill(Color(red: 0.25, green: 0.55, blue: 1.0))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(insightTreeCanvasColor, lineWidth: 1.5))
                        .offset(x: 4, y: 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard canAcceptTap else { return }
                markNodeDiscovered(node.id)
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
        .transition(.glideFadeUp)
        // 2.5D depth: farther nodes render smaller, dimmer, and behind nearer ones.
        .scaleEffect(depthScale(node.id) * projection.scale)
        // While rotate-dragging a chip, every Node recedes so the dragged chip alone stands out.
        // No `.animation(_, value:)` here — see the matching note in `insightLabel`; a placed
        // Midpoint's `.position()` below needs to ride whatever ambient animation is active
        // (its live drag-follow), not get locked to a spring keyed only to `draggingChipID`.
        .opacity(depthOpacity(node.id) * chipDragDimFactor)
        .position(position)
        .zIndex((node.isSuggested ? 20 : 10) + Double(depthFactor(node.id)) * 5)
    }

    /// Dims every Node and every non-dragged Insight chip to half opacity while a chip
    /// rotate-drag is active, so the one chip under the finger reads unambiguously.
    private var chipDragDimFactor: Double {
        draggingChipID == nil ? 1.0 : 0.5
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
        _ placement: InsightPlacement,
        node: NodeModel,
        camera: InsightTreeCamera,
        size: CGSize,
        labelOpacity: Double
    ) -> some View {
        let insight = placement.insight
        let index = placement.index
        let count = placement.count
        // Placed-midpoint insights are pinned at the node position itself (no orbit).
        let isPinnedAtNode = placement.isPinnedAtNode
        let worldPosition = placement.world
        let isRevealed    = revealedInsightIDs.contains(insight.id)
        let isLoading     = loadingInsightIDs.contains(insight.id)
        let isSelected    = selectedCanvasTargets.contains(.insight(insight.id))
        // Pinned (placed-midpoint) chips stay visible from the moment they appear — even in
        // the brief gap between the icon turning solid and the title blurring in.
        let isVisible     = isRevealed || isLoading || isPinnedAtNode
        // While unsplayed, render at the node center so the child appears to splay out from it.
        let atCenter      = unsplayedInsightIDs.contains(insight.id)
        let projection    = atCenter
            ? camera.project(node.position, in: size)
            : insightProjection(placement, camera: camera, size: size)
        let position      = projection.position
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
            focusHoveredTarget(at: worldPosition, elevation: placement.elevation, in: size)
            onInsightTapped(insight)
        }
        .simultaneousGesture(
            chipRotateDragGesture(
                insight: insight,
                node: node,
                index: index,
                count: count,
                isPinnedAtNode: isPinnedAtNode,
                camera: camera,
                size: size
            ),
            isEnabled: canAcceptTap
        )
        .offset(y: isVisible ? 0 : 24)
        .opacity(isVisible ? 1 : 0)
        .blur(radius: isVisible ? 0 : 8)
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: isVisible)
        .transition(.scale(scale: 0.88, anchor: .center).combined(with: .opacity))
        // 2.5D depth: each chip combines its Node Concept's semantic depth with its own
        // bounded local elevation, so a cluster reads as a shallow spatial volume.
        // While rotate-dragging, the dragged chip grows 5% and stays full opacity; every other
        // chip dims along with the Nodes (see `chipDragDimFactor`).
        // No `.animation(_, value:)` here: that resets the animation context for every modifier
        // after it — including `.position()` below — to ONLY animate on `draggingChipID`
        // changes, using its own spring. That decoupled the chip from `AnimatableLine`'s
        // connector, which has no such override and just rides whatever ambient `withAnimation`
        // is active — so the line eased back on release while the chip itself snapped instantly.
        // Wrapping the state mutations in `chipRotateDragGesture` in `withAnimation` covers scale,
        // opacity, AND position uniformly, the same way it already covers the connector line.
        // Node Concept depth times true perspective magnification at the chip's elevation.
        .scaleEffect(depthScale(node.id) * chipScale(nodeID: node.id, magnification: projection.scale) * (draggingChipID == insight.id ? 1.05 : 1.0))
        .opacity(insightDepthOpacity(placement) * (draggingChipID == insight.id ? 1.0 : chipDragDimFactor))
        .opacity(studyOpacity(forNodeID: node.id) * (1 - 0.4 * studyProgress * studyDepthDim(placement, camera: camera)))
        // A hovered Insight in Study always draws in front; it never dims (see `studyDepthDim`).
        .position(position)
        // Nearer the camera draws on top, whether nearer by elevation or by plane position.
        // In Study, Insights behind the Node Concept draw behind it.
        .zIndex(
            studyDepthDim(placement, camera: camera) > 0.5 && insight.id != studyPivotID
                ? 5 + Double(projection.scale)
                : 30 + Double(projection.scale) * 5 + (draggingChipID == insight.id ? 100 : 0)
        )
    }

    private func insightFocusTarget(for insightID: UUID) -> CGPoint? {
        for node in displayNodes {
            if placedMidpointNodeIDs.contains(node.id), node.insights.contains(where: { $0.id == insightID }) {
                return node.position   // pinned chip sits on the node itself
            }
            let visibleInsights = canvasInsights(for: node)
            if let index = visibleInsights.firstIndex(where: { $0.id == insightID }) {
                return insightWorldPosition(for: node, index: index, count: visibleInsights.count)
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

    /// Midpoint of the largest unoccupied arc. New Insight bonds use this instead of an
    /// index-based angle so additions preserve the widest possible bond angles around a node.
    private func maximizedChipGapAngle(among angles: [Double]) -> Double {
        guard !angles.isEmpty else { return .pi / 8 }
        let fullTurn = Double.pi * 2
        let sorted = angles.map { angle in
            var normalized = angle.truncatingRemainder(dividingBy: fullTurn)
            if normalized < 0 { normalized += fullTurn }
            return normalized
        }.sorted()

        var largestGap = -Double.infinity
        var largestGapStart = sorted[0]
        for index in sorted.indices {
            let start = sorted[index]
            let end = index + 1 < sorted.count ? sorted[index + 1] : sorted[0] + fullTurn
            let gap = end - start
            if gap > largestGap {
                largestGap = gap
                largestGapStart = start
            }
        }
        return (largestGapStart + largestGap / 2).truncatingRemainder(dividingBy: fullTurn)
    }

    /// Directions of every visible node-to-node line connected to `nodeID`. These fixed bonds
    /// participate in the same angular domain as the Node Concept's Insight bonds.
    private func connectedNodeBondAngles(for nodeID: UUID) -> [Double] {
        displayGraphEdges().compactMap { edge in
            let neighborID: UUID
            if edge.fromNodeID == nodeID {
                neighborID = edge.toNodeID
            } else if edge.toNodeID == nodeID {
                neighborID = edge.fromNodeID
            } else {
                return nil
            }
            guard let parentPosition = bodies[nodeID]?.pos,
                  let neighborPosition = bodies[neighborID]?.pos else {
                return nil
            }
            return Double(
                atan2(
                    neighborPosition.y - parentPosition.y,
                    neighborPosition.x - parentPosition.x
                )
            )
        }
    }

    /// Matches the rendered Insight chip's fixed horizontal layout closely enough for the
    /// cleanup simulation to keep even long titles from overlapping chips in another node.
    private func insightCollisionSize(for insight: InsightModel) -> CGSize {
        if let cached = collisionSizeCache.sizes[insight.title] { return cached }
        let titleWidth = ceil(
            (insight.title as NSString).size(
                withAttributes: [.font: Self.insightCollisionFont]
            ).width
        )
        let size = CGSize(
            width: 20 + 14 + 10 + titleWidth + 20,
            height: 16 + Self.insightCollisionFont.lineHeight + 16
        )
        collisionSizeCache.sizes[insight.title] = size
        return size
    }

    /// Wraps an angle difference to [-π, π].
    private func wrapAngle(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 2 * .pi)
        if x > .pi { x -= 2 * .pi }
        if x < -.pi { x += 2 * .pi }
        return x
    }

    private func insightWorldPosition(for node: NodeModel, index: Int, count: Int) -> CGPoint {
        let visibleInsights = canvasInsights(for: node)
        guard index < visibleInsights.count else { return node.position }
        return insightSpatialPosition(visibleInsights[index], node: node, index: index, count: count).world
    }

    /// The single source of an orbiting Insight's projected world position and local depth.
    /// While this exact chip is being press-dragged, it follows the finger anywhere — the
    /// connector line stretches to match — rather than the fixed (angle, bond length) orbit.
    private func insightSpatialPosition(
        _ insight: InsightModel,
        node: NodeModel,
        index: Int,
        count: Int
    ) -> (world: CGPoint, elevation: CGFloat, localDepth: CGFloat) {
        let radius = bondLength(forInsightID: insight.id)
        let elevationAngle = Self.depthCuesEnabled ? insightElevationAngle(insight.id) : 0
        let localDepth = InsightClusterSpatialLayout.normalizedDepth(angle: elevationAngle)
        if draggingChipID == insight.id, let live = draggingChipWorldPosition {
            // Same angle at the live distance: a chip dragged inward sinks toward the plane
            // rather than climbing past 45° over its Node Concept.
            let liveZ = InsightClusterSpatialLayout.elevation(
                angle: elevationAngle,
                horizontalDistance: hypot(live.x - node.position.x, live.y - node.position.y)
            )
            return (live, liveZ, localDepth)
        }
        let z = InsightClusterSpatialLayout.elevation(angle: elevationAngle, horizontalDistance: radius)
        // Free VSEPR bond angle (falls back to the even base angle until the sim seeds it).
        let angle = chipAngles[insight.id]?.angle ?? baseChipAngle(index: index, count: count)
        let world = CGPoint(
            x: node.position.x + cos(angle) * radius,
            y: node.position.y + sin(angle) * radius
        )
        return (world, z, localDepth)
    }

    private func insightElevationAngle(_ id: UUID) -> CGFloat {
        chipElevationAngles[id] ?? 0
    }

    /// Orbit height of an Insight: its elevation angle at its bond length.
    private func insightElevation(_ insight: InsightModel) -> CGFloat {
        InsightClusterSpatialLayout.elevation(
            angle: insightElevationAngle(insight.id),
            horizontalDistance: bondLength(forInsightID: insight.id)
        )
    }

    /// The plane point under the finger for a dragged chip. Its height depends on its distance
    /// from the Node Concept, which depends on the point, so refine from the orbit height.
    private func draggedChipFootprint(
        under location: CGPoint,
        insight: InsightModel,
        node: NodeModel,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> CGPoint {
        let angle = Self.depthCuesEnabled ? insightElevationAngle(insight.id) : 0
        var world = camera.screenToWorld(location, elevation: insightElevation(insight), in: size)
        for _ in 0..<3 {
            let z = InsightClusterSpatialLayout.elevation(
                angle: angle,
                horizontalDistance: hypot(world.x - node.position.x, world.y - node.position.y)
            )
            world = camera.screenToWorld(location, elevation: z, in: size)
        }
        return world
    }

    /// Resolves every visible Insight once per render. Chips, connectors, pulses, midpoint
    /// connectors, and selection lines all read these placements, so they cannot disagree about
    /// where a chip is, and no render path rescans nodes or re-filters members per chip.
    private func makeInsightLayout() -> CanvasInsightLayout {
        var layout = CanvasInsightLayout(nodes: displayNodes)
        for node in layout.nodes {
            let visibleInsights = canvasInsights(for: node)
            layout.insightsByNode[node.id] = visibleInsights
            let isPinnedAtNode = placedMidpointNodeIDs.contains(node.id)
            for (index, insight) in visibleInsights.enumerated() {
                var spatial: (world: CGPoint, elevation: CGFloat, localDepth: CGFloat) = isPinnedAtNode
                    ? (node.position, 0, 0)
                    : insightSpatialPosition(insight, node: node, index: index, count: visibleInsights.count)
                if !isPinnedAtNode, let offset = studyOffset(forInsightID: insight.id, nodeID: node.id) {
                    spatial = (
                        CGPoint(x: node.position.x + CGFloat(offset.x), y: node.position.y + CGFloat(offset.y)),
                        CGFloat(offset.z),
                        spatial.localDepth * CGFloat(1 - studyProgress)
                    )
                }
                layout.placements[insight.id] = InsightPlacement(
                    insight: insight,
                    nodeID: node.id,
                    index: index,
                    count: visibleInsights.count,
                    isPinnedAtNode: isPinnedAtNode,
                    world: spatial.world,
                    elevation: spatial.elevation,
                    localDepth: spatial.localDepth
                )
            }
        }
        return layout
    }

    // MARK: - Node Concept Study

    /// The ring's bottom edge sits this far above the canvas's bottom, which is the top of the
    /// docked Study tool card.
    private static let studyRingBottomMargin: CGFloat = 24

    private func makeStudyFraming(in size: CGSize) -> StudyFraming? {
        guard let nodeID = studyFocusNodeID, let slot = studySlot,
              let position = bodies[nodeID]?.pos ?? nodes.first(where: { $0.id == nodeID })?.position
        else { return nil }
        return StudyFraming(
            nodeCenter: SIMD3(Double(position.x), Double(position.y), 0),
            radius: studyRadius,
            slot: slot,
            // The ring is 42 pt tall, so its center is 21 pt above its bottom edge.
            ringCenterY: size.height - Self.studyRingBottomMargin - 21
        )
    }

    /// The Study camera starts from the tree's live camera, not a snapshot: the canvas can
    /// resize while docked cards swap, and at progress 0 the two must match exactly so handing
    /// back to the tree never jumps.
    private func studyCamera(_ tree: InsightTreeCamera, framing: StudyFraming?, in size: CGSize) -> InsightTreeCamera {
        guard let framing else { return tree }
        var camera = tree
        camera.orbit = framing.camera(
            from: tree.currentOrbitCamera(in: size),
            progress: studyProgress,
            yaw: studyYaw,
            pan: studyPan,
            zoom: studyZoom,
            pivot: studyPivotPoint(framing: framing),
            pivotBlend: studyPivotBlend,
            targetShift: studyTargetShift
        )
        camera.studyNodeCenter = framing.nodeCenter
        return camera
    }

    /// Everything but the studied Node Concept and its Insights fades as the camera moves in.
    private func studyOpacity(forNodeID nodeID: UUID) -> Double {
        guard let focus = studyFocusNodeID, nodeID != focus else { return 1 }
        return 1 - studyProgress
    }

    /// Chip scale: the tree's, blending in Study to the same size with gentle depth scaling.
    private func chipScale(nodeID: UUID, magnification: CGFloat) -> CGFloat {
        // In the tree, perspective moves chips but doesn't resize them.
        let tree: CGFloat = 1
        guard nodeID == studyFocusNodeID else { return tree }
        let study = pow(max(magnification, 0.01), 0.6)
        return tree + (study - tree) * CGFloat(studyProgress)
    }

    /// How far a studied Insight has swung behind its Node Concept: 0 in front, 1 behind, easing
    /// smoothly (smoothstep) across the node's depth so dimming never snaps while rotating.
    private func studyDepthDim(_ placement: InsightPlacement, camera: InsightTreeCamera) -> Double {
        guard placement.nodeID == studyFocusNodeID, placement.insight.id != studyPivotID,
              let orbit = camera.orbit, let center = camera.studyNodeCenter,
              let chip = orbit.project(SIMD3(Double(placement.world.x), Double(placement.world.y), Double(placement.elevation))),
              let node = orbit.project(center)
        else { return 0 }
        let band = 0.7 * studyRadius
        let t = min(max((chip.depth - node.depth + band / 2) / band, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// A studied Insight's offset from its Node Concept, moving from its tree position to its
    /// place on the Study sphere.
    private func studyOffset(forInsightID insightID: UUID, nodeID: UUID) -> SIMD3<Double>? {
        guard nodeID == studyFocusNodeID, studyProgress > 0,
              let start = studyTreeOffsets[insightID], let spread = studySpread[insightID]
        else { return nil }
        let length = simd_length(start)
        let from = length > 1e-9 ? start / length : spread
        let direction = StudyNodeLayout.slerp(from, spread, studyProgress)
        return direction * (length + (studyRadius - length) * studyProgress)
    }

    private func beginStudy(of nodeID: UUID) {
        let layout = makeInsightLayout()
        guard let node = layout.nodes.first(where: { $0.id == nodeID }) else { return }
        let center = SIMD3(Double(node.position.x), Double(node.position.y), 0)
        var ids: [UUID] = []
        var offsets: [SIMD3<Double>] = []
        for insight in layout.insightsByNode[nodeID] ?? [] {
            guard let placement = layout.placements[insight.id], !placement.isPinnedAtNode else { continue }
            ids.append(insight.id)
            offsets.append(SIMD3(
                Double(placement.world.x), Double(placement.world.y), Double(placement.elevation)
            ) - center)
        }
        studyTreeOffsets = Dictionary(uniqueKeysWithValues: zip(ids, offsets))
        studySpread = Dictionary(uniqueKeysWithValues: zip(ids, StudyNodeLayout.sphereSpread(from: offsets)))
        let lengths = offsets.map(simd_length).filter { $0 > 1 }
        studyRadius = lengths.isEmpty ? 190 : lengths.reduce(0, +) / Double(lengths.count)
        studyYaw = 0
        studyPan = .zero
        studyZoom = StudyFraming.entryZoom
        studyLastDetentYaw = 0
        studyPivotLink?.stop()
        studyPivotSwitchLink?.stop()
        studyPivotID = nil
        studyPivotFrom = nil
        studyPivotBlend = 0
        studyTargetShift = .zero
        studyFocusNodeID = nodeID
        // Opened from an Insight's Study: fly straight to that Insight, hovered. It is already
        // the hover, so only the Study camera needs it.
        if let insightID = studyInitialHoverInsightID, studyTreeOffsets[insightID] != nil {
            studyPivotID = insightID
            studyPivotBlend = 1
            studyZoom = max(studyZoom, StudyFraming.hoverZoom)
        }
        animateStudyProgress(to: 1, duration: 0.8)
    }

    private func endStudy() {
        guard studyFocusNodeID != nil else { return }
        studyDragMode = nil
        studyRingActive = 0
        studySpinLink?.stop()
        studySpinLink = nil
        // Whole turns look identical, so drop them before flying back: the exit unwinds at most
        // half a turn, the short way, rather than every turn the user made.
        let wrappedYaw = remainder(studyYaw, 2 * .pi)
        studyLastDetentYaw += wrappedYaw - studyYaw
        studyYaw = wrappedYaw
        // Leaving Study keeps a hovered Insight hovered; only the Study camera lets go of it.
        if studyPivotID != nil { releaseStudyPivot(in: lastCanvasSize) }
        animateStudyProgress(to: 0, duration: 0.6) {
            studyFocusNodeID = nil
            studyTreeOffsets = [:]
            studySpread = [:]
        }
    }

    /// Drives the camera move frame by frame (ease in-out), since every position on the canvas
    /// is computed from `studyProgress` rather than interpolated by SwiftUI.
    private func animateStudyProgress(to target: Double, duration: Double, completion: (() -> Void)? = nil) {
        studyLink?.stop()
        let from = studyProgress
        let start = CACurrentMediaTime()
        let driver = DisplayLinkDriver()
        driver.onTick = { now in
            let t = min(max((now - start) / duration, 0), 1)
            let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            studyProgress = from + (target - from) * eased
            if t >= 1 {
                studyLink?.stop()
                studyLink = nil
                completion?()
            }
        }
        driver.start()
        studyLink = driver
    }

    /// In Study a drag on the ring spins the node like a turntable; any other drag moves it. It
    /// starts on touch-down so the ring responds the moment a finger lands on it.
    private func studyDragGesture(
        ring: [CGPoint],
        chips: [(id: UUID, frame: CGRect)],
        nodeFrame: CGRect?,
        size: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if studyDragMode == nil {
                    // Any touch catches a coasting ring.
                    studySpinLink?.stop()
                    studySpinLink = nil
                    let onRing = StudyFraming.distance(from: value.startLocation, toPolyline: ring) < 28
                    studyDragMode = onRing ? .rotate : .pending
                    studyLastDragLocation = value.startLocation
                    if studyDragMode == .rotate {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
                        withAnimation(.easeInOut(duration: 0.25)) { studyRingActive = 1 }
                    }
                }
                if studyDragMode == .pending {
                    // Still possibly a tap; becomes a pan once it moves.
                    guard hypot(value.translation.width, value.translation.height) > Self.studyTapSlop else { return }
                    studyDragMode = .pan
                    // Like panning away in the tree, dragging off a hovered Insight unhovers it.
                    if studyPivotID != nil { unhoverStudyInsight(in: size) }
                }
                let previous = studyLastDragLocation ?? value.startLocation
                let delta = CGSize(width: value.location.x - previous.x, height: value.location.y - previous.y)
                studyLastDragLocation = value.location
                switch studyDragMode {
                case .rotate:
                    // Dragging right carries the front of the ring to the right.
                    let xs = ring.map(\.x)
                    let halfWidth = max(((xs.max() ?? 0) - (xs.min() ?? 0)) / 2, 40)
                    studyRingHalfWidth = halfWidth
                    spinStudy(by: -Double(delta.width / halfWidth))
                case .pan:
                    studyPan.width += delta.width
                    studyPan.height += delta.height
                case .pending, nil:
                    break
                }
            }
            .onEnded { value in
                if studyDragMode == .pending {
                    if let hit = chips.first(where: { $0.frame.contains(value.location) }) {
                        hoverStudyInsight(hit.id, in: size)
                    } else if let nodeFrame, nodeFrame.contains(value.location) {
                        hoverStudyNode(in: size)
                    }
                } else if studyDragMode == .rotate {
                    coastStudySpin(velocity: -Double(value.velocity.width / studyRingHalfWidth))
                }
                studyDragMode = nil
                studyLastDragLocation = nil
                withAnimation(.easeInOut(duration: 0.3)) { studyRingActive = 0 }
            }
    }

    private var studyPinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = studyPinchStartZoom ?? studyZoom
                studyPinchStartZoom = start
                studyZoom = min(max(start * value.magnification, 0.5), 5)
            }
            .onEnded { _ in studyPinchStartZoom = nil }
    }

    /// Where the camera centers for the focused Insight, gliding from the previous one.
    private func studyPivotPoint(framing: StudyFraming) -> SIMD3<Double>? {
        guard let id = studyPivotID, let target = studyInsightPosition(id, framing: framing) else { return nil }
        guard let from = studyPivotFrom else { return target }
        return from + (target - from) * studyPivotSwitch
    }

    /// A studied Insight's position on its Study sphere.
    private func studyInsightPosition(_ insightID: UUID, framing: StudyFraming) -> SIMD3<Double>? {
        guard let focus = studyFocusNodeID,
              let offset = studyOffset(forInsightID: insightID, nodeID: focus) else { return nil }
        return framing.nodeCenter + offset
    }

    /// Where each studied Insight's chip is on screen, padded for an easy tap.
    private func studyTapTargets(
        layout: CanvasInsightLayout,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> [(id: UUID, frame: CGRect)] {
        guard let focus = studyFocusNodeID else { return [] }
        return (layout.insightsByNode[focus] ?? []).compactMap { insight in
            guard let placement = layout.placements[insight.id], !placement.isPinnedAtNode else { return nil }
            let projection = insightProjection(placement, camera: camera, size: size)
            let chip = insightCollisionSize(for: insight)
            let scale = chipScale(nodeID: focus, magnification: projection.scale)
            let frame = CGRect(
                x: projection.position.x - chip.width * scale / 2,
                y: projection.position.y - chip.height * scale / 2,
                width: chip.width * scale,
                height: chip.height * scale
            )
            return (insight.id, frame.insetBy(dx: -8, dy: -8))
        }
        // Nearer chips first, so the one drawn on top wins an overlapping tap.
        .sorted { first, second in
            (studyDepth(of: first.id, camera: camera) ?? 0) < (studyDepth(of: second.id, camera: camera) ?? 0)
        }
    }

    private func studyDepth(of insightID: UUID, camera: InsightTreeCamera) -> Double? {
        guard let orbit = camera.orbit, let center = camera.studyNodeCenter,
              let focus = studyFocusNodeID,
              let offset = studyOffset(forInsightID: insightID, nodeID: focus) else { return nil }
        return orbit.project(center + offset)?.depth
    }

    /// Hovering an Insight in Study is the tree's hover (same haptic, card state, and pulses via
    /// `onInsightTapped`), and the Study camera centers it, zooms in, and turns around it. The
    /// tree's own camera focuses it too, unseen, so leaving Study lands on it still hovered.
    private func hoverStudyInsight(_ insightID: UUID, in size: CGSize) {
        guard let focus = studyFocusNodeID,
              let node = nodes.first(where: { $0.id == focus }),
              let insight = node.insights.first(where: { $0.id == insightID }) else { return }
        markDiscovered(insightID)
        if let treeOffset = studyTreeOffsets[insightID] {
            let bodyPosition = bodies[focus]?.pos ?? node.position
            focusHoveredTarget(
                at: CGPoint(x: bodyPosition.x + CGFloat(treeOffset.x), y: bodyPosition.y + CGFloat(treeOffset.y)),
                elevation: CGFloat(treeOffset.z),
                in: size
            )
        }
        onInsightTapped(insight)
        focusStudyInsight(insightID)
    }

    /// The studied node's label on screen, padded for an easy tap.
    private func studyNodeTapTarget(camera: InsightTreeCamera, size: CGSize) -> CGRect? {
        guard let focus = studyFocusNodeID,
              let node = displayNodes.first(where: { $0.id == focus }) else { return nil }
        let position = camera.project(node.position, in: size).position
        let width: CGFloat = node.isSuggested ? 220 : 260
        return CGRect(x: position.x - width / 2, y: position.y - 44, width: width, height: 88)
    }

    /// Tapping the studied node hovers it (the tree's node hover), and the camera glides back to
    /// center the node with the axis on it (from a hovered Insight, or from a pan).
    private func hoverStudyNode(in size: CGSize) {
        guard let focus = studyFocusNodeID,
              let node = displayNodes.first(where: { $0.id == focus }) else { return }
        if studyPivotID != nil { releaseStudyPivot(in: size) }
        recenterStudyNode()
        focusHoveredTarget(at: node.position, in: size)
        onNodeTapped(node)
    }

    /// Eases any pan and look-at shift back to zero, centering the node, and zooms in like a
    /// hover in the tree (to at least `StudyFraming.hoverZoom`).
    private func recenterStudyNode() {
        let fromPan = studyPan
        let fromShift = studyTargetShift
        let fromZoom = studyZoom
        let toZoom = max(studyZoom, StudyFraming.hoverZoom)
        studyPivotLink?.stop()
        let start = CACurrentMediaTime()
        let driver = DisplayLinkDriver()
        driver.onTick = { now in
            let (eased, done) = Self.studyHoverCurve(elapsed: now - start)
            studyPan = CGSize(width: fromPan.width * (1 - eased), height: fromPan.height * (1 - eased))
            studyTargetShift = fromShift * (1 - eased)
            studyZoom = fromZoom + (toZoom - fromZoom) * CGFloat(eased)
            if done {
                studyPivotLink?.stop()
                studyPivotLink = nil
            }
        }
        driver.start()
        studyPivotLink = driver
    }

    /// Turns the node, with a detent haptic every 15°.
    private func spinStudy(by delta: Double) {
        studyYaw += delta
        if abs(studyYaw - studyLastDetentYaw) >= .pi / 12 {
            studyLastDetentYaw = studyYaw
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// After a ring swipe the node keeps turning at the release velocity (radians per second)
    /// and eases to a stop.
    private func coastStudySpin(velocity: Double) {
        studySpinLink?.stop()
        guard abs(velocity) > 0.3 else { return }
        var speed = min(max(velocity, -12), 12)
        var last = CACurrentMediaTime()
        let driver = DisplayLinkDriver()
        driver.onTick = { now in
            let dt = min(now - last, 1.0 / 30)
            last = now
            spinStudy(by: speed * dt)
            speed *= exp(-3.2 * dt)
            if abs(speed) < 0.05 {
                studySpinLink?.stop()
                studySpinLink = nil
            }
        }
        driver.start()
        studySpinLink = driver
    }

    /// Unhovering returns the hover to the studied node (as tapping it would) and the axis of
    /// rotation to the node's center, without moving the view.
    private func unhoverStudyInsight(in size: CGSize) {
        releaseStudyPivot(in: size)
        guard let focus = studyFocusNodeID,
              let node = displayNodes.first(where: { $0.id == focus }) else { return }
        focusHoveredTarget(at: node.position, in: size)
        onNodeTapped(node)
    }

    private func focusStudyInsight(_ insightID: UUID) {
        guard insightID != studyPivotID || studyPivotBlend < 1 else { return }
        let settledPan = studyPan
        if studyPivotID != nil, studyPivotID != insightID, studyPivotBlend > 0,
           // Only the node's position matters here, not the canvas size.
           let framing = makeStudyFraming(in: .zero),
           let from = studyPivotPoint(framing: framing) {
            // Moving between focused Insights: glide from one to the other.
            studyPivotFrom = from
            studyPivotID = insightID
            animateStudyPivotSwitch()
            return animateStudyPivot(to: 1)
        }
        studyPivotID = insightID
        animateStudyPivot(to: 1) {
            // Fully centered: the pan and any shift have eased out, so drop them for good.
            if studyPan == settledPan {
                studyPan = .zero
                studyTargetShift = .zero
            }
        }
    }

    /// The tree's hover spring as a 0 → 1 curve (it overshoots slightly), and whether it has
    /// settled.
    private static func studyHoverCurve(elapsed: TimeInterval) -> (value: Double, done: Bool) {
        let spring = StudyFraming.hoverSpring
        guard elapsed < spring.settlingDuration else { return (1, true) }
        return (spring.value(target: 1.0, time: elapsed), false)
    }

    /// Returns the axis of rotation to the node's center without moving anything on screen: the
    /// rotation center moves to the node while the look-at point, zoom, and pan are re-expressed
    /// so every point projects exactly where it did.
    private func releaseStudyPivot(in size: CGSize) {
        studyPivotLink?.stop()
        studyPivotSwitchLink?.stop()
        defer {
            studyPivotID = nil
            studyPivotFrom = nil
            studyPivotBlend = 0
        }
        guard let framing = makeStudyFraming(in: size),
              let current = studyCamera(
                  InsightTreeCamera(scale: activeScale, offset: activeOffset),
                  framing: framing,
                  in: size
              ).orbit,
              studyProgress > 0.99
        else { return }
        let blend = studyPivotBlend
        let newTarget = current.target(
            keepingViewWhenCenterMovesFrom: current.rotationCenter ?? current.target,
            to: framing.nodeCenter
        )
        studyTargetShift = newTarget - framing.nodeCenter
        // Fold the focus's zoom and eased-out pan into the plain Study values.
        studyZoom *= 1 + (StudyFraming.hoverZoomFactor(zoom: studyZoom) - 1) * CGFloat(blend)
        studyPan = CGSize(
            width: studyPan.width * (1 - blend),
            height: studyPan.height * (1 - blend) + StudyFraming.pivotDrop * blend
        )
    }

    private func animateStudyPivotSwitch() {
        studyPivotSwitchLink?.stop()
        studyPivotSwitch = 0
        let start = CACurrentMediaTime()
        let driver = DisplayLinkDriver()
        driver.onTick = { now in
            let (eased, done) = Self.studyHoverCurve(elapsed: now - start)
            studyPivotSwitch = eased
            if done {
                studyPivotSwitchLink?.stop()
                studyPivotSwitchLink = nil
                studyPivotFrom = nil
            }
        }
        driver.start()
        studyPivotSwitchLink = driver
    }

    private func animateStudyPivot(to target: Double, completion: (() -> Void)? = nil) {
        studyPivotLink?.stop()
        let from = studyPivotBlend
        let start = CACurrentMediaTime()
        let driver = DisplayLinkDriver()
        driver.onTick = { now in
            let (eased, done) = Self.studyHoverCurve(elapsed: now - start)
            studyPivotBlend = from + (target - from) * eased
            if done {
                studyPivotLink?.stop()
                studyPivotLink = nil
                completion?()
            }
        }
        driver.start()
        studyPivotLink = driver
    }

    /// The Node currently hosting `insightID` as one of its own (non-pinned) chips.
    private func parentNode(ofInsightID insightID: UUID) -> NodeModel? {
        nodes.first { node in
            !placedMidpointNodeIDs.contains(node.id) && node.insights.contains { $0.id == insightID }
        }
    }

    /// Points every source of a placed Midpoint at that Midpoint's own node, except `excluding`
    /// (the chip the user just deliberately dragged, whose angle is authoritative). Two connected
    /// chips facing each other is what keeps their line from cutting across an unrelated one —
    /// e.g. the line between their own two parent Nodes.
    private func reangleMidpointSources(of midpointID: UUID, excluding: UUID? = nil) {
        guard let midpointNode = nodes.first(where: { $0.id == midpointID }),
              let sources = placedMidpointSources[midpointID] else { return }
        for source in sources where !source.isNode && source.insightID != excluding {
            guard let parent = parentNode(ofInsightID: source.insightID) else { continue }
            let angle = Double(atan2(
                midpointNode.position.y - parent.position.y,
                midpointNode.position.x - parent.position.x
            ))
            chipAngles[source.insightID] = ChipAngle(angle: angle)
            pinnedChipAngleIDs.insert(source.insightID)
        }
    }

    /// Every placed Midpoint that `insightID` is itself a source of.
    private func midpointIDs(sourcedBy insightID: UUID) -> [UUID] {
        placedMidpointSources.compactMap { midpointID, sources in
            sources.contains { !$0.isNode && $0.insightID == insightID } ? midpointID : nil
        }
    }

    // MARK: - 2.5D Depth Cues

    /// Depth multiplier for a node in [depthMin…, 1]: 1 = nearest (full size/opacity, no
    /// parallax). Always 1 when the depth layer is disabled or the node has no depth entry.
    private func depthFactor(_ nodeID: UUID) -> CGFloat {
        guard Self.depthCuesEnabled else { return 1 }
        return CGFloat(nodeDepths[nodeID] ?? 1)
    }

    private func depthScale(_ nodeID: UUID) -> CGFloat {
        Self.depthMinScale + (1 - Self.depthMinScale) * depthFactor(nodeID)
    }

    private func depthOpacity(_ nodeID: UUID) -> Double {
        Self.depthMinOpacity + (1 - Self.depthMinOpacity) * Double(depthFactor(nodeID))
    }

    /// Every chip goes through the same perspective camera as the plane beneath it, so a raised
    /// chip sits higher and nearer than its footprint and moves faster than the plane while
    /// panning. The hovered chip needs no special case: focus solves for its elevation.
    private func insightProjection(
        _ placement: InsightPlacement,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> PerspectivePlaneProjection.Point {
        camera.project(placement.world, elevation: placement.elevation, in: size)
    }

    private func insightScreenPosition(
        _ placement: InsightPlacement,
        camera: InsightTreeCamera,
        size: CGSize
    ) -> CGPoint {
        insightProjection(placement, camera: camera, size: size).position
    }

    /// Combines the global semantic MDS depth of a Node Concept with an Insight's local
    /// elevation for opacity. Pinned midpoint Insights stay at their Node depth.
    private func insightDepthFactor(_ placement: InsightPlacement) -> CGFloat {
        clamp(depthFactor(placement.nodeID) + placement.localDepth * 0.12, lower: 0, upper: 1)
    }

    private func insightDepthOpacity(_ placement: InsightPlacement) -> Double {
        Self.depthMinOpacity + (1 - Self.depthMinOpacity) * Double(insightDepthFactor(placement))
    }

    /// World elevation of a visible Insight by id (0 for pinned midpoints and hidden members).
    private func insightElevation(forInsightID id: UUID) -> CGFloat {
        guard Self.depthCuesEnabled,
              let node = nodes.first(where: { node in
                  !placedMidpointNodeIDs.contains(node.id) && node.insights.contains { $0.id == id }
              }),
              let insight = canvasInsights(for: node).first(where: { $0.id == id }) else { return 0 }
        return insightElevation(insight)
    }

    /// The node whose orbit an insight chip belongs to (for depth lookups by insight id).
    private func owningNodeID(forInsightID id: UUID) -> UUID? {
        nodes.first(where: { $0.insights.contains { $0.id == id } })?.id
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

    private func canvasInsights(for node: NodeModel) -> [InsightModel] {
        let members = canvasInsightMembers(
            nodeLabel: node.conceptLabel,
            insights: node.insights,
            preservesMatchingTitle: placedMidpointNodeIDs.contains(node.id)
        )
        return showsAllClusterInsights ? members : Array(members.prefix(6))
    }

    /// Live simulated position for a node id (for by-id lookups).
    private func simPosition(of id: UUID) -> CGPoint? {
        bodies[id]?.pos ?? nodes.first(where: { $0.id == id })?.position
    }

    /// Node footprint for the overlap-separation force — its longest bond plus chip extent.
    private func simFootprintRadius(_ node: NodeModel) -> CGFloat {
        if placedMidpointNodeIDs.contains(node.id) { return 70 }
        let maxBond = canvasInsights(for: node)
            .map { bondLength(forInsightID: $0.id) }
            .max() ?? 70
        return maxBond + 64
    }

    private func startSim(
        intensity: Double = 1,
        alphaDecay: Double = Self.alphaDecay,
        addsBreeze: Bool = false,
        frameBudget: Int = Self.settleFrameBudget
    ) {
        simFramesRemaining = max(simFramesRemaining, frameBudget)
        alpha = max(alpha, intensity)
        simAlphaDecay = alphaDecay
        if addsBreeze {
            breezeStartedAt = CACurrentMediaTime()
            let angle = CGFloat.random(in: -0.5...0.5)
            breezeDirection = CGVector(dx: cos(angle), dy: sin(angle))
        }
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
        breezeStartedAt = nil
        stopSim()
    }

    /// Seed bodies for new nodes, drop bodies for removed nodes, preserve the rest (no jump),
    /// and wake the sim. Called when the view model's topology changes.
    private func reconcileBodies() {
        let isInitialLayout = bodies.isEmpty
        let liveIDs = Set(nodes.map(\.id))
        var next = bodies.filter { liveIDs.contains($0.key) }
        if !isInitialLayout {
            for (id, var body) in next {
                body.vel = CGVector(
                    dx: body.vel.dx * 0.2,
                    dy: body.vel.dy * 0.2
                )
                next[id] = body
            }
        }
        for node in nodes where next[node.id] == nil {
            next[node.id] = SimBody(pos: node.position, vel: .zero)
        }
        bodies = next

        // Seed/drop per-insight bond angles. A node without external bonds starts evenly
        // distributed. Otherwise every new Insight enters the largest open arc among both its
        // sibling Insight bonds and all node-to-node lines connected to the parent concept.
        let chipIDs = Set(nodes.flatMap { canvasInsights(for: $0).map(\.id) })
        var nextAngles = chipAngles.filter { chipIDs.contains($0.key) }
        pinnedChipAngleIDs.formIntersection(chipIDs)
        for node in nodes {
            let visibleInsights = canvasInsights(for: node)
            var occupiedAngles = connectedNodeBondAngles(for: node.id)
            if isInitialLayout && occupiedAngles.isEmpty {
                for (index, insight) in visibleInsights.enumerated() where nextAngles[insight.id] == nil {
                    nextAngles[insight.id] = ChipAngle(
                        angle: baseChipAngle(index: index, count: visibleInsights.count)
                    )
                }
                continue
            }

            occupiedAngles.append(
                contentsOf: visibleInsights.compactMap { nextAngles[$0.id]?.angle }
            )
            for insight in visibleInsights where nextAngles[insight.id] == nil {
                let seed = maximizedChipGapAngle(among: occupiedAngles)
                nextAngles[insight.id] = ChipAngle(angle: seed)
                occupiedAngles.append(seed)
            }
        }
        chipAngles = nextAngles

        // Seed elevation angles here too, not only in the sim: opening a tree freezes the sim, so
        // it never runs to assign them and every Insight would sit flat on the plane. Insights
        // already placed keep their angle; the sim (when it runs) eases them to new targets.
        var nextElevations = chipElevationAngles.filter { chipIDs.contains($0.key) }
        for node in nodes where !placedMidpointNodeIDs.contains(node.id) {
            let members = canvasInsights(for: node).compactMap { insight in
                nextAngles[insight.id].map {
                    InsightClusterSpatialLayout.Member(id: insight.id, azimuth: $0.angle)
                }
            }
            for (id, target) in InsightClusterSpatialLayout.elevationTargets(members)
            where nextElevations[id] == nil {
                nextElevations[id] = target
            }
        }
        chipElevationAngles = nextElevations

        if isInitialLayout {
            // Restored positions are already authoritative. Opening the Canvas should be
            // perfectly still rather than replaying a global settling pass.
            freezeSimulation()
        } else {
            startSim(
                intensity: Self.updateIntensity,
                alphaDecay: Self.updateAlphaDecay,
                addsBreeze: true,
                frameBudget: 90
            )
        }
    }

    /// One cleanup step. Anchors each node to its semantic (MDS) target, separates overlapping
    /// footprints/chips, spreads chip-label angles, holds pinned nodes fixed, and writes back once.
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

        let nodeByID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let entries = bodies.map { ($0.key, $0.value) }
        var forces: [UUID: CGVector] = [:]
        var maxChipAngMotion: Double = 0   // keeps the sim awake while chips are still spreading

        // Live world footprint of every visible chip. These participate in one global collision
        // pass, regardless of which Node Concept owns them.
        struct ChipInfo {
            let id: UUID
            let nodeID: UUID
            let angle: Double
            let radius: CGFloat
            let pos: CGPoint
            let halfWidth: CGFloat
            let halfHeight: CGFloat
        }
        var chipInfos: [ChipInfo] = []
        for node in nodes {
            guard let body = bodies[node.id] else { continue }
            if placedMidpointNodeIDs.contains(node.id) {
                guard let insight = node.insights.first else { continue }
                let size = insightCollisionSize(for: insight)
                chipInfos.append(
                    ChipInfo(
                        id: insight.id,
                        nodeID: node.id,
                        angle: 0,
                        radius: 0,
                        pos: body.pos,
                        halfWidth: size.width / 2,
                        halfHeight: size.height / 2
                    )
                )
                continue
            }
            let visibleInsights = canvasInsights(for: node)
            for (index, insight) in visibleInsights.enumerated() {
                let theta: Double
                let radius: CGFloat
                let pos: CGPoint
                if draggingChipID == insight.id, let live = draggingChipWorldPosition {
                    // The dragged chip's real-time position, so collision/spread this frame
                    // reacts to where it actually is right now instead of its last committed
                    // (angle, bond length) — this is what makes nearby chips make room for it
                    // live instead of only after the drag ends.
                    pos = live
                    radius = hypot(live.x - body.pos.x, live.y - body.pos.y)
                    theta = Double(atan2(live.y - body.pos.y, live.x - body.pos.x))
                } else {
                    theta = chipAngles[insight.id]?.angle ?? baseChipAngle(index: index, count: visibleInsights.count)
                    radius = bondLength(forInsightID: insight.id)
                    pos = CGPoint(x: body.pos.x + cos(theta) * radius, y: body.pos.y + sin(theta) * radius)
                }
                let size = insightCollisionSize(for: insight)
                chipInfos.append(
                    ChipInfo(
                        id: insight.id,
                        nodeID: node.id,
                        angle: theta,
                        radius: radius,
                        pos: pos,
                        halfWidth: size.width / 2,
                        halfHeight: size.height / 2
                    )
                )
            }
        }

        // Every domain around a node: its insight bonds AND the fixed directions of its
        // node-to-node lines. Only chip angles move — node positions belong to the MDS targets,
        // so line directions act as read-only repellers that keep chips off visible edges.
        enum BondKind { case insight(UUID); case fixedEdge }
        struct Bond { let angle: Double; let kind: BondKind }
        var bondsByNode: [UUID: [Bond]] = [:]
        var chipInfoByID: [UUID: ChipInfo] = [:]
        for ci in chipInfos {
            bondsByNode[ci.nodeID, default: []].append(Bond(angle: ci.angle, kind: .insight(ci.id)))
            chipInfoByID[ci.id] = ci
        }
        // Use the SAME edges that are rendered (displayGraphEdges fabricates a line for the
        // 2-node / ring fallback), so every visible node-to-node line repels chips too.
        for edge in displayGraphEdges() {
            guard let aPos = bodies[edge.fromNodeID]?.pos, let bPos = bodies[edge.toNodeID]?.pos else { continue }
            bondsByNode[edge.fromNodeID, default: []].append(Bond(angle: Double(atan2(bPos.y - aPos.y, bPos.x - aPos.x)), kind: .fixedEdge))
            bondsByNode[edge.toNodeID, default: []].append(Bond(angle: Double(atan2(aPos.y - bPos.y, aPos.x - bPos.x)), kind: .fixedEdge))
        }

        // Insight collision. A collision rotates both free bonds away from contact; across nodes
        // it also gently separates their parent nodes, allowing Insights in unrelated concepts to
        // affect one another without discarding the semantic layout. Same-node chips only rotate:
        // the angular spread below is planar, and opposite elevations can still bring two sibling
        // labels together on screen.
        var crossNodeForces: [UUID: CGVector] = [:]
        var chipTorque: [UUID: Double] = [:]
        func addCrossNodeForce(_ force: CGVector, to nodeID: UUID) {
            let current = crossNodeForces[nodeID, default: .zero]
            crossNodeForces[nodeID] = CGVector(
                dx: current.dx + force.dx,
                dy: current.dy + force.dy
            )
        }
        for firstIndex in chipInfos.indices {
            for secondIndex in chipInfos.indices where secondIndex > firstIndex {
                let first = chipInfos[firstIndex]
                let second = chipInfos[secondIndex]
                let isSameNode = first.nodeID == second.nodeID

                let dx = first.pos.x - second.pos.x
                let dy = first.pos.y - second.pos.y
                let overlapX = first.halfWidth + second.halfWidth
                    + Self.insightCollisionPadding - abs(dx)
                let overlapY = first.halfHeight + second.halfHeight
                    + Self.insightCollisionPadding - abs(dy)
                guard overlapX > 0, overlapY > 0 else { continue }

                let firstSortsBeforeSecond = first.id.uuidString < second.id.uuidString
                let xDirection: CGFloat = abs(dx) > 0.5
                    ? (dx >= 0 ? 1 : -1)
                    : (firstSortsBeforeSecond ? -1 : 1)
                let yDirection: CGFloat = abs(dy) > 0.5
                    ? (dy >= 0 ? 1 : -1)
                    : (firstSortsBeforeSecond ? 1 : -1)
                let separation: CGVector = overlapX < overlapY
                    ? CGVector(dx: xDirection * overlapX, dy: 0)
                    : CGVector(dx: 0, dy: yDirection * overlapY)
                let separationLength = max(hypot(separation.dx, separation.dy), 1)
                let unitX = separation.dx / separationLength
                let unitY = separation.dy / separationLength
                let force = CGVector(
                    dx: separation.dx * Self.bubblePushK,
                    dy: separation.dy * Self.bubblePushK
                )
                if !isSameNode {
                    addCrossNodeForce(force, to: first.nodeID)
                    addCrossNodeForce(CGVector(dx: -force.dx, dy: -force.dy), to: second.nodeID)
                }

                let normalizedDepth = Double(min(min(overlapX, overlapY) / 48, 2))
                if first.radius > 1 {
                    let tangentX = CGFloat(-sin(first.angle))
                    let tangentY = CGFloat(cos(first.angle))
                    let tangentialContact = Double(unitX * tangentX + unitY * tangentY)
                    chipTorque[first.id, default: 0] +=
                        tangentialContact * normalizedDepth * Self.crossNodeChipTorqueK
                }
                if second.radius > 1 {
                    let tangentX = CGFloat(-sin(second.angle))
                    let tangentY = CGFloat(cos(second.angle))
                    let tangentialContact = Double(-unitX * tangentX - unitY * tangentY)
                    chipTorque[second.id, default: 0] +=
                        tangentialContact * normalizedDepth * Self.crossNodeChipTorqueK
                }
            }
        }

        // Anchor spring toward the MDS target + whole-node and global Insight separation.
        for i in entries.indices {
            let (idA, a) = entries[i]
            if pinned.contains(idA) { continue }
            var fx = crossNodeForces[idA]?.dx ?? 0
            var fy = crossNodeForces[idA]?.dy ?? 0
            if let target = layoutTargets[idA] {
                fx += (target.x - a.pos.x) * Self.anchorSpringK
                fy += (target.y - a.pos.y) * Self.anchorSpringK
            }
            if let breezeStartedAt {
                let progress = min(max((now - breezeStartedAt) / Self.breezeDuration, 0), 1)
                if progress < 1 {
                    // A single soft gust: the sine-squared envelope reaches zero at both
                    // ends, avoiding the abrupt force changes that read as jitter.
                    let envelope = CGFloat(pow(sin(.pi * progress), 2))
                    let phaseOffset = Double(idA.uuid.0) / 255 * 0.18
                    let localVariation = CGFloat(
                        0.88 + 0.12 * sin(progress * .pi + phaseOffset)
                    )
                    fx += breezeDirection.dx * Self.breezeForce * envelope * localVariation
                    fy += breezeDirection.dy * Self.breezeForce * envelope * localVariation
                }
            }
            for j in entries.indices where j != i {
                let (idB, b) = entries[j]
                var dx = a.pos.x - b.pos.x
                var dy = a.pos.y - b.pos.y
                var dist = hypot(dx, dy)
                if dist < 0.5 { dx = .random(in: -1...1); dy = .random(in: -1...1); dist = 1 }

                if let na = nodeByID[idA], let nb = nodeByID[idB] {
                    let minDist = simFootprintRadius(na) + simFootprintRadius(nb) + Self.overlapPadding
                    if dist < minDist {
                        let push = (minDist - dist) * 0.05
                        fx += (dx / dist) * push
                        fy += (dy / dist) * push
                    }
                }
            }
            // No idle jitter: once the short settling pass ends, nodes stay put.
            fx += CGFloat.random(in: -Self.jitterAmplitude...Self.jitterAmplitude) * CGFloat(alpha)
            fy += CGFloat.random(in: -Self.jitterAmplitude...Self.jitterAmplitude) * CGFloat(alpha)
            forces[idA] = CGVector(dx: fx, dy: fy)
        }

        // Chip-angle spread: Insight bonds and fixed Node lines repel with equal domain weight,
        // maximizing separation across every bond connected to the parent Node Concept.
        for (_, bonds) in bondsByNode where bonds.count > 1 {
            for ii in bonds.indices {
                guard case .insight(let id) = bonds[ii].kind else { continue }
                let bi = bonds[ii]
                var torque = 0.0
                for jj in bonds.indices where jj != ii {
                    var dθ = wrapAngle(bi.angle - bonds[jj].angle)
                    if abs(dθ) < 1e-4 { dθ = .random(in: -0.05...0.05) }
                    torque += Self.bondDomainK * (dθ >= 0 ? 1 : -1)
                        / (abs(dθ) + Self.chipAngleEps)

                    // Extra push once two Insight labels' angular gap is tighter than their real
                    // widths need at this orbit radius — the uniform spread above doesn't know
                    // either chip's width, so a long title can still settle too close to its
                    // neighbor even at "maximized" angular separation.
                    if case .insight(let otherID) = bonds[jj].kind,
                       let chipA = chipInfoByID[id], let chipB = chipInfoByID[otherID],
                       chipA.radius > 1 {
                        let requiredGap = atan2(
                            chipA.halfWidth + chipB.halfWidth + Self.chipWidthAngularPadding,
                            chipA.radius
                        )
                        let deficit = requiredGap - abs(dθ)
                        if deficit > 0 {
                            torque += Self.chipWidthRepulsionK * (dθ >= 0 ? 1 : -1) * Double(deficit)
                        }
                    }
                }
                chipTorque[id, default: 0] += torque
            }
        }
        // Cooling factor (simulated annealing). The angular repulsion never vanishes at
        // equilibrium, so leaving motion uncooled makes bonds oscillate around the ±π boundary —
        // visible as jitter that only stops when the frame budget expires. Scaling every frame's
        // displacement by `alpha` (which decays to 0) lets the layout converge and freeze smoothly.
        let cool = alpha
        let coolCG = CGFloat(alpha)

        if !chipTorque.isEmpty {
            var nextAngles = chipAngles
            for (id, torque) in chipTorque {
                // A pinned chip (deliberately dragged, or facing a Midpoint it's a source of)
                // still repels its siblings via the torque IT exerts on THEM above — only the
                // write-back of ITS OWN angle is skipped, so the spread simulation can't quietly
                // rotate a chosen angle back out from under it.
                guard !pinnedChipAngleIDs.contains(id), id != draggingChipID else { continue }
                guard var ch = nextAngles[id] else { continue }
                let rawStep = max(-Self.chipMaxAngStep, min(Self.chipMaxAngStep, torque * Self.chipAngGain * Double(dtScale)))
                let step = rawStep * cool
                ch.angle += step
                maxChipAngMotion = max(maxChipAngMotion, abs(step))
                nextAngles[id] = ch
            }
            chipAngles = nextAngles
        }

        // Elevation spread: each cluster's Insights alternate up and down the ±45° band around
        // their Node Concept. Angles ease toward those targets (cooled like the bond angles) so a
        // reordering glides instead of snapping. A drag only moves a chip around its node; its
        // height, like every sibling's, follows from the new order.
        if Self.depthCuesEnabled {
            var nextElevations = chipElevationAngles
            var membersByNode: [UUID: [InsightClusterSpatialLayout.Member]] = [:]
            for ci in chipInfos where ci.radius > 1 {
                membersByNode[ci.nodeID, default: []].append(
                    InsightClusterSpatialLayout.Member(id: ci.id, azimuth: ci.angle)
                )
            }
            for members in membersByNode.values {
                for (id, target) in InsightClusterSpatialLayout.elevationTargets(members) {
                    guard let current = nextElevations[id] else {
                        nextElevations[id] = target
                        continue
                    }
                    let step = (target - current) * Self.elevationEaseRate * CGFloat(dtScale) * coolCG
                    maxChipAngMotion = max(maxChipAngMotion, Double(abs(step)))
                    nextElevations[id] = current + step
                }
            }
            if nextElevations != chipElevationAngles { chipElevationAngles = nextElevations }
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

        // Pinned bodies track their authoritative view-model position — with two exceptions:
        // a placed Midpoint being dragged directly (its own chip has no orbit, so the drag just
        // repositions it 1:1), and a placed Midpoint currently sourced by the chip being
        // rotate-dragged, which leans toward it by a fraction of how far that chip has moved from
        // where the drag started. Both read live off `draggingChipWorldPosition` (updated every
        // drag move, bypassing the chip's own pinned angle/radius — see `insightWorldPosition`).
        for id in pinned {
            if id == draggingChipID, let live = draggingChipWorldPosition {
                next[id]?.pos = live
                continue
            }
            if placedMidpointNodeIDs.contains(id),
               let draggingChipID, let live = draggingChipWorldPosition,
               let start = draggingChipStartWorldPosition,
               let sources = placedMidpointSources[id],
               sources.contains(where: { !$0.isNode && $0.insightID == draggingChipID }) {
                let followFactor: CGFloat = 0.35
                let base = nodeByID[id]?.position ?? next[id]?.pos ?? .zero
                next[id]?.pos = CGPoint(
                    x: base.x + (live.x - start.x) * followFactor,
                    y: base.y + (live.y - start.y) * followFactor
                )
                continue
            }
            if let node = nodeByID[id] { next[id]?.pos = node.position }
        }

        alpha = max(Self.alphaFloor, alpha * (1 - simAlphaDecay))
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

    private func visibleInsightIDs(in nodes: [NodeModel]) -> Set<UUID> {
        Set(nodes.flatMap { node in
            canvasInsights(for: node).map(\.id)
        })
    }

    private func loadSeenInsightIDs() -> Set<UUID> {
        InsightDiscoveryStore.loadSeenInsightIDs()
    }

    /// Merges this open's visible insights into the persisted "seen" set — never replaces it.
    /// `seenInsightIDsKey` is one shared UserDefaults key across every Insight Tree instance (the
    /// Global tree and every per-conversation tree), and the same saved Insight can legitimately
    /// appear in more than one of them. A plain overwrite here dropped every OTHER tree's
    /// previously-seen insights the moment this tree opened — so tapping an insight to clear its
    /// blue dot, then opening a different tree containing that same insight and coming back,
    /// re-flagged it "new" on `computeNewInsights()`'s next diff and put the dot right back.
    private func saveAllInsightIDsAsSeen() {
        let ids = Set(nodes.flatMap { $0.insights }.map(\.id))
        InsightDiscoveryStore.saveSeenInsightIDs(Array(loadSeenInsightIDs().union(ids)))
    }

    /// Returns insights that weren't present the last time InsightTree was opened.
    /// Returns empty on the very first open (no persisted state yet).
    private func computeNewInsights() -> [InsightModel] {
        let seenIDs = loadSeenInsightIDs()
        guard !seenIDs.isEmpty else { return [] }
        return nodes.flatMap { node in
            canvasInsights(for: node).filter { !seenIDs.contains($0.id) }
        }
    }

    /// Establishes the first backend snapshot as the camera baseline, then tours only content
    /// introduced by later successful persisted mutations. This prevents the temporary
    /// in-memory fallback from consuming the update animation while the backend is still working.
    private func presentPersistedTree(animated: Bool, in size: CGSize) {
        entranceTask?.cancel()

        let currentInsightIDs = visibleInsightIDs(in: nodes)
        let currentNodeIDs = Set(nodes.map(\.id))
        // A live refresh uses the diff from the previously applied snapshot. If the update
        // completed while Canvas was closed, consume the exact persisted presentation targets
        // instead of treating the entire first snapshot as new.
        let pendingInsightIDs = InsightDiscoveryStore.pendingInsightPresentationIDs()
            .intersection(currentInsightIDs)
        let pendingNodeIDs = InsightDiscoveryStore.pendingNodePresentationIDs()
            .intersection(currentNodeIDs)
        let changedInsightIDs =
            currentInsightIDs.subtracting(confirmedPersistedInsightIDs)
        let changedNodeIDs =
            currentNodeIDs.subtracting(confirmedPersistedNodeIDs)
        // In-app mutations record their exact presentation targets. Intersecting those with
        // the snapshot diff prevents a first-load race from touring older content. Keep the
        // raw diff as a fallback for tree changes made by another client or backend process.
        let newInsightIDs = animated
            ? (pendingInsightIDs.isEmpty
                ? changedInsightIDs
                : changedInsightIDs.intersection(pendingInsightIDs))
            : pendingInsightIDs
        let newNodeIDs = animated
            ? (pendingNodeIDs.isEmpty
                ? changedNodeIDs
                : changedNodeIDs.intersection(pendingNodeIDs))
            : pendingNodeIDs
        let newInsights = nodes.flatMap { node in
            canvasInsights(for: node).filter { newInsightIDs.contains($0.id) }
        }
        // Clear these before the asynchronous camera/reveal sequence begins. This prevents a
        // connector from the previous topology from remaining visible during the camera scroll.
        revealedInsightConnectorIDs.subtract(newInsightIDs)
        let newGraphEdgeIDs = Set(displayGraphEdges().filter {
            newNodeIDs.contains($0.fromNodeID) || newNodeIDs.contains($0.toNodeID)
        }.map(\.id))
        revealedGraphEdgeIDs.subtract(newGraphEdgeIDs)
        animatedGraphEdgeIDs.formUnion(newGraphEdgeIDs)
        confirmedPersistedInsightIDs = currentInsightIDs
        confirmedPersistedNodeIDs = currentNodeIDs
        undiscoveredInsightIDs.formUnion(loadUndiscoveredInsightIDs())
        undiscoveredNodeIDs.formUnion(loadUndiscoveredNodeIDs())

        guard !newInsights.isEmpty || !newNodeIDs.isEmpty else {
            revealedInsightIDs = currentInsightIDs
            revealedInsightConnectorIDs = currentInsightIDs
            revealedGraphEdgeIDs = Set(displayGraphEdges().map(\.id))
            revealedNodeIDs = currentNodeIDs
            saveAllInsightIDsAsSeen()
            reportUndiscoveredInsightCount()
            return
        }

        markUndiscovered(newInsights.map(\.id))
        markNodesUndiscovered(Array(newNodeIDs))
        reportUndiscoveredInsightCount()
        entranceTask = Task {
            // Let the node/body reconciliation from this same snapshot reach the canvas first.
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            await runPersistedUpdateSequence(
                newInsights: newInsights,
                newNodeIDs: newNodeIDs,
                in: size
            )
            guard !Task.isCancelled else { return }
            saveAllInsightIDsAsSeen()
            InsightDiscoveryStore.clearPendingTreePresentation(
                insightIDs: Set(newInsights.map(\.id)),
                nodeIDs: newNodeIDs
            )
        }
    }

    /// Camera/reveal sequence for one fully loaded persisted mutation. Node Concepts participate
    /// even when the backend correctly adds no automatic Insights.
    private func runPersistedUpdateSequence(
        newInsights: [InsightModel],
        newNodeIDs: Set<UUID>,
        in size: CGSize
    ) async {
        enum Target {
            case insight(InsightModel)
            case node(UUID)
        }

        let insightIDs = Set(newInsights.map(\.id))
        let allInsightIDs = visibleInsightIDs(in: nodes)
        let allNodeIDs = Set(nodes.map(\.id))
        revealedInsightIDs = allInsightIDs.subtracting(insightIDs)
        revealedInsightConnectorIDs = allInsightIDs.subtracting(insightIDs)
        let newGraphEdgeIDs = Set(displayGraphEdges().filter {
            newNodeIDs.contains($0.fromNodeID) || newNodeIDs.contains($0.toNodeID)
        }.map(\.id))
        revealedGraphEdgeIDs = Set(displayGraphEdges().map(\.id)).subtracting(newGraphEdgeIDs)
        revealedNodeIDs = allNodeIDs.subtracting(newNodeIDs)

        // The topology callback can arrive before the simulation has reconciled the new nodes.
        // Give the layout a beat to create/settle their bodies before resolving camera targets;
        // otherwise positionedTargets is empty and the post-update camera tour is skipped.
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }

        let targets: [Target] =
            nodes.filter { newNodeIDs.contains($0.id) }.map { Target.node($0.id) }
            + newInsights.map(Target.insight)

        func position(for target: Target) -> CGPoint? {
            switch target {
            case .insight(let insight):
                return worldPosition(forInsightID: insight.id)
            case .node(let nodeID):
                return simPosition(of: nodeID)
                    ?? nodes.first(where: { $0.id == nodeID })?.position
            }
        }

        let positionedTargets = targets.compactMap { target -> (Target, CGPoint)? in
            guard let position = position(for: target) else { return nil }
            return (target, position)
        }
        guard !positionedTargets.isEmpty else {
            revealedInsightIDs = allInsightIDs
            revealedInsightConnectorIDs = allInsightIDs
            revealedNodeIDs = allNodeIDs
            return
        }

        if positionedTargets.count <= 3 {
            for (target, position) in positionedTargets {
                guard !Task.isCancelled else { return }
                focusInsight(at: position, in: size)
                try? await Task.sleep(for: .milliseconds(950))
                guard !Task.isCancelled else { return }

                switch target {
                case .insight(let insight):
                    withAnimation(
                        .spring(response: 0.6, dampingFraction: 0.75),
                        completionCriteria: .logicallyComplete
                    ) {
                        revealedInsightIDs.insert(insight.id)
                    } completion: {
                        guard !Task.isCancelled else { return }
                        revealedInsightConnectorIDs.insert(insight.id)
                    }
                case .node(let nodeID):
                    _ = withAnimation(.easeOut(duration: 0.22)) {
                        revealedNodeIDs.insert(nodeID)
                    }
                    try? await Task.sleep(for: .milliseconds(620))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.62)) {
                        revealedGraphEdgeIDs.formUnion(displayGraphEdges().filter {
                            $0.fromNodeID == nodeID || $0.toNodeID == nodeID
                        }.map(\.id))
                    }
                }
                rippleTrigger = RippleTrigger(
                    worldOrigin: position,
                    startTime: Date().timeIntervalSinceReferenceDate
                )
                try? await Task.sleep(for: .milliseconds(700))
            }
        } else {
            let positions = positionedTargets.map(\.1)
            zoomToFit(worldPositions: positions, in: size)
            try? await Task.sleep(for: .milliseconds(1_100))
            guard !Task.isCancelled else { return }
            withAnimation(
                .easeOut(duration: 0.22),
                completionCriteria: .logicallyComplete
            ) {
                revealedNodeIDs.formUnion(newNodeIDs)
                revealedInsightIDs.formUnion(insightIDs)
            } completion: {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(620))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.62)) {
                        revealedInsightConnectorIDs.formUnion(insightIDs)
                        revealedGraphEdgeIDs.formUnion(displayGraphEdges().filter {
                            newNodeIDs.contains($0.fromNodeID) || newNodeIDs.contains($0.toNodeID)
                        }.map(\.id))
                    }
                }
            }
            let center = CGPoint(
                x: positions.map(\.x).reduce(0, +) / CGFloat(positions.count),
                y: positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
            )
            rippleTrigger = RippleTrigger(
                worldOrigin: center,
                startTime: Date().timeIntervalSinceReferenceDate
            )
        }
    }

    // MARK: - Undiscovered (blue-dot) tracking

    private func loadUndiscoveredInsightIDs() -> Set<UUID> {
        InsightDiscoveryStore.loadUndiscoveredInsightIDs()
    }

    private func persistUndiscoveredInsightIDs() {
        InsightDiscoveryStore.saveUndiscoveredInsightIDs(undiscoveredInsightIDs)
    }

    private func loadUndiscoveredNodeIDs() -> Set<UUID> {
        InsightDiscoveryStore.loadUndiscoveredNodeIDs()
    }

    private func persistUndiscoveredNodeIDs() {
        InsightDiscoveryStore.saveUndiscoveredNodeIDs(undiscoveredNodeIDs)
    }

    private func reportUndiscoveredInsightCount() {
        let visibleInsightIDs = Set(nodes.flatMap { node in
            canvasInsights(for: node).map(\.id)
        })
        let visibleNodeIDs = Set(
            nodes.lazy
                .filter { !placedMidpointNodeIDs.contains($0.id) }
                .map(\.id)
        )
        let insightCount = undiscoveredInsightIDs.intersection(visibleInsightIDs).count
        let nodeCount = undiscoveredNodeIDs.intersection(visibleNodeIDs).count
        onUndiscoveredInsightCountChange(insightCount + nodeCount)
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

    /// Flag newly generated Node Concepts so they receive the same blue discovery dot.
    private func markNodesUndiscovered(_ ids: [UUID]) {
        let previousCount = undiscoveredNodeIDs.count
        undiscoveredNodeIDs.formUnion(ids)
        if undiscoveredNodeIDs.count != previousCount {
            persistUndiscoveredNodeIDs()
            reportUndiscoveredInsightCount()
        }
    }

    /// Opening a Node Concept clears its discovery dot permanently.
    private func markNodeDiscovered(_ id: UUID) {
        guard undiscoveredNodeIDs.contains(id) else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            _ = undiscoveredNodeIDs.remove(id)
        }
        persistUndiscoveredNodeIDs()
        reportUndiscoveredInsightCount()
    }

    /// World position of an insight looked up by ID (nil if not visible on tree).
    private func worldPosition(forInsightID id: UUID) -> CGPoint? {
        for node in displayNodes {
            if placedMidpointNodeIDs.contains(node.id), node.insights.contains(where: { $0.id == id }) {
                return node.position   // pinned chip sits on the node itself
            }
            let visible = canvasInsights(for: node)
            if let idx = visible.firstIndex(where: { $0.id == id }) {
                return insightWorldPosition(for: node, index: idx, count: visible.count)
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
            cameraState.scale = targetScale
            cameraState.offset = CGSize(width: -(centerX * targetScale), height: centerY * targetScale)
        }
    }

    /// Orchestrates the full entrance sequence based on how many new insights there are.
    private func runEntranceSequence(newInsights: [InsightModel], in size: CGSize) async {
        let allIDs = Set(nodes.flatMap { canvasInsights(for: $0).map(\.id) })
        let newIDs    = Set(newInsights.map { $0.id })
        let nonNewIDs = allIDs.subtracting(newIDs)

        // All non-new insights animate in with the standard 0.25 s stagger.
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        revealedInsightIDs = nonNewIDs
        revealedInsightConnectorIDs = nonNewIDs

        if newInsights.isEmpty {
            // Nothing new — reveal everything at the stagger point and we're done.
            revealedInsightIDs = allIDs
            revealedInsightConnectorIDs = allIDs
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
                withAnimation(
                    .spring(response: 0.6, dampingFraction: 0.75),
                    completionCriteria: .logicallyComplete
                ) {
                    revealedInsightIDs.insert(insight.id)
                } completion: {
                    guard !Task.isCancelled else { return }
                    revealedInsightConnectorIDs.insert(insight.id)
                }
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
            withAnimation(
                .spring(response: 0.6, dampingFraction: 0.75),
                completionCriteria: .logicallyComplete
            ) {
                revealedInsightIDs.formUnion(newIDs)
            } completion: {
                guard !Task.isCancelled else { return }
                revealedInsightConnectorIDs.formUnion(newIDs)
            }
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

/// `pending` is a touch that could still be a tap; it becomes `pan` once it moves.
private enum StudyDragMode { case rotate, pending, pan }

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

/// A connector between a Node and one of its Insights. The parent controls when this view is
/// inserted, so the line itself stays stateless while the camera is moving its endpoints.
private struct InsightConnectorLine: View {
    var start: CGPoint
    var end: CGPoint
    var color: Color

    init(start: CGPoint, end: CGPoint, color: Color) {
        self.start = start
        self.end = end
        self.color = color
    }

    var body: some View {
        AnimatableLine(start: start, end: end)
            .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round))
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

@MainActor
private final class InsightCollisionSizeCache {
    var sizes: [String: CGSize] = [:]
}

// MARK: - Camera Projection

private struct InsightTreeCamera {
    var scale: CGFloat
    var offset: CGSize
    /// In Study, every projection goes through this camera instead of the tree's, so the whole
    /// canvas moves with it.
    var orbit: OrbitCamera? = nil
    /// The studied Node Concept, for ordering its Insights in front of or behind it.
    var studyNodeCenter: SIMD3<Double>? = nil

    /// The camera looks straight down, so the plane (grid, edges, Node Concepts) stays flat on
    /// screen while Insights above or below it get a faint perspective parallax.
    /// Camera height in world units: an Insight at the full 45° on a typical 190-unit bond sits
    /// 5% farther from screen center and pans 5% faster than the plane (190 · 1.05 / 0.05). It
    /// scales with zoom, so the parallax depends only on elevation. The Study view is where
    /// Insights are seen in full 3D.
    static let focalLength: CGFloat = 3990

    func projection(in size: CGSize) -> PerspectivePlaneProjection {
        PerspectivePlaneProjection(
            pitch: 0,
            focalLength: Self.focalLength * scale,
            principalPoint: CGPoint(x: size.width / 2, y: size.height / 2)
        )
    }

    /// The top-down pan/zoom position, before perspective.
    func flatPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + point.x * scale + offset.width,
            y: size.height / 2 - point.y * scale + offset.height
        )
    }

    func world(fromFlat flat: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (flat.x - size.width / 2 - offset.width) / scale,
            y: -(flat.y - size.height / 2 - offset.height) / scale
        )
    }

    /// Projects a world point at `elevation` world units above the graph plane.
    func project(_ point: CGPoint, elevation: CGFloat = 0, in size: CGSize) -> PerspectivePlaneProjection.Point {
        if let orbit {
            guard let projected = orbit.project(SIMD3(Double(point.x), Double(point.y), Double(elevation))) else {
                return PerspectivePlaneProjection.Point(position: CGPoint(x: -10_000, y: -10_000), scale: 0.01)
            }
            return PerspectivePlaneProjection.Point(position: projected.position, scale: CGFloat(projected.scale))
        }
        return projection(in: size).project(flat: flatPoint(point, in: size), elevation: elevation * scale)
    }

    /// The flat point that puts something at `elevation` exactly on screen center.
    func flatPointCentering(elevation: CGFloat, in size: CGSize) -> CGPoint {
        projection(in: size).flatPointCentering(elevation: elevation * scale)
    }

    func worldToScreen(_ point: CGPoint, in size: CGSize) -> CGPoint {
        project(point, in: size).position
    }

    /// This camera's current framing as an `OrbitCamera` (yaw and pitch zero), exactly.
    func currentOrbitCamera(in size: CGSize) -> OrbitCamera {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let target = world(fromFlat: center, in: size)
        return OrbitCamera(
            target: SIMD3(Double(target.x), Double(target.y), 0),
            distance: Double(Self.focalLength),
            zoom: Double(scale),
            principalPoint: center
        )
    }

    /// The world point under `point`, assuming it lies `elevation` world units above the plane.
    func screenToWorld(_ point: CGPoint, elevation: CGFloat = 0, in size: CGSize) -> CGPoint {
        world(fromFlat: projection(in: size).unproject(point, elevation: elevation * scale), in: size)
    }
}

private func clamp<T: Comparable>(_ value: T, lower: T, upper: T) -> T {
    min(max(value, lower), upper)
}
