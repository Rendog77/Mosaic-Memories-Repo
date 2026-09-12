import MosaicCore
import SwiftUI

public struct ProjectLibraryView: View {
    @ObservedObject private var session: ProjectLibrarySession
    private let onNewProject: () -> Void
    private let onContinueProject: (MosaicProject) -> Void
    @State private var projectToRename: MosaicProject?
    @State private var projectToDelete: MosaicProject?
    @State private var proposedTitle = ""

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
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                proposedTitle = project.title
                                projectToRename = project
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                projectToDelete = project
                            }
                        }
                    }
                    .listStyle(.plain)
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
        .alert(
            "Rename mosaic",
            isPresented: isRenaming,
            presenting: projectToRename
        ) { project in
            TextField("Project name", text: $proposedTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                Task { await session.rename(project, to: proposedTitle) }
            }
        }
        .confirmationDialog(
            "Delete this mosaic?",
            isPresented: isDeleting,
            titleVisibility: .visible,
            presenting: projectToDelete
        ) { project in
            Button("Delete “\(project.title)”", role: .destructive) {
                Task { await session.delete(project) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the saved project recipe from this device. Your original photos are not deleted.")
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(
            get: { projectToRename != nil },
            set: { if !$0 { projectToRename = nil } }
        )
    }

    private var isDeleting: Binding<Bool> {
        Binding(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        )
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
