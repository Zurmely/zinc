import Foundation

public final class ClipJSONStore: ObservableObject {
    @Published public private(set) var clips: [Clip] = []

    private let fileURL: URL

    public init(filename: String = "clips.json", subdirectory: String = "Zinc") {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent(subdirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(filename)
        load()
    }

    public func replaceAll(_ clips: [Clip]) {
        self.clips = clips
        save()
    }

    public func applyRemoteUpserts(_ upserts: [Clip]) {
        guard !upserts.isEmpty else { return }

        var byID = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
        for upsert in upserts {
            if let existing = byID[upsert.id] {
                if upsert.modifiedAt >= existing.modifiedAt {
                    byID[upsert.id] = merge(existing: existing, remote: upsert)
                }
            } else {
                byID[upsert.id] = upsert
            }
        }

        clips = byID.values.sorted { $0.savedAt > $1.savedAt }
        save()
    }

    public func applyRemoteDeletes(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let before = clips.count
        clips.removeAll { ids.contains($0.id) }
        guard clips.count < before else { return }
        save()
    }

    public func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let before = clips.count
        clips.removeAll { ids.contains($0.id) }
        guard clips.count < before else { return }
        save()
    }

    private func merge(existing: Clip, remote: Clip) -> Clip {
        var merged = remote
        if let markdownPath = existing.markdownPath {
            merged.markdownPath = markdownPath
        }
        return merged
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            clips = try ClipCodec.decode(data)
        } catch {
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
            NSLog("Zinc: failed to save clips cache: \(error)")
        }
    }
}
