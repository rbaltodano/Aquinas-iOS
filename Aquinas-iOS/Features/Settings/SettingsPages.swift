//
//  SettingsPages.swift
//  Aquinas-iOS
//

import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
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

struct AppExperienceSettingsView: View {
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

struct NotificationSettingsView: View {
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

struct PrivacyAndDataSettingsView: View {
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

struct ModelBehaviorSettingsView: View {
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

struct ModelActivitySettingsView: View {
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

struct TextAndDisplaySettingsView: View {
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

struct ConversationDefaultsSettingsView: View {
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

struct SettingsInformationView: View {
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
