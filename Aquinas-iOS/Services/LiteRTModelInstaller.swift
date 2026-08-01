//
//  LiteRTModelInstaller.swift
//  Aquinas-iOS
//

import CryptoKit
import Foundation

nonisolated enum LiteRTModelInstallerError: LocalizedError, Sendable {
    case invalidServerResponse

    var errorDescription: String? {
        switch self {
        case .invalidServerResponse:
            "The Aquinas model server returned an invalid response."
        }
    }
}

/// Installs an externally hosted model after download. Aquinas verifies both size and SHA-256
/// before atomically promoting the temporary file into Application Support.
actor LiteRTModelInstaller {
    private let store: LiteRTModelStore
    private let session: URLSession

    init(
        store: LiteRTModelStore = LiteRTModelStore(),
        session: URLSession = .shared
    ) {
        self.store = store
        self.session = session
    }

    @discardableResult
    func install(from sourceURL: URL) async throws -> URL {
        let (temporaryURL, response) = try await session.download(
            from: sourceURL
        )
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            throw LiteRTModelInstallerError.invalidServerResponse
        }

        try store.validateModel(at: temporaryURL)
        let digest = try Self.sha256(of: temporaryURL)
        guard digest == store.manifest.sha256 else {
            throw LiteRTModelStoreError.invalidModelDigest
        }

        let destination = try store.postInstallDestinationURL()
        let fileManager = FileManager.default
        let staged = destination.appendingPathExtension("installing")
        if fileManager.fileExists(atPath: staged.path) {
            try fileManager.removeItem(at: staged)
        }
        try fileManager.moveItem(at: temporaryURL, to: staged)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: staged, to: destination)

        let receipt = LiteRTModelVerificationReceipt(
            byteCount: store.manifest.byteCount,
            sha256: digest
        )
        let receiptData = try JSONEncoder().encode(receipt)
        try receiptData.write(
            to: store.verificationReceiptURL(for: destination),
            options: .atomic
        )
        return destination
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 8 * 1_024 * 1_024)
            guard let data, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map {
            String(format: "%02x", $0)
        }
        .joined()
    }
}
