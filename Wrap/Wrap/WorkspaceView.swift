import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @Environment(\.modelContext) private var context
    let project: Project

    @State private var showImporter = false
    @State private var importingApps = true
    @State private var addingWebsite = false
    @State private var websiteText = ""
    @State private var layoutMessage: String?
    @State private var askingForPermission = false

    private var items: [WorkspaceItem] { project.sortedWorkspaceItems }

    var body: some View {
        VStack(spacing: 0) {
            header

            List {
                ForEach(items) { item in
                    WorkspaceRow(item: item)
                        .contextMenu {
                            Button("Open Now") { WorkspaceLauncher.open(item) }
                            if !item.savedWindows.isEmpty {
                                Button("Forget Window Position") { item.savedWindows = [] }
                            }
                            Divider()
                            Button("Remove", role: .destructive) { delete(item) }
                        }
                }
                .onMove(perform: move)
            }
            .reportsScrollForNav()
            .scrollContentBackground(.hidden)
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Empty workspace",
                        systemImage: "macwindow.on.rectangle",
                        description: Text("Add the apps, files and folders you use for this project, or drag them here from Finder.")
                    )
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                urls.forEach(addFile)
                return !urls.isEmpty
            }

            HStack {
                Button("Add App…", systemImage: "app.badge.checkmark") {
                    importingApps = true
                    showImporter = true
                }
                Button("Add File or Folder…", systemImage: "doc.badge.plus") {
                    importingApps = false
                    showImporter = true
                }
                Button("Add Website…", systemImage: "globe") {
                    websiteText = ""
                    addingWebsite = true
                }
                Spacer()
            }
            .buttonStyle(.wrapSecondary)
            .padding(16)
        }
        .background(Color.wrapBackground)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importingApps ? [.application] : [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                urls.forEach(addFile)
            }
        }
        .fileDialogDefaultDirectory(importingApps ? URL(fileURLWithPath: "/Applications") : nil)
        .alert("Add Website", isPresented: $addingWebsite) {
            TextField("e.g. mail.google.com", text: $websiteText)
            Button("Add", action: addWebsite)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Opens in your default browser when the workspace launches.")
        }
        .alert("Allow Wrap to arrange windows", isPresented: $askingForPermission) {
            Button("Open System Settings") { WindowMover.requestPermission() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("To save and restore window positions, turn on Wrap in System Settings > Privacy & Security > Accessibility. Then press Save Layout again.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Heading(items.isEmpty ? "Nothing to open yet" : "\(items.count) item\(items.count == 1 ? "" : "s")")
                    Text(layoutMessage ?? "Opens top to bottom. Arrange your windows, then Save Layout.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wrapSecondary)
                }
                Spacer()
                Button("Save Layout", systemImage: "rectangle.3.group", action: saveLayout)
                    .buttonStyle(.wrapSecondary)
                    .help("Arrange the windows how you like, then press this to remember their places.")
                    .disabled(items.isEmpty)
                Button("Hide") { WorkspaceLauncher.hide(items) }
                    .buttonStyle(.wrapSecondary)
                    .disabled(items.isEmpty)
                Button("Launch Workspace", systemImage: "play.fill") { WorkspaceLauncher.launch(items) }
                    .buttonStyle(.wrapPrimary)
                    .disabled(items.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func saveLayout() {
        guard WindowMover.hasPermission else {
            askingForPermission = true
            return
        }
        let saved = WorkspaceLauncher.saveLayout(items)
        try? context.save()
        let placeable = items.filter { $0.kind != .website }.count
        if saved == 0 {
            layoutMessage = "No open windows found. Launch the workspace and arrange it first."
        } else {
            layoutMessage = "Saved window positions for \(saved) of \(placeable) items."
        }
    }

    private var nextOrder: Int { (items.map(\.order).max() ?? -1) + 1 }

    private func addFile(_ url: URL) {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let kind: WorkspaceItem.Kind =
            url.pathExtension == "app" ? .app : (isDirectory ? .folder : .file)
        let name = FileManager.default.displayName(atPath: url.path)
        insert(WorkspaceItem(kind: kind, name: name, location: url.path, order: nextOrder))
    }

    private func addWebsite() {
        var text = websiteText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text) else { return }
        insert(WorkspaceItem(kind: .website, name: url.host() ?? text, location: text, order: nextOrder))
    }

    private func insert(_ item: WorkspaceItem) {
        context.insert(item)
        item.project = project
        try? context.save()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in reordered.enumerated() {
            item.order = index
        }
    }

    private func delete(_ item: WorkspaceItem) {
        SyncEngine.shared.recordDeletion(.workspaceItems, id: item.remoteID)
        context.delete(item)
        try? context.save()
    }
}

struct WorkspaceRow: View {
    let item: WorkspaceItem

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.isMissing {
                Label("Missing", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let base = item.kind == .website ? item.location : item.kind.label
        return item.savedWindows.isEmpty ? base : base + " · position saved"
    }

    @ViewBuilder private var icon: some View {
        if item.kind == .website {
            Image(systemName: "globe")
                .font(.title3)
                .foregroundStyle(.secondary)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.location))
                .resizable()
        }
    }
}
