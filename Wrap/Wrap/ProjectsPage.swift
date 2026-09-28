import SwiftUI
import SwiftData

/// The Projects tab: every project, active and wrapped.
struct ProjectsListView: View {
    let projects: [Project]
    let open: (Project) -> Void
    let create: (String) -> Void
    let delete: (Project) -> Void

    @State private var newName = ""
    @State private var showActive = true
    @State private var showWrapped = true

    private var active: [Project] { projects.filter { !$0.isWrapped } }
    private var wrapped: [Project] { projects.filter { $0.isWrapped } }
    private var trimmedName: String { newName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Heading("All projects")
                    .padding(.top, 24)
                HStack(spacing: 10) {
                    TextField("Client or project name", text: $newName)
                        .textFieldStyle(WrapFieldStyle())
                        .onSubmit(submit)
                    Button("Create project", action: submit)
                        .buttonStyle(.wrapSecondary)
                        .disabled(trimmedName.isEmpty)
                }
                .frame(maxWidth: 560)
                .padding(.bottom, 24)

                CollapsibleHeader(title: "Active", count: active.count, isOpen: $showActive)
                if showActive {
                    if active.isEmpty {
                        HintText("Nothing active. Create a project above.")
                    } else {
                        rows(active)
                    }
                }

                CollapsibleHeader(title: "Wrapped", count: wrapped.count, isOpen: $showWrapped)
                    .padding(.top, 24)
                if showWrapped {
                    if wrapped.isEmpty {
                        HintText("Finished projects land here when you mark them as wrapped.")
                    } else {
                        rows(wrapped)
                    }
                }
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity)
        }
    }

    private func rows(_ list: [Project]) -> some View {
        VStack(spacing: 0) {
            ForEach(list) { project in
                ProjectRow(project: project) { open(project) }
                    .contextMenu {
                        Button(project.isWrapped ? "Move to Active" : "Mark as Wrapped") {
                            project.isWrapped.toggle()
                        }
                        Divider()
                        Button("Delete", role: .destructive) { delete(project) }
                    }
            }
        }
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        create(trimmedName)
        newName = ""
    }
}

/// One project, full page: header with actions, then its tabs.
struct ProjectPage: View {
    @Bindable var project: Project
    let back: () -> Void
    let delete: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: back) {
                        Label("Dashboard", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.wrapSecondary)

                    Text(project.displayName)
                        .font(.system(size: 34, weight: .medium))
                        .tracking(-1)
                        .foregroundStyle(.white)
                    Text(project.clientName.isEmpty ? "No client yet · add one in Overview" : project.clientName)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.wrapSecondary)
                }
                Spacer()
                Button(project.isWrapped ? "Move to active" : "Mark as wrapped") {
                    project.isWrapped.toggle()
                }
                .buttonStyle(.wrapSecondary)
                Button("Delete") { confirmingDelete = true }
                    .buttonStyle(.wrapSecondary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 16)

            ProjectDetailView(project: project)
        }
        .confirmationDialog("Delete \(project.displayName)?", isPresented: $confirmingDelete) {
            Button("Delete Project", role: .destructive, action: delete)
        } message: {
            Text("Its shots and workspace list are deleted too. Your files stay where they are.")
        }
    }
}
