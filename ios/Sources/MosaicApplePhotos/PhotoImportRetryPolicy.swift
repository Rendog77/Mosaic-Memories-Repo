import MosaicFeatures

public struct PhotoImportRetryPolicy: Sendable {
    public init() {}

    public func shouldOfferRetry(for error: PhotoSelectionError) -> Bool {
        switch error {
        case .assetUnavailable, .iCloudDownloadFailed, .transferFailed:
            return true
        case .permissionDenied, .selectionCancelled, .unsupportedFormat, .invalidDimensions, .imageTooLarge:
            return false
        }
    }
}
