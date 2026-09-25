//
//  ModelCompletionNotifications.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

private struct OpenModelTaskPageActionKey: EnvironmentKey {
    static let defaultValue: (ModelTaskSnapshot) -> Void = { _ in }
}

extension EnvironmentValues {
    var openModelTaskPage: (ModelTaskSnapshot) -> Void {
        get { self[OpenModelTaskPageActionKey.self] }
        set { self[OpenModelTaskPageActionKey.self] = newValue }
    }
}

extension EnvironmentValues {
    @Entry var modelCompletionNotifications: ModelCompletionNotificationCenter? = nil
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

extension Notification.Name {
    static let aquinasMiniScrollButtonVisibilityChanged = Notification.Name("aquinasMiniScrollButtonVisibilityChanged")
}

struct ModelCompletionNotificationPill: View {
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
