//
//  LiteRTModelStore.swift
//  Aquinas-iOS
//

import Foundation

nonisolated struct LiteRTModelManifest: Sendable, Equatable {
    // dynamic_wi8_emb4_afp32 candidate: 8-bit decoder weights, 4-bit embeddings.
    // Fixes the 4-bit checkpoint's repetition/looping without the memory failure the
    // straight-8-bit export hit. Vision is intentionally disabled for this package
    // (see LiteRTAquinasRuntime) pending a fix for its STABLEHLO_COMPOSITE load failure.
    static let aquinas = LiteRTModelManifest(
        fileName: "gemma-4-E2B-it.litertlm",
        byteCount: 3_862_121_696,
        sha256: "9a6345f1a6cd39283f957977c84d31cc63b8dd56f2b8fffeb784940f63365282"
    )

    let fileName: String
    let byteCount: Int64
    let sha256: String
}

nonisolated enum LiteRTModelStoreError: LocalizedError, Sendable {
    case modelMissing
    case invalidModelSize(expected: Int64, actual: Int64)
    case invalidModelDigest
    case missingVerificationReceipt
    case cacheUnavailable

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            "The Aquinas on-device model has not been installed."
        case let .invalidModelSize(expected, actual):
            "The installed Aquinas model is incomplete (\(actual) of \(expected) bytes)."
        case .invalidModelDigest:
            "The Aquinas model did not pass its integrity check."
        case .missingVerificationReceipt:
            "The downloaded Aquinas model has not been verified."
        case .cacheUnavailable:
            "The app could not create the LiteRT model cache."
        }
    }
}

/// Resolves a post-install model before the development-only bundled seed. Production delivery
/// writes the verified package to Application Support; the bundled path keeps device development
/// usable while that downloader and hosting endpoint are brought online.
nonisolated struct LiteRTModelStore: Sendable {
    let manifest: LiteRTModelManifest
    private let developmentModelURL: URL?

    init(
        manifest: LiteRTModelManifest = .aquinas,
        developmentModelURL: URL? = nil
    ) {
        self.manifest = manifest
        self.developmentModelURL = developmentModelURL
    }

    func installedModelURL() throws -> URL {
        let fileManager = FileManager.default
        if let developmentModelURL {
            try validateModel(at: developmentModelURL)
            return developmentModelURL
        }
        if let downloaded = applicationSupportModelURL(
            fileManager: fileManager
        ), fileManager.fileExists(atPath: downloaded.path) {
            try validateModel(at: downloaded)
            let receiptURL = verificationReceiptURL(for: downloaded)
            guard let data = try? Data(contentsOf: receiptURL),
                  let receipt = try? JSONDecoder().decode(
                    LiteRTModelVerificationReceipt.self,
                    from: data
                  ),
                  receipt.byteCount == manifest.byteCount,
                  receipt.sha256 == manifest.sha256 else {
                throw LiteRTModelStoreError.missingVerificationReceipt
            }
            return downloaded
        }
        if let bundled = bundledModelURL(),
           fileManager.fileExists(atPath: bundled.path) {
            try validateModel(at: bundled)
            return bundled
        }
        throw LiteRTModelStoreError.modelMissing
    }

    func hasInstalledModel() -> Bool {
        (try? installedModelURL()) != nil
    }

    func cacheDirectory() throws -> URL {
        guard let root = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw LiteRTModelStoreError.cacheUnavailable
        }
        let directory = root.appending(path: "LiteRTLM")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func postInstallDestinationURL() throws -> URL {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw LiteRTModelStoreError.modelMissing
        }
        let directory = root.appending(path: "Models")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appending(path: manifest.fileName)
    }

    func validateModel(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw LiteRTModelStoreError.modelMissing
        }
        let size = try url.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize.map(Int64.init) ?? 0
        guard size == manifest.byteCount else {
            throw LiteRTModelStoreError.invalidModelSize(
                expected: manifest.byteCount,
                actual: size
            )
        }
    }

    func verificationReceiptURL(for modelURL: URL) -> URL {
        modelURL.appendingPathExtension("verified.json")
    }

    private func applicationSupportModelURL(
        fileManager: FileManager
    ) -> URL? {
        if let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            return applicationSupport
                .appending(path: "Models")
                .appending(path: manifest.fileName)
        }
        return nil
    }

    private func bundledModelURL() -> URL? {
        if let bundled = Bundle.main.url(
            forResource: manifest.fileName.deletingPathExtension,
            withExtension: manifest.fileName.pathExtension,
            subdirectory: "LocalModels"
        ) ?? Bundle.main.url(
            forResource: manifest.fileName.deletingPathExtension,
            withExtension: manifest.fileName.pathExtension
        ) {
            return bundled
        }
        return nil
    }
}

nonisolated struct LiteRTModelVerificationReceipt: Codable, Sendable, Equatable {
    let byteCount: Int64
    let sha256: String
}

private extension String {
    nonisolated var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }

    nonisolated var pathExtension: String {
        (self as NSString).pathExtension
    }
}
