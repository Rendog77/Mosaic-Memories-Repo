import Combine
import Foundation
import MosaicCore
import MosaicPersistence

@MainActor
public final class ProjectLibrarySession: ObservableObject {
    @Published public private(set) var projects: [MosaicProject] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var message: String?

    private let store: any ProjectStoring

    public init(store: any ProjectStoring) {
        self.store = store
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let catalog = try await store.catalog()
            projects = catalog.projects
            if catalog.unreadableProjectCount > 0 {
                let noun = catalog.unreadableProjectCount == 1 ? "project" : "projects"
                message = "\(catalog.unreadableProjectCount) saved \(noun) could not be opened."
            } else {
                message = nil
            }
        } catch {
            message = "Saved projects could not be loaded."
        }
    }
}
