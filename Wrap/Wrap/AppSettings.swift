import Foundation
import ServiceManagement

/// Names and defaults for the choices on the Settings page.
enum AppSettings {
    // General
    static let showMenuBarIcon = "showMenuBarIcon"      // Bool, default true
    static let startPage = "startPage"                  // "dashboard" or "projects"

    // Delivery
    static let linkExpiryHours = "linkExpiryHours"      // 24, 48 or 168
    static let downloadAlerts = "downloadAlertsOn"      // Bool, default true

    static let expiryChoices = [24, 48, 168]

    static var expiryHours: Int {
        let value = UserDefaults.standard.integer(forKey: linkExpiryHours)
        return expiryChoices.contains(value) ? value : 48
    }

    static var downloadAlertsOn: Bool {
        UserDefaults.standard.object(forKey: downloadAlerts) as? Bool ?? true
    }

    /// "24 hours", "48 hours", "7 days"
    static func expiryLabel(_ hours: Int) -> String {
        hours % 24 == 0 && hours > 48 ? "\(hours / 24) days" : "\(hours) hours"
    }

    // MARK: Open at login

    static var opensAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Turn "Open Wrap at login" on or off. Returns an error message if macOS refused.
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
