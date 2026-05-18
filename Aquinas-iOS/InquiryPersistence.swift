//
//  InquiryPersistence.swift
//  Aquinas-iOS
//

import Foundation

// MARK: - Inquiry Persistence

/// The full piece of local state needed to restore the user's conversation canvases.
struct InquiryPersistenceSnapshot: Codable, Equatable {
    var conversations: [InquiryConversation]
    var activeConversationID: UUID?
}

/// Small UserDefaults-backed store for prototype conversation memory.
enum InquiryPersistenceStore {
    private static let snapshotKey = "aquinas.inquiry.persistence.snapshot.v1"

    static func load() -> InquiryPersistenceSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(InquiryPersistenceSnapshot.self, from: data)
        } catch {
            UserDefaults.standard.removeObject(forKey: snapshotKey)
            return nil
        }
    }

    static func save(_ snapshot: InquiryPersistenceSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            UserDefaults.standard.set(data, forKey: snapshotKey)
        } catch {
            assertionFailure("Unable to save inquiry snapshot: \(error)")
        }
    }
}
