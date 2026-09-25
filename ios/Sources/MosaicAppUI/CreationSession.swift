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

public struct TileReplacementChange: Equatable, Sendable {
    public let coordinate: TileCoordinate
    public let source: AssetReference

    public init(coordinate: TileCoordinate, source: AssetReference) {
        self.coordinate = coordinate
        self.source = source
    }
}

public enum MosaicEditChange: Equatable, Sendable {
    case likeness(Double)
    case tileReplacement(TileReplacementChange)
}

private enum MosaicEditCommand: Sendable {
    case likeness(before: Double, after: Double)
    case tileReplacement(
        coordinate: TileCoordinate,
        beforeOverride: AssetReference?,
        afterOverride: AssetReference,
        beforeSource: AssetReference,
        afterSource: AssetReference
    )
}

@MainActor
public final class CreationSession: ObservableObject {
    @Published public private(set) var workflow: CreationWorkflow
    @Published public private(set) var isSaving = false
    @Published public private(set) var isCheckingAssets = false
    @Published public private(set) var message: String?
    @Published public private(set) var photoSelectionState: PhotoSelectionState = .idle
    @Published public private(set) var missingAssetIDs: Set<String> = []
    @Published public private(set) var isHeroMissing = false
    @Published public private(set) var canUndoEdit = false
    @Published public private(set) var canRedoEdit = false

    private let store: any ProjectStoring
    private let analytics: any AnalyticsRecording
    private let heroSelector: any HeroPhotoSelecting
    private let sourceSelector: any SourcePhotosSelecting
    private let sourceValidator: SourceSelectionValidator
    private let assetChecker: (any PhotoAssetChecking)?
    private var editUndoStack: [MosaicEditCommand] = []
    private var editRedoStack: [MosaicEditCommand] = []

    public init(
        store: any ProjectStoring,
        analytics: any AnalyticsRecording = NoOpAnalyticsRecorder(),
        heroSelector: any HeroPhotoSelecting = UnavailablePhotoSelector(),
        sourceSelector: any SourcePhotosSelecting = UnavailablePhotoSelector(),
        sourceValidator: SourceSelectionValidator = .init(),
        assetChecker: (any PhotoAssetChecking)? = nil,
        project: MosaicProject = .init(),
        step: CreationStep? = nil
    ) {
        self.store = store
        self.analytics = ValidatingAnalyticsRecorder(destination: analytics)
        self.heroSelector = heroSelector
        self.sourceSelector = sourceSelector
        self.sourceValidator = sourceValidator
        self.assetChecker = assetChecker
        self.workflow = CreationWorkflow(project: project, step: step ?? Self.inferredStep(for: project))
    }

    public func startNewProject() async {
        clearEditHistory()
        missingAssetIDs = []
        isHeroMissing = false
        workflow = CreationWorkflow()
        await persist(
            event: .projectStarted,
            fields: [.workflowStep: "hero", .engineVersion: String(workflow.project.recipe.engineVersion)]
        )
    }

    public func restoreMostRecentProject() async {
        clearEditHistory()
        do {
            let projects = try await store.list()
            if let project = projects.first {
                missingAssetIDs = []
                isHeroMissing = false
                workflow = CreationWorkflow(project: project, step: Self.inferredStep(for: project))
            }
            message = nil
        } catch {
            message = "Your most recent project could not be restored."
        }
    }

    public func selectHero(_ reference: AssetReference) async {
        clearEditHistory()
        missingAssetIDs = []
        isHeroMissing = false
        workflow.selectHero(reference)
        await persist(event: .heroSelected, fields: [.workflowStep: Self.analyticsName(for: workflow.step)])
    }

    public func setHeroCrop(_ crop: HeroCrop?) async {
        guard workflow.project.hero != nil else { return }
        let previousWorkflow = workflow
        workflow.setHeroCrop(crop)
        if !(await persist()) {
            workflow = previousWorkflow
        } else {
            clearEditHistory()
        }
    }

    @discardableResult
    public func setLikeness(_ likeness: Double) async -> Bool {
        let previousLikeness = workflow.project.recipe.likeness
        guard likeness != previousLikeness else { return true }
        let previousWorkflow = workflow
        do {
            try workflow.setLikeness(likeness)
        } catch {
            message = "Choose a likeness value between Photo Detail and Hero Likeness."
            return false
        }
        guard await persist() else {
            workflow = previousWorkflow
            return false
        }
        record(.likeness(before: previousLikeness, after: likeness))
        return true
    }

    @discardableResult
    public func replaceTile(
        at coordinate: TileCoordinate,
        with source: AssetReference,
        replacing currentSource: AssetReference
    ) async -> Bool {
        let previousWorkflow = workflow
        let previousOverride = workflow.project.recipe.replacements[coordinate]
        guard previousOverride != source || currentSource != source else { return true }
        do {
            try workflow.setTileReplacement(source, at: coordinate)
        } catch {
            message = "That photo cannot be used for this tile."
            return false
        }
        guard await persist() else {
            workflow = previousWorkflow
            return false
        }
        record(
            .tileReplacement(
                coordinate: coordinate,
                beforeOverride: previousOverride,
                afterOverride: source,
                beforeSource: currentSource,
                afterSource: source
            )
        )
        return true
    }

    public func undoLastEdit() async -> MosaicEditChange? {
        guard let command = editUndoStack.last else { return nil }
        let previousWorkflow = workflow
        do {
            let change = try apply(command, forward: false)
            guard await persist() else {
                workflow = previousWorkflow
                return nil
            }
            editUndoStack.removeLast()
            editRedoStack.append(command)
            updateEditHistoryAvailability()
            return change
        } catch {
            workflow = previousWorkflow
            message = "That edit could not be undone."
            return nil
        }
    }

    public func redoLastEdit() async -> MosaicEditChange? {
        guard let command = editRedoStack.last else { return nil }
        let previousWorkflow = workflow
        do {
            let change = try apply(command, forward: true)
            guard await persist() else {
                workflow = previousWorkflow
                return nil
            }
            editRedoStack.removeLast()
            editUndoStack.append(command)
            updateEditHistoryAvailability()
            return change
        } catch {
            workflow = previousWorkflow
            message = "That edit could not be redone."
            return nil
        }
    }

    public func rollbackLastEdit() async -> MosaicEditChange? {
        guard let change = await undoLastEdit() else { return nil }
        editRedoStack = []
        updateEditHistoryAvailability()
        return change
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
        clearEditHistory()
        missingAssetIDs = []
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
        clearEditHistory()
        missingAssetIDs.remove(id)
        return true
    }

    public func sourceReadiness(minimum: Int = 100) -> SourceSetReadiness {
        workflow.sourceReadiness(minimum: minimum)
    }

    public func confirmSources(minimum: Int = 100) async {
        guard !isCheckingAssets else { return }
        isCheckingAssets = true
        defer { isCheckingAssets = false }
        do {
            if case .needsMore(let required, let actual) = workflow.sourceReadiness(minimum: minimum) {
                throw CreationWorkflowError.insufficientSources(required: required, actual: actual)
            }
            if let assetChecker {
                let project = workflow.project
                if let hero = project.hero, !(await assetChecker.isAvailable(hero)) {
                    isHeroMissing = true
                    message = "Your hero photo is no longer available. Choose it again before creating a mosaic."
                    return
                }
                isHeroMissing = false
                var missingIDs = Set<String>()
                for reference in project.sources {
                    if !(await assetChecker.isAvailable(reference)) {
                        missingIDs.insert(reference.id)
                    }
                }
                guard workflow.project == project else { return }
                missingAssetIDs = missingIDs
                if !missingIDs.isEmpty {
                    message = "\(missingIDs.count) selected \(missingIDs.count == 1 ? "photo is" : "photos are") no longer available. Remove the marked photos or select them again."
                    return
                }
            }
            missingAssetIDs = []
            isHeroMissing = false
            let previousWorkflow = workflow
            try workflow.confirmReviewedSources(minimum: minimum)
            message = nil
            if !(await persist(
                event: .sourceSetConfirmed,
                fields: [
                    .workflowStep: "preview",
                    .sourceCountBucket: SourceCountBucket(count: workflow.project.sources.count).rawValue,
                ]
            )) {
                workflow = previousWorkflow
            }
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
        return project.sourcesConfirmed ? .preview : .sourceReview
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

    private func record(_ command: MosaicEditCommand) {
        editUndoStack.append(command)
        editRedoStack = []
        updateEditHistoryAvailability()
    }

    private func apply(_ command: MosaicEditCommand, forward: Bool) throws -> MosaicEditChange {
        switch command {
        case .likeness(let before, let after):
            let value = forward ? after : before
            try workflow.setLikeness(value)
            return .likeness(value)
        case .tileReplacement(
            let coordinate,
            let beforeOverride,
            let afterOverride,
            let beforeSource,
            let afterSource
        ):
            let override = forward ? afterOverride : beforeOverride
            let source = forward ? afterSource : beforeSource
            try workflow.setTileReplacement(override, at: coordinate)
            return .tileReplacement(.init(coordinate: coordinate, source: source))
        }
    }

    private func clearEditHistory() {
        editUndoStack = []
        editRedoStack = []
        updateEditHistoryAvailability()
    }

    private func updateEditHistoryAvailability() {
        canUndoEdit = !editUndoStack.isEmpty
        canRedoEdit = !editRedoStack.isEmpty
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
