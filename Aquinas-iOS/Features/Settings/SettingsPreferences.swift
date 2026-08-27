//
//  SettingsPreferences.swift
//  Aquinas-iOS
//

import Foundation
import UserNotifications

protocol SettingsChoice: CaseIterable, Hashable, Identifiable {
    var title: LocalizedStringResource { get }
}

extension SettingsChoice {
    var id: Self { self }
}

enum SettingsStorageKey {
    static let customInstructions = "aquinas.settings.customInstructions"
    static let hapticFeedback = "aquinas.settings.hapticFeedback"
    static let defaultStartScreen = "aquinas.settings.defaultStartScreen"
    static let dailyQuestionNotifications = "aquinas.settings.dailyQuestionNotifications"
    static let completedResponseNotifications = "aquinas.settings.completedResponseNotifications"
    static let dailyQuestionReminderTime = "aquinas.settings.dailyQuestionReminderTime"
    static let conversationMemory = "aquinas.settings.conversationMemory"
    static let appLock = "aquinas.settings.appLock"
    static let appLockGracePeriod = "aquinas.settings.appLockGracePeriod"
    static let conversationalInitiative = "aquinas.settings.conversationalInitiative"
    static let knowledgeLevel = "aquinas.settings.knowledgeLevel"
    static let intellectualChallenge = "aquinas.settings.intellectualChallenge"
    static let theologicalFraming = "aquinas.settings.theologicalFraming"
    static let responseFormat = "aquinas.settings.responseFormat"
    static let citationPreference = "aquinas.settings.citationPreference"
    static let citationFormat = "aquinas.settings.citationFormat"
    static let linkHandling = "aquinas.settings.linkHandling"
    static let modelActivityDisplay = "aquinas.settings.modelActivityDisplay"
    static let conversationTitles = "aquinas.settings.conversationTitles"
    static let insightMapping = "aquinas.settings.insightMapping"
    static let definitionHighlights = "aquinas.settings.definitionHighlights"
    static let dailyQuestionFocus = "aquinas.settings.dailyQuestionFocus"
    /// Retains the original question-alignment key so existing preferences migrate seamlessly
    /// when question and response alignment become one conversation-wide setting.
    static let conversationTextAlignment = "aquinas.settings.inputTextAlignment"
    static let legacyResponseTextAlignment = "aquinas.settings.responseTextAlignment"

    static let allResettableKeys = [
        customInstructions,
        hapticFeedback,
        defaultStartScreen,
        dailyQuestionNotifications,
        completedResponseNotifications,
        dailyQuestionReminderTime,
        conversationMemory,
        appLock,
        appLockGracePeriod,
        conversationalInitiative,
        knowledgeLevel,
        intellectualChallenge,
        theologicalFraming,
        responseFormat,
        citationPreference,
        citationFormat,
        linkHandling,
        modelActivityDisplay,
        conversationTitles,
        insightMapping,
        definitionHighlights,
        dailyQuestionFocus,
        "aquinas.settings.userName",
        "aquinas.settings.conversationFontSize",
        conversationTextAlignment,
        "aquinas.settings.inputFont",
        legacyResponseTextAlignment,
        "aquinas.settings.responseFont",
        "aquinas.settings.conversationPersonality"
    ]
}

enum DefaultStartScreenOption: String, SettingsChoice {
    case home
    case newConversation
    case lastConversation

    var title: LocalizedStringResource {
        switch self {
        case .home: "Home"
        case .newConversation: "New Conversation"
        case .lastConversation: "Last Conversation"
        }
    }
}

enum ConversationMemoryOption: String, SettingsChoice {
    case off
    case personalDetails
    case fullContext

    var title: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .personalDetails: "Personal Details Only"
        case .fullContext: "Full Context"
        }
    }
}

enum AppLockGracePeriodOption: String, SettingsChoice {
    case immediately
    case oneMinute
    case fiveMinutes
    case fifteenMinutes

    var title: LocalizedStringResource {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 Minute"
        case .fiveMinutes: "After 5 Minutes"
        case .fifteenMinutes: "After 15 Minutes"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .immediately: 0
        case .oneMinute: 60
        case .fiveMinutes: 5 * 60
        case .fifteenMinutes: 15 * 60
        }
    }
}

enum ConversationalInitiativeOption: String, SettingsChoice {
    case reserved
    case adaptive
    case proactive

    var title: LocalizedStringResource {
        switch self {
        case .reserved: "Reserved"
        case .adaptive: "Adaptive"
        case .proactive: "Proactive"
        }
    }
}

enum KnowledgeLevelOption: String, SettingsChoice {
    case accessible
    case adaptive
    case advanced

    var title: LocalizedStringResource {
        switch self {
        case .accessible: "Accessible"
        case .adaptive: "Adaptive"
        case .advanced: "Advanced"
        }
    }
}

enum IntellectualChallengeOption: String, SettingsChoice {
    case supportive
    case balanced
    case rigorous

    var title: LocalizedStringResource {
        switch self {
        case .supportive: "Supportive"
        case .balanced: "Balanced"
        case .rigorous: "Rigorous"
        }
    }
}

enum TheologicalFramingOption: String, SettingsChoice {
    case onlyWhenRelevant
    case integrated
    case faithForward

    var title: LocalizedStringResource {
        switch self {
        case .onlyWhenRelevant: "Only When Relevant"
        case .integrated: "Integrated"
        case .faithForward: "Faith-Forward"
        }
    }
}

enum ResponseFormatOption: String, SettingsChoice {
    case naturalProse
    case adaptive
    case structured

    var title: LocalizedStringResource {
        switch self {
        case .naturalProse: "Natural Prose"
        case .adaptive: "Adaptive"
        case .structured: "Structured"
        }
    }
}

enum CitationPreferenceOption: String, SettingsChoice {
    case whenHelpful
    case always
    case onlyWhenAsked

    var title: LocalizedStringResource {
        switch self {
        case .whenHelpful: "When Helpful"
        case .always: "Always"
        case .onlyWhenAsked: "Only When Asked"
        }
    }
}

enum CitationFormatOption: String, SettingsChoice {
    case inlineLinks
    case footnotes
    case mla

    var title: LocalizedStringResource {
        switch self {
        case .inlineLinks: "Inline Links"
        case .footnotes: "Footnotes"
        case .mla: "MLA"
        }
    }
}

enum LinkHandlingOption: String, SettingsChoice {
    case inApp
    case systemBrowser
    case askEveryTime

    var title: LocalizedStringResource {
        switch self {
        case .inApp: "In App"
        case .systemBrowser: "System Browser"
        case .askEveryTime: "Ask Every Time"
        }
    }
}

enum ModelActivityDisplayOption: String, SettingsChoice {
    case detailed
    case compact
    case hidden

    var title: LocalizedStringResource {
        switch self {
        case .detailed: "Detailed"
        case .compact: "Compact"
        case .hidden: "Hidden"
        }
    }
}

enum ConversationTitleOption: String, SettingsChoice {
    case automatic
    case firstQuestion
    case manual

    var title: LocalizedStringResource {
        switch self {
        case .automatic: "Automatic"
        case .firstQuestion: "First Question"
        case .manual: "Manual"
        }
    }
}

enum ConversationTitlePolicy {
    static func title(
        for question: String,
        option: ConversationTitleOption
    ) -> String? {
        let cleaned = question
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !cleaned.isEmpty else { return nil }

        switch option {
        case .automatic:
            let words = cleaned
                .replacingOccurrences(of: "[^A-Za-z0-9'’\\s-]", with: " ", options: .regularExpression)
                .split(whereSeparator: \.isWhitespace)
                .prefix(5)
                .map { String($0).capitalized }
            return words.isEmpty ? "New Inquiry" : words.joined(separator: " ")
        case .firstQuestion:
            let questionWithoutTrailingPunctuation = cleaned
                .trimmingCharacters(in: .punctuationCharacters)
            guard questionWithoutTrailingPunctuation.count > 80 else {
                return questionWithoutTrailingPunctuation
            }
            return String(questionWithoutTrailingPunctuation.prefix(79)) + "…"
        case .manual:
            return nil
        }
    }
}

enum InsightMappingOption: String, SettingsChoice {
    case manual
    case adaptive
    case always

    var title: LocalizedStringResource {
        switch self {
        case .manual: "Manual"
        case .adaptive: "Adaptive"
        case .always: "Always"
        }
    }
}

enum DefinitionHighlightsOption: String, SettingsChoice {
    case off
    case adaptive
    case expanded

    var title: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .adaptive: "Adaptive"
        case .expanded: "Expanded"
        }
    }
}

enum DailyQuestionFocusOption: String, SettingsChoice {
    case varied
    case philosophy
    case theology
    case ethics
    case personalReflection
    case currentStudyTopics

    var title: LocalizedStringResource {
        switch self {
        case .varied: "Varied"
        case .philosophy: "Philosophy"
        case .theology: "Theology"
        case .ethics: "Ethics"
        case .personalReflection: "Personal Reflection"
        case .currentStudyTopics: "Current Study Topics"
        }
    }
}

enum AquinasSystemNotifications {
    static let dailyQuestionIdentifier = "aquinas.question-of-the-day"

    @MainActor
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    @MainActor
    static func scheduleDailyQuestionReminder(secondsFromMidnight: Double) async {
        guard await requestAuthorization() else { return }

        let totalMinutes = max(0, min(Int(secondsFromMidnight / 60), 23 * 60 + 59))
        var components = DateComponents()
        components.hour = totalMinutes / 60
        components.minute = totalMinutes % 60

        let content = UNMutableNotificationContent()
        content.title = "Question of the Day"
        content.body = "Today’s question is ready."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: dailyQuestionIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: true
            )
        )

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [dailyQuestionIdentifier])
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func removeDailyQuestionReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [dailyQuestionIdentifier])
    }

    static func postCompletedResponse(title: String) {
        guard UserDefaults.standard.bool(
            forKey: SettingsStorageKey.completedResponseNotifications
        ) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Response Ready"
        content.body = title
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "aquinas.completed-response.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
