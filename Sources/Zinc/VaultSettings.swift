import Foundation
import ZincCore

enum VaultSettings {
    private static let vaultPathKey = "zinc.vaultPath"
    private static let healthLock = NSLock()
    private static var _lastHealthError: ZincError?

    /// Most recent vault health failure, if any. Cleared when the vault verifies writable.
    static var lastHealthError: ZincError? {
        healthLock.lock()
        defer { healthLock.unlock() }
        return _lastHealthError
    }

    static var isVaultHealthy: Bool {
        lastHealthError == nil
    }

    static var vaultURL: URL {
        if let stored = UserDefaults.standard.string(forKey: vaultPathKey) {
            return URL(fileURLWithPath: stored, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Zinc", isDirectory: true)
    }

    /// Creates the vault if needed and confirms it is writable via a probe file.
    static func verifyWritable(at url: URL = vaultURL) -> Result<Void, ZincError> {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            return .failure(.vaultUnavailable(path: url.path, underlying: error))
        }

        let probe = url.appendingPathComponent(".zinc-write-test-\(UUID().uuidString)")
        do {
            try Data("ok".utf8).write(to: probe, options: .atomic)
            try? fileManager.removeItem(at: probe)
            return .success(())
        } catch {
            try? fileManager.removeItem(at: probe)
            return .failure(.vaultNotWritable(path: url.path, underlying: error))
        }
    }

    @discardableResult
    static func ensureVaultExists(reportFailure: Bool = false) -> Bool {
        switch verifyWritable() {
        case .success:
            updateHealth(nil)
            return true
        case .failure(let error):
            updateHealth(error)
            if reportFailure {
                ErrorReporter.report(error)
            } else {
                ErrorReporter.log(error)
            }
            return false
        }
    }

    /// Persists a new vault location after verifying it is writable.
    @discardableResult
    static func setVaultURL(_ url: URL, reportFailure: Bool = true) -> Bool {
        switch verifyWritable(at: url) {
        case .success:
            UserDefaults.standard.set(url.path, forKey: vaultPathKey)
            updateHealth(nil)
            return true
        case .failure(let error):
            // Do not mark the currently configured vault unhealthy when a candidate fails.
            if reportFailure {
                ErrorReporter.report(error)
            } else {
                ErrorReporter.log(error)
            }
            return false
        }
    }

    private static func updateHealth(_ error: ZincError?) {
        healthLock.lock()
        let changed = _lastHealthError != error
        _lastHealthError = error
        healthLock.unlock()

        guard changed else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .zincVaultHealthDidChange, object: error)
        }
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
