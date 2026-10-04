import SwiftUI
import SwiftData

struct DashboardView: View {
    let projects: [Project]
    let open: (Project) -> Void
    let create: (String) -> Void
    var openProjectsPage: () -> Void = {}

    @AppStorage("displayName") private var displayName = WrapUser.defaultName
    @State private var editingName = false
    @State private var scrollOffset: CGFloat = 0

    private var active: [Project] { projects.filter { !$0.isWrapped } }
    private var allShots: [Shot] { active.flatMap(\.shots) }
    private var doneShots: Int { allShots.filter(\.isDone).count }
    private var withWorkspace: [Project] { active.filter { !$0.workspaceItems.isEmpty } }
    private var upcoming: [Project] {
        projects.filter { $0.upcomingShoot != nil }
            .sorted { $0.upcomingShoot! < $1.upcomingShoot! }
    }
    private var linksStillOut: [Delivery] {
        DeliveryService.shared.deliveries.filter(\.isActive)
    }
    private var usedBytes: Int64 {
        linksStillOut.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                    .padding(.top, 28)
                stats

                if !upcoming.isEmpty {
                    section("Upcoming shoots", count: upcoming.count) {
                        VStack(spacing: 0) {
                            ForEach(upcoming) { project in
                                ShootRow(project: project) { open(project) }
                            }
                        }
                    }
                }

                section("Projects", count: active.count, actionTitle: "View all", action: openProjectsPage) {
                    if active.isEmpty {
                        Text("No active projects.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.wrapSecondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                            ForEach(active.prefix(9)) { project in
                                ProjectCard(project: project) { open(project) }
                                    .projectMenu(project)
                            }
                        }
                    }
                }

                if !withWorkspace.isEmpty {
                    section("Workspaces", count: withWorkspace.count) {
                        VStack(spacing: 0) {
                            ForEach(withWorkspace) { project in
                                WorkspaceLaunchRow(project: project) { open(project) }
                            }
                        }
                    }
                }

                if !linksStillOut.isEmpty {
                    section("Links out", count: linksStillOut.count) {
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
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) {
            HeroGlow()
                .opacity(glowOpacity * 0.6)
                .offset(y: -min(scrollOffset, 400) * 0.35)
                .ignoresSafeArea(edges: .top)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, offset in
            scrollOffset = offset
        }
        .reportsScrollForNav()
        .task {
            await DeliveryService.shared.refresh()
        }
        .alert("Your name", isPresented: $editingName) {
            TextField("Name", text: $displayName)
            Button("Done") {}
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.wrapSecondary)
                Text("\(greetingWord), \(displayName)")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(.white)
            }
            .contextMenu {
                Button("Change Name…") { editingName = true }
            }
            Spacer()
        }
    }

    private var greetingWord: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var glowOpacity: Double {
        let t = min(max(scrollOffset / 380, 0), 1)
        return 1 - t * t * (3 - 2 * t)
    }

    // MARK: Stats

    private var stats: some View {
        HStack(spacing: 0) {
            StatTile(label: "Shots",
                     value: "\(doneShots)/\(allShots.count)",
                     detail: allShots.isEmpty ? nil : "\(allShots.count - doneShots) to go",
                     progress: allShots.isEmpty ? nil : Double(doneShots) / Double(allShots.count))
            divider
            StatTile(label: "Next shoot",
                     value: upcoming.first?.upcomingShoot.map(ShootReminders.relativeDay) ?? "—",
                     detail: upcoming.first?.displayName)
            divider
            StatTile(label: "Waiting for clients",
                     value: ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file),
                     detail: "of \(ByteCountFormatter.string(fromByteCount: DeliveryConfig.maxActiveBytes, countStyle: .file))",
                     progress: Double(usedBytes) / Double(DeliveryConfig.maxActiveBytes))
            divider
            StatTile(label: "Links out", value: "\(linksStillOut.count)",
                     detail: "expire after \(AppSettings.expiryLabel(AppSettings.expiryHours))")
        }
        .fixedSize(horizontal: false, vertical: true)
        .wrapCard(padding: 0)
    }

    private var divider: some View {
        Rectangle().fill(Color.wrapBorder).frame(width: 1)
    }

    // MARK: Sections

    private func section<Content: View>(
        _ title: String, count: Int,
        actionTitle: String? = nil, action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(count)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.wrapSecondary)
                Spacer()
                if let actionTitle, let action {
                    TextLinkButton(title: actionTitle, action: action)
                }
            }
            content()
        }
    }

    private func project(for delivery: Delivery) -> Project? {
        projects.first { $0.remoteID.uuidString.lowercased() == delivery.projectID }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var detail: String? = nil
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.wrapSecondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
            if let progress {
                ThinProgressBar(value: progress)
                    .padding(.top, 2)
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.wrapSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
    }
}

struct TextLinkButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Color.white : Color.wrapSecondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ProjectCard: View {
    let project: Project
    let action: () -> Void
    @State private var hovering = false

    private var shots: [Shot] { project.sortedShots }
    private var done: Int { shots.filter(\.isDone).count }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                thumbnails
                    .frame(height: 104)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(project.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let shoot = project.upcomingShoot {
                            Text(ShootReminders.relativeDay(shoot))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.wrapAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.wrapAccent.opacity(0.14)))
                        }
                    }
                    Text(project.clientName.isEmpty ? "No client" : project.clientName)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wrapSecondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if shots.isEmpty {
                            Text("No shots")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.wrapSecondary)
                        } else {
                            ThinProgressBar(value: Double(done) / Double(shots.count))
                            Text("\(done)/\(shots.count)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.wrapSecondary)
                        }
                    }
                    .frame(height: 14)
                    .padding(.top, 4)
                }
                .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.wrapCard))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(hovering ? Color.wrapAccent.opacity(0.45) : Color.wrapBorder)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    @ViewBuilder private var thumbnails: some View {
        let images = Array(shots.compactMap(\.referenceImage).prefix(3).compactMap { NSImage(data: $0) })
        if images.isEmpty {
            ZStack {
                LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(initials)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.22))
            }
        } else {
            HStack(spacing: 2) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                }
            }
        }
    }

    private var initials: String {
        let words = project.displayName.split(separator: " ").prefix(2)
        return words.compactMap(\.first).map { String($0).uppercased() }.joined()
    }
}

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
            .rowHover(hovering)
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
            .rowHover(hovering)
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
        .rowHover(hovering)
        .onHover { hovering = $0 }
    }

    private var itemSummary: String {
        let names = project.sortedWorkspaceItems.prefix(3).map(\.name)
        let extra = project.workspaceItems.count - names.count
        return names.joined(separator: ", ") + (extra > 0 ? " +\(extra)" : "")
    }
}

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
        .rowHover(hovering)
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
