import Foundation

/// Rebuilds clip index entries from Markdown files in the vault.
///
/// Each vault `.md` file carries YAML front matter with `id`, `app`, `bundle`,
/// optional `url`/`title`, and `saved`. The body becomes the clip text.
enum VaultReindexer {
    /// Walks `vaultURL` recursively, parses front matter, and returns clips sorted
    /// newest-first. Files that lack a usable `id` are skipped.
    static func reindex(vaultURL: URL, fileManager: FileManager = .default) -> [Clip] {
        guard fileManager.fileExists(atPath: vaultURL.path) else { return [] }

        let enumerator = fileManager.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var clipsByID: [UUID: Clip] = [:]

        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension.lowercased() == "md" else { continue }
            guard let values = try? item.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }

            if let clip = clip(fromMarkdownAt: item) {
                // Prefer the existing entry if we already saw this id (idempotent).
                if clipsByID[clip.id] == nil {
                    clipsByID[clip.id] = clip
                }
            }
        }

        return clipsByID.values.sorted { $0.savedAt > $1.savedAt }
    }

    /// Merges vault-derived clips into an existing index by `id`. Vault entries
    /// fill gaps; existing index entries win on conflict so in-memory edits aren't
    /// clobbered.
    static func merge(existing: [Clip], fromVault vaultClips: [Clip]) -> [Clip] {
        var byID = Dictionary(uniqueKeysWithValues: vaultClips.map { ($0.id, $0) })
        for clip in existing {
            byID[clip.id] = clip
        }
        return byID.values.sorted { $0.savedAt > $1.savedAt }
    }

    // MARK: - Parsing

    static func clip(fromMarkdownAt url: URL) -> Clip? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return clip(fromMarkdown: contents, markdownPath: url.path)
    }

    static func clip(fromMarkdown contents: String, markdownPath: String) -> Clip? {
        let (frontMatter, body) = splitFrontMatter(contents)
        guard let idString = frontMatter["id"], let id = UUID(uuidString: idString) else {
            return nil
        }

        let appName = frontMatter["app"]?.nilIfEmpty ?? "Unknown"
        let bundleID = frontMatter["bundle"]?.nilIfEmpty ?? ""
        let pageURL = frontMatter["url"]?.nilIfEmpty
        let pageTitle = frontMatter["title"]?.nilIfEmpty

        let savedAt: Date
        if let saved = frontMatter["saved"], let parsed = parseISO8601(saved) {
            savedAt = parsed
        } else {
            savedAt = Date()
        }

        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || frontMatter["id"] != nil else { return nil }

        return Clip(
            id: id,
            text: text,
            savedAt: savedAt,
            appName: appName,
            bundleID: bundleID,
            pageURL: pageURL,
            pageTitle: pageTitle,
            markdownPath: markdownPath
        )
    }

    private static func splitFrontMatter(_ contents: String) -> ([String: String], String) {
        let lines = contents.components(separatedBy: .newlines)
        guard lines.first == "---" else {
            return ([:], contents)
        }

        var frontMatter: [String: String] = [:]
        var index = 1
        while index < lines.count, lines[index] != "---" {
            let line = lines[index]
            if let separator = line.firstIndex(of: ":") {
                let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                frontMatter[key] = value
            }
            index += 1
        }

        let bodyStart = index + 1
        let body = bodyStart < lines.count ? lines[bodyStart...].joined(separator: "\n") : ""
        return (frontMatter, body)
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: string)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
