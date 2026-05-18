//
//  ConversationCanvasCameraView.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

// MARK: - Conversation Canvas Camera

/// Canvas-mode renderer for branch lanes.
/// Branch mode keeps the native vertical ScrollView; this view only owns the free camera experience.
struct ConversationCanvasCameraView<FullBranch: View>: View {
    @Binding var branches: [ChatBranch]
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var isViewingEntireCanvas: Bool
    @Binding var measuredCanvasHeight: CGFloat

    let size: CGSize
    let branchSpacing: CGFloat
    let overviewBranchSpacing: CGFloat
    let areResponsesCollapsed: Bool
    let focusedBranchID: UUID?
    let makeFullBranch: (Binding<ChatBranch>, CGSize) -> FullBranch
    let onFocusBranch: (ChatBranch) -> Void

    @State private var pinchStartScale: CGFloat?
    @State private var pinchStartOffset: CGSize?
    @State private var lastDragEndedAt: Date = .distantPast
    @GestureState private var dragOffset: CGSize = .zero

    private let viewportBuffer: CGFloat = 900
    private let minimumTapPause: TimeInterval = 0.16

    private var activeOffset: CGSize {
        CGSize(width: offset.width + dragOffset.width, height: offset.height + dragOffset.height)
    }

    private var activeSpacing: CGFloat {
        isViewingEntireCanvas ? overviewBranchSpacing : branchSpacing
    }

    private var laneWidth: CGFloat {
        max(size.width, 1)
    }

    private var laneStep: CGFloat {
        laneWidth + activeSpacing
    }

    private var branchWorldHeight: CGFloat {
        max(measuredCanvasHeight, size.height)
    }

    private var camera: ConversationCanvasCamera {
        ConversationCanvasCamera(scale: scale, offset: activeOffset)
    }

    private var canAcceptTap: Bool {
        Date().timeIntervalSince(lastDragEndedAt) > minimumTapPause
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            connectorsLayer

            ForEach(visibleBranchIndices, id: \.self) { index in
                branchView(at: index)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .coordinateSpace(name: "GlobalCanvas")
        .simultaneousGesture(panGesture)
        .simultaneousGesture(zoomGesture)
        .onAppear {
            if offset == .zero {
                offset = regularOffsetForFocusedBranch()
            }
        }
    }

    private var visibleBranchIndices: [Int] {
        let visibleWorld = visibleWorldRect.insetBy(dx: -viewportBuffer, dy: -viewportBuffer)

        return branches.indices.filter { index in
            let frame = branchWorldFrame(at: index)
            return frame.intersects(visibleWorld)
        }
    }

    private var visibleWorldRect: CGRect {
        let topLeft = camera.screenToWorld(.zero)
        let bottomRight = camera.screenToWorld(CGPoint(x: size.width, y: size.height))
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }

    @ViewBuilder
    private func branchView(at index: Int) -> some View {
        let branch = branches[index]
        let level = detailLevel
        let frame = branchWorldFrame(at: index)
        let screenOrigin = camera.worldToScreen(frame.origin)
        let screenWidth = frame.width * scale
        let screenHeight = frame.height * scale

        Group {
            switch level {
            case .full:
                makeFullBranch($branches[index], size)
                    .frame(width: frame.width, height: frame.height, alignment: .top)
                    .scaleEffect(scale, anchor: .topLeading)
            case .map:
                CanvasBranchSummaryView(
                    branch: branch,
                    areResponsesCollapsed: areResponsesCollapsed,
                    style: .map,
                    scale: scale
                )
                .frame(width: frame.width - 24)
                .scaleEffect(scale, anchor: .topLeading)
            case .icon:
                CanvasBranchSummaryView(
                    branch: branch,
                    areResponsesCollapsed: areResponsesCollapsed,
                    style: .icon,
                    scale: scale
                )
                .frame(width: frame.width - 48)
                .scaleEffect(scale, anchor: .topLeading)
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .top)
        .position(x: screenOrigin.x + screenWidth / 2, y: screenOrigin.y + screenHeight / 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canAcceptTap else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onFocusBranch(branch)
        }
        .zIndex(Double(index + 1))
    }

    private var connectorsLayer: some View {
        Canvas { context, _ in
            for childIndex in branches.indices {
                let child = branches[childIndex]
                guard let parentID = child.parentBranchID,
                      let parentIndex = branches.firstIndex(where: { $0.id == parentID }) else {
                    continue
                }

                let y = max(120, child.yOffset)
                let start = camera.worldToScreen(
                    CGPoint(x: branchWorldFrame(at: parentIndex).maxX - 24, y: y)
                )
                let end = camera.worldToScreen(
                    CGPoint(x: branchWorldFrame(at: childIndex).minX + 24, y: y)
                )

                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(AquinasTheme.Colors.divider), lineWidth: max(1, scale))
            }
        }
        .allowsHitTesting(false)
    }

    private var detailLevel: ConversationCanvasDetailLevel {
        if scale >= 0.55 {
            return .full
        }
        if scale >= 0.24 {
            return .map
        }
        return .icon
    }

    private func branchWorldFrame(at index: Int) -> CGRect {
        CGRect(
            x: CGFloat(index) * laneStep,
            y: 0,
            width: laneWidth,
            height: branchWorldHeight
        )
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                offset.width += value.translation.width
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

                let initialScale = pinchStartScale ?? scale
                let initialOffset = pinchStartOffset ?? offset
                let nextScale = clampedScale(initialScale * pow(value.magnification, 0.72))
                let anchor = CGPoint(x: value.startAnchor.x * size.width, y: value.startAnchor.y * size.height)

                scale = nextScale
                offset = offsetKeeping(anchor, fixedFrom: initialOffset, initialScale: initialScale, nextScale: nextScale)
            }
            .onEnded { value in
                let initialScale = pinchStartScale ?? scale
                let initialOffset = pinchStartOffset ?? offset
                let nextScale = clampedScale(initialScale * pow(value.magnification, 0.72))
                let anchor = CGPoint(x: value.startAnchor.x * size.width, y: value.startAnchor.y * size.height)

                scale = nextScale
                offset = offsetKeeping(anchor, fixedFrom: initialOffset, initialScale: initialScale, nextScale: nextScale)
                pinchStartScale = nil
                pinchStartOffset = nil
                isViewingEntireCanvas = scale <= fitScale() + 0.01
            }
    }

    private func clampedScale(_ proposedScale: CGFloat) -> CGFloat {
        min(1.0, max(min(0.18, fitScale()), proposedScale))
    }

    private func offsetKeeping(
        _ anchor: CGPoint,
        fixedFrom initialOffset: CGSize,
        initialScale: CGFloat,
        nextScale: CGFloat
    ) -> CGSize {
        let worldX = (anchor.x - initialOffset.width) / initialScale
        let worldY = (anchor.y - initialOffset.height) / initialScale

        return CGSize(
            width: anchor.x - worldX * nextScale,
            height: anchor.y - worldY * nextScale
        )
    }

    func fitScale() -> CGFloat {
        guard !branches.isEmpty, size.width > 0, size.height > 0 else {
            return 0.8
        }

        let bounds = worldBounds
        let availableWidth = max(size.width - 24, 1)
        let availableHeight = max(size.height - 160, 1)
        let widthScale = availableWidth / max(bounds.width, 1)
        let heightScale = availableHeight / max(bounds.height, 1)
        return min(1.0, max(0.18, min(widthScale, heightScale)))
    }

    func fitOffset(scale fitScale: CGFloat) -> CGSize {
        let bounds = worldBounds
        let scaledWidth = bounds.width * fitScale
        let horizontalInset = max(12, (size.width - scaledWidth) / 2)
        return CGSize(
            width: horizontalInset - bounds.minX * fitScale,
            height: 40 - bounds.minY * fitScale
        )
    }

    func regularOffsetForFocusedBranch(scale regularScale: CGFloat = 0.80) -> CGSize {
        let index = branches.firstIndex { $0.id == focusedBranchID } ?? 0
        let frame = branchWorldFrame(at: index)
        return CGSize(width: -frame.minX * regularScale, height: 0)
    }

    private var worldBounds: CGRect {
        guard !branches.isEmpty else {
            return CGRect(origin: .zero, size: size)
        }

        let frames = branches.indices.map { branchWorldFrame(at: $0) }
        return frames.dropFirst().reduce(frames[0]) { partialResult, frame in
            partialResult.union(frame)
        }
    }
}

// MARK: - Canvas Branch LOD

private enum ConversationCanvasDetailLevel {
    case full
    case map
    case icon
}

private enum CanvasBranchSummaryStyle {
    case map
    case icon
}

private struct CanvasBranchSummaryView: View {
    let branch: ChatBranch
    let areResponsesCollapsed: Bool
    let style: CanvasBranchSummaryStyle
    let scale: CGFloat

    private var title: String {
        branch.generatedBranchTitle ?? (branch.parentBranchID == nil ? "New Conversation" : "New Branch")
    }

    private var contextTitle: String? {
        if let concept = branch.branchContextConcept ?? branch.startingConcept {
            return concept.word.capitalized
        }

        if let duplicatedResponse = branch.duplicatedResponse {
            return generatedContextTitle(from: duplicatedResponse)
        }

        return nil
    }

    private var contextIcon: String {
        (branch.branchContextConcept ?? branch.startingConcept) == nil ? "arrow.triangle.branch" : "text.bubble.fill"
    }

    var body: some View {
        switch style {
        case .map:
            BranchMapPreviewView(
                branch: branch,
                title: title,
                contextTitle: contextTitle,
                contextIcon: contextIcon,
                areResponsesCollapsed: areResponsesCollapsed,
                labelOpacity: labelOpacity,
                questionOpacity: questionOpacity,
                responseTitleOpacity: responseTitleOpacity
            )
        case .icon:
            BranchIconPreviewView(
                branch: branch,
                title: title,
                contextTitle: contextTitle,
                contextIcon: contextIcon,
                labelOpacity: labelOpacity
            )
        }
    }

    private var labelOpacity: Double {
        Double(Self.progress(scale, from: 0.18, to: 0.34))
    }

    private var questionOpacity: Double {
        Double(Self.progress(scale, from: 0.22, to: 0.38))
    }

    private var responseTitleOpacity: Double {
        Double(Self.progress(scale, from: 0.40, to: 0.54))
    }

    private static func progress(_ value: CGFloat, from lowerBound: CGFloat, to upperBound: CGFloat) -> CGFloat {
        guard upperBound > lowerBound else { return value >= upperBound ? 1 : 0 }
        return min(1, max(0, (value - lowerBound) / (upperBound - lowerBound)))
    }
}

private struct BranchMapPreviewView: View {
    let branch: ChatBranch
    let title: String
    let contextTitle: String?
    let contextIcon: String
    let areResponsesCollapsed: Bool
    let labelOpacity: Double
    let questionOpacity: Double
    let responseTitleOpacity: Double

    private var previewBlocks: ArraySlice<ChatBlock> {
        branch.activeChatBlocks.prefix(5)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 10)
                .padding(.bottom, 22)

            if let contextTitle {
                contextChip(title: contextTitle, icon: contextIcon)
                    .padding(.bottom, 20)
            }

            questionText(
                branch.topQuestionSubmitted && !branch.topQuestionText.isEmpty ? branch.topQuestionText : "Ask Theo a question...",
                submitted: branch.topQuestionSubmitted,
                lineLimit: 2
            )
            .opacity(questionOpacity)

            connector(height: 42)

            VStack(spacing: 0) {
                ForEach(Array(previewBlocks.enumerated()), id: \.offset) { index, block in
                    blockPreview(block)

                    if index < previewBlocks.count - 1 {
                        connector(height: 36)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image("cross-1")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
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
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
            }
            .opacity(labelOpacity)
        }
        .frame(maxWidth: .infinity)
    }

    private func contextChip(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.baskervilleSmall)
                .lineLimit(1)
        }
        .foregroundColor(AquinasTheme.Colors.darkGreen)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(AquinasTheme.Colors.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AquinasTheme.Colors.border, lineWidth: 1)
        }
        .opacity(labelOpacity)
    }

    private func questionText(_ text: String, submitted: Bool, lineLimit: Int) -> some View {
        Text(text)
            .font(.custom("LibreBaskerville-Regular", size: 16))
            .foregroundColor(submitted ? AquinasTheme.Colors.primaryReadable : AquinasTheme.Colors.placeholderText)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 26)
    }

    @ViewBuilder
    private func blockPreview(_ block: ChatBlock) -> some View {
        switch block {
        case .text(let text):
            responseShell(title: generatedResponseTitle(from: text))

        case .user(let question, let concept, let attachments):
            userQuestionPreview(question: question, concept: concept, attachments: attachments)
        }
    }

    private func responseShell(title: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AquinasTheme.Colors.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AquinasTheme.Colors.border, lineWidth: 1)
                }

            Image(systemName: "book.pages")
                .font(.system(size: 38, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)

            VStack {
                HStack {
                    Text(title)
                        .font(.figtreeHeading3)
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .lineLimit(1)
                        .opacity(responseTitleOpacity)
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
        question: String,
        concept: ConceptDefinition?,
        attachments: [UploadedFile]
    ) -> some View {
        VStack(spacing: 10) {
            if !attachments.isEmpty {
                HStack(spacing: -8) {
                    ForEach(attachments.prefix(3)) { file in
                        if let imageData = file.imageData,
                           let image = UIImage(data: imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AquinasTheme.Colors.uploadBorder, lineWidth: 2)
                                }
                        }
                    }
                }
            }

            if let concept {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                    Text(concept.word.capitalized)
                }
                .font(.baskervilleSmall)
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .lineLimit(1)
                .opacity(labelOpacity)
            }

            questionText(question, submitted: true, lineLimit: 3)
                .opacity(questionOpacity)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
    }

    private func connector(height: CGFloat) -> some View {
        Rectangle()
            .fill(AquinasTheme.Colors.divider)
            .frame(width: 1, height: height)
            .opacity(0.72)
    }

    private func generatedResponseTitle(from response: String) -> String {
        let cleaned = cleanCanvasPreviewText(response)
        let sentence = cleaned
            .split(separator: ".")
            .first
            .map(String.init) ?? cleaned
        let words = sentence.split(separator: " ").prefix(4).map { String($0) }
        return words.isEmpty ? "Response" : words.joined(separator: " ")
    }
}

private struct BranchIconPreviewView: View {
    let branch: ChatBranch
    let title: String
    let contextTitle: String?
    let contextIcon: String
    let labelOpacity: Double

    private var responseCount: Int {
        branch.activeChatBlocks.filter { block in
            if case .text = block { return true }
            return false
        }.count
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image("cross-1")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(AquinasTheme.Colors.accent)

                Text(title)
                    .font(.custom("LibreBaskerville-Regular", size: 24))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .opacity(labelOpacity)
            }

            if let contextTitle {
                HStack(spacing: 8) {
                    Image(systemName: contextIcon)
                    Text(contextTitle)
                }
                .font(.baskervilleSmall)
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AquinasTheme.Colors.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AquinasTheme.Colors.border, lineWidth: 1)
                }
                .opacity(labelOpacity)
            }

            VStack(spacing: 24) {
                ForEach(0..<max(1, min(responseCount, 3)), id: \.self) { index in
                    responseIconShell(height: index == 0 ? 300 : 260)

                    if index < min(responseCount, 3) - 1 {
                        connector(height: 40)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func responseIconShell(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AquinasTheme.Colors.card.opacity(0.86))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AquinasTheme.Colors.border, lineWidth: 1)
                }

            Image(systemName: "book.pages")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func connector(height: CGFloat) -> some View {
        Rectangle()
            .fill(AquinasTheme.Colors.divider)
            .frame(width: 1, height: height)
            .opacity(0.62)
    }

}

private func generatedContextTitle(from response: String) -> String {
    let stopWords: Set<String> = ["the", "a", "an", "and", "or", "but", "is", "are", "was", "were", "of", "to", "in", "for", "with", "as", "on"]
    let words = response
        .replacingOccurrences(of: "[^A-Za-z0-9\\s]", with: " ", options: .regularExpression)
        .split(separator: " ")
        .map { String($0) }
        .filter { !stopWords.contains($0.lowercased()) }
        .prefix(3)
        .map { $0.capitalized }

    return words.isEmpty ? "Response Branch" : words.joined(separator: " ")
}

private struct ConversationCanvasCamera {
    var scale: CGFloat
    var offset: CGSize

    func worldToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + offset.width, y: point.y * scale + offset.height)
    }

    func screenToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.width) / scale, y: (point.y - offset.height) / scale)
    }
}

private func cleanCanvasPreviewText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}
