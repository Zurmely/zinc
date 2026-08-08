import SwiftUI
import ZincCore

struct ClipListView: View {
    @EnvironmentObject private var store: MobileClipStore

    var body: some View {
        Group {
            if store.isLoading && store.clips.isEmpty {
                ProgressView("Syncing clips…")
            } else if let message = store.emptyMessage {
                ContentUnavailableView {
                    Label("No Clips", systemImage: "doc.text")
                } description: {
                    Text(message)
                }
            } else {
                List {
                    ForEach(store.filteredClips) { clip in
                        NavigationLink(value: clip) {
                            ClipRow(clip: clip)
                        }
                    }
                    .onDelete(perform: deleteClips)
                }
                .searchable(text: $store.searchText, prompt: "Search clips")
            }
        }
        .navigationDestination(for: Clip.self) { clip in
            ClipDetailView(clip: clip)
        }
    }

    private func deleteClips(at offsets: IndexSet) {
        let clips = store.filteredClips
        let ids = Set(offsets.compactMap { index in
            clips.indices.contains(index) ? clips[index].id : nil
        })
        store.delete(ids: ids)
    }
}

private struct ClipRow: View {
    let clip: Clip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(clip.preview)
                .lineLimit(2)
            HStack {
                Text(clip.contextLabel)
                Spacer()
                Text(SavedAtFormat.string(for: clip.savedAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
