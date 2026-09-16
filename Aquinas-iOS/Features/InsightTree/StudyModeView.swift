//
//  StudyModeView.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

/// The focused, single-Insight shell for Study. Each tool will eventually give the matrix its
/// own semantic behavior; this pass establishes Branch's count selection and placement surface.
struct StudyModeView: View {
    let insight: InsightModel
    let branchCount: Int
    let isExiting: Bool
    let onBranchCountChange: (Int) -> Void

    @State private var selectedTool: StudyTool = .branch
    @State private var hasEntered: Bool = false
    @State private var showsCenterIcon: Bool = false
    @State private var toolTransitionDirection: Int = 1

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AquinasTheme.Colors.canvas
                    .ignoresSafeArea()
                    .opacity(hasEntered ? 1 : 0)

                VStack(spacing: 48) {
                    StudyInsightTitle(title: insight.title)
                        .padding(.top, max(proxy.safeAreaInsets.top, 20) + 28)
                        .opacity(hasEntered ? 1 : 0)
                        .blur(radius: hasEntered ? 0 : 8)

                    StudyDotMatrix(
                        insightID: insight.id,
                        tool: selectedTool,
                        branchCount: branchCount,
                        isVisible: hasEntered,
                        isExiting: isExiting,
                        showsCenterIcon: showsCenterIcon,
                        onBranchCountChange: onBranchCountChange
                    )
                    .frame(width: 300, height: 300)
                    // Keep the matrix present after the surrounding Study chrome fades so
                    // its dots can retrace their entrance during the one-second exit.
                    .opacity(hasEntered || isExiting ? 1 : 0)
                    .transition(.opacity)

                    StudyToolCarousel(
                        tool: selectedTool,
                        transitionDirection: toolTransitionDirection,
                        onPrevious: { select(selectedTool.previous, direction: -1) },
                        onNext: { select(selectedTool.next, direction: 1) }
                    )
                    .padding(.horizontal, 24)
                    .opacity(hasEntered ? 1 : 0)
                    .offset(y: hasEntered ? 0 : 18)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .task(id: insight.id) {
            hasEntered = false
            showsCenterIcon = false
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                hasEntered = true
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 0.01)) {
                showsCenterIcon = true
            }
        }
        .onChange(of: isExiting) { _, exitsStudy in
            guard exitsStudy else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                hasEntered = false
                showsCenterIcon = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Study \(insight.title)")
    }

    private func select(_ tool: StudyTool, direction: Int) {
        guard tool != selectedTool else { return }
        toolTransitionDirection = direction
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            selectedTool = tool
        }
    }

}

private enum StudyTool: CaseIterable, Hashable {
    case branch
    case deconstruct
    case traverse

    var title: LocalizedStringResource {
        switch self {
        case .branch: "Branch"
        case .deconstruct: "Deconstruct"
        case .traverse: "Traverse"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .branch: "Explore concepts that are near this Insight in vector space."
        case .deconstruct: "Break this Insight into its core semantic parts."
        case .traverse: "Travel outward through a chosen semantic direction."
        }
    }

    var position: Int {
        switch self {
        case .branch: 1
        case .deconstruct: 2
        case .traverse: 3
        }
    }

    var next: Self { Self.allCases[position % Self.allCases.count] }
    var previous: Self { Self.allCases[(position - 2 + Self.allCases.count) % Self.allCases.count] }
}

private struct StudyInsightTitle: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "text.bubble.fill")
            .font(.custom("Figtree-Bold", size: 18, relativeTo: .headline))
            .foregroundStyle(AquinasTheme.Colors.lightGreen)
            .lineLimit(1)
            .padding(.horizontal, 24)
    }
}

private struct StudyDotMatrix: View {
    let insightID: UUID
    let tool: StudyTool
    let branchCount: Int
    let isVisible: Bool
    let isExiting: Bool
    let showsCenterIcon: Bool
    let onBranchCountChange: (Int) -> Void

    private let dots = StudyMatrixDot.points
    @State private var hapticPattern = StudyToolHapticPattern()
    @State private var previousDragAngle: CGFloat?
    @State private var accumulatedRotation: CGFloat = 0
    @State private var deconstructPhase: DeconstructPhase = .inactive
    @State private var firstPresentedToolID: UUID?

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                ForEach(dots) { dot in
                    StudyMatrixDotView(
                        dot: dot,
                        insightID: insightID,
                        highlightBehavior: dot.highlightBehavior(
                            for: tool,
                            branchCount: branchCount,
                            deconstructPhase: deconstructPhase
                        ),
                        isExiting: isExiting
                    )
                    .position(
                        x: center.x + dot.x * diameter / 2,
                        y: center.y + dot.y * diameter / 2
                    )
                }

                if showsCenterIcon {
                    StudyInsightCenterIcon()
                        .position(center)
                }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(branchCountGesture(in: proxy.size))
        }
        .task(id: MatrixEntranceHapticID(insightID: insightID, isVisible: isVisible)) {
            guard isVisible else { return }
            await hapticPattern.playMatrixEntrance()
        }
        .task(id: isExiting) {
            guard isExiting else { return }
            await hapticPattern.playExit()
        }
        .task(id: ToolHapticID(insightID: insightID, tool: tool, isVisible: isVisible)) {
            guard isVisible else {
                firstPresentedToolID = nil
                return
            }
            guard firstPresentedToolID == insightID else {
                firstPresentedToolID = insightID
                return
            }
            await hapticPattern.playIntro(for: tool)
        }
        .task(id: tool) {
            guard tool == .deconstruct else {
                deconstructPhase = .inactive
                return
            }

            deconstructPhase = .forming
            // Base dots may take up to one second to arrive, and the ring itself
            // has a final randomized highlight delay. Wait until that formation is
            // complete before moving the dot outward.
            try? await Task.sleep(for: .milliseconds(1_350))
            guard !Task.isCancelled, tool == .deconstruct else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                deconstructPhase = .transferred
            }
            hapticPattern.playDeconstructBreakout()
        }
        .accessibilityHidden(true)
    }

    private func branchCountGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard tool == .branch else { return }

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let currentAngle = atan2(
                    value.location.y - center.y,
                    value.location.x - center.x
                )

                guard let previousDragAngle else {
                    self.previousDragAngle = currentAngle
                    return
                }

                var angularDelta = currentAngle - previousDragAngle
                if angularDelta > .pi {
                    angularDelta -= 2 * .pi
                } else if angularDelta < -.pi {
                    angularDelta += 2 * .pi
                }

                self.previousDragAngle = currentAngle
                accumulatedRotation += angularDelta
                applyRotationStepsIfNeeded()
            }
            .onEnded { _ in
                previousDragAngle = nil
                accumulatedRotation = 0
            }
    }

    private func applyRotationStepsIfNeeded() {
        let anglePerCountStep: CGFloat = .pi / 5
        let requestedSteps = Int(accumulatedRotation / anglePerCountStep)
        guard requestedSteps != 0 else { return }

        let updatedCount = min(6, max(2, branchCount + requestedSteps))
        guard updatedCount != branchCount else {
            accumulatedRotation = 0
            return
        }

        let appliedSteps = updatedCount - branchCount
        accumulatedRotation -= CGFloat(appliedSteps) * anglePerCountStep
        onBranchCountChange(updatedCount)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.62)
    }
}

private struct StudyInsightCenterIcon: View {
    var body: some View {
        Image(systemName: "text.bubble.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AquinasTheme.Colors.lightGreen)
    }
}

private struct StudyMatrixDotView: View {
    let dot: StudyMatrixDot
    let insightID: UUID
    let highlightBehavior: StudyDotHighlightBehavior
    let isExiting: Bool

    @State private var isVisible: Bool = false
    @State private var hasSettled: Bool = false
    @State private var isHighlightVisible: Bool = false

    private var isHighlighted: Bool {
        highlightBehavior != .none
    }

    var body: some View {
        Circle()
            .fill(isHighlightVisible ? AquinasTheme.Colors.paragraphText : AquinasTheme.Colors.placeholderText)
            .frame(
                width: isHighlightVisible ? 8 : 4,
                height: isHighlightVisible ? 8 : 4
            )
            .scaleEffect(isHighlightVisible ? 1 : (hasSettled ? 0.5 : 1))
            .opacity(isVisible ? (isHighlightVisible ? 0.86 : 0.75) : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.76), value: isHighlightVisible)
            .task(id: BaseDotAnimationID(insightID: insightID, isExiting: isExiting)) {
                guard !isExiting else { return }
                isVisible = false
                hasSettled = false
                try? await Task.sleep(for: .milliseconds(dot.delayMilliseconds(for: insightID)))
                guard !Task.isCancelled else { return }
                isVisible = true
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    hasSettled = true
                }
            }
            .task(id: DotExitAnimationID(insightID: insightID, isExiting: isExiting)) {
                guard isExiting else { return }

                // Reverse the deterministic entrance order: dots that arrived last
                // enlarge and disappear first.
                try? await Task.sleep(for: .milliseconds(dot.exitDelayMilliseconds(for: insightID)))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.16)) {
                    isHighlightVisible = false
                    hasSettled = false
                }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                isVisible = false
            }
            .task(id: HighlightAnimationID(
                insightID: insightID,
                behavior: highlightBehavior,
                isBaseVisible: isVisible,
                isExiting: isExiting
            )) {
                guard isVisible, isHighlighted, !isExiting else {
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHighlightVisible = false
                    }
                    return
                }

                isHighlightVisible = false
                try? await Task.sleep(for: .milliseconds(dot.highlightDelayMilliseconds(
                    for: insightID,
                    behavior: highlightBehavior
                )))
                guard !Task.isCancelled, isHighlighted, !isExiting else { return }

                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isHighlightVisible = true
                }
            }
    }
}

private struct HighlightAnimationID: Hashable {
    let insightID: UUID
    let behavior: StudyDotHighlightBehavior
    let isBaseVisible: Bool
    let isExiting: Bool
}

private struct BaseDotAnimationID: Hashable {
    let insightID: UUID
    let isExiting: Bool
}

private struct DotExitAnimationID: Hashable {
    let insightID: UUID
    let isExiting: Bool
}

private struct MatrixEntranceHapticID: Hashable {
    let insightID: UUID
    let isVisible: Bool
}

private struct ToolHapticID: Hashable {
    let insightID: UUID
    let tool: StudyTool
    let isVisible: Bool
}

private enum DeconstructPhase: Hashable {
    case inactive
    case forming
    case transferred
}

private enum StudyDotHighlightBehavior: Hashable {
    case none
    case branch(count: Int)
    case deconstructRing
    case deconstructTransfer
}

/// Supplies a stable, recognizable feedback signature per Study tool. Visual dots
/// remain independently timed, but their count never changes the haptic rhythm.
@MainActor
private final class StudyToolHapticPattern {
    /// A simple 1.5-second physical bed for the matrix appearing: 20 evenly-spaced
    /// taps, with a one-in-four chance that an individual tap is emphasized.
    func playMatrixEntrance() async {
        guard SettingsHaptics.isEnabled else { return }

        for index in 0..<20 {
            guard !Task.isCancelled else { return }
            emit(Int.random(in: 0..<4) == 0 ? .emphasized : .light)
            guard index < 19 else { continue }
            try? await Task.sleep(for: .nanoseconds(78_947_368))
        }
    }

    /// Seven evenly spaced taps across one second: heavy, light, light,
    /// heavy, light, light, light.
    func playExit() async {
        guard SettingsHaptics.isEnabled else { return }

        let taps: [StudyHapticTap] = [
            .emphasized, .light, .light, .emphasized, .light, .light, .light
        ]
        for index in taps.indices {
            guard !Task.isCancelled else { return }
            emit(taps[index])
            guard index < taps.count - 1 else { continue }
            try? await Task.sleep(for: .nanoseconds(166_666_667))
        }
    }

    func playIntro(for tool: StudyTool) async {
        guard SettingsHaptics.isEnabled else { return }

        let taps: [StudyHapticTap]
        switch tool {
        case .branch:
            taps = [.light, .light, .emphasized]
        case .deconstruct:
            taps = [.emphasized, .light, .light]
        case .traverse:
            return
        }

        for index in taps.indices {
            guard !Task.isCancelled else { return }
            emit(taps[index])
            guard index < taps.count - 1 else { continue }
            try? await Task.sleep(for: .milliseconds(140))
        }
    }

    func playDeconstructBreakout() {
        guard SettingsHaptics.isEnabled else { return }
        emit(.emphasized)
    }

    private func emit(_ tap: StudyHapticTap) {
        let generator = UIImpactFeedbackGenerator(style: tap == .emphasized ? .medium : .light)
        generator.prepare()
        generator.impactOccurred(intensity: tap == .emphasized ? 0.74 : 0.48)
    }
}

private enum StudyHapticTap {
    case light
    case emphasized
}

private struct StudyToolCarousel: View {
    let tool: StudyTool
    let transitionDirection: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AquinasTheme.Colors.paragraphText)
                .accessibilityLabel("Previous Study tool")

                ZStack {
                    StudyToolCopy(tool: tool)
                        .id(tool)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: transitionDirection > 0 ? .trailing : .leading)
                                    .combined(with: .opacity),
                                removal: .move(edge: transitionDirection > 0 ? .leading : .trailing)
                                    .combined(with: .opacity)
                            )
                        )
                }
                .frame(maxWidth: .infinity, minHeight: 72)
                .clipped()

                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AquinasTheme.Colors.paragraphText)
                .accessibilityLabel("Next Study tool")
            }

            HStack(spacing: 8) {
                ForEach(StudyTool.allCases, id: \.position) { candidate in
                    Capsule()
                        .fill(AquinasTheme.Colors.paragraphText.opacity(candidate == tool ? 0.75 : 0.5))
                        .frame(width: candidate == tool ? 16 : 4, height: 4)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .contentShape(Rectangle())
        .simultaneousGesture(toolSwipeGesture)
    }

    private var toolSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 56 else {
                    return
                }
                value.translation.width < 0 ? onNext() : onPrevious()
            }
    }
}

private struct StudyToolCopy: View {
    let tool: StudyTool

    var body: some View {
        VStack(spacing: 4) {
            Text(tool.title)
                .font(.custom("Figtree-Bold", size: 18, relativeTo: .headline))
                .foregroundStyle(AquinasTheme.Colors.paragraphText)
            Text(tool.summary)
                .font(.custom("Figtree-Regular", size: 14, relativeTo: .body))
                .foregroundStyle(AquinasTheme.Colors.paragraphText.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StudyMatrixDot: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let ring: Int
    let slot: Int
    let slotsInRing: Int

    static let points: [StudyMatrixDot] = {
        let radii: [CGFloat] = [0.21, 0.32, 0.43, 0.54, 0.65, 0.76, 0.88]
        let counts = [14, 20, 28, 36, 44, 52, 60]
        return radii.indices.flatMap { ring in
            let count = counts[ring]
            return (0..<count).map { slot in
                let angle = (2 * .pi * CGFloat(slot) / CGFloat(count))
                    + ((ring == 3 || ring == radii.indices.last) ? -.pi / 2 : CGFloat(ring) * 0.23)
                return StudyMatrixDot(
                    id: ring * 100 + slot,
                    x: cos(angle) * radii[ring],
                    y: sin(angle) * radii[ring],
                    ring: ring,
                    slot: slot,
                    slotsInRing: count
                )
            }
        }
    }()

    func delayMilliseconds(for insightID: UUID) -> Int {
        var hash = UInt64(id)
        for byte in insightID.uuidString.utf8 {
            hash = (hash &* 1_099_511_628_211) ^ UInt64(byte)
        }
        return 200 + Int(hash % 801)
    }

    func exitDelayMilliseconds(for insightID: UUID) -> Int {
        1_000 - delayMilliseconds(for: insightID)
    }

    func highlightDelayMilliseconds(
        for insightID: UUID,
        behavior: StudyDotHighlightBehavior
    ) -> Int {
        guard behavior != .deconstructTransfer else { return 0 }

        let behaviorSeed: Int
        switch behavior {
        case .branch(let count):
            behaviorSeed = count * 1_003
        case .deconstructRing:
            behaviorSeed = 7_919
        case .none, .deconstructTransfer:
            behaviorSeed = 0
        }

        var hash = UInt64(id ^ behaviorSeed)
        for byte in insightID.uuidString.utf8 {
            hash = (hash &* 1_099_511_628_211) ^ UInt64(byte)
        }
        return 80 + Int(hash % 241)
    }

    func highlightBehavior(
        for tool: StudyTool,
        branchCount: Int,
        deconstructPhase: DeconstructPhase
    ) -> StudyDotHighlightBehavior {
        switch tool {
        case .branch:
            guard ring == 6, branchCount > 0,
                  Self.branchHighlightedSlots(for: branchCount).contains(slot) else {
                return .none
            }
            return .branch(count: branchCount)

        case .deconstruct:
            switch deconstructPhase {
            case .inactive:
                return .none
            case .forming:
                return ring == Self.deconstructRingIndex ? .deconstructRing : .none
            case .transferred:
                if ring == Self.deconstructRingIndex, slot != Self.deconstructClockTwoSlot {
                    return .deconstructRing
                }
                if ring == Self.deconstructTransferRingIndex, slot == Self.deconstructClockTwoTransferSlot {
                    return .deconstructTransfer
                }
                return .none
            }

        case .traverse:
            return .none
        }
    }

    private static let deconstructRingIndex = 3
    private static let deconstructTransferRingIndex = 5
    private static let deconstructClockTwoSlot = 6
    private static let deconstructClockTwoTransferSlot = 38

    private static func branchHighlightedSlots(for count: Int) -> Set<Int> {
        switch count {
        case 2:
            [0, 30]
        case 3:
            [10, 30, 50]
        case 4:
            [0, 15, 30, 45]
        case 5:
            [0, 10, 25, 35, 50]
        case 6:
            [0, 10, 20, 30, 40, 50]
        default:
            []
        }
    }
}
