import Foundation

/// Path helpers for vault containment and portable (relative) markdown paths.
///
/// Containment compares resolved path components — never string `hasPrefix`.
public enum VaultPathSafety {
    /// Returns whether `item` is strictly inside `vaultRoot` (or equal when `allowRoot` is true).
    public static func contains(_ item: URL, vaultRoot: URL, allowRoot: Bool = false) -> Bool {
        let root = canonicalURL(vaultRoot)
        let candidate = canonicalURL(item)
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents

        guard candidateComponents.count >= rootComponents.count else { return false }
        guard Array(candidateComponents.prefix(rootComponents.count)) == rootComponents else {
            return false
        }

        if candidateComponents.count == rootComponents.count {
            return allowRoot
        }
        return true
    }

    public static func isAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/")
    }

    /// Resolves a stored markdown path: absolute paths as-is, relative paths against `vaultRoot`.
    public static func resolveMarkdownURL(_ storedPath: String, vaultRoot: URL) -> URL {
        if isAbsolutePath(storedPath) {
            return canonicalURL(URL(fileURLWithPath: storedPath))
        }
        return canonicalURL(URL(fileURLWithPath: storedPath, relativeTo: vaultRoot).absoluteURL)
    }

    /// Returns a vault-relative path (no leading slash), or `nil` if `item` is outside the vault.
    public static func relativePath(of item: URL, to vaultRoot: URL) -> String? {
        guard contains(item, vaultRoot: vaultRoot, allowRoot: true) else { return nil }

        let root = canonicalURL(vaultRoot)
        let file = canonicalURL(item)
        let relativeComponents = file.pathComponents.dropFirst(root.pathComponents.count)
        if relativeComponents.isEmpty {
            return ""
        }
        return relativeComponents.joined(separator: "/")
    }

    /// Resolves `.` / `..` and symlinks, including when the leaf path does not exist yet.
    private static func canonicalURL(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: standardized.path) {
            return standardized.resolvingSymlinksInPath().standardizedFileURL
        }

        var current = standardized
        var missingSuffix: [String] = []
        while current.path != "/", !fileManager.fileExists(atPath: current.path) {
            missingSuffix.insert(current.lastPathComponent, at: 0)
            current = current.deletingLastPathComponent()
        }

        var resolved = current.resolvingSymlinksInPath().standardizedFileURL
        for component in missingSuffix {
            resolved.appendPathComponent(component)
        }
        return resolved.standardizedFileURL
    }
}
