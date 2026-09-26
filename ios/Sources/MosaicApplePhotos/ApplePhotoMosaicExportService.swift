import Foundation
import MosaicAppUI
import MosaicCore
import MosaicFeatures

public struct ApplePhotoMosaicExportService: MosaicExporting, Sendable {
    private let loader: any PhotoAssetLoading
    private let renderer: AppleMosaicExportRenderer

    public init(
        loader: any PhotoAssetLoading,
        renderer: AppleMosaicExportRenderer = AppleMosaicExportRenderer()
    ) {
        self.loader = loader
        self.renderer = renderer
    }

    public func export(
        project: MosaicProject,
        tiles: [MosaicAssignedTile],
        policy: MosaicExportPolicy,
        to destination: URL,
        progress: @escaping @Sendable (MosaicProgress) -> Void
    ) async throws -> MosaicExportResult {
        try await renderer.export(
            project: project,
            assignment: .init(engineVersion: project.recipe.engineVersion, tiles: tiles),
            loader: loader,
            policy: policy,
            to: destination,
            progress: progress
        )
    }
}
