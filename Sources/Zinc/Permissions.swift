import AppKit
import ApplicationServices
import Foundation

enum Permissions {
    private static var didShowAlertThisSession = false

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityIfNeeded() {
        let trusted = AXIsProcessTrusted()
        ZincLogger.info("Accessibility trusted = \(trusted ? "yes" : "no")")

        if !trusted {
            DispatchQueue.main.async {
                showAccessibilityAlertIfNeeded()
            }
        }
    }

    static func showAccessibilityAlertIfNeeded() {
        guard !didShowAlertThisSession else { return }
        guard !isAccessibilityTrusted else { return }
        didShowAlertThisSession = true
        showAccessibilityAlert()
    }

    static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        Zinc needs Accessibility to detect double-Shift and capture selections.

        1. Click “Open System Settings” below
        2. Find Zinc in the Accessibility list and turn it ON
        3. If Zinc isn’t listed, click + and choose Zinc.app
        4. Return here — Zinc will show a brief “Shift monitor active” confirmation
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
