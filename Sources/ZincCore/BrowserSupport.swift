import Foundation

public enum BrowserDialect: String, Sendable {
    case safari
    case chromium
}

public struct BrowserDefinition: Sendable, Equatable {
    public let bundleID: String
    public let applicationName: String
    public let dialect: BrowserDialect

    public init(bundleID: String, applicationName: String, dialect: BrowserDialect) {
        self.bundleID = bundleID
        self.applicationName = applicationName
        self.dialect = dialect
    }
}

/// Supported browsers for URL/title capture via AppleScript.
///
/// Firefox (`org.mozilla.firefox`) is intentionally omitted — it has no scriptable tab API on macOS.
public enum BrowserSupport {
    public static let supportedBrowsers: [BrowserDefinition] = [
        BrowserDefinition(bundleID: "com.apple.Safari", applicationName: "Safari", dialect: .safari),
        BrowserDefinition(
            bundleID: "com.apple.SafariTechnologyPreview",
            applicationName: "Safari Technology Preview",
            dialect: .safari
        ),
        BrowserDefinition(bundleID: "com.google.Chrome", applicationName: "Google Chrome", dialect: .chromium),
        BrowserDefinition(bundleID: "com.google.Chrome.beta", applicationName: "Google Chrome Beta", dialect: .chromium),
        BrowserDefinition(bundleID: "com.google.Chrome.dev", applicationName: "Google Chrome Dev", dialect: .chromium),
        BrowserDefinition(bundleID: "com.google.Chrome.canary", applicationName: "Google Chrome Canary", dialect: .chromium),
        BrowserDefinition(bundleID: "com.brave.Browser", applicationName: "Brave Browser", dialect: .chromium),
        BrowserDefinition(bundleID: "com.vivaldi.Vivaldi", applicationName: "Vivaldi", dialect: .chromium),
        BrowserDefinition(bundleID: "com.operasoftware.Opera", applicationName: "Opera", dialect: .chromium),
        BrowserDefinition(bundleID: "org.chromium.Chromium", applicationName: "Chromium", dialect: .chromium),
        BrowserDefinition(bundleID: "company.thebrowser.Browser", applicationName: "Arc", dialect: .chromium),
        BrowserDefinition(bundleID: "company.thebrowser.dia", applicationName: "Dia", dialect: .chromium),
        BrowserDefinition(bundleID: "com.microsoft.edgemac", applicationName: "Microsoft Edge", dialect: .chromium),
        BrowserDefinition(bundleID: "com.kagi.kagimacOS", applicationName: "Orion", dialect: .safari),
        BrowserDefinition(bundleID: "com.kagi.kagimacOS.RC", applicationName: "Orion RC", dialect: .safari),
    ]

    private static let byBundleID: [String: BrowserDefinition] = Dictionary(
        uniqueKeysWithValues: supportedBrowsers.map { ($0.bundleID, $0) }
    )

    public static func definition(for bundleID: String) -> BrowserDefinition? {
        byBundleID[bundleID]
    }

    public static func isSupported(bundleID: String) -> Bool {
        byBundleID[bundleID] != nil
    }

    public static func appleScript(for bundleID: String) -> String? {
        guard let browser = definition(for: bundleID) else { return nil }
        return appleScript(for: browser)
    }

    public static func appleScript(for browser: BrowserDefinition) -> String {
        switch browser.dialect {
        case .safari:
            return """
            tell application "\(browser.applicationName)"
                if (count of windows) = 0 then return ""
                set theDoc to current tab of front window
                return (URL of theDoc) & linefeed & (name of theDoc)
            end tell
            """
        case .chromium:
            return """
            tell application "\(browser.applicationName)"
                if (count of windows) = 0 then return ""
                set theTab to active tab of front window
                return (URL of theTab) & linefeed & (title of theTab)
            end tell
            """
        }
    }

    public static func parseAppleScriptOutput(_ raw: String) -> (url: String, title: String)? {
        guard !raw.isEmpty else { return nil }
        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let urlPart = parts.first else { return nil }
        let url = String(urlPart)
        let title = parts.count > 1 ? String(parts[1]) : ""
        guard !url.isEmpty else { return nil }
        return (url: url, title: title)
    }
}
