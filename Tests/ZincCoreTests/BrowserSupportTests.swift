import XCTest
@testable import ZincCore

final class BrowserSupportTests: XCTestCase {
    func testSupportedBrowsersIncludeRequestedChromiumBrowsers() {
        let bundleIDs = Set(BrowserSupport.supportedBrowsers.map(\.bundleID))
        let expected: Set<String> = [
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
            "com.operasoftware.Opera",
            "org.chromium.Chromium",
            "company.thebrowser.dia",
            "com.google.Chrome.beta",
            "com.google.Chrome.dev",
            "com.apple.SafariTechnologyPreview",
            "com.kagi.kagimacOS",
        ]
        XCTAssertTrue(expected.isSubset(of: bundleIDs))
    }

    func testLegacyBrowsersRemainSupported() {
        let bundleIDs = Set(BrowserSupport.supportedBrowsers.map(\.bundleID))
        XCTAssertTrue(bundleIDs.contains("com.apple.Safari"))
        XCTAssertTrue(bundleIDs.contains("com.google.Chrome"))
        XCTAssertTrue(bundleIDs.contains("company.thebrowser.Browser"))
        XCTAssertTrue(bundleIDs.contains("com.microsoft.edgemac"))
    }

    func testChromiumScriptUsesActiveTab() {
        let script = BrowserSupport.appleScript(for: "com.brave.Browser")
        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains("tell application \"Brave Browser\"") == true)
        XCTAssertTrue(script?.contains("active tab of front window") == true)
        XCTAssertTrue(script?.contains("title of theTab") == true)
    }

    func testSafariScriptUsesCurrentTab() {
        let script = BrowserSupport.appleScript(for: "com.apple.Safari")
        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains("tell application \"Safari\"") == true)
        XCTAssertTrue(script?.contains("current tab of front window") == true)
        XCTAssertTrue(script?.contains("name of theDoc") == true)
    }

    func testOrionUsesSafariDialect() {
        let browser = BrowserSupport.definition(for: "com.kagi.kagimacOS")
        XCTAssertEqual(browser?.dialect, .safari)
        XCTAssertEqual(browser?.applicationName, "Orion")
    }

    func testParseAppleScriptOutput() {
        let parsed = BrowserSupport.parseAppleScriptOutput("https://example.com\nExample")
        XCTAssertEqual(parsed?.url, "https://example.com")
        XCTAssertEqual(parsed?.title, "Example")
        XCTAssertNil(BrowserSupport.parseAppleScriptOutput(""))
        XCTAssertNil(BrowserSupport.parseAppleScriptOutput("\n"))
    }

    func testUnsupportedBundleReturnsNilScript() {
        XCTAssertFalse(BrowserSupport.isSupported(bundleID: "org.mozilla.firefox"))
        XCTAssertNil(BrowserSupport.appleScript(for: "org.mozilla.firefox"))
    }
}
