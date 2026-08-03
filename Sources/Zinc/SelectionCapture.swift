import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum SelectionCapture {
    static let syntheticUserData: Int64 = 0x5A494E43 // "ZINC"

    /// Captures the current selection by synthesizing Cmd+C, then restores the pasteboard.
    /// Must be called on the main thread.
    static func captureSelection() -> RichSelection? {
        let pasteboard = NSPasteboard.general
        let originalChangeCount = pasteboard.changeCount
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        guard postCopyCommand() else {
            NSLog("Zinc: failed to post Cmd+C")
            return nil
        }

        let captured = waitForNewPasteboardContent(
            pasteboard: pasteboard,
            originalChangeCount: originalChangeCount
        )

        snapshot.restore(to: pasteboard)

        if captured == nil {
            NSLog("Zinc: no content captured")
        } else {
            NSLog("Zinc: captured \(captured!.plainText.count) characters")
        }
        return captured
    }

    private static func postCopyCommand() -> Bool {
        // Private source so physical Shift is not inherited into the synthetic event.
        guard let source = CGEventSource(stateID: .privateState) else { return false }
        source.localEventsSuppressionInterval = 0.0

        let keyCode = CGKeyCode(kVK_ANSI_C)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand
        keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticUserData)
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticUserData)

        keyDown.post(tap: .cghidEventTap)
        usleep(8_000)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func waitForNewPasteboardContent(
        pasteboard: NSPasteboard,
        originalChangeCount: Int
    ) -> RichSelection? {
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline {
            if pasteboard.changeCount != originalChangeCount {
                usleep(25_000)
                return RichSelection.read(from: pasteboard)
            }
            usleep(10_000)
        }
        return nil
    }

    static func isSyntheticEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == syntheticUserData
    }
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            items.append(entry)
        }
        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored: [NSPasteboardItem] = items.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
