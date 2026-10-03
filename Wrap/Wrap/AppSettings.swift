import Foundation
import ServiceManagement

enum AppSettings {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let startPage = "startPage"

    static let linkExpiryHours = "linkExpiryHours"
    static let downloadAlerts = "downloadAlertsOn"

    static let expiryChoices = [24, 48, 168]

    static var expiryHours: Int {
        let value = UserDefaults.standard.integer(forKey: linkExpiryHours)
        return expiryChoices.contains(value) ? value : 48
    }

    static var downloadAlertsOn: Bool {
        UserDefaults.standard.object(forKey: downloadAlerts) as? Bool ?? true
    }

    static func expiryLabel(_ hours: Int) -> String {
        hours % 24 == 0 && hours > 48 ? "\(hours / 24) days" : "\(hours) hours"
    }

    // MARK: Open at login

    static var opensAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setOpensAtLogin(_ on: Bool) -> String? {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "macOS wouldn't change this (\(error.localizedDescription)). Make sure Wrap is in your Applications folder."
        }
    }
}
