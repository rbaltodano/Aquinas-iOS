import Testing
import UIKit
@testable import Aquinas_iOS

@Suite("Uploaded files")
struct UploadedFileTests {
    @Test("Image data is recognized from its header")
    func recognizesImageData() throws {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }

        #expect(UploadedFile.isImageData(png))
        #expect(!UploadedFile.isImageData(Data("Summa Theologiae".utf8)))
        #expect(!UploadedFile.isImageData(Data()))
    }

    @Test("An attachment's image is decoded once and reused")
    @MainActor
    func reusesDecodedImage() throws {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { _ in }
        let file = UploadedFile(name: "Photo", imageData: png, rotationDegrees: 0)

        let first = try #require(file.image)
        #expect(file.image === first)
        #expect(UploadedFile(name: "Notes", imageData: nil, rotationDegrees: 0).image == nil)
    }
}
