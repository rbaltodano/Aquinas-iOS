//
//  SettingsView.swift
//  Aquinas-iOS
//

import SwiftUI

// MARK: - Settings

struct SettingsView: View {
    @Binding var colorSchemeOverride: ColorScheme?
    @Binding var userName: String
    @Binding var customInstructions: String
    @Binding var conversationFontSize: ConversationFontSizeOption
    @Binding var conversationTextAlignment: ConversationTextAlignmentOption
    @Binding var inputFont: ConversationFontOption
    @Binding var responseFont: ConversationFontOption
    @Binding var conversationPersonality: ConversationPersonality
    var onOpenMenu: () -> Void
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }
    var onClearInsightTree: () -> Void = {}

    @State private var path: [SettingsRoute] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            NavigationStack(path: $path) {
                SettingsHubView { route in
                    path.append(route)
                }
                .navigationDestination(for: SettingsRoute.self) { route in
                    SettingsDestinationView(
                        route: route,
                        colorSchemeOverride: $colorSchemeOverride,
                        userName: $userName,
                        customInstructions: $customInstructions,
                        conversationFontSize: $conversationFontSize,
                        conversationTextAlignment: $conversationTextAlignment,
                        inputFont: $inputFont,
                        responseFont: $responseFont,
                        conversationPersonality: $conversationPersonality,
                        onReset: resetSettings,
                        onClearInsightTree: onClearInsightTree
                    )
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .background(AquinasTheme.Colors.canvas)

            HStack(spacing: 8) {
                AquinasNavButton(onMenuTap: onOpenMenu)
                if !path.isEmpty {
                    NavBackCapsuleButton(title: "Settings") {
                        guard !path.isEmpty else { return }
                        path.removeLast()
                    }
                    .transition(.studyExitGrow)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: path.isEmpty)
            .padding(.top, 24)
            .padding(.leading, 24)
            .zIndex(2)
        }
        .simultaneousGesture(settingsBackGesture)
        .onAppear {
            onDetailVisibilityChange(!path.isEmpty)
        }
        .onChange(of: path) { _, newPath in
            onDetailVisibilityChange(!newPath.isEmpty)
        }
        .onDisappear {
            onDetailVisibilityChange(false)
        }
    }

    private var settingsBackGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onEnded { value in
                guard !path.isEmpty,
                      value.startLocation.x < 30,
                      value.translation.width > 60,
                      abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }

                SettingsHaptics.playSelection()
                path.removeLast()
            }
    }

    private func resetSettings() {
        for key in SettingsStorageKey.allResettableKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        colorSchemeOverride = nil
        userName = ""
        customInstructions = ""
        conversationFontSize = .small
        conversationTextAlignment = .center
        inputFont = .serif
        responseFont = .sans
        conversationPersonality = .balanced
    }
}

private enum SettingsRoute: Hashable {
    case appearance
    case appExperience
    case notifications
    case privacyAndData
    case modelBehavior
    case modelActivity
    case textAndDisplay
    case conversationDefaults
    case documentation
    case reportBug
}

// MARK: - Hub

private struct SettingsHubView: View {
    let onSelect: (SettingsRoute) -> Void

    var body: some View {
        SettingsPageScaffold(title: "Settings") {
            VStack(alignment: .leading, spacing: 24) {
                SettingsHubSection(
                    title: "General",
                    rows: [
                        SettingsHubItem(title: "Appearance", iconName: "paintpalette", route: .appearance),
                        SettingsHubItem(title: "App Experience", iconName: "sparkles", route: .appExperience),
                        SettingsHubItem(title: "Notifications", iconName: "bell", route: .notifications),
                        SettingsHubItem(title: "Privacy & Data", iconName: "lock.shield", route: .privacyAndData)
                    ],
                    onSelect: onSelect
                )

                SettingsHubSection(
                    title: "Model",
                    rows: [
                        SettingsHubItem(title: "Model Behavior", iconName: "brain", route: .modelBehavior),
                        SettingsHubItem(title: "Model Activity", iconName: "waveform", route: .modelActivity)
                    ],
                    onSelect: onSelect
                )

                SettingsHubSection(
                    title: "Conversations",
                    rows: [
                        SettingsHubItem(title: "Text & Display", iconName: "textformat.size", route: .textAndDisplay),
                        SettingsHubItem(title: "Conversation Defaults", iconName: "bubble.left.and.bubble.right", route: .conversationDefaults)
                    ],
                    onSelect: onSelect
                )

                SettingsHubSection(
                    title: "Support",
                    rows: [
                        SettingsHubItem(title: "Documentation", iconName: "book", route: .documentation),
                        SettingsHubItem(title: "Report a Bug", iconName: "ladybug", route: .reportBug)
                    ],
                    onSelect: onSelect
                )
            }
        }
    }
}

private struct SettingsHubItem: Identifiable {
    let title: LocalizedStringResource
    let iconName: String
    let route: SettingsRoute

    var id: SettingsRoute { route }
}

private struct SettingsHubSection: View {
    let title: LocalizedStringResource
    let rows: [SettingsHubItem]
    let onSelect: (SettingsRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AquinasTheme.Typography.uiHeading)
                .foregroundStyle(AquinasTheme.Colors.headingText)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(rows) { row in
                    Button {
                        SettingsHaptics.playSelection()
                        onSelect(row.route)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: row.iconName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AquinasTheme.Colors.paragraphText)
                                .frame(width: 20)

                            Text(row.title)
                                .font(AquinasTheme.Typography.body)
                                .foregroundStyle(AquinasTheme.Colors.paragraphText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this settings menu")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Destinations

private struct SettingsDestinationView: View {
    let route: SettingsRoute
    @Binding var colorSchemeOverride: ColorScheme?
    @Binding var userName: String
    @Binding var customInstructions: String
    @Binding var conversationFontSize: ConversationFontSizeOption
    @Binding var conversationTextAlignment: ConversationTextAlignmentOption
    @Binding var inputFont: ConversationFontOption
    @Binding var responseFont: ConversationFontOption
    @Binding var conversationPersonality: ConversationPersonality
    let onReset: () -> Void
    var onClearInsightTree: () -> Void = {}

    var body: some View {
        switch route {
        case .appearance:
            AppearanceSettingsView(colorSchemeOverride: $colorSchemeOverride)
        case .appExperience:
            AppExperienceSettingsView(onReset: onReset)
        case .notifications:
            NotificationSettingsView()
        case .privacyAndData:
            PrivacyAndDataSettingsView(onClearInsightTree: onClearInsightTree)
        case .modelBehavior:
            ModelBehaviorSettingsView(
                userName: $userName,
                conversationPersonality: $conversationPersonality
            )
        case .modelActivity:
            ModelActivitySettingsView()
        case .textAndDisplay:
            TextAndDisplaySettingsView(
                conversationFontSize: $conversationFontSize,
                conversationTextAlignment: $conversationTextAlignment,
                inputFont: $inputFont,
                responseFont: $responseFont
            )
        case .conversationDefaults:
            ConversationDefaultsSettingsView()
        case .documentation:
            SettingsInformationView(
                title: "Documentation",
                message: "Guides for Aquinas will appear here as they become available."
            )
        case .reportBug:
            SettingsInformationView(
                title: "Report a Bug",
                message: "Bug reporting will be connected before release."
            )
        }
    }
}
