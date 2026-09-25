//
//  SettingsView.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

private struct AppearanceSettingsView: View {
    @Binding var colorSchemeOverride: ColorScheme?

    private var selectedAppearance: AppearanceOption {
        switch colorSchemeOverride {
        case .light: .light
        case .dark: .dark
        default: .system
        }
    }

    var body: some View {
        SettingsDetailScaffold(title: "Appearance") {
            SettingsControlCard {
                SettingsLabeledControl(title: "Color Scheme") {
                    HStack(spacing: 8) {
                        ForEach(AppearanceOption.allCases) { option in
                            AppearanceButton(
                                option: option,
                                isSelected: option == selectedAppearance
                            ) {
                                SettingsHaptics.playSelection()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                    colorSchemeOverride = option.colorScheme
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct AppExperienceSettingsView: View {
    @AppStorage(SettingsStorageKey.defaultStartScreen)
    private var defaultStartScreen: DefaultStartScreenOption = .home
    @AppStorage(SettingsStorageKey.hapticFeedback)
    private var hapticFeedback = true

    let onReset: () -> Void
    @State private var showsResetConfirmation = false

    var body: some View {
        SettingsDetailScaffold(title: "App Experience") {
            VStack(alignment: .leading, spacing: 24) {
                SettingsControlCard {
                    SettingsChoiceRow(
                        title: "Default Start Screen",
                        selection: $defaultStartScreen,
                        options: Array(DefaultStartScreenOption.allCases)
                    )

                    SettingsToggleRow(
                        title: "Haptic Feedback",
                        isOn: $hapticFeedback
                    )
                }

                SettingsControlCard {
                    Button(role: .destructive) {
                        showsResetConfirmation = true
                    } label: {
                        Text("Reset Settings")
                            .font(.custom("Figtree-Bold", size: 12))
                            .foregroundStyle(AquinasTheme.Colors.accentRed)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .confirmationDialog(
            "Reset all settings?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Settings", role: .destructive) {
                onReset()
                defaultStartScreen = .home
                hapticFeedback = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Conversations, memories, Study Topics, and Insights will not be deleted.")
        }
    }
}

private struct NotificationSettingsView: View {
    @AppStorage(SettingsStorageKey.dailyQuestionNotifications)
    private var dailyQuestionNotifications = false
    @AppStorage(SettingsStorageKey.completedResponseNotifications)
    private var completedResponseNotifications = false
    @AppStorage(SettingsStorageKey.dailyQuestionReminderTime)
    private var dailyQuestionReminderSeconds = 9.0 * 60.0 * 60.0

    var body: some View {
        SettingsDetailScaffold(title: "Notifications") {
            SettingsControlCard {
                SettingsToggleRow(
                    title: "Question of the Day",
                    detail: "Receive one daily reminder.",
                    isOn: $dailyQuestionNotifications
                )

                if dailyQuestionNotifications {
                    SettingsLabeledControl(title: "Reminder Time") {
                        DatePicker(
                            "Reminder Time",
                            selection: reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .tint(AquinasTheme.Colors.darkGreen)
                    }
                }

                SettingsToggleRow(
                    title: "Completed Responses",
                    detail: "Notify me when an answer finishes outside the app.",
                    isOn: $completedResponseNotifications
                )
            }
        }
        .onChange(of: dailyQuestionNotifications) { _, isEnabled in
            Task {
                await updateDailyQuestionNotifications(isEnabled: isEnabled)
            }
        }
        .onChange(of: completedResponseNotifications) { _, isEnabled in
            guard isEnabled else { return }
            Task {
                let granted = await AquinasSystemNotifications.requestAuthorization()
                if !granted {
                    completedResponseNotifications = false
                }
            }
        }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.startOfDay(for: Date())
                    .addingTimeInterval(dailyQuestionReminderSeconds)
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                dailyQuestionReminderSeconds =
                    Double((components.hour ?? 9) * 60 * 60 + (components.minute ?? 0) * 60)
                Task {
                    await AquinasSystemNotifications.scheduleDailyQuestionReminder(
                        secondsFromMidnight: dailyQuestionReminderSeconds
                    )
                }
            }
        )
    }

    @MainActor
    private func updateDailyQuestionNotifications(isEnabled: Bool) async {
        if isEnabled {
            let granted = await AquinasSystemNotifications.requestAuthorization()
            guard granted else {
                dailyQuestionNotifications = false
                return
            }
            await AquinasSystemNotifications.scheduleDailyQuestionReminder(
                secondsFromMidnight: dailyQuestionReminderSeconds
            )
        } else {
            AquinasSystemNotifications.removeDailyQuestionReminder()
        }
    }
}

private struct PrivacyAndDataSettingsView: View {
    @AppStorage(SettingsStorageKey.appLock)
    private var appLock = false
    @AppStorage(SettingsStorageKey.appLockGracePeriod)
    private var appLockGracePeriod: AppLockGracePeriodOption = .immediately
    @State private var exportDocument: AquinasConversationDocument?
    @State private var isExportingConversations = false
    @State private var isImportingConversations = false
    @State private var dataTransferError: String?
    @State private var showsClearInsightTreeConfirmation = false
    var onClearInsightTree: () -> Void = {}

    var body: some View {
        SettingsDetailScaffold(title: "Privacy & Data") {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSubsection(title: "Security") {
                    SettingsToggleRow(title: "App Lock", isOn: $appLock)

                    if appLock {
                        SettingsChoiceRow(
                            title: "Lock Grace Period",
                            selection: $appLockGracePeriod,
                            options: Array(AppLockGracePeriodOption.allCases)
                        )
                    }
                }

                SettingsSubsection(title: "Data Controls") {
                    Button(action: exportConversations) {
                        SettingsNavigationLabel(title: "Export Conversations")
                    }
                    .buttonStyle(.plain)

                    Button {
                        isImportingConversations = true
                    } label: {
                        SettingsNavigationLabel(title: "Import Conversations")
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        showsClearInsightTreeConfirmation = true
                    } label: {
                        Text("Clear Insight Tree")
                            .font(.custom("Figtree-Bold", size: 12))
                            .foregroundStyle(AquinasTheme.Colors.accentRed)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    SettingsUnavailableActionRow(title: "Delete All Conversations", isDestructive: true)
                    SettingsUnavailableActionRow(title: "Delete Memories", isDestructive: true)
                    SettingsUnavailableActionRow(title: "Delete All App Data", isDestructive: true)
                }
            }
        }
        .confirmationDialog(
            "Clear the Insight Tree?",
            isPresented: $showsClearInsightTreeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Insight Tree", role: .destructive, action: onClearInsightTree)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved Insight and the whole tree on this device. Conversations are kept. This can’t be undone. Fully quit and reopen Aquinas afterward.")
        }
        .fileExporter(
            isPresented: $isExportingConversations,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Aquinas Conversations"
        ) { result in
            if case .failure(let error) = result {
                dataTransferError = error.localizedDescription
            }
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $isImportingConversations,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importConversations(from: result)
        }
        .alert(
            "Couldn’t Transfer Conversations",
            isPresented: Binding(
                get: { dataTransferError != nil },
                set: { if !$0 { dataTransferError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(dataTransferError ?? "Please try again.")
        }
    }

    private func exportConversations() {
        do {
            exportDocument = AquinasConversationDocument(
                data: try InquiryPersistenceStore.exportData()
            )
            isExportingConversations = true
        } catch {
            dataTransferError = error.localizedDescription
        }
    }

    private func importConversations(
        from result: Result<[URL], any Error>
    ) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let snapshot = try InquiryPersistenceStore.importData(
                Data(contentsOf: url)
            )
            NotificationCenter.default.post(
                name: .aquinasConversationStoreDidImport,
                object: snapshot
            )
        } catch {
            dataTransferError = error.localizedDescription
        }
    }
}

private struct AquinasConversationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw InquiryPersistenceError.invalidImport
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension Notification.Name {
    static let aquinasConversationStoreDidImport = Notification.Name(
        "aquinas.conversation-store.did-import"
    )
}

private struct ModelBehaviorSettingsView: View {
    @Binding var userName: String
    @Binding var conversationPersonality: ConversationPersonality

    var body: some View {
        SettingsDetailScaffold(title: "Model Behavior") {
            VStack(alignment: .leading, spacing: 24) {
                SettingsControlCard {
                    SettingsTextInputRow(
                        title: "Name",
                        placeholder: "John Appleseed",
                        text: $userName
                    )
                }

                SettingsControlCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default Personality")
                            .font(.custom("Figtree-Bold", size: 12))
                            .foregroundStyle(AquinasTheme.Colors.paragraphText)

                        PersonalitySegmentedControl(selection: $conversationPersonality)

                        Text(conversationPersonality.shortDescription)
                            .font(.custom("Figtree-Regular", size: 12))
                            .foregroundStyle(AquinasTheme.Colors.paragraphText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct ResearchAndCitationsSettingsView: View {
    @AppStorage(SettingsStorageKey.citationPreference)
    private var citationPreference: CitationPreferenceOption = .whenHelpful
    @AppStorage(SettingsStorageKey.citationFormat)
    private var citationFormat: CitationFormatOption = .inlineLinks
    @AppStorage(SettingsStorageKey.linkHandling)
    private var linkHandling: LinkHandlingOption = .inApp

    var body: some View {
        SettingsDetailScaffold(title: "Research & Citations") {
            SettingsControlCard {
                SettingsChoiceRow(
                    title: "Citation Preference",
                    selection: $citationPreference,
                    options: Array(CitationPreferenceOption.allCases)
                )
                SettingsChoiceRow(
                    title: "Citation Format",
                    selection: $citationFormat,
                    options: Array(CitationFormatOption.allCases)
                )
                SettingsChoiceRow(
                    title: "Link Handling",
                    selection: $linkHandling,
                    options: Array(LinkHandlingOption.allCases)
                )
            }
        }
    }
}

private struct ModelActivitySettingsView: View {
    @AppStorage(SettingsStorageKey.modelActivityDisplay)
    private var modelActivityDisplay: ModelActivityDisplayOption = .detailed

    var body: some View {
        SettingsDetailScaffold(title: "Model Activity") {
            SettingsControlCard {
                SettingsChoiceRow(
                    title: "Activity Display",
                    selection: $modelActivityDisplay,
                    options: Array(ModelActivityDisplayOption.allCases)
                )

                ModelActivityPreview(display: modelActivityDisplay)
            }
        }
    }
}

private struct ModelActivityPreview: View {
    let display: ModelActivityDisplayOption

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.custom("Figtree-Bold", size: 12))
                .foregroundStyle(AquinasTheme.Colors.paragraphText)

            switch display {
            case .detailed:
                Text("Thinking...")
                    .font(.custom("Figtree-Regular", size: 14))
                    .foregroundStyle(AquinasTheme.Colors.primaryReadable)
            case .compact:
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(AquinasTheme.Colors.primaryReadable)
                            .frame(width: 4, height: 4)
                    }
                }
                .accessibilityLabel("Model active")
            case .hidden:
                Text("No visual activity indicator")
                    .font(.custom("Figtree-Regular", size: 12))
                    .foregroundStyle(AquinasTheme.Colors.placeholderText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TextAndDisplaySettingsView: View {
    @Binding var conversationFontSize: ConversationFontSizeOption
    @Binding var conversationTextAlignment: ConversationTextAlignmentOption
    @Binding var inputFont: ConversationFontOption
    @Binding var responseFont: ConversationFontOption

    var body: some View {
        SettingsDetailScaffold(title: "Text & Display") {
            SettingsControlCard {
                SettingsLabeledControl(title: "Font Size") {
                    FontSizeSegmentedControl(selection: $conversationFontSize)
                }
                SettingsLabeledControl(title: "Conversation Text Alignment") {
                    ConversationAlignmentSegmentedControl(selection: $conversationTextAlignment)
                }
                SettingsLabeledControl(title: "Input Font") {
                    FontSegmentedControl(selection: $inputFont)
                }
                SettingsLabeledControl(title: "Response Font") {
                    FontSegmentedControl(selection: $responseFont)
                }
            }
        }
    }
}

private struct ConversationDefaultsSettingsView: View {
    @AppStorage(SettingsStorageKey.conversationTitles)
    private var conversationTitles: ConversationTitleOption = .automatic

    var body: some View {
        SettingsDetailScaffold(title: "Conversation Defaults") {
            SettingsControlCard {
                SettingsChoiceRow(
                    title: "Conversation Titles",
                    detail: "Automatic creates a concise title after the first answer. First Question titles immediately. Manual waits for you to rename it.",
                    selection: $conversationTitles,
                    options: Array(ConversationTitleOption.allCases)
                )
            }
        }
    }
}

private struct InsightsAndDailyStudySettingsView: View {
    @AppStorage(SettingsStorageKey.insightMapping)
    private var insightMapping: InsightMappingOption = .adaptive
    @AppStorage(SettingsStorageKey.definitionHighlights)
    private var definitionHighlights: DefinitionHighlightsOption = .adaptive
    @AppStorage(SettingsStorageKey.dailyQuestionFocus)
    private var dailyQuestionFocus: DailyQuestionFocusOption = .varied

    var body: some View {
        SettingsDetailScaffold(title: "Insights & Daily Study") {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSubsection(title: "Insight Tree") {
                    SettingsChoiceRow(
                        title: "Automatic Insight Mapping",
                        selection: $insightMapping,
                        options: Array(InsightMappingOption.allCases)
                    )
                    SettingsChoiceRow(
                        title: "Definition Highlights",
                        selection: $definitionHighlights,
                        options: Array(DefinitionHighlightsOption.allCases)
                    )
                }

                SettingsSubsection(title: "Question of the Day") {
                    SettingsChoiceRow(
                        title: "Focus",
                        selection: $dailyQuestionFocus,
                        options: Array(DailyQuestionFocusOption.allCases)
                    )
                }
            }
        }
    }
}

private struct SettingsInformationView: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    var body: some View {
        SettingsDetailScaffold(title: title) {
            SettingsControlCard {
                Text(message)
                    .font(.custom("Figtree-Regular", size: 14))
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Shared Layout

private struct SettingsPageScaffold<Content: View>: View {
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

private struct SettingsDetailScaffold<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        SettingsPageScaffold(title: title) {
            content
        }
    }
}

private struct SettingsControlCard<Content: View>: View {
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

private struct SettingsSubsection<Content: View>: View {
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

private struct SettingsLabeledControl<Content: View>: View {
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

private struct SettingsChoiceRow<Option: SettingsChoice>: View {
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

private struct SettingsToggleRow: View {
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

private struct SettingsTextInputRow: View {
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

private struct SettingsNavigationLabel: View {
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

private struct SettingsUnavailableActionRow: View {
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

// MARK: - Existing Controls

private enum AppearanceOption: CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var iconName: String {
        switch self {
        case .system: "iphone"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var accessibilityLabel: LocalizedStringResource {
        switch self {
        case .system: "Use system appearance"
        case .light: "Use light appearance"
        case .dark: "Use dark appearance"
        }
    }
}

private struct AppearanceButton: View {
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

enum ConversationTextAlignmentOption: String, CaseIterable, Identifiable {
    case center
    case left

    var id: Self { self }

    var textAlignment: TextAlignment {
        switch self {
        case .center: .center
        case .left: .leading
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .center: .center
        case .left: .leading
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .center: .center
        case .left: .leading
        }
    }

    var inputContainerPadding: EdgeInsets {
        EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    }

    var inputContainerRadius: CGFloat { 24 }

    var inputContainerBorderOpacity: CGFloat {
        switch self {
        case .center: 0
        case .left: 0.15
        }
    }

    var iconName: String {
        switch self {
        case .center: "text.aligncenter"
        case .left: "text.alignleft"
        }
    }

    var accessibilityLabel: LocalizedStringResource {
        switch self {
        case .center: "Center all conversation text"
        case .left: "Align all conversation text left"
        }
    }
}

typealias InputTextAlignmentOption = ConversationTextAlignmentOption
typealias ResponseTextAlignmentOption = ConversationTextAlignmentOption

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
            .custom("Figtree-Regular", size: size.pointSize)
        case .serif:
            .custom("LibreBaskerville-Regular", size: size.pointSize)
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
        case .small: 12
        case .medium: 14
        case .large: 16
        }
    }
}

private struct PersonalitySegmentedControl: View {
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

private struct ConversationAlignmentSegmentedControl: View {
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

private struct FontSizeSegmentedControl: View {
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

private struct FontSegmentedControl: View {
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
