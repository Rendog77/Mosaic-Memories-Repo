import MosaicApplePhotos
import SwiftUI

@main
struct MosaicMemoriesApp: App {
    private let environment = MosaicAppEnvironment.production()

    var body: some Scene {
        WindowGroup {
            PhotosPickerRootView(
                store: environment.projectStore,
                assetStore: environment.assetStore
            )
        }
    }
}
