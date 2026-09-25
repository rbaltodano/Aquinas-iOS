//
//  StudyModeView.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

/// What Study is focused on.
enum StudySubject {
    case insight(InsightModel)
    /// A Node Concept. The tree canvas itself frames the node into the slot in 3D, optionally
    /// opening with one of its Insights hovered (Study pressed on that Insight).
    case node(NodeModel, hoveredInsightID: UUID? = nil)
    /// Insights selected with the Select tool, studied together without their Node Concepts.
    case selection([InsightModel])

    var id: UUID {
        switch self {
        case .insight(let insight): insight.id
        case .node(let node, _): node.id
        case .selection(let insights): insights.first?.id ?? UUID()
        }
    }

    var title: String {
        switch self {
        case .insight(let insight): insight.title
        case .node(let node, _): node.conceptLabel
        case .selection(let insights): insights.map(\.title).joined(separator: ", ")
        }
    }
}

/// The focused shell for Study. For an Insight, each tool will eventually give the matrix its
/// own semantic behavior; this pass establishes Branch's count selection and placement surface.
/// For a Node Concept there is no matrix and no backdrop: this view only reserves the slot
/// (reported through `onNodeSlotChange`) while the tree canvas moves its camera to frame the
/// tree's own node there in 3D. The tool switcher lives in `StudyToolCard`, docked below like
/// an Insight card; the tools are not yet wired to a Node Concept.
struct StudyModeView: View {
    let subject: StudySubject
    /// The active tool, chosen in `StudyToolCard`.
    let tool: StudyTool
    let branchCount: Int
    let isExiting: Bool
    /// The Insight Tree already supplies its own focus transition. A standalone Insights page
    /// can opt in to a distinct center-icon entrance when it adopts this shared Study surface.
    var animatesCenterIconEntrance: Bool = true
    let onBranchCountChange: (Int) -> Void
    /// The node slot's frame in `InsightTreeStackSpace`.
    var onNodeSlotChange: (CGRect) -> Void = { _ in }

    @State private var hasEntered: Bool = false
    @State private var showsCenterIcon: Bool = false
    /// Height of the removed title row, kept so the slot stays where it was.
    private static let removedTitleHeight: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // A Node Concept is studied in the tree canvas itself, which fades the rest of the
                // tree; only the Insight view covers the tree.
                if case .insight = subject {
                    AquinasTheme.Colors.canvas
                        .ignoresSafeArea()
                        .opacity(hasEntered ? 1 : 0)
                }

                VStack(spacing: 48) {
                    // The title row is gone; this keeps the slot at its original height.
                    Color.clear
                        .frame(height: Self.removedTitleHeight)
                        .padding(.top, max(proxy.safeAreaInsets.top, 20) + 28)

                    switch subject {
                    case .insight(let insight):
                        StudyDotMatrix(
                            insightID: insight.id,
                            tool: tool,
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
                    case .node, .selection:
                        // Reserves and reports the slot the canvas frames the node into.
                        Color.clear
                            .frame(width: 300, height: 300)
                            .onGeometryChange(for: CGRect.self) { proxy in
                                proxy.frame(in: .named(InsightTreeStackSpace.name))
                            } action: { frame in
                                onNodeSlotChange(frame)
                            }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .task(id: subject.id) {
            hasEntered = false
            showsCenterIcon = !animatesCenterIconEntrance
            withAnimation(.easeOut(duration: 0.2)) {
                hasEntered = true
            }
            guard animatesCenterIconEntrance else { return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
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
        .accessibilityLabel("Study \(subject.title)")
    }
}

/// Study's tool switcher in a docked card that matches the Insight card exactly
/// (`dockedCardChrome`), presented with the same pop-up transition.
struct StudyToolCard: View {
    let tool: StudyTool
    let transitionDirection: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        StudyToolCarousel(
            tool: tool,
            transitionDirection: transitionDirection,
            onPrevious: onPrevious,
            onNext: onNext
        )
        // The Insight card trims its bottom to offset its definition's line spacing; this
        // card ends in the page dots, so it keeps the full 32 pt for the same visual margin.
        // The copy slides past the card's edges when switching tools.
        .dockedCardChrome(bottomPadding: 32, clipsContent: false)
        .growsWhileTouched()
    }
}

/// Docked cards, like the Study floor ring, grow 5% while a finger is on them.
private struct GrowsWhileTouched: ViewModifier {
    @State private var isTouched = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isTouched ? 1.05 : 1)
            .animation(.easeInOut(duration: 0.25), value: isTouched)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isTouched { isTouched = true } }
                    .onEnded { _ in isTouched = false }
            )
    }
}

extension View {
    func growsWhileTouched() -> some View {
        modifier(GrowsWhileTouched())
    }
}

enum StudyTool: String, CaseIterable, Hashable {
    case branch
    case deconstruct
    case sequence

    var title: LocalizedStringResource {
        switch self {
        case .branch: "Branch"
        case .deconstruct: "Deconstruct"
        case .sequence: "Sequence"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .branch: "Explore concepts that are near this Insight in vector space."
        case .deconstruct: "Break this Insight into its core semantic parts."
        case .sequence: "Explore the stages, steps, or chain of events that shape this Insight."
        }
    }

    var position: Int {
        switch self {
        case .branch: 1
        case .deconstruct: 2
        case .sequence: 3
        }
    }

    var next: Self { Self.allCases[position % Self.allCases.count] }
    var previous: Self { Self.allCases[(position - 2 + Self.allCases.count) % Self.allCases.count] }
}

/// Kept in case it becomes useful again; only Insights without an ordinary parent Node Concept
/// (placed midpoints) reach it. Remove before launch if still unused (Documentation/Study-Tool.md).
private struct StudyDotMatrix: View {
    let insightID: UUID
    let tool: StudyTool
    let branchCount: Int
    let isVisible: Bool
    let isExiting: Bool
    let showsCenterIcon: Bool
    let onBranchCountChange: (Int) -> Void

    private let dots = StudyMatrixDot.points
    /// Kept behind a feature flag while the Branch visual language is being evaluated.
    private let showsBranchConnectionLines = false
    @State private var hapticPattern = StudyToolHapticPattern()
    @State private var previousDragAngle: CGFloat?
    @State private var accumulatedRotation: CGFloat = 0
    @State private var deconstructPhase: DeconstructPhase = .inactive
    @State private var firstPresentedToolID: UUID?
    @State private var previousTool: StudyTool?
    @State private var branchEntryGeneration: Int = 0
    @State private var isBranchEntryAnimating: Bool = false
    @State private var branchLineProgress: CGFloat = 0
    @State private var displayedBranchCount: Int?
    @State private var previousBranchCount: Int?
    @State private var isBranchCountTransitioning: Bool = false
    @State private var isBranchCountDragging: Bool = false
    @State private var branchLinesNeedRedraw: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                if showsBranchConnectionLines, tool == .branch, let displayedBranchCount {
                    ForEach(dots.filter { $0.isBranchTarget(for: displayedBranchCount) }) { dot in
                        BranchConnectionLine(
                            center: center,
                            destination: CGPoint(
                                x: center.x + dot.x * diameter / 2,
                                y: center.y + dot.y * diameter / 2
                            ),
                            progress: branchLineProgress
                        )
                    }
                }

                ForEach(dots) { dot in
                    let highlightBehavior = dot.highlightBehavior(
                        for: tool,
                        branchCount: branchCount,
                        deconstructPhase: deconstructPhase
                    )

                    StudyMatrixDotView(
                        dot: dot,
                        insightID: insightID,
                        highlightBehavior: highlightBehavior,
                        usesInstantHighlightTransition: !isBranchEntryAnimating && tool == .branch,
                        branchEntryGeneration: branchEntryGeneration,
                        isExiting: isExiting
                    )
                    .position(
                        x: center.x + dot.x * diameter / 2,
                        y: center.y + dot.y * diameter / 2
                    )
                }

                StudyInsightCenterIcon()
                    .scaleEffect(
                        showsCenterIcon
                            ? (showsBranchConnectionLines && isBranchCountTransitioning ? 1.1 : 1)
                            : 1.05
                    )
                    .opacity(showsCenterIcon ? 1 : 0)
                    .blur(radius: showsCenterIcon ? 0 : 5)
                    .shadow(
                        color: AquinasTheme.Colors.lightGreen.opacity(
                            showsBranchConnectionLines && isBranchCountTransitioning ? 0.75 : 0
                        ),
                        radius: 4,
                        x: 0,
                        y: 0
                    )
                    .animation(
                        .spring(response: 0.28, dampingFraction: 0.72),
                        value: showsCenterIcon
                    )
                    .position(center)

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
        .task(id: BranchConnectionAnimationID(
            insightID: insightID,
            tool: tool,
            branchCount: branchCount,
            isVisible: isVisible,
            isExiting: isExiting,
            isDragging: isBranchCountDragging
        )) {
            guard showsBranchConnectionLines, tool == .branch, isVisible, !isExiting else {
                branchLineProgress = 0
                displayedBranchCount = nil
                previousBranchCount = nil
                isBranchCountTransitioning = false
                branchLinesNeedRedraw = false
                return
            }

            let isCountChange = previousBranchCount.map { $0 != branchCount } ?? false
            previousBranchCount = branchCount

            if isCountChange {
                withAnimation(.easeOut(duration: 0.15)) {
                    branchLineProgress = 0
                    isBranchCountTransitioning = true
                }
                branchLinesNeedRedraw = true
            }

            if displayedBranchCount == nil {
                displayedBranchCount = branchCount
                branchLineProgress = 0
                branchLinesNeedRedraw = true
            }

            // During a radial drag, preserve the retracted state. Releasing the gesture
            // restarts this task and is the single point at which the new lines draw outward.
            guard !isBranchCountDragging, branchLinesNeedRedraw else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, tool == .branch, isVisible, !isExiting else { return }

            displayedBranchCount = branchCount
            branchLinesNeedRedraw = false
            withAnimation(.easeOut(duration: 0.15)) {
                isBranchCountTransitioning = false
            }
            withAnimation(.timingCurve(0.55, 0, 0.17, 1, duration: 1)) {
                branchLineProgress = 1
            }
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
            let isReturningToBranch = tool == .branch && previousTool != nil
            previousTool = tool

            if isReturningToBranch {
                branchEntryGeneration += 1
                isBranchEntryAnimating = true
                // Branch's per-dot delay tops out at 320 ms; retain the transition
                // state long enough for the final 200 ms spring to finish as well.
                try? await Task.sleep(for: .milliseconds(560))
                guard !Task.isCancelled, tool == .branch else { return }
                isBranchEntryAnimating = false
            }

            guard tool == .deconstruct else {
                deconstructPhase = .inactive
                return
            }

            deconstructPhase = .forming
            let sourceEntranceDelay = dots.first {
                $0.ring == 2 && $0.slot == 5
            }?.highlightDelayMilliseconds(
                for: insightID,
                behavior: .deconstructRing
            ) ?? 0
            // Transfer the emphasis as soon as the clock-two source dot has finished its own
            // stagger and growth animation, rather than waiting for the whole ring.
            try? await Task.sleep(for: .milliseconds(sourceEntranceDelay + 200))
            guard !Task.isCancelled, tool == .deconstruct else { return }
            deconstructPhase = .transferred
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
                    isBranchCountDragging = true
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
                isBranchCountDragging = false
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

private struct BranchConnectionLine: View {
    let center: CGPoint
    let destination: CGPoint
    let progress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: center)
                path.addLine(to: destination)
            }
            .trim(from: 0, to: progress)
            .stroke(
                LinearGradient(
                    stops: [
                        .init(color: AquinasTheme.Colors.headingText.opacity(0), location: 0),
                        .init(color: AquinasTheme.Colors.headingText.opacity(0), location: 0.12),
                        .init(color: AquinasTheme.Colors.headingText.opacity(0.35), location: 1)
                    ],
                    startPoint: UnitPoint(
                        x: center.x / max(proxy.size.width, 1),
                        y: center.y / max(proxy.size.height, 1)
                    ),
                    endPoint: UnitPoint(
                        x: destination.x / max(proxy.size.width, 1),
                        y: destination.y / max(proxy.size.height, 1)
                    )
                ),
                style: StrokeStyle(lineWidth: 1, lineCap: .round)
            )
        }
    }
}

private struct StudyMatrixDotView: View {
    let dot: StudyMatrixDot
    let insightID: UUID
    let highlightBehavior: StudyDotHighlightBehavior
    let usesInstantHighlightTransition: Bool
    let branchEntryGeneration: Int
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
            .animation(
                usesInstantHighlightTransition
                    ? nil
                    : .spring(response: 0.28, dampingFraction: 0.76),
                value: isHighlightVisible
            )
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
                branchEntryGeneration: branchEntryGeneration,
                isExiting: isExiting
            )) {
                // The Deconstruct breakout skips its own delay, but still grows into place
                // immediately after the source dot completes its ring entrance.
                if highlightBehavior == .deconstructTransfer, !isExiting {
                    isVisible = true
                    hasSettled = true
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        isHighlightVisible = true
                    }
                    return
                }

                guard isVisible, isHighlighted, !isExiting else {
                    if usesInstantHighlightTransition {
                        isHighlightVisible = false
                    } else {
                        withAnimation(.easeOut(duration: 0.12)) {
                            isHighlightVisible = false
                        }
                    }
                    return
                }

                isHighlightVisible = false
                if !usesInstantHighlightTransition {
                    try? await Task.sleep(for: .milliseconds(dot.highlightDelayMilliseconds(
                        for: insightID,
                        behavior: highlightBehavior
                    )))
                }
                guard !Task.isCancelled, isHighlighted, !isExiting else { return }

                if usesInstantHighlightTransition {
                    isHighlightVisible = true
                } else {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        isHighlightVisible = true
                    }
                }
            }
    }
}

private struct HighlightAnimationID: Hashable {
    let insightID: UUID
    let behavior: StudyDotHighlightBehavior
    let isBaseVisible: Bool
    let branchEntryGeneration: Int
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

private struct BranchConnectionAnimationID: Hashable {
    let insightID: UUID
    let tool: StudyTool
    let branchCount: Int
    let isVisible: Bool
    let isExiting: Bool
    let isDragging: Bool
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
    case traverseRing
}

/// Supplies a stable, recognizable feedback signature per Study tool. Visual dots
/// remain independently timed, but their count never changes the haptic rhythm.
@MainActor
private final class StudyToolHapticPattern {
    private let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)

    /// A concise one-second physical bed for the matrix appearing: 10 evenly-spaced
    /// taps, each with a forty-percent chance of being emphasized.
    func playMatrixEntrance() async {
        guard SettingsHaptics.isEnabled else { return }

        for index in 0..<10 {
            guard !Task.isCancelled else { return }
            emit(Int.random(in: 0..<10) < 4 ? .emphasized : .light)
            guard index < 9 else { continue }
            try? await Task.sleep(for: .nanoseconds(111_111_111))
        }
    }

    /// Seven evenly spaced taps across half a second: heavy, light, light,
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
            try? await Task.sleep(for: .nanoseconds(83_333_333))
        }
    }

    func playIntro(for tool: StudyTool) async {
        guard SettingsHaptics.isEnabled else { return }

        let taps: [StudyHapticTap]
        switch tool {
        case .branch:
            taps = [.light, .light, .emphasized]
        case .deconstruct, .sequence:
            taps = [.emphasized, .light, .light]
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
        rigidGenerator.prepare()
        rigidGenerator.impactOccurred(intensity: tap == .emphasized ? 1.0 : 0.74)
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

    /// The tool at the center of the carousel. Pages sit one `pageWidth` apart around it and
    /// all move with `dragOffset`, which follows the finger 1:1 and eases to 0 after a switch.
    @State private var shownTool: StudyTool?
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var pageWidth: CGFloat = 280

    private var displayed: StudyTool { shownTool ?? tool }
    private static let settle = Animation.spring(response: 0.42, dampingFraction: 0.86)

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                Button { step(forward: false) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AquinasTheme.Colors.paragraphText)
                .accessibilityLabel("Previous Study tool")

                ZStack {
                    ForEach([displayed.previous, displayed, displayed.next], id: \.self) { page in
                        let x = CGFloat(relativeIndex(of: page)) * pageWidth + dragOffset
                        let distance = min(abs(x) / max(pageWidth, 1), 1)
                        StudyToolCopy(tool: page)
                            .offset(x: x)
                            .opacity(1 - Double(distance) * 0.9)
                            .blur(radius: distance * 6)
                            .accessibilityHidden(page != displayed)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 72)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    // A page travels past the chevrons before it fades out.
                    pageWidth = width + 80
                }

                Button { step(forward: true) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AquinasTheme.Colors.paragraphText)
                .accessibilityLabel("Next Study tool")
            }

            HStack(spacing: 6) {
                ForEach(StudyTool.allCases, id: \.position) { candidate in
                    // Follows the drag too: how centered this tool's page is, 0...1.
                    let pagePosition = CGFloat(relativeIndex(of: candidate)) + dragOffset / max(pageWidth, 1)
                    let active = max(1 - abs(pagePosition), 0)
                    Capsule()
                        .fill(AquinasTheme.Colors.paragraphText.opacity(0.35 + 0.45 * Double(active)))
                        .frame(width: 5 + 15 * active, height: 5)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .contentShape(Rectangle())
        .simultaneousGesture(toolSwipeGesture)
        .onChange(of: tool) { _, newTool in
            // Changed from outside the carousel (e.g. restored): slide in from its side.
            guard newTool != displayed else { return }
            let forward = transitionDirection >= 0
            shownTool = newTool
            dragOffset += forward ? pageWidth : -pageWidth
            withAnimation(Self.settle) { dragOffset = 0 }
        }
    }

    /// -1, 0, or 1: where a tool's page sits relative to the centered one.
    private func relativeIndex(of candidate: StudyTool) -> Int {
        if candidate == displayed { return 0 }
        if candidate == displayed.next { return 1 }
        if candidate == displayed.previous { return -1 }
        return 2
    }

    /// Centers the neighboring page, keeping everything where it is on screen, then eases the
    /// rest of the way. Next slides the copy off to the left; previous to the right.
    private func step(forward: Bool) {
        UISelectionFeedbackGenerator().selectionChanged()
        shownTool = forward ? displayed.next : displayed.previous
        dragOffset += forward ? pageWidth : -pageWidth
        withAnimation(Self.settle) { dragOffset = 0 }
        forward ? onNext() : onPrevious()
    }

    private var toolSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !isDragging {
                    // Only horizontal swipes page.
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    isDragging = true
                }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard isDragging else { return }
                isDragging = false
                let projected = value.predictedEndTranslation.width
                let threshold = pageWidth * 0.3
                if value.translation.width < -threshold || projected < -pageWidth * 0.5 {
                    step(forward: true)
                } else if value.translation.width > threshold || projected > pageWidth * 0.5 {
                    step(forward: false)
                } else {
                    withAnimation(Self.settle) { dragOffset = 0 }
                }
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
                    + ((ring == 2 || ring == 3 || ring == radii.indices.last) ? -.pi / 2 : CGFloat(ring) * 0.23)
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
        // The final shrink-to-dismiss occupies 200 ms, leaving a 300 ms reverse
        // stagger so the full dot exit completes in half a second.
        (1_000 - delayMilliseconds(for: insightID)) * 3 / 8
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
        case .traverseRing:
            behaviorSeed = 4_873
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

        case .sequence:
            // Traverse currently uses the closest available ring as a simple placeholder
            // for the starting point of a semantic journey outward.
            return ring == Self.traverseRingIndex ? .traverseRing : .none
        }
    }

    func isBranchTarget(for count: Int) -> Bool {
        ring == 6 && Self.branchHighlightedSlots(for: count).contains(slot)
    }

    private static let deconstructRingIndex = 2
    private static let deconstructTransferRingIndex = 4
    private static let deconstructClockTwoSlot = 5
    private static let deconstructClockTwoTransferSlot = 34
    private static let traverseRingIndex = 0

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
