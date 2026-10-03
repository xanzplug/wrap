import Foundation
import Observation
import Sparkle

@Observable
final class AppUpdater {
    static let shared = AppUpdater()

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

    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    var lastChecked: Date? { controller.updater.lastUpdateCheckDate }

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }
}
