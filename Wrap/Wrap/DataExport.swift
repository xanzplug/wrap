import AppKit
import UniformTypeIdentifiers

enum DataExport {
    struct Backup: Codable {
        var exportedAt: Date
        var account: String
        var projects: [ProjectData]
        var templates: [TemplateData]
    }

    struct ProjectData: Codable {
        var name: String
        var client: String
        var createdAt: Date
        var shootDate: Date?
        var isWrapped: Bool
        var shots: [ShotData]
        var workspace: [WorkspaceData]
    }

    struct ShotData: Codable {
        var title: String
        var isDone: Bool
        var outfit: String
        var location: String
        var notes: String
    }

    struct WorkspaceData: Codable {
        var kind: String
        var name: String
        var location: String
    }

    struct TemplateData: Codable {
        var name: String
        var shots: [String]
    }

    static func run(projects: [Project], templates: [ShotTemplate], account: String) -> String? {
        let backup = Backup(
            exportedAt: .now,
            account: account,
            projects: projects.map { project in
                ProjectData(
                    name: project.name,
                    client: project.clientName,
                    createdAt: project.createdAt,
                    shootDate: project.shootDate,
                    isWrapped: project.isWrapped,
                    shots: project.sortedShots.map {
                        ShotData(title: $0.title, isDone: $0.isDone, outfit: $0.outfit,
                                 location: $0.location, notes: $0.notes)
                    },
                    workspace: project.sortedWorkspaceItems.map {
                        WorkspaceData(kind: $0.kindRaw, name: $0.name, location: $0.location)
                    }
                )
            },
            templates: templates.map { TemplateData(name: $0.name, shots: $0.items.map(\.title)) }
        )

        let panel = NSSavePanel()
        panel.title = "Export My Data"
        panel.nameFieldStringValue = "Wrap backup \(Date.now.formatted(.iso8601.year().month().day())).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(backup).write(to: url)
            return "Saved \(projects.count) project\(projects.count == 1 ? "" : "s") to \(url.lastPathComponent)."
        } catch {
            return "Couldn't save the file: \(error.localizedDescription)"
        }
    }
}
