import MosaicFeatures

public struct PhotoImportValidationPolicy: Equatable, Sendable {
    public let maximumPixelCount: UInt64

    public init(maximumPixelCount: UInt64 = 500_000_000) {
        precondition(maximumPixelCount > 0)
        self.maximumPixelCount = maximumPixelCount
    }

    public func validate(width: Int, height: Int, identifier: String) throws {
        guard width > 0, height > 0 else {
            throw PhotoSelectionError.invalidDimensions(identifier)
        }
        let (pixelCount, overflow) = UInt64(width).multipliedReportingOverflow(by: UInt64(height))
        guard !overflow, pixelCount <= maximumPixelCount else {
            throw PhotoSelectionError.imageTooLarge(identifier)
        }
    }
}
