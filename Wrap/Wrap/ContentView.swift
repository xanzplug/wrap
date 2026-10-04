import SwiftUI
import SwiftData

enum Route: Hashable {
    case dashboard
    case projects
    case settings
    case project(PersistentIdentifier)
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var route: Route = .dashboard
    @State private var searchRequest = false
    @State private var navProgress: CGFloat = 0
    @State private var pendingDelete: Project?
    @AppStorage(ShootReminders.enabledKey) private var remindersOn = true

    var body: some View {
        page
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.setNavProgress) { progress in
                guard progress != navProgress else { return }
                withAnimation(.smooth(duration: 0.25)) {
                    navProgress = progress
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
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
                .padding(.top, 38)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    LinearGradient(
                        colors: [Color.wrapBackground, Color.wrapBackground.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 44)
                    .allowsHitTesting(false)
                }
            }
        .background(Color.wrapBackground)
        .overlay {
            ZStack {
                if pendingDelete != nil {
                    Color.black.opacity(0.55)
                        .background(.ultraThinMaterial.opacity(0.4))
                        .ignoresSafeArea()
                        .onTapGesture { closeDeletePopup() }
                        .transition(.opacity)
                }
                if let project = pendingDelete {
                    DeleteProjectPopup(
                        project: project,
                        cancel: closeDeletePopup,
                        confirm: {
                            closeDeletePopup()
                            Task {
                                try? await Task.sleep(for: .milliseconds(220))
                                delete(project)
                            }
                        }
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity).combined(with: .offset(y: 12)))
                }
            }
        }
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
            DashboardView(projects: projects, open: open, create: createProject,
                          openProjectsPage: { route = .projects })
        case .settings:
            SettingsView()
        case .projects:
            ProjectsListView(projects: projects, open: open, create: createProject, delete: askDelete,
                             searchRequest: $searchRequest)
        case .project(let id):
            if let project = projects.first(where: { $0.persistentModelID == id }) {
                ProjectPage(project: project, back: { route = .dashboard }, delete: { askDelete(project) })
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
        let project = Project(name: trimmed)
        context.insert(project)
        try? context.save()
        open(project)
    }

    private func askDelete(_ project: Project) {
        withAnimation(.spring(duration: 0.35, bounce: 0.22)) {
            pendingDelete = project
        }
    }

    private func closeDeletePopup() {
        withAnimation(.easeOut(duration: 0.18)) {
            pendingDelete = nil
        }
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

enum NavTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case projects = "Projects"
    case settings = "Settings"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .projects: "folder"
        case .settings: "gearshape"
        }
    }
}

struct TopBar: View {
    @Environment(AuthService.self) private var auth
    let progress: CGFloat
    let selected: NavTab
    let select: (NavTab) -> Void
    let onSearch: () -> Void
    let onNewProject: () -> Void

    @Namespace private var tabHighlight

    var body: some View {
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
                    NavTabButton(title: tab.rawValue, systemImage: tab.systemImage, isSelected: tab == selected,
                                 namespace: tabHighlight) { select(tab) }
                }
            }
            .fixedSize()

            HStack(spacing: 8) {
                CircleIconButton(systemImage: "magnifyingglass", help: "Search projects (⌘F)", action: onSearch)
                    .keyboardShortcut("f", modifiers: .command)
                Button(action: onNewProject) {
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
        .containerRelativeFrame(.horizontal) { width, _ in
            let full = width - 32
            let small = min(680, full)
            return full + (small - full) * eased
        }
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.85)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.12))
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.08 + 0.04 * eased))
        )
        .shadow(color: .black.opacity(0.2 + 0.35 * eased), radius: 20, y: 8)
    }

    private var labelFold: CGFloat {
        min(max((eased - 0.25) / 0.6, 0), 1)
    }

    private var eased: CGFloat {
        let p = min(max(progress, 0), 1)
        return p * p * (3 - 2 * p)
    }

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

struct NavTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
            }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected || hovering ? Color.white : Color.white.opacity(0.5))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.wrapAccent.opacity(0.16))
                            .overlay(Capsule().strokeBorder(Color.wrapAccent.opacity(0.28)))
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

struct NavPrimaryButtonStyle: ButtonStyle {
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
