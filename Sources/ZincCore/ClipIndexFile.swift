import Foundation

/// Result of attempting to load the clip index from disk.
enum ClipIndexLoadResult: Equatable {
    /// No `clips.json` present — fresh install or cleared state.
    case missing
    /// Successfully decoded clips (versioned or legacy bare-array format).
    case loaded([Clip])
    /// File existed but could not be decoded. The damaged bytes were moved aside
    /// to `preservedURL` and must never be overwritten in place.
    case corrupt(preservedURL: URL)
}

/// Atomic, versioned persistence for the clip index with corrupt-file quarantine
/// and a single rolling backup of the last good write.
final class ClipIndexFile {
    let directoryURL: URL
    let fileURL: URL
    let backupURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let now: () -> Date

    init(
        directoryURL: URL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent("clips.json")
        self.backupURL = directoryURL.appendingPathComponent("clips.json.bak")
        self.fileManager = fileManager
        self.now = now

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Loads the index. On decode failure, quarantines the bad file as
    /// `clips.corrupt-<timestamp>.json` and returns `.corrupt`.
    func load() -> ClipIndexLoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let clips = try decodeClips(from: data)
            return .loaded(clips)
        } catch {
            let preservedURL = quarantineCorruptFile()
            return .corrupt(preservedURL: preservedURL)
        }
    }

    /// Writes a versioned envelope atomically. Keeps one rolling backup of the
    /// previous good index at `clips.json.bak`.
    func save(_ clips: [Clip]) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let document = ClipIndexDocument(clips: clips)
        let data = try encoder.encode(document)

        let tempURL = directoryURL.appendingPathComponent("clips.json.tmp-\(UUID().uuidString)")
        do {
            try data.write(to: tempURL, options: .atomic)

            if fileManager.fileExists(atPath: fileURL.path) {
                try refreshRollingBackup()
                try atomicallyReplaceLiveFile(with: tempURL, encoded: data)
            } else {
                try fileManager.moveItem(at: tempURL, to: fileURL)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    /// Restores clips from the rolling backup, if present and valid.
    func loadBackup() -> [Clip]? {
        guard fileManager.fileExists(atPath: backupURL.path) else { return nil }
        guard let data = try? Data(contentsOf: backupURL) else { return nil }
        return try? decodeClips(from: data)
    }

    var hasBackup: Bool {
        fileManager.fileExists(atPath: backupURL.path)
    }

    // MARK: - Private

    private func atomicallyReplaceLiveFile(with tempURL: URL, encoded data: Data) throws {
        // Preferred on Apple platforms: metadata-preserving atomic swap.
        do {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: tempURL)
            return
        } catch {
            // Linux swift-corelibs-foundation (and some edge cases) reject replaceItemAt.
            // `Data.write(..., options: .atomic)` renames over the destination on POSIX,
            // so the live path is never deleted before the new bytes are visible.
            try data.write(to: fileURL, options: .atomic)
            try? fileManager.removeItem(at: tempURL)
        }
    }

    private func decodeClips(from data: Data) throws -> [Clip] {
        if let document = try? decoder.decode(ClipIndexDocument.self, from: data) {
            return document.clips
        }
        // Legacy format: bare `[Clip]` array written by older Zinc builds.
        return try decoder.decode([Clip].self, from: data)
    }

    private func quarantineCorruptFile() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now())
        let preservedURL = directoryURL.appendingPathComponent("clips.corrupt-\(stamp).json")

        // Prefer move so the live path is vacated without destroying bytes.
        // Fall back to copy+remove if replace across volumes fails.
        do {
            if fileManager.fileExists(atPath: preservedURL.path) {
                try fileManager.removeItem(at: preservedURL)
            }
            try fileManager.moveItem(at: fileURL, to: preservedURL)
        } catch {
            // Last resort: copy then remove so a subsequent save cannot clobber
            // the only remaining copy of the damaged (but possibly recoverable) file.
            try? fileManager.copyItem(at: fileURL, to: preservedURL)
            try? fileManager.removeItem(at: fileURL)
        }

        return preservedURL
    }

    private func refreshRollingBackup() throws {
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: fileURL, to: backupURL)
    }
}
