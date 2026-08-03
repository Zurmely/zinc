import AppKit
import ApplicationServices
import Foundation

enum Permissions {
    private static var didShowAlertThisSession = false

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityIfNeeded() {
        // Check only — do NOT pass prompt:true (that opens a second system dialog).
        let trusted = AXIsProcessTrusted()
        log("Accessibility trusted = \(trusted ? "yes" : "no")")

        if !trusted {
            // Defer the alert so app launch / monitors can finish first.
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
        4. Return here — the menu bar icon will say “Shift monitor: active”
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
        // Sequoia+ URL first, then legacy.
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

    static func log(_ message: String) {
        NSLog("Zinc: %@", message)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Zinc", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let logURL = dir.appendingPathComponent("debug.log")
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
    }
}
