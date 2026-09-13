import Foundation
import XCTest
import ImageIO
import MosaicCore
import MosaicFeatures
@testable import MosaicApplePhotos

final class PhotosPickerAssetStoreTests: XCTestCase {
    func testRegisteredSelectionReturnsBoundedJPEGThumbnail() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PhotosPickerAssetStore(directory: directory)
        let png = try XCTUnwrap(Data(base64Encoded: Self.onePixelPNG))

        let reference = try await store.registerImportedData(png)
        let thumbnail = try await store.thumbnail(for: reference, maximumPixelSize: 64)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])

        XCTAssertEqual(reference.origin, .photoPicker)
        XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelWidth] as? Int ?? .max, 64)
        XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelHeight] as? Int ?? .max, 64)
    }

    func testMissingCachedAssetReturnsTypedFailure() async {
        let store = PhotosPickerAssetStore(directory: FileManager.default.temporaryDirectory)
        let reference = AssetReference(id: UUID().uuidString, origin: .photoPicker)
        do {
            _ = try await store.thumbnail(for: reference, maximumPixelSize: 64)
            XCTFail("Expected unavailable asset")
        } catch let error as PhotoSelectionError {
            XCTAssertEqual(error, .assetUnavailable(reference.id))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static let onePixelPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}

