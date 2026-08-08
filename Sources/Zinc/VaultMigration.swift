import Foundation
import ZincCore

enum VaultMigration {
    /// Changes the vault root. When `migrateFiles` is true, moves vault contents into the new
    /// folder and rewrites clip paths to be relative. When false, keeps files in place and
    /// stores absolute paths so previews and deletion still work.
    static func changeVault(to newURL: URL, migrateFiles: Bool) {
        let oldURL = VaultSettings.vaultURL.standardizedFileURL
        let destination = newURL.standardizedFileURL

        guard destination.path != oldURL.path else { return }

        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            NSLog("Zinc: failed to create new vault at \(destination.path): \(error)")
            return
        }

        if migrateFiles {
            moveVaultContents(from: oldURL, to: destination)
        }

        VaultSettings.setVaultURL(destination)
        ClipStore.shared.rewriteMarkdownPathsAfterVaultChange(
            oldRoot: oldURL,
            newRoot: destination,
            didMigrate: migrateFiles
        )
    }

    private static func moveVaultContents(from oldRoot: URL, to newRoot: URL) {
        let fileManager = FileManager.default
        let resolvedOld = oldRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedNew = newRoot.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedOld.path != resolvedNew.path else { return }
        guard fileManager.fileExists(atPath: resolvedOld.path) else { return }

        let items: [URL]
        do {
            items = try fileManager.contentsOfDirectory(
                at: resolvedOld,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants]
            )
        } catch {
            NSLog("Zinc: failed to list vault contents at \(resolvedOld.path): \(error)")
            return
        }

        for item in items {
            let destination = resolvedNew.appendingPathComponent(item.lastPathComponent)
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try mergeMove(from: item, to: destination, fileManager: fileManager)
                } else {
                    try fileManager.moveItem(at: item, to: destination)
                }
            } catch {
                NSLog("Zinc: failed to migrate \(item.path) → \(destination.path): \(error)")
            }
        }
    }

    private static func mergeMove(from source: URL, to destination: URL, fileManager: FileManager) throws {
        var sourceIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &sourceIsDirectory) else { return }

        if sourceIsDirectory.boolValue {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let children = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants]
            )
            for child in children {
                let childDestination = destination.appendingPathComponent(child.lastPathComponent)
                if fileManager.fileExists(atPath: childDestination.path) {
                    try mergeMove(from: child, to: childDestination, fileManager: fileManager)
                } else {
                    try fileManager.moveItem(at: child, to: childDestination)
                }
            }
            let remaining = (try? fileManager.contentsOfDirectory(atPath: source.path)) ?? []
            if remaining.filter({ $0 != ".DS_Store" }).isEmpty {
                try? fileManager.removeItem(at: source)
            }
            return
        }

        // File conflict: keep the existing destination; leave the source in place.
        NSLog("Zinc: skipping migrate of \(source.path); destination already exists")
    }
}
