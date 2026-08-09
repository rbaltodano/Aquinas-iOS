//
//  InsightTreeLocalStateStore.swift
//  Aquinas-iOS
//

import CryptoKit
import Foundation

/// Protected, atomic storage for on-device Insight Tree topology and presentation state. Each
/// logical legacy key maps to its own file so one corrupt canvas detail cannot invalidate the rest
/// of the tree. Existing `UserDefaults` values migrate on first read.
struct InsightTreeLocalStateFileStore {
    let rootDirectory: URL
    let defaults: UserDefaults
    let fileManager: FileManager

    init(
        rootDirectory: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func load<Value: Codable>(_ type: Value.Type, key: String) -> Value? {
        let fileURL = url(for: key)
        if let data = try? Data(contentsOf: fileURL),
           let value = try? JSONDecoder().decode(type, from: data) {
            return value
        }
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(type, from: data) else {
            return nil
        }
        do {
            try save(value, key: key)
            defaults.removeObject(forKey: key)
        } catch {
            // Retain the legacy copy until the protected file write succeeds.
        }
        return value
    }

    func save<Value: Encodable>(_ value: Value, key: String) throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(value)
        try data.write(
            to: url(for: key),
            options: [.atomic, .completeFileProtection]
        )
    }

    private func url(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return rootDirectory.appending(path: "\(name).json")
    }
}

enum InsightTreeLocalStateStore {
    static func load<Value: Codable>(_ type: Value.Type, key: String) -> Value? {
        liveStore()?.load(type, key: key)
    }

    static func save<Value: Encodable>(_ value: Value, key: String) {
        try? liveStore()?.save(value, key: key)
    }

    private static func liveStore() -> InsightTreeLocalStateFileStore? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return InsightTreeLocalStateFileStore(
            rootDirectory: applicationSupport.appending(
                path: "Aquinas/InsightTree/CanvasState",
                directoryHint: .isDirectory
            )
        )
    }
}
