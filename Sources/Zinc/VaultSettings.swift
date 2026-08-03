import Foundation

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
}
