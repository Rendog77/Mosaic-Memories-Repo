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
    case invalidSources(SourceSelectionValidationError)
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
    private let sourceValidator: SourceSelectionValidator

    public init(
        store: any ProjectStoring,
        analytics: any AnalyticsRecording = NoOpAnalyticsRecorder(),
        heroSelector: any HeroPhotoSelecting = UnavailablePhotoSelector(),
        sourceSelector: any SourcePhotosSelecting = UnavailablePhotoSelector(),
        sourceValidator: SourceSelectionValidator = .init(),
        project: MosaicProject = .init(),
        step: CreationStep? = nil
    ) {
        self.store = store
        self.analytics = ValidatingAnalyticsRecorder(destination: analytics)
        self.heroSelector = heroSelector
        self.sourceSelector = sourceSelector
        self.sourceValidator = sourceValidator
        self.workflow = CreationWorkflow(project: project, step: step ?? Self.inferredStep(for: project))
    }

    public func startNewProject() async {
        workflow = CreationWorkflow()
        await persist(
            event: .projectStarted,
            fields: [.workflowStep: "hero", .engineVersion: String(workflow.project.recipe.engineVersion)]
        )
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
        await persist(event: .heroSelected, fields: [.workflowStep: "memories"])
    }

    public func setHeroCrop(_ crop: HeroCrop) async {
        workflow.setHeroCrop(crop)
        await persist()
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
            let validated = try sourceValidator.validate(references, for: request)
            await reviewSources(validated)
            photoSelectionState = .idle
        } catch let error as SourceSelectionValidationError {
            handleSourceValidationError(error)
        } catch let error as PhotoSelectionError {
            handleSelectionError(error)
        } catch {
            handleSelectionError(.assetUnavailable("Unexpected photo selection failure"))
        }
    }

    public func requestAdditionalSources(request: SourceSelectionRequest = .init()) async {
        photoSelectionState = .selectingSources
        message = nil
        do {
            let additional = try await sourceSelector.selectSources(request: request)
            try await addSources(additional, request: request)
            photoSelectionState = .idle
        } catch let error as SourceSelectionValidationError {
            handleSourceValidationError(error)
        } catch let error as PhotoSelectionError {
            handleSelectionError(error)
        } catch {
            handleSelectionError(.assetUnavailable("Unexpected photo selection failure"))
        }
    }

    public func addSources(
        _ additional: [AssetReference],
        request: SourceSelectionRequest = .init()
    ) async throws {
        let combined = workflow.project.sources + additional
        let validated = try sourceValidator.validate(combined, for: request)
        await reviewSources(validated)
    }

    @discardableResult
    public func removeSource(id: String) async -> Bool {
        let originalWorkflow = workflow
        guard workflow.removeSource(id: id) else { return false }
        guard await persist() else {
            workflow = originalWorkflow
            return false
        }
        return true
    }

    public func sourceReadiness(minimum: Int = 100) -> SourceSetReadiness {
        workflow.sourceReadiness(minimum: minimum)
    }

    public func confirmSources(minimum: Int = 100) async {
        do {
            try workflow.confirmReviewedSources(minimum: minimum)
            message = nil
            await persist(
                event: .sourceSetConfirmed,
                fields: [
                    .workflowStep: "preview",
                    .sourceCountBucket: SourceCountBucket(count: workflow.project.sources.count).rawValue,
                ]
            )
        } catch CreationWorkflowError.insufficientSources(let required, let actual) {
            message = "Choose at least \(required) photos. You currently have \(actual)."
        } catch {
            message = "The source selection could not be confirmed."
        }
    }

    public func move(to step: CreationStep) async {
        workflow.move(to: step)
        let event: AnalyticsEventName? = step == .edit ? .previewCompleted : nil
        await persist(event: event, fields: [.workflowStep: Self.analyticsName(for: step)])
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

    private static func analyticsName(for step: CreationStep) -> String {
        switch step {
        case .hero: return "hero"
        case .memories: return "memories"
        case .sourceReview: return "source_review"
        case .preview: return "preview"
        case .edit: return "edit"
        case .export: return "export"
        }
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
        case .transferFailed:
            message = "A selected photo could not be imported. Choose it again and retry."
        case .unsupportedFormat:
            message = "A selected file is not a supported image. Choose another photo and try again."
        case .invalidDimensions:
            message = "A selected image has invalid dimensions. Choose another photo and try again."
        case .imageTooLarge:
            message = "A selected image is too large to process safely. Choose a smaller photo and try again."
        }
    }

    private func handleSourceValidationError(_ error: SourceSelectionValidationError) {
        photoSelectionState = .invalidSources(error)
        switch error {
        case .tooManySources(let maximum, let actual):
            message = "Choose no more than \(maximum) photos. You selected \(actual)."
        case .duplicateReferences(let identifiers):
            let noun = identifiers.count == 1 ? "photo was" : "photos were"
            message = "\(identifiers.count) duplicate \(noun) selected. Remove duplicates and try again."
        case .unexpectedOrigin:
            message = "Those photos came from an unexpected access mode. Please select them again."
        }
    }

    @discardableResult
    private func persist(
        event: AnalyticsEventName? = nil,
        fields: [AnalyticsField: String] = [:]
    ) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.save(workflow.project)
            if let event {
                await analytics.record(.init(name: event, fields: fields))
            }
            message = nil
            return true
        } catch {
            message = "Changes could not be saved. Please try again."
            return false
        }
    }
}
