import Foundation
import SwiftData

@Model
final class ShotTemplate {
    var name: String
    var createdAt: Date
    var shotsJSON: String

    struct Item: Codable {
        var title: String
        var outfit: String = ""
        var location: String = ""
        var notes: String = ""
    }

    init(name: String, items: [Item]) {
        self.name = name
        self.createdAt = .now
        self.shotsJSON = ShotTemplate.encode(items)
    }

    var items: [Item] {
        guard let data = shotsJSON.data(using: .utf8),
              let items = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        return items
    }

    convenience init(name: String, from project: Project) {
        self.init(name: name, items: project.sortedShots.map {
            Item(title: $0.title, outfit: $0.outfit, location: $0.location, notes: $0.notes)
        })
    }

    func addShots(to project: Project, in context: ModelContext) {
        var order = (project.shots.map(\.order).max() ?? -1) + 1
        for item in items {
            let shot = Shot(title: item.title, order: order)
            shot.outfit = item.outfit
            shot.location = item.location
            shot.notes = item.notes
            context.insert(shot)
            shot.project = project
            order += 1
        }
        try? context.save()
    }

    private static func encode(_ items: [Item]) -> String {
        guard let data = try? JSONEncoder().encode(items) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func makeStarters() -> [ShotTemplate] {
        [
            ShotTemplate(name: "Portrait session", items: [
                "Full body", "Waist up", "Close-up", "Profile", "Detail: hands",
                "Candid / walking", "Low angle", "Over the shoulder",
            ].map { Item(title: $0) }),
            ShotTemplate(name: "Music video", items: [
                "Wide performance", "Medium performance", "Close-up performance",
                "Establishing shot", "B-roll: location", "B-roll: details",
                "Walking shot", "Ending shot",
            ].map { Item(title: $0) }),
            ShotTemplate(name: "Product shoot", items: [
                "Hero shot", "Front", "Back", "Side", "Detail close-up",
                "In hand / in use", "Flat lay", "Packaging",
            ].map { Item(title: $0) }),
        ]
    }
}
