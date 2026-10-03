import SwiftUI
import SwiftData

/// The Shots tab: a checklist you tick off on the day.
struct ShotsView: View {
    @Environment(\.modelContext) private var context
    let project: Project
    @Query(sort: \ShotTemplate.name) private var templates: [ShotTemplate]

    @State private var newShotTitle = ""
    @State private var savingTemplate = false
    @State private var templateName = ""
    @State private var savedNote: String?
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
            .scrollContentBackground(.hidden)
            .overlay {
                if shots.isEmpty { emptyState }
            }

            HStack {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                TextField("Add a shot, e.g. Low angle, then press Return", text: $newShotTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(addShot)
            }
            .wrapCard(padding: 12)
            .padding(16)
        }
        .background(Color.wrapBackground)
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
        .onChange(of: selectedShotID) { _, newValue in
            if newValue != nil { showDetails = true }
        }
        .alert("Save as template", isPresented: $savingTemplate) {
            TextField("Template name", text: $templateName)
            Button("Save", action: saveTemplate)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves these \(shots.count) shots, with their outfits, locations and notes, so you can reuse them on new projects.")
        }
    }

    // MARK: Templates

    private var templatesMenu: some View {
        Menu {
            if !templates.isEmpty {
                Section("Add shots from") {
                    ForEach(templates) { template in
                        Button("\(template.name) (\(template.items.count))") {
                            template.addShots(to: project, in: context)
                        }
                    }
                }
            }
            Divider()
            Button("Save This List as a Template…") {
                templateName = project.displayName
                savingTemplate = true
            }
            .disabled(shots.isEmpty)
            if !templates.isEmpty {
                Menu("Delete a Template") {
                    ForEach(templates) { template in
                        Button(template.name, role: .destructive) {
                            context.delete(template)
                            try? context.save()
                        }
                    }
                }
            }
        } label: {
            Label(savedNote ?? "Templates", systemImage: "square.stack")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.03)))
                .overlay(Capsule().strokeBorder(Color.wrapBorder))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Shown in place of the empty list: start from a template, or type below.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera")
                .font(.system(size: 26))
                .foregroundStyle(Color.wrapSecondary)
            Text("Start your shot list")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
            if templates.isEmpty {
                HintText("Type your first shot in the box below.")
            } else {
                HintText("Start from a template, or type your first shot below.")
                HStack(spacing: 8) {
                    ForEach(templates.prefix(4)) { template in
                        Button(template.name) {
                            template.addShots(to: project, in: context)
                        }
                        .buttonStyle(.wrapSecondary)
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
    }

    private func saveTemplate() {
        let name = templateName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !shots.isEmpty else { return }
        context.insert(ShotTemplate(name: name, from: project))
        try? context.save()
        savedNote = "Saved"
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            savedNote = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Shot list")
            HStack(alignment: .firstTextBaseline) {
                Heading(shots.isEmpty ? "No shots yet" : "\(doneCount) of \(shots.count) shot")
                Spacer()
                if !shots.isEmpty {
                    Text("\(Int((Double(doneCount) / Double(shots.count) * 100).rounded()))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.wrapSecondary)
                }
                templatesMenu
                Button(showDetails ? "Hide details" : "Details", systemImage: "sidebar.right") {
                    showDetails.toggle()
                }
                .buttonStyle(.wrapSecondary)
            }
            if !shots.isEmpty {
                ThinProgressBar(value: Double(doneCount) / Double(shots.count))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
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
        SyncEngine.shared.recordDeletion(.shots, id: shot.remoteID)
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
