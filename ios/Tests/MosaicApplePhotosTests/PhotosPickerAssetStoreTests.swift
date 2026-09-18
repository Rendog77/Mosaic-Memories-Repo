import Foundation
import XCTest
import CoreGraphics
import ImageIO
import MosaicCore
import MosaicFeatures
import UniformTypeIdentifiers
@testable import MosaicApplePhotos

final class PhotosPickerAssetStoreTests: XCTestCase {
    func testRetryPolicyOffersRetryOnlyForTransientImportFailures() {
        let policy = PhotoImportRetryPolicy()

        XCTAssertTrue(policy.shouldOfferRetry(for: .assetUnavailable("one")))
        XCTAssertTrue(policy.shouldOfferRetry(for: .iCloudDownloadFailed("two")))
        XCTAssertTrue(policy.shouldOfferRetry(for: .transferFailed("three")))
        XCTAssertFalse(policy.shouldOfferRetry(for: .selectionCancelled))
        XCTAssertFalse(policy.shouldOfferRetry(for: .permissionDenied))
        XCTAssertFalse(policy.shouldOfferRetry(for: .unsupportedFormat("four")))
        XCTAssertFalse(policy.shouldOfferRetry(for: .invalidDimensions("five")))
        XCTAssertFalse(policy.shouldOfferRetry(for: .imageTooLarge("six")))
    }

    func testDimensionPolicyRejectsInvalidAndOversizedMetadata() {
        let policy = PhotoImportValidationPolicy(maximumPixelCount: 100)

        XCTAssertNoThrow(try policy.validate(width: 10, height: 10, identifier: "boundary"))
        XCTAssertThrowsError(try policy.validate(width: 0, height: 10, identifier: "invalid")) { error in
            XCTAssertEqual(error as? PhotoSelectionError, .invalidDimensions("invalid"))
        }
        XCTAssertThrowsError(try policy.validate(width: 11, height: 10, identifier: "large")) { error in
            XCTAssertEqual(error as? PhotoSelectionError, .imageTooLarge("large"))
        }
    }

    func testTransferClassifierDistinguishesStableFailureSignals() {
        let classifier = PhotoTransferErrorClassifier()
        let unavailable = NSError(
            domain: NSItemProvider.errorDomain,
            code: NSItemProvider.ErrorCode.itemUnavailableError.rawValue
        )
        let offline = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.notConnectedToInternet.rawValue
        )
        let unknown = NSError(domain: "MosaicTests", code: 42)

        XCTAssertEqual(classifier.classify(unavailable, identifier: "one"), .assetUnavailable("one"))
        XCTAssertEqual(classifier.classify(offline, identifier: "two"), .iCloudDownloadFailed("two"))
        XCTAssertEqual(classifier.classify(unknown, identifier: "three"), .transferFailed("three"))
    }

    func testTransferClassifierTreatsCancellationAsNonFailureState() {
        let error = PhotoTransferErrorClassifier().classify(
            CancellationError(),
            identifier: "cancelled"
        )
        XCTAssertEqual(error, .selectionCancelled)
    }

    func testImportProgressReportsBoundedFraction() {
        XCTAssertEqual(PhotoImportProgress(completedCount: 0, totalCount: 4).fractionCompleted, 0)
        XCTAssertEqual(PhotoImportProgress(completedCount: 2, totalCount: 4).fractionCompleted, 0.5)
        XCTAssertEqual(PhotoImportProgress(completedCount: 4, totalCount: 4).fractionCompleted, 1)
    }

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

    func testThumbnailNormalizesOrientationMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PhotosPickerAssetStore(directory: directory)
        let orientedJPEG = try makeOrientedJPEG()

        let reference = try await store.registerImportedData(orientedJPEG)
        let thumbnail = try await store.thumbnail(for: reference, maximumPixelSize: 64)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )

        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 2)
    }

    func testHeroCropAppliesAfterOrientationNormalization() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PhotosPickerAssetStore(directory: directory)
        let reference = try await store.registerImportedData(makeOrientedJPEG())
        let upperHalf = try HeroCrop(x: 0, y: 0, width: 1, height: 0.5)

        let thumbnail = try await store.thumbnail(for: reference, maximumPixelSize: 64, crop: upperHalf)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])

        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 1)
    }

    func testHeroCropChangesUnrotatedThumbnailDimensions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PhotosPickerAssetStore(directory: directory)
        let reference = try await store.registerImportedData(makeOrientedJPEG(orientation: 1))
        let leftHalf = try HeroCrop(x: 0, y: 0, width: 0.5, height: 1)

        let thumbnail = try await store.thumbnail(for: reference, maximumPixelSize: 64, crop: leftHalf)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])

        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 1)
    }

    func testOversizedImageIsRejectedBeforeCaching() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PhotosPickerAssetStore(
            directory: directory,
            validationPolicy: .init(maximumPixelCount: 1)
        )

        do {
            _ = try await store.registerImportedData(
                makeOrientedJPEG(),
                sourceIdentifier: "large-item"
            )
            XCTFail("Expected oversized image failure")
        } catch let error as PhotoSelectionError {
            XCTAssertEqual(error, .imageTooLarge("large-item"))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
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

    func testUnsupportedImageIsRejectedBeforeCaching() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PhotosPickerAssetStore(directory: directory)

        do {
            _ = try await store.registerImportedData(
                Data("not-an-image".utf8),
                sourceIdentifier: "unsupported-item"
            )
            XCTFail("Expected unsupported image failure")
        } catch let error as PhotoSelectionError {
            XCTAssertEqual(error, .unsupportedFormat("unsupported-item"))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
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

    func testDiscardRemovesOnlyCachedPickerAssets() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PhotosPickerAssetStore(directory: directory)
        let png = try XCTUnwrap(Data(base64Encoded: Self.onePixelPNG))
        let cached = try await store.registerImportedData([png, png])

        await store.discardCachedAssets([
            cached[0],
            AssetReference(id: "fixture", origin: .testFixture),
            cached[1],
        ])

        let remaining = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(remaining.isEmpty)
    }

    private static let onePixelPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    private func makeOrientedJPEG(orientation: Int = 6) throws -> Data {
        let colourSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 2,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 8,
                space: colourSpace,
                bitmapInfo: bitmapInfo.rawValue
            )
        )
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))

        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                output as CFMutableData,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
