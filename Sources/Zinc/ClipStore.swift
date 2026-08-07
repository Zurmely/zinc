import Combine
import Foundation

extension Notification.Name {
    static let clipsDidChange = Notification.Name("ZincClipsDidChange")
}

enum ClipAddResult: Equatable {
    case added
    case deduplicated(existingID: UUID)
}

/// Describes a recoverable failure loading `clips.json`.
struct ClipIndexRecoveryOffer: Equatable {
    let preservedCorruptURL: URL
    let backupAvailable: Bool
}

final class ClipStore: ObservableObject {
    static let shared = ClipStore()

    /// Placeholder index text used when the pasteboard has no plain text.
    /// These collide across distinct captures, so they only dedupe against the newest clip.
    private static let nonUniqueIndexTexts: Set<String> = ["[Image]", "[Rich content]"]

    @Published private(set) var clips: [Clip] = []

    /// Set when the on-disk index could not be decoded. Cleared after the user
    /// recovers (backup / reindex) or dismisses and starts empty.
    private(set) var pendingRecovery: ClipIndexRecoveryOffer?

    private let indexFile: ClipIndexFile

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let zincDir = appSupport.appendingPathComponent("Zinc", isDirectory: true)
        try? FileManager.default.createDirectory(at: zincDir, withIntermediateDirectories: true)
        indexFile = ClipIndexFile(directoryURL: zincDir)
        load()
    }

    /// Test seam — uses an isolated directory instead of Application Support.
    init(directoryURL: URL) {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        indexFile = ClipIndexFile(directoryURL: directoryURL)
        load()
    }

    /// Inserts a new clip, or bumps an existing duplicate to the top.
    /// Callers must skip vault export when the result is `.deduplicated`.
    @discardableResult
    func add(_ clip: Clip) -> ClipAddResult {
        if let existingIndex = indexOfDuplicate(for: clip.text) {
            var existing = clips.remove(at: existingIndex)
            existing.savedAt = clip.savedAt
            clips.insert(existing, at: 0)
            save()
            NotificationCenter.default.post(name: .clipsDidChange, object: nil)
            return .deduplicated(existingID: existing.id)
        }

        clips.insert(clip, at: 0)
        save()
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
        return .added
    }

    private func indexOfDuplicate(for text: String) -> Int? {
        if Self.nonUniqueIndexTexts.contains(text) {
            guard let first = clips.first, first.text == text else { return nil }
            return 0
        }
        return clips.firstIndex(where: { $0.text == text })
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
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
    }

    func clear() {
        guard !clips.isEmpty else { return }
        let paths = clips.compactMap(\.markdownPath)
        clips.removeAll()
        SystemSounds.playTrash()
        save()
        MarkdownPreviewStore.shared.clear()
        VaultFileManager.trashInBackground(markdownPaths: paths)
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

    /// Restores the rolling backup of the last good index, if available.
    @discardableResult
    func restoreFromBackup() -> Bool {
        guard let restored = indexFile.loadBackup() else { return false }
        clips = restored
        pendingRecovery = nil
        save()
        MarkdownPreviewStore.shared.clear()
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
        return true
    }

    /// Rebuilds the index from Markdown files in the vault (merge by id).
    @discardableResult
    func reindexFromVault(vaultURL: URL = VaultSettings.vaultURL) -> Int {
        let vaultClips = VaultReindexer.reindex(vaultURL: vaultURL)
        clips = VaultReindexer.merge(existing: clips, fromVault: vaultClips)
        pendingRecovery = nil
        save()
        MarkdownPreviewStore.shared.clear()
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
        return clips.count
    }

    /// Clears the recovery offer without restoring — user chose to start empty.
    /// The quarantined corrupt file is left untouched on disk.
    func dismissRecoveryOffer() {
        pendingRecovery = nil
    }

    private func load() {
        switch indexFile.load() {
        case .missing:
            clips = []
        case .loaded(let loaded):
            clips = loaded
        case .corrupt(let preservedURL):
            NSLog("Zinc: failed to load clips; preserved corrupt index at \(preservedURL.path)")
            clips = []
            pendingRecovery = ClipIndexRecoveryOffer(
                preservedCorruptURL: preservedURL,
                backupAvailable: indexFile.hasBackup
            )
        }
    }

    private func save() {
        do {
            try indexFile.save(clips)
        } catch {
            NSLog("Zinc: failed to save clips: \(error)")
        }
    }
}
