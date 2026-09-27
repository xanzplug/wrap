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

    init(title: String, order: Int) {
        self.title = title
        self.isDone = false
        self.order = order
        self.outfit = ""
        self.location = ""
        self.notes = ""
    }
}
