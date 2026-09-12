import Combine
import Foundation
import MosaicCore
import MosaicFeatures
import MosaicPersistence
import MosaicPrivacy

public enum PhotoSelectionState: Equatable, Sendable {
    case idle
    case selectingHero
    case selectingSources
    case cancelled
    case failed(PhotoSelectionError)
}

@MainActor
public final class CreationSession: ObservableObject {
    @Published public private(set) var workflow: CreationWorkflow
    @Published public private(set) var isSaving = false
    @Published public private(set) var message: String?
    @Published public private(set) var photoSelectionState: PhotoSelectionState = .idle

    private let store: any ProjectStoring
    private let analytics: any AnalyticsRecording
    private let heroSelector: any HeroPhotoSelecting
    private let sourceSelector: any SourcePhotosSelecting

    public init(
        store: any ProjectStoring,
        analytics: any AnalyticsRecording = NoOpAnalyticsRecorder(),
        heroSelector: any HeroPhotoSelecting = UnavailablePhotoSelector(),
        sourceSelector: any SourcePhotosSelecting = UnavailablePhotoSelector(),
        project: MosaicProject = .init(),
        step: CreationStep? = nil
    ) {
        self.store = store
        self.analytics = analytics
        self.heroSelector = heroSelector
        self.sourceSelector = sourceSelector
        self.workflow = CreationWorkflow(project: project, step: step ?? Self.inferredStep(for: project))
    }

    public func startNewProject() async {
        workflow = CreationWorkflow()
        await persist(event: .projectStarted)
    }

    public func restoreMostRecentProject() async {
        do {
            let projects = try await store.list()
            if let project = projects.first {
                workflow = CreationWorkflow(project: project, step: Self.inferredStep(for: project))
            }
            message = nil
        } catch {
            message = "Your most recent project could not be restored."
        }
    }

    public func selectHero(_ reference: AssetReference) async {
        workflow.selectHero(reference)
        await persist(event: .heroSelected)
    }

    public func requestHeroSelection() async {
        photoSelectionState = .selectingHero
        message = nil
        do {
            guard let reference = try await heroSelector.selectHero() else {
                photoSelectionState = .cancelled
                return
            }
            await selectHero(reference)
            photoSelectionState = .idle
        } catch let error as PhotoSelectionError {
            handleSelectionError(error)
        } catch {
            handleSelectionError(.assetUnavailable("Unexpected photo selection failure"))
        }
    }

    public func reviewSources(_ references: [AssetReference]) async {
        workflow.reviewSources(references)
        await persist()
    }

    public func requestSourceSelection(request: SourceSelectionRequest = .init()) async {
        photoSelectionState = .selectingSources
        message = nil
        do {
            let references = try await sourceSelector.selectSources(request: request)
            await reviewSources(Array(references.prefix(request.maximumCount)))
            photoSelectionState = .idle
        } catch let error as PhotoSelectionError {
            handleSelectionError(error)
        } catch {
            handleSelectionError(.assetUnavailable("Unexpected photo selection failure"))
        }
    }

    public func confirmSources(minimum: Int = 100) async {
        do {
            try workflow.confirmReviewedSources(minimum: minimum)
            message = nil
            await persist(event: .sourceSetConfirmed)
        } catch CreationWorkflowError.insufficientSources(let required, let actual) {
            message = "Choose at least \(required) photos. You currently have \(actual)."
        } catch {
            message = "The source selection could not be confirmed."
        }
    }

    public func move(to step: CreationStep) async {
        workflow.move(to: step)
        await persist()
    }

    public func renameProject(to title: String) async {
        workflow.renameProject(to: title)
        await persist()
    }

    private static func inferredStep(for project: MosaicProject) -> CreationStep {
        if project.hero == nil { return .hero }
        if project.sources.isEmpty { return .memories }
        return .preview
    }

    private func handleSelectionError(_ error: PhotoSelectionError) {
        if error == .selectionCancelled {
            photoSelectionState = .cancelled
            message = nil
            return
        }
        photoSelectionState = .failed(error)
        switch error {
        case .permissionDenied:
            message = "Photo access was denied. You can still choose selected photos without granting full-library access."
        case .selectionCancelled:
            message = nil
        case .assetUnavailable:
            message = "A selected photo is unavailable. Choose another photo and try again."
        case .iCloudDownloadFailed:
            message = "A photo could not be downloaded from iCloud. Check your connection and try again."
        }
    }

    private func persist(event: AnalyticsEventName? = nil) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.save(workflow.project)
            if let event {
                await analytics.record(.init(name: event))
            }
            message = nil
        } catch {
            message = "Changes could not be saved. Please try again."
        }
    }
}
