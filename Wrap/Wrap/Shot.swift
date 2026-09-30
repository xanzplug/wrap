import Foundation
import SwiftData

/// One shot on a project's shot list, e.g. "Low angle".
@Model
final class Shot {
    var title: String
    var isDone: Bool
    /// Position in the list (0 = first).
    var order: Int
    var outfit: String
    var location: String
    var notes: String
    /// Stored as a separate file next to the library, so big images stay fast.
    @Attribute(.externalStorage) var referenceImage: Data?
    var project: Project?

    /// Stable ID shared with the server, so the same item matches on every Mac.
    var remoteID: UUID = UUID()
    /// The field values last sent to or received from the server.
    /// If `snapshot` differs from this, there are local changes to upload.
    var syncedSnapshot: String = ""

    init(title: String, order: Int) {
        self.title = title
        self.isDone = false
        self.order = order
        self.outfit = ""
        self.location = ""
        self.notes = ""
    }

    /// The synced fields, joined into one string to spot changes.
    /// Reference images aren't synced yet; they stay on this Mac.
    var snapshot: String {
        [title, String(isDone), String(order), outfit, location, notes,
         project?.remoteID.uuidString ?? ""].joined(separator: "\u{1F}")
    }
}
