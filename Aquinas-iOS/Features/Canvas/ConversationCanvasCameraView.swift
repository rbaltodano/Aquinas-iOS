//
//  ConversationCanvasCameraView.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

// MARK: - Conversation Canvas Camera

/// InsightTree-style world-space camera for conversation branches.
///
/// • Each branch occupies a vertical column in world space: x = index × laneStep, y = 0.
/// • The camera (scale + offset) maps world → screen via `worldToScreen`.
/// • When `scale ≥ focusedScaleThreshold` **and** the branch is the focused one, the live
///   `ChatThreadColumn` (ScrollView, full interaction) is rendered at native 1:1 size.
/// • Below that threshold every branch renders as a lightweight `CanvasBranchSummaryView`
///   (map or icon LOD).  Tapping a summary card calls `onFocusBranch`.
/// • Canvas pan / zoom gestures are suppressed while focused so the inner ScrollView owns
///   vertical drag; only a horizontal swipe (handled by the caller) exits focus mode.
struct ConversationCanvasCameraView<FullBranch: View>: View {

    // MARK: Bindings & configuration

    @Binding var branches: [ChatBranch]
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var isViewingEntireCanvas: Bool

    let size: CGSize
    let focusedBranchID: UUID?
    let branchSpacing: CGFloat
    let areResponsesCollapsed: Bool
    let makeFullBranch: (Binding<ChatBranch>, CGSize) -> FullBranch
    let onFocusBranch: (ChatBranch) -> Void

    // MARK: Private state

    @State private var pinchStartScale: CGFloat?
    @State private var pinchStartOffset: CGSize?
    @State private var lastDragEndedAt: Date = .distantPast
    @GestureState private var liveDragOffset: CGSize = .zero

    // MARK: Constants

    /// Branch transitions from live view to preview below this scale.
    static var focusedScaleThreshold: CGFloat { 0.85 }
    /// Tall enough to contain any realistic conversation.
    private let worldBranchHeight: CGFloat = 4000

    // MARK: Derived geometry

    private var activeOffset: CGSize {
        CGSize(width: offset.width + liveDragOffset.width,
               height: offset.height + liveDragOffset.height)
    }

    private var laneWidth: CGFloat { max(size.width, 1) }
    private var laneStep:  CGFloat { laneWidth + branchSpacing }

    private var camera: ConversationCanvasCamera {
        ConversationCanvasCamera(scale: scale, offset: activeOffset)
    }

    /// True while the camera is zoomed in enough to show the live branch.
    var isFocused: Bool { scale >= Self.focusedScaleThreshold }

    /// True if enough time has passed since the last drag ended (tap guard).
    private var canAcceptTap: Bool {
        !isFocused && Date().timeIntervalSince(lastDragEndedAt) > 0.16
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            connectorsLayer

            ForEach(visibleBranchIndices, id: \.self) { index in
                branchView(at: index)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(panGesture)
        .simultaneousGesture(zoomGesture)
        .onAppear {
            // Initialise offset so the focused branch is visible on first render.
            if offset == .zero {
                let idx = branches.firstIndex { $0.id == focusedBranchID } ?? 0
                offset = offsetToFocus(at: idx, scale: scale)
            }
        }
    }

    // MARK: Visibility culling

    private var visibleBranchIndices: [Int] {
        // Use a tighter buffer when focused so non-focused branches aren't rendered at full LOD.
        let buffer: CGFloat = isFocused ? 120 : 900
        let visible = visibleWorldRect.insetBy(dx: -buffer, dy: -buffer)
        return branches.indices.filter { branchWorldFrame(at: $0).intersects(visible) }
    }

    private var visibleWorldRect: CGRect {
        let tl = camera.screenToWorld(.zero)
        let br = camera.screenToWorld(CGPoint(x: size.width, y: size.height))
        return CGRect(x: min(tl.x, br.x), y: min(tl.y, br.y),
                      width: abs(br.x - tl.x), height: abs(br.y - tl.y))
    }

    // MARK: Branch views

    @ViewBuilder
    private func branchView(at index: Int) -> some View {
        let branch = branches[index]
        let level  = detailLevel(for: index)
        let frame  = branchWorldFrame(at: index)
        let origin = camera.worldToScreen(frame.origin)

        switch level {

        case .full:
            // Live, scrollable branch at native (1:1) scale — no scaleEffect needed.
            makeFullBranch($branches[index], size)
                .frame(width: laneWidth, height: size.height)
                .position(x: origin.x + laneWidth / 2,
                          y: origin.y + size.height / 2)
                .transition(.opacity)
                .zIndex(Double(index + 1))

        case .map, .icon:
            let sw    = frame.width * scale
            let sh    = frame.height * scale
            let style: CanvasBranchSummaryStyle = level == .map ? .map : .icon
            let inset: CGFloat = level == .map ? 24 : 48

            CanvasBranchSummaryView(
                branch: branch,
                areResponsesCollapsed: areResponsesCollapsed,
                style: style,
                scale: scale
            )
            .frame(width: frame.width - inset)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: frame.width, height: frame.height, alignment: .top)
            .position(x: origin.x + sw / 2, y: origin.y + sh / 2)
            .contentShape(Rectangle())
            .onTapGesture {
                guard canAcceptTap else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onFocusBranch(branch)
            }
            .transition(.opacity)
            .zIndex(Double(index + 1))
        }
    }

    private func detailLevel(for index: Int) -> ConversationCanvasDetailLevel {
        let isBranchFocused = branches[index].id == focusedBranchID
            || (focusedBranchID == nil && index == 0)
        if isBranchFocused && scale >= Self.focusedScaleThreshold { return .full }
        if scale >= 0.20 { return .map }
        return .icon
    }

    // MARK: Connector lines

    private var connectorsLayer: some View {
        Canvas { context, _ in
            guard !isFocused else { return }
            for childIndex in branches.indices {
                let child = branches[childIndex]
                guard let parentID = child.parentBranchID,
                      let parentIndex = branches.firstIndex(where: { $0.id == parentID })
                else { continue }

                let y     = max(120, child.yOffset)
                let start = camera.worldToScreen(
                    CGPoint(x: branchWorldFrame(at: parentIndex).maxX - 24, y: y))
                let end   = camera.worldToScreen(
                    CGPoint(x: branchWorldFrame(at: childIndex).minX  + 24, y: y))

                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(AquinasTheme.Colors.divider),
                               lineWidth: max(1, scale))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: World layout

    private func branchWorldFrame(at index: Int) -> CGRect {
        CGRect(x: CGFloat(index) * laneStep, y: 0,
               width: laneWidth, height: worldBranchHeight)
    }

    private var worldBounds: CGRect {
        guard !branches.isEmpty else { return CGRect(origin: .zero, size: size) }
        return branches.indices
            .map { branchWorldFrame(at: $0) }
            .reduce(branchWorldFrame(at: 0)) { $0.union($1) }
    }

    // MARK: Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($liveDragOffset) { value, state, _ in
                guard !isFocused else { return }
                state = value.translation
            }
            .onEnded { value in
                guard !isFocused else { return }
                offset.width  += value.translation.width
                offset.height += value.translation.height
                if hypot(value.translation.width, value.translation.height) > 8 {
                    lastDragEndedAt = Date()
                }
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if pinchStartScale == nil {
                    pinchStartScale = scale
                    pinchStartOffset = offset
                }
                apply(magnification: value.magnification,
                      anchor: value.startAnchor, commit: false)
            }
            .onEnded { value in
                apply(magnification: value.magnification,
                      anchor: value.startAnchor, commit: true)
                pinchStartScale  = nil
                pinchStartOffset = nil
            }
    }

    private func apply(magnification: CGFloat, anchor unitAnchor: UnitPoint, commit: Bool) {
        let initScale  = pinchStartScale  ?? scale
        let initOffset = pinchStartOffset ?? offset
        let next       = clampedScale(initScale * pow(magnification, 0.72))
        let pt         = CGPoint(x: unitAnchor.x * size.width, y: unitAnchor.y * size.height)

        scale  = next
        offset = keepAnchor(pt, from: initOffset, initScale: initScale, nextScale: next)

        if commit {
            isViewingEntireCanvas = next <= fitScale() + 0.01
        }
    }

    // MARK: Camera math (public so ActiveInquiry can call them)

    func fitScale() -> CGFloat {
        guard !branches.isEmpty, size.width > 0 else { return 0.8 }
        let available = max(size.width - 24, 1)
        return min(1.0, max(0.18, available / max(worldBounds.width, 1)))
    }

    func fitOffset(for s: CGFloat) -> CGSize {
        let bounds = worldBounds
        let inset  = max(12, (size.width - bounds.width * s) / 2)
        return CGSize(width: inset - bounds.minX * s, height: 40)
    }

    /// Camera offset that positions branch `index` at the left edge of the screen.
    func offsetToFocus(at index: Int, scale s: CGFloat) -> CGSize {
        CGSize(width: -CGFloat(index) * laneStep * s, height: 0)
    }

    private func clampedScale(_ s: CGFloat) -> CGFloat {
        min(1.0, max(min(0.18, fitScale()), s))
    }

    private func keepAnchor(
        _ anchor: CGPoint, from initOffset: CGSize,
        initScale: CGFloat, nextScale: CGFloat
    ) -> CGSize {
        let wx = (anchor.x - initOffset.width)  / initScale
        let wy = (anchor.y - initOffset.height) / initScale
        return CGSize(width: anchor.x - wx * nextScale, height: anchor.y - wy * nextScale)
    }
}

// MARK: - Camera Projection

private struct ConversationCanvasCamera {
    var scale: CGFloat
    var offset: CGSize

    func worldToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + offset.width,
                y: point.y * scale + offset.height)
    }

    func screenToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.width)  / scale,
                y: (point.y - offset.height) / scale)
    }
}

// MARK: - LOD

private enum ConversationCanvasDetailLevel { case full, map, icon }

private enum CanvasBranchSummaryStyle { case map, icon }

// MARK: - Branch Summary Views (shown in canvas / zoomed-out mode)

private struct CanvasBranchSummaryView: View {
    let branch: ChatBranch
    let areResponsesCollapsed: Bool
    let style: CanvasBranchSummaryStyle
    let scale: CGFloat

    private var title: String {
        branch.generatedBranchTitle
            ?? (branch.parentBranchID == nil ? "New Conversation" : "New Branch")
    }

    private var contextTitle: String? {
        if let concept = branch.branchContextConcept ?? branch.startingConcept {
            return concept.word.capitalized
        }
        if let dup = branch.duplicatedResponse {
            return generatedContextTitle(from: dup)
        }
        return nil
    }

    private var contextIcon: String {
        (branch.branchContextConcept ?? branch.startingConcept) == nil
            ? "arrow.triangle.branch" : "text.bubble.fill"
    }

    var body: some View {
        switch style {
        case .map:
            BranchMapPreviewView(
                branch: branch, title: title,
                contextTitle: contextTitle, contextIcon: contextIcon,
                areResponsesCollapsed: areResponsesCollapsed,
                labelOpacity: opacity(from: 0.18, to: 0.34),
                questionOpacity: opacity(from: 0.22, to: 0.38),
                responseTitleOpacity: opacity(from: 0.40, to: 0.54)
            )
        case .icon:
            BranchIconPreviewView(
                branch: branch, title: title,
                contextTitle: contextTitle, contextIcon: contextIcon,
                labelOpacity: opacity(from: 0.18, to: 0.34)
            )
        }
    }

    private func opacity(from lo: CGFloat, to hi: CGFloat) -> Double {
        Double(min(1, max(0, (scale - lo) / max(hi - lo, 0.001))))
    }
}

// MARK: Map preview

private struct BranchMapPreviewView: View {
    let branch: ChatBranch
    let title: String
    let contextTitle: String?
    let contextIcon: String
    let areResponsesCollapsed: Bool
    let labelOpacity: Double
    let questionOpacity: Double
    let responseTitleOpacity: Double
    @Environment(\.colorScheme) private var colorScheme

    private var previewBlocks: ArraySlice<ChatBlock> { branch.activeChatBlocks.prefix(5) }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.top, 10).padding(.bottom, 22)

            if let ctx = contextTitle {
                contextChip(title: ctx, icon: contextIcon).padding(.bottom, 20)
            }

            questionText(
                branch.topQuestionSubmitted && !branch.topQuestionText.isEmpty
                    ? branch.topQuestionText : "Ask Theo a question…",
                submitted: branch.topQuestionSubmitted,
                lineLimit: 2
            )
            .opacity(questionOpacity)

            connector(height: 42)

            VStack(spacing: 0) {
                ForEach(Array(previewBlocks.enumerated()), id: \.offset) { i, block in
                    blockPreview(block)
                    if i < previewBlocks.count - 1 { connector(height: 36) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image("cross-1")
                .renderingMode(.template).resizable().scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundColor(AquinasTheme.Colors.accent)

            HStack(spacing: 8) {
                if branch.parentBranchID != nil {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.accent)
                        .rotationEffect(.degrees(-18))
                }
                Text(title)
                    .font(.custom("LibreBaskerville-Regular", size: 30))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.72)
            }
            .opacity(labelOpacity)
        }
        .frame(maxWidth: .infinity)
    }

    private func contextChip(title: String, icon: String) -> some View {
        let isInsightChip = icon == "text.bubble" || icon == "text.bubble.fill"
        return HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: isInsightChip ? 14 : 12, weight: .semibold))
            Text(title).font(isInsightChip ? .figtreeHeading2 : .figtreeChipLabel).lineLimit(1)
        }
        .foregroundColor(AquinasTheme.Colors.darkGreen)
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(AquinasTheme.Colors.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AquinasTheme.Colors.border, lineWidth: 1) }
        .opacity(labelOpacity)
    }

    private func questionText(_ text: String, submitted: Bool, lineLimit: Int) -> some View {
        Text(text)
            .font(.custom("LibreBaskerville-Regular", size: 16))
            .foregroundColor(submitted
                             ? AquinasTheme.Colors.primaryReadable
                             : (colorScheme == .dark ? Color(hex: 0xFFFAF0, alpha: 0.50) : Color(hex: 0x4A321C, alpha: 0.50)))
            .lineLimit(lineLimit).multilineTextAlignment(.center).padding(.horizontal, 26)
    }

    @ViewBuilder
    private func blockPreview(_ block: ChatBlock) -> some View {
        switch block {
        case .text(let t):
            responseShell(title: generatedResponseTitle(from: t))
        case .user(let q, let concept, let attachments):
            userQuestionPreview(question: q, concept: concept, attachments: attachments)
        }
    }

    private func responseShell(title: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AquinasTheme.Colors.card)
                .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(AquinasTheme.Colors.border, lineWidth: 1) }
            Image(systemName: "book.pages")
                .font(.system(size: 38, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
            VStack {
                HStack {
                    Text(title).font(.figtreeHeading3)
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .lineLimit(1).opacity(responseTitleOpacity)
                    Spacer()
                }
                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .frame(height: areResponsesCollapsed ? 190 : 320)
    }

    private func userQuestionPreview(
        question: String, concept: ConceptDefinition?, attachments: [UploadedFile]
    ) -> some View {
        VStack(spacing: 10) {
            if !attachments.isEmpty {
                HStack(spacing: -8) {
                    ForEach(attachments.prefix(3)) { file in
                        if let img = file.image {
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(AquinasTheme.Colors.uploadBorder, lineWidth: 2) }
                        }
                    }
                }
            }
            if let concept {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(concept.word.capitalized)
                        .font(.figtreeHeading2)
                }
                .foregroundColor(AquinasTheme.Colors.darkGreen).lineLimit(1)
                .opacity(labelOpacity)
            }
            questionText(question, submitted: true, lineLimit: 3).opacity(questionOpacity)
        }
        .padding(.vertical, 2).frame(maxWidth: .infinity)
    }

    private func connector(height: CGFloat) -> some View {
        Rectangle().fill(AquinasTheme.Colors.divider)
            .frame(width: 1, height: height).opacity(0.72)
    }

    private func generatedResponseTitle(from text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let words = (cleaned.split(separator: ".").first.map(String.init) ?? cleaned)
            .split(separator: " ").prefix(4).map(String.init)
        return words.isEmpty ? "Response" : words.joined(separator: " ")
    }
}

// MARK: Icon preview

private struct BranchIconPreviewView: View {
    let branch: ChatBranch
    let title: String
    let contextTitle: String?
    let contextIcon: String
    let labelOpacity: Double

    private var responseCount: Int {
        branch.activeChatBlocks.filter { if case .text = $0 { return true }; return false }.count
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image("cross-1").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 16, height: 16).foregroundColor(AquinasTheme.Colors.accent)
                Text(title)
                    .font(.custom("LibreBaskerville-Regular", size: 24))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .lineLimit(1).minimumScaleFactor(0.72).opacity(labelOpacity)
            }
            if let ctx = contextTitle {
                let isInsightChip = contextIcon == "text.bubble" || contextIcon == "text.bubble.fill"
                HStack(spacing: 8) {
                    Image(systemName: contextIcon)
                        .font(.system(size: isInsightChip ? 14 : 12, weight: .semibold))
                    Text(ctx)
                        .font(isInsightChip ? .figtreeHeading2 : .figtreeChipLabel)
                }
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .lineLimit(1).padding(.horizontal, 16).padding(.vertical, 12)
                .background(AquinasTheme.Colors.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AquinasTheme.Colors.border, lineWidth: 1) }
                .opacity(labelOpacity)
            }
            VStack(spacing: 24) {
                ForEach(0..<max(1, min(responseCount, 3)), id: \.self) { i in
                    iconShell(height: i == 0 ? 300 : 260)
                    if i < min(responseCount, 3) - 1 {
                        Rectangle().fill(AquinasTheme.Colors.divider)
                            .frame(width: 1, height: 40).opacity(0.62)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func iconShell(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AquinasTheme.Colors.card.opacity(0.86))
                .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(AquinasTheme.Colors.border, lineWidth: 1) }
            Image(systemName: "book.pages")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
        }
        .frame(maxWidth: .infinity).frame(height: height)
    }
}

// MARK: - Helpers

private func generatedContextTitle(from text: String) -> String {
    let stop: Set<String> = ["the","a","an","and","or","but","is","are","was","were","of","to","in","for","with","as","on"]
    let words = text
        .replacingOccurrences(of: "[^A-Za-z0-9\\s]", with: " ", options: .regularExpression)
        .split(separator: " ").map(String.init)
        .filter { !stop.contains($0.lowercased()) }
        .prefix(3).map { $0.capitalized }
    return words.isEmpty ? "Response Branch" : words.joined(separator: " ")
}
