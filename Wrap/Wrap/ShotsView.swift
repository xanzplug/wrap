import SwiftUI
import SwiftData

/// The Shots tab: a checklist you tick off on the day.
struct ShotsView: View {
    @Environment(\.modelContext) private var context
    let project: Project

    @State private var newShotTitle = ""
    @State private var selectedShotID: PersistentIdentifier?
    @State private var showDetails = false

    private var shots: [Shot] { project.sortedShots }
    private var doneCount: Int { shots.filter(\.isDone).count }
    private var selectedShot: Shot? {
        shots.first { $0.persistentModelID == selectedShotID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            List(selection: $selectedShotID) {
                ForEach(shots) { shot in
                    ShotRow(shot: shot)
                        .tag(shot.persistentModelID)
                        .contextMenu {
                            Button("Delete", role: .destructive) { delete(shot) }
                        }
                }
                .onMove(perform: move)
            }
            .onDeleteCommand {
                if let shot = selectedShot { delete(shot) }
            }

            Divider()
            HStack {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                TextField("Add a shot, e.g. Low angle, then press Return", text: $newShotTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(addShot)
            }
            .padding(12)
        }
        .inspector(isPresented: $showDetails) {
            if let shot = selectedShot {
                ShotDetailView(shot: shot)
            } else {
                ContentUnavailableView(
                    "No shot selected",
                    systemImage: "camera",
                    description: Text("Click a shot to add a reference, outfit, location and notes.")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Shot Details", systemImage: "sidebar.right") {
                    showDetails.toggle()
                }
            }
        }
        .onChange(of: selectedShotID) { _, newValue in
            if newValue != nil { showDetails = true }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(shots.isEmpty ? "No shots yet" : "\(doneCount) of \(shots.count) shot")
                .font(.headline)
            if !shots.isEmpty {
                ProgressView(value: Double(doneCount), total: Double(shots.count))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addShot() {
        let title = newShotTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let nextOrder = (shots.map(\.order).max() ?? -1) + 1
        let shot = Shot(title: title, order: nextOrder)
        context.insert(shot)
        shot.project = project
        try? context.save()
        newShotTitle = ""
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = shots
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, shot) in reordered.enumerated() {
            shot.order = index
        }
    }

    private func delete(_ shot: Shot) {
        if shot.persistentModelID == selectedShotID { selectedShotID = nil }
        context.delete(shot)
        try? context.save()
    }
}

/// One line in the shot list: checkbox, thumbnail, name, location.
struct ShotRow: View {
    @Bindable var shot: Shot

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Done", isOn: $shot.isDone)
                .toggleStyle(.checkbox)
                .labelsHidden()

            if let data = shot.referenceImage, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text(shot.title)
                .strikethrough(shot.isDone)
                .foregroundStyle(shot.isDone ? .secondary : .primary)

            Spacer()

            if !shot.location.isEmpty {
                Text(shot.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
