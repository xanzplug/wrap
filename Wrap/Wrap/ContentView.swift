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
    /// 0 at the top of a page, 1 once scrolled down: the nav bar follows it smoothly.
    @State private var navProgress: CGFloat = 0
    @AppStorage(ShootReminders.enabledKey) private var remindersOn = true

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                progress: navProgress,
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
                .environment(\.setNavProgress) { progress in
                    guard progress != navProgress else { return }
                    // Every change glides a little, so mouse-wheel steps blend into
                    // one continuous motion. A bigger jump (like a new page) glides longer.
                    let jump = abs(progress - navProgress)
                    withAnimation(.smooth(duration: jump > 0.3 ? 0.4 : 0.22)) {
                        navProgress = progress
                    }
                }
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
    /// 0 = full width (top of the page), 1 = small centered pill (scrolled down).
    let progress: CGFloat
    let selected: NavTab
    let select: (NavTab) -> Void
    let onSearch: () -> Void
    let onNewProject: () -> Void

    @Namespace private var tabHighlight

    var body: some View {
        // Left and right get equal space, so the sections stay centred
        // and can never slide under the buttons.
        HStack(spacing: 12) {
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
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(NavTab.allCases) { tab in
                    NavTabButton(title: tab.rawValue, isSelected: tab == selected,
                                 namespace: tabHighlight) { select(tab) }
                }
            }
            .fixedSize()

            HStack(spacing: 8) {
                CircleIconButton(systemImage: "magnifyingglass", help: "Search projects (⌘F)", action: onSearch)
                    .keyboardShortcut("f", modifiers: .command)
                Button(action: onNewProject) {
                    // The words fold away as the bar shrinks, leaving a round +.
                    HStack(spacing: 6 * (1 - labelFold)) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("New project")
                            .fixedSize()
                            .frame(width: 84 * (1 - labelFold), alignment: .leading)
                            .clipped()
                            .opacity(1 - labelFold)
                    }
                }
                .buttonStyle(NavPrimaryButtonStyle(fold: labelFold))
                .keyboardShortcut("n", modifiers: .command)
                .help("New project (⌘N)")
                accountMenu
            }
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 54)
        // Full width at the top of a page, easing into a small pill as you scroll.
        .containerRelativeFrame(.horizontal) { width, _ in
            let full = width - 32
            let small = min(600, full)
            return full + (small - full) * eased
        }
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.035 + 0.03 * eased))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.08 + 0.04 * eased))
        )
        .shadow(color: .black.opacity(0.2 + 0.35 * eased), radius: 20, y: 8)
    }

    /// How far "New project" has folded into a round + (0 = full words).
    private var labelFold: CGFloat {
        min(max((eased - 0.25) / 0.6, 0), 1)
    }

    /// Smoothstep: starts and ends gently, so the change feels soft.
    private var eased: CGFloat {
        let p = min(max(progress, 0), 1)
        return p * p * (3 - 2 * p)
    }

    /// One line for the account menu: synced, syncing, or failed.
    private var syncStatusText: String {
        switch SyncEngine.shared.status {
        case .idle: "Sync starting…"
        case .syncing: "Syncing…"
        case .synced(let date): "Synced at \(date.formatted(date: .omitted, time: .shortened))"
        case .failed(let message): "Sync failed: \(message)"
        }
    }

    private var syncFailed: Bool {
        if case .failed = SyncEngine.shared.status { return true }
        return false
    }

    /// A round initial (with an orange dot if sync failed); click for your
    /// email, sync status, Sync Now and Sign Out.
    private var accountMenu: some View {
        Menu {
            if let account = auth.account {
                Text(account.name.isEmpty ? account.email : "\(account.name) · \(account.email)")
            }
            Text(syncStatusText)
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
                .overlay(alignment: .topTrailing) {
                    if syncFailed {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(Color.wrapBackground, lineWidth: 2))
                            .offset(x: 1, y: -1)
                    }
                }
                .help(syncStatusText)
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
    /// 0 = "＋ New project" pill, 1 = a round + button.
    var fold: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16 - 5.5 * fold)
            .frame(height: 34 + 4 * (1 - fold))
            .frame(minWidth: 34)
            .background(
                RoundedRectangle(cornerRadius: 13 + 4 * fold, style: .continuous)
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
