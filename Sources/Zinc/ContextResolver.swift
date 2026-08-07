import AppKit
import ApplicationServices
import Foundation

struct SourceContext {
    let appName: String
    let bundleID: String
    let icon: NSImage?
    let pageURL: String?
    let pageTitle: String?
}

enum ContextResolver {
    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser", // Arc
        "com.microsoft.edgemac",
    ]

    /// Persisted so a denied Automation prompt is not re-offered on every capture.
    private static let deniedDefaultsPrefix = "Zinc.automationDenied."

    private static let errAEEventNotPermitted: OSStatus = -1743
    private static let errAEEventWouldRequireUserConsent: OSStatus = -1744
    private static let procNotFoundStatus: OSStatus = -600

    static func resolve() async -> SourceContext {
        let workspace = NSWorkspace.shared
        let frontApp = workspace.frontmostApplication

        let appName = frontApp?.localizedName ?? "Unknown"
        let bundleID = frontApp?.bundleIdentifier ?? "unknown"
        let icon = frontApp.flatMap { workspace.icon(forFile: $0.bundleURL?.path ?? "") }

        guard browserBundleIDs.contains(bundleID) else {
            return SourceContext(
                appName: appName,
                bundleID: bundleID,
                icon: icon,
                pageURL: nil,
                pageTitle: nil
            )
        }

        let browserInfo = await fetchBrowserInfo(bundleID: bundleID)
        return SourceContext(
            appName: appName,
            bundleID: bundleID,
            icon: icon,
            pageURL: browserInfo?.url,
            pageTitle: browserInfo?.title
        )
    }

    private static func fetchBrowserInfo(bundleID: String) async -> (url: String, title: String)? {
        if isDenied(bundleID: bundleID) {
            // Re-check silently in case the user granted access later in System Settings.
            let status = await determinePermission(bundleID: bundleID, askUserIfNeeded: false)
            if status == noErr {
                clearDenied(bundleID: bundleID)
                log("browser Automation previously denied for \(bundleID) — now authorized")
            } else {
                log("browser context skipped — Automation denied for \(bundleID) (remembered)")
                return nil
            }
        }

        guard let script = appleScript(for: bundleID) else { return nil }

        switch await automationPermission(for: bundleID) {
        case .authorized:
            break
        case .denied:
            rememberDenied(bundleID: bundleID)
            log("browser context skipped — Automation not permitted for \(bundleID) (errAEEventNotPermitted)")
            return nil
        case .notRunning:
            log("browser context skipped — \(bundleID) not running (procNotFound)")
            return nil
        case .failed(let status):
            log("browser context skipped — Automation check failed for \(bundleID) (status \(status))")
            return nil
        }

        switch await runAppleScript(script) {
        case .success(let url, let title):
            return (url: url, title: title)
        case .noWindows:
            log("browser context — no windows open in \(bundleID)")
            return nil
        case .notPermitted:
            rememberDenied(bundleID: bundleID)
            log("browser context failed — Automation not permitted for \(bundleID) (errAEEventNotPermitted)")
            return nil
        case .failed(let code, let message):
            log("browser context AppleScript failed for \(bundleID) (code \(code)): \(message)")
            return nil
        }
    }

    private static func appleScript(for bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.Safari":
            return """
            tell application "Safari"
                if (count of windows) = 0 then return ""
                set theDoc to current tab of front window
                return (URL of theDoc) & linefeed & (name of theDoc)
            end tell
            """
        case "com.google.Chrome", "com.google.Chrome.canary",
             "company.thebrowser.Browser", "com.microsoft.edgemac":
            let appName: String
            switch bundleID {
            case "com.google.Chrome": appName = "Google Chrome"
            case "com.google.Chrome.canary": appName = "Google Chrome Canary"
            case "company.thebrowser.Browser": appName = "Arc"
            case "com.microsoft.edgemac": appName = "Microsoft Edge"
            default: appName = "Google Chrome"
            }
            return """
            tell application "\(appName)"
                if (count of windows) = 0 then return ""
                set theTab to active tab of front window
                return (URL of theTab) & linefeed & (title of theTab)
            end tell
            """
        default:
            return nil
        }
    }

    private enum AutomationPermission {
        case authorized
        case denied
        case notRunning
        case failed(OSStatus)
    }

    /// Checks Automation permission; if consent is pending, waits for the user without a short deadline.
    private static func automationPermission(for bundleID: String) async -> AutomationPermission {
        let status = await determinePermission(bundleID: bundleID, askUserIfNeeded: false)

        switch status {
        case noErr:
            return .authorized
        case errAEEventNotPermitted:
            return .denied
        case errAEEventWouldRequireUserConsent:
            log("browser Automation consent pending for \(bundleID) — waiting for user")
            let afterPrompt = await determinePermission(bundleID: bundleID, askUserIfNeeded: true)
            switch afterPrompt {
            case noErr:
                log("browser Automation granted for \(bundleID)")
                return .authorized
            case errAEEventNotPermitted:
                return .denied
            case procNotFoundStatus:
                return .notRunning
            default:
                return .failed(afterPrompt)
            }
        case procNotFoundStatus:
            return .notRunning
        default:
            return .failed(status)
        }
    }

    private static func determinePermission(bundleID: String, askUserIfNeeded: Bool) async -> OSStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleID)
                let status = AEDeterminePermissionToAutomateTarget(
                    descriptor.aeDesc,
                    typeWildCard,
                    typeWildCard,
                    askUserIfNeeded
                )
                continuation.resume(returning: status)
            }
        }
    }

    private enum AppleScriptOutcome {
        case success(url: String, title: String)
        case noWindows
        case notPermitted
        case failed(code: Int, message: String)
    }

    private static func runAppleScript(_ source: String) async -> AppleScriptOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: .failed(code: -1, message: "failed to create NSAppleScript"))
                    return
                }

                var error: NSDictionary?
                let output = script.executeAndReturnError(&error)
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                    let message = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
                    if code == Int(errAEEventNotPermitted) {
                        continuation.resume(returning: .notPermitted)
                    } else {
                        continuation.resume(returning: .failed(code: code, message: message))
                    }
                    return
                }

                guard let raw = output.stringValue else {
                    continuation.resume(returning: .noWindows)
                    return
                }
                if raw.isEmpty {
                    continuation.resume(returning: .noWindows)
                    return
                }

                let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                guard let urlPart = parts.first else {
                    continuation.resume(returning: .noWindows)
                    return
                }
                let url = String(urlPart)
                let title = parts.count > 1 ? String(parts[1]) : ""
                guard !url.isEmpty else {
                    continuation.resume(returning: .noWindows)
                    return
                }
                continuation.resume(returning: .success(url: url, title: title))
            }
        }
    }

    private static func deniedDefaultsKey(for bundleID: String) -> String {
        deniedDefaultsPrefix + bundleID
    }

    private static func isDenied(bundleID: String) -> Bool {
        UserDefaults.standard.bool(forKey: deniedDefaultsKey(for: bundleID))
    }

    private static func rememberDenied(bundleID: String) {
        UserDefaults.standard.set(true, forKey: deniedDefaultsKey(for: bundleID))
    }

    private static func clearDenied(bundleID: String) {
        UserDefaults.standard.removeObject(forKey: deniedDefaultsKey(for: bundleID))
    }

    private static func log(_ message: String) {
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
