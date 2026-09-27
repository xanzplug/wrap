import SwiftUI
import SwiftData

/// The main window: projects on the left, the selected project on the right.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var selectedID: PersistentIdentifier?

    private var activeProjects: [Project] { projects.filter { !$0.isWrapped } }
    private var wrappedProjects: [Project] { projects.filter { $0.isWrapped } }
    private var selectedProject: Project? {
        projects.first { $0.persistentModelID == selectedID }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                Section("Active") {
                    ForEach(activeProjects) { project in
                        row(for: project)
                    }
                }
                if !wrappedProjects.isEmpty {
                    Section("Wrapped") {
                        ForEach(wrappedProjects) { project in
                            row(for: project)
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Button("New Project", systemImage: "plus", action: addProject)
                        .keyboardShortcut("n")
                }
            }
            .onDeleteCommand {
                if let project = selectedProject { delete(project) }
            }
        } detail: {
            if let project = selectedProject {
                ProjectDetailView(project: project)
                    .id(project.persistentModelID)
            } else {
                ContentUnavailableView(
                    "No project selected",
                    systemImage: "film.stack",
                    description: Text("Pick a project, or press + to make one.")
                )
            }
        }
    }

    /// One project in the sidebar, with a right-click menu.
    private func row(for project: Project) -> some View {
        Text(project.displayName)
            .tag(project.persistentModelID)
            .contextMenu {
                Button(project.isWrapped ? "Move to Active" : "Mark as Wrapped") {
                    project.isWrapped.toggle()
                }
                Divider()
                Button("Delete", role: .destructive) {
                    delete(project)
                }
            }
    }

    private func addProject() {
        let project = Project(name: "Untitled Project")
        context.insert(project)
        try? context.save()   // save first so the project keeps a stable ID
        selectedID = project.persistentModelID
    }

    private func delete(_ project: Project) {
        if project.persistentModelID == selectedID { selectedID = nil }
        context.delete(project)
        try? context.save()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Project.self, Shot.self, WorkspaceItem.self], inMemory: true)
}
