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
        [name, clientName, String(isWrapped)].joined(separator: "\u{1F}")
    }

    /// The name to show, even if the user cleared it.
    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled Project" : name
    }
}
