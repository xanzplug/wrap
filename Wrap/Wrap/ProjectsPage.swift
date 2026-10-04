import SwiftUI
import SwiftData

struct ProjectsListView: View {
    let projects: [Project]
    let open: (Project) -> Void
    let create: (String) -> Void
    let delete: (Project) -> Void
    @Binding var searchRequest: Bool

    @State private var newName = ""
    @State private var showActive = true
    @State private var showWrapped = true
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var found: [Project] { projects.filter { $0.matches(query) } }
    private var active: [Project] { found.filter { !$0.isWrapped } }
    private var wrapped: [Project] { found.filter { $0.isWrapped } }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var trimmedName: String { newName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    Heading("All projects")
                    Spacer()
                    searchField
                }
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

                if isSearching && found.isEmpty {
                    HintText("No results for “\(query)”.")
                        .padding(.bottom, 12)
                }

                CollapsibleHeader(title: "Active", count: active.count, isOpen: $showActive)
                if showActive {
                    if active.isEmpty {
                        HintText(isSearching ? "No matches." : "None.")
                    } else {
                        rows(active)
                    }
                }

                CollapsibleHeader(title: "Wrapped", count: wrapped.count, isOpen: $showWrapped)
                    .padding(.top, 24)
                if showWrapped {
                    if wrapped.isEmpty {
                        HintText(isSearching ? "No matches." : "None.")
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
        .reportsScrollForNav()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.wrapSecondary)
            TextField("Search projects, clients, shots", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.wrapSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: 300)
        .background(Capsule().fill(Color.white.opacity(0.03)))
        .overlay(Capsule().strokeBorder(searchFocused ? Color.white.opacity(0.3) : Color.wrapBorder))
        .onChange(of: searchRequest, initial: true) { _, requested in
            guard requested else { return }
            searchFocused = true
            searchRequest = false
        }
    }

    private func rows(_ list: [Project]) -> some View {
        VStack(spacing: 0) {
            ForEach(list) { project in
                ProjectRow(project: project) { open(project) }
                    .projectMenu(project, delete: { delete(project) })
            }
        }
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        create(trimmedName)
        newName = ""
    }
}

struct ProjectPage: View {
    @Bindable var project: Project
    let back: () -> Void
    let delete: () -> Void
    @State private var confirmingDelete = false
    @State private var pickingShootDate = false

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

                    InlineTextField(text: $project.name, placeholder: "Untitled Project",
                                    font: .system(size: 30, weight: .semibold), color: .white,
                                    autoFocus: project.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    HStack(spacing: 6) {
                        InlineTextField(text: $project.clientName, placeholder: "Add client",
                                        font: .system(size: 13), color: Color.wrapSecondary)
                            .fixedSize()
                        if let shoot = project.upcomingShoot {
                            Text("· Shoot \(ShootReminders.relativeDay(shoot)), \(shoot.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.wrapSecondary)
                        }
                    }
                }
                Spacer()
                Button(shootButtonTitle, systemImage: "calendar") {
                    pickingShootDate = true
                }
                .buttonStyle(.wrapSecondary)
                .popover(isPresented: $pickingShootDate, arrowEdge: .bottom) {
                    ShootDateEditor(project: project)
                        .padding(18)
                        .frame(width: 300)
                }
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

    private var shootButtonTitle: String {
        guard let date = project.shootDate else { return "Set shoot date" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}

struct ShootDateEditor: View {
    @Bindable var project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Shoot is scheduled", isOn: scheduled)
                .toggleStyle(.switch)
            if project.shootDate != nil {
                DatePicker("Date", selection: date, displayedComponents: .date)
                DatePicker("Time", selection: date, displayedComponents: .hourAndMinute)
            }
        }
    }

    private var scheduled: Binding<Bool> {
        Binding(
            get: { project.shootDate != nil },
            set: { on in project.shootDate = on ? ShootDateEditor.defaultDate : nil }
        )
    }

    private var date: Binding<Date> {
        Binding(
            get: { project.shootDate ?? ShootDateEditor.defaultDate },
            set: { project.shootDate = ShootDateEditor.wholeMinute($0) }
        )
    }

    static var defaultDate: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    static func wholeMinute(_ date: Date) -> Date {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return Calendar.current.date(from: parts) ?? date
    }
}

struct InlineTextField: View {
    @Binding var text: String
    let placeholder: String
    let font: Font
    let color: Color
    var autoFocus = false
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(color)
            .focused($focused)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(focused ? 0.06 : (hovering ? 0.04 : 0)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(focused ? Color.wrapAccent.opacity(0.5) : Color.clear)
            )
            .padding(.horizontal, -6)
            .onHover { hovering = $0 }
            .onSubmit { focused = false }
            .help("Click to edit")
            .task {
                guard autoFocus else { return }
                try? await Task.sleep(for: .milliseconds(150))
                focused = true
            }
    }
}

extension View {
    func projectMenu(_ project: Project, delete: (() -> Void)? = nil) -> some View {
        modifier(ProjectMenu(project: project, delete: delete))
    }
}

private struct ProjectMenu: ViewModifier {
    @Bindable var project: Project
    let delete: (() -> Void)?
    @State private var renaming = false
    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Rename…") {
                    draft = project.name
                    renaming = true
                }
                Button(project.isWrapped ? "Move to Active" : "Mark as Wrapped") {
                    project.isWrapped.toggle()
                }
                if let delete {
                    Divider()
                    Button("Delete", role: .destructive, action: delete)
                }
            }
            .alert("Rename project", isPresented: $renaming) {
                TextField("Name", text: $draft)
                Button("Rename") {
                    project.name = draft.trimmingCharacters(in: .whitespaces)
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}
