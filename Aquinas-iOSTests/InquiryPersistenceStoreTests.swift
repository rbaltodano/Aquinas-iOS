import Foundation
import Testing
@testable import Aquinas_iOS

@Suite("Inquiry persistence")
struct InquiryPersistenceStoreTests {
    @Test("A file-backed snapshot round-trips with stable identifiers")
    func snapshotRoundTrip() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let conversation = InquiryConversation(title: "Grace and Nature")
        let snapshot = InquiryPersistenceSnapshot(
            conversations: [conversation],
            activeConversationID: conversation.id
        )

        try fixture.store.save(snapshot)

        #expect(fixture.store.load() == snapshot)
    }

    @Test("A completed response replaces its persisted placeholder by stable IDs")
    func completedResponseReplacesPlaceholder() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var branch = ChatBranch(startingConcept: nil)
        branch.activeChatBlocks = [
            .user("What is prudence?", nil, []),
            .text("")
        ]
        let conversation = InquiryConversation(branches: [branch])
        try fixture.store.save(
            InquiryPersistenceSnapshot(
                conversations: [conversation],
                activeConversationID: conversation.id
            )
        )

        branch.activeChatBlocks[1] = .text("Prudence is practical wisdom.")
        branch.showBottomInput = true
        try fixture.store.saveCompletedBranch(
            branch,
            conversationID: conversation.id
        )

        let restoredBranch = fixture.store.load()?.conversations.first?.branches.first
        #expect(restoredBranch?.activeChatBlocks[1] == .text("Prudence is practical wisdom."))
        #expect(restoredBranch?.showBottomInput == true)
    }

    @Test("The current UserDefaults prototype migrates once to the file store")
    func legacyMigration() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let conversation = InquiryConversation(title: "Migrated Inquiry")
        let snapshot = InquiryPersistenceSnapshot(
            conversations: [conversation],
            activeConversationID: conversation.id
        )
        fixture.defaults.set(
            try JSONEncoder().encode(snapshot),
            forKey: InquirySnapshotFileStore.currentLegacyKey
        )

        #expect(fixture.store.load() == snapshot)
        #expect(
            fixture.defaults.object(
                forKey: InquirySnapshotFileStore.currentLegacyKey
            ) == nil
        )
        #expect(fixture.store.load() == snapshot)
    }

    @Test("A corrupt live snapshot recovers from the newest valid backup")
    func backupRecovery() throws {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try Fixture(now: { clock })
        defer { fixture.cleanup() }
        let first = InquiryPersistenceSnapshot(
            conversations: [InquiryConversation(title: "Known Good")],
            activeConversationID: nil
        )
        let second = InquiryPersistenceSnapshot(
            conversations: [InquiryConversation(title: "Current")],
            activeConversationID: nil
        )

        try fixture.store.save(first)
        clock.addTimeInterval(7 * 60 * 60)
        try fixture.store.save(second)
        try Data("not json".utf8).write(
            to: fixture.root.appending(path: "conversations-v1.json"),
            options: .atomic
        )

        #expect(fixture.store.load() == first)
    }

    @Test("Imports are validated before replacing live conversations")
    func invalidImportIsRejected() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let original = InquiryPersistenceSnapshot(
            conversations: [InquiryConversation(title: "Keep Me")],
            activeConversationID: nil
        )
        try fixture.store.save(original)

        #expect(throws: InquiryPersistenceError.self) {
            try fixture.store.importData(Data("invalid".utf8))
        }
        #expect(fixture.store.load() == original)
    }
}

@Suite("Local Insight Tree persistence")
struct LocalInsightTreePersistenceTests {
    @Test("Canvas state migrates from UserDefaults into protected files")
    func canvasStateMigration() throws {
        let fixture = try LocalTreeFixture()
        defer { fixture.cleanup() }
        let key = "canvas.\(UUID().uuidString)"
        let expected = ["node-a": StoredPoint(x: 42, y: -18)]
        fixture.defaults.set(try JSONEncoder().encode(expected), forKey: key)
        let store = InsightTreeLocalStateFileStore(
            rootDirectory: fixture.root.appending(path: "canvas"),
            defaults: fixture.defaults
        )

        #expect(store.load([String: StoredPoint].self, key: key) == expected)
        #expect(fixture.defaults.object(forKey: key) == nil)
        #expect(store.load([String: StoredPoint].self, key: key) == expected)
    }

    @Test("Local semantic seeds preserve embedding provenance")
    func seedRoundTrip() throws {
        let fixture = try LocalTreeFixture()
        defer { fixture.cleanup() }
        let seed = LocalInsightTreeSeed(
            id: UUID(),
            label: "Natural law",
            summary: "A principle grounded in human nature.",
            embedding: [0.1, 0.2, 0.3],
            embeddingVersion: "minilm.test.v1",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let store = LocalInsightTreeSeedFileStore(
            fileURL: fixture.root.appending(path: "seeds.json"),
            defaults: fixture.defaults
        )

        try store.save(["conversation": [seed]])

        #expect(store.load() == ["conversation": [seed]])
    }
}

private struct StoredPoint: Codable, Equatable {
    let x: Double
    let y: Double
}

private struct LocalTreeFixture {
    let root: URL
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "AquinasLocalTreePersistenceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        suiteName = "AquinasLocalTreePersistenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw InquiryPersistenceError.applicationSupportUnavailable
        }
        self.defaults = defaults
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct Fixture {
    let root: URL
    let suiteName: String
    let defaults: UserDefaults
    let store: InquirySnapshotFileStore

    init(now: @escaping () -> Date = Date.init) throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "AquinasInquiryPersistenceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        suiteName = "AquinasInquiryPersistenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw InquiryPersistenceError.applicationSupportUnavailable
        }
        self.defaults = defaults
        store = InquirySnapshotFileStore(
            rootDirectory: root,
            defaults: defaults,
            now: now
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
