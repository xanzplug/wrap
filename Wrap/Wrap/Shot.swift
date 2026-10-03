import Foundation
import SwiftData

@Model
final class Shot {
    var title: String
    var isDone: Bool
    var order: Int
    var outfit: String
    var location: String
    var notes: String
    @Attribute(.externalStorage) var referenceImage: Data?
    var project: Project?

    var remoteID: UUID = UUID()
    var syncedSnapshot: String = ""

    init(title: String, order: Int) {
        self.title = title
        self.isDone = false
        self.order = order
        self.outfit = ""
        self.location = ""
        self.notes = ""
    }

    var snapshot: String {
        [title, String(isDone), String(order), outfit, location, notes,
         project?.remoteID.uuidString ?? ""].joined(separator: "\u{1F}")
    }
}
