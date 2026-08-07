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

    private static let appleScriptTimeout: Duration = .milliseconds(500)

    /// Resolves the frontmost app and, for known browsers, the active tab URL/title.
    /// AppleScript runs off the main thread; callers should prefer this async API.
    static func resolve() async -> SourceContext {
        let (appName, bundleID, icon) = await MainActor.run { () -> (String, String, NSImage?) in
            let workspace = NSWorkspace.shared
            let frontApp = workspace.frontmostApplication
            let appName = frontApp?.localizedName ?? "Unknown"
            let bundleID = frontApp?.bundleIdentifier ?? "unknown"
            let icon = frontApp.flatMap { workspace.icon(forFile: $0.bundleURL?.path ?? "") }
            return (appName, bundleID, icon)
        }

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

        return await runAppleScript(script)
    }

    private static func runAppleScript(_ source: String) async -> (url: String, title: String)? {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            func finish(_ value: (url: String, title: String)?) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                finish(Self.executeAppleScript(source))
            }

            Task {
                try? await Task.sleep(for: appleScriptTimeout)
                finish(nil)
            }
        }
    }

    private static func executeAppleScript(_ source: String) -> (url: String, title: String)? {
        guard let script = NSAppleScript(source: source) else { return nil }

        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if error != nil { return nil }

        guard let raw = output.stringValue, !raw.isEmpty else { return nil }
        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let urlPart = parts.first else { return nil }
        let url = String(urlPart)
        let title = parts.count > 1 ? String(parts[1]) : ""
        guard !url.isEmpty else { return nil }
        return (url: url, title: title)
    }
}
