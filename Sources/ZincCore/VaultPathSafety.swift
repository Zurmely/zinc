import Foundation

/// Path containment for vault operations. String prefix matching is unsafe because
/// `/Users/me/Zinc` is a prefix of `/Users/me/Zinc-backup`.
public enum VaultPathSafety {
    /// Returns whether `url` is inside `vaultRoot` after resolving `..` / `.` and symlinks.
    ///
    /// - Parameter allowRoot: When `true`, the vault root itself is considered contained.
    ///   Destructive operations should pass `false` so the root is never deleted.
    public static func contains(_ url: URL, vaultRoot: URL, allowRoot: Bool = false) -> Bool {
        let resolvedURL = resolvedLocation(url)
        let resolvedRoot = resolvedLocation(vaultRoot)

        let urlComponents = resolvedURL.pathComponents
        let rootComponents = resolvedRoot.pathComponents

        if urlComponents == rootComponents {
            return allowRoot
        }

        guard urlComponents.count > rootComponents.count else {
            return false
        }

        return rootComponents.elementsEqual(urlComponents.prefix(rootComponents.count))
    }

    /// Resolves `.` / `..` and symlinks for existing path prefixes.
    /// Unlike `URL.resolvingSymlinksInPath()`, intermediate symlinks are still resolved
    /// when a trailing leaf does not exist yet.
    public static func resolvedLocation(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        let components = standardized.pathComponents
        guard components.first == "/" else {
            return standardized.resolvingSymlinksInPath()
        }

        var resolved = URL(fileURLWithPath: "/")
        let fileManager = FileManager.default

        for component in components.dropFirst() {
            let next = resolved.appendingPathComponent(component, isDirectory: false)
            if fileManager.fileExists(atPath: next.path) {
                resolved = next.resolvingSymlinksInPath()
            } else {
                resolved = next
            }
        }

        return resolved.standardizedFileURL
    }
}
