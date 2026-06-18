//
//  SettingsView.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

// MARK: - Settings

struct SettingsView: View {
    @Binding var colorSchemeOverride: ColorScheme?
    @Binding var userName: String
    @Binding var customInstructions: String
    @Binding var conversationFontSize: ConversationFontSizeOption
    @Binding var inputTextAlignment: InputTextAlignmentOption
    @Binding var inputFont: ConversationFontOption
    @Binding var responseFont: ConversationFontOption
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
                VStack(alignment: .center, spacing: 48) {
                    Text("Settings")
                        .font(.custom("LibreBaskerville-Regular", size: 28))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .lineSpacing(14)
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 60) {
                        SettingsSection(title: "General") {
                            VStack(alignment: .leading, spacing: 8) {
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
                                    .frame(width: 180, alignment: .trailing)
                                }

                                SettingsRow(title: "Appearance") {
                                    HStack(spacing: 8) {
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
                            }
                        }

                        SettingsSection(title: "Conversations") {
                            VStack(alignment: .leading, spacing: 8) {
                                SettingsRow(title: "Font Size") {
                                    FontSizeSegmentedControl(selection: $conversationFontSize)
                                }

                                SettingsRow(title: "Input Text Allignment") {
                                    IconSegmentedControl(selection: $inputTextAlignment)
                                }

                                SettingsRow(title: "Input Font") {
                                    FontSegmentedControl(selection: $inputFont)
                                }

                                SettingsRow(title: "Response Font") {
                                    FontSegmentedControl(selection: $responseFont)
                                }
                            }
                        }

                        SettingsSection(title: "Conversations") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Custom Instructions")
                                    .font(.custom("Figtree-Bold", size: 14))
                                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                                    .lineSpacing(14)

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
                                .frame(minHeight: 60, alignment: .topLeading)
                                .background(AquinasTheme.Colors.canvas)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AquinasTheme.Colors.darkBrown.opacity(0.15), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 24)
                .padding(.top, 96)
                .frame(maxWidth: .infinity, alignment: .top)
            }

            AquinasNavButton(onMenuTap: onOpenMenu)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 24)
                .padding(.leading, 24)
                .zIndex(2)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.custom("LibreBaskerville-Regular", size: 18))
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .lineSpacing(9)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.custom("Figtree-Bold", size: 14))
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .lineSpacing(14)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 12)

            content
        }
        .frame(maxWidth: .infinity, minHeight: 28)
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

enum InputTextAlignmentOption: CaseIterable, Identifiable {
    case center
    case left

    var id: Self { self }

    var textAlignment: TextAlignment {
        switch self {
        case .center:
            return .center
        case .left:
            return .leading
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .center:
            return .center
        case .left:
            return .leading
        }
    }

    var inputContainerPadding: EdgeInsets {
        EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    }

    var inputContainerRadius: CGFloat {
        24
    }

    var inputContainerBorderOpacity: CGFloat {
        switch self {
        case .center:
            return 0
        case .left:
            return 0.15
        }
    }

    var iconName: String {
        switch self {
        case .center:
            return "text.aligncenter"
        case .left:
            return "text.alignleft"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .center:
            return "Align input text center"
        case .left:
            return "Align input text left"
        }
    }
}

enum ConversationFontOption: String, CaseIterable, Identifiable {
    case sans = "Sans"
    case serif = "Serif"

    var id: Self { self }

    var textFont: Font {
        textFont(size: .large)
    }

    func textFont(size: ConversationFontSizeOption) -> Font {
        switch self {
        case .sans:
            return .custom("Figtree-Regular", size: size.pointSize)
        case .serif:
            return .custom("LibreBaskerville-Regular", size: size.pointSize)
        }
    }
}

enum ConversationFontSizeOption: String, CaseIterable, Identifiable {
    case large = "Large"
    case medium = "Medium"
    case small = "Small"

    var id: Self { self }

    var pointSize: CGFloat {
        switch self {
        case .small:
            return 12
        case .medium:
            return 14
        case .large:
            return 16
        }
    }
}

private struct IconSegmentedControl: View {
    @Binding var selection: InputTextAlignmentOption
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(InputTextAlignmentOption.allCases) { option in
                Button {
                    guard selection != option else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        selection = option
                    }
                } label: {
                    Image(systemName: option.iconName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .frame(width: 58.5, height: 26.125)
                        .background(
                            ZStack {
                                if selection == option {
                                    Capsule()
                                        .fill(AquinasTheme.Colors.systemSelection)
                                        .matchedGeometryEffect(id: "input-alignment-selection", in: selectionNamespace)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel)
            }
        }
        .padding(4)
        .background(AquinasTheme.Colors.canvas)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AquinasTheme.Colors.darkBrown.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct FontSizeSegmentedControl: View {
    @Binding var selection: ConversationFontSizeOption
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ConversationFontSizeOption.allCases) { option in
                Button {
                    guard selection != option else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        selection = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.custom("Figtree-Bold", size: 12))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .lineSpacing(6)
                        .frame(width: 76, height: 34)
                        .background(
                            ZStack {
                                if selection == option {
                                    Capsule()
                                        .fill(AquinasTheme.Colors.systemSelection)
                                        .matchedGeometryEffect(id: "font-size-selection", in: selectionNamespace)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AquinasTheme.Colors.canvas)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AquinasTheme.Colors.darkBrown.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct FontSegmentedControl: View {
    @Binding var selection: ConversationFontOption
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ConversationFontOption.allCases) { option in
                Button {
                    guard selection != option else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        selection = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.custom("Figtree-Bold", size: 12))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .lineSpacing(6)
                        .frame(width: 76, height: 34)
                        .background(
                            ZStack {
                                if selection == option {
                                    Capsule()
                                        .fill(AquinasTheme.Colors.systemSelection)
                                        .matchedGeometryEffect(id: "font-selection", in: selectionNamespace)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AquinasTheme.Colors.canvas)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AquinasTheme.Colors.darkBrown.opacity(0.05), lineWidth: 1)
        )
    }
}
