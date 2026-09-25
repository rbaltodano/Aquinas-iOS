//
//  ModelControlsStack.swift
//  Aquinas-iOS
//

import SwiftUI

/// Bottom-anchored vertical composition shared by every model-control surface.
/// Its middle position is intentionally reserved for the upcoming notification cards.
struct ModelControlsStack<Controls: View>: View {
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

// MARK: - Model Status Button

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

struct FloatingControlPressFeedback: ViewModifier {
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

struct FloatingControlButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}
