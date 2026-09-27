import AppKit
import ApplicationServices

/// A window's saved position and size, plus its title to find it again.
struct SavedWindow: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var title: String

    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Reads and moves other apps' windows using the macOS Accessibility API.
/// Needs the Accessibility permission in System Settings > Privacy & Security.
enum WindowMover {
    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to System Settings.
    static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// The normal (non-panel, non-dialog) windows of an app, front to back.
    static func windows(of app: NSRunningApplication) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement]
        else { return [] }
        return list.filter { string($0, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String) }
    }

    static func title(of window: AXUIElement) -> String {
        string(window, kAXTitleAttribute) ?? ""
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = axValue(window, kAXPositionAttribute),
              let size = axValue(window, kAXSizeAttribute)
        else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position, .cgPoint, &point)
        AXValueGetValue(size, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }

    static func setFrame(_ rect: CGRect, of window: AXUIElement) {
        var point = rect.origin
        var extent = rect.size
        guard let position = AXValueCreate(.cgPoint, &point),
              let size = AXValueCreate(.cgSize, &extent)
        else { return }
        // Size, then position, then size again: some apps clamp the size
        // to the screen they're on before they've moved.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
    }

    /// True when the window is already (almost) where it should be.
    static func isPlaced(_ window: AXUIElement, at rect: CGRect) -> Bool {
        guard let current = frame(of: window) else { return false }
        return abs(current.minX - rect.minX) < 4 && abs(current.minY - rect.minY) < 4
            && abs(current.width - rect.width) < 4 && abs(current.height - rect.height) < 4
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        return (value as! AXValue)
    }
}
