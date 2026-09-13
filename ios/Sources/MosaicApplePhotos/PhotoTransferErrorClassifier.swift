import Foundation
import MosaicFeatures

public struct PhotoTransferErrorClassifier: Sendable {
    public init() {}

    public func classify(_ error: any Error, identifier: String) -> PhotoSelectionError {
        if error is CancellationError {
            return .selectionCancelled
        }

        let nsError = error as NSError
        if nsError.domain == NSItemProvider.errorDomain,
           nsError.code == NSItemProvider.ErrorCode.itemUnavailableError.rawValue {
            return .assetUnavailable(identifier)
        }

        if nsError.domain == NSURLErrorDomain,
           Self.networkFailureCodes.contains(nsError.code) {
            return .iCloudDownloadFailed(identifier)
        }

        return .transferFailed(identifier)
    }

    private static let networkFailureCodes: Set<Int> = [
        URLError.Code.timedOut.rawValue,
        URLError.Code.cannotFindHost.rawValue,
        URLError.Code.cannotConnectToHost.rawValue,
        URLError.Code.networkConnectionLost.rawValue,
        URLError.Code.dnsLookupFailed.rawValue,
        URLError.Code.notConnectedToInternet.rawValue,
        URLError.Code.internationalRoamingOff.rawValue,
        URLError.Code.dataNotAllowed.rawValue,
    ]
}
