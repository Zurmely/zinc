import Foundation

enum ZincError: Error, LocalizedError, Equatable {
    case vaultUnavailable(path: String, message: String)
    case vaultNotWritable(path: String, message: String)
    case exportDirectoryFailed(message: String)
    case markdownWriteFailed(message: String)
    case imageWriteFailed(message: String)
    case indexSaveFailed(message: String)
    case indexLoadFailed(message: String)
    case trashFailed(path: String, message: String)

    enum RecoveryAction: Equatable {
        case chooseVaultFolder
        case openSettings
    }

    var errorDescription: String? {
        switch self {
        case .vaultUnavailable(let path, let message):
            return "Vault unavailable at \(path): \(message)"
        case .vaultNotWritable(let path, let message):
            return "Vault not writable at \(path): \(message)"
        case .exportDirectoryFailed(let message):
            return "Failed to create export directory: \(message)"
        case .markdownWriteFailed(let message):
            return "Failed to write markdown: \(message)"
        case .imageWriteFailed(let message):
            return "Failed to write image: \(message)"
        case .indexSaveFailed(let message):
            return "Failed to save clip index: \(message)"
        case .indexLoadFailed(let message):
            return "Failed to load clip index: \(message)"
        case .trashFailed(let path, let message):
            return "Failed to trash \(path): \(message)"
        }
    }

    /// Compact title shown in the failure HUD.
    var hudTitle: String {
        switch self {
        case .vaultUnavailable, .vaultNotWritable:
            return "Couldn't save — vault unavailable"
        case .exportDirectoryFailed, .markdownWriteFailed, .imageWriteFailed:
            return "Couldn't save — write failed"
        case .indexSaveFailed:
            return "Couldn't save — index unavailable"
        case .indexLoadFailed:
            return "Couldn't load clips"
        case .trashFailed:
            return "Couldn't move to Trash"
        }
    }

    var hudHint: String? {
        switch recoveryAction {
        case .chooseVaultFolder:
            return "Cmd+Click to choose folder"
        case .openSettings:
            return "Cmd+Click for Settings"
        case nil:
            return nil
        }
    }

    var recoveryAction: RecoveryAction? {
        switch self {
        case .vaultUnavailable, .vaultNotWritable, .exportDirectoryFailed,
             .markdownWriteFailed, .imageWriteFailed:
            return .chooseVaultFolder
        case .indexSaveFailed, .indexLoadFailed:
            return .openSettings
        case .trashFailed:
            return .chooseVaultFolder
        }
    }

    static func vaultUnavailable(path: String, underlying: Error) -> ZincError {
        .vaultUnavailable(path: path, message: underlying.localizedDescription)
    }

    static func vaultNotWritable(path: String, underlying: Error) -> ZincError {
        .vaultNotWritable(path: path, message: underlying.localizedDescription)
    }

    static func exportDirectoryFailed(_ underlying: Error) -> ZincError {
        .exportDirectoryFailed(message: underlying.localizedDescription)
    }

    static func markdownWriteFailed(_ underlying: Error) -> ZincError {
        .markdownWriteFailed(message: underlying.localizedDescription)
    }

    static func imageWriteFailed(_ underlying: Error) -> ZincError {
        .imageWriteFailed(message: underlying.localizedDescription)
    }

    static func indexSaveFailed(_ underlying: Error) -> ZincError {
        .indexSaveFailed(message: underlying.localizedDescription)
    }

    static func indexLoadFailed(_ underlying: Error) -> ZincError {
        .indexLoadFailed(message: underlying.localizedDescription)
    }

    static func trashFailed(path: String, underlying: Error) -> ZincError {
        .trashFailed(path: path, message: underlying.localizedDescription)
    }
}

extension Notification.Name {
    static let zincVaultHealthDidChange = Notification.Name("ZincVaultHealthDidChange")
    static let zincChooseVaultFolder = Notification.Name("ZincChooseVaultFolder")
    static let zincOpenSettings = Notification.Name("ZincOpenSettings")
}
