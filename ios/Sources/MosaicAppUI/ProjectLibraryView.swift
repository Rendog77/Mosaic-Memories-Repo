import MosaicCore
import SwiftUI

public struct ProjectLibraryView: View {
    @ObservedObject private var session: ProjectLibrarySession
    private let onNewProject: () -> Void
    private let onContinueProject: (MosaicProject) -> Void

    public init(
        session: ProjectLibrarySession,
        onNewProject: @escaping () -> Void,
        onContinueProject: @escaping (MosaicProject) -> Void
    ) {
        self.session = session
        self.onNewProject = onNewProject
        self.onContinueProject = onContinueProject
    }

    public var body: some View {
        NavigationStack {
            Group {
                if session.isLoading && session.projects.isEmpty {
                    ProgressView("Loading your mosaics")
                } else if session.projects.isEmpty {
                    ContentUnavailableView(
                        "Create your first mosaic",
                        systemImage: "square.grid.3x3.fill",
                        description: Text("Turn a collection of personal photos into one picture you will keep.")
                    )
                } else {
                    List(session.projects) { project in
                        Button {
                            onContinueProject(project)
                        } label: {
                            ProjectRow(project: project)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Continues this mosaic")
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Your mosaics")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New mosaic", systemImage: "plus", action: onNewProject)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message = session.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                        .accessibilityLabel("Notice: \(message)")
                }
            }
        }
        .task { await session.refresh() }
        .refreshable { await session.refresh() }
    }
}

private struct ProjectRow: View {
    let project: MosaicProject

    var body: some View {
        VStack(alignment: .leading, spacing: MosaicDesign.compactSpacing) {
            Text(project.title)
                .font(.headline)
            Text(project.updatedAt, style: .relative)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(project.sources.count) source photos")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, MosaicDesign.compactSpacing)
    }
}
