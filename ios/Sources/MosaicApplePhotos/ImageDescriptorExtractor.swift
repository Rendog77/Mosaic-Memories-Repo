import CoreGraphics
import Foundation
import ImageIO
import MosaicCore
import MosaicAppUI
import MosaicFeatures
import MosaicPersistence

public struct PhotoPreviewDescriptorSet: Equatable, Sendable {
    public let targets: [MosaicTargetDescriptor]
    public let sources: [MosaicSourceDescriptor]

    public init(targets: [MosaicTargetDescriptor], sources: [MosaicSourceDescriptor]) {
        self.targets = targets
        self.sources = sources
    }
}

public enum PhotoPreviewGenerationProgress: Equatable, Sendable {
    case descriptors(MosaicProgress)
    case assignment(MosaicProgress)
    case rendering(MosaicProgress)
}

public struct PhotoPreviewResult: Equatable, Sendable {
    public let image: MosaicPreviewImage
    public let assignment: MosaicPreviewAssignment
    public let assignmentOrigin: PreviewAssignmentOrigin

    public init(
        image: MosaicPreviewImage,
        assignment: MosaicPreviewAssignment,
        assignmentOrigin: PreviewAssignmentOrigin
    ) {
        self.image = image
        self.assignment = assignment
        self.assignmentOrigin = assignmentOrigin
    }
}

public struct AppleImageDescriptorExtractor: Sendable {
    public let maximumPixelSize: Int
    public let sourceSampleSize: Int

    public init(maximumPixelSize: Int = 512, sourceSampleSize: Int = 8) {
        precondition(maximumPixelSize > 0)
        precondition(sourceSampleSize > 0)
        self.maximumPixelSize = maximumPixelSize
        self.sourceSampleSize = sourceSampleSize
    }

    public func sourceDescriptor(
        for reference: AssetReference,
        imageData: Data
    ) throws -> MosaicSourceDescriptor {
        let image = try decode(imageData)
        let side = min(image.width, image.height)
        let rectangle = CGRect(
            x: CGFloat(image.width - side) / 2,
            y: CGFloat(image.height - side) / 2,
            width: CGFloat(side),
            height: CGFloat(side)
        )
        guard let cropped = image.cropping(to: rectangle) else {
            throw ImageDescriptorError.rasterizationFailed
        }
        let pixels = try rasterize(
            cropped,
            width: sourceSampleSize,
            height: sourceSampleSize
        )
        let colour = averageLinearSRGB(pixels)
        return MosaicSourceDescriptor(
            reference: reference,
            descriptor: try MosaicDescriptor(components: labComponents(for: colour))
        )
    }

    public func targetDescriptors(
        heroImageData: Data,
        columns: Int
    ) throws -> [MosaicTargetDescriptor] {
        guard columns > 0 else { throw ImageDescriptorError.invalidColumnCount }
        let image = try decode(heroImageData)
        let rows = max(1, Int((Double(columns) * Double(image.height) / Double(image.width)).rounded()))
        let pixels = try rasterize(image, width: columns, height: rows)
        var descriptors: [MosaicTargetDescriptor] = []
        descriptors.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let offset = (row * columns + column) * 4
                let colour = (
                    Double(pixels[offset]) / 255,
                    Double(pixels[offset + 1]) / 255,
                    Double(pixels[offset + 2]) / 255
                )
                descriptors.append(
                    .init(
                        coordinate: .init(column: column, row: row),
                        descriptor: try MosaicDescriptor(components: labComponents(for: colour))
                    )
                )
            }
        }
        return descriptors
    }

    private func decode(_ data: Data) throws -> CGImage {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                  ] as CFDictionary
              ) else {
            throw ImageDescriptorError.imageDecodeFailed
        }
        return image
    }

    private func rasterize(_ image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                    CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw ImageDescriptorError.rasterizationFailed }
        return pixels
    }

    private func averageLinearSRGB(_ pixels: [UInt8]) -> (Double, Double, Double) {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        let count = pixels.count / 4
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            red += srgbToLinear(Double(pixels[offset]) / 255)
            green += srgbToLinear(Double(pixels[offset + 1]) / 255)
            blue += srgbToLinear(Double(pixels[offset + 2]) / 255)
        }
        return (
            linearToSRGB(red / Double(count)),
            linearToSRGB(green / Double(count)),
            linearToSRGB(blue / Double(count))
        )
    }

    private func labComponents(for colour: (Double, Double, Double)) -> [Double] {
        let red = srgbToLinear(colour.0)
        let green = srgbToLinear(colour.1)
        let blue = srgbToLinear(colour.2)
        let x = (0.4124564 * red + 0.3575761 * green + 0.1804375 * blue) / 0.95047
        let y = 0.2126729 * red + 0.7151522 * green + 0.0721750 * blue
        let z = (0.0193339 * red + 0.1191920 * green + 0.9503041 * blue) / 1.08883
        let fx = labCurve(x)
        let fy = labCurve(y)
        let fz = labCurve(z)
        return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)]
    }

    private func srgbToLinear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private func linearToSRGB(_ value: Double) -> Double {
        value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    private func labCurve(_ value: Double) -> Double {
        let threshold = 216.0 / 24_389.0
        return value > threshold ? pow(value, 1.0 / 3.0) : (24_389.0 / 2_700.0 * value + 16) / 116
    }
}

public struct PhotoPreviewDescriptorBuilder: Sendable {
    private let extractor: AppleImageDescriptorExtractor

    public init(extractor: AppleImageDescriptorExtractor = .init()) {
        self.extractor = extractor
    }

    public func descriptors(
        for project: MosaicProject,
        loader: any PhotoAssetLoading,
        progress: @escaping @Sendable (MosaicProgress) -> Void = { _ in }
    ) async throws -> PhotoPreviewDescriptorSet {
        guard project.sourcesConfirmed else { throw ImageDescriptorError.sourcesNotConfirmed }
        guard let hero = project.hero else { throw ImageDescriptorError.missingHero }
        let total = project.sources.count + 1
        progress(.init(completed: 0, total: total))
        try Task.checkCancellation()
        let heroData = try await loader.thumbnail(
            for: hero,
            maximumPixelSize: extractor.maximumPixelSize,
            crop: project.heroCrop
        )
        let targets = try extractor.targetDescriptors(
            heroImageData: heroData,
            columns: project.recipe.columns
        )
        progress(.init(completed: 1, total: total))

        var sources: [MosaicSourceDescriptor] = []
        sources.reserveCapacity(project.sources.count)
        for (index, reference) in project.sources.enumerated() {
            if index.isMultiple(of: 8) { await Task.yield() }
            try Task.checkCancellation()
            let data = try await loader.thumbnail(
                for: reference,
                maximumPixelSize: extractor.maximumPixelSize
            )
            sources.append(try extractor.sourceDescriptor(for: reference, imageData: data))
            progress(.init(completed: index + 2, total: total))
        }
        try Task.checkCancellation()
        return .init(targets: targets, sources: sources)
    }
}

public struct ApplePhotoPreviewAssignmentService: Sendable {
    private let loader: any PhotoAssetLoading
    private let builder: PhotoPreviewDescriptorBuilder
    private let generator: CachedPreviewAssignmentGenerator
    private let renderer: AppleMosaicPreviewRenderer

    public init(
        loader: any PhotoAssetLoading,
        generator: CachedPreviewAssignmentGenerator,
        builder: PhotoPreviewDescriptorBuilder = .init(),
        renderer: AppleMosaicPreviewRenderer = .init()
    ) {
        self.loader = loader
        self.generator = generator
        self.builder = builder
        self.renderer = renderer
    }

    public func assignment(
        for project: MosaicProject,
        progress: @escaping @Sendable (PhotoPreviewGenerationProgress) -> Void = { _ in }
    ) async throws -> PreviewAssignmentResult {
        let descriptors = try await builder.descriptors(
            for: project,
            loader: loader
        ) { progress(.descriptors($0)) }
        return try await generator.assignment(
            for: project,
            targets: descriptors.targets,
            sources: descriptors.sources
        ) { progress(.assignment($0)) }
    }

    public func preview(
        for project: MosaicProject,
        progress: @escaping @Sendable (PhotoPreviewGenerationProgress) -> Void = { _ in }
    ) async throws -> PhotoPreviewResult {
        let assignmentResult = try await assignment(for: project, progress: progress)
        let image = try await renderer.render(
            project: project,
            assignment: assignmentResult.assignment,
            loader: loader
        ) { progress(.rendering($0)) }
        return .init(
            image: image,
            assignment: assignmentResult.assignment,
            assignmentOrigin: assignmentResult.origin
        )
    }
}

public enum ImageDescriptorError: Error, Equatable, Sendable {
    case imageDecodeFailed
    case rasterizationFailed
    case invalidColumnCount
    case missingHero
    case sourcesNotConfirmed
}

extension ApplePhotoPreviewAssignmentService: MosaicPreviewGenerating {
    public func generatePreview(
        for project: MosaicProject,
        progress: @escaping @Sendable (MosaicPreviewGenerationStatus) -> Void
    ) async throws -> MosaicPreviewOutput {
        let result = try await preview(for: project) { update in
            switch update {
            case .descriptors(let value):
                progress(.init(
                    stage: .analyzingPhotos,
                    completed: value.completed,
                    total: value.total
                ))
            case .assignment(let value):
                progress(.init(
                    stage: .arrangingTiles,
                    completed: value.completed,
                    total: value.total
                ))
            case .rendering(let value):
                progress(.init(
                    stage: .renderingMosaic,
                    completed: value.completed,
                    total: value.total
                ))
            }
        }
        return .init(
            data: result.image.data,
            width: result.image.width,
            height: result.image.height
        )
    }
}
