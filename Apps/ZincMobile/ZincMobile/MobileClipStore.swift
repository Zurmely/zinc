import Foundation
import ZincCore

@MainActor
final class MobileClipStore: ObservableObject {
    @Published private(set) var clips: [Clip] = []
    @Published var searchText = ""
    @Published private(set) var status: ClipCloudSync.Status = .disabled
    @Published private(set) var isLoading = false
    @Published private(set) var lastSyncedAt: Date?

    private let cache = ClipJSONStore(filename: "clips.json", subdirectory: "ZincMobile")
    private let cloudSync = ClipCloudSync.shared

    var filteredClips: [Clip] {
        ClipSearch.filter(clips, query: searchText)
    }

    var emptyMessage: String? {
        if case let .unavailable(message) = status {
            return message
        }
        if !searchText.isEmpty && filteredClips.isEmpty {
            return "No clips match your search."
        }
        if clips.isEmpty {
            return "Enable iCloud sync in Zinc on your Mac to see clips here."
        }
        return nil
    }

    init() {
        clips = cache.clips
        configureCloudSync()
    }

    func startSync() async {
        isLoading = true
        await cloudSync.start()
        cloudSync.fetchChanges()
        refreshStatus()
        isLoading = false
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        cache.remove(ids: ids)
        clips = cache.clips
        cloudSync.enqueueDelete(ids: ids)
    }

    private func configureCloudSync() {
        cloudSync.onRemoteUpserts = { [weak self] upserts in
            Task { @MainActor in
                self?.cache.applyRemoteUpserts(upserts)
                self?.clips = self?.cache.clips ?? []
                self?.refreshStatus()
            }
        }
        cloudSync.onRemoteDeletes = { [weak self] ids in
            Task { @MainActor in
                self?.cache.applyRemoteDeletes(ids)
                self?.clips = self?.cache.clips ?? []
                self?.refreshStatus()
            }
        }
    }

    private func refreshStatus() {
        status = cloudSync.status
        lastSyncedAt = cloudSync.lastSyncedAt
    }
}
