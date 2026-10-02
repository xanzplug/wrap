import Foundation
import SwiftData

/// One creative project, e.g. "ME, MYSELF & I".
/// Saved automatically in Wrap's local library on this Mac.
@Model
final class Project {
    var name: String
    var clientName: String
    var createdAt: Date
    var isWrapped: Bool
    /// When the shoot happens, if it's been scheduled. Wrap reminds you before it.
    var shootDate: Date? = nil

    /// Stable ID shared with the server, so the same item matches on every Mac.
    var remoteID: UUID = UUID()
    /// The field values last sent to or received from the server.
    /// If `snapshot` differs from this, there are local changes to upload.
    var syncedSnapshot: String = ""

    /// Deleting a project also deletes its shots.
    @Relationship(deleteRule: .cascade, inverse: \Shot.project)
    var shots: [Shot] = []

    /// Deleting a project also deletes its workspace list (not the files themselves).
    @Relationship(deleteRule: .cascade, inverse: \WorkspaceItem.project)
    var workspaceItems: [WorkspaceItem] = []

    init(name: String, clientName: String = "", createdAt: Date = .now, isWrapped: Bool = false) {
        self.name = name
        self.clientName = clientName
        self.createdAt = createdAt
        self.isWrapped = isWrapped
    }

    /// Shots in list order.
    var sortedShots: [Shot] {
        shots.sorted { $0.order < $1.order }
    }

    /// Workspace items in the order they open.
    var sortedWorkspaceItems: [WorkspaceItem] {
        workspaceItems.sorted { $0.order < $1.order }
    }

    /// The synced fields, joined into one string to spot changes.
    var snapshot: String {
        Project.snapshot(name: name, client: clientName, wrapped: isWrapped, shootDate: shootDate)
    }

    static func snapshot(name: String, client: String, wrapped: Bool, shootDate: Date?) -> String {
        let shoot = shootDate.map { String(Int($0.timeIntervalSince1970)) } ?? ""
        return [name, client, String(wrapped), shoot].joined(separator: "\u{1F}")
    }

    /// Does this project match a search? Checks the name, client and shot titles.
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(q)
            || clientName.localizedCaseInsensitiveContains(q)
            || shots.contains { $0.title.localizedCaseInsensitiveContains(q) }
    }

    /// The shoot date if it's today or later.
    var upcomingShoot: Date? {
        guard let shootDate, !isWrapped,
              shootDate >= Calendar.current.startOfDay(for: .now) else { return nil }
        return shootDate
    }

    /// The name to show, even if the user cleared it.
    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled Project" : name
    }
}
