import Foundation
import ZincCore

enum VaultFileManager {
    private static let queue = DispatchQueue(label: "com.zurmely.zinc.vault-trash")

    static func trashInBackground(markdownPaths: [String]) {
        guard !markdownPaths.isEmpty else { return }
        queue.async {
            trash(markdownPaths: markdownPaths)
        }
    }

    static func trash(markdownPaths: [String]) {
        let vaultRoot = VaultSettings.vaultURL
        let fileManager = FileManager.default

        for path in markdownPaths {
            let markdownURL = VaultPathSafety.resolveMarkdownURL(path, vaultRoot: vaultRoot)
            let storedIsAbsolute = VaultPathSafety.isAbsolutePath(path)

            if storedIsAbsolute {
                // Keep-in-place / legacy absolute paths may live outside the current vault root.
                // Only trash tracked markdown exports (and their sibling assets folder).
                guard markdownURL.pathExtension.lowercased() == "md" else {
                    ErrorReporter.log(
                        .trashFailed(
                            path: path,
                            message: "Refusing to trash non-markdown path"
                        )
                    )
                    continue
                }
            } else {
                guard VaultPathSafety.contains(markdownURL, vaultRoot: vaultRoot) else {
                    ErrorReporter.log(
                        .trashFailed(
                            path: path,
                            message: "Refusing to trash path outside vault"
                        )
                    )
                    continue
                }
            }

            let parentDirectory = markdownURL.deletingLastPathComponent()
            let baseName = markdownURL.deletingPathExtension().lastPathComponent
            let assetsURL = parentDirectory.appendingPathComponent("\(baseName)-assets", isDirectory: true)

            trashItem(at: assetsURL, fileManager: fileManager)
            trashItem(at: markdownURL, fileManager: fileManager)

            if VaultPathSafety.contains(parentDirectory, vaultRoot: vaultRoot) {
                pruneEmptyDirectories(startingAt: parentDirectory, vaultRoot: vaultRoot, fileManager: fileManager)
            }
        }
    }

    private static func trashItem(at url: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        } catch {
            ErrorReporter.report(.trashFailed(path: url.path, underlying: error))
        }
    }

    private static func pruneEmptyDirectories(
        startingAt directory: URL,
        vaultRoot: URL,
        fileManager: FileManager
    ) {
        var current = directory.standardizedFileURL

        // `contains` rejects the vault root itself, so pruning cannot remove or escape the root.
        while VaultPathSafety.contains(current, vaultRoot: vaultRoot) {
            guard fileManager.fileExists(atPath: current.path) else {
                current = current.deletingLastPathComponent()
                continue
            }

            let contents = (try? fileManager.contentsOfDirectory(atPath: current.path)) ?? ["placeholder"]
            let meaningful = contents.filter { $0 != ".DS_Store" }
            guard meaningful.isEmpty else { break }

            do {
                try fileManager.trashItem(at: current, resultingItemURL: nil)
            } catch {
                ErrorReporter.log(
                    .trashFailed(path: current.path, underlying: error)
                )
                break
            }

            current = current.deletingLastPathComponent()
        }
    }
}
