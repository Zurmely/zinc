import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum SelectionCapture {
    static let syntheticUserData: Int64 = 0x5A494E43 // "ZINC"

    private static let pasteboardPollNanos: UInt64 = 10_000_000 // 10 ms
    private static let settlePollNanos: UInt64 = 25_000_000 // 25 ms
    private static let copyKeyGapNanos: UInt64 = 8_000_000 // 8 ms
    private static let pasteboardTimeout: TimeInterval = 0.5
    private static let maxSettlePasses = 10

    /// Captures the current selection by synthesizing Cmd+C, then restores the pasteboard.
    /// Polls with `Task.sleep` so the main thread is never busy-waited.
    static func captureSelection() async -> RichSelection? {
        let pasteboard = NSPasteboard.general
        let originalChangeCount = pasteboard.changeCount
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        guard await postCopyCommand() else {
            NSLog("Zinc: failed to post Cmd+C")
            return nil
        }

        let captured = await waitForNewPasteboardContent(
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

    private static func postCopyCommand() async -> Bool {
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
        try? await Task.sleep(nanoseconds: copyKeyGapNanos)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func waitForNewPasteboardContent(
        pasteboard: NSPasteboard,
        originalChangeCount: Int
    ) async -> RichSelection? {
        let deadline = Date().addingTimeInterval(pasteboardTimeout)
        while Date() < deadline {
            if pasteboard.changeCount != originalChangeCount {
                return await waitForStableSelection(from: pasteboard)
            }
            try? await Task.sleep(nanoseconds: pasteboardPollNanos)
        }
        return nil
    }

    /// Read, wait, read again until the pasteboard flavor set stops changing.
    private static func waitForStableSelection(from pasteboard: NSPasteboard) async -> RichSelection? {
        var previousSignature: String?
        var previousSelection: RichSelection?

        for _ in 0..<maxSettlePasses {
            let signature = pasteboardSignature(pasteboard)
            let selection = RichSelection.read(from: pasteboard)

            if let previousSignature, previousSignature == signature {
                return selection ?? previousSelection
            }

            previousSignature = signature
            previousSelection = selection
            try? await Task.sleep(nanoseconds: settlePollNanos)
        }

        return previousSelection ?? RichSelection.read(from: pasteboard)
    }

    private static func pasteboardSignature(_ pasteboard: NSPasteboard) -> String {
        let types = (pasteboard.types ?? []).map(\.rawValue).sorted()
        let itemCount = pasteboard.pasteboardItems?.count ?? 0
        let plainLength = pasteboard.string(forType: .string)?.count ?? 0
        let htmlLength = pasteboard.data(forType: .html)?.count ?? 0
        return "\(itemCount)|\(plainLength)|\(htmlLength)|\(types.joined(separator: ","))"
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
