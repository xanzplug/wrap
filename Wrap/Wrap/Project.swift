import Foundation
import SwiftData

@Model
final class Project {
    var name: String
    var clientName: String
    var createdAt: Date
    var isWrapped: Bool
    var shootDate: Date? = nil

    var remoteID: UUID = UUID()
    var syncedSnapshot: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Shot.project)
    var shots: [Shot] = []

    @Relationship(deleteRule: .cascade, inverse: \WorkspaceItem.project)
    var workspaceItems: [WorkspaceItem] = []

    init(name: String, clientName: String = "", createdAt: Date = .now, isWrapped: Bool = false) {
        self.name = name
        self.clientName = clientName
        self.createdAt = createdAt
        self.isWrapped = isWrapped
    }

    var sortedShots: [Shot] {
        shots.sorted { $0.order < $1.order }
    }

    var sortedWorkspaceItems: [WorkspaceItem] {
        workspaceItems.sorted { $0.order < $1.order }
    }

    var snapshot: String {
        Project.snapshot(name: name, client: clientName, wrapped: isWrapped, shootDate: shootDate)
    }

    static func snapshot(name: String, client: String, wrapped: Bool, shootDate: Date?) -> String {
        let shoot = shootDate.map { String(Int($0.timeIntervalSince1970)) } ?? ""
        return [name, client, String(wrapped), shoot].joined(separator: "\u{1F}")
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(q)
            || clientName.localizedCaseInsensitiveContains(q)
            || shots.contains { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var upcomingShoot: Date? {
        guard let shootDate, !isWrapped,
              shootDate >= Calendar.current.startOfDay(for: .now) else { return nil }
        return shootDate
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled Project" : name
    }
}
