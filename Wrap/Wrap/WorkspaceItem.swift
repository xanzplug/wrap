import Foundation
import SwiftData

/// One thing a project's workspace opens: an app, a file, a folder or a website.
@Model
final class WorkspaceItem {
    enum Kind: String, CaseIterable {
        case app, file, folder, website

        var label: String {
            switch self {
            case .app: "App"
            case .file: "File"
            case .folder: "Folder"
            case .website: "Website"
            }
        }
    }

    /// Stored as text so the library stays simple to read and migrate.
    var kindRaw: String
    var name: String
    /// A file path on this Mac, or a web address for websites.
    var location: String
    /// Position in the list (0 = opens first).
    var order: Int
    /// Saved window positions (see Save Layout), stored as JSON.
    var layoutData: Data?
    var project: Project?

    /// Stable ID shared with the server, so the same item matches on every Mac.
    var remoteID: UUID = UUID()
    /// The field values last sent to or received from the server.
    /// If `snapshot` differs from this, there are local changes to upload.
    var syncedSnapshot: String = ""

    init(kind: Kind, name: String, location: String, order: Int) {
        self.kindRaw = kind.rawValue
        self.name = name
        self.location = location
        self.order = order
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .file }

    /// The synced fields, joined into one string to spot changes.
    /// Window positions aren't synced; they depend on this Mac's screens.
    var snapshot: String {
        [kindRaw, name, location, String(order),
         project?.remoteID.uuidString ?? ""].joined(separator: "\u{1F}")
    }

    var url: URL? {
        kind == .website ? URL(string: location) : URL(fileURLWithPath: location)
    }

    /// The windows saved by Save Layout, if any.
    var savedWindows: [SavedWindow] {
        get {
            guard let layoutData else { return [] }
            return (try? JSONDecoder().decode([SavedWindow].self, from: layoutData)) ?? []
        }
        set {
            layoutData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    /// True when a saved app, file or folder has been moved or deleted.
    var isMissing: Bool {
        kind != .website && !FileManager.default.fileExists(atPath: location)
    }
}
