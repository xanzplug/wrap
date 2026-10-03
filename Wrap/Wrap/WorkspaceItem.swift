import Foundation
import SwiftData

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

    var kindRaw: String
    var name: String
    var location: String
    var order: Int
    var layoutData: Data?
    var project: Project?

    var remoteID: UUID = UUID()
    var syncedSnapshot: String = ""

    init(kind: Kind, name: String, location: String, order: Int) {
        self.kindRaw = kind.rawValue
        self.name = name
        self.location = location
        self.order = order
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .file }

    var snapshot: String {
        [kindRaw, name, location, String(order),
         project?.remoteID.uuidString ?? ""].joined(separator: "\u{1F}")
    }

    var url: URL? {
        kind == .website ? URL(string: location) : URL(fileURLWithPath: location)
    }

    var savedWindows: [SavedWindow] {
        get {
            guard let layoutData else { return [] }
            return (try? JSONDecoder().decode([SavedWindow].self, from: layoutData)) ?? []
        }
        set {
            layoutData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    var isMissing: Bool {
        kind != .website && !FileManager.default.fileExists(atPath: location)
    }
}
