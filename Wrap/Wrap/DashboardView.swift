import SwiftUI
import SwiftData

/// The home page: greeting, shot progress, delivery space, projects, workspaces and links out.
struct DashboardView: View {
    let projects: [Project]
    let open: (Project) -> Void
    let create: (String) -> Void

    @AppStorage("displayName") private var displayName = WrapUser.defaultName
    @State private var newName = ""
    @State private var showProjects = true
    @State private var showWorkspaces = true
    @State private var editingName = false
    @State private var showLinks = true
    @State private var showShoots = true

    private var active: [Project] { projects.filter { !$0.isWrapped } }
    private var allShots: [Shot] { active.flatMap(\.shots) }
    private var doneShots: Int { allShots.filter(\.isDone).count }
    private var withWorkspace: [Project] { active.filter { !$0.workspaceItems.isEmpty } }
    private var trimmedName: String { newName.trimmingCharacters(in: .whitespaces) }
    private var upcoming: [Project] {
        projects.filter { $0.upcomingShoot != nil }
            .sorted { $0.upcomingShoot! < $1.upcomingShoot! }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                greeting
                    .padding(.top, 40)
                HStack(alignment: .top, spacing: 64) {
                    progress
                    storage
                }
                .padding(.top, 56)
                upcomingShoots
                    .padding(.top, 64)
                HStack(alignment: .top, spacing: 64) {
                    projectsColumn
                    workspacesColumn
                }
                .padding(.top, 64)
                linksOut
                    .padding(.top, 64)
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity)
        }
        .task {
            await DeliveryService.shared.refresh()
        }
        .alert("Your name", isPresented: $editingName) {
            TextField("Name", text: $displayName)
            Button("Done") {}
        } message: {
            Text("Shown in the greeting on your dashboard.")
        }
    }

    // MARK: Sections

    private var greeting: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Welcome back,")
                    .foregroundStyle(.white)
                Text(displayName)
                    .foregroundStyle(Color.wrapSecondary)
            }
            .font(.system(size: 46, weight: .medium))
            .tracking(-1.4)

            Spacer()

            Menu {
                Button("Change Name…") { editingName = true }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color.wrapSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("Shots on your lists")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(doneShots)")
                    .foregroundStyle(.white)
                Text("/ \(allShots.count) done")
                    .foregroundStyle(Color.wrapSecondary)
            }
            .font(.system(size: 32, weight: .medium))
            .monospacedDigit()

            ThinProgressBar(value: allShots.isEmpty ? 0 : Double(doneShots) / Double(allShots.count))

            HintText("Across your active projects. Tick shots off on set, and this fills up.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Deliveries

    /// Files still on the server: waiting for a client, or just downloaded
    /// and about to be deleted.
    private var linksStillOut: [Delivery] {
        DeliveryService.shared.deliveries.filter(\.isActive)
    }

    private var usedBytes: Int64 {
        linksStillOut.reduce(0) { $0 + $1.sizeBytes }
    }

    private var storage: some View {
        let used = usedBytes
        let limit = DeliveryConfig.maxActiveBytes
        return VStack(alignment: .leading, spacing: 16) {
            Eyebrow("Waiting for clients")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ByteCountFormatter.string(fromByteCount: used, countStyle: .file))
                    .foregroundStyle(.white)
                Text("/ \(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file))")
                    .foregroundStyle(Color.wrapSecondary)
            }
            .font(.system(size: 32, weight: .medium))
            .monospacedDigit()

            ThinProgressBar(value: Double(used) / Double(limit))

            HintText("Files your clients haven't downloaded yet. Once they do, this frees up. Links expire after \(AppSettings.expiryLabel(AppSettings.expiryHours)).")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var linksOut: some View {
        VStack(alignment: .leading, spacing: 18) {
            CollapsibleHeader(title: "Links out", count: linksStillOut.count, isOpen: $showLinks)

            if showLinks {
                if linksStillOut.isEmpty {
                    HintText("No links out. Open a project's Deliveries tab and drop in a finished file to get a link for your client.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(linksStillOut) { delivery in
                            LinkOutRow(delivery: delivery, project: project(for: delivery)) {
                                if let project = project(for: delivery) { open(project) }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Shoots

    private var upcomingShoots: some View {
        VStack(alignment: .leading, spacing: 18) {
            CollapsibleHeader(title: "Upcoming shoots", count: upcoming.count, isOpen: $showShoots)

            if showShoots {
                if upcoming.isEmpty {
                    HintText("No shoots scheduled. Open a project and press Set shoot date. Wrap reminds you the evening before and 2 hours before.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(upcoming) { project in
                            ShootRow(project: project) { open(project) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func project(for delivery: Delivery) -> Project? {
        projects.first { $0.remoteID.uuidString.lowercased() == delivery.projectID }
    }

    private var projectsColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            CollapsibleHeader(title: "Projects", count: active.count, isOpen: $showProjects)

            if showProjects {
                Eyebrow("New project")
                HStack(spacing: 10) {
                    TextField("Client or project name", text: $newName)
                        .textFieldStyle(WrapFieldStyle())
                        .onSubmit(submit)
                    Button("Create project", action: submit)
                        .buttonStyle(.wrapSecondary)
                        .disabled(trimmedName.isEmpty)
                }

                if active.isEmpty {
                    HintText("No projects yet. Make one per shoot or client, like “Acme” or “Wedding film”, then add your shots.")
                } else {
                    Eyebrow("Active")
                        .padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(active) { project in
                            ProjectRow(project: project) { open(project) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var workspacesColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            CollapsibleHeader(title: "Workspaces", count: withWorkspace.count, isOpen: $showWorkspaces)

            if showWorkspaces {
                if withWorkspace.isEmpty {
                    HintText("No workspaces yet. Open a project and add the apps, files and folders you use for it. Then launch it from here in one click.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(withWorkspace) { project in
                            WorkspaceLaunchRow(project: project) { open(project) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        create(trimmedName)
        newName = ""
    }
}

/// One project in a list: name, client, shot count.
struct ProjectRow: View {
    let project: Project
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    if !project.clientName.isEmpty {
                        Text(project.clientName)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.wrapSecondary)
                    }
                }
                Spacer()
                Text(shotSummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.wrapSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.wrapSecondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var shotSummary: String {
        let total = project.shots.count
        let shots = total > 0 ? "\(project.shots.filter(\.isDone).count)/\(total) shots" : "no shots"
        guard let shoot = project.upcomingShoot else { return shots }
        return "\(ShootReminders.relativeDay(shoot)) · \(shots)"
    }
}

/// One scheduled shoot: when, which project, shots left.
struct ShootRow: View {
    let project: Project
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                if let shoot = project.upcomingShoot {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ShootReminders.relativeDay(shoot))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                        Text(shoot.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.wrapSecondary)
                    }
                    .frame(width: 120, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    if !project.clientName.isEmpty {
                        Text(project.clientName)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.wrapSecondary)
                    }
                }
                Spacer()
                Text(shotsLeft)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.wrapSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.wrapSecondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var shotsLeft: String {
        let total = project.shots.count
        guard total > 0 else { return "no shot list yet" }
        let left = project.shots.filter { !$0.isDone }.count
        return left == 0 ? "all \(total) shot" : "\(left) of \(total) to shoot"
    }
}

/// One workspace on the dashboard, with a Launch button.
struct WorkspaceLaunchRow: View {
    let project: Project
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    Text(itemSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wrapSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button("Launch", systemImage: "play.fill") {
                WorkspaceLauncher.launch(project.sortedWorkspaceItems)
            }
            .buttonStyle(.wrapPrimary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.05 : 0)))
        .onHover { hovering = $0 }
    }

    private var itemSummary: String {
        let names = project.sortedWorkspaceItems.prefix(3).map(\.name)
        let extra = project.workspaceItems.count - names.count
        return names.joined(separator: ", ") + (extra > 0 ? " +\(extra)" : "")
    }
}

/// One file still out with a client: name, project, size, time left, Copy Link.
struct LinkOutRow: View {
    let delivery: Delivery
    let project: Project?
    let openProject: () -> Void
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: delivery.status == "downloaded" ? "checkmark.circle.fill" : "paperplane")
                .foregroundStyle(delivery.status == "downloaded" ? Color.white : Color.wrapSecondary)
                .frame(width: 18)

            Button(action: openProject) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(delivery.fileName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(project?.displayName ?? "No project")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wrapSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.wrapSecondary)

            Button(copied ? "Copied" : "Copy Link") {
                DeliveryService.shared.copyLink(delivery)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            .buttonStyle(.wrapSecondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.05 : 0)))
        .onHover { hovering = $0 }
    }

    private var detail: String {
        let size = ByteCountFormatter.string(fromByteCount: delivery.sizeBytes, countStyle: .file)
        if delivery.status == "downloaded" {
            return "\(size) · downloaded"
        }
        guard let expires = delivery.expiresAt else { return size }
        let hours = max(0, Int(expires.timeIntervalSinceNow / 3600))
        return "\(size) · \(hours >= 1 ? "\(hours)h left" : "expiring")"
    }
}

