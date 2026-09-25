//
//  InquiryPersistence.swift
//  Aquinas-iOS
//

import Foundation

// MARK: - Inquiry Persistence

/// The full piece of local state needed to restore the user's conversation canvases.
nonisolated struct InquiryPersistenceSnapshot: Codable, Equatable, Sendable {
    var conversations: [InquiryConversation]
    var activeConversationID: UUID?
}

nonisolated enum InquiryPersistenceError: LocalizedError {
    case applicationSupportUnavailable
    case invalidImport

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "Aquinas could not open its local data directory."
        case .invalidImport:
            "That file is not a valid Aquinas conversation export."
        }
    }
}

/// File-backed conversation storage with atomic replacement, rotating backups, and migration from
/// both prototype `UserDefaults` keys. The snapshot shape deliberately remains Codable so stable
/// conversation, branch, response, and Insight identifiers survive the storage migration.
nonisolated struct InquirySnapshotFileStore {
    static let currentLegacyKey = "aquinas.current.conversations.v1"
    static let originalLegacyKey = "aquinas.inquiry.persistence.snapshot.v1"

    private let rootDirectory: URL
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let now: () -> Date

    private let snapshotFileName = "conversations-v1.json"
    private let backupDirectoryName = "Backups"
    private let maximumBackupCount = 5
    private let minimumBackupInterval: TimeInterval = 6 * 60 * 60

    init(
        rootDirectory: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.rootDirectory = rootDirectory
        self.defaults = defaults
        self.fileManager = fileManager
        self.now = now
    }

    func load() -> InquiryPersistenceSnapshot? {
        if let snapshot = decodeSnapshot(at: snapshotURL) {
            return snapshot
        }

        for backupURL in backupURLsNewestFirst() {
            if let snapshot = decodeSnapshot(at: backupURL) {
                // Restore the last known-good snapshot to the live location. Failure here should
                // not hide the recovered in-memory value from the user.
                try? write(snapshot, createsBackup: false)
                return snapshot
            }
        }

        return migrateLegacySnapshotIfAvailable()
    }

    func save(_ snapshot: InquiryPersistenceSnapshot) throws {
        try write(snapshot, createsBackup: true)
    }

    /// Replaces only the branch whose model response just completed. This narrow write is used by
    /// shell-owned model work after its originating SwiftUI screen has been removed, so a stale
    /// view snapshot cannot turn the completed answer back into an empty response placeholder.
    func saveCompletedBranch(
        _ completedBranch: ChatBranch,
        conversationID: UUID
    ) throws {
        guard var snapshot = load(),
              let conversationIndex = snapshot.conversations.firstIndex(where: {
                  $0.id == conversationID
              }),
              let branchIndex = snapshot.conversations[conversationIndex].branches.firstIndex(where: {
                  $0.id == completedBranch.id
              }) else {
            return
        }
        snapshot.conversations[conversationIndex].branches[branchIndex] = completedBranch
        try write(snapshot, createsBackup: true)
    }

    func exportData() throws -> Data {
        guard let snapshot = load() else {
            return try Self.encoder.encode(
                InquiryPersistenceSnapshot(conversations: [], activeConversationID: nil)
            )
        }
        return try Self.encoder.encode(snapshot)
    }

    @discardableResult
    func importData(_ data: Data) throws -> InquiryPersistenceSnapshot {
        guard let snapshot = try? Self.decoder.decode(
            InquiryPersistenceSnapshot.self,
            from: data
        ) else {
            throw InquiryPersistenceError.invalidImport
        }
        try write(snapshot, createsBackup: true)
        return snapshot
    }

    private var snapshotURL: URL {
        rootDirectory.appending(path: snapshotFileName)
    }

    private var backupDirectoryURL: URL {
        rootDirectory.appending(path: backupDirectoryName, directoryHint: .isDirectory)
    }

    private func write(
        _ snapshot: InquiryPersistenceSnapshot,
        createsBackup: Bool
    ) throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        if createsBackup {
            try createBackupIfNeeded()
        }
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: snapshotURL, options: [.atomic, .completeFileProtection])
    }

    private func createBackupIfNeeded() throws {
        guard fileManager.fileExists(atPath: snapshotURL.path) else { return }
        try fileManager.createDirectory(
            at: backupDirectoryURL,
            withIntermediateDirectories: true
        )

        if let newest = backupURLsNewestFirst().first,
           let values = try? newest.resourceValues(forKeys: [.contentModificationDateKey]),
           let modificationDate = values.contentModificationDate,
           now().timeIntervalSince(modificationDate) < minimumBackupInterval {
            return
        }

        let backupURL = backupDirectoryURL.appending(
            path: "conversations-\(Self.backupTimestamp.string(from: now())).json"
        )
        try fileManager.copyItem(at: snapshotURL, to: backupURL)
        try pruneBackups()
    }

    private func pruneBackups() throws {
        for oldBackup in backupURLsNewestFirst().dropFirst(maximumBackupCount) {
            try fileManager.removeItem(at: oldBackup)
        }
    }

    private func backupURLsNewestFirst() -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: backupDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { left, right in
                let leftDate = try? left.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                let rightDate = try? right.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                return (leftDate ?? .distantPast) > (rightDate ?? .distantPast)
            }
    }

    private func decodeSnapshot(at url: URL) -> InquiryPersistenceSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(InquiryPersistenceSnapshot.self, from: data)
    }

    private func migrateLegacySnapshotIfAvailable() -> InquiryPersistenceSnapshot? {
        for key in [Self.currentLegacyKey, Self.originalLegacyKey] {
            guard let data = defaults.data(forKey: key),
                  let snapshot = try? Self.decoder.decode(
                    InquiryPersistenceSnapshot.self,
                    from: data
                  ) else {
                continue
            }
            do {
                try write(snapshot, createsBackup: false)
                defaults.removeObject(forKey: Self.currentLegacyKey)
                defaults.removeObject(forKey: Self.originalLegacyKey)
            } catch {
                // Keep the legacy copy until a verified file write succeeds.
            }
            return snapshot
        }
        return nil
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private static let backupTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

/// Canonical process-facing conversation repository. All app features use this boundary; the
/// concrete file store can later be replaced by normalized SwiftData records without another view
/// rewrite.
enum InquiryPersistenceStore {
    nonisolated private static let shared = SerializedInquiryStore(makeStore: liveStore)

    static func load() -> InquiryPersistenceSnapshot? {
        shared.load()
    }

    static func save(_ snapshot: InquiryPersistenceSnapshot) {
        shared.save(snapshot)
    }

    static func saveCompletedBranch(
        _ completedBranch: ChatBranch,
        conversationID: UUID
    ) {
        shared.saveCompletedBranch(completedBranch, conversationID: conversationID)
    }

    static func exportData() throws -> Data {
        try shared.exportData()
    }

    @discardableResult
    static func importData(_ data: Data) throws -> InquiryPersistenceSnapshot {
        try shared.importData(data)
    }

    /// Blocks until every queued write has reached disk. Call before the app is suspended.
    static func flush() {
        shared.flush()
    }

    nonisolated private static func liveStore() -> InquirySnapshotFileStore? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return InquirySnapshotFileStore(
            rootDirectory: applicationSupport.appending(
                path: "Aquinas/ConversationStore",
                directoryHint: .isDirectory
            )
        )
    }
}

/// Runs every snapshot operation on one serial background queue so JSON encoding and file I/O stay
/// off the main thread. Writes are enqueued and return immediately; reads and imports wait behind
/// queued writes, so a load never observes a stale file and writes never interleave.
nonisolated final class SerializedInquiryStore: @unchecked Sendable {
    private let makeStore: () -> InquirySnapshotFileStore?
    private let queue = DispatchQueue(label: "com.aquinas.inquiry-persistence", qos: .utility)

    init(makeStore: @escaping () -> InquirySnapshotFileStore?) {
        self.makeStore = makeStore
    }

    func load() -> InquiryPersistenceSnapshot? {
        queue.sync { makeStore()?.load() }
    }

    func save(_ snapshot: InquiryPersistenceSnapshot) {
        enqueue("Unable to save inquiry snapshot") { try $0.save(snapshot) }
    }

    func saveCompletedBranch(_ completedBranch: ChatBranch, conversationID: UUID) {
        enqueue("Unable to save completed response") {
            try $0.saveCompletedBranch(completedBranch, conversationID: conversationID)
        }
    }

    func exportData() throws -> Data {
        try queue.sync { try requireStore().exportData() }
    }

    func importData(_ data: Data) throws -> InquiryPersistenceSnapshot {
        try queue.sync { try requireStore().importData(data) }
    }

    func flush() {
        queue.sync {}
    }

    private func enqueue(
        _ failureMessage: String,
        _ operation: @escaping (InquirySnapshotFileStore) throws -> Void
    ) {
        queue.async { [self] in
            do {
                try operation(requireStore())
            } catch {
                assertionFailure("\(failureMessage): \(error)")
            }
        }
    }

    private func requireStore() throws -> InquirySnapshotFileStore {
        guard let store = makeStore() else {
            throw InquiryPersistenceError.applicationSupportUnavailable
        }
        return store
    }
}
