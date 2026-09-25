//
//  SettingsComponents.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

// MARK: - Shared Layout

struct SettingsPageScaffold<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AquinasTheme.Colors.canvas
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .center, spacing: 48) {
                    Text(title)
                        .font(.custom("LibreBaskerville-Regular", size: 28))
                        .foregroundStyle(AquinasTheme.Colors.headingText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)

                    content
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 24)
                .padding(.top, 96)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

struct SettingsDetailScaffold<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        SettingsPageScaffold(title: title) {
            content
        }
    }
}

struct SettingsControlCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct SettingsSubsection<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AquinasTheme.Typography.uiHeading)
                .foregroundStyle(AquinasTheme.Colors.headingText)

            SettingsControlCard {
                content
            }
        }
    }
}

struct SettingsLabeledControl<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.custom("Figtree-Bold", size: 12))
                .foregroundStyle(AquinasTheme.Colors.paragraphText)

            Spacer(minLength: 8)

            content
        }
        .frame(maxWidth: .infinity, minHeight: 32)
    }
}

struct SettingsChoiceRow<Option: SettingsChoice>: View {
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?
    @Binding var selection: Option
    let options: [Option]

    init(
        title: LocalizedStringResource,
        detail: LocalizedStringResource? = nil,
        selection: Binding<Option>,
        options: [Option]
    ) {
        self.title = title
        self.detail = detail
        _selection = selection
        self.options = options
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Figtree-Bold", size: 12))
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)

                if let detail {
                    Text(detail)
                        .font(.custom("Figtree-Regular", size: 11))
                        .foregroundStyle(AquinasTheme.Colors.placeholderText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Menu {
                ForEach(options) { option in
                    Button {
                        SettingsHaptics.playSelection()
                        selection = option
                    } label: {
                        HStack {
                            Text(option.title)
                            if option == selection {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection.title)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.custom("Figtree-Bold", size: 12))
                .foregroundStyle(AquinasTheme.Colors.primaryReadable)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
    }
}

struct SettingsToggleRow: View {
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?
    @Binding var isOn: Bool

    init(
        title: LocalizedStringResource,
        detail: LocalizedStringResource? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Figtree-Bold", size: 12))
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)

                if let detail {
                    Text(detail)
                        .font(.custom("Figtree-Regular", size: 11))
                        .foregroundStyle(AquinasTheme.Colors.placeholderText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(AquinasTheme.Colors.darkGreen)
        .onChange(of: isOn) { _, _ in
            SettingsHaptics.playSelection()
        }
    }
}

struct SettingsTextInputRow: View {
    let title: LocalizedStringResource
    let placeholder: LocalizedStringResource
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.custom("Figtree-Bold", size: 12))
                .foregroundStyle(AquinasTheme.Colors.paragraphText)

            Spacer(minLength: 8)

            TextField("", text: $text, prompt: Text(placeholder))
                .font(.custom("Figtree-Regular", size: 14))
                .foregroundStyle(AquinasTheme.Colors.primaryReadable)
                .multilineTextAlignment(.trailing)
                .tint(AquinasTheme.Colors.darkGreen)
        }
        .frame(minHeight: 32)
    }
}

struct SettingsNavigationLabel: View {
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Figtree-Bold", size: 12))
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)

                if let detail {
                    Text(detail)
                        .font(.custom("Figtree-Regular", size: 11))
                        .foregroundStyle(AquinasTheme.Colors.placeholderText)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AquinasTheme.Colors.placeholderText)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .contentShape(Rectangle())
    }
}

struct SettingsUnavailableActionRow: View {
    let title: LocalizedStringResource
    var isDestructive = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.custom("Figtree-Bold", size: 12))
                .foregroundStyle(
                    isDestructive
                        ? AquinasTheme.Colors.accentRed.opacity(0.45)
                        : AquinasTheme.Colors.paragraphText.opacity(0.45)
                )

            Spacer()

            Text("Coming Soon")
                .font(.custom("Figtree-Regular", size: 10))
                .foregroundStyle(AquinasTheme.Colors.placeholderText)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Unavailable")
    }
}

// MARK: - Segmented Controls

struct AppearanceButton: View {
    let option: AppearanceOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: option.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    isSelected
                        ? AquinasTheme.Colors.lightGreen
                        : AquinasTheme.Colors.placeholderText
                )
                .frame(width: 28, height: 28)
                .background(
                    isSelected
                        ? Color(red: 0.13, green: 0.11, blue: 0.09)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PersonalitySegmentedControl: View {
    @Binding var selection: ConversationPersonality
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ConversationPersonality.allCases) { option in
                Button {
                    guard selection != option else { return }
                    SettingsHaptics.playSelection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        selection = option
                    }
                } label: {
                    Text(option.displayName)
                        .font(.custom("Figtree-Bold", size: 11))
                        .foregroundStyle(AquinasTheme.Colors.primaryReadable)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(AquinasTheme.Colors.systemSelection)
                                    .matchedGeometryEffect(
                                        id: "personality-selection",
                                        in: selectionNamespace
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
                .accessibilityHint(option.shortDescription)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AquinasTheme.Colors.canvas)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(AquinasTheme.Colors.darkBrown.opacity(0.05), lineWidth: 1)
        }
    }
}

struct ConversationAlignmentSegmentedControl: View {
    @Binding var selection: ConversationTextAlignmentOption
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ConversationTextAlignmentOption.allCases) { option in
                Button {
                    guard selection != option else { return }
                    SettingsHaptics.playSelection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        selection = option
                    }
                } label: {
                    Image(systemName: option.iconName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AquinasTheme.Colors.primaryReadable)
                        .frame(width: 44, height: 26)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(AquinasTheme.Colors.systemSelection)
                                    .matchedGeometryEffect(
                                        id: "conversation-alignment-selection",
                                        in: selectionNamespace
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AquinasTheme.Colors.canvas)
        .clipShape(Capsule())
    }
}

struct FontSizeSegmentedControl: View {
    @Binding var selection: ConversationFontSizeOption
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ConversationFontSizeOption.allCases) { option in
                Button {
                    guard selection != option else { return }
                    SettingsHaptics.playSelection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        selection = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.custom("Figtree-Bold", size: 11))
                        .foregroundStyle(AquinasTheme.Colors.primaryReadable)
                        .frame(width: 54, height: 30)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(AquinasTheme.Colors.systemSelection)
                                    .matchedGeometryEffect(
                                        id: "font-size-selection",
                                        in: selectionNamespace
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AquinasTheme.Colors.canvas)
        .clipShape(Capsule())
    }
}

struct FontSegmentedControl: View {
    @Binding var selection: ConversationFontOption
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ConversationFontOption.allCases) { option in
                Button {
                    guard selection != option else { return }
                    SettingsHaptics.playSelection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        selection = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.custom("Figtree-Bold", size: 11))
                        .foregroundStyle(AquinasTheme.Colors.primaryReadable)
                        .frame(width: 54, height: 30)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(AquinasTheme.Colors.systemSelection)
                                    .matchedGeometryEffect(
                                        id: "font-selection",
                                        in: selectionNamespace
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AquinasTheme.Colors.canvas)
        .clipShape(Capsule())
    }
}

enum SettingsHaptics {
    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SettingsStorageKey.hapticFeedback) != nil else {
            return true
        }
        return defaults.bool(forKey: SettingsStorageKey.hapticFeedback)
    }

    static func playSelection() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
