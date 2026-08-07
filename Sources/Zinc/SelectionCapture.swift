import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum SelectionCapture {
    static let syntheticUserData: Int64 = 0x5A494E43 // "ZINC"

    private static let pasteboardPollInterval: Duration = .milliseconds(10)
    private static let stabilityPollInterval: Duration = .milliseconds(15)
    private static let captureTimeout: Duration = .milliseconds(500)
    private static let keyEventGap: Duration = .milliseconds(8)

    /// Captures the current selection by synthesizing Cmd+C, then restores the pasteboard.
    /// Pasteboard polling and settle waits use cooperative `Task.sleep` so the main thread stays free.
    static func captureSelection() async -> RichSelection? {
        let (originalChangeCount, snapshot) = await MainActor.run { () -> (Int, PasteboardSnapshot) in
            let pasteboard = NSPasteboard.general
            return (pasteboard.changeCount, PasteboardSnapshot.capture(from: pasteboard))
        }

        guard await postCopyCommand() else {
            NSLog("Zinc: failed to post Cmd+C")
            return nil
        }

        let captured = await waitForNewPasteboardContent(originalChangeCount: originalChangeCount)

        await MainActor.run {
            snapshot.restore(to: NSPasteboard.general)
        }

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
        try? await Task.sleep(for: keyEventGap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func waitForNewPasteboardContent(originalChangeCount: Int) async -> RichSelection? {
        let clock = ContinuousClock()
        let deadline = clock.now + captureTimeout

        while clock.now < deadline {
            let changeCount = await MainActor.run { NSPasteboard.general.changeCount }
            if changeCount != originalChangeCount {
                return await waitForStableContent(deadline: deadline)
            }
            try? await Task.sleep(for: pasteboardPollInterval)
        }
        return nil
    }

    /// Reads pasteboard flavor sizes, waits briefly, and re-reads until the signature stops changing
    /// or the deadline elapses. Returns nil if content never stabilizes (avoids silently partial captures).
    private static func waitForStableContent(deadline: ContinuousClock.Instant) async -> RichSelection? {
        let clock = ContinuousClock()
        var previousSignature = await MainActor.run { pasteboardFlavorSignature() }

        while clock.now < deadline {
            try? await Task.sleep(for: stabilityPollInterval)

            let (currentSignature, selection) = await MainActor.run { () -> (String, RichSelection?) in
                (pasteboardFlavorSignature(), RichSelection.read(from: NSPasteboard.general))
            }

            if currentSignature == previousSignature {
                if selection == nil {
                    NSLog("Zinc: pasteboard stabilized empty")
                }
                return selection
            }
            previousSignature = currentSignature
        }

        NSLog("Zinc: pasteboard content never stabilized")
        return nil
    }

    /// Signature over changeCount plus each flavor's byte length so staged multi-flavor writes are detected.
    private static func pasteboardFlavorSignature() -> String {
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []
        let parts = types.map { type in
            let size = pasteboard.data(forType: type)?.count ?? 0
            return "\(type.rawValue):\(size)"
        }
        return "\(pasteboard.changeCount)|\(parts.joined(separator: ","))"
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
