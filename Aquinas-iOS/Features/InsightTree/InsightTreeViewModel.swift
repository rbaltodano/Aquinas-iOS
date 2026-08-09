//
//  InsightTreeViewModel.swift
//  Aquinas-iOS
//

import Combine
import CoreGraphics
import CryptoKit
import Foundation
import NaturalLanguage
import SpriteKit
import SwiftUI

// MARK: - Insight Tree View Model

@MainActor
final class InsightTreeViewModel: ObservableObject {
    @Published private(set) var nodes: [NodeModel] = []
    @Published private(set) var edges: [EdgeModel] = []
    @Published private(set) var makeNodeChildIDs: Set<UUID> = []
    /// Child IDs whose generated title/definition have replaced their stable loading content.
    /// The canvas uses this to begin the three-stop reveal tour only after generation completes.
    @Published private(set) var generatedMakeNodeChildIDs: Set<UUID> = []
    /// Node IDs for user-placed midpoints. These render as a bare insight chip (no
    /// node-concept circle) pinned at their placed position.
    @Published private(set) var placedMidpointNodeIDs: Set<UUID> = []
    /// For each placed-midpoint node, the sources it connects to (insight chips / node concepts).
    @Published private(set) var placedMidpointSources: [UUID: [MidpointSource]] = [:]
    /// Per-insight bond length (connector radius): shorter = more related to its parent node.
    @Published private(set) var insightBondLengths: [UUID: CGFloat] = [:]
    /// Semantic (MDS) target position per node — the canvas anchors each node to its target
    /// with a weak spring so overlap cleanup can't destroy the embedding-driven layout.
    @Published private(set) var layoutTargets: [UUID: CGPoint] = [:]
    /// Normalized [0,1] depth per node from the third MDS component (1 = nearest),
    /// consumed by the canvas's 2.5D depth cues.
    @Published private(set) var nodeDepths: [UUID: Double] = [:]
    @Published var selectedNode: NodeModel?
    @Published var selectedSuggestedNode: NodeModel?

    let scene: InsightTreeScene
    private var insights: [InsightModel]
    private var persistedTree: PersistedInsightTree?
    private var promotedInsightIDs: [UUID]
    private var renderedNodeIDs: Set<UUID> = []
    private var placedMidpoints: [PlacedMidpoint] = []
    private let positionStoreKey = "aquinas.insight-tree.positions.v1"
    private static let clusterLabelStoreKey = "aquinas.insight-tree.cluster-labels.v1"
    /// The model boundary for every generative call (subject labels, concept blends). See
    /// `AquinasModel`'s doc comment — swapping in the real model is one conforming type.
    private let model: AquinasModel
    /// The source of insight embedding vectors. See `EmbeddingProvider`'s doc comment.
    private let embeddingProvider: EmbeddingProvider
    /// Global Insights graphs every cluster member. Persisted conversation trees retain their
    /// intentionally compact six-member presentation.
    private let showsAllClusterInsights: Bool
    /// Real Make Node children once generated, keyed by the promoted node's id — checked before
    /// the synchronous placeholder in `appendPromotedNodes`. Populated by `requestChildren`, which
    /// requests them once per newly-promoted insight and triggers a rebuild when they arrive.
    /// Child ids stay deterministic (`makeNodeChildID`) either way, so swapping placeholder → real
    /// content in place never re-triggers the reveal animation.
    private var generatedChildInsights: [UUID: [InsightModel]] = [:]
    private var childGenerationInFlight: Set<UUID> = []
    /// Scoped the same way as `placedMidpointStoreKey` — without this, a Make Node promotion's
    /// generated children reset to empty the moment the view model was recreated (e.g. navigating
    /// away from the Global tree and back), even on the rare paths where the promotion id itself
    /// survived: the tree would show the loading placeholder and regenerate from scratch.
    private static let makeNodeChildrenStoreKeyPrefix = "aquinas.insight-tree.make-node-children.v1"
    private var makeNodeChildrenStoreKey: String {
        "\(Self.makeNodeChildrenStoreKeyPrefix):\(midpointStoreScope?.uuidString ?? "global")"
    }
    private var generatedClusterLabels: [UUID: String] = [:]
    private var clusterLabelGenerationInFlight: Set<UUID> = []
    /// Real generated definitions for auto-clustered Nodes, keyed by cluster id — requested right
    /// after the label (see `requestClusterLabels`). Until it arrives, the Node's docked card
    /// falls back to `DockedNodeTreeCard.summaryText`.
    private var generatedClusterDefinitions: [UUID: String] = [:]
    private static let clusterDefinitionStoreKey = "aquinas.insight-tree.cluster-definitions.v1"
    /// Which auto-cluster (Node) each Insight belongs to, keyed by the Insight's own id rather
    /// than derived from "whichever Insight happened to found the cluster." A cluster used to get
    /// its id from `stableUUID(from: "global-insight-cluster:\(firstInsight.id)")` — so removing
    /// that one founding Insight silently re-founded the whole cluster under a fresh id on the
    /// next rebuild, discarding its position, label, and definition even though every other member
    /// was untouched. Persisting the assignment per-member means an add or remove only changes the
    /// Insight actually added or removed; everyone else's Node stays exactly where it was.
    private var insightClusterAssignments: [UUID: UUID] = [:]
    private static let insightClusterAssignmentStoreKey = "aquinas.insight-tree.insight-cluster-assignments.v1"
    /// Minimum cosine similarity for an Insight to attach to an existing local Node. The bundled
    /// provider is MiniLM, matching the backend embedding space. This value is centralized as a
    /// calibration constant so real-conversation evaluation can change it without touching layout.
    private let localMembershipThreshold = InsightTreeSemanticPolicy.membershipSimilarity
    /// On-device Node Concepts seeded from a conversation's questions (see
    /// `LocalInsightTreeSeedStore`), used only when the backend-owned persisted tree is
    /// unreachable. Fed into `makeClusteredTree` as pre-existing anchor clusters rather than a
    /// separate `persistedTree` snapshot, so a saved Insight that's semantically related attaches
    /// under the seeded subject instead of the seed and the clustering fallback fighting over
    /// which one owns the tree (see `setLocalSeedAnchors`'s doc comment for the history here).
    private var localSeedAnchors: [LocalInsightTreeSeed] = []

    /// A user-placed "midpoint" insight: a permanent node pinned at an explicit world
    /// position, connected by an edge to each of the source insights it was spawned from.
    private struct PlacedMidpoint: Equatable {
        let concept: ConceptDefinition
        let position: CGPoint
        let sources: [MidpointSource]
    }

    /// On-disk form of `PlacedMidpoint` — `ConceptDefinition` and `MidpointSource` are already
    /// Codable; only `CGPoint` needs the usual wrapper.
    private struct CodablePlacedMidpoint: Codable {
        let concept: ConceptDefinition
        let position: CodablePoint
        let sources: [MidpointSource]
    }

    /// Which conversation's tree this instance belongs to (`nil` for the Global tree) — scopes
    /// placed-Midpoint persistence the same way `LocalInsightTreeSeedStore` scopes seeds, so a
    /// Midpoint placed in one tree doesn't leak into another's.
    private let midpointStoreScope: UUID?
    private static let placedMidpointStoreKeyPrefix = "aquinas.insight-tree.placed-midpoints.v1"
    private var placedMidpointStoreKey: String {
        "\(Self.placedMidpointStoreKeyPrefix):\(midpointStoreScope?.uuidString ?? "global")"
    }

    init(
        insights: [ConceptDefinition],
        promotedInsightIDs: [UUID] = [],
        showsAllClusterInsights: Bool = false,
        model: AquinasModel = MockAquinasModel(),
        embeddingProvider: EmbeddingProvider = NLEmbeddingProvider(),
        localSeedAnchors: [LocalInsightTreeSeed] = [],
        midpointStoreScope: UUID? = nil
    ) {
        self.insights = Self.deduplicated(insights.map { InsightModel(concept: $0) })
        self.promotedInsightIDs = promotedInsightIDs
        self.showsAllClusterInsights = showsAllClusterInsights
        self.model = model
        self.embeddingProvider = embeddingProvider
        self.localSeedAnchors = localSeedAnchors
        self.midpointStoreScope = midpointStoreScope
        generatedClusterLabels = Self.loadClusterLabels(
            storageKey: Self.clusterLabelStoreKey
        )
        generatedClusterDefinitions = Self.loadClusterLabels(
            storageKey: Self.clusterDefinitionStoreKey
        )
        insightClusterAssignments = Self.loadUUIDMapping(
            storageKey: Self.insightClusterAssignmentStoreKey
        )
        placedMidpoints = Self.loadPlacedMidpoints(
            storageKey: "\(Self.placedMidpointStoreKeyPrefix):\(midpointStoreScope?.uuidString ?? "global")"
        )
        generatedChildInsights = Self.loadMakeNodeChildren(
            storageKey: "\(Self.makeNodeChildrenStoreKeyPrefix):\(midpointStoreScope?.uuidString ?? "global")"
        )
        scene = InsightTreeScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = UIColor(AquinasTheme.Colors.canvas)
        scene.onNodeTapped = { [weak self] node in
            Task { @MainActor in self?.handleTappedNode(node) }
        }
        scene.onSuggestConnection = { [weak self] edge in
            Task { @MainActor in await self?.generateSuggestedNode(for: edge) }
        }

        rebuildTree()
    }

    func updateInsights(_ concepts: [ConceptDefinition], promotedInsightIDs: [UUID]? = nil) {
#if DEBUG
        print("Aquinas updateInsights: incoming \(concepts.count) concept(s) \(concepts.map(\.word)), persistedTree=\(persistedTree == nil ? "nil" : "set")")
#endif
        if persistedTree == nil {
            insights = Self.deduplicated(concepts.map { InsightModel(concept: $0) })
        }
        if let promotedInsightIDs {
            self.promotedInsightIDs = promotedInsightIDs
            let retainedNodeIDs = Set(promotedInsightIDs.map {
                promotedNodeID(for: $0)
            })
            generatedChildInsights = generatedChildInsights.filter {
                retainedNodeIDs.contains($0.key)
            }
            persistMakeNodeChildren()
            childGenerationInFlight.formIntersection(retainedNodeIDs)
            let retainedChildIDs = Set(promotedInsightIDs.flatMap { insightID in
                let nodeID = promotedNodeID(for: insightID)
                return (0..<3).map { makeNodeChildID(for: nodeID, index: $0) }
            })
            generatedMakeNodeChildIDs.formIntersection(retainedChildIDs)
        }
        rebuildTree()
        if persistedTree == nil {
            refreshEmbeddingsIfNeeded()
        }
    }

    /// Replaces the on-device Node-seed anchors and rebuilds. A no-op when a real `persistedTree`
    /// is active — the backend-owned tree always wins when it's reachable.
    ///
    /// Earlier this session, on-device seeding instead called `applyPersistedTree` with a bare
    /// snapshot built purely from the seed labels (`insights: []` on every node). That worked
    /// for the very first render, but every later call — including the routine ones triggered by
    /// simply reopening the tree — replaced whatever richer state existed with that same bare
    /// snapshot again, silently discarding any Insight the user had saved in between. Gating that
    /// call on "only when nothing else exists yet" stopped the data loss, but then the seed and
    /// the clustering fallback became two separate, mutually exclusive trees: whichever last
    /// wrote to `persistedTree`/`insights` won, and the other's content vanished outright — so
    /// saving your first Insight would make the seeded Node itself disappear instead of the two
    /// coexisting. Feeding the seeds into the SAME clustering pass as regular Insights (below)
    /// removes the two-systems problem at the root: the seed renders as its own Node with zero
    /// Insights when none are saved yet, and a saved Insight that's semantically close attaches
    /// under it exactly like a real backend Node would, rather than either side overwriting the
    /// other.
    func setLocalSeedAnchors(_ seeds: [LocalInsightTreeSeed]) {
#if DEBUG
        print("Aquinas setLocalSeedAnchors: incoming \(seeds.map { "\($0.label)[emb=\($0.embedding?.count.description ?? "nil")]" }), persistedTree=\(persistedTree == nil ? "nil" : "set"), unchanged=\(localSeedAnchors == seeds)")
#endif
        guard persistedTree == nil, localSeedAnchors != seeds else { return }
        localSeedAnchors = seeds
        rebuildTree()
    }

    func applyPersistedTree(_ tree: PersistedInsightTree) {
#if DEBUG
        print("Aquinas InsightTreeViewModel: applyPersistedTree called with \(tree.nodes.count) node(s)")
#endif
        persistedTree = tree
        insights = tree.nodes.flatMap { node in
            node.insights.map { insight in
                InsightModel(
                    id: insight.id,
                    title: insight.title.capitalized,
                    definition: insight.definition,
                    conversationID: tree.conversationID,
                    relatednessToNode: insight.relatedness,
                    distanceToNode: insight.distance
                )
            }
        }
        rebuildTree()
    }

    /// Drops any later entry that repeats an earlier one's id, keeping first-seen order. Callers
    /// like the per-conversation tree build this list fresh from live conversation state (rather
    /// than a stable saved-insights store), so a duplicate id can slip in upstream — e.g. two
    /// synthesized "question" pseudo-insights whose ids happen to coincide. Every downstream step
    /// (clustering, force layout, position persistence) keys dictionaries by insight/node id and
    /// fatally crashes on a duplicate key, so this is enforced once, right at the boundary.
    private static func deduplicated(_ insights: [InsightModel]) -> [InsightModel] {
        var seen = Set<UUID>()
        return insights.filter { seen.insert($0.id).inserted }
    }

    /// Legacy in-memory save entry point. Conversation-scoped saves now flow through
    /// `InsightTreeService`; this remains available to non-persisted canvas variants.
    func onInsightSaved(_ insight: InsightModel) {
        var savedInsight = insight
        savedInsight.embedding = savedInsight.embedding ?? computeEmbedding(for: "\(insight.title). \(insight.definition)")
        savedInsight.embeddingVersion = savedInsight.embeddingVersion ?? NLEmbeddingProvider.version
        insights.append(savedInsight)
        rebuildTree()
        refreshEmbeddingsIfNeeded()
    }

    /// Confirms every insight's cached embedding matches the configured `embeddingProvider`,
    /// recomputing any that are missing or were produced by a different provider (a source swap).
    /// `rebuildTree`'s own embedding step above is a synchronous same-provider fallback only (it
    /// keeps the tree usable immediately, including during `init`); this is the versioned,
    /// async-capable path that becomes load-bearing once a non-`NLEmbeddingProvider` is configured.
    /// A no-op today: everything `rebuildTree` just tagged already matches, so this rebuilds
    /// nothing further.
    private func refreshEmbeddingsIfNeeded() {
        Task { @MainActor in
            let corrected = await ensureEmbeddings(for: insights)
            guard corrected != insights else { return }
            insights = corrected
            rebuildTree()
        }
    }

    private func ensureEmbeddings(for insights: [InsightModel]) async -> [InsightModel] {
        var next = insights
        for index in next.indices {
            let stale = next[index].embedding == nil || next[index].embeddingVersion != embeddingProvider.version
            guard stale else { continue }
            let text = "\(next[index].title). \(next[index].definition)"
            next[index].embedding = await embeddingProvider.embed(text)
            next[index].embeddingVersion = embeddingProvider.version
        }
        return next
    }

    /// Commits the canvas's live-simulated positions back into the model and persists them.
    /// Mutates positions in place without changing the node id set, so the canvas's body
    /// reconciliation is a no-op (no jump) and next launch restores the live layout.
    func commitLivePositions(_ positions: [UUID: CGPoint]) {
        var changed = false
        for index in nodes.indices {
            if let p = positions[nodes[index].id], nodes[index].position != p {
                nodes[index].position = p
                changed = true
            }
        }
        guard changed else { return }
        persistPositions(nodes)
        // A placed Midpoint's position is authoritative from `placedMidpoints`, not the position
        // store — every `rebuildTree()` reconstructs its Node fresh from `placed.position` (see
        // `appendPlacedMidpointNodes`), so a live-followed position (from rotate-dragging one of
        // its sources) needs updating here too or it reverts on the next rebuild.
        var midpointsChanged = false
        for index in placedMidpoints.indices {
            guard let p = positions[placedMidpoints[index].concept.id],
                  placedMidpoints[index].position != p else { continue }
            placedMidpoints[index] = PlacedMidpoint(
                concept: placedMidpoints[index].concept,
                position: p,
                sources: placedMidpoints[index].sources
            )
            midpointsChanged = true
        }
        if midpointsChanged {
            persistPlacedMidpoints()
        }
    }

    /// Places a new permanent insight node at an explicit world position, pinned (never moved
    /// by the force layout) and connected by a line to each source insight it was spawned from.
    func addPlacedMidpoint(concept: ConceptDefinition, at position: CGPoint, sources: [MidpointSource]) {
        placedMidpoints.append(PlacedMidpoint(concept: concept, position: position, sources: sources))
        persistPlacedMidpoints()
        rebuildTree()
    }

    /// Replaces a placed Midpoint's loading placeholder without changing its application-owned
    /// identity, position, or source connectors. Keeping the id stable prevents the canvas from
    /// treating the generated contents as a second Insight and replaying the entrance sequence.
    func replacePlacedMidpoint(id: UUID, with generatedConcept: ConceptDefinition) {
        guard let index = placedMidpoints.firstIndex(where: { $0.concept.id == id }) else {
            return
        }
        let placed = placedMidpoints[index]
        let replacement = ConceptDefinition(
            id: id,
            word: generatedConcept.word,
            partOfSpeech: generatedConcept.partOfSpeech,
            pronunciation: generatedConcept.pronunciation,
            meaning: generatedConcept.meaning,
            example: generatedConcept.example
        )
        placedMidpoints[index] = PlacedMidpoint(
            concept: replacement,
            position: placed.position,
            sources: placed.sources
        )
        persistPlacedMidpoints()
        rebuildTree()
    }

    func removePlacedMidpoint(id: UUID) {
        placedMidpoints.removeAll { $0.concept.id == id }
        persistPlacedMidpoints()
        rebuildTree()
    }

    func placedMidpointConcept(for id: UUID) -> ConceptDefinition? {
        placedMidpoints.first(where: { $0.concept.id == id })?.concept
    }

    func generateSuggestedNode(between nodeA: NodeModel, and nodeB: NodeModel) {
        let temporaryEdge = EdgeModel(
            id: UUID(),
            fromNodeID: nodeA.id,
            toNodeID: nodeB.id,
            distance: semanticDistance(nodeA.embedding, nodeB.embedding),
            isSuggested: false,
            showSuggestButton: true
        )
        Task { @MainActor in await generateSuggestedNode(for: temporaryEdge) }
    }

    func dismissSuggestedNode(_ node: NodeModel) {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            nodes.removeAll { $0.id == node.id }
            edges.removeAll { $0.fromNodeID == node.id || $0.toNodeID == node.id }
        }
        scene.render(nodes: nodes, edges: edges, animated: true)
    }

    func selectNode(_ node: NodeModel) {
        handleTappedNode(node)
    }

    func suggestConnection(for edge: EdgeModel) {
        Task { @MainActor in await generateSuggestedNode(for: edge) }
    }

    private func handleTappedNode(_ node: NodeModel) {
        if node.isSuggested {
            selectedSuggestedNode = node
        } else {
            selectedNode = node
        }
    }

    private func generateSuggestedNode(for edge: EdgeModel) async {
        guard let from = nodes.first(where: { $0.id == edge.fromNodeID }),
              let to = nodes.first(where: { $0.id == edge.toNodeID }) else {
            return
        }

        let midpointEmbedding = centroid([from.embedding, to.embedding])
        let suggestions = insights
            .filter { $0.embedding != nil }
            .sorted { lhs, rhs in
                semanticDistance(lhs.embedding ?? [], midpointEmbedding) < semanticDistance(rhs.embedding ?? [], midpointEmbedding)
            }
            .prefix(3)

        let suggestionInsights = Array(suggestions)
        guard !suggestionInsights.isEmpty else { return }

        let descriptions = suggestionInsights.map {
            "\($0.title): \($0.definition)"
        }
        guard let label = try? await model.labelSubject(
            forTitles: descriptions
        ) else {
            return
        }
        let suggestedNode = NodeModel(
            id: UUID(),
            conceptLabel: label,
            insights: suggestionInsights,
            embedding: centroid(suggestionInsights.compactMap(\.embedding)),
            position: CGPoint(
                x: (from.position.x + to.position.x) / 2,
                y: (from.position.y + to.position.y) / 2
            ),
            isSuggested: true,
            suggestedInsights: suggestionInsights
        )

        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            nodes.removeAll { $0.isSuggested }
            edges.removeAll { $0.isSuggested }
            nodes.append(suggestedNode)
            edges.append(EdgeModel(id: UUID(), fromNodeID: from.id, toNodeID: suggestedNode.id, distance: 0.18, isSuggested: true, showSuggestButton: false))
            edges.append(EdgeModel(id: UUID(), fromNodeID: suggestedNode.id, toNodeID: to.id, distance: 0.18, isSuggested: true, showSuggestButton: false))
        }
        scene.render(nodes: nodes, edges: edges, animated: true)
    }

    private func rebuildTree() {
        if let persistedTree {
            rebuildPersistedTree(persistedTree)
            return
        }

        // Synchronous same-provider fallback: keeps the tree usable immediately (including
        // during `init`, which can't await). `refreshEmbeddingsIfNeeded`/`ensureEmbeddings` is
        // the versioned, async-capable path layered on top (see its doc comment).
        let embeddedInsights = insights.map { insight -> InsightModel in
            var copy = insight
            guard copy.embedding == nil else { return copy }
            copy.embedding = computeEmbedding(for: "\(insight.title). \(insight.definition)")
            copy.embeddingVersion = NLEmbeddingProvider.version
            return copy
        }
        insights = embeddedInsights

        // The children spawned by "Make Node" (deterministic IDs) — used by the canvas to
        // give only these the icon-first loading mask + splay animation.
        makeNodeChildIDs = Set(promotedInsightIDs.flatMap { insightID -> [UUID] in
            let nodeID = promotedNodeID(for: insightID)
            return (0..<3).map { makeNodeChildID(for: nodeID, index: $0) }
        })

        // A placed Midpoint gets auto-bookmarked (see `InsightTreeView.placeMidpointInsight`),
        // which feeds its concept right back into `insights` alongside every ordinary saved
        // Insight. Without this exclusion it also goes through normal clustering below and gets
        // folded into whichever existing Node it's semantically nearest to — showing up doubled:
        // once as its own pinned Midpoint node, and again as a member listed under some other
        // Node's description that it happens to resemble.
        let placedMidpointIDs = Set(placedMidpoints.map { $0.concept.id })
        var (nextNodes, nextEdges) = makeClusteredTree(
            from: embeddedInsights.filter { !placedMidpointIDs.contains($0.id) }
        )
        appendPromotedNodes(to: &nextNodes, edges: &nextEdges, from: embeddedInsights)
        appendPlacedMidpointNodes(to: &nextNodes, edges: &nextEdges)
        adoptSpawnTargets(for: nextNodes)
        nextNodes = separateOverlaps(nodes: nextNodes)
        persistPositions(nextNodes)
        recomputeBondLengths(for: nextNodes)

        let nextIDs = Set(nextNodes.map(\.id))
        let hasNew = !nextIDs.isSubset(of: renderedNodeIDs)
        renderedNodeIDs = nextIDs
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            nodes = nextNodes
            edges = nextEdges
        }
        scene.render(nodes: nodes, edges: edges, animated: hasNew)
        requestClusterLabels(for: nextNodes)
    }

    /// Bond length per visible insight = relatedness (semantic distance) to its parent node's
    /// centroid embedding. Midpoint nodes (bare center chip) are skipped.
    ///
    /// Membership in a Node already requires distance below `localMembershipThreshold`'s
    /// complement — every insight under the same Node sits in a narrow absolute slice of that
    /// range (tighter still for a well-matched cluster), which used to feed `insightBondLength`
    /// directly: real, meaningful differences in relatedness compressed into a handful of pixels,
    /// reading as "every bond is the same length." Stretching each Node's own distances to fill
    /// the full [0, 1] range before mapping to pixels keeps the *relative* ordering (this insight
    /// is closer than that one) visible regardless of how tightly clustered the absolute values
    /// happen to be.
    private func recomputeBondLengths(for nodes: [NodeModel]) {
        var lengths: [UUID: CGFloat] = [:]
        for node in nodes where !placedMidpointNodeIDs.contains(node.id) {
            let distances: [(id: UUID, distance: Double)] = canvasInsights(for: node).map { insight in
                let dist = insight.distanceToNode
                    ?? semanticDistance(insight.embedding ?? [], node.embedding)
                return (insight.id, dist)
            }
            let range = distances.map(\.distance)
            guard let minDist = range.min(), let maxDist = range.max(), maxDist > minDist else {
                for entry in distances { lengths[entry.id] = insightBondLength(entry.distance) }
                continue
            }
            for entry in distances {
                let normalized = (entry.distance - minDist) / (maxDist - minDist)
                lengths[entry.id] = insightBondLength(normalized)
            }
        }
        insightBondLengths = lengths
    }

    private func rebuildPersistedTree(_ tree: PersistedInsightTree) {
        makeNodeChildIDs = Set(promotedInsightIDs.flatMap { insightID -> [UUID] in
            let nodeID = promotedNodeID(for: insightID)
            return (0..<3).map { makeNodeChildID(for: nodeID, index: $0) }
        })

        var builtNodes: [NodeModel] = []
        var builtEdges: [EdgeModel] = []
        for storedNode in tree.nodes {
            let nodeInsights = storedNode.insights.map { insight in
                InsightModel(
                    id: insight.id,
                    title: insight.title.capitalized,
                    definition: insight.definition,
                    conversationID: tree.conversationID,
                    embeddingVersion: "\(tree.embeddingModel).v\(tree.embeddingVersion)",
                    relatednessToNode: insight.relatedness,
                    distanceToNode: insight.distance
                )
            }
            let position: CGPoint
            if let restored = restoredPosition(for: storedNode.id) {
                position = restored
            } else if let neighbor = nearestPersistedNeighbor(
                for: storedNode.id,
                in: tree.edges,
                builtNodes: builtNodes
            ) {
                let angleSeed = stableUUID(from: "node-placement:\(storedNode.id)").uuid.0
                let angle = CGFloat(angleSeed) / 255 * (.pi * 2)
                let length = mapDistanceToLength(neighbor.edge.distance)
                position = CGPoint(
                    x: neighbor.node.position.x + cos(angle) * length,
                    y: neighbor.node.position.y + sin(angle) * length
                )
            } else if let previousNode = builtNodes.last {
                position = chainExtensionPosition(
                    from: previousNode,
                    nodes: builtNodes,
                    edges: builtEdges
                )
            } else {
                position = .zero
            }
            let node = NodeModel(
                id: storedNode.id,
                conceptLabel: storedNode.label,
                definition: storedNode.summary,
                insights: nodeInsights,
                embedding: [],
                position: position,
                isSuggested: false,
                suggestedInsights: nil
            )
            builtNodes.append(node)
        }

        let persistedNodeIDs = Set(builtNodes.map(\.id))
        builtEdges = tree.edges.compactMap { edge in
            guard persistedNodeIDs.contains(edge.fromNodeID),
                  persistedNodeIDs.contains(edge.toNodeID) else {
                return nil
            }
            return EdgeModel(
                id: edge.id,
                fromNodeID: edge.fromNodeID,
                toNodeID: edge.toNodeID,
                distance: edge.distance,
                isSuggested: false,
                showSuggestButton: false
            )
        }

        appendPromotedNodes(to: &builtNodes, edges: &builtEdges, from: insights)
        appendPlacedMidpointNodes(to: &builtNodes, edges: &builtEdges)
        adoptSpawnTargets(for: builtNodes)
        builtNodes = separateOverlaps(nodes: builtNodes)
        persistPositions(builtNodes)
        recomputeBondLengths(for: builtNodes)

        let nextIDs = Set(builtNodes.map(\.id))
        let hasNew = !nextIDs.isSubset(of: renderedNodeIDs)
        renderedNodeIDs = nextIDs
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            nodes = builtNodes
            edges = builtEdges
        }
        scene.render(nodes: nodes, edges: edges, animated: hasNew)
#if DEBUG
        print("Aquinas InsightTreeViewModel: rebuildPersistedTree applied \(builtNodes.count) node(s), \(builtEdges.count) edge(s), hasNew=\(hasNew)")
#endif
    }

    private func nearestPersistedNeighbor(
        for nodeID: UUID,
        in edges: [PersistedInsightTreeEdge],
        builtNodes: [NodeModel]
    ) -> (node: NodeModel, edge: PersistedInsightTreeEdge)? {
        let builtByID = Dictionary(uniqueKeysWithValues: builtNodes.map { ($0.id, $0) })
        return edges
            .compactMap { edge -> (NodeModel, PersistedInsightTreeEdge)? in
                if edge.fromNodeID == nodeID, let node = builtByID[edge.toNodeID] {
                    return (node, edge)
                }
                if edge.toNodeID == nodeID, let node = builtByID[edge.fromNodeID] {
                    return (node, edge)
                }
                return nil
            }
            .min { $0.1.distance < $1.1.distance }
    }

    /// Groups global-library bookmarks around semantic subject Nodes. Conversation trees use
    /// backend MiniLM membership; this offline/global fallback stays in the local embedding space.
    /// `localSeedAnchors` (on-device Node-seed labels — see `setLocalSeedAnchors`) seed this
    /// clustering as pre-existing, always-rendered clusters: an Insight within the same
    /// similarity threshold attaches under the seeded subject instead of spawning its own
    /// cluster, and an anchor with zero attached Insights still renders as its own Node so the
    /// seeded subject never just disappears once real Insights exist.
    private func makeClusteredTree(
        from insights: [InsightModel]
    ) -> (nodes: [NodeModel], edges: [EdgeModel]) {
        struct Cluster {
            let id: UUID
            var insights: [InsightModel]
            var embedding: [Double]
            var seedLabel: String?
            var seedSummary: String?
        }

        var clusters: [Cluster] = localSeedAnchors.map { seed in
            Cluster(
                id: seed.id,
                insights: [],
                embedding: seed.embedding ?? [],
                seedLabel: seed.label,
                seedSummary: seed.summary
            )
        }
#if DEBUG
        print("Aquinas makeClusteredTree: \(localSeedAnchors.count) anchor(s) \(localSeedAnchors.map { "\($0.label)[emb=\($0.embedding?.count.description ?? "nil")]" }), \(insights.count) insight(s) in order: \(insights.map { "\($0.title)[\($0.id.uuidString.prefix(4))]" })")
#endif
        for insight in insights {
            let embedding = insight.embedding ?? []

            // An Insight that already belongs to a Node keeps that Node's identity regardless of
            // what else was added or removed — no re-matching against current cluster centroids.
            let targetClusterID: UUID
            if let assigned = insightClusterAssignments[insight.id] {
                targetClusterID = assigned
            } else {
                let best = clusters.indices
                    .map { ($0, cosineSimilarity(embedding, clusters[$0].embedding)) }
                    .max { $0.1 < $1.1 }
                if let best, best.1 >= localMembershipThreshold {
                    targetClusterID = clusters[best.0].id
                } else {
                    targetClusterID = UUID()
                }
                insightClusterAssignments[insight.id] = targetClusterID
#if DEBUG
                print("Aquinas makeClusteredTree: '\(insight.title)' -> newly assigned cluster \(targetClusterID) (bestSim=\(best?.1 ?? -1))")
#endif
            }

            if let index = clusters.firstIndex(where: { $0.id == targetClusterID }) {
                clusters[index].insights.append(insight)
                clusters[index].embedding = centroid(
                    clusters[index].insights.compactMap(\.embedding)
                )
            } else {
                clusters.append(
                    Cluster(
                        id: targetClusterID,
                        insights: [insight],
                        embedding: embedding
                    )
                )
            }
        }
        let liveInsightIDs = Set(insights.map(\.id))
        insightClusterAssignments = insightClusterAssignments.filter { liveInsightIDs.contains($0.key) }
        persistInsightClusterAssignments()
#if DEBUG
        print("Aquinas makeClusteredTree: result \(clusters.count) cluster(s): \(clusters.map { "\($0.seedLabel ?? "auto"):\($0.insights.count)" })")
#endif

        // Bare nodes first — position filled in below by the same pass that decides edges, so
        // the two can never disagree (see the comment on that loop for why that matters).
        var builtNodes: [NodeModel] = clusters.map { cluster in
            NodeModel(
                id: cluster.id,
                conceptLabel: cluster.seedLabel
                    ?? generatedClusterLabels[cluster.id]
                    ?? provisionalClusterLabel(for: cluster.insights),
                definition: cluster.seedLabel != nil
                    ? (cluster.seedSummary ?? "")
                    : (generatedClusterDefinitions[cluster.id] ?? ""),
                insights: cluster.insights,
                embedding: cluster.embedding,
                position: .zero,
                isSuggested: false,
                suggestedInsights: nil
            )
        }

        var builtEdges: [EdgeModel] = []
        guard !builtNodes.isEmpty else { return (builtNodes, builtEdges) }

        // Grow a nearest-neighbor spanning tree (Prim's) and position each node AS it attaches,
        // directly off the edge that attaches it — one pass, not two. This used to be two
        // independent nearest-neighbor searches: one decided where to *draw* a node (nearest
        // among already-built nodes, in cluster-creation order) and a separate one decided what
        // to *connect* it to (a proper MST over every node). Those don't necessarily agree, so a
        // node could be drawn next to one node while its edge actually connected to a different,
        // farther one — exactly what produces confusing, criss-crossing lines. A tree can always
        // be drawn with zero crossings; computing both from the same edge is what makes that hold.
        var connected: Set<Int> = [0]
        builtNodes[0].position = restoredPosition(for: builtNodes[0].id) ?? .zero
        while connected.count < builtNodes.count {
            let candidate = connected.flatMap { left in
                builtNodes.indices
                    .filter { !connected.contains($0) }
                    .map { right in
                        (
                            left,
                            right,
                            semanticDistance(
                                builtNodes[left].embedding,
                                builtNodes[right].embedding
                            )
                        )
                    }
            }
            .min { $0.2 < $1.2 }
            guard let candidate else { break }
            let (parentIndex, childIndex, distance) = candidate
            let parentNode = builtNodes[parentIndex]
            let childID = builtNodes[childIndex].id
            // maximizedGapAngle (inside chainExtensionPosition) also spreads this node away from
            // any siblings already attached to the same parent, rather than a random angle.
            builtNodes[childIndex].position = restoredPosition(for: childID) ?? chainExtensionPosition(
                from: parentNode,
                nodes: builtNodes,
                edges: builtEdges,
                bondLength: mapDistanceToLength(distance)
            )
            builtEdges.append(
                EdgeModel(
                    id: stableUUID(from: "global-cluster-edge:\(parentNode.id):\(childID)"),
                    fromNodeID: parentNode.id,
                    toNodeID: childID,
                    distance: distance,
                    isSuggested: false,
                    // Suggest Connection (generates a suggested midpoint node between two Nodes)
                    // is disabled here for now, matching the persisted per-conversation tree's
                    // edges (rebuildPersistedTree), which already set this false.
                    showSuggestButton: false
                )
            )
            connected.insert(childIndex)
        }
        return (builtNodes, builtEdges)
    }

    private func provisionalClusterLabel(for insights: [InsightModel]) -> String {
        guard let first = insights.first else { return "New Subject" }
        return insights.count > 1 ? "Related Insights" : "Exploring \(first.title)"
    }

    private func requestClusterLabels(for clusters: [NodeModel]) {
        let seedAnchorIDs = Set(localSeedAnchors.map(\.id))
        for cluster in clusters
        where !seedAnchorIDs.contains(cluster.id)
            && generatedClusterLabels[cluster.id] == nil
            && clusterLabelGenerationInFlight.insert(cluster.id).inserted {
            let nodeID = cluster.id
            let subjects = cluster.insights.map { "\($0.title): \($0.definition)" }
            Task { @MainActor in
                let label: String
                do {
                    label = try await model.labelSubject(forTitles: subjects)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    clusterLabelGenerationInFlight.remove(nodeID)
                    return
                }
                clusterLabelGenerationInFlight.remove(nodeID)
                guard !label.isEmpty else { return }
                generatedClusterLabels[nodeID] = label
                persistClusterLabels()
                guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else {
                    return
                }
                nodes[index].conceptLabel = label
                scene.render(nodes: nodes, edges: edges, animated: false)
                requestClusterDefinition(for: nodeID, label: label)
            }
        }
    }

    /// Follows a successful label with a real generated definition of that label (the same
    /// per-term definition call used elsewhere, e.g. tapped highlighted terms), replacing
    /// `DockedNodeTreeCard`'s canned "gathers related insights around..." fallback with an
    /// actual description of the subject.
    private func requestClusterDefinition(for nodeID: UUID, label: String) {
        guard generatedClusterDefinitions[nodeID] == nil else { return }
        Task { @MainActor in
            guard let concept = try? await model.defineTerm(label, in: ConversationContext()),
                  !concept.meaning.isEmpty else {
                return
            }
            generatedClusterDefinitions[nodeID] = concept.meaning
            persistClusterDefinitions()
            guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
            nodes[index].definition = concept.meaning
            if selectedNode?.id == nodeID {
                selectedNode?.definition = concept.meaning
            }
        }
    }

    private func appendPromotedNodes(
        to nodes: inout [NodeModel],
        edges: inout [EdgeModel],
        from embeddedInsights: [InsightModel]
    ) {
        guard !promotedInsightIDs.isEmpty else { return }

        for insightID in promotedInsightIDs {
            guard let sourceIndex = nodes.firstIndex(where: { $0.insights.contains(where: { $0.id == insightID }) }),
                  let insight = nodes[sourceIndex].insights.first(where: { $0.id == insightID }) else {
                continue
            }
            let sourceNode = nodes[sourceIndex]
            let promotedNodeID = promotedNodeID(for: insightID)

            // Turning an insight into a concept spawns 3 relevant child insights around it.
            // Identity-only loading children exist until `requestChildren` resolves. Their IDs
            // remain stable across the generated-content swap so the canvas runs one animation.
            let childInsights = generatedChildInsights[promotedNodeID] ?? (0..<3).map { childIndex in
                InsightModel(
                    id: makeNodeChildID(for: promotedNodeID, index: childIndex),
                    title: "",
                    definition: ""
                )
            }
            if generatedChildInsights[promotedNodeID] == nil {
                requestChildren(for: insight, promotedNodeID: promotedNodeID)
            }

            // If the insight already is its own node (canvas early layout), convert it in
            // place so the insight itself becomes the concept — no duplicate node beside it.
            if sourceNode.id == insightID && sourceNode.insights.count == 1 {
                nodes[sourceIndex].conceptLabel = insight.title
                nodes[sourceIndex].definition = insight.definition
                nodes[sourceIndex].insights = childInsights
                continue
            }

            guard !nodes.contains(where: { $0.id == promotedNodeID }) else { continue }

            // Clustered layout: pull the insight out into its own node, extending the chain from
            // its source node, and remove it from the cluster so it isn't shown twice.
            let chainPos = chainExtensionPosition(from: sourceNode, nodes: nodes, edges: edges)
            nodes[sourceIndex].insights.removeAll { $0.id == insightID }

            let promotedNode = NodeModel(
                id: promotedNodeID,
                conceptLabel: insight.title,
                definition: insight.definition,
                insights: childInsights,
                embedding: insight.embedding ?? [],
                position: restoredPosition(for: promotedNodeID) ?? chainPos,
                isSuggested: false,
                suggestedInsights: nil
            )

            nodes.append(promotedNode)
            edges.append(
                EdgeModel(
                    id: UUID(),
                    fromNodeID: sourceNode.id,
                    toNodeID: promotedNodeID,
                    distance: 0.18,
                    isSuggested: false,
                    showSuggestButton: false
                )
            )
        }
    }

    /// Requests the real Make Node children once per promoted node. Generated content replaces
    /// the identity-only children in place, then publishes readiness after the rebuilt nodes are
    /// available so the canvas can safely begin its camera tour.
    private func requestChildren(for insight: InsightModel, promotedNodeID: UUID) {
        guard childGenerationInFlight.insert(promotedNodeID).inserted else { return }
        Task { @MainActor in
            do {
                try await generateMakeNodeChildren(
                    for: insight,
                    promotedNodeID: promotedNodeID
                )
            } catch {
                cancelMakeNodeGeneration(for: insight.id)
            }
        }
    }

    /// Reserves the generation slot before a queued Make Node task publishes its promoted id.
    /// This prevents the normal tree rebuild from launching an untracked duplicate request.
    func reserveMakeNodeGeneration(for insightID: UUID) {
        childGenerationInFlight.insert(promotedNodeID(for: insightID))
        if !promotedInsightIDs.contains(insightID) {
            promotedInsightIDs.append(insightID)
        }
        rebuildTree()
    }

    func generateReservedMakeNodeChildren(
        for insight: InsightModel
    ) async throws {
        try await generateMakeNodeChildren(
            for: insight,
            promotedNodeID: promotedNodeID(for: insight.id)
        )
    }

    func cancelMakeNodeGeneration(for insightID: UUID) {
        let nodeID = promotedNodeID(for: insightID)
        promotedInsightIDs.removeAll { $0 == insightID }
        childGenerationInFlight.remove(nodeID)
        generatedChildInsights.removeValue(forKey: nodeID)
        persistMakeNodeChildren()
        generatedMakeNodeChildIDs.subtract(
            (0..<3).map { makeNodeChildID(for: nodeID, index: $0) }
        )
        rebuildTree()
    }

    private func generateMakeNodeChildren(
        for insight: InsightModel,
        promotedNodeID: UUID
    ) async throws {
        let sourceConcept = ConceptDefinition(
            word: insight.title,
            partOfSpeech: "",
            pronunciation: "",
            meaning: insight.definition,
            example: ""
        )
        let generated: [ConceptDefinition]
        do {
            generated = try await model.generateChildren(for: sourceConcept)
        } catch {
            childGenerationInFlight.remove(promotedNodeID)
            throw error
        }
        guard !Task.isCancelled, promotedInsightIDs.contains(insight.id) else {
            childGenerationInFlight.remove(promotedNodeID)
            return
        }
        guard generated.count == 3 else {
            childGenerationInFlight.remove(promotedNodeID)
            throw AquinasModelActionError.invalidResponse
        }
        let children = generated.enumerated().map { index, concept in
            return InsightModel(
                id: makeNodeChildID(for: promotedNodeID, index: index),
                title: concept.word,
                definition: concept.meaning
            )
        }
        generatedChildInsights[promotedNodeID] = children
        persistMakeNodeChildren()
        childGenerationInFlight.remove(promotedNodeID)
        rebuildTree()
        generatedMakeNodeChildIDs.formUnion(children.map(\.id))
    }

    /// Appends user-placed midpoint nodes at their pinned positions, each connected by an edge
    /// to every source concept it was spawned from. Runs AFTER the force layout so these nodes
    /// are never relocated.
    private func appendPlacedMidpointNodes(to nodes: inout [NodeModel], edges: inout [EdgeModel]) {
        placedMidpointNodeIDs = Set(placedMidpoints.map { $0.concept.id })
        placedMidpointSources = Dictionary(placedMidpoints.map { ($0.concept.id, $0.sources) }, uniquingKeysWith: { _, latest in latest })
        guard !placedMidpoints.isEmpty else { return }

        for placed in placedMidpoints {
            let nodeID = placed.concept.id
            guard !nodes.contains(where: { $0.id == nodeID }) else { continue }

            let insight = InsightModel(concept: placed.concept)
            let placedNode = NodeModel(
                id: nodeID,
                conceptLabel: placed.concept.word,
                insights: [insight],
                embedding: computeEmbedding(for: "\(insight.title). \(insight.definition)") ?? [],
                position: placed.position,
                isSuggested: false,
                suggestedInsights: nil
            )

            // Connector lines are drawn by the canvas directly to each source insight chip /
            // node concept (see placedMidpointSources), not as generic node-to-node edges.
            nodes.append(placedNode)
        }
    }

    /// Where a newly promoted Node Concept spawns: extending the chain it's growing from, one
    /// link at a time (like a carbon adding onto a lipid tail), rather than orbiting its source
    /// at a semantically-meaningless angle. A node with no existing bonds — the chain's root —
    /// starts growing straight up. A node with two or more existing bonds is a real branch point,
    /// so the new bond bisects the largest open angular gap among them (VSEPR-style maximum
    /// separation). This is a placeholder: once the model drives relation-based folding between
    /// concepts, that will replace this simple maximized-angle continuation.
    ///
    /// A node with EXACTLY one existing bond is the plain-chain case, and deliberately does NOT
    /// use that same maximized-gap rule: with only one angle to separate from, "maximize
    /// separation" is just its exact opposite (180°) — so a simple chain (which is what most
    /// on-device Node-seed growth actually is, one seed per conversation turn) continued dead
    /// straight forever, however many links long. `chainBendDirection` alternates a small bend
    /// left/right at each link instead, so the chain reads as an organic curve/branch rather than
    /// a straight line down the canvas.
    private func chainExtensionPosition(
        from sourceNode: NodeModel,
        nodes: [NodeModel],
        edges: [EdgeModel],
        bondLength: CGFloat = mapDistanceToLength(0.18)   // matches the promoted-node edge's target length
    ) -> CGPoint {
        let occupiedAngles: [CGFloat] = edges.compactMap { edge in
            let neighborID: UUID
            if edge.toNodeID == sourceNode.id { neighborID = edge.fromNodeID }
            else if edge.fromNodeID == sourceNode.id { neighborID = edge.toNodeID }
            else { return nil }
            guard let neighbor = nodes.first(where: { $0.id == neighborID }) else { return nil }
            return atan2(neighbor.position.y - sourceNode.position.y, neighbor.position.x - sourceNode.position.x)
        }

        let angle: CGFloat
        if occupiedAngles.isEmpty {
            angle = -.pi / 2
        } else if occupiedAngles.count == 1 {
            let bendDegrees: CGFloat = 32
            angle = normalizedAngle(occupiedAngles[0] + .pi + chainBendDirection(for: sourceNode.id) * bendDegrees * .pi / 180)
        } else {
            angle = maximizedGapAngle(among: occupiedAngles)
        }

        return CGPoint(
            x: sourceNode.position.x + cos(angle) * bondLength,
            y: sourceNode.position.y + sin(angle) * bondLength
        )
    }

    /// Deterministic left/right alternation for `chainExtensionPosition`'s single-bond bend,
    /// keyed off the growing node's own id (stable across relaunches, unlike an index into
    /// whatever order the current rebuild happens to process nodes in) so the same chain always
    /// curves the same way instead of jittering between rebuilds.
    private func chainBendDirection(for nodeID: UUID) -> CGFloat {
        stableUUID(from: "chain-bend:\(nodeID)").uuid.0 % 2 == 0 ? 1 : -1
    }

    /// The angle that maximizes angular separation from every angle in `angles`: the bisector of
    /// the largest gap between them going around the circle. With one existing angle this is
    /// exactly its opposite (180°); with several, it's the widest open gap — the same "maximum
    /// separation" rule VSEPR uses to spread bonds around an atom.
    private func maximizedGapAngle(among angles: [CGFloat]) -> CGFloat {
        let twoPi = CGFloat.pi * 2
        let sorted = angles.map { normalizedAngle($0) }.sorted()
        guard sorted.count > 1 else { return normalizedAngle(sorted[0] + .pi) }

        var bestGapStart = sorted[0]
        var bestGapSize: CGFloat = 0
        for i in sorted.indices {
            let start = sorted[i]
            let end = (i + 1 < sorted.count ? sorted[i + 1] : sorted[0] + twoPi)
            let gap = end - start
            if gap > bestGapSize {
                bestGapSize = gap
                bestGapStart = start
            }
        }
        return normalizedAngle(bestGapStart + bestGapSize / 2)
    }

    /// Wraps an angle to [0, 2π).
    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        let twoPi = CGFloat.pi * 2
        var a = angle.truncatingRemainder(dividingBy: twoPi)
        if a < 0 { a += twoPi }
        return a
    }

    /// Effective footprint radius of a node (its concept circle + the ring of orbiting chips),
    /// used to keep whole nodes from overlapping during the separation pass.
    private func nodeFootprintRadius(_ node: NodeModel) -> CGFloat {
        if placedMidpointNodeIDs.contains(node.id) { return 70 }   // bare single-chip midpoint
        let visibleInsights = canvasInsights(for: node)
        let longest = visibleInsights.map { $0.title.count }.max() ?? 0
        return insightOrbitRadius(longestTitleChars: longest,
                                  count: visibleInsights.count,
                                  isSuggested: node.isSuggested) + 64   // ring + chip extent
    }

    private func canvasInsights(for node: NodeModel) -> [InsightModel] {
        let members = canvasInsightMembers(
            nodeLabel: node.conceptLabel,
            insights: node.insights,
            preservesMatchingTitle: placedMidpointNodeIDs.contains(node.id)
        )
        return showsAllClusterInsights ? members : Array(members.prefix(6))
    }

    /// Gently pushes apart only the nodes whose footprints overlap, starting from their current
    /// positions. Pinned midpoint nodes stay fixed (neighbors move around them). A no-op when
    /// nothing overlaps, so a settled tree never moves.
    private func separateOverlaps(nodes: [NodeModel]) -> [NodeModel] {
        var working = nodes
        let iterations = 8
        let padding: CGFloat = 24
        let maxStep: CGFloat = 12
        for _ in 0..<iterations {
            var moved = false
            for i in working.indices {
                for j in (i + 1)..<working.count {
                    let aPinned = placedMidpointNodeIDs.contains(working[i].id)
                    let bPinned = placedMidpointNodeIDs.contains(working[j].id)
                    if aPinned && bPinned { continue }

                    var dx = working[j].position.x - working[i].position.x
                    var dy = working[j].position.y - working[i].position.y
                    var dist = hypot(dx, dy)
                    if dist < 0.5 {
                        dx = .random(in: -1...1); dy = .random(in: -1...1); dist = 1
                    }
                    let minDist = nodeFootprintRadius(working[i]) + nodeFootprintRadius(working[j]) + padding
                    guard dist < minDist else { continue }

                    let overlap = minDist - dist
                    let ux = dx / dist, uy = dy / dist
                    func push(_ idx: Int, _ amount: CGFloat) {
                        let s = min(abs(amount), maxStep) * (amount < 0 ? -1 : 1)
                        working[idx].position.x += ux * s
                        working[idx].position.y += uy * s
                    }
                    if aPinned {
                        push(j, overlap)            // only j moves, away from i
                    } else if bPinned {
                        push(i, -overlap)           // only i moves, away from j
                    } else {
                        push(j, overlap / 2)
                        push(i, -overlap / 2)
                    }
                    moved = true
                }
            }
            if !moved { break }   // converged / nothing overlaps
        }
        return working
    }

    private func makeNodeChildID(for nodeID: UUID, index: Int) -> UUID {
        stableUUID(from: "makenode-child:\(nodeID.uuidString):\(index)")
    }

    private func promotedNodeID(for insightID: UUID) -> UUID {
        stableUUID(from: "promoted:\(insightID.uuidString)")
    }

    /// Embedding-driven layout: positions every non-pinned node at its semantic (MDS) target
    /// so on-screen distance reflects semantic distance. Publishes `layoutTargets` (the raw
    /// targets, before overlap separation) and `nodeDepths` for the canvas. Nodes without an
    /// embedding fall back to previous/restored position → graph-neighbor centroid → radial seed.
    private func runSemanticLayout(nodes: [NodeModel], edges: [EdgeModel]) -> [NodeModel] {
        var working = nodes
        guard working.count > 1 else {
            layoutTargets = Dictionary(working.map { ($0.id, $0.position) }, uniquingKeysWith: { _, latest in latest })
            nodeDepths = [:]
            return working
        }

        var previous: [UUID: CGPoint] = [:]
        for node in working {
            previous[node.id] = restoredPosition(for: node.id) ?? node.position
        }

        let result = SemanticLayout.solve(
            nodes: working,
            pinnedIDs: placedMidpointNodeIDs,
            previousPositions: previous
        )

        var targets: [UUID: CGPoint] = [:]
        for index in working.indices {
            let node = working[index]
            if placedMidpointNodeIDs.contains(node.id) {
                targets[node.id] = node.position   // user-pinned: never relocated
                continue
            }
            if let solved = result.positions[node.id] {
                working[index].position = solved
                targets[node.id] = solved
                continue
            }
            // No embedding: keep the previous position if one exists; otherwise sit near
            // the centroid of graph neighbors (small deterministic offset breaks ties),
            // falling back to the radial seed the node already carries.
            if let prev = previous[node.id] {
                targets[node.id] = prev
                working[index].position = prev
            } else {
                let neighborIDs = edges.compactMap { edge -> UUID? in
                    if edge.fromNodeID == node.id { return edge.toNodeID }
                    if edge.toNodeID == node.id { return edge.fromNodeID }
                    return nil
                }
                let neighborPoints = neighborIDs.compactMap { id in
                    result.positions[id] ?? previous[id]
                }
                if !neighborPoints.isEmpty {
                    let cx = neighborPoints.reduce(0) { $0 + $1.x } / CGFloat(neighborPoints.count)
                    let cy = neighborPoints.reduce(0) { $0 + $1.y } / CGFloat(neighborPoints.count)
                    let offset = CGFloat(index % 4) * 40 + 80
                    working[index].position = CGPoint(x: cx + offset, y: cy - offset / 2)
                }
                targets[node.id] = working[index].position
            }
        }

        layoutTargets = targets
        nodeDepths = result.depth
        return working
    }

    /// Nodes appended after the semantic solve (promoted / placed midpoints) anchor at
    /// their spawn position until the next rebuild folds them into the MDS solve proper.
    private func adoptSpawnTargets(for nodes: [NodeModel]) {
        for node in nodes where layoutTargets[node.id] == nil {
            layoutTargets[node.id] = node.position
        }
    }

    /// The position store's one key is shared across every Insight Tree instance — the global
    /// tree and every per-conversation tree — keyed by node id. Always read-modify-write through
    /// this pair (`loadStoredPositions`/`persistPositions`) rather than replacing the value
    /// outright, or one tree's rebuild silently wipes every other tree's saved positions.
    private static func loadStoredPositions(storageKey: String) -> [String: CodablePoint] {
        InsightTreeLocalStateStore.load(
            [String: CodablePoint].self,
            key: storageKey
        ) ?? [:]
    }

    private func restoredPosition(for id: UUID) -> CGPoint? {
        Self.loadStoredPositions(storageKey: positionStoreKey)[id.uuidString]?.cgPoint
    }

    private func persistPositions(_ nodes: [NodeModel]) {
        var positions = Self.loadStoredPositions(storageKey: positionStoreKey)
        for node in nodes {
            positions[node.id.uuidString] = CodablePoint(node.position)
        }
        InsightTreeLocalStateStore.save(positions, key: positionStoreKey)
    }

    private static func loadClusterLabels(storageKey: String) -> [UUID: String] {
        guard let stored = InsightTreeLocalStateStore.load(
            [String: String].self,
            key: storageKey
        ) else { return [:] }
        return stored.reduce(into: [:]) { result, entry in
            guard let id = UUID(uuidString: entry.key) else { return }
            result[id] = entry.value
        }
    }

    private func persistClusterLabels() {
        let stored = Dictionary(
            uniqueKeysWithValues: generatedClusterLabels.map {
                ($0.key.uuidString, $0.value)
            }
        )
        InsightTreeLocalStateStore.save(stored, key: Self.clusterLabelStoreKey)
    }

    private func persistClusterDefinitions() {
        let stored = Dictionary(
            uniqueKeysWithValues: generatedClusterDefinitions.map {
                ($0.key.uuidString, $0.value)
            }
        )
        InsightTreeLocalStateStore.save(stored, key: Self.clusterDefinitionStoreKey)
    }

    private static func loadUUIDMapping(storageKey: String) -> [UUID: UUID] {
        guard let stored = InsightTreeLocalStateStore.load(
            [String: String].self,
            key: storageKey
        ) else { return [:] }
        return stored.reduce(into: [:]) { result, entry in
            guard let key = UUID(uuidString: entry.key), let value = UUID(uuidString: entry.value) else { return }
            result[key] = value
        }
    }

    private func persistInsightClusterAssignments() {
        let stored = Dictionary(
            uniqueKeysWithValues: insightClusterAssignments.map {
                ($0.key.uuidString, $0.value.uuidString)
            }
        )
        InsightTreeLocalStateStore.save(
            stored,
            key: Self.insightClusterAssignmentStoreKey
        )
    }

    /// Placed Midpoints previously lived only in memory — reopening the tree (navigating away and
    /// back re-creates this view model from scratch) dropped `placedMidpoints` back to empty, so
    /// the Midpoint's own auto-bookmarked concept fell through to ordinary clustering instead of
    /// staying a pinned node connected to its two sources. Persisting them the same way positions
    /// and cluster labels already are fixes that.
    private static func loadPlacedMidpoints(storageKey: String) -> [PlacedMidpoint] {
        guard let stored = InsightTreeLocalStateStore.load(
            [CodablePlacedMidpoint].self,
            key: storageKey
        ) else { return [] }
        return stored.map {
            PlacedMidpoint(concept: $0.concept, position: $0.position.cgPoint, sources: $0.sources)
        }
    }

    private func persistPlacedMidpoints() {
        let stored = placedMidpoints.map {
            CodablePlacedMidpoint(concept: $0.concept, position: CodablePoint($0.position), sources: $0.sources)
        }
        InsightTreeLocalStateStore.save(stored, key: placedMidpointStoreKey)
    }

    private static func loadMakeNodeChildren(storageKey: String) -> [UUID: [InsightModel]] {
        guard let stored = InsightTreeLocalStateStore.load(
            [String: [InsightModel]].self,
            key: storageKey
        ) else { return [:] }
        return stored.reduce(into: [:]) { result, entry in
            guard let id = UUID(uuidString: entry.key) else { return }
            result[id] = entry.value
        }
    }

    private func persistMakeNodeChildren() {
        let stored = Dictionary(
            uniqueKeysWithValues: generatedChildInsights.map { ($0.key.uuidString, $0.value) }
        )
        InsightTreeLocalStateStore.save(stored, key: makeNodeChildrenStoreKey)
    }

}

/// Deterministic UUID from a seed string (SHA-256, truncated to the first 16 bytes formatted as a
/// standard UUID) — the same input always yields the same id. Callers that need a stable identity
/// derived from content (a term, a promoted node, a generated child) use this instead of inventing
/// and tracking their own id-generation scheme. See MODEL-INTEGRATION.md: "Persistent IDs:
/// generated by application code, never by either model."
func stableUUID(from seed: String) -> UUID {
    let digest = SHA256.hash(data: Data(seed.utf8))
    let bytes = Array(digest.prefix(16))
    let uuidString = String(
        format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5],
        bytes[6], bytes[7],
        bytes[8], bytes[9],
        bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    )
    return UUID(uuidString: uuidString) ?? UUID()
}

func computeEmbedding(for text: String) -> [Double]? {
    if let embedding = NLEmbedding.sentenceEmbedding(for: .english),
       let vector = embedding.vector(for: text) {
        return vector
    }

    var buckets = Array(repeating: 0.0, count: 64)
    for scalar in text.lowercased().unicodeScalars {
        let index = Int(scalar.value) % buckets.count
        buckets[index] += 1
    }
    return buckets
}

func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count else { return 0 }
    let dot = zip(a, b).map(*).reduce(0, +)
    let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
    let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))
    guard magA > 0, magB > 0 else { return 0 }
    return dot / (magA * magB)
}

func semanticDistance(_ a: [Double], _ b: [Double]) -> Double {
    1.0 - cosineSimilarity(a, b)
}

let nodeNodeMinLength: CGFloat = 360
private let nodeNodeDistanceScale: CGFloat = 320

func mapDistanceToLength(_ distance: Double) -> CGFloat {
    nodeNodeMinLength + CGFloat(max(distance, 0)) * nodeNodeDistanceScale
}

/// Bond length (insight connector radius) from how related an insight is to its parent node.
/// More related (smaller distance) → shorter bond; floored so close chips don't crowd the node.
func insightBondLength(_ distance: Double) -> CGFloat {
    150 + CGFloat(min(max(distance, 0), 1)) * 180   // ~[150, 330]px
}

private func centroid(_ vectors: [[Double]]) -> [Double] {
    guard let first = vectors.first, !first.isEmpty else { return [] }
    var result = Array(repeating: 0.0, count: first.count)
    for vector in vectors where vector.count == first.count {
        for index in vector.indices {
            result[index] += vector[index]
        }
    }
    return result.map { $0 / Double(max(vectors.count, 1)) }
}

private struct CodablePoint: Codable {
    let x: CGFloat
    let y: CGFloat

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}
