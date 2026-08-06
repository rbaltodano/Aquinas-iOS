//
//  InquiryControlDock.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Full context capacity of the deployed Gemma 4 E2B checkpoint.
let aquinasContextWindowLimit = 131_072

private struct OpenModelTaskPageActionKey: EnvironmentKey {
    static let defaultValue: (ModelTaskSnapshot) -> Void = { _ in }
}

extension EnvironmentValues {
    var openModelTaskPage: (ModelTaskSnapshot) -> Void {
        get { self[OpenModelTaskPageActionKey.self] }
        set { self[OpenModelTaskPageActionKey.self] = newValue }
    }
}

struct ModelCompletionNotification: Identifiable {
    let id = UUID()
    let title: String
    let openAction: @MainActor () -> Void
}

@MainActor
@Observable
final class ModelCompletionNotificationCenter {
    private(set) var notifications: [ModelCompletionNotification] = []

    func post(
        title: String,
        openAction: @escaping @MainActor () -> Void
    ) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            notifications.insert(
                ModelCompletionNotification(
                    title: title,
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
    var onClearConversation: () -> Void = {}

    var body: some View {
        ContextUsageCard(
            wordCount: wordCount,
            wordLimit: wordLimit,
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
        guard !contextCard.isCompacting else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            contextCard.isCompacting = true
            contextCard.isCompactionComplete = false
        }
        contextCard.compactTask?.cancel()
        contextCard.compactTask = Task {
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
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
    let onClearConversation: () -> Void
    let modelTasksPopupState: ModelTasksPopupState?
    let modelTasks: ModelTaskQueue?
    let confirmationTitle: String?
    let onConfirm: () -> Void
    let onDecline: () -> Void
    let controls: Controls
    @Environment(\.modelCompletionNotifications) private var completionNotifications
    @State private var controlsWidth: CGFloat = 315

    init(
        showsScrollToBottom: Bool = false,
        onScrollToBottom: @escaping () -> Void = {},
        contextCard: ContextCardState? = nil,
        contextWordCount: Int = 0,
        contextWordLimit: Int = aquinasContextWindowLimit,
        onClearConversation: @escaping () -> Void = {},
        modelTasksPopupState: ModelTasksPopupState? = nil,
        modelTasks: ModelTaskQueue? = nil,
        confirmationTitle: String? = nil,
        onConfirm: @escaping () -> Void = {},
        onDecline: @escaping () -> Void = {},
        @ViewBuilder controls: () -> Controls
    ) {
        self.showsScrollToBottom = showsScrollToBottom
        self.onScrollToBottom = onScrollToBottom
        self.contextCard = contextCard
        self.contextWordCount = contextWordCount
        self.contextWordLimit = contextWordLimit
        self.onClearConversation = onClearConversation
        self.modelTasksPopupState = modelTasksPopupState
        self.modelTasks = modelTasks
        self.confirmationTitle = confirmationTitle
        self.onConfirm = onConfirm
        self.onDecline = onDecline
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
                        width: controlsWidth,
                        onOpen: {
                            completionNotifications.open(id: notification.id)
                        },
                        onDismiss: {
                            completionNotifications.dismiss(id: notification.id)
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
                    onClearConversation: onClearConversation
                )
            } else if let modelTasksPopupState,
                      modelTasksPopupState.isOpen,
                      let modelTasks {
                ModelTasksCard(modelTasks: modelTasks)
                    .transition(.bottomDockCard)
            }

            controls
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
            controlsWidth = width
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
            value: completionNotifications?.notifications.map(\.id) ?? []
        )
        .animation(
            .spring(response: 0.42, dampingFraction: 0.86),
            value: confirmationTitle
        )
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
    let width: CGFloat
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Image("InsightNotificationIcon")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(AquinasTheme.Colors.lightGreen)
                        .frame(width: 12, height: 12)

                    Text(title)
                        .font(AquinasTheme.Typography.uiLabel)
                        .foregroundStyle(AquinasTheme.Colors.lightGreen)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(width: width)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
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
    @AppStorage(SettingsStorageKey.modelActivityDisplay)
    private var activityDisplay: ModelActivityDisplayOption = .detailed

    private var isActive: Bool {
        modelTasks.isBusy
    }

    private var totalTaskCount: Int {
        modelTasks.totalCount
    }

    private var currentTaskNumber: Int {
        min(modelTasks.currentPosition, max(totalTaskCount, 1))
    }

    private var activeStatusText: String {
        if modelTasks.isRuntimeLoading {
            return modelTasks.currentTask?.funLoadingStatusText
                ?? String(localized: "Loading...")
        }
        return modelTasks.currentTask?.funStatusText
            ?? modelTasks.currentTask?.kind.standardStatusText
            ?? String(localized: "Thinking...")
    }

    private var accessibleActiveStatusText: String {
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
        .buttonStyle(.plain)
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
    var actionTitle: String? = nil
    var secondaryActionTitle: String? = nil
    var secondaryAction: () -> Void = {}
    var confirmationTitle: String? = nil
    var onConfirm: () -> Void = {}
    var onDecline: () -> Void = {}
    var action: () -> Void = {}

    @State private var controlScale: CGFloat = 1
    @AppStorage(SettingsStorageKey.modelActivityDisplay)
    private var activityDisplay: ModelActivityDisplayOption = .detailed

    private var showsModelStatus: Bool {
        modelTasks.isBusy && activityDisplay != .hidden
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
            onDecline: onDecline
        ) {
            if showsControlPill {
                HStack(
                    alignment: .center,
                    spacing: secondaryActionTitle == nil ? 24 : 16
                ) {
                    if showsModelStatus {
                        ModelStatusButton(
                            modelTasks: modelTasks,
                            action: toggleModelTasksPopup
                        )
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }

                    if let actionTitle {
                        PageModelControlActionButton(
                            title: actionTitle,
                            action: action
                        )
                    }

                    if let secondaryActionTitle {
                        PageModelControlActionButton(
                            title: secondaryActionTitle,
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
                .scaleEffect(controlScale)
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
        .onChange(of: controlLayoutKey) { _, _ in
            controlScale = 1.05
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                controlScale = 1
            }
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

private struct PageModelControlActionButton: View {
    let title: String
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
        .buttonStyle(.plain)
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
    /// While a placed midpoint insight is generating, the dock hides its canvas actions.
    var isCanvasInsightLoading: Bool = false
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
    var onClearConversation: () -> Void = {}
    var onContextWillOpen: () -> Void = {}
    /// Owned by the hosting screen so Context state survives control-layout changes.
    let contextCard: ContextCardState

    @State private var canvasActionDrawID = UUID()
    @State private var isScrollButtonVisible = false
    @State private var controlScale: CGFloat = 1
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
        (!isCanvasMode || showsModelControlsInCanvasMode) && !isCanvasAskMode
    }

    private var showsModelStatusControl: Bool {
        activityDisplay != .hidden
            && modelTasks != nil
            && !(isCanvasMode && (
                hasCanvasInsightHover
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
    }

    private var showsContextControl: Bool {
        !isCanvasMode || (!hasSelectedCanvasItems && !isCanvasAskMode)
    }

    private var controlCount: Int {
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
        } else if hasSelectedCanvasItems {
            if hasCanvasHover {
                canvasActionCount = canAddCanvasSelection ? 1 : 0
            } else if selectedCanvasItemCount == 2 {
                canvasActionCount = 2 // Inquire + Midpoint
            } else if selectedCanvasItemCount > 2 {
                canvasActionCount = 2 // Inquire + Midpoint
            } else {
                canvasActionCount = 1 // Select only
            }
        } else if hasCanvasInsightHover {
            canvasActionCount = 3 // Select + Quote + Make Node
        } else if hasCanvasHover {
            canvasActionCount = 2 // Select + Quote
        } else {
            canvasActionCount = 0
        }
        let selectionCancelCount = isCanvasMode && hasSelectedCanvasItems ? 1 : 0
        return attachmentCount + searchCount + modelStatusCount + canvasActionCount
            + selectionCancelCount + (showsContextControl ? 1 : 0)
            + (showsSendButton ? 1 : 0)
    }

    /// Captures everything that changes the dock's visible controls — including swaps that
    /// keep the same control count but change content width (e.g. the "Add" button ↔ the
    /// "Tap another Insight" hint) — so the capsule resizes with the same spring + scale bump.
    private var controlLayoutKey: String {
        "\(controlCount)|\(modelTaskCounterKey)|\(isMidpointMode ? 1 : 0)|\(isCanvasInsightLoading ? 1 : 0)|\(hasCanvasHover ? 1 : 0)|\(hasCanvasInsightHover ? 1 : 0)|\(selectedCanvasItemCount)|\(showsSendButton ? 1 : 0)|\(canvasSearchIsActive ? 1 : 0)|\(isCanvasAskMode ? 1 : 0)"
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
            onClearConversation: onClearConversation,
            modelTasksPopupState: modelTasksPopupState,
            modelTasks: modelTasks,
            confirmationTitle: confirmationTitle,
            onConfirm: onConfirm,
            onDecline: onDecline
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
                    ModelStatusButton(
                        modelTasks: modelTasks,
                        action: handleModelStatusTap
                    )
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if isCanvasMode && isCanvasAskMode {
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
                        // selection actions (Quote + Midpoint for 2, Midpoint for 3+).
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
                        } else {
                            canvasActionButton(title: "Inquire", icon: "point.3.connected.trianglepath.dotted", action: onInquireConnection)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                            canvasActionButton(title: "Midpoint", icon: "graph.2d", action: onMidpointConcepts)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    } else {
                        // No selection yet — entry point while hovering an insight/node.
                        selectCanvasActionButton
                        if hasCanvasInsightHover {
                            canvasActionButton(title: usesCanvasAskFlow ? "Ask" : "Quote", icon: "arrow.turn.down.right", action: onQuoteCanvasItem)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                            canvasActionButton(title: "Make Node", icon: "move.3d", action: onCreateCanvasConcept)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        } else if hasCanvasHover {
                            canvasActionButton(title: usesCanvasAskFlow ? "Ask" : "Quote", icon: "arrow.turn.down.right", action: onQuoteCanvasItem)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                }

                if isCanvasMode && hasSelectedCanvasItems && !isCanvasAskMode {
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
                .padding(.horizontal, isCanvasAskMode ? 16 : 32)
                .padding(.vertical, 24)
                .fixedSize(horizontal: true, vertical: true)
                .background(AquinasTheme.Colors.canvasSecondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
                .scaleEffect(controlScale)
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
        .onChange(of: controlLayoutKey) { _, _ in
            controlScale = 1.05
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                controlScale = 1
            }
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
        .buttonStyle(.plain)
        .accessibilityLabel("Search Insights")
    }

    private func expandedCanvasSearchBar(text: Binding<String>) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Button(action: dismissCanvasSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(AquinasTheme.Colors.placeholderText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Insight search")

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
            .buttonStyle(.plain)
            .foregroundColor(AquinasTheme.Colors.placeholderText)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
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
        .buttonStyle(.plain)
    }

    private var contextButton: some View {
        Button {
            if !contextCard.isCompacting {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
                contextCard.dragY = 0
                if !contextCard.isOpen {
                    modelTasksPopupState?.reset()
                    onContextWillOpen()
                }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    contextCard.isOpen.toggle()
                }
            }
        } label: {
            let contextColor = AquinasTheme.Colors.paragraphText.opacity(0.75)
            HStack(spacing: 8) {
                ContextUsageIcon(progress: contextProgress, color: contextColor)
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(contextColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Conversation context")
    }

    private func handleModelStatusTap() {
        guard !contextCard.isCompacting else { return }
        contextCard.reset()
        onModelStatusTap()
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
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
    }

    private var clearCanvasSelectionButton: some View {
        Button(action: onClearCanvasSelection) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
                .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel current selection")
    }

    private var cancelCanvasAskButton: some View {
        Button(action: onCancelCanvasAsk) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
                .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
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
                            Text("\(formatted(wordCount)) / \(formatted(wordLimit))")
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
        .shadow(color: Color(red: 0.13, green: 0.06, blue: 0).opacity(0.15), radius: 24, x: 0, y: 16)
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
