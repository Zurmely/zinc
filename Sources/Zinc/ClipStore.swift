import Foundation

extension Notification.Name {
    static let clipsDidChange = Notification.Name("ZincClipsDidChange")
}

final class ClipStore: ObservableObject {
    static let shared = ClipStore()

    @Published private(set) var clips: [Clip] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let zincDir = appSupport.appendingPathComponent("Zinc", isDirectory: true)
        try? FileManager.default.createDirectory(at: zincDir, withIntermediateDirectories: true)
        fileURL = zincDir.appendingPathComponent("clips.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        load()
    }

    func add(_ clip: Clip) {
        if let first = clips.first, first.text == clip.text {
            return
        }
        clips.insert(clip, at: 0)
        save()
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

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            clips = try decoder.decode([Clip].self, from: data)
        } catch {
            NSLog("Zinc: failed to load clips: \(error)")
            clips = []
        }
    }

    private func save() {
        do {
            let data = try encoder.encode(clips)
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
