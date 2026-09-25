import MosaicApplePhotos
import Foundation
import SwiftUI

@main
struct MosaicMemoriesApp: App {
    private let environment = MosaicAppEnvironment.production()

    var body: some Scene {
        WindowGroup {
            PhotosPickerRootView(
                store: environment.projectStore,
                assetStore: environment.assetStore,
                previewGenerator: environment.previewService
            )
            .task {
                await runPersistenceProbeIfRequested()
            }
        }
    }

    private func runPersistenceProbeIfRequested() async {
        guard let expectedTitle = ProcessInfo.processInfo.environment["MOSAIC_CI_EXPECT_PROJECT_TITLE"] else {
            return
        }
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("mosaic-persistence-probe.txt")
        do {
            let projects = try await environment.projectStore.list()
            let recoveredTitle = projects.first(where: { $0.title == expectedTitle })?.title ?? "missing"
            try Data(recoveredTitle.utf8).write(to: marker, options: .atomic)
        } catch {
            try? Data("unreadable".utf8).write(to: marker, options: .atomic)
        }
    }
}
