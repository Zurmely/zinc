import AppKit
import Foundation

/// Presents recovery options when `clips.json` could not be decoded.
enum ClipIndexRecoveryAlert {
    static func presentIfNeeded(from store: ClipStore = .shared) {
        guard let offer = store.pendingRecovery else { return }

        // Defer so launch / menu wiring can finish first (same pattern as Permissions).
        DispatchQueue.main.async {
            present(offer: offer, store: store)
        }
    }

    private static func present(offer: ClipIndexRecoveryOffer, store: ClipStore) {
        let alert = NSAlert()
        alert.messageText = "Clip History Could Not Be Read"
        alert.informativeText = """
        Zinc could not read your saved clip index. The damaged file was preserved as:

        \(offer.preservedCorruptURL.lastPathComponent)

        Your Markdown vault files are still on disk. You can rebuild the history from the vault\(offer.backupAvailable ? ", restore the last good backup," : "") or start with an empty index.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reindex from Vault")
        if offer.backupAvailable {
            alert.addButton(withTitle: "Restore Backup")
        }
        alert.addButton(withTitle: "Start Empty")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            let count = store.reindexFromVault()
            NSLog("Zinc: reindexed \(count) clip(s) from vault after corrupt index")
        case .alertSecondButtonReturn where offer.backupAvailable:
            if store.restoreFromBackup() {
                NSLog("Zinc: restored clip index from rolling backup")
            } else {
                // Backup disappeared or was also unreadable — fall through to reindex prompt.
                let count = store.reindexFromVault()
                NSLog("Zinc: backup restore failed; reindexed \(count) clip(s) from vault")
            }
        default:
            store.dismissRecoveryOffer()
            NSLog("Zinc: user dismissed corrupt-index recovery; starting empty")
        }
    }
}
