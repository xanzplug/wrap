import Foundation
import Observation
import Sparkle

/// "Check for Updates…": looks for a newer Wrap on GitHub, then downloads,
/// installs and restarts it. Also checks quietly once a day.
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    /// False while a check is already running.
    private(set) var canCheck = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = value }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// e.g. "Version 1.1 (2)"
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }
}
