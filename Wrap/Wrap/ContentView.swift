import SwiftUI
import SwiftData

/// Which page the main window is showing.
enum Route: Hashable {
    case dashboard
    case projects
    case project(PersistentIdentifier)
}

/// The main window: a top bar, page tabs, then the current page.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var route: Route = .dashboard
    @State private var searchRequest = false

    private var activeProjects: [Project] { projects.filter { !$0.isWrapped } }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                status: statusText,
                onProjects: { route = .projects },
                onSearch: {
                    route = .projects
                    searchRequest = true
                },
                onNewProject: { createProject(named: "") }
            )
            Rectangle().fill(Color.wrapBorder).frame(height: 1)
            pageTabs
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.wrapBackground)
        .frame(minWidth: 900, minHeight: 640)
        .task(id: reminderKey) {
            ShootReminders.schedule(for: projects)
        }
    }

    /// Changes whenever a shoot date, wrap state or shot count changes,
    /// so the reminders are rescheduled.
    private var reminderKey: String {
        projects.map { project in
            let shoot = project.shootDate.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
            let left = project.shots.filter { !$0.isDone }.count
            return "\(project.remoteID)|\(project.displayName)|\(shoot)|\(project.isWrapped)|\(left)"
        }.joined(separator: ",")
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        switch route {
        case .dashboard:
            DashboardView(projects: projects, open: open, create: createProject)
        case .projects:
            ProjectsListView(projects: projects, open: open, create: createProject, delete: delete,
                             searchRequest: $searchRequest)
        case .project(let id):
            if let project = projects.first(where: { $0.persistentModelID == id }) {
                ProjectPage(project: project, back: { route = .dashboard }, delete: { delete(project) })
            } else {
                DashboardView(projects: projects, open: open, create: createProject)
            }
        }
    }

    private var pageTabs: some View {
        HStack(spacing: 28) {
            tab("Dashboard", isOn: route == .dashboard) { route = .dashboard }
            tab("Projects", isOn: route != .dashboard) { route = .projects }
            Spacer()
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 16)
    }

    private func tab(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(isOn ? Color.white : Color.wrapSecondary)
    }

    private var statusText: String {
        let count = activeProjects.count
        let left = activeProjects.flatMap(\.shots).filter { !$0.isDone }.count
        let projectsPart = count == 1 ? "1 active project" : "\(count) active projects"
        let shotsPart = left == 1 ? "1 shot to go" : "\(left) shots to go"
        return count == 0 ? "No projects yet · make one to get started" : "\(projectsPart) · \(shotsPart)"
    }

    // MARK: Actions

    private func open(_ project: Project) {
        route = .project(project.persistentModelID)
    }

    private func createProject(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let project = Project(name: trimmed.isEmpty ? "Untitled Project" : trimmed)
        context.insert(project)
        try? context.save()   // save first so the project keeps a stable ID
        open(project)
    }

    private func delete(_ project: Project) {
        if case .project(let id) = route, id == project.persistentModelID {
            route = .dashboard
        }
        SyncEngine.shared.recordDeletion(.projects, id: project.remoteID)
        context.delete(project)
        try? context.save()
    }
}

/// The strip across the top: logo, status, and quick buttons.
struct TopBar: View {
    @Environment(AuthService.self) private var auth
    let status: String
    let onProjects: () -> Void
    let onSearch: () -> Void
    let onNewProject: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image("WrapLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 18)
                Text("wrap")
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.3)
            }
            Rectangle().fill(Color.wrapBorder).frame(width: 1, height: 18)
            Text(status)
                .font(.system(size: 13))
                .foregroundStyle(Color.wrapSecondary)
                .lineLimit(1)
            Spacer()
            Button("Search", systemImage: "magnifyingglass", action: onSearch)
                .buttonStyle(.wrapSecondary)
                .keyboardShortcut("f", modifiers: .command)
                .help("Search projects (⌘F)")
            Button("Projects", action: onProjects).buttonStyle(.wrapSecondary)
            Button("New project", action: onNewProject).buttonStyle(.wrapSecondary)
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.wrapSecondary)
            syncLabel
            accountMenu
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)   // room for the window's close/minimise buttons
        .padding(.bottom, 14)
    }

    /// A small "Synced" / "Syncing…" / "Sync failed" note next to your initial.
    @ViewBuilder private var syncLabel: some View {
        switch SyncEngine.shared.status {
        case .idle:
            EmptyView()
        case .syncing:
            Text("Syncing…")
                .font(.system(size: 12))
                .foregroundStyle(Color.wrapSecondary)
        case .synced:
            Label("Synced", systemImage: "checkmark.icloud")
                .font(.system(size: 12))
                .foregroundStyle(Color.wrapSecondary)
        case .failed(let message):
            Label("Sync failed", systemImage: "exclamationmark.icloud")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .help(message)
        }
    }

    /// A round initial; click for your email and Sign Out.
    private var accountMenu: some View {
        Menu {
            if let account = auth.account {
                Text(account.name.isEmpty ? account.email : "\(account.name) · \(account.email)")
            }
            Button("Sync Now") {
                Task { await SyncEngine.shared.syncNow() }
            }
            Divider()
            Button("Sign Out") {
                Task { await auth.signOut() }
            }
        } label: {
            Text(initial)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .overlay(Circle().strokeBorder(Color.wrapBorder))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var initial: String {
        let source = auth.account.map { $0.name.isEmpty ? $0.email : $0.name } ?? "?"
        return source.first.map { String($0).uppercased() } ?? "?"
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Project.self, Shot.self, WorkspaceItem.self, ShotTemplate.self], inMemory: true)
        .environment(AuthService())
        .preferredColorScheme(.dark)
}
