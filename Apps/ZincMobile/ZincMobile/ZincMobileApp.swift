import SwiftUI
import ZincCore

@main
struct ZincMobileApp: App {
    @StateObject private var store = MobileClipStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
