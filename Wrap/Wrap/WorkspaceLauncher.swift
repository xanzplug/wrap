import AppKit

/// Opens, hides and arranges a project's workspace.
enum WorkspaceLauncher {
    // MARK: Launch

    /// Opens every item in list order, then moves windows to their saved places.
    static func launch(_ items: [WorkspaceItem]) {
        let available = items.filter { !$0.isMissing }
        for item in available {
            open(item)
        }
        let withLayout = available.filter { !$0.savedWindows.isEmpty }
        if !withLayout.isEmpty && WindowMover.hasPermission {
            restoreLayout(withLayout)
        }
    }

    static func open(_ item: WorkspaceItem) {
        guard let url = item.url else { return }
        switch item.kind {
        case .app:
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .file, .folder, .website:
            // Files open in their usual app, e.g. a .prproj opens in Premiere Pro.
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Hide

    /// Hides the apps this workspace uses, without quitting them.
    static func hide(_ items: [WorkspaceItem]) {
        for item in items {
            guard let app = runningApp(for: item),
                  app.bundleIdentifier != "com.apple.finder"
            else { continue }
            app.hide()
        }
    }

    // MARK: Save Layout

    /// Records where each item's windows are right now.
    /// Returns how many items had a window to save.
    @discardableResult
    static func saveLayout(_ items: [WorkspaceItem]) -> Int {
        var saved = 0
        for item in items {
            let windows = captureWindows(for: item)
            item.savedWindows = windows
            if !windows.isEmpty { saved += 1 }
        }
        return saved
    }

    private static func captureWindows(for item: WorkspaceItem) -> [SavedWindow] {
        guard item.kind != .website, let app = runningApp(for: item) else { return [] }
        let windows = WindowMover.windows(of: app)
        let chosen: [AXUIElement]
        switch item.kind {
        case .app:
            chosen = windows
        case .file, .folder:
            chosen = matchingWindow(for: item, in: windows).map { [$0] } ?? []
        case .website:
            chosen = []
        }
        return chosen.compactMap { window in
            guard let frame = WindowMover.frame(of: window) else { return nil }
            return SavedWindow(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height,
                               title: WindowMover.title(of: window))
        }
    }

    // MARK: Restore

    /// Apps take a while to open, so keep checking for their windows
    /// for up to 30 seconds. An item counts as done once its windows have
    /// stayed in place for three checks in a row (some apps move their own
    /// windows back just after launching).
    private static func restoreLayout(_ items: [WorkspaceItem]) {
        Task { @MainActor in
            var steadyChecks: [ObjectIdentifier: Int] = [:]
            var pending = items
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(500))
                pending = pending.filter { item in
                    let key = ObjectIdentifier(item)
                    if placeWindows(for: item) {
                        steadyChecks[key, default: 0] += 1
                    } else {
                        steadyChecks[key] = 0
                    }
                    return steadyChecks[key, default: 0] < 3
                }
                if pending.isEmpty { break }
            }
        }
    }

    /// Moves this item's windows to their saved frames.
    /// Returns true when every saved window was found and is in place.
    private static func placeWindows(for item: WorkspaceItem) -> Bool {
        guard let app = runningApp(for: item) else { return false }
        let windows = WindowMover.windows(of: app)
        guard !windows.isEmpty else { return false }
        let saved = item.savedWindows

        switch item.kind {
        case .app:
            var allPlaced = windows.count >= saved.count
            var used = Set<Int>()
            for (index, target) in saved.enumerated() {
                // Prefer the window with the same title, else the same position in the list.
                let byTitle = windows.indices.first { !used.contains($0) && !target.title.isEmpty
                    && WindowMover.title(of: windows[$0]) == target.title }
                let fallback = index < windows.count && !used.contains(index) ? index : nil
                guard let chosen = byTitle ?? fallback else { allPlaced = false; continue }
                used.insert(chosen)
                if !WindowMover.isPlaced(windows[chosen], at: target.frame) {
                    WindowMover.setFrame(target.frame, of: windows[chosen])
                    allPlaced = false
                }
            }
            return allPlaced
        case .file, .folder:
            guard let target = saved.first,
                  let window = matchingWindow(for: item, in: windows)
            else { return false }
            if WindowMover.isPlaced(window, at: target.frame) { return true }
            WindowMover.setFrame(target.frame, of: window)
            return false
        case .website:
            return true
        }
    }

    // MARK: Helpers

    /// The running app that shows this item: the app itself, or the app that opens the file.
    private static func runningApp(for item: WorkspaceItem) -> NSRunningApplication? {
        guard let url = item.url else { return nil }
        let appURL = item.kind == .app ? url : NSWorkspace.shared.urlForApplication(toOpen: url)
        guard let appPath = appURL?.standardizedFileURL.path else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.standardizedFileURL.path == appPath
        }
    }

    /// For a file or folder: the window whose title mentions it,
    /// or the app's only window if there's just one.
    private static func matchingWindow(for item: WorkspaceItem, in windows: [AXUIElement]) -> AXUIElement? {
        let baseName = ((item.name as NSString).deletingPathExtension).lowercased()
        if let match = windows.first(where: { WindowMover.title(of: $0).lowercased().contains(baseName) }) {
            return match
        }
        return windows.count == 1 ? windows.first : nil
    }
}
