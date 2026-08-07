import Foundation
import ZincCore

enum VaultSettings {
    private static let vaultPathKey = "zinc.vaultPath"

    static var vaultURL: URL {
        if let stored = UserDefaults.standard.string(forKey: vaultPathKey) {
            return URL(fileURLWithPath: stored, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Zinc", isDirectory: true)
    }

    @discardableResult
    static func ensureVaultExists() -> Bool {
        do {
            try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
            return true
        } catch {
            NSLog("Zinc: failed to create vault at \(vaultURL.path): \(error)")
            return false
        }
    }

    static func setVaultURL(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: vaultPathKey)
        _ = ensureVaultExists()
    }

    /// Resolves a stored clip markdown path (relative preferred, absolute legacy supported).
    static func resolveMarkdownURL(_ storedPath: String) -> URL {
        VaultPathSafety.resolveMarkdownURL(storedPath, vaultRoot: vaultURL)
    }

    /// Stores a portable vault-relative path when the file is inside the current vault.
    static func storedMarkdownPath(for absoluteURL: URL) -> String {
        if let relative = VaultPathSafety.relativePath(of: absoluteURL, to: vaultURL), !relative.isEmpty {
            return relative
        }
        return absoluteURL.path
    }
}
