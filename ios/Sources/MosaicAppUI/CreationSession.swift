import Combine
import Foundation
import MosaicCore
import MosaicFeatures
import MosaicPersistence
import MosaicPrivacy

@MainActor
public final class CreationSession: ObservableObject {
    @Published public private(set) var workflow: CreationWorkflow
    @Published public private(set) var isSaving = false
    @Published public private(set) var message: String?

    private let store: any ProjectStoring
    private let analytics: any AnalyticsRecording

    public init(
        store: any ProjectStoring,
        analytics: any AnalyticsRecording = NoOpAnalyticsRecorder(),
        project: MosaicProject = .init(),
        step: CreationStep? = nil
    ) {
        self.store = store
        self.analytics = analytics
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

    public func reviewSources(_ references: [AssetReference]) async {
        workflow.reviewSources(references)
        await persist()
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
