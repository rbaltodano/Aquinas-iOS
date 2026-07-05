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
    /// Node IDs for user-placed midpoints. These render as a bare insight chip (no
    /// node-concept circle) pinned at their placed position.
    @Published private(set) var placedMidpointNodeIDs: Set<UUID> = []
    /// For each placed-midpoint node, the sources it connects to (insight chips / node concepts).
    @Published private(set) var placedMidpointSources: [UUID: [MidpointSource]] = [:]
    /// Per-insight bond length (connector radius): shorter = more related to its parent node.
    @Published private(set) var insightBondLengths: [UUID: CGFloat] = [:]
    @Published var selectedNode: NodeModel?
    @Published var selectedSuggestedNode: NodeModel?

    let scene: InsightTreeScene
    private var insights: [InsightModel]
    private var promotedInsightIDs: [UUID]
    private var renderedNodeIDs: Set<UUID> = []
    private var placedMidpoints: [PlacedMidpoint] = []
    private let positionStoreKey = "aquinas.insight-tree.positions.v1"

    /// A user-placed "midpoint" insight: a permanent node pinned at an explicit world
    /// position, connected by an edge to each of the source insights it was spawned from.
    private struct PlacedMidpoint {
        let concept: ConceptDefinition
        let position: CGPoint
        let sources: [MidpointSource]
    }

    init(insights: [ConceptDefinition], promotedInsightIDs: [UUID] = []) {
        self.insights = insights.map { InsightModel(concept: $0) }
        self.promotedInsightIDs = promotedInsightIDs
        scene = InsightTreeScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = UIColor(AquinasTheme.Colors.canvas)
        scene.onNodeTapped = { [weak self] node in
            Task { @MainActor in self?.handleTappedNode(node) }
        }
        scene.onSuggestConnection = { [weak self] edge in
            Task { @MainActor in self?.generateSuggestedNode(for: edge) }
        }

        rebuildTree()
    }

    func updateInsights(_ concepts: [ConceptDefinition], promotedInsightIDs: [UUID]? = nil) {
        insights = concepts.map { InsightModel(concept: $0) }
        if let promotedInsightIDs {
            self.promotedInsightIDs = promotedInsightIDs
        }
        rebuildTree()
    }

    func onInsightSaved(_ insight: InsightModel) {
        var savedInsight = insight
        savedInsight.embedding = savedInsight.embedding ?? computeEmbedding(for: "\(insight.title). \(insight.definition)")
        insights.append(savedInsight)
        if insights.count % 5 == 0 {
            recluster()
        } else {
            rebuildTree()
        }
    }

    func recluster() {
        rebuildTree(forceRelayout: true)
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
    }

    /// Places a new permanent insight node at an explicit world position, pinned (never moved
    /// by the force layout) and connected by a line to each source insight it was spawned from.
    func addPlacedMidpoint(concept: ConceptDefinition, at position: CGPoint, sources: [MidpointSource]) {
        placedMidpoints.append(PlacedMidpoint(concept: concept, position: position, sources: sources))
        rebuildTree()
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
        generateSuggestedNode(for: temporaryEdge)
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
        generateSuggestedNode(for: edge)
    }

    private func handleTappedNode(_ node: NodeModel) {
        if node.isSuggested {
            selectedSuggestedNode = node
        } else {
            selectedNode = node
        }
    }

    private func generateSuggestedNode(for edge: EdgeModel) {
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

        let suggestedNode = NodeModel(
            id: UUID(),
            conceptLabel: makeConceptLabel(from: suggestionInsights.map(\.title)),
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

    private func rebuildTree(forceRelayout: Bool = false) {
        let embeddedInsights = insights.map { insight -> InsightModel in
            var copy = insight
            copy.embedding = copy.embedding ?? computeEmbedding(for: "\(insight.title). \(insight.definition)")
            return copy
        }
        insights = embeddedInsights

        // The children spawned by "Make Node" (deterministic IDs) — used by the canvas to
        // give only these the icon-first loading mask + splay animation.
        makeNodeChildIDs = Set(promotedInsightIDs.flatMap { insightID -> [UUID] in
            let nodeID = promotedNodeID(for: insightID)
            return (0..<3).map { makeNodeChildID(for: nodeID, index: $0) }
        })

        guard embeddedInsights.count >= 5 else {
            var nextNodes = makeEarlyNodes(from: embeddedInsights)
            var nextEdges: [EdgeModel] = []
            appendPromotedNodes(to: &nextNodes, edges: &nextEdges, from: embeddedInsights)
            appendPlacedMidpointNodes(to: &nextNodes, edges: &nextEdges)
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
            return
        }

        let clusters = makeClusters(from: embeddedInsights)
        var nextNodes = clusters.enumerated().map { index, cluster in
            NodeModel(
                id: stableNodeID(for: cluster),
                conceptLabel: makeConceptLabel(from: cluster.map(\.title)),
                insights: cluster,
                embedding: centroid(cluster.compactMap(\.embedding)),
                position: restoredPosition(for: stableNodeID(for: cluster)) ?? radialPosition(index: index, count: clusters.count),
                isSuggested: false,
                suggestedInsights: nil
            )
        }

        var nextEdges: [EdgeModel] = []
        for leftIndex in nextNodes.indices {
            for rightIndex in nextNodes.indices where rightIndex > leftIndex {
                let distance = semanticDistance(nextNodes[leftIndex].embedding, nextNodes[rightIndex].embedding)
                if nextNodes.count <= 2 || distance < 0.58 {
                    nextEdges.append(
                        EdgeModel(
                            id: UUID(),
                            fromNodeID: nextNodes[leftIndex].id,
                            toNodeID: nextNodes[rightIndex].id,
                            distance: distance,
                            isSuggested: false,
                            showSuggestButton: true
                        )
                    )
                }
            }
        }

        if forceRelayout || nextNodes.contains(where: { restoredPosition(for: $0.id) == nil }) {
            nextNodes = runForceLayout(nodes: nextNodes, edges: nextEdges)
            persistPositions(nextNodes)
        }

        appendPromotedNodes(to: &nextNodes, edges: &nextEdges, from: embeddedInsights)
        appendPlacedMidpointNodes(to: &nextNodes, edges: &nextEdges)
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
    }

    /// Bond length per visible insight = relatedness (semantic distance) to its parent node's
    /// centroid embedding. Midpoint nodes (bare center chip) are skipped.
    private func recomputeBondLengths(for nodes: [NodeModel]) {
        var lengths: [UUID: CGFloat] = [:]
        for node in nodes where !placedMidpointNodeIDs.contains(node.id) {
            for insight in node.insights.prefix(6) {
                let dist = semanticDistance(insight.embedding ?? [], node.embedding)
                lengths[insight.id] = insightBondLength(dist)
            }
        }
        insightBondLengths = lengths
    }

    private func makeEarlyNodes(from insights: [InsightModel]) -> [NodeModel] {
        insights.enumerated().map { index, insight in
            NodeModel(
                id: insight.id,
                conceptLabel: insight.title,
                insights: [insight],
                embedding: insight.embedding ?? [],
                position: radialPosition(index: index, count: max(insights.count, 1)),
                isSuggested: false,
                suggestedInsights: nil
            )
        }
    }

    private func makeClusters(from insights: [InsightModel]) -> [[InsightModel]] {
        let categories = [
            "Philosophy": ["philosophy", "aristotle", "virtue", "ethics", "truth", "nihilism", "eudaimonia", "nietzsche"],
            "Theology": ["theology", "aquinas", "augustine", "gospel", "church", "christian", "baptism", "eucharist", "didache", "prayer"],
            "Practice": ["fasting", "ritual", "liturgy", "habit", "manual", "discipline", "community"]
        ]

        var grouped: [String: [InsightModel]] = [:]
        for insight in insights {
            let text = "\(insight.title) \(insight.definition)".lowercased()
            let category = categories.first { _, keywords in
                keywords.contains { text.contains($0) }
            }?.key ?? "Inquiry"
            grouped[category, default: []].append(insight)
        }

        return grouped.values.sorted { $0.count > $1.count }
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
            // Placeholder "New Insight" copy until the model fills them in. IDs are stable so
            // rebuilds don't recreate them (which would re-trigger their load animation).
            let childInsights = (0..<3).map { childIndex in
                InsightModel(
                    id: makeNodeChildID(for: promotedNodeID, index: childIndex),
                    title: "New Insight",
                    definition: ""
                )
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

            // Clustered layout: pull the insight out into its own node positioned where its
            // chip was orbiting, and remove it from the cluster so it isn't shown twice.
            let visible = Array(sourceNode.insights.prefix(6))
            let orbitIndex = visible.firstIndex(where: { $0.id == insightID }) ?? 0
            let orbitPos = insightOrbitPosition(node: sourceNode, index: orbitIndex, count: min(sourceNode.insights.count, 6))
            nodes[sourceIndex].insights.removeAll { $0.id == insightID }

            let promotedNode = NodeModel(
                id: promotedNodeID,
                conceptLabel: insight.title,
                definition: insight.definition,
                insights: childInsights,
                embedding: insight.embedding ?? [],
                position: restoredPosition(for: promotedNodeID) ?? orbitPos,
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

    /// Appends user-placed midpoint nodes at their pinned positions, each connected by an edge
    /// to every source concept it was spawned from. Runs AFTER the force layout so these nodes
    /// are never relocated.
    private func appendPlacedMidpointNodes(to nodes: inout [NodeModel], edges: inout [EdgeModel]) {
        placedMidpointNodeIDs = Set(placedMidpoints.map { $0.concept.id })
        placedMidpointSources = Dictionary(uniqueKeysWithValues: placedMidpoints.map { ($0.concept.id, $0.sources) })
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

    /// Orbit position of an insight chip around its node — mirrors the canvas layout
    /// so a promoted node lands exactly where its chip was.
    private func insightOrbitPosition(node: NodeModel, index: Int, count: Int) -> CGPoint {
        let clampedCount = max(count, 1)
        let angle = (CGFloat(index) / CGFloat(clampedCount)) * (.pi * 2) + .pi / 8
        let insightID = index < node.insights.count ? node.insights[index].id : nil
        let radius = insightID.flatMap { insightBondLengths[$0] } ?? 190
        return CGPoint(x: node.position.x + cos(angle) * radius, y: node.position.y + sin(angle) * radius)
    }

    /// Effective footprint radius of a node (its concept circle + the ring of orbiting chips),
    /// used to keep whole nodes from overlapping during the separation pass.
    private func nodeFootprintRadius(_ node: NodeModel) -> CGFloat {
        if placedMidpointNodeIDs.contains(node.id) { return 70 }   // bare single-chip midpoint
        let longest = node.insights.prefix(6).map { $0.title.count }.max() ?? 0
        return insightOrbitRadius(longestTitleChars: longest,
                                  count: min(node.insights.count, 6),
                                  isSuggested: node.isSuggested) + 64   // ring + chip extent
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
        let digest = SHA256.hash(data: Data("makenode-child:\(nodeID.uuidString):\(index)".utf8))
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

    private func promotedNodeID(for insightID: UUID) -> UUID {
        let digest = SHA256.hash(data: Data("promoted:\(insightID.uuidString)".utf8))
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

    private func runForceLayout(nodes: [NodeModel], edges: [EdgeModel]) -> [NodeModel] {
        var working = nodes
        guard working.count > 1 else { return working }

        for _ in 0..<200 {
            var deltas = Dictionary(uniqueKeysWithValues: working.map { ($0.id, CGVector.zero) })

            for left in working.indices {
                for right in working.indices where right != left {
                    let dx = working[left].position.x - working[right].position.x
                    let dy = working[left].position.y - working[right].position.y
                    let distance = max(60, hypot(dx, dy))
                    let force = 3600 / (distance * distance)
                    deltas[working[left].id]?.dx += (dx / distance) * force
                    deltas[working[left].id]?.dy += (dy / distance) * force
                }
            }

            for edge in edges {
                guard let fromIndex = working.firstIndex(where: { $0.id == edge.fromNodeID }),
                      let toIndex = working.firstIndex(where: { $0.id == edge.toNodeID }) else {
                    continue
                }
                let dx = working[toIndex].position.x - working[fromIndex].position.x
                let dy = working[toIndex].position.y - working[fromIndex].position.y
                let distance = max(1, hypot(dx, dy))
                let targetLength = mapDistanceToLength(edge.distance)
                let pull = (distance - targetLength) * (1 - edge.distance) * 0.003
                deltas[working[fromIndex].id]?.dx += dx * pull
                deltas[working[fromIndex].id]?.dy += dy * pull
                deltas[working[toIndex].id]?.dx -= dx * pull
                deltas[working[toIndex].id]?.dy -= dy * pull
            }

            for index in working.indices {
                let delta = deltas[working[index].id] ?? .zero
                working[index].position.x += max(-4, min(4, delta.dx))
                working[index].position.y += max(-4, min(4, delta.dy))
            }
        }

        return working
    }

    private func radialPosition(index: Int, count: Int) -> CGPoint {
        let radius = count <= 2 ? CGFloat(260) : CGFloat(340)
        let angle = (CGFloat(index) / CGFloat(max(count, 1))) * (.pi * 2)
        return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
    }

    private func stableNodeID(for insights: [InsightModel]) -> UUID {
        insights.sorted { $0.title < $1.title }.first?.id ?? UUID()
    }

    private func restoredPosition(for id: UUID) -> CGPoint? {
        guard let data = UserDefaults.standard.data(forKey: positionStoreKey),
              let positions = try? JSONDecoder().decode([String: CodablePoint].self, from: data),
              let point = positions[id.uuidString] else {
            return nil
        }
        return point.cgPoint
    }

    private func persistPositions(_ nodes: [NodeModel]) {
        let positions = Dictionary(uniqueKeysWithValues: nodes.map {
            ($0.id.uuidString, CodablePoint($0.position))
        })
        if let data = try? JSONEncoder().encode(positions) {
            UserDefaults.standard.set(data, forKey: positionStoreKey)
        }
    }

    private func makeConceptLabel(from titles: [String]) -> String {
        let stopWords: Set<String> = ["the", "and", "of", "to", "in", "a", "an", "is", "for", "on", "with", "from"]
        let words = titles
            .flatMap { $0.lowercased().split(separator: " ") }
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 3 && !stopWords.contains($0) }

        let ranked = Dictionary(grouping: words, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
            .map { $0.0.capitalized }

        return ranked.isEmpty ? "Inquiry" : ranked.joined(separator: " ")
    }
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

func mapDistanceToLength(_ distance: Double) -> CGFloat {
    80 + CGFloat(distance) * 320
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
