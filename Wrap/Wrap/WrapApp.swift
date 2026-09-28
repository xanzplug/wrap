import SwiftUI
import SwiftData

@main
struct WrapApp: App {
    /// One shared library, used by both the main window and the menu bar.
    let container: ModelContainer = {
        do {
            return try ModelContainer(for: Project.self, Shot.self, WorkspaceItem.self)
        } catch {
            fatalError("Could not open the project library: \(error)")
        }
    }()

    var body: some Scene {
        Window("Wrap", id: "main") {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 820)
        .modelContainer(container)

        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image("MenuBarIcon")
        }
        .modelContainer(container)
    }
}

/// What appears when you click the film icon in the menu bar.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    @Query(filter: #Predicate<Project> { $0.isWrapped == false },
           sort: \Project.createdAt, order: .reverse)
    private var activeProjects: [Project]

    var body: some View {
        Button("Open Wrap") {
            openWindow(id: "main")
            NSApp.activate()
        }

        if !activeProjects.isEmpty {
            Divider()
            Text("Launch a workspace")
            ForEach(activeProjects.prefix(5)) { project in
                Button(project.displayName, systemImage: "play.fill") {
                    WorkspaceLauncher.launch(project.sortedWorkspaceItems)
                }
                .disabled(project.workspaceItems.isEmpty)
            }
        }

        Divider()
        Button("Quit Wrap") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
