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

    func testBatchRegistrationRemovesEarlierAssetsWhenALaterItemFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PhotosPickerAssetStore(directory: directory)
        let png = try XCTUnwrap(Data(base64Encoded: Self.onePixelPNG))

        do {
            _ = try await store.registerImportedData([png, Data()])
            XCTFail("Expected the empty selection to fail")
        } catch let error as PhotoSelectionError {
            XCTAssertEqual(error, .assetUnavailable("selected-photo"))
        }

        let cachedFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(cachedFiles.isEmpty)
    }

    func testBatchRegistrationReturnsEveryImportedReference() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PhotosPickerAssetStore(directory: directory)
        let png = try XCTUnwrap(Data(base64Encoded: Self.onePixelPNG))

        let references = try await store.registerImportedData([png, png])

        XCTAssertEqual(references.count, 2)
        XCTAssertEqual(Set(references.map(\.id)).count, 2)
        XCTAssertTrue(references.allSatisfy { $0.origin == .photoPicker })
    }

    func testAppEnvironmentSeparatesRecipesFromSelectedPhotoCopies() async throws {
        let applicationSupport = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let environment = MosaicAppEnvironment(applicationSupportDirectory: applicationSupport)
        let project = MosaicProject(title: "Persistent mosaic")
        let png = try XCTUnwrap(Data(base64Encoded: Self.onePixelPNG))

        try await environment.projectStore.save(project)
        _ = try await environment.assetStore.registerImportedData(png)

        let root = applicationSupport.appendingPathComponent("MosaicMemories")
        let projectFiles = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Projects"),
            includingPropertiesForKeys: nil
        )
        let assetFiles = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("SelectedPhotos"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(projectFiles.map(\.pathExtension), ["json"])
        XCTAssertEqual(assetFiles.map(\.pathExtension), ["asset"])
    }

    private static let onePixelPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
