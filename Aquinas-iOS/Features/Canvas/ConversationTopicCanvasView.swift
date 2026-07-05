//
//  ConversationTopicCanvasView.swift
//  Aquinas-iOS
//
//  Conversation topic canvas — each user question becomes a bubble on a freely
//  pannable world-space canvas with the InsightTree dot-grid background.
//  Open: swipe right-to-left from the right edge of any branch.
//  Close: swipe left-to-right from the left edge.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Data Model

struct ConversationTopicNode: Identifiable, Equatable {
    let id: String              // stable: "\(branchID.uuidString)-\(questionIndex)"
    let branchID: UUID
    let questionIndex: Int
    let title: String
    let summary: String
    let insights: [ConceptDefinition]
    let parentID: String?       // parent topic node id (nil for first node in root branch)
    var position: CGPoint       // world-space centre
    var forkLabel: String?      // shown on the horizontal connector into this branch's first node
    var forkInsight: ConceptDefinition?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

private struct ConversationTopicOverview {
    let title: String
    let summary: String
    let position: CGPoint
}

// MARK: - Node Builder

private let kOverviewNodeID = "conversation-overview"
private let kTopicTimelineX: CGFloat = 0
private let kTopicFirstNodeY: CGFloat = -270
private let kTopicNodeStep: CGFloat = 300
private let kTopicOverviewApproxHeight: CGFloat = 112
private let kTopicBubbleApproxHeight: CGFloat = 204
private let kTopicConnectorLength: CGFloat = 48
/// Horizontal world-space distance between column centres.
/// Gap = kColumnWidth − kBubbleMaxWidth (300) = 320 pt, giving 8 pt padding on each
/// side around the 304 pt connector element (48 pt line + 8 + label + 8 + 48 pt line).
private let kColumnWidth: CGFloat = 620

private func buildConversationTopicNodes(
    from branches: [ChatBranch],
    savedInsights: [ConceptDefinition]
) -> [ConversationTopicNode] {
    var nodes: [ConversationTopicNode] = []
    // branchID → ordered nodes for that branch (used to align fork Y)
    var branchNodes: [UUID: [ConversationTopicNode]] = [:]
    // branchID → assigned column index
    var branchToCol: [UUID: Int] = [:]
    // parentBranchID → number of direct forks already placed (for sibling offsets)
    var childCountPerParent: [UUID: Int] = [:]
    // count of nodes placed in column 0 (root) so far
    var col0Count = 0

    for branch in branches {
        // ── Column assignment ────────────────────────────────────────────────
        let col: Int
        // For forks: ID of the parent node that should connect horizontally
        let forkParentNodeID: String?
        // For forks: Y of that parent node (this branch's first node aligns here)
        let forkOriginY: CGFloat

        if let parentID = branch.parentBranchID {
            let parentCol = branchToCol[parentID] ?? 0
            let siblingN  = childCountPerParent[parentID] ?? 0
            col = parentCol + 1 + siblingN
            childCountPerParent[parentID] = siblingN + 1

            let pNodes    = branchNodes[parentID] ?? []
            let targetIdx = branch.parentResponseIndex ?? 0
            let alignNode = pNodes.first(where: { $0.questionIndex == targetIdx }) ?? pNodes.last
            forkParentNodeID = alignNode?.id ?? kOverviewNodeID
            forkOriginY      = alignNode?.position.y ?? kTopicFirstNodeY
        } else {
            col              = 0
            forkParentNodeID = nil
            forkOriginY      = 0   // unused for root column
        }

        branchToCol[branch.id] = col
        let columnX = CGFloat(col) * kColumnWidth

        // ── Build nodes for this branch ──────────────────────────────────────
        var questionCount = 0
        var i = 0
        let blocks = branch.activeChatBlocks
        // prevID: chains nodes within the same branch vertically.
        // First node of a fork points to the parent branch node (horizontal link).
        // First node of root branch points to the overview node.
        var prevID: String = forkParentNodeID ?? kOverviewNodeID
        var bNodes: [ConversationTopicNode] = []
        // Label carried only by the first node of a fork branch
        var isFirstForkNode = (col > 0)

        func nodeY() -> CGFloat {
            col == 0
                ? kTopicFirstNodeY - CGFloat(col0Count) * kTopicNodeStep
                : forkOriginY - CGFloat(questionCount) * kTopicNodeStep
        }

        func appendNode(id: String, title: String, summary: String, forkLabel: String? = nil) {
            let responseLower = summary.lowercased()
            let matched = savedInsights.filter {
                responseLower.contains($0.word.lowercased())
            }.uniquedByWord()

            let node = ConversationTopicNode(
                id: id,
                branchID: branch.id,
                questionIndex: questionCount,
                title: title,
                summary: summary,
                insights: matched,
                parentID: prevID,
                position: CGPoint(x: columnX, y: nodeY()),
                forkLabel: forkLabel,
                forkInsight: isFirstForkNode ? branch.startingConcept : nil
            )
            nodes.append(node)
            bNodes.append(node)
            if col == 0 { col0Count += 1 }
            prevID = id
            questionCount += 1
        }

        let topQuestion = branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if branch.topQuestionSubmitted, !topQuestion.isEmpty {
            let responseText: String
            if !blocks.isEmpty, case .text(let rt) = blocks[0] {
                responseText = rt; i = 1
            } else {
                responseText = ""
            }
            let label: String? = isFirstForkNode
                ? (branch.startingConcept?.word.capitalized ?? branch.generatedBranchTitle)
                : nil
            appendNode(
                id: "\(branch.id.uuidString)-\(questionCount)",
                title: makeTopicTitle(from: topQuestion),
                summary: responseText,
                forkLabel: label
            )
            isFirstForkNode = false
        }

        while i < blocks.count {
            guard case .user(let questionText, _, _) = blocks[i] else { i += 1; continue }
            let responseText: String
            if i + 1 < blocks.count, case .text(let rt) = blocks[i + 1] {
                responseText = rt
            } else {
                responseText = ""
            }
            appendNode(
                id: "\(branch.id.uuidString)-\(questionCount)",
                title: makeTopicTitle(from: questionText),
                summary: responseText
            )
            i += 2
        }

        if questionCount == 0 {
            let label: String? = col > 0
                ? (branch.startingConcept?.word.capitalized ?? branch.generatedBranchTitle)
                : nil
            let y = col == 0
                ? kTopicFirstNodeY - CGFloat(col0Count) * kTopicNodeStep
                : forkOriginY
            let node = ConversationTopicNode(
                id: "\(branch.id.uuidString)-0",
                branchID: branch.id,
                questionIndex: 0,
                title: branch.generatedBranchTitle ?? "New Conversation",
                summary: "",
                insights: [],
                parentID: prevID,
                position: CGPoint(x: columnX, y: y),
                forkLabel: label,
                forkInsight: col > 0 ? branch.startingConcept : nil
            )
            nodes.append(node)
            bNodes.append(node)
            if col == 0 { col0Count += 1 }
        }

        branchNodes[branch.id] = bNodes
    }

    return nodes
}

private func buildConversationTopicOverview(
    title conversationTitle: String,
    from branches: [ChatBranch]
) -> ConversationTopicOverview {
    let cleanTitle = conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallbackTitle = firstQuestion(in: branches).map(makeTopicTitle(from:)) ?? "New Conversation"
    let title = cleanTitle.isEmpty || cleanTitle == "New Conversation" ? fallbackTitle : cleanTitle

    let questions = branches.flatMap { branch in
        branch.activeChatBlocks.compactMap { block -> String? in
            guard case .user(let text, _, _) = block else { return nil }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    .filter { !$0.isEmpty }

    let summary: String
    if questions.isEmpty {
        summary = "Conversation topics and their summaries will appear below as the discussion develops."
    } else {
        summary = truncatedTopicText(questions.prefix(2).joined(separator: " "), maxLength: 132)
    }

    return ConversationTopicOverview(
        title: title,
        summary: summary,
        position: CGPoint(x: kTopicTimelineX, y: 0)
    )
}

private func firstQuestion(in branches: [ChatBranch]) -> String? {
    for branch in branches {
        for block in branch.activeChatBlocks {
            if case .user(let text, _, _) = block {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
    }

    return nil
}

private func makeTopicTitle(from text: String) -> String {
    let stripped = text.filter { !"?!.,;:".contains($0) }
    let titleWords = stripped
        .split(separator: " ")
        .filter { !$0.isEmpty }
        .prefix(6)
        .map(String.init)

    return titleWords.isEmpty ? "Question" : titleWords.joined(separator: " ")
}

private func truncatedTopicText(_ text: String, maxLength: Int) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > maxLength else { return trimmed }

    let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
    return String(trimmed[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
}

// MARK: - Camera

private struct TopicCanvasCamera {
    var scale: CGFloat
    var offset: CGSize

    /// World-space Y grows upward; screen Y grows downward — matches InsightTreeCamera exactly.
    func worldToScreen(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width  / 2 + point.x *  scale + offset.width,
            y: size.height / 2 - point.y *  scale + offset.height
        )
    }
}

// MARK: - Connector helpers

/// A screen-space connector segment between two canvas nodes.
/// Keeping it as an identifiable struct lets ForEach give each line stable
/// SwiftUI identity, so `.position()` animates frame-by-frame during momentum
/// instead of jumping to the final camera position in one render.
private struct ConnectorDescriptor: Identifiable {
    let id: String          // "connector-<childNodeID>"
    let start: CGPoint
    let end: CGPoint
    var label: String? = nil
    var insight: ConceptDefinition? = nil
    var isHorizontal: Bool = false
    var midWorld: CGPoint = .zero   // world-space midpoint for zoom-aware label positioning
}

private func buildConnectorDescriptors(
    nodes: [ConversationTopicNode],
    overview: ConversationTopicOverview,
    camera: TopicCanvasCamera,
    size: CGSize,
    nodeHeights: [String: CGFloat]
) -> [ConnectorDescriptor] {
    let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    var result: [ConnectorDescriptor] = []

    for node in nodes {
        guard let parentID = node.parentID else { continue }

        let parentPosition: CGPoint
        let parentHalfHeight: CGFloat
        if parentID == kOverviewNodeID {
            parentPosition = overview.position
            parentHalfHeight = kTopicOverviewApproxHeight / 2
        } else if let parent = byID[parentID] {
            parentPosition = parent.position
            // Use the measured height when available so connectors start at the
            // actual bottom edge of an expanded bubble rather than the default estimate.
            parentHalfHeight = (nodeHeights[parent.id] ?? kTopicBubbleApproxHeight) / 2
        } else {
            continue
        }

        let isHorizontal = abs(node.position.x - parentPosition.x) > 10

        let startWorld: CGPoint
        let endWorld: CGPoint

        if isHorizontal {
            // Horizontal connector: same Y as the fork node, spanning the gap between columns.
            let y = node.position.y
            let margin: CGFloat = 8
            startWorld = CGPoint(x: parentPosition.x + kBubbleMaxWidth / 2 + margin, y: y)
            endWorld   = CGPoint(x: node.position.x  - kBubbleMaxWidth / 2 - margin, y: y)
        } else {
            // Vertical connector follows the measured edges of both cards.
            let parentBottomY    = parentPosition.y - parentHalfHeight
            let childHalfHeight  = (nodeHeights[node.id] ?? kTopicBubbleApproxHeight) / 2
            let childTopY        = node.position.y + childHalfHeight
            let connectorCenterY = (parentBottomY + childTopY) / 2
            startWorld = CGPoint(x: parentPosition.x, y: connectorCenterY + kTopicConnectorLength / 2)
            endWorld   = CGPoint(x: node.position.x,  y: connectorCenterY - kTopicConnectorLength / 2)
        }

        let midWorld = isHorizontal
            ? CGPoint(x: (parentPosition.x + node.position.x) / 2, y: node.position.y)
            : .zero

        result.append(ConnectorDescriptor(
            id: "connector-\(node.id)",
            start: camera.worldToScreen(startWorld, in: size),
            end:   camera.worldToScreen(endWorld,   in: size),
            label: isHorizontal ? node.forkLabel : nil,
            insight: isHorizontal ? node.forkInsight : nil,
            isHorizontal: isHorizontal,
            midWorld: midWorld
        ))
    }

    return result
}

/// A thin 1-pt line between two screen-space points.
/// Rendered as a sized+rotated Rectangle so SwiftUI can animate `.position()`
/// and `.frame()` smoothly via the normal spring animation engine.
private struct ConnectorLineView: View {
    let start: CGPoint
    let end: CGPoint

    @Environment(\.colorScheme) private var colorScheme

    private var connectorColor: Color {
        colorScheme == .dark
            ? Color(red: 1,    green: 0.98, blue: 0.94).opacity(0.18)
            : Color(red: 0.13, green: 0.06, blue: 0   ).opacity(0.18)
    }

    var body: some View {
        let dx     = end.x - start.x
        let dy     = end.y - start.y
        let length = max(hypot(dx, dy), 0)
        let center = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let angle  = Angle(radians: atan2(Double(dy), Double(dx)))

        Rectangle()
            .fill(connectorColor)
            .frame(width: length, height: 1)
            .rotationEffect(angle)
            .position(center)
    }
}

/// A 48 pt horizontal line with a traveling gradient capsule pulse.
private struct TravelingPulseLine: View {
    let width: CGFloat
    let progress: Double

    @Environment(\.colorScheme) private var colorScheme

    private var baseColor: Color {
        colorScheme == .dark
            ? Color(red: 1,    green: 0.98, blue: 0.94).opacity(0.18)
            : Color(red: 0.13, green: 0.06, blue: 0   ).opacity(0.18)
    }

    private var pulseColor: Color { Color(red: 0.53, green: 0.49, blue: 0.31) }

    var body: some View {
        let segmentWidth = 0.22
        let segStart = CGFloat(max(0, progress - segmentWidth))
        let segEnd   = CGFloat(min(progress, 1.0))

        ZStack(alignment: .leading) {
            Rectangle()
                .fill(baseColor)
                .frame(width: width, height: 1)

            if segEnd > segStart {
                let centerPct = (segStart + segEnd) / 2
                let segLen    = max(width * (segEnd - segStart), 2)

                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: pulseColor.opacity(0), location: 0),
                                .init(color: pulseColor,            location: 0.5),
                                .init(color: pulseColor.opacity(0), location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: segLen, height: 1)
                    .offset(x: width * centerPct - segLen / 2)
                    .opacity(0.5)
            }
        }
        .frame(width: width, height: 1)
        .clipped()
    }
}

// MARK: - Node Height Preference Key

private struct NodeHeightKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Main Canvas View

struct ConversationTopicCanvasView: View {
    let conversationTitle: String
    let branches: [ChatBranch]
    @Binding var savedInsights: [ConceptDefinition]
    var onClose: () -> Void

    // Camera state
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var liveDrag: CGSize = .zero
    @State private var pinchStartScale: CGFloat?
    @State private var pinchStartOffset: CGSize?
    @State private var lastDragEndedAt: Date = .distantPast
    @State private var isDraggingCanvas: Bool = false
    @State private var rippleTrigger: RippleTrigger? = nil
    @State private var hasAppeared: Bool = false

    // Bubble expansion state
    @State private var selectedNodeID: String? = nil
    @State private var expandedNodeIDs: Set<String> = []
    @State private var insightChipExpandedIDs: Set<String> = []
    @State private var activeInsight: ConceptDefinition? = nil
    @State private var dockedBridgeInsight: ConceptDefinition? = nil
    // Measured world-space heights reported by each rendered bubble.
    @State private var nodeHeights: [String: CGFloat] = [:]

    private var activeScale: CGFloat { min(max(scale, 0.22), 2.6) }

    private var activeOffset: CGSize {
        CGSize(width: offset.width + liveDrag.width,
               height: offset.height + liveDrag.height)
    }

    private var topicNodes: [ConversationTopicNode] {
        buildConversationTopicNodes(from: branches, savedInsights: savedInsights)
    }

    private var topicOverview: ConversationTopicOverview {
        buildConversationTopicOverview(title: conversationTitle, from: branches)
    }

    private var canAcceptTap: Bool {
        !isDraggingCanvas && Date().timeIntervalSince(lastDragEndedAt) > 0.16
    }

    var body: some View {
        GeometryReader { proxy in
            let size     = proxy.size
            let camera   = TopicCanvasCamera(scale: activeScale, offset: activeOffset)
            let nodes    = withAdjustedPositions(topicNodes)
            let overview = topicOverview
            let connectors = buildConnectorDescriptors(nodes: nodes, overview: overview,
                                                       camera: camera, size: size,
                                                       nodeHeights: nodeHeights)

            ZStack {
                AquinasTheme.Colors.canvas.ignoresSafeArea()

                // Pass activeOffset as a single value so the background and nodes
                // share the same source of truth. Animatable interpolates it
                // frame-by-frame during momentum; live-drag changes are immediate
                // because they don't go through withAnimation.
                AnimatedDotGridBackground(
                    settledOffset: activeOffset,
                    settledScale:  activeScale,
                    dragOffset:    .zero,
                    ripples:       rippleTrigger.map { [$0] } ?? []
                )
                .ignoresSafeArea()
                .opacity(hasAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.6), value: hasAppeared)

                // Connector lines — rendered as positioned Views so SwiftUI's
                // animation engine can interpolate `.position()` frame-by-frame
                // during momentum (Canvas would jump to the final position immediately).
                ForEach(connectors) { conn in
                    if conn.isHorizontal, let label = conn.label {
                        // World-space width available between the two bubble edges,
                        // minus 8 pt padding on each side.
                        let connectorWidth = kColumnWidth - kBubbleMaxWidth - 16
                        Button {
                            guard canAcceptTap, let insight = conn.insight else { return }
                            playTopicBubbleHaptic()
                            focusTopic(at: conn.midWorld, in: size)
                            rippleTrigger = RippleTrigger(
                                worldOrigin: conn.midWorld,
                                startTime: Date().timeIntervalSinceReferenceDate
                            )
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                dockedBridgeInsight = insight
                            }
                        } label: {
                            TimelineView(.animation) { tl in
                                let progress = tl.date.timeIntervalSinceReferenceDate
                                    .truncatingRemainder(dividingBy: 2.0) / 2.0
                                HStack(spacing: 8) {
                                    TravelingPulseLine(width: 48, progress: progress)
                                    HStack(spacing: 6) {
                                        Image(systemName: "text.bubble.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(AquinasTheme.Colors.darkGreen)
                                        Text(label)
                                            .font(.figtreeHeading2)
                                            .foregroundColor(AquinasTheme.Colors.darkGreen)
                                            .lineLimit(1)
                                    }
                                    TravelingPulseLine(width: 48, progress: progress)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(conn.insight == nil)
                        .frame(width: connectorWidth)
                        .scaleEffect(camera.scale)
                        .position(camera.worldToScreen(conn.midWorld, in: size))
                    } else {
                        ConnectorLineView(start: conn.start, end: conn.end)
                            .allowsHitTesting(false)
                    }
                }

                conversationOverviewView(overview, camera: camera, size: size)

                ForEach(nodes) { node in
                    topicBubbleView(node, camera: camera, size: size)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(panGesture)
            .simultaneousGesture(zoomGesture(in: size))
            .gesture(closeSwipeGesture)
            .onPreferenceChange(NodeHeightKey.self) { heights in
                nodeHeights = heights
            }
            .onAppear {
                hasAppeared = true
                initCamera(for: overview, in: size)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let dockedBridgeInsight {
                DockedInsightTreeCard(insight: InsightModel(concept: dockedBridgeInsight))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                    .transition(.scale(scale: 0.35, anchor: .bottom).combined(with: .opacity))
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onEnded { value in
                                guard value.translation.height > 80
                                    || value.predictedEndTranslation.height > 140 else { return }
                                playTopicBubbleHaptic()
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    self.dockedBridgeInsight = nil
                                }
                            }
                    )
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: dockedBridgeInsight?.id)
        .sheet(item: $activeInsight) { insight in
            ConceptSheetContent(
                concept: insight,
                collectedDefinitions: $savedInsights
            )
            .presentationDetents([.height(340), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
        }
    }

    // MARK: - Bubble

    private func conversationOverviewView(
        _ overview: ConversationTopicOverview,
        camera: TopicCanvasCamera,
        size: CGSize
    ) -> some View {
        ConversationTopicOverviewView(
            title: overview.title,
            summary: overview.summary
        )
        .scaleEffect(camera.scale)
        .position(camera.worldToScreen(overview.position, in: size))
    }

    @ViewBuilder
    private func topicBubbleView(
        _ node: ConversationTopicNode,
        camera: TopicCanvasCamera,
        size: CGSize
    ) -> some View {
        let screenPos        = camera.worldToScreen(node.position, in: size)
        let isSelected       = selectedNodeID == node.id
        let isExpanded       = expandedNodeIDs.contains(node.id)
        let insightsExpanded = insightChipExpandedIDs.contains(node.id)

        TopicBubbleView(
            node: node,
            isSelected: isSelected,
            isExpanded: isExpanded,
            insightsExpanded: insightsExpanded,
            onTapBubble: {
                guard canAcceptTap else { return }
                selectTopic(node, in: size)
            },
            onTapSummary: {
                guard canAcceptTap else { return }
                guard isSelected else {
                    selectTopic(node, in: size)
                    return
                }

                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    if isExpanded {
                        expandedNodeIDs.remove(node.id)
                        insightChipExpandedIDs.remove(node.id)
                    } else {
                        expandedNodeIDs.insert(node.id)
                    }
                }
            },
            onTapInsightChip: {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    if insightsExpanded {
                        insightChipExpandedIDs.remove(node.id)
                    } else {
                        insightChipExpandedIDs.insert(node.id)
                    }
                }
            },
            onTapInsight: { insight in
                activeInsight = insight
            }
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: NodeHeightKey.self,
                    value: [node.id: geo.size.height]
                )
            }
        )
        .scaleEffect(camera.scale)
        .position(screenPos)
    }

    // MARK: - Position adjustment

    /// Shifts nodes downward (more-negative world Y) so that expanded bubbles push
    /// subsequent nodes in the same column rather than overlapping them.
    private func withAdjustedPositions(_ nodes: [ConversationTopicNode]) -> [ConversationTopicNode] {
        var result = nodes
        let columnXValues = Set(nodes.map { $0.position.x })
        for x in columnXValues {
            // Collect indices for this column, sorted top-to-bottom (descending Y).
            let indices = result.indices
                .filter { result[$0].position.x == x }
                .sorted { result[$0].position.y > result[$1].position.y }
            var extraOffset: CGFloat = 0
            for i in indices {
                result[i].position.y -= extraOffset
                let measuredH = nodeHeights[result[i].id] ?? kTopicBubbleApproxHeight
                extraOffset += max(0, measuredH - kTopicBubbleApproxHeight)
            }
        }
        return result
    }

    // MARK: - Camera initialisation

    private func initCamera(for overview: ConversationTopicOverview, in size: CGSize) {
        let targetScreenY = size.height * 0.20
        offset = CGSize(
            width: -overview.position.x * scale,
            height: targetScreenY - size.height / 2 + overview.position.y * scale
        )
    }

    private func selectTopic(_ node: ConversationTopicNode, in size: CGSize) {
        selectedNodeID = node.id
        playTopicBubbleHaptic()
        focusTopic(at: node.position, in: size)
        rippleTrigger = RippleTrigger(
            worldOrigin: node.position,
            startTime: Date().timeIntervalSinceReferenceDate
        )
    }

    private func focusTopic(at worldPosition: CGPoint, in size: CGSize) {
        let nextScale = min(max(scale, 1.15), 2.6)
        let target = CGPoint(x: size.width / 2, y: size.height * 0.5)

        withAnimation(.spring(response: 0.58, dampingFraction: 0.64, blendDuration: 0.08)) {
            scale = nextScale
            offset = CGSize(
                width: target.x - size.width / 2 - (worldPosition.x * nextScale),
                height: target.y - size.height / 2 + (worldPosition.y * nextScale)
            )
        }
    }

    private func playTopicBubbleHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.65)
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($liveDrag) { value, state, _ in
                state = value.translation
            }
            .onChanged { value in
                if hypot(value.translation.width, value.translation.height) > 8,
                   !isDraggingCanvas {
                    isDraggingCanvas = true
                    if dockedBridgeInsight != nil {
                        playTopicBubbleHaptic()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            dockedBridgeInsight = nil
                        }
                    }
                }
            }
            .onEnded { value in
                offset.width  += value.translation.width
                offset.height += value.translation.height
                if hypot(value.translation.width, value.translation.height) > 8 {
                    lastDragEndedAt = Date()
                }
                let decay: CGFloat = 0.13
                withAnimation(.spring(response: 0.65, dampingFraction: 0.88)) {
                    offset.width  += value.velocity.width  * decay
                    offset.height += value.velocity.height * decay
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    isDraggingCanvas = false
                }
            }
    }

    private func zoomGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if pinchStartScale == nil {
                    pinchStartScale  = scale
                    pinchStartOffset = offset
                }
                let initS = pinchStartScale  ?? scale
                let initO = pinchStartOffset ?? offset
                let next  = min(max(initS * pow(value.magnification, 0.72), 0.22), 2.6)
                let anchor = CGPoint(x: value.startAnchor.x * size.width,
                                     y: value.startAnchor.y * size.height)
                scale  = next
                offset = topicOffsetKeepingAnchor(anchor, from: initO,
                                                  initScale: initS, nextScale: next, in: size)
            }
            .onEnded { value in
                let initS = pinchStartScale  ?? scale
                let initO = pinchStartOffset ?? offset
                let next  = min(max(initS * pow(value.magnification, 0.72), 0.22), 2.6)
                let anchor = CGPoint(x: value.startAnchor.x * size.width,
                                     y: value.startAnchor.y * size.height)
                scale  = next
                offset = topicOffsetKeepingAnchor(anchor, from: initO,
                                                  initScale: initS, nextScale: next, in: size)
                pinchStartScale  = nil
                pinchStartOffset = nil
            }
    }

    /// Left-edge swipe returns to branch mode.
    private var closeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let fromLeftEdge = value.startLocation.x < 48
                let swipingRight = value.translation.width > 56
                let moreHoriz    = abs(value.translation.width) > abs(value.translation.height) * 1.4
                if fromLeftEdge && swipingRight && moreHoriz {
                    onClose()
                }
            }
    }

    // Mirrors InsightTreeCanvasView.offsetKeeping exactly.
    private func topicOffsetKeepingAnchor(
        _ anchor: CGPoint,
        from initOffset: CGSize,
        initScale: CGFloat,
        nextScale: CGFloat,
        in size: CGSize
    ) -> CGSize {
        let cx     = anchor.x - size.width  / 2
        let cy     = anchor.y - size.height / 2
        let worldX = (cx - initOffset.width)   / initScale
        let worldY = (initOffset.height - cy)  / initScale
        return CGSize(
            width:  cx - worldX * nextScale,
            height: cy + worldY * nextScale
        )
    }
}

// MARK: - Topic Bubble View

private let kBubbleMaxWidth: CGFloat = 300

private struct ConversationTopicOverviewView: View {
    let title: String
    let summary: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.custom("LibreBaskerville-Regular", size: 28))
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(summary)
                .font(.custom("Figtree-Regular", size: 14))
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .lineSpacing(3)
        }
        .frame(width: 352)
    }
}

struct TopicBubbleView: View {
    let node: ConversationTopicNode
    let isSelected: Bool
    let isExpanded: Bool
    let insightsExpanded: Bool
    var onTapBubble: () -> Void
    var onTapSummary: () -> Void
    var onTapInsightChip: () -> Void
    var onTapInsight: (ConceptDefinition) -> Void

    private static let alwaysVisible = 2

    private var visibleInsights: [ConceptDefinition] {
        if insightsExpanded || node.insights.count <= Self.alwaysVisible {
            return node.insights
        }
        return Array(node.insights.prefix(Self.alwaysVisible))
    }

    private var collapsedCount: Int {
        guard !insightsExpanded, node.insights.count > Self.alwaysVisible else { return 0 }
        return node.insights.count - Self.alwaysVisible
    }

    private var summaryText: String {
        node.summary.isEmpty
            ? "This placeholder summary shows how a longer response will appear inside the conversation topic. Tap the text to expand the full summary, then tap it again to collapse it back to the shorter preview."
            : node.summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(node.title)
                .font(.baskervilleSmall)
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture(perform: onTapBubble)

            Button(action: onTapSummary) {
                Text(summaryText)
                    .font(.custom("Figtree-Regular", size: 14))
                    .foregroundColor(
                        node.summary.isEmpty
                            ? AquinasTheme.Colors.placeholderText
                            : AquinasTheme.Colors.paragraphText
                    )
                    .lineLimit(isExpanded ? nil : 2)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                isSelected
                    ? "Expands or collapses the summary"
                    : "Select the topic before expanding its summary"
            )

            // Insights — only shown when expanded
            if isExpanded && !node.insights.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(visibleInsights) { insight in
                        Button {
                            onTapInsight(insight)
                        } label: {
                            InsightLine(word: insight.word)
                        }
                        .buttonStyle(.plain)
                    }

                    if collapsedCount > 0 {
                        Button(action: onTapInsightChip) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.bubble.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                                Text("+\(collapsedCount)")
                                    .font(.figtreeHeading2)
                                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AquinasTheme.Colors.canvas.opacity(0.8))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(24)
        .frame(width: kBubbleMaxWidth, alignment: .leading)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
        )
        .shadow(
            color: AquinasTheme.Colors.canvas.opacity(0.5),
            radius: 16, x: 0, y: 4
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isExpanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: insightsExpanded)
    }
}
