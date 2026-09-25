//
//  UploadedFile.swift
//  Aquinas-iOS
//

import ImageIO
import UIKit

/// File/image selected before submitting a question.
nonisolated struct UploadedFile: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let name: String
    let imageData: Data?
    let rotationDegrees: Double

    init(id: UUID = UUID(), name: String, imageData: Data?, rotationDegrees: Double) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.rotationDegrees = rotationDegrees
    }

    static func == (lhs: UploadedFile, rhs: UploadedFile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension UploadedFile {
    /// Whether `data` holds a readable image, judged from its header without decoding pixels.
    nonisolated static func isImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// The attachment's image, decoded once and reused across redraws.
    @MainActor var image: UIImage? {
        UploadedFileImageCache.image(for: self)
    }
}

/// Decoded attachment images keyed by file ID. An `UploadedFile`'s data never changes, so its ID
/// is a stable key, and `NSCache` releases entries under memory pressure.
@MainActor
private enum UploadedFileImageCache {
    private static let images = NSCache<NSUUID, UIImage>()

    static func image(for file: UploadedFile) -> UIImage? {
        guard let data = file.imageData else { return nil }
        let key = file.id as NSUUID
        if let cached = images.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }
}
