import SwiftUI
import SwiftData

/// The home page: greeting, shot progress, projects and workspaces.
struct DashboardView: View {
    let projects: [Project]
    let open: (Project) -> Void
    let create: (String) -> Void

    @AppStorage("displayName") private var displayName = WrapUser.defaultName
    @State private var newName = ""
    @State private var showProjects = true
    @State private var showWorkspaces = true
    @State private var editingName = false

    private var active: [Project] { projects.filter { !$0.isWrapped } }
    private var allShots: [Shot] { active.flatMap(\.shots) }
    private var doneShots: Int { allShots.filter(\.isDone).count }
    private var withWorkspace: [Project] { active.filter { !$0.workspaceItems.isEmpty } }
    private var trimmedName: String { newName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                greeting
                    .padding(.top, 40)
                progress
                    .padding(.top, 56)
                HStack(alignment: .top, spacing: 64) {
                    projectsColumn
                    workspacesColumn
                }
                .padding(.top, 64)
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity)
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

            HintText("Across your active projects. Tick shots off on set, and this fills up. Wrapped projects don't count.")
                .frame(maxWidth: 520, alignment: .leading)
        }
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
        guard total > 0 else { return "no shots" }
        return "\(project.shots.filter(\.isDone).count)/\(total) shots"
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
