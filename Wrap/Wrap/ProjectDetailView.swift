import SwiftUI
import SwiftData

/// The right side of the window: the selected project, in tabs.
struct ProjectDetailView: View {
    @Bindable var project: Project

    @State private var tab: ProjectTab = .shots

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(ProjectTab.allCases) { item in
                    TabPill(title: item.title, systemImage: item.systemImage, isSelected: tab == item) {
                        withAnimation(.easeOut(duration: 0.15)) { tab = item }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 14)

            Rectangle().fill(Color.wrapBorder).frame(height: 1)

            Group {
                switch tab {
                case .shots: ShotsView(project: project)
                case .workspace: WorkspaceView(project: project)
                case .deliveries: DeliveriesView(project: project)
                case .overview: overview
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.wrapBackground)
    }

    private var overview: some View {
        Form {
            Section("Project") {
                TextField("Name", text: $project.name)
                TextField("Client", text: $project.clientName, prompt: Text("Optional"))
                Toggle("Wrapped", isOn: $project.isWrapped)
            }
            Section("Shoot day") {
                ShootDateEditor(project: project)
            }

        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.wrapBackground)
    }
}

/// The sections of a project page.
enum ProjectTab: String, CaseIterable, Identifiable {
    case shots, workspace, deliveries, overview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shots: "Shots"
        case .workspace: "Workspace"
        case .deliveries: "Deliveries"
        case .overview: "Overview"
        }
    }

    var systemImage: String {
        switch self {
        case .shots: "checklist"
        case .workspace: "macwindow.on.rectangle"
        case .deliveries: "paperplane"
        case .overview: "info.circle"
        }
    }
}

/// A rounded tab button: white when selected, outlined when not.
struct TabPill: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Color.black : (hovering ? Color.white : Color.wrapSecondary))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Color.white : Color.white.opacity(hovering ? 0.06 : 0.02))
                )
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : Color.wrapBorder)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
