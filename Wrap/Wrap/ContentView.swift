import SwiftUI
import SwiftData

/// Which page the main window is showing.
enum Route: Hashable {
    case dashboard
    case projects
    case settings
    case project(PersistentIdentifier)
}

/// The main window: a floating nav bar, then the current page.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var route: Route = .dashboard
    @State private var searchRequest = false
    @AppStorage(ShootReminders.enabledKey) private var remindersOn = true

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                selected: selectedTab,
                select: { tab in
                    withAnimation(.easeOut(duration: 0.18)) {
                        switch tab {
                        case .dashboard: route = .dashboard
                        case .projects: route = .projects
                        case .settings: route = .settings
                        }
                    }
                },
                onSearch: {
                    route = .projects
                    searchRequest = true
                },
                onNewProject: { createProject(named: "") }
            )
            .padding(.horizontal, 16)
            .padding(.top, 38)      // room for the window's close/minimise buttons
            .padding(.bottom, 8)

            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }
        .background(Color.wrapBackground)
        .frame(minWidth: 900, minHeight: 640)
        .onAppear {
            if UserDefaults.standard.string(forKey: AppSettings.startPage) == "projects" {
                route = .projects
            }
        }
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
            return "\(remindersOn)|\(project.remoteID)|\(project.displayName)|\(shoot)|\(project.isWrapped)|\(left)"
        }.joined(separator: ",")
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        switch route {
        case .dashboard:
            DashboardView(projects: projects, open: open, create: createProject)
        case .settings:
            SettingsView()
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

    private var selectedTab: NavTab {
        switch route {
        case .dashboard: .dashboard
        case .projects, .project: .projects
        case .settings: .settings
        }
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

/// The sections in the nav bar.
enum NavTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case projects = "Projects"
    case settings = "Settings"
    var id: String { rawValue }
}

/// A floating rounded bar: logo on the left, sections in the middle,
/// New project and your account on the right.
struct TopBar: View {
    @Environment(AuthService.self) private var auth
    let selected: NavTab
    let select: (NavTab) -> Void
    let onSearch: () -> Void
    let onNewProject: () -> Void

    @Namespace private var tabHighlight

    var body: some View {
        ZStack {
            // The sections sit in the true centre of the bar.
            HStack(spacing: 4) {
                ForEach(NavTab.allCases) { tab in
                    NavTabButton(title: tab.rawValue, isSelected: tab == selected,
                                 namespace: tabHighlight) { select(tab) }
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image("WrapLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 20)
                    Text("wrap")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(.white)
                }
                Spacer()
                CircleIconButton(systemImage: "magnifyingglass", help: "Search projects (⌘F)", action: onSearch)
                    .keyboardShortcut("f", modifiers: .command)
                syncIndicator
                Button("New project", action: onNewProject)
                    .buttonStyle(NavPrimaryButtonStyle())
                    .keyboardShortcut("n", modifiers: .command)
                accountMenu
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 54)
        .frame(width: 700)   // a compact bar in the middle, not edge to edge
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
    }

    /// A small cloud: synced, syncing, or failed (hover for details).
    @ViewBuilder private var syncIndicator: some View {
        switch SyncEngine.shared.status {
        case .idle:
            EmptyView()
        case .syncing:
            ProgressView()
                .controlSize(.small)
                .frame(width: 20)
                .help("Syncing…")
        case .synced(let date):
            Image(systemName: "checkmark.icloud")
                .font(.system(size: 14))
                .foregroundStyle(Color.wrapSecondary)
                .frame(width: 20)
                .help("Synced at \(date.formatted(date: .omitted, time: .shortened))")
        case .failed(let message):
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
                .frame(width: 20)
                .help("Sync failed: \(message)")
        }
    }

    /// A round initial; click for your email, Sync Now and Sign Out.
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
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.1)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var initial: String {
        let source = auth.account.map { $0.name.isEmpty ? $0.email : $0.name } ?? "?"
        return source.first.map { String($0).uppercased() } ?? "?"
    }
}

/// One section in the nav bar: grey text, white when selected or hovered,
/// with a soft pill that slides between sections.
struct NavTabButton: View {
    let title: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected || hovering ? Color.white : Color.white.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.07))
                            .matchedGeometryEffect(id: "selected", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The big white button on the right of the nav bar.
struct NavPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// A round outlined icon button, e.g. Search.
struct CircleIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(hovering ? Color.white : Color.white.opacity(0.7))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.08 : 0.03)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Project.self, Shot.self, WorkspaceItem.self, ShotTemplate.self], inMemory: true)
        .environment(AuthService())
        .preferredColorScheme(.dark)
}
