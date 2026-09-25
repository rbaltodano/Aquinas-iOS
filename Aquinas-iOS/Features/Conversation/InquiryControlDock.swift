//
//  InquiryControlDock.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Full shared input-and-output KV-cache of the deployed Gemma 4 E2B LiteRT checkpoint.
let aquinasContextWindowLimit = AquinasContextBudget.totalTokenLimit

private struct OpenModelTaskPageActionKey: EnvironmentKey {
    static let defaultValue: (ModelTaskSnapshot) -> Void = { _ in }
}

extension EnvironmentValues {
    var openModelTaskPage: (ModelTaskSnapshot) -> Void {
        get { self[OpenModelTaskPageActionKey.self] }
        set { self[OpenModelTaskPageActionKey.self] = newValue }
    }
}

enum ModelCompletionNotificationKind {
    case question
    case insightDefinition
}

struct ModelCompletionNotification: Identifiable {
    let id = UUID()
    let title: String
    let kind: ModelCompletionNotificationKind
    let openAction: @MainActor () -> Void
}

@MainActor
@Observable
final class ModelCompletionNotificationCenter {
    private(set) var notifications: [ModelCompletionNotification] = []

    func post(
        title: String,
        kind: ModelCompletionNotificationKind = .question,
        openAction: @escaping @MainActor () -> Void
    ) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            notifications.insert(
                ModelCompletionNotification(
                    title: title,
                    kind: kind,
                    openAction: openAction
                ),
                at: 0
            )
        }
        if UIApplication.shared.applicationState != .active {
            AquinasSystemNotifications.postCompletedResponse(title: title)
        }
        playCompletionHaptics()
    }

    func dismiss(id: UUID) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            notifications.removeAll { $0.id == id }
        }
    }

    func open(id: UUID) {
        guard let notification = notifications.first(where: { $0.id == id }) else {
            return
        }
        dismiss(id: id)
        notification.openAction()
    }

    private func playCompletionHaptics() {
        guard SettingsHaptics.isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            generator.prepare()
            generator.impactOccurred(intensity: 0.7)
        }
    }
}

extension EnvironmentValues {
    @Entry var modelCompletionNotifications: ModelCompletionNotificationCenter? = nil
}

extension Notification.Name {
    static let aquinasMiniScrollButtonVisibilityChanged = Notification.Name("aquinasMiniScrollButtonVisibilityChanged")
}

/// Shared open/animation state for the Context row in the model-controls stack.
@Observable
final class ContextCardState {
    var isOpen = false
    var isCompacting = false
    var isCompactionComplete = false
    var dragY: CGFloat = 0
    var compactTask: Task<Void, Never>?

    func reset() {
        compactTask?.cancel()
        isOpen = false
        isCompacting = false
        isCompactionComplete = false
        dragY = 0
    }
}

@Observable
final class ModelTasksPopupState {
    var isOpen = false

    func reset() {
        isOpen = false
    }
}

/// The Context card as a real row in the bottom model-controls stack.
private struct ContextControlsStackCard: View {
    let contextCard: ContextCardState
    let wordCount: Int
    var wordLimit: Int = aquinasContextWindowLimit
    var canCompact: Bool = false
    var onCompactContext: () async -> Bool = { false }
    var onClearConversation: () -> Void = {}

    var body: some View {
        ContextUsageCard(
            wordCount: wordCount,
            wordLimit: wordLimit,
            canCompact: canCompact,
            isCompacting: contextCard.isCompacting,
            isCompactionComplete: contextCard.isCompactionComplete,
            onCompact: beginContextCompaction,
            onClear: clearConversation,
            onArrowAppear: contextArrowDidAppear
        )
        .offset(y: contextCard.dragY)
        .gesture(contextCardDismissGesture)
        .transition(.bottomDockCard)
    }

    private var contextCardDismissGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !contextCard.isCompacting else { return }
                contextCard.dragY = max(0, value.translation.height)
            }
            .onEnded { value in
                guard !contextCard.isCompacting else { return }
                let height = value.translation.height
                let predicted = value.predictedEndTranslation.height
                if height > 100 || predicted > 180 {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        contextCard.isOpen = false
                        contextCard.dragY = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        contextCard.dragY = 0
                    }
                }
            }
    }

    private func beginContextCompaction() {
        guard canCompact, !contextCard.isCompacting else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            contextCard.isCompacting = true
            contextCard.isCompactionComplete = false
        }
        contextCard.compactTask?.cancel()
        contextCard.compactTask = Task {
            let didCompact = await onCompactContext()
            guard !Task.isCancelled else { return }
            guard didCompact else {
                await MainActor.run {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        contextCard.isCompacting = false
                    }
                }
                return
            }
            await MainActor.run {
                playContextCompactedHaptics()
                withAnimation(.easeInOut(duration: 0.18)) {
                    contextCard.isCompactionComplete = true
                }
            }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    contextCard.isOpen = false
                }
            }
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            await MainActor.run {
                contextCard.isCompacting = false
                contextCard.isCompactionComplete = false
            }
        }
    }

    private func contextArrowDidAppear() {
        guard contextCard.isCompacting, !contextCard.isCompactionComplete else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
    }

    private func playContextCompactedHaptics() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.75)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            generator.prepare()
            generator.impactOccurred(intensity: 0.75)
        }
    }

    private func clearConversation() {
        contextCard.compactTask?.cancel()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)
        onClearConversation()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            contextCard.isOpen = false
            contextCard.isCompacting = false
            contextCard.isCompactionComplete = false
        }
    }
}

private struct ModelTasksCard: View {
    let modelTasks: ModelTaskQueue
    @Environment(\.openModelTaskPage) private var openModelTaskPage
    @State private var draggingTaskID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Model Tasks")
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.headingText)

                if !modelTasks.allTasks.isEmpty {
                    Spacer()

                    Text("\(modelTasks.completedTasks.count) of \(modelTasks.totalCount)")
                        .font(.custom("Figtree-Regular", size: 14))
                        .monospacedDigit()
                        .transition(.opacity)
                }
            }

            if modelTasks.allTasks.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 12, weight: .regular))
                        .frame(width: 12, height: 12)

                    Text("Model is current idle...")
                        .font(.custom("Figtree-Regular", size: 14))
                        .lineLimit(1)
                }
                .frame(minHeight: 28)
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(modelTasks.allTasks) { task in
                        ModelTaskRow(
                            task: task,
                            isDragging: draggingTaskID == task.id,
                            onOpen: {
                                openModelTaskPage(task)
                            },
                            onStop: modelTasks.stopCurrent,
                            onRemove: {
                                modelTasks.removeUpcoming(id: task.id)
                            },
                            draggingTaskID: $draggingTaskID,
                            onReorder: { draggedID in
                                guard draggedID != task.id else { return }
                                let didMove = modelTasks.moveUpcoming(
                                    id: draggedID,
                                    relativeTo: task.id,
                                    placeAfterTarget: false
                                )
                                if didMove {
                                    UIImpactFeedbackGenerator(style: .light)
                                        .impactOccurred(intensity: 0.5)
                                }
                            }
                        )
                        .transition(.opacity)
                    }
                }
                .transition(.opacity)
            }
        }
        .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: modelTasks.allTasks)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(32)
        .frame(width: 355)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(AquinasTheme.Colors.darkBrown.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ModelTaskRow: View {
    let task: ModelTaskSnapshot
    let isDragging: Bool
    let onOpen: () -> Void
    let onStop: () -> Void
    let onRemove: () -> Void
    @Binding var draggingTaskID: UUID?
    /// Called continuously as a dragged row is carried over this row, so upcoming tasks
    /// visibly reflow into their landing order before the drag is released — the same
    /// live-preview feel as rearranging objects in an auto-layout frame.
    let onReorder: (_ draggedID: UUID) -> Void

    @ViewBuilder
    var body: some View {
        if task.phase == .upcoming {
            rowContent
                .opacity(isDragging ? 0.35 : 1)
                .scaleEffect(isDragging ? 0.97 : 1, anchor: .leading)
                .onDrag {
                    draggingTaskID = task.id
                    return NSItemProvider(object: task.id.uuidString as NSString)
                }
                .onDrop(
                    of: [.text],
                    delegate: ModelTaskDropDelegate(
                        targetID: task.id,
                        draggingTaskID: $draggingTaskID,
                        onReorder: onReorder
                    )
                )
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 4) {
                    taskStatusIcon

                    Text(task.title)
                        .font(.custom("Figtree-Regular", size: 14))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            taskAction
        }
        .frame(minHeight: 28)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var taskStatusIcon: some View {
        ZStack {
            switch task.phase {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AquinasTheme.Colors.headingText)
                    .transition(.opacity)
            case .current:
                ContextUsageIcon(
                    progress: 0,
                    color: AquinasTheme.Colors.paragraphText.opacity(0.75),
                    isSpinning: true
                )
                .transition(.opacity)
            case .upcoming:
                Image(systemName: "circle.dotted")
                    .font(.system(size: 14, weight: .regular))
                    .transition(.opacity)
            }
        }
        .frame(width: 14, height: 14)
        .animation(.easeInOut(duration: 0.2), value: task.phase)
    }

    @ViewBuilder
    private var taskAction: some View {
        ZStack {
            switch task.phase {
            case .completed:
                EmptyView()
            case .current:
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop current model task")
                .transition(.opacity)
            case .upcoming:
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.5))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove queued model task")
                .transition(.opacity)
            }
        }
        .frame(width: 14, height: 14)
        .animation(.easeInOut(duration: 0.2), value: task.phase)
    }
}

/// Reorders upcoming model tasks live as a dragged row passes over another row, mirroring
/// how objects slide into place while dragging inside an auto-layout frame.
private struct ModelTaskDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingTaskID: UUID?
    let onReorder: (_ draggedID: UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingTaskID, draggingTaskID != targetID else { return }
        onReorder(draggingTaskID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingTaskID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

/// Bottom-anchored vertical composition shared by every model-control surface.
/// Its middle position is intentionally reserved for the upcoming notification cards.
private struct ModelControlsStack<Controls: View>: View {
    let showsScrollToBottom: Bool
    let onScrollToBottom: () -> Void
    let contextCard: ContextCardState?
    let contextWordCount: Int
    let contextWordLimit: Int
    let canCompactContext: Bool
    let onCompactContext: () async -> Bool
    let onClearConversation: () -> Void
    let modelTasksPopupState: ModelTasksPopupState?
    let modelTasks: ModelTaskQueue?
    let supplementalPopupIsOpen: Bool
    let supplementalPopup: AnyView?
    let confirmationTitle: String?
    let onConfirm: () -> Void
    let onDecline: () -> Void
    let controlsUpdateKey: String
    let controls: Controls
    @Environment(\.modelCompletionNotifications) private var completionNotifications
    @State private var controlsWidth: CGFloat = 315
    @State private var controlsScale: CGFloat = 1
    @State private var hasMeasuredControls = false
    @State private var controlsPulseTask: Task<Void, Never>?

    init(
        showsScrollToBottom: Bool = false,
        onScrollToBottom: @escaping () -> Void = {},
        contextCard: ContextCardState? = nil,
        contextWordCount: Int = 0,
        contextWordLimit: Int = aquinasContextWindowLimit,
        canCompactContext: Bool = false,
        onCompactContext: @escaping () async -> Bool = { false },
        onClearConversation: @escaping () -> Void = {},
        modelTasksPopupState: ModelTasksPopupState? = nil,
        modelTasks: ModelTaskQueue? = nil,
        supplementalPopupIsOpen: Bool = false,
        supplementalPopup: AnyView? = nil,
        confirmationTitle: String? = nil,
        onConfirm: @escaping () -> Void = {},
        onDecline: @escaping () -> Void = {},
        controlsUpdateKey: String = "",
        @ViewBuilder controls: () -> Controls
    ) {
        self.showsScrollToBottom = showsScrollToBottom
        self.onScrollToBottom = onScrollToBottom
        self.contextCard = contextCard
        self.contextWordCount = contextWordCount
        self.contextWordLimit = contextWordLimit
        self.canCompactContext = canCompactContext
        self.onCompactContext = onCompactContext
        self.onClearConversation = onClearConversation
        self.modelTasksPopupState = modelTasksPopupState
        self.modelTasks = modelTasks
        self.supplementalPopupIsOpen = supplementalPopupIsOpen
        self.supplementalPopup = supplementalPopup
        self.confirmationTitle = confirmationTitle
        self.onConfirm = onConfirm
        self.onDecline = onDecline
        self.controlsUpdateKey = controlsUpdateKey
        self.controls = controls()
    }

    var body: some View {
        VStack(spacing: 16) {
            if showsScrollToBottom {
                ScrollToBottomStackButton(action: onScrollToBottom)
                    .transition(.bottomDockCard)
            }

            if let completionNotifications {
                ForEach(completionNotifications.notifications) { notification in
                    ModelCompletionNotificationPill(
                        title: notification.title,
                        kind: notification.kind,
                        width: controlsWidth,
                        onOpen: {
                            completionNotifications.open(id: notification.id)
                        }
                    )
                    .transition(.bottomDockCard)
                }
            }

            if let confirmationTitle {
                ModelControlsConfirmationPill(
                    title: confirmationTitle,
                    width: controlsWidth,
                    onConfirm: onConfirm,
                    onDecline: onDecline
                )
                .transition(.bottomDockCard)
            }

            if let contextCard, contextCard.isOpen {
                ContextControlsStackCard(
                    contextCard: contextCard,
                    wordCount: contextWordCount,
                    wordLimit: contextWordLimit,
                    canCompact: canCompactContext,
                    onCompactContext: onCompactContext,
                    onClearConversation: onClearConversation
                )
            } else if supplementalPopupIsOpen, let supplementalPopup {
                supplementalPopup
                    .transition(.bottomDockCard)
            } else if let modelTasksPopupState,
                      modelTasksPopupState.isOpen,
                      let modelTasks {
                ModelTasksCard(modelTasks: modelTasks)
                    .transition(.bottomDockCard)
            }

            controls
                .scaleEffect(controlsScale)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ModelControlsWidthPreferenceKey.self,
                            value: geometry.size.width
                        )
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onPreferenceChange(ModelControlsWidthPreferenceKey.self) { width in
            guard width > 0, abs(controlsWidth - width) > 0.5 else { return }
            let shouldPulseForSizeChange = hasMeasuredControls
            hasMeasuredControls = true
            controlsWidth = width
            if shouldPulseForSizeChange {
                pulseControls()
            }
        }
        .onChange(of: controlsUpdateKey) { _, _ in
            pulseControls()
        }
        .onDisappear {
            controlsPulseTask?.cancel()
        }
        .animation(
            .spring(response: 0.42, dampingFraction: 0.86),
            value: showsScrollToBottom
        )
        .animation(
            .spring(response: 0.42, dampingFraction: 0.86),
            value: contextCard?.isOpen == true
        )
        .animation(
            .spring(response: 0.42, dampingFraction: 0.86),
            value: modelTasksPopupState?.isOpen == true
        )
        .animation(
            .spring(response: 0.42, dampingFraction: 0.86),
            value: supplementalPopupIsOpen
        )
        .animation(
            .spring(response: 0.42, dampingFraction: 0.86),
            value: completionNotifications?.notifications.map(\.id) ?? []
        )
        .animation(
            .spring(response: 0.42, dampingFraction: 0.86),
            value: confirmationTitle
        )
    }

    private func pulseControls() {
        controlsPulseTask?.cancel()
        withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
            controlsScale = 1.05
        }
        controlsPulseTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                controlsScale = 1
            }
        }
    }
}

private struct ModelControlsConfirmationPill: View {
    let title: String
    let width: CGFloat
    let onConfirm: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AquinasTheme.Colors.lightGreen)
                    .sfSymbolDrawOn()
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(AquinasTheme.Typography.uiLabel)
                    .foregroundStyle(AquinasTheme.Colors.headingText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button("Yes", action: onConfirm)
                    .accessibilityLabel("Confirm \(title)")

                Button("No", action: onDecline)
                    .accessibilityLabel("Decline \(title)")
            }
            .font(.custom("Figtree-Bold", size: 12))
            .foregroundStyle(AquinasTheme.Colors.headingText)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .frame(width: width, height: 50)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
    }
}

private struct ModelControlsWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 315

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ModelCompletionNotificationPill: View {
    let title: String
    let kind: ModelCompletionNotificationKind
    let width: CGFloat
    let onOpen: () -> Void

    private var iconName: String {
        switch kind {
        case .question: "QuestionNotificationIcon"
        case .insightDefinition: "InsightNotificationIcon"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .question: AquinasTheme.Colors.headingText
        case .insightDefinition: AquinasTheme.Colors.lightGreen
        }
    }

    private var titleColor: Color {
        switch kind {
        case .question: AquinasTheme.Colors.paragraphText
        case .insightDefinition: AquinasTheme.Colors.lightGreen
        }
    }

    private var accessibilityDescription: String {
        switch kind {
        case .question:
            String(localized: "View completed question: \(title)")
        case .insightDefinition:
            String(localized: "View completed Insight Definition: \(title)")
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(iconName)
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(iconColor)
                        .frame(width: 14, height: 14)

                    Text(title)
                        .font(AquinasTheme.Typography.uiLabel)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: 238, alignment: .leading)

                Spacer(minLength: 0)

                Text("View", comment: "Action that opens completed model content.")
                    .font(AquinasTheme.Typography.uiLabel)
                    .foregroundStyle(iconColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDescription)
        .padding(.horizontal, 24)
        .frame(width: width, height: 50)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(AquinasTheme.Colors.darkBrown.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct ScrollToBottomStackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(Color(hex: 0xFFFAF0))
                .frame(width: 24, height: 24)
                .background(AquinasTheme.Colors.lightBrown)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scroll to bottom")
    }
}

// MARK: - Bottom Control Dock

struct ModelStatusButton: View {
    let modelTasks: ModelTaskQueue
    let action: () -> Void
    var controlIsPressed: Binding<Bool> = .constant(false)
    /// Allows non-model background work (such as Global Insight Tree reconciliation) to use the
    /// same activity affordance without acquiring a model-runtime lease.
    var statusOverride: String? = nil
    @AppStorage(SettingsStorageKey.modelActivityDisplay)
    private var activityDisplay: ModelActivityDisplayOption = .detailed

    private var isActive: Bool {
        modelTasks.isBusy || statusOverride != nil
    }

    private var totalTaskCount: Int {
        modelTasks.totalCount
    }

    private var currentTaskNumber: Int {
        min(modelTasks.currentPosition, max(totalTaskCount, 1))
    }

    private var activeStatusText: String {
        if let statusOverride { return statusOverride }
        if modelTasks.isRuntimeLoading {
            return modelTasks.currentTask?.funLoadingStatusText
                ?? String(localized: "Loading...")
        }
        return modelTasks.currentTask?.funStatusText
            ?? modelTasks.currentTask?.kind.standardStatusText
            ?? String(localized: "Thinking...")
    }

    private var accessibleActiveStatusText: String {
        if let statusOverride { return statusOverride }
        if modelTasks.isRuntimeLoading {
            return String(localized: "Loading...")
        }
        return modelTasks.currentTask?.kind.standardStatusText
            ?? String(localized: "Thinking...")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if activityDisplay == .detailed && isActive && totalTaskCount > 1 {
                    ModelTaskCounter(
                        currentTaskNumber: currentTaskNumber,
                        totalTaskCount: totalTaskCount
                    )
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                if isActive {
                    if activityDisplay == .compact {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle()
                                    .fill(AquinasTheme.Colors.lightGreen)
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .modifier(
                            ThinkingShimmer(
                                isActive: true,
                                color: AquinasTheme.Colors.lightGreen
                            )
                        )
                        .transition(.opacity)
                    } else {
                        Text(activeStatusText)
                            .modifier(
                                ThinkingShimmer(
                                    isActive: true,
                                    color: AquinasTheme.Colors.lightGreen
                                )
                            )
                            .transition(.opacity)
                    }
                } else {
                    if activityDisplay == .compact {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle()
                                    .fill(AquinasTheme.Colors.paragraphText)
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .transition(.opacity)
                    } else {
                        Text("Idle")
                            .foregroundColor(AquinasTheme.Colors.paragraphText)
                            .transition(.opacity)
                    }
                }
            }
            .font(.custom("Figtree-SemiBold", size: 14))
            .foregroundColor(AquinasTheme.Colors.lightGreen)
            .frame(minHeight: 21)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.25), value: isActive)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: totalTaskCount)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: currentTaskNumber)
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: controlIsPressed))
        .accessibilityLabel(accessibilityStatus)
    }

    private var accessibilityStatus: String {
        guard isActive else { return String(localized: "Model status: Idle") }
        guard totalTaskCount > 1 else {
            return String(localized: "Model status: \(accessibleActiveStatusText)")
        }
        return String(
            localized: "Model status: task \(currentTaskNumber) of \(totalTaskCount), \(accessibleActiveStatusText)"
        )
    }

}

private struct FloatingControlPressFeedback: ViewModifier {
    let isButtonPressed: Bool
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed || isButtonPressed ? 1.05 : 1)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.72),
                value: isPressed || isButtonPressed
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, isPressed, _ in
                        isPressed = true
                    }
            )
    }
}

private struct FloatingControlButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

private struct ModelTaskCounter: View {
    let currentTaskNumber: Int
    let totalTaskCount: Int

    var body: some View {
        HStack(spacing: 0) {
            Text(currentTaskNumber, format: .number)
                .contentTransition(.numericText(value: Double(currentTaskNumber)))
                .animation(
                    .spring(response: 0.32, dampingFraction: 0.82),
                    value: currentTaskNumber
                )

            Text("/")

            Text(totalTaskCount, format: .number)
                .contentTransition(.numericText(value: Double(totalTaskCount)))
                .animation(
                    .spring(response: 0.32, dampingFraction: 0.82),
                    value: totalTaskCount
                )
        }
        .monospacedDigit()
    }
}

/// Compact global controls for non-conversation pages. Idle model status stays out of the way
/// here; it returns whenever the shared queue becomes active. Page-specific actions remain.
struct PageModelControls: View {
    let modelTasks: ModelTaskQueue
    let popupState: ModelTasksPopupState
    var alwaysShowModelStatus: Bool = false
    var actionTitle: String? = nil
    var secondaryActionTitle: String? = nil
    var secondaryAction: () -> Void = {}
    var confirmationTitle: String? = nil
    var onConfirm: () -> Void = {}
    var onDecline: () -> Void = {}
    var action: () -> Void = {}

    @State private var isControlButtonPressed = false
    @AppStorage(SettingsStorageKey.modelActivityDisplay)
    private var activityDisplay: ModelActivityDisplayOption = .detailed

    private var showsModelStatus: Bool {
        (alwaysShowModelStatus || modelTasks.isBusy) && activityDisplay != .hidden
    }

    private var showsControlPill: Bool {
        showsModelStatus || actionTitle != nil || secondaryActionTitle != nil
    }

    private var controlLayoutKey: String {
        let taskKey = modelTasks.isBusy
            ? "\(modelTasks.currentPosition)/\(modelTasks.totalCount)"
            : "idle"
        return "\(taskKey)|\(actionTitle ?? "")|\(secondaryActionTitle ?? "")"
    }

    var body: some View {
        ModelControlsStack(
            modelTasksPopupState: popupState,
            modelTasks: modelTasks,
            confirmationTitle: confirmationTitle,
            onConfirm: onConfirm,
            onDecline: onDecline,
            controlsUpdateKey: controlLayoutKey
        ) {
            if showsControlPill {
                HStack(
                    alignment: .center,
                    spacing: secondaryActionTitle == nil ? 24 : 16
                ) {
                    if showsModelStatus {
                        ModelStatusButton(
                            modelTasks: modelTasks,
                            action: toggleModelTasksPopup,
                            controlIsPressed: $isControlButtonPressed
                        )
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }

                    if let actionTitle {
                        PageModelControlActionButton(
                            title: actionTitle,
                            controlIsPressed: $isControlButtonPressed,
                            action: action
                        )
                    }

                    if let secondaryActionTitle {
                        PageModelControlActionButton(
                            title: secondaryActionTitle,
                            controlIsPressed: $isControlButtonPressed,
                            action: secondaryAction
                        )
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, secondaryActionTitle == nil ? 32 : 24)
                .padding(.vertical, 24)
                .fixedSize(horizontal: true, vertical: true)
                .background(AquinasTheme.Colors.canvasSecondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
                .modifier(FloatingControlPressFeedback(isButtonPressed: isControlButtonPressed))
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: controlLayoutKey)
            }
        }
        .padding(.bottom, 24)
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: AquinasTheme.Colors.canvas.opacity(0.95), location: 0),
                    .init(color: AquinasTheme.Colors.canvas.opacity(0), location: 1)
                ],
                startPoint: UnitPoint(x: 0.5, y: 0.52),
                endPoint: UnitPoint(x: 0.5, y: 0)
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
        .onChange(of: modelTasks.isBusy) { _, isBusy in
            guard !isBusy else { return }
            popupState.reset()
        }
    }

    private func toggleModelTasksPopup() {
        if !popupState.isOpen {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred(intensity: 0.65)
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            popupState.isOpen.toggle()
        }
    }
}

/// Reader-specific controls surface the shared Model Status button only while work is active,
/// allowing a document table of contents to occupy the same expanding dock position.
struct LibraryModelControls<Contents: View>: View {
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    @Binding var isContentsOpen: Bool
    var previousChapterTitle: String? = nil
    var nextChapterTitle: String? = nil
    var onPreviousChapter: () -> Void = {}
    var onNextChapter: () -> Void = {}
    let contents: Contents
    @State private var isControlButtonPressed = false

    init(
        modelTasks: ModelTaskQueue,
        modelTasksPopupState: ModelTasksPopupState,
        isContentsOpen: Binding<Bool>,
        previousChapterTitle: String? = nil,
        nextChapterTitle: String? = nil,
        onPreviousChapter: @escaping () -> Void = {},
        onNextChapter: @escaping () -> Void = {},
        @ViewBuilder contents: () -> Contents
    ) {
        self.modelTasks = modelTasks
        self.modelTasksPopupState = modelTasksPopupState
        _isContentsOpen = isContentsOpen
        self.previousChapterTitle = previousChapterTitle
        self.nextChapterTitle = nextChapterTitle
        self.onPreviousChapter = onPreviousChapter
        self.onNextChapter = onNextChapter
        self.contents = contents()
    }

    var body: some View {
        ModelControlsStack(
            modelTasksPopupState: modelTasksPopupState,
            modelTasks: modelTasks,
            supplementalPopupIsOpen: isContentsOpen,
            supplementalPopup: AnyView(contents),
            controlsUpdateKey: controlLayoutKey
        ) {
            HStack(spacing: 24) {
                if let previousChapterTitle {
                    ReaderChapterControlButton(
                        title: previousChapterTitle,
                        icon: "chevron.left",
                        iconFirst: true,
                        action: onPreviousChapter
                    )
                    .id(previousChapterTitle)
                        .transition(.blurFade)
                }

                if modelTasks.isBusy {
                    ModelStatusButton(
                        modelTasks: modelTasks,
                        action: toggleModelTasks,
                        controlIsPressed: $isControlButtonPressed
                    )
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                Button(action: toggleContents) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Contents")
                            .font(.custom("Figtree-SemiBold", size: 14))
                    }
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
                    .frame(minHeight: 21)
                }
                .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))

                if let nextChapterTitle {
                    ReaderChapterControlButton(
                        title: nextChapterTitle,
                        icon: "chevron.right",
                        iconFirst: false,
                        action: onNextChapter
                    )
                    .id(nextChapterTitle)
                        .transition(.blurFade)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .fixedSize(horizontal: true, vertical: true)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: controlLayoutKey)
        }
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [AquinasTheme.Colors.canvas.opacity(0.95), AquinasTheme.Colors.canvas.opacity(0)],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 300)
                .allowsHitTesting(false)
        }
        .onChange(of: modelTasks.isBusy) { _, isBusy in
            if !isBusy {
                modelTasksPopupState.reset()
            }
        }
    }

    private func toggleModelTasks() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isContentsOpen = false
            modelTasksPopupState.isOpen.toggle()
        }
    }

    private func toggleContents() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            modelTasksPopupState.isOpen = false
            isContentsOpen.toggle()
        }
    }

    private var controlLayoutKey: String {
        let taskKey = modelTasks.isBusy
            ? "\(modelTasks.currentPosition)/\(modelTasks.totalCount)"
            : "idle"
        return "\(previousChapterTitle ?? "")|\(nextChapterTitle ?? "")|\(taskKey)"
    }

}

private struct ReaderChapterControlButton: View {
    let title: String
    let icon: String
    let iconFirst: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if iconFirst { iconView }
                Text(title)
                if !iconFirst { iconView }
            }
            .font(.custom("Figtree-SemiBold", size: 14))
            .foregroundStyle(AquinasTheme.Colors.lightGreen)
            .frame(minHeight: 21)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var iconView: some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .sfSymbolDrawOn()
    }
}

private struct PageModelControlActionButton: View {
    let title: String
    @Binding var controlIsPressed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(.custom("Figtree-SemiBold", size: 14))
                    .contentTransition(.opacity)
            }
            .foregroundColor(AquinasTheme.Colors.lightGreen)
            .frame(minHeight: 21)
            .contentShape(Rectangle())
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $controlIsPressed))
        .accessibilityLabel(title)
    }
}

/// A single persistent control surface whose contents adapt to Branch and Canvas mode.
struct InquiryControlDock: View {
    let isCanvasMode: Bool
    @Binding var showFilePicker: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var selectedPersonality: String
    @Binding var isPersonalityMenuOpen: Bool
    let isAtBottom: Bool
    var showsModelControlsInCanvasMode: Bool = false
    var isKeyboardOpen: Bool = false
    var showsSendButton: Bool = false
    var hasCanvasHover: Bool = false
    var hasCanvasInsightHover: Bool = false
    var hasSelectedCanvasItems: Bool = false
    var selectedCanvasItemCount: Int = 0
    var onScrollToBottom: () -> Void
    var onViewEntireCanvas: () -> Void
    var onOpenInsights: () -> Void
    var onSend: () -> Void = {}
    var onSelectCanvasItem: () -> Void = {}
    var onCreateCanvasConcept: () -> Void = {}
    var onStudyCanvasInsight: () -> Void = {}
    var onInquireConnection: () -> Void = {}
    var onQuoteCanvasItem: () -> Void = {}
    /// Global and Study Topic trees use a two-step Ask flow instead of quoting immediately.
    var usesCanvasAskFlow: Bool = false
    var isCanvasAskMode: Bool = false
    var onAskInNewConversation: () -> Void = {}
    var onAskInExistingConversation: () -> Void = {}
    var onCancelCanvasAsk: () -> Void = {}
    var onMidpointConcepts: () -> Void = {}
    var isMidpointMode: Bool = false
    /// In Study the dock keeps its tree controls, with Tools in place of Study.
    var isStudyMode: Bool = false
    /// Study's tools are open (the Tools button shows light green).
    var isStudyToolsActive: Bool = false
    var onToggleStudyTools: () -> Void = {}
    /// Follows `isStudyMode`, except that leaving Study first tucks Place away (the reverse of
    /// its entrance) before the normal controls return.
    @State private var showsStudyControls = false
    @State private var isLeavingStudy = false
    var studyBranchCount: Int = 2
    var onStudyBranchCountChange: (Int) -> Void = { _ in }
    /// While a placed midpoint insight is generating, the dock hides its canvas actions.
    var isCanvasInsightLoading: Bool = false
    /// Status for background canvas work that does not run through `ModelTaskQueue`.
    var modelStatusOverride: String? = nil
    /// Shared serialized model work. Drives both the status control and its task popup.
    var modelTasks: ModelTaskQueue? = nil
    var modelTasksPopupState: ModelTasksPopupState? = nil
    var canvasSearchText: Binding<String>? = nil
    var isCanvasSearchActive: Binding<Bool>? = nil
    var canvasSearchResultIndex: Int = 0
    var canvasSearchResultCount: Int = 0
    var onCanvasSearchPrevious: () -> Void = {}
    var onCanvasSearchNext: () -> Void = {}
    var onCanvasSearchActivated: () -> Void = {}
    var onModelStatusTap: () -> Void = {}
    var confirmationTitle: String? = nil
    var onConfirm: () -> Void = {}
    var onDecline: () -> Void = {}
    var onMidpointCenter: () -> Void = {}
    var onMidpointPlace: () -> Void = {}
    var onClearCanvasSelection: () -> Void = {}
    var contextWordCount: Int = 0
    var contextWordLimit: Int = aquinasContextWindowLimit
    /// The context gauge belongs to an active conversation, not standalone tree canvases.
    var showsContextWheel: Bool = true
    var canCompactContext: Bool = false
    var onCompactContext: () async -> Bool = { false }
    var onClearConversation: () -> Void = {}
    var onContextWillOpen: () -> Void = {}
    /// Owned by the hosting screen so Context state survives control-layout changes.
    let contextCard: ContextCardState

    @State private var canvasActionDrawID = UUID()
    @State private var isScrollButtonVisible = false
    @State private var isControlButtonPressed = false
    @State private var addFlashOpacity: CGFloat = 1
    @AppStorage(SettingsStorageKey.modelActivityDisplay)
    private var activityDisplay: ModelActivityDisplayOption = .detailed
    @FocusState private var isCanvasSearchFieldFocused: Bool

    /// Flash the Add button while in Select mode with an insight hovered, hinting it can be added.
    private var shouldFlashAdd: Bool {
        canAddCanvasSelection && hasCanvasHover
    }

    private var canAddCanvasSelection: Bool {
        hasSelectedCanvasItems && selectedCanvasItemCount < CanvasSelectionPolicy.maximumCount
    }

    private func startAddFlashIfNeeded() {
        if shouldFlashAdd {
            addFlashOpacity = 1
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                addFlashOpacity = 0.5
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { addFlashOpacity = 1 }
        }
    }

    /// While a placed midpoint is generating AND nothing else is hovered/selected, canvas
    /// actions are hidden while Model Status and the context gauge remain visible.
    private var isLoadingCollapsed: Bool {
        isCanvasMode && isCanvasInsightLoading && !hasCanvasHover && !hasSelectedCanvasItems
    }

    private var showsAttachmentControl: Bool {
        (!isCanvasMode || showsModelControlsInCanvasMode) && !isCanvasAskMode && !showsStudyControls
    }

    private var showsModelStatusControl: Bool {
        !showsStudyControls && activityDisplay != .hidden
            && modelTasks != nil
            && !(isCanvasMode && (
                hasCanvasHover
                    || hasSelectedCanvasItems
                    || isMidpointMode
                    || isCanvasAskMode
            ))
    }

    private var canvasSearchIsActive: Bool {
        isCanvasSearchActive?.wrappedValue == true
    }

    private var showsCanvasSearchControl: Bool {
        isCanvasMode
            && canvasSearchText != nil
            && isCanvasSearchActive != nil
            && !hasCanvasHover
            && !hasSelectedCanvasItems
            && !isMidpointMode
            && !isCanvasInsightLoading
            && !isCanvasAskMode
            && !isStudyMode
    }

    private var showsContextControl: Bool {
        showsContextWheel
            && !showsStudyControls
            && !isCanvasMode
    }

    private var controlCount: Int {
        if showsStudyControls { return 2 }
        if isCanvasMode && isCanvasAskMode {
            return 3
        }
        if isLoadingCollapsed {
            return (showsModelStatusControl ? 1 : 0) + (showsContextControl ? 1 : 0)
        }
        if isCanvasMode && isMidpointMode {
            return (showsModelStatusControl ? 1 : 0) + 2
                + (showsContextControl ? 1 : 0) + 1
        }
        let attachmentCount = showsAttachmentControl ? 1 : 0
        let modelStatusCount = showsModelStatusControl ? 1 : 0
        let searchCount = showsCanvasSearchControl ? 1 : 0
        let canvasActionCount: Int
        if !isCanvasMode {
            canvasActionCount = 0
        } else if isStudyMode {
            canvasActionCount = (hasCanvasHover ? 1 : 0) + 1 // Quote + Tools
        } else if hasSelectedCanvasItems {
            if hasCanvasHover {
                canvasActionCount = canAddCanvasSelection ? 1 : 0
            } else if selectedCanvasItemCount >= 2 {
                canvasActionCount = 3 // Inquire + Midpoint + Study
            } else {
                canvasActionCount = 1 // Select only
            }
        } else if hasCanvasHover {
            canvasActionCount = 3 // Select + Quote + Study (Insights and Node Concepts)
        } else {
            canvasActionCount = 0
        }
        let selectionCancelCount = isCanvasMode && hasSelectedCanvasItems && !isStudyMode ? 1 : 0
        return attachmentCount + searchCount + modelStatusCount + canvasActionCount
            + selectionCancelCount + (showsContextControl ? 1 : 0)
            + (showsSendButton ? 1 : 0)
    }

    /// Captures everything that changes the dock's visible controls — including swaps that
    /// keep the same control count but change content width (e.g. the "Add" button ↔ the
    /// "Tap another Insight" hint) — so the capsule resizes with the same spring + scale bump.
    private var controlLayoutKey: String {
        let statusKey = modelStatusOverride ?? "idle"
        return "\(controlCount)|\(modelTaskCounterKey)|\(statusKey)|\(showsStudyControls ? 1 : 0)|\(studyBranchCount)|\(isMidpointMode ? 1 : 0)|\(isCanvasInsightLoading ? 1 : 0)|\(hasCanvasHover ? 1 : 0)|\(hasCanvasInsightHover ? 1 : 0)|\(selectedCanvasItemCount)|\(showsSendButton ? 1 : 0)|\(canvasSearchIsActive ? 1 : 0)|\(isCanvasAskMode ? 1 : 0)|\(isStudyMode ? 1 : 0)|\(isStudyToolsActive ? 1 : 0)"
    }

    /// Explicitly keys the pill's resize and 5% pulse to the fraction shown by Model Status.
    private var modelTaskCounterKey: String {
        guard let modelTasks, modelTasks.isBusy else { return "idle" }
        return "\(modelTasks.currentPosition)/\(modelTasks.totalCount)"
    }

    var body: some View {
        ModelControlsStack(
            showsScrollToBottom: !isCanvasMode && isScrollButtonVisible,
            onScrollToBottom: onScrollToBottom,
            contextCard: contextCard,
            contextWordCount: contextWordCount,
            contextWordLimit: contextWordLimit,
            canCompactContext: canCompactContext,
            onCompactContext: onCompactContext,
            onClearConversation: onClearConversation,
            modelTasksPopupState: modelTasksPopupState,
            modelTasks: modelTasks,
            confirmationTitle: confirmationTitle,
            onConfirm: onConfirm,
            onDecline: onDecline,
            controlsUpdateKey: controlLayoutKey
        ) {
            ZStack(alignment: .top) {
                HStack(alignment: .center, spacing: isCanvasAskMode ? 12 : 24) {
                if showsAttachmentControl {
                    attachmentButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if showsCanvasSearchControl {
                    canvasSearchButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if showsModelStatusControl, let modelTasks {
                    if let modelStatusOverride {
                        ModelStatusButton(
                            modelTasks: modelTasks,
                            action: {},
                            controlIsPressed: $isControlButtonPressed,
                            statusOverride: modelStatusOverride
                        )
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    } else {
                        ModelStatusButton(
                            modelTasks: modelTasks,
                            action: handleModelStatusTap,
                            controlIsPressed: $isControlButtonPressed
                        )
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }

                if isCanvasMode && showsStudyControls {
                    StudyBranchDockControls(
                        count: studyBranchCount,
                        onCountChange: onStudyBranchCountChange,
                        isLeaving: isLeavingStudy
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else if isCanvasMode && isCanvasAskMode {
                    canvasActionButton(
                        title: "New Conversation",
                        icon: "plus.bubble",
                        action: onAskInNewConversation
                    )
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    canvasActionButton(
                        title: "Existing Conversation",
                        icon: "bubble.left.and.bubble.right",
                        action: onAskInExistingConversation
                    )
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    cancelCanvasAskButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else if isLoadingCollapsed {
                    // Generating a placed midpoint, nothing hovered — keep only status + context.
                    EmptyView()
                } else if isCanvasMode && isMidpointMode {
                    canvasActionButton(title: "Center", icon: "lines.measurement.horizontal", action: onMidpointCenter)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    canvasActionButton(title: "Place", icon: "arrow.down", action: onMidpointPlace)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else if isCanvasMode && isStudyMode {
                    // Study keeps the tree's hover controls; Tools opens Study's tools.
                    if hasCanvasHover {
                        canvasActionButton(title: usesCanvasAskFlow ? "Ask" : "Quote", icon: "arrow.turn.down.right", action: onQuoteCanvasItem)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                    studyToolsButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else if isCanvasMode && (hasCanvasHover || hasSelectedCanvasItems) {
                    if hasSelectedCanvasItems && hasCanvasHover {
                        // Selection mode + hovering an addable insight/node:
                        // the Add button is the only control present.
                        if canAddCanvasSelection {
                            selectCanvasActionButton
                                .opacity(shouldFlashAdd ? addFlashOpacity : 1)
                                .onAppear { startAddFlashIfNeeded() }
                                .onChange(of: shouldFlashAdd) { _, _ in startAddFlashIfNeeded() }
                        }
                    } else if hasSelectedCanvasItems {
                        // Selection mode, nothing hovered: hint (1 selected) or the
                        // selection actions (Inquire, Midpoint, and Study).
                        if selectedCanvasItemCount == 1 {
                            Text("Tap another Insight for actions")
                                .font(.custom("Figtree-Bold", size: 14))
                                .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                                .fixedSize()
                                .transition(.opacity)
                        } else if selectedCanvasItemCount == 2 {
                            canvasActionButton(title: "Inquire", icon: "point.3.connected.trianglepath.dotted", action: onInquireConnection)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                            canvasActionButton(title: "Midpoint", icon: "graph.2d", action: onMidpointConcepts)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                            canvasActionButton(title: "Study", icon: "graph.3d", action: onStudyCanvasInsight)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        } else {
                            canvasActionButton(title: "Inquire", icon: "point.3.connected.trianglepath.dotted", action: onInquireConnection)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                            canvasActionButton(title: "Midpoint", icon: "graph.2d", action: onMidpointConcepts)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                            canvasActionButton(title: "Study", icon: "graph.3d", action: onStudyCanvasInsight)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    } else {
                        // No selection yet — entry point while hovering an insight/node.
                        selectCanvasActionButton
                        // Study opens for a hovered Insight or Node Concept.
                        if hasCanvasHover {
                            canvasActionButton(title: usesCanvasAskFlow ? "Ask" : "Quote", icon: "arrow.turn.down.right", action: onQuoteCanvasItem)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                            canvasActionButton(title: "Study", icon: "graph.3d", action: onStudyCanvasInsight)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                }

                if isCanvasMode && hasSelectedCanvasItems && !isCanvasAskMode && !showsStudyControls && !isStudyMode {
                    clearCanvasSelectionButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if showsContextControl {
                    contextButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if showsSendButton {
                    sendButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
                }
                .padding(.horizontal, showsStudyControls ? 0 : (isCanvasAskMode ? 16 : 32))
                .padding(.vertical, showsStudyControls ? 0 : 24)
                .fixedSize(horizontal: true, vertical: true)
                .background(AquinasTheme.Colors.canvasSecondary.opacity(showsStudyControls ? 0 : 1))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AquinasTheme.Colors.controlBorder.opacity(showsStudyControls ? 0 : 1), lineWidth: 1))
                .modifier(FloatingControlPressFeedback(isButtonPressed: isControlButtonPressed))
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: controlLayoutKey)
                .opacity(canvasSearchIsActive ? 0 : 1)
                .allowsHitTesting(!canvasSearchIsActive)

                if canvasSearchIsActive, let canvasSearchText {
                    expandedCanvasSearchBar(text: canvasSearchText)
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, isKeyboardOpen ? 8 : 24)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isKeyboardOpen)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showsSendButton)
        .animation(.easeInOut(duration: 0.24), value: canvasSearchIsActive)
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: AquinasTheme.Colors.canvas.opacity(0.95), location: 0),
                    .init(color: AquinasTheme.Colors.canvas.opacity(0), location: 1)
                ],
                startPoint: UnitPoint(x: 0.5, y: 0.52),
                endPoint: UnitPoint(x: 0.5, y: 0)
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
        .onAppear {
            isScrollButtonVisible = !isAtBottom
        }
        .onReceive(NotificationCenter.default.publisher(for: .aquinasMiniScrollButtonVisibilityChanged)) { notification in
            guard let isVisible = notification.userInfo?["isVisible"] as? Bool else { return }
            isScrollButtonVisible = isVisible
        }
        .onChange(of: hasCanvasHover) { _, selected in
            if selected { canvasActionDrawID = UUID() }
        }
        .onChange(of: hasCanvasInsightHover) { _, isHoveringInsight in
            if isHoveringInsight { dismissContextPopup() }
        }
        .onChange(of: hasSelectedCanvasItems) { _, isSelecting in
            if isSelecting { dismissContextPopup() }
        }
        .onChange(of: isCanvasAskMode) { _, isAsking in
            guard isAsking else { return }
            dismissContextPopup()
            modelTasksPopupState?.reset()
            isCanvasSearchActive?.wrappedValue = false
        }
        .onChange(of: canvasSearchIsActive) { _, isActive in
            if isActive {
                DispatchQueue.main.async {
                    isCanvasSearchFieldFocused = true
                }
            } else {
                isCanvasSearchFieldFocused = false
            }
        }
        .onDisappear {
            contextCard.compactTask?.cancel()
        }
    }

    private var canvasSearchButton: some View {
        Button(action: activateCanvasSearch) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .regular))

                Text("Search")
                    .font(.custom("Figtree-SemiBold", size: 14))
            }
            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
            .frame(minHeight: 21)
            .contentShape(Rectangle())
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
        .accessibilityLabel("Search Insights")
    }

    private func expandedCanvasSearchBar(text: Binding<String>) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Button(action: dismissCanvasSearch) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AquinasTheme.Colors.placeholderText)
                }
                .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
                .accessibilityLabel("Dismiss Insight search")

                TextField(
                    "",
                    text: text,
                    prompt: Text("Search")
                        .foregroundColor(AquinasTheme.Colors.placeholderText)
                )
                .font(.custom("Figtree-SemiBold", size: 14))
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isCanvasSearchFieldFocused)
                .accessibilityLabel("Search Insights")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 9) {
                Button(action: onCanvasSearchPrevious) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 14, height: 14)
                }
                .disabled(canvasSearchResultCount == 0)
                .accessibilityLabel("Previous search result")

                Text(searchResultFraction)
                    .font(.custom("Figtree-SemiBold", size: 14))
                    .monospacedDigit()
                    .fixedSize()

                Button(action: onCanvasSearchNext) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 14, height: 14)
                }
                .disabled(canvasSearchResultCount == 0)
                .accessibilityLabel("Next search result")
            }
            .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
            .foregroundColor(AquinasTheme.Colors.placeholderText)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
        .modifier(FloatingControlPressFeedback(isButtonPressed: isControlButtonPressed))
    }

    private var searchResultFraction: String {
        guard canvasSearchResultCount > 0 else { return "0/0" }
        return "\(max(canvasSearchResultIndex, 1))/\(canvasSearchResultCount)"
    }

    private func activateCanvasSearch() {
        dismissContextPopup()
        onCanvasSearchActivated()
        withAnimation(.easeInOut(duration: 0.24)) {
            isCanvasSearchActive?.wrappedValue = true
        }
        DispatchQueue.main.async {
            isCanvasSearchFieldFocused = true
        }
    }

    private func dismissCanvasSearch() {
        isCanvasSearchFieldFocused = false
        canvasSearchText?.wrappedValue = ""
        withAnimation(.easeInOut(duration: 0.24)) {
            isCanvasSearchActive?.wrappedValue = false
        }
    }

    private var attachmentButton: some View {
        Menu {
            Button {
                showCamera = true
            } label: {
                Label("Camera", systemImage: "camera")
            }

            Button {
                showPhotoPicker = true
            } label: {
                Label("Photo", systemImage: "photo")
            }

            Button {
                showFilePicker = true
            } label: {
                Label("File", systemImage: "doc")
            }

            Button {
                onOpenInsights()
            } label: {
                Label("Insights", systemImage: "text.bubble")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .frame(width: 16, height: 16)
        }
        .menuStyle(.button)
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
    }

    private var contextButton: some View {
        Button {
            guard !contextCard.isCompacting else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
            contextCard.dragY = 0
            if contextCard.isOpen {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    contextCard.isOpen = false
                }
                return
            }
            let otherWasOpen = modelTasksPopupState?.isOpen == true
            onContextWillOpen()
            switchPopups(
                otherIsOpen: otherWasOpen,
                closeOther: { modelTasksPopupState?.isOpen = false },
                openThis: { contextCard.isOpen = true }
            )
        } label: {
            let contextColor = AquinasTheme.Colors.paragraphText.opacity(0.75)
            HStack(spacing: 8) {
                ContextUsageIcon(progress: contextProgress, color: contextColor)
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(contextColor)
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
        .accessibilityLabel("Conversation context")
    }

    private func handleModelStatusTap() {
        guard !contextCard.isCompacting, let modelTasksPopupState else { return }
        if modelTasksPopupState.isOpen {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                modelTasksPopupState.isOpen = false
            }
            return
        }
        let otherWasOpen = contextCard.isOpen
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.65)
        onModelStatusTap()
        switchPopups(
            otherIsOpen: otherWasOpen,
            closeOther: { contextCard.reset() },
            openThis: { modelTasksPopupState.isOpen = true }
        )
    }

    /// Coordinates switching between the Context card and the Model Tasks popup: if the other one
    /// is currently open, its exit animation is allowed to fully finish before this one's entrance
    /// animation begins — the same sequential out-then-in feel used for the Insight Tree's docked
    /// cards — rather than cross-fading both at once.
    private func switchPopups(
        otherIsOpen: Bool,
        closeOther: @escaping () -> Void,
        openThis: @escaping () -> Void
    ) {
        guard otherIsOpen else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                openThis()
            }
            return
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            closeOther()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                openThis()
            }
        }
    }

    private var contextProgress: CGFloat {
        guard contextWordLimit > 0 else { return 0 }
        return min(max(CGFloat(contextWordCount) / CGFloat(contextWordLimit), 0), 1)
    }

    private func dismissContextPopup() {
        guard contextCard.isOpen else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            contextCard.reset()
        }
    }

    private func canvasActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .id("\(title)-\(canvasActionDrawID)")
                    .sfSymbolDrawOn()
                Text(title)
                    .font(.custom("Figtree-Bold", size: 14))
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
    }

    private var studyToolsButton: some View {
        Button(action: onToggleStudyTools) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.adjustable")
                    .font(.system(size: 14, weight: .semibold))
                Text("Tools")
                    .font(.custom("Figtree-Bold", size: 14))
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(isStudyToolsActive ? AquinasTheme.Colors.lightGreen : AquinasTheme.Colors.paragraphText.opacity(0.75))
            .animation(.easeInOut(duration: 0.2), value: isStudyToolsActive)
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
        .accessibilityLabel(isStudyToolsActive ? "Close Study tools" : "Open Study tools")
    }

    private var selectCanvasActionButton: some View {
        Button(action: onSelectCanvasItem) {
            HStack(spacing: 8) {
                selectionCountIcon
                Text(selectedCanvasItemCount >= 1 ? "Add concept to selection" : "Select")
                    .font(.custom("Figtree-Bold", size: 14))
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(selectedCanvasItemCount >= 1 ? AquinasTheme.Colors.lightGreen : AquinasTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
    }

    private var clearCanvasSelectionButton: some View {
        Button(action: onClearCanvasSelection) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
                .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
        .accessibilityLabel("Cancel current selection")
    }

    private var cancelCanvasAskButton: some View {
        Button(action: onCancelCanvasAsk) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
                .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
        .accessibilityLabel("Cancel Ask")
    }

    @ViewBuilder
    private var selectionCountIcon: some View {
        if selectedCanvasItemCount > 0 {
            ZStack {
                Circle()
                    .fill(AquinasTheme.Colors.lightGreen)
                Text("\(min(selectedCanvasItemCount, 99))")
                    .font(.custom("Figtree-Bold", size: selectedCanvasItemCount > 9 ? 7 : 8))
                    .foregroundColor(AquinasTheme.Colors.canvasSecondary)
            }
            .frame(width: 14, height: 14)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
        } else {
            Image(systemName: "circle.dashed")
                .font(.system(size: 14, weight: .semibold))
                .id("select-\(canvasActionDrawID)")
                .sfSymbolDrawOn()
        }
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))
    }

}

struct ContextUsageIcon: View {
    let progress: CGFloat
    let color: Color
    var isSpinning: Bool = false

    private enum Phase { case idle, spinning, settling }

    @State private var phase: Phase = .idle
    @State private var startDate = Date()
    @State private var settleAngle: Double = 0   // angle (deg) used while not actively spinning
    @State private var arc: Double = 0           // 0 = progress ring, 1 = quarter spinner
    @State private var settleTask: Task<Void, Never>? = nil

    private let revDuration: Double = 1.1         // seconds per revolution
    private let settleDuration: Double = 1.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.35), lineWidth: 1.5)
            TimelineView(.animation(paused: phase == .idle)) { timeline in
                let angle = phase == .spinning
                    ? timeline.date.timeIntervalSince(startDate) * 360.0 / revDuration
                    : settleAngle
                let trimEnd = 0.25 * arc + Double(min(max(progress, 0), 1)) * (1 - arc)
                Circle()
                    .trim(from: 0, to: trimEnd)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90 + angle))
                    .animation(.easeInOut(duration: 0.65), value: progress)
            }
        }
        .frame(width: 14, height: 14)
        .onAppear { if isSpinning { beginSpin() } }
        .onChange(of: isSpinning) { _, spinning in
            if spinning { beginSpin() } else { endSpin() }
        }
    }

    private func beginSpin() {
        settleTask?.cancel()
        startDate = Date()
        phase = .spinning
        withAnimation(.easeInOut(duration: 0.3)) { arc = 1 }
    }

    private func endSpin() {
        // Continue clockwise to the next upright position, then morph the arc back to the ring.
        let elapsed = Date().timeIntervalSince(startDate)
        let current = elapsed * 360.0 / revDuration
        let target = (current / 360.0).rounded(.up) * 360.0
        settleAngle = current
        phase = .settling
        withAnimation(.easeOut(duration: settleDuration)) {
            settleAngle = target
            arc = 0
        }
        settleTask = Task {
            try? await Task.sleep(for: .seconds(settleDuration))
            if !Task.isCancelled { phase = .idle }
        }
    }
}

private struct ContextUsageCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let wordCount: Int
    let wordLimit: Int
    let canCompact: Bool
    let isCompacting: Bool
    let isCompactionComplete: Bool
    var onCompact: () -> Void
    var onClear: () -> Void
    var onArrowAppear: () -> Void

    @State private var hasAppeared = false
    @State private var showClearConfirmation = false

    private var progress: CGFloat {
        guard wordLimit > 0 else { return 0 }
        return min(max(CGFloat(wordCount) / CGFloat(wordLimit), 0), 1)
    }

    private var progressTrackColor: Color {
        colorScheme == .dark
            ? Color(hex: 0x130F0C)
            : .white
    }

    private var progressTrackBorderColor: Color {
        colorScheme == .dark
            ? Color(hex: 0xFFFAF0, alpha: 0.08)
            : AquinasTheme.Colors.darkBrown.opacity(0.15)
    }

    private var progressFillColor: Color {
        colorScheme == .dark
            ? Color(hex: 0xFFFAF0, alpha: 0.55)
            : AquinasTheme.Colors.paragraphText.opacity(0.5)
    }

    var body: some View {
        Group {
            if isCompacting {
                if isCompactionComplete {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                            .sfSymbolDrawOn()
                        Text("Compacted")
                            .font(.custom("Figtree-SemiBold", size: 14))
                            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                    }
                    .transition(.opacity)
                } else {
                    HStack(spacing: 8) {
                        ContextCompactingIcon(onAppearCycle: onArrowAppear)
                        Text("Compacting")
                            .font(.custom("Figtree-SemiBold", size: 14))
                            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                    }
                    .transition(.opacity)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Context")
                                .font(.custom("Figtree-Bold", size: 18))
                                .foregroundColor(AquinasTheme.Colors.headingText)
                            Spacer()
                            Text("\(formatted(wordCount)) / \(formatted(wordLimit)) tokens")
                                .font(.custom("Figtree-Bold", size: 14))
                                .monospacedDigit()
                        }
                        .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(progressTrackColor)
                                    .overlay(Capsule().stroke(progressTrackBorderColor, lineWidth: 1))
                                Capsule()
                                    .fill(progressFillColor)
                                    .frame(width: progress > 0 ? max(geometry.size.width * progress, 8) : 0)
                                    .animation(.easeInOut(duration: 0.65), value: progress)
                            }
                        }
                        .frame(height: 2)
                    }

                    HStack {
                        Button("Compact", action: onCompact)
                            .disabled(!canCompact)
                            .opacity(canCompact ? 1 : 0.35)
                        Spacer()
                        Button("Clear") { showClearConfirmation = true }
                    }
                    .font(.custom("Figtree-Bold", size: 14))
                    .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .padding(isCompacting ? 14 : 32)
        .frame(width: isCompacting ? 126 : 355, height: isCompacting ? 44 : nil)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: isCompacting ? 22 : 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isCompacting ? 22 : 36, style: .continuous)
                .stroke(AquinasTheme.Colors.darkBrown.opacity(0.08), lineWidth: 1)
        )
        .scaleEffect(hasAppeared ? 1 : 0.35, anchor: .bottom)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isCompacting)
        .onAppear {
            hasAppeared = false
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    hasAppeared = true
                }
            }
        }
        .alert("Clear conversation context?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive, action: onClear)
        } message: {
            Text("This removes every question and response in this conversation and starts it fresh, so the model no longer has any of the earlier context to build on. Insights you've saved are kept. This can't be undone.")
        }
    }

    private func formatted(_ count: Int) -> String {
        if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

private struct ContextCompactingIcon: View {
    var onAppearCycle: () -> Void

    @State private var rotation = Double([0, 45, 90, 135, 180, 225, 270].randomElement() ?? 0)
    @State private var iconOpacity: Double = 0
    @State private var iconScale: CGFloat = 0.86
    @State private var iconBlur: CGFloat = 4

    var body: some View {
        Image(systemName: "line.diagonal.trianglehead.up.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
            .rotationEffect(.degrees(rotation))
            .opacity(iconOpacity)
            .scaleEffect(iconScale)
            .blur(radius: iconBlur)
            .frame(width: 16, height: 16)
            .task {
                while !Task.isCancelled {
                    onAppearCycle()
                    withAnimation(.easeOut(duration: 0.15)) {
                        iconOpacity = 1
                        iconScale = 1
                        iconBlur = 0
                    }
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeIn(duration: 0.15)) {
                        iconOpacity = 0
                        iconScale = 0.86
                        iconBlur = 4
                    }
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    let directions = [0, 45, 90, 135, 180, 225, 270].map(Double.init)
                    rotation = directions.filter { $0 != rotation }.randomElement() ?? 0
                }
            }
    }
}
