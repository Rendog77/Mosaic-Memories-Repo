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
    @StateObject private var previewModel: MosaicPreviewViewModel
    private let onClose: () -> Void
    private let onChooseHero: (() -> Void)?
    private let onChooseSources: (() -> Void)?
    private let onRemoveSource: (@MainActor (AssetReference) async -> Void)?

    public init(
        session: CreationSession,
        assetLoader: any PhotoAssetLoading = UnavailablePhotoAssetLoader(),
        previewGenerator: any MosaicPreviewGenerating = UnavailableMosaicPreviewGenerator(),
        onChooseHero: (() -> Void)? = nil,
        onChooseSources: (() -> Void)? = nil,
        onRemoveSource: (@MainActor (AssetReference) async -> Void)? = nil,
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
        _previewModel = StateObject(wrappedValue: MosaicPreviewViewModel(generator: previewGenerator))
        self.onChooseHero = onChooseHero
        self.onChooseSources = onChooseSources
        self.onRemoveSource = onRemoveSource
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
            HeroSelectionScreen(session: session, model: heroModel, onChooseHero: onChooseHero)
        case .memories:
            MemorySelectionScreen(session: session, heroModel: heroModel, onChooseSources: onChooseSources)
        case .sourceReview:
            SourceReviewScreen(
                session: session,
                model: sourceModel,
                onChooseHero: onChooseHero,
                onChooseSources: onChooseSources,
                onRemoveSource: onRemoveSource
            )
        case .preview:
            PreviewPreparationScreen(session: session, model: previewModel)
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

private struct PreviewPreparationScreen: View {
    @ObservedObject var session: CreationSession
    @ObservedObject var model: MosaicPreviewViewModel

    var body: some View {
        VStack(spacing: MosaicDesign.standardSpacing) {
            Text("Your mosaic")
                .font(.title.bold())
            previewContent
                .frame(maxWidth: 560, maxHeight: 440)
            if case .loaded = model.state {
                Button("Continue to editor") {
                    Task { await session.move(to: .edit) }
                }
                .buttonStyle(.borderedProminent)
                .tint(MosaicDesign.accent)
                .controlSize(.large)
            }
        }
        .task(id: session.workflow.project) {
            await model.load(project: session.workflow.project)
        }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch model.state {
        case .idle:
            ProgressView("Preparing preview")
        case .loading(let status):
            VStack(spacing: MosaicDesign.compactSpacing) {
                ProgressView(value: status.fractionCompleted)
                    .frame(maxWidth: 320)
                Text(status.stage.title)
                    .font(.headline)
                Text("\(status.completed) of \(status.total)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Cancel", role: .cancel) { model.cancel() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(status.stage.title)
            .accessibilityValue("\(Int((status.fractionCompleted * 100).rounded())) percent")
        case .loaded(let preview):
            previewImage(data: preview.data)
                .aspectRatio(CGFloat(preview.width) / CGFloat(preview.height), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: MosaicDesign.cornerRadius))
                .accessibilityLabel("Generated mosaic preview")
        case .cancelled:
            retryCard(
                title: "Preview cancelled",
                detail: "Your selected photos are unchanged. Create the preview whenever you are ready."
            )
        case .failed(let message):
            retryCard(title: "Preview unavailable", detail: message)
        }
    }

    @ViewBuilder
    private func retryCard(title: String, detail: String) -> some View {
        VStack(spacing: MosaicDesign.compactSpacing) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
            Text(title).font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await model.load(project: session.workflow.project) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(MosaicDesign.standardSpacing)
    }

    @ViewBuilder
    private func previewImage(data: Data) -> some View {
#if canImport(UIKit)
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
        } else {
            invalidPreview
        }
#elseif canImport(AppKit)
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
        } else {
            invalidPreview
        }
#else
        invalidPreview
#endif
    }

    private var invalidPreview: some View {
        Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .accessibilityLabel("Preview image unavailable")
    }
}

private struct HeroSelectionScreen: View {
    @ObservedObject var session: CreationSession
    @ObservedObject var model: HeroPhotoViewModel
    let onChooseHero: (() -> Void)?

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
                if let onChooseHero {
                    onChooseHero()
                } else {
                    Task {
                        await session.requestHeroSelection()
                        if let reference = session.workflow.project.hero {
                            await model.load(reference)
                        }
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
    let onChooseSources: (() -> Void)?

    var body: some View {
        VStack(spacing: MosaicDesign.standardSpacing) {
            Text("Choose your memories")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            if session.workflow.project.hero != nil {
                ThumbnailView(state: heroModel.thumbnailState, emptySystemImage: "photo.fill")
                    .frame(width: 160, height: 120)
                    .accessibilityLabel("Hero photo with selected framing")
                Text("Frame your hero")
                    .font(.headline)
                Text("Choose the area to feature. The preview updates when you change the framing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: MosaicDesign.compactSpacing) {
                    ForEach(HeroCropPreset.allCases, id: \.self) { preset in
                        Button(preset.title) {
                            Task { await session.setHeroCrop(preset.crop) }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityValue(
                            HeroCropPreset.selected(for: session.workflow.project.heroCrop) == preset
                                ? "Selected" : "Not selected"
                        )
                    }
                }
            }
            Text("Select at least 100 photos. You will review them before anything is generated.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose source photos") {
                if let onChooseSources {
                    onChooseSources()
                } else {
                    Task { await session.requestSourceSelection() }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(MosaicDesign.accent)
            .controlSize(.large)
        }
        .task(id: session.workflow.project.heroCrop) {
            if let reference = session.workflow.project.hero,
               heroModel.reference != reference || heroModel.crop != session.workflow.project.heroCrop {
                await heroModel.load(reference, crop: session.workflow.project.heroCrop)
            }
        }
    }
}

private struct SourceReviewScreen: View {
    @ObservedObject var session: CreationSession
    @ObservedObject var model: SourceReviewViewModel
    let onChooseHero: (() -> Void)?
    let onChooseSources: (() -> Void)?
    let onRemoveSource: (@MainActor (AssetReference) async -> Void)?
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
                    if let onChooseSources {
                        onChooseSources()
                    } else {
                        Task {
                            await session.requestAdditionalSources()
                            model.replaceReferences(session.workflow.project.sources)
                        }
                    }
                }
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: MosaicDesign.compactSpacing) {
                    ForEach(model.items) { item in
                        SourceThumbnailCell(item: item, isMissing: session.missingAssetIDs.contains(item.id)) {
                            Task {
                                if await session.removeSource(id: item.id) {
                                    model.remove(id: item.id)
                                    await onRemoveSource?(item.reference)
                                }
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
                if session.isHeroMissing {
                    Button("Replace hero photo") {
                        if let onChooseHero {
                            onChooseHero()
                        } else {
                            Task { await session.requestHeroSelection() }
                        }
                    }
                }
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
                .disabled(!isReady || session.isCheckingAssets)
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
    let isMissing: Bool
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
            .overlay(alignment: .bottom) {
                if isMissing {
                    Text("Missing")
                        .font(.caption.bold())
                        .padding(4)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                        .accessibilityLabel("Photo no longer available")
                }
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
