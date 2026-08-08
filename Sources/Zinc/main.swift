import AppKit
import Foundation

if ProcessInfo.processInfo.environment["ZINC_VERIFY_BROWSER_CONTEXT"] == "1" {
    let semaphore = DispatchSemaphore(value: 0)
    var resolved: SourceContext?
    Task {
        resolved = await ContextResolver.resolve()
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 30)

    if let pageURL = resolved?.pageURL, !pageURL.isEmpty {
        print("url: \(pageURL)")
        if let pageTitle = resolved?.pageTitle, !pageTitle.isEmpty {
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
