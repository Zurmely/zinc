import Foundation
import ZincCore

extension Notification.Name {
    static let clipsDidChange = Notification.Name("ZincClipsDidChange")
}

final class ClipStore: ObservableObject {
    static let shared = ClipStore()

    @Published private(set) var clips: [Clip] = []

    private let fileURL: URL
    private let syncSettings = SyncSettings.shared
    private var isApplyingRemoteChanges = false

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let zincDir = appSupport.appendingPathComponent("Zinc", isDirectory: true)
        try? FileManager.default.createDirectory(at: zincDir, withIntermediateDirectories: true)
        fileURL = zincDir.appendingPathComponent("clips.json")

        load()
        configureSync()
    }

    func add(_ clip: Clip) {
        if let first = clips.first, first.text == clip.text {
            return
        }
        clips.insert(clip, at: 0)
        save()
        pushToCloudIfNeeded(save: [clip])
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
    }

    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let paths = clips.filter { ids.contains($0.id) }.compactMap(\.markdownPath)
        let removed = clips.count
        clips.removeAll { ids.contains($0.id) }
        guard clips.count < removed else { return }
        SystemSounds.playTrash()
        save()
        MarkdownPreviewStore.shared.invalidate(ids: ids)
        VaultFileManager.trashInBackground(markdownPaths: paths)
        pushToCloudIfNeeded(delete: ids)
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
    }

    func clear() {
        guard !clips.isEmpty else { return }
        let ids = Set(clips.map(\.id))
        let paths = clips.compactMap(\.markdownPath)
        clips.removeAll()
        SystemSounds.playTrash()
        save()
        MarkdownPreviewStore.shared.clear()
        VaultFileManager.trashInBackground(markdownPaths: paths)
        pushToCloudIfNeeded(delete: ids)
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
    }

    func setMarkdownPath(_ path: String, for id: UUID) {
        let apply = { [self] in
            guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
            clips[index].markdownPath = path
            save()
            // Export finishes after the clip is first shown as plain-text fallback —
            // invalidate and reload so the panel picks up the real markdown file.
            MarkdownPreviewStore.shared.invalidate(ids: [id])
            MarkdownPreviewStore.shared.loadIfNeeded(for: clips[index])
            NotificationCenter.default.post(name: .clipsDidChange, object: nil)
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    func handleSyncEnabledChanged(_ enabled: Bool) {
        Task { @MainActor in
            await ClipSyncCoordinator.shared.setEnabled(enabled, clips: clips)
        }
    }

    private func configureSync() {
        Task { @MainActor in
            ClipSyncCoordinator.shared.configure(store: self)
            if syncSettings.iCloudSyncEnabled {
                await ClipSyncCoordinator.shared.setEnabled(true, clips: clips)
            }
        }
    }

    private func pushToCloudIfNeeded(save: [Clip] = [], delete: Set<UUID> = []) {
        guard syncSettings.iCloudSyncEnabled, !isApplyingRemoteChanges else { return }
        Task { @MainActor in
            await ClipSyncCoordinator.shared.pushLocalChanges(save: save, delete: delete)
        }
    }

    fileprivate func applyRemoteUpserts(_ upserts: [Clip]) {
        guard !upserts.isEmpty else { return }
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        var byID = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
        for upsert in upserts {
            if let existing = byID[upsert.id] {
                if upsert.modifiedAt >= existing.modifiedAt {
                    var merged = upsert
                    merged.markdownPath = existing.markdownPath
                    byID[upsert.id] = merged
                }
            } else {
                byID[upsert.id] = upsert
            }
        }

        clips = byID.values.sorted { $0.savedAt > $1.savedAt }
        save()
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
    }

    fileprivate func applyRemoteDeletes(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        let paths = clips.filter { ids.contains($0.id) }.compactMap(\.markdownPath)
        let before = clips.count
        clips.removeAll { ids.contains($0.id) }
        guard clips.count < before else { return }

        save()
        MarkdownPreviewStore.shared.invalidate(ids: ids)
        VaultFileManager.trashInBackground(markdownPaths: paths)
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            clips = try ClipCodec.decode(data)
        } catch {
            NSLog("Zinc: failed to load clips: \(error)")
            clips = []
        }
    }

    private func save() {
        do {
            let data = try ClipCodec.encode(clips)
            let tempURL = fileURL.appendingPathExtension("tmp")
            try data.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        } catch {
            NSLog("Zinc: failed to save clips: \(error)")
        }
    }
}

@MainActor
final class ClipSyncCoordinator {
    static let shared = ClipSyncCoordinator()

    private weak var store: ClipStore?
    private let cloudSync = ClipCloudSync.shared

    private init() {}

    func configure(store: ClipStore) {
        self.store = store
        cloudSync.onRemoteUpserts = { [weak store] upserts in
            store?.applyRemoteUpserts(upserts)
        }
        cloudSync.onRemoteDeletes = { [weak store] ids in
            store?.applyRemoteDeletes(ids)
        }
    }

    func setEnabled(_ enabled: Bool, clips: [Clip]) async {
        if enabled {
            await cloudSync.start()
            cloudSync.uploadAll(clips)
            cloudSync.fetchChanges()
        } else {
            cloudSync.stop()
        }
    }

    func pushLocalChanges(save: [Clip], delete: Set<UUID>) async {
        guard SyncSettings.shared.iCloudSyncEnabled else { return }
        for clip in save {
            cloudSync.enqueueSave(clip)
        }
        if !delete.isEmpty {
            cloudSync.enqueueDelete(ids: delete)
        }
    }

    var status: ClipCloudSync.Status {
        cloudSync.status
    }

    var lastSyncedAt: Date? {
        cloudSync.lastSyncedAt
    }
}
