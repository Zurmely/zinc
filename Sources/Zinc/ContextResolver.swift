import AppKit

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

    static func resolve() -> SourceContext {
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

        let browserInfo = fetchBrowserInfo(bundleID: bundleID)
        return SourceContext(
            appName: appName,
            bundleID: bundleID,
            icon: icon,
            pageURL: browserInfo?.url,
            pageTitle: browserInfo?.title
        )
    }

    private static func fetchBrowserInfo(bundleID: String) -> (url: String, title: String)? {
        let script: String

        switch bundleID {
        case "com.apple.Safari":
            script = """
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
            script = """
            tell application "\(appName)"
                if (count of windows) = 0 then return ""
                set theTab to active tab of front window
                return (URL of theTab) & linefeed & (title of theTab)
            end tell
            """
        default:
            return nil
        }

        return runAppleScript(script)
    }

    private static func runAppleScript(_ source: String) -> (url: String, title: String)? {
        var result: (url: String, title: String)?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            defer { semaphore.signal() }
            guard let script = NSAppleScript(source: source) else { return }

            var error: NSDictionary?
            let output = script.executeAndReturnError(&error)
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                let message = error[NSAppleScript.errorMessage] as? String ?? "unknown"
                NSLog("Zinc: AppleScript failed (\(code)): \(message)")
                return
            }

            guard let raw = output.stringValue, !raw.isEmpty else { return }
            let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard let urlPart = parts.first else { return }
            let url = String(urlPart)
            let title = parts.count > 1 ? String(parts[1]) : ""
            guard !url.isEmpty else { return }
            result = (url: url, title: title)
        }

        _ = semaphore.wait(timeout: .now() + 0.5)
        return result
    }
}
