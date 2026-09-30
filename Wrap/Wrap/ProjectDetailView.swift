import SwiftUI
import SwiftData

/// The right side of the window: the selected project, in tabs.
struct ProjectDetailView: View {
    @Bindable var project: Project

    var body: some View {
        TabView {
            Tab("Shots", systemImage: "checklist") {
                ShotsView(project: project)
            }
            Tab("Workspace", systemImage: "macwindow.on.rectangle") {
                WorkspaceView(project: project)
            }
            Tab("Deliveries", systemImage: "paperplane") {
                DeliveriesView(project: project)
            }
            Tab("Overview", systemImage: "info.circle") {
                overview
            }
        }
        .navigationTitle(project.displayName)
    }

    private var overview: some View {
        Form {
            Section("Project") {
                TextField("Name", text: $project.name)
                TextField("Client", text: $project.clientName, prompt: Text("Optional"))
                Toggle("Wrapped", isOn: $project.isWrapped)
            }

        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.wrapBackground)
    }
}
