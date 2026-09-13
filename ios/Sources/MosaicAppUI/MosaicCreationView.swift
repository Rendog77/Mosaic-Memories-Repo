import Foundation
import MosaicCore
import MosaicFeatures
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct MosaicCreationView: View {
    @ObservedObject private var session: CreationSession
    @StateObject private var heroModel: HeroPhotoViewModel
    @StateObject private var sourceModel: SourceReviewViewModel
    private let onClose: () -> Void

    public init(
        session: CreationSession,
        assetLoader: any PhotoAssetLoading = UnavailablePhotoAssetLoader(),
        onClose: @escaping () -> Void = {}
    ) {
        self.session = session
        _heroModel = StateObject(wrappedValue: HeroPhotoViewModel(loader: assetLoader))
        _sourceModel = StateObject(
            wrappedValue: SourceReviewViewModel(
                references: session.workflow.project.sources,
                loader: assetLoader
            )
        )
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: MosaicDesign.generousSpacing) {
                CreationProgress(step: session.workflow.step)
                Spacer()
                stepContent
                Spacer()
                if let message = session.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Notice: \(message)")
                }
            }
            .padding(MosaicDesign.standardSpacing)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .background(MosaicDesign.canvas.ignoresSafeArea())
            .navigationTitle("Mosaic Memories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Your mosaics", action: onClose)
                }
            }
            .overlay(alignment: .topTrailing) {
                if session.isSaving {
                    ProgressView("Saving")
                        .controlSize(.small)
                        .padding()
                }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch session.workflow.step {
        case .hero:
            HeroSelectionScreen(session: session, model: heroModel)
        case .memories:
            MemorySelectionScreen(session: session, heroModel: heroModel)
        case .sourceReview:
            SourceReviewScreen(session: session, model: sourceModel)
        case .preview:
            StepCard(
                title: "Create your mosaic",
                detail: "The preview engine will build the first recognisable composition here.",
                actionTitle: "Continue to editor"
            ) {
                await session.move(to: .edit)
            }
        case .edit:
            StepCard(
                title: "Make it yours",
                detail: "Zoom, inspect memories, replace tiles, and balance photo detail with hero likeness.",
                actionTitle: "Continue to export"
            ) {
                await session.move(to: .export)
            }
        case .export:
            StepCard(
                title: "Keep your memory",
                detail: "Save or share a high-quality image when export rendering is connected.",
                actionTitle: "Start another mosaic"
            ) {
                await session.startNewProject()
            }
        }
    }
}

private struct HeroSelectionScreen: View {
    @ObservedObject var session: CreationSession
    @ObservedObject var model: HeroPhotoViewModel

    var body: some View {
        VStack(spacing: MosaicDesign.standardSpacing) {
            Text("Choose your picture")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Select the main image your memories will recreate.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ThumbnailView(state: model.thumbnailState, emptySystemImage: "photo")
                .frame(maxWidth: 420, maxHeight: 320)
                .aspectRatio(4 / 3, contentMode: .fit)
            Button("Choose hero photo") {
                Task {
                    await session.requestHeroSelection()
                    if let reference = session.workflow.project.hero {
                        await model.load(reference)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(MosaicDesign.accent)
            .controlSize(.large)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct MemorySelectionScreen: View {
    @ObservedObject var session: CreationSession
    @ObservedObject var heroModel: HeroPhotoViewModel

    var body: some View {
        VStack(spacing: MosaicDesign.standardSpacing) {
            Text("Choose your memories")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            if session.workflow.project.hero != nil {
                ThumbnailView(state: heroModel.thumbnailState, emptySystemImage: "photo.fill")
                    .frame(width: 160, height: 120)
                    .accessibilityLabel("Selected hero photo")
            }
            Text("Select at least 100 photos. You will review them before anything is generated.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose source photos") {
                Task { await session.requestSourceSelection() }
            }
            .buttonStyle(.borderedProminent)
            .tint(MosaicDesign.accent)
            .controlSize(.large)
        }
        .task {
            if let reference = session.workflow.project.hero, heroModel.reference != reference {
                await heroModel.load(reference)
            }
        }
    }
}

private struct SourceReviewScreen: View {
    @ObservedObject var session: CreationSession
    @ObservedObject var model: SourceReviewViewModel
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: MosaicDesign.compactSpacing)]

    var body: some View {
        VStack(spacing: MosaicDesign.standardSpacing) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: MosaicDesign.compactSpacing) {
                    Text("Review your photos")
                        .font(.title.bold())
                    readinessText
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add photos", systemImage: "plus") {
                    Task {
                        await session.requestAdditionalSources()
                        model.replaceReferences(session.workflow.project.sources)
                    }
                }
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: MosaicDesign.compactSpacing) {
                    ForEach(model.items) { item in
                        SourceThumbnailCell(item: item) {
                            Task {
                                await session.removeSource(id: item.id)
                                model.remove(id: item.id)
                            }
                        }
                        .task(id: item.id) {
                            if item.state == .idle {
                                await model.loadThumbnail(for: item.id)
                            }
                        }
                    }
                }
            }

            HStack {
                if model.items.contains(where: { if case .failed = $0.state { return true }; return false }) {
                    Button("Retry failed thumbnails") {
                        Task { await model.retryFailed() }
                    }
                }
                Spacer()
                Button("Confirm photos") {
                    Task { await session.confirmSources() }
                }
                .buttonStyle(.borderedProminent)
                .tint(MosaicDesign.accent)
                .disabled(!isReady)
            }
        }
        .task(id: session.workflow.project.sources) {
            model.replaceReferences(session.workflow.project.sources)
        }
    }

    private var isReady: Bool {
        if case .ready = session.sourceReadiness() { return true }
        return false
    }

    @ViewBuilder
    private var readinessText: some View {
        switch session.sourceReadiness() {
        case .ready(let count):
            Text("\(count) photos selected — ready to create")
        case .needsMore(let required, let actual):
            Text("\(actual) selected — choose \(required - actual) more")
        }
    }
}

private struct SourceThumbnailCell: View {
    let item: SourceThumbnailItem
    let remove: () -> Void

    var body: some View {
        ThumbnailView(state: item.state, emptySystemImage: "photo")
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.65))
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Remove photo")
            }
            .accessibilityElement(children: .contain)
    }
}

private struct ThumbnailView: View {
    let state: ThumbnailLoadingState
    let emptySystemImage: String

    @ViewBuilder
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MosaicDesign.cornerRadius)
                .fill(.secondary.opacity(0.12))
            switch state {
            case .idle:
                Image(systemName: emptySystemImage)
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                    .accessibilityLabel("Loading thumbnail")
            case .loaded(let data):
                platformImage(data: data)
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Thumbnail unavailable")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MosaicDesign.cornerRadius))
    }

    @ViewBuilder
    private func platformImage(data: Data) -> some View {
#if canImport(UIKit)
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
#elseif canImport(AppKit)
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
#else
        Image(systemName: "photo")
#endif
    }
}

private struct CreationProgress: View {
    let step: CreationStep

    var body: some View {
        ProgressView(value: Double(step.rawValue + 1), total: Double(CreationStep.allCases.count))
            .tint(MosaicDesign.accent)
            .accessibilityLabel("Creation progress")
            .accessibilityValue("Step \(step.rawValue + 1) of \(CreationStep.allCases.count)")
    }
}

private struct StepCard: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: @MainActor () async -> Void

    var body: some View {
        VStack(spacing: MosaicDesign.standardSpacing) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 48))
                .foregroundStyle(MosaicDesign.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(MosaicDesign.ink)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(actionTitle) {
                Task { await action() }
            }
            .buttonStyle(.borderedProminent)
            .tint(MosaicDesign.accent)
            .controlSize(.large)
        }
        .padding(MosaicDesign.generousSpacing)
        .background(.background, in: RoundedRectangle(cornerRadius: MosaicDesign.cornerRadius))
        .accessibilityElement(children: .contain)
    }
}
