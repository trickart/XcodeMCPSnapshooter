import AppKit
@preconcurrency import ApplicationServices

/// Detects and auto-clicks the "Allow" button on Xcode's MCP permission dialog
/// using the Accessibility API.
enum AccessibilityHelper {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Finds and clicks the "Allow" button on Xcode's MCP permission dialog.
    /// Returns `true` if the button was found and clicked.
    static func clickAllowButtonInXcode() -> Bool {
        guard let xcodePID = findXcodePID() else { return false }

        let app = AXUIElementCreateApplication(xcodePID)
        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else {
            return false
        }

        for window in windows {
            guard isMCPPermissionDialog(window) else { continue }
            if pressAllowButton(in: window) {
                return true
            }
        }
        return false
    }

    // MARK: - Private

    private static func findXcodePID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Xcode")
            .first?.processIdentifier
    }

    private static func isMCPPermissionDialog(_ window: AXUIElement) -> Bool {
        // 1. subrole == "AXDialog"
        guard (attribute(window, kAXSubroleAttribute) as? String) == "AXDialog" else {
            return false
        }
        // 2. title == ""
        guard (attribute(window, kAXTitleAttribute) as? String) == "" else {
            return false
        }

        let children = childElements(of: window)

        // 3. Has AXStaticText matching 'Allow "..." to access Xcode?'
        let hasPermissionText = children.contains { child in
            guard (attribute(child, kAXRoleAttribute) as? String) == "AXStaticText" else {
                return false
            }
            guard let value = attribute(child, kAXValueAttribute) as? String else {
                return false
            }
            return value.hasPrefix("Allow ") && value.hasSuffix(" to access Xcode?")
        }
        guard hasPermissionText else { return false }

        // 4. Has both "Allow" and "Don't Allow" buttons
        let buttonTitles = children
            .filter { (attribute($0, kAXRoleAttribute) as? String) == "AXButton" }
            .compactMap { attribute($0, kAXTitleAttribute) as? String }
        return buttonTitles.contains("Allow") && buttonTitles.contains("Don\u{2019}t Allow")
    }

    private static func pressAllowButton(in window: AXUIElement) -> Bool {
        let children = childElements(of: window)
        for child in children {
            guard (attribute(child, kAXRoleAttribute) as? String) == "AXButton",
                  (attribute(child, kAXTitleAttribute) as? String) == "Allow" else {
                continue
            }
            let result = AXUIElementPerformAction(child, kAXPressAction as CFString)
            return result == .success
        }
        return false
    }

    private static func attribute(_ element: AXUIElement, _ attr: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    private static func childElements(of element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}
