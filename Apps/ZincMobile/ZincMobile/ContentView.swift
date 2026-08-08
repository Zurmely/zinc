import SwiftUI
import ZincCore

struct ContentView: View {
    @EnvironmentObject private var store: MobileClipStore

    var body: some View {
        NavigationStack {
            ClipListView()
                .navigationTitle("Zinc")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text(store.status.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .task {
            await store.startSync()
        }
    }
}
