#if os(iOS)
import Foundation
import SwiftUI
import UIKit

public struct MosaicShareSheet: UIViewControllerRepresentable {
    private let fileURL: URL
    private let onCompletion: @MainActor (Bool, Error?) -> Void

    public init(
        fileURL: URL,
        onCompletion: @escaping @MainActor (Bool, Error?) -> Void = { _, _ in }
    ) {
        self.fileURL = fileURL
        self.onCompletion = onCompletion
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, completed, _, error in
            Task { @MainActor in
                onCompletion(completed, error)
            }
        }
        return controller
    }

    public func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
#endif
