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
    @StateObject private var tileInspectorModel: HeroPhotoViewModel
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
        _tileInspectorModel = StateObject(wrappedValue: HeroPhotoViewModel(loader: assetLoader))
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
            MosaicEditorScreen(
                session: session,
                previewModel: previewModel,
                inspectorModel: tileInspectorModel
            )
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

private struct MosaicEditorScreen: View {
    @ObservedObject var session: CreationSession
    @ObservedObject var previewModel: MosaicPreviewViewModel
    @ObservedObject var inspectorModel: HeroPhotoViewModel
    @State private var selectedTile: MosaicAssignedTile?
    @State private var likeness: Double

    init(
        session: CreationSession,
        previewModel: MosaicPreviewViewModel,
        inspectorModel: HeroPhotoViewModel
    ) {
        self.session = session
        self.previewModel = previewModel
        self.inspectorModel = inspectorModel
        _likeness = State(initialValue: session.workflow.project.recipe.likeness)
    }

    var body: some View {
        Group {
            if case .loaded(let preview) = previewModel.state {
                VStack(spacing: MosaicDesign.standardSpacing) {
                    Text("Explore your mosaic")
                        .font(.title.bold())
                    Text("Pinch to zoom, drag to move, and tap a tile to see its memory.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(spacing: MosaicDesign.compactSpacing) {
                        HStack {
                            Text("Photo Detail")
                            Spacer()
                            Text("Hero Likeness")
                        }
                        .font(.caption.bold())
                        Slider(
                            value: $likeness,
                            in: 0...1,
                            step: 0.05,
                            onEditingChanged: { isEditing in
                                if !isEditing { applyLikeness() }
                            }
                        )
                        .accessibilityLabel("Photo detail to hero likeness")
                        .accessibilityValue("\(Int((likeness * 100).rounded())) percent hero likeness")
                        Text("\(Int((likeness * 100).rounded()))% hero likeness")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let status = previewModel.refreshStatus {
                            ProgressView(value: status.fractionCompleted)
                                .accessibilityLabel("Updating hero likeness")
                        }
                        if let message = previewModel.refreshMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: 520)

                    InteractiveMosaicCanvas(preview: preview, selectedTile: selectedTile) { tile in
                        selectedTile = tile
                        inspectorModel.clear()
                        Task { await inspectorModel.load(tile.source, maximumPixelSize: 640) }
                    }
                    .aspectRatio(
                        CGFloat(preview.width) / CGFloat(preview.height),
                        contentMode: .fit
                    )
                    .frame(maxWidth: 620, maxHeight: 440)

                    if let selectedTile {
                        HStack(spacing: MosaicDesign.standardSpacing) {
                            ThumbnailView(
                                state: inspectorModel.thumbnailState,
                                emptySystemImage: "photo"
                            )
                            .frame(width: 96, height: 96)
                            VStack(alignment: .leading, spacing: MosaicDesign.compactSpacing) {
                                Text("Selected memory")
                                    .font(.headline)
                                Text(
                                    "Tile \(selectedTile.coordinate.column + 1), " +
                                        "\(selectedTile.coordinate.row + 1)"
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(MosaicDesign.compactSpacing)
                        .background(.background, in: RoundedRectangle(cornerRadius: MosaicDesign.cornerRadius))
                        .accessibilityElement(children: .contain)
                    }

                    Button("Continue to export") {
                        Task { await session.move(to: .export) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MosaicDesign.accent)
                    .disabled(previewModel.refreshStatus != nil)
                }
            } else {
                StepCard(
                    title: "Preview required",
                    detail: "Create the mosaic preview before opening the editor.",
                    actionTitle: "Create preview"
                ) {
                    await session.move(to: .preview)
                }
            }
        }
        .onDisappear { previewModel.cancel() }
    }

    private func applyLikeness() {
        guard likeness != session.workflow.project.recipe.likeness else { return }
        Task {
            let saved = await session.setLikeness(likeness)
            guard saved else {
                likeness = session.workflow.project.recipe.likeness
                return
            }
            await previewModel.rerender(project: session.workflow.project)
        }
    }
}

private struct InteractiveMosaicCanvas: View {
    let preview: MosaicPreviewOutput
    let selectedTile: MosaicAssignedTile?
    let onSelect: (MosaicAssignedTile) -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let imageSize = fittedSize(in: geometry.size)
            let displayedScale = boundedScale(scale * gestureScale)
            let displayedOffset = boundedOffset(
                CGSize(
                    width: offset.width + gestureTranslation.width,
                    height: offset.height + gestureTranslation.height
                ),
                imageSize: imageSize,
                scale: displayedScale
            )

            ZStack {
                Color.black.opacity(0.08)
                mosaicLayer(size: imageSize)
                    .scaleEffect(displayedScale)
                    .offset(displayedOffset)
            }
            .clipShape(RoundedRectangle(cornerRadius: MosaicDesign.cornerRadius))
            .overlay(alignment: .topTrailing) {
                if scale > 1.001 || offset != .zero {
                    Button("Reset view") {
                        withAnimation {
                            scale = 1
                            offset = .zero
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(MosaicDesign.compactSpacing)
                }
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($gestureScale) { value, state, _ in state = value }
                    .onEnded { value in
                        let newScale = boundedScale(scale * value)
                        scale = newScale
                        offset = boundedOffset(offset, imageSize: imageSize, scale: newScale)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .updating($gestureTranslation) { value, state, _ in
                        if displayedScale > 1 { state = value.translation }
                    }
                    .onEnded { value in
                        guard displayedScale > 1 else { return }
                        offset = boundedOffset(
                            CGSize(
                                width: offset.width + value.translation.width,
                                height: offset.height + value.translation.height
                            ),
                            imageSize: imageSize,
                            scale: displayedScale
                        )
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Interactive mosaic preview")
            .accessibilityValue("\(Int((scale * 100).rounded())) percent zoom")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    scale = boundedScale(scale + 0.5)
                    offset = boundedOffset(offset, imageSize: imageSize, scale: scale)
                case .decrement:
                    scale = boundedScale(scale - 0.5)
                    offset = boundedOffset(offset, imageSize: imageSize, scale: scale)
                @unknown default: break
                }
            }
        }
    }

    private func mosaicLayer(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            previewImage
                .frame(width: size.width, height: size.height)
            if let selectedTile {
                let cellWidth = size.width / CGFloat(preview.columns)
                let cellHeight = size.height / CGFloat(preview.rows)
                Rectangle()
                    .stroke(.white, lineWidth: 2)
                    .shadow(color: .black.opacity(0.8), radius: 1)
                    .frame(width: cellWidth, height: cellHeight)
                    .offset(
                        x: CGFloat(selectedTile.coordinate.column) * cellWidth,
                        y: CGFloat(selectedTile.coordinate.row) * cellHeight
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                guard size.width > 0, size.height > 0,
                      let tile = preview.tile(
                          normalizedX: Double(value.location.x / size.width),
                          normalizedY: Double(value.location.y / size.height)
                      ) else { return }
                onSelect(tile)
            }
        )
    }

    @ViewBuilder
    private var previewImage: some View {
#if canImport(UIKit)
        if let image = UIImage(data: preview.data) {
            Image(uiImage: image).resizable()
        } else {
            Color.secondary
        }
#elseif canImport(AppKit)
        if let image = NSImage(data: preview.data) {
            Image(nsImage: image).resizable()
        } else {
            Color.secondary
        }
#else
        Color.secondary
#endif
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        guard available.width > 0, available.height > 0 else { return .zero }
        let imageAspect = CGFloat(preview.width) / CGFloat(preview.height)
        let availableAspect = available.width / available.height
        if imageAspect > availableAspect {
            return .init(width: available.width, height: available.width / imageAspect)
        }
        return .init(width: available.height * imageAspect, height: available.height)
    }

    private func boundedScale(_ value: CGFloat) -> CGFloat {
        min(6, max(1, value))
    }

    private func boundedOffset(_ value: CGSize, imageSize: CGSize, scale: CGFloat) -> CGSize {
        guard scale > 1 else { return .zero }
        let maximumX = imageSize.width * (scale - 1) / 2
        let maximumY = imageSize.height * (scale - 1) / 2
        return .init(
            width: min(maximumX, max(-maximumX, value.width)),
            height: min(maximumY, max(-maximumY, value.height))
        )
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
