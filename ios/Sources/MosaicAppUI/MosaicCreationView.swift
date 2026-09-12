import MosaicCore
import MosaicFeatures
import SwiftUI

public struct MosaicCreationView: View {
    @ObservedObject private var session: CreationSession
    private let onClose: () -> Void

    public init(session: CreationSession, onClose: @escaping () -> Void = {}) {
        self.session = session
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
            StepCard(
                title: "Choose your picture",
                detail: "Select the main image your memories will recreate.",
                actionTitle: "Choose hero photo"
            ) {
                await session.selectHero(.init(id: "ui-placeholder-hero", origin: .testFixture))
            }
        case .memories:
            StepCard(
                title: "Choose your memories",
                detail: "For the first release, select at least 100 photos using Apple's system picker.",
                actionTitle: "Choose source photos"
            ) {
                let fixtures = (0..<100).map { AssetReference(id: "ui-placeholder-\($0)", origin: .testFixture) }
                await session.reviewSources(fixtures)
            }
        case .sourceReview:
            StepCard(
                title: "Review your photos",
                detail: "\(session.workflow.project.sources.count) photos selected. Remove anything you do not want included.",
                actionTitle: "Confirm photos"
            ) {
                await session.confirmSources()
            }
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
