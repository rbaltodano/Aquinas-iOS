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
    var onOpenMenu: () -> Void

    private var selectedAppearance: AppearanceOption {
        switch colorSchemeOverride {
        case .light:
            return .light
        case .dark:
            return .dark
        default:
            return .system
        }
    }

    var body: some View {
        ZStack {
            AquinasTheme.Colors.canvas
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    SideMenuTriggerButton(action: onOpenMenu)
                        .padding(.top, 24)

                    Text("Settings")
                        .font(.custom("LibreBaskerville-Regular", size: 28))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 28)

                    VStack(alignment: .leading, spacing: 46) {
                        SettingsRow(title: "Name") {
                            TextField(
                                "",
                                text: $userName,
                                prompt: Text("John Appleseed")
                                    .foregroundColor(AquinasTheme.Colors.paragraphText)
                            )
                                .font(.custom("Figtree-Regular", size: 14))
                                .foregroundColor(AquinasTheme.Colors.paragraphText)
                                .tint(AquinasTheme.Colors.secondaryMuted)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 160, alignment: .trailing)
                        }

                        SettingsRow(title: "Appearance") {
                            HStack(spacing: 12) {
                                ForEach(AppearanceOption.allCases) { option in
                                    AppearanceButton(
                                        option: option,
                                        isSelected: option == selectedAppearance,
                                        action: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                                colorSchemeOverride = option.colorScheme
                                            }
                                        }
                                    )
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Custom Instructions")
                                .font(.custom("Figtree-Bold", size: 14))
                                .foregroundColor(AquinasTheme.Colors.primaryReadable)

                            VStack(alignment: .leading, spacing: 0) {
                                TextField(
                                    "",
                                    text: $customInstructions,
                                    prompt: Text("Instructions apply to all conversations")
                                        .foregroundColor(AquinasTheme.Colors.placeholderText),
                                    axis: .vertical
                                )
                                .font(.custom("Figtree-Regular", size: 14))
                                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                                .tint(AquinasTheme.Colors.secondaryMuted)
                                .lineLimit(1...4)

                                Spacer(minLength: 0)
                            }
                            .padding(16)
                            .frame(minHeight: 90, alignment: .topLeading)
                            .background(AquinasTheme.Colors.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AquinasTheme.Colors.sideMenuSearchBorder, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.top, 82)

                    Spacer(minLength: 320)
                }
                .padding(.horizontal, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.custom("Figtree-Bold", size: 14))
                .foregroundColor(AquinasTheme.Colors.primaryReadable)

            Spacer(minLength: 24)

            content
        }
    }
}

private enum AppearanceOption: CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var iconName: String {
        switch self {
        case .system:
            return "iphone"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .system:
            return "Use system appearance"
        case .light:
            return "Use light appearance"
        case .dark:
            return "Use dark appearance"
        }
    }
}

private struct AppearanceButton: View {
    let option: AppearanceOption
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: option.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isSelected ? AquinasTheme.Colors.lightGreen : AquinasTheme.Colors.placeholderText)
                .padding(0)
                .frame(width: 28, height: 28, alignment: .center)
                .background(isSelected ? Color(red: 0.13, green: 0.11, blue: 0.09) : Color.clear)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .inset(by: 0.5)
                        .stroke(Color(red: 0.13, green: 0.06, blue: 0).opacity(isSelected ? 0.05 : 0), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.accessibilityLabel)
    }
}
