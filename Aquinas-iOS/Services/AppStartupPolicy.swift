//
//  AppStartupPolicy.swift
//  Aquinas-iOS
//

import Foundation

enum AppStartupAction: Equatable {
    case home
    case openConversation(UUID)
    case newConversation
}

enum AppStartupPolicy {
    static func resolve(
        preference: DefaultStartScreenOption,
        conversationIDs: [UUID],
        activeConversationID: UUID?
    ) -> AppStartupAction {
        switch preference {
        case .home:
            return .home
        case .newConversation:
            return .newConversation
        case .lastConversation:
            if let activeConversationID,
               conversationIDs.contains(activeConversationID) {
                return .openConversation(activeConversationID)
            }
            if let firstConversationID = conversationIDs.first {
                return .openConversation(firstConversationID)
            }
            return .home
        }
    }
}
