import SwiftUI
import SwiftData

@main
struct WrapApp: App {
    /// Who's signed in. Shared by the window and the menu bar.
    @State private var auth = AuthService()

    init() {
        _ = AppUpdater.shared   // start the daily update check
    }

    var body: some Scene {
        Window("Wrap", id: "main") {
            RootView()
                .environment(auth)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 820)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(auth)
        } label: {
            Image("MenuBarIcon")
        }
    }
}

/// What appears when you click the logo in the menu bar.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AuthService.self) private var auth

    var body: some View {
        Button("Open Wrap") {
            openWindow(id: "main")
            NSApp.activate()
        }

        if let account = auth.account {
            MenuBarProjects()
                .modelContainer(LibraryStore.container(for: account.id))
        } else {
            Divider()
            Text("Open Wrap to log in")
        }

        Divider()
        Button("Quit Wrap") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// "Check for Updates…", greyed out while a check is running.
struct CheckForUpdatesButton: View {
    var body: some View {
        Button("Check for Updates…") {
            AppUpdater.shared.checkForUpdates()
        }
        .disabled(!AppUpdater.shared.canCheck)
    }
}

/// The signed-in account's newest active projects, one click to launch each.
struct MenuBarProjects: View {
    @Query(filter: #Predicate<Project> { $0.isWrapped == false },
           sort: \Project.createdAt, order: .reverse)
    private var activeProjects: [Project]

    var body: some View {
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
    }
}
