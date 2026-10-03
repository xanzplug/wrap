import Foundation
import SwiftData

enum LibraryStore {
    private static var containers: [String: ModelContainer] = [:]
    private static let legacyClaimedKey = "legacyLibraryClaimed"

    static func container(for accountID: String) -> ModelContainer {
        if let existing = containers[accountID] { return existing }

        let folder = URL.applicationSupportDirectory
            .appending(path: "Wrap/Accounts/\(accountID)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storeURL = folder.appending(path: "Library.store")

        adoptOldLibraryIfNeeded(into: storeURL)

        let container: ModelContainer
        do {
            container = try open(storeURL)
        } catch {
            removeStoreFiles(at: storeURL)
            container = (try? open(storeURL)) ?? inMemoryFallback()
        }
        addStarterTemplatesIfNeeded(to: container, accountID: accountID)
        containers[accountID] = container
        return container
    }

    private static func addStarterTemplatesIfNeeded(to container: ModelContainer, accountID: String) {
        let key = "starterTemplatesAdded.\(accountID)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let context = container.mainContext
        for template in ShotTemplate.makeStarters() {
            context.insert(template)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    private static func open(_ url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Project.self, Shot.self, WorkspaceItem.self, ShotTemplate.self,
            configurations: ModelConfiguration(url: url)
        )
    }

    private static func inMemoryFallback() -> ModelContainer {
        try! ModelContainer(
            for: Project.self, Shot.self, WorkspaceItem.self, ShotTemplate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private static func adoptOldLibraryIfNeeded(into storeURL: URL) {
        let defaults = UserDefaults.standard
        let fm = FileManager.default
        let oldStore = URL.applicationSupportDirectory.appending(path: "default.store")

        guard !defaults.bool(forKey: legacyClaimedKey),
              fm.fileExists(atPath: oldStore.path),
              !fm.fileExists(atPath: storeURL.path)
        else { return }

        let folder = storeURL.deletingLastPathComponent()
        for suffix in ["", "-shm", "-wal"] {
            let from = URL(fileURLWithPath: oldStore.path + suffix)
            let to = URL(fileURLWithPath: storeURL.path + suffix)
            if fm.fileExists(atPath: from.path) {
                try? fm.copyItem(at: from, to: to)
            }
        }
        let oldImages = URL.applicationSupportDirectory.appending(path: ".default_SUPPORT")
        if fm.fileExists(atPath: oldImages.path) {
            try? fm.copyItem(at: oldImages, to: folder.appending(path: ".Library_SUPPORT"))
        }
        defaults.set(true, forKey: legacyClaimedKey)
    }

    private static func removeStoreFiles(at storeURL: URL) {
        let fm = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            try? fm.removeItem(atPath: storeURL.path + suffix)
        }
        try? fm.removeItem(at: storeURL.deletingLastPathComponent().appending(path: ".Library_SUPPORT"))
    }
}
