import AppKit
import Foundation

if ProcessInfo.processInfo.environment["ZINC_VERIFY_BROWSER_CONTEXT"] == "1" {
    let context = ContextResolver.resolve()
    if let pageURL = context.pageURL, !pageURL.isEmpty {
        print("url: \(pageURL)")
        if let pageTitle = context.pageTitle, !pageTitle.isEmpty {
            print("title: \(pageTitle)")
        }
        exit(0)
    }

    fputs("error: no browser URL resolved\n", stderr)
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
