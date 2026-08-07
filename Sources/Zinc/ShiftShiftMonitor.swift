import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import ZincCore

private enum ZincLog {
    static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Zinc", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
        NSLog("Zinc: %@", message)
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: url)
            }
        }
    }
}

/// Detects a clean double-tap of Shift via NSEvent monitors.
final class ShiftShiftMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var accessibilityPollTimer: Timer?

    private var previousShiftDown = false
    private var armedUntil: Date?
    private var secondPressStarted = false
    private var contaminated = false
    private var isCapturing = false
    private var shiftPressStartedAt: Date?

    private let doubleTapWindow: TimeInterval = 0.55

    var onDoubleShift: (() -> Void)?
    var onMonitoringBecameActive: (() -> Void)?
    private(set) var isMonitoring = false
    private var wasWaitingForPermission = false

    private var settings: ShiftFilterSettings { .shared }

    func start() {
        wasWaitingForPermission = !Permissions.isAccessibilityTrusted
        installMonitorsIfPossible()
        startAccessibilityPolling()
    }

    func stop() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        removeMonitors()
    }

    private func installMonitorsIfPossible() {
        guard globalMonitor == nil else { return }
        guard Permissions.isAccessibilityTrusted else {
            isMonitoring = false
            ZincLog.write("Accessibility not trusted — Shift monitor deferred")
            return
        }

        previousShiftDown = NSEvent.modifierFlags.contains(.shift)

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
            return event
        }

        isMonitoring = globalMonitor != nil
        ZincLog.write("Shift monitor installed (global=\(globalMonitor != nil))")

        if isMonitoring && wasWaitingForPermission {
            wasWaitingForPermission = false
            DispatchQueue.main.async { [weak self] in
                self?.onMonitoringBecameActive?()
            }
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        isMonitoring = false
    }

    private func startAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Permissions.isAccessibilityTrusted {
                if self.globalMonitor == nil {
                    self.wasWaitingForPermission = true
                    self.installMonitorsIfPossible()
                }
            } else if self.globalMonitor != nil {
                self.removeMonitors()
                self.wasWaitingForPermission = true
            }
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if previousShiftDown || armedUntil != nil {
                cancelArm()
                contaminated = true
            }
        case .flagsChanged:
            handleFlagsChanged(event)
        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let isShiftKey = keyCode == kVK_Shift || keyCode == kVK_RightShift

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shiftDown = flags.contains(.shift)
        let otherModifiers = flags.contains(.command)
            || flags.contains(.control)
            || flags.contains(.option)

        let isShiftEdge = isShiftKey || (shiftDown != previousShiftDown)

        if !isShiftEdge {
            if otherModifiers && (previousShiftDown || armedUntil != nil) {
                cancelArm()
                contaminated = true
            }
            previousShiftDown = shiftDown
            return
        }

        if shiftDown && !previousShiftDown {
            shiftPressStartedAt = Date()
            contaminated = otherModifiers || shouldIgnoreForMouse() || settings.isFrontmostAppExcluded()
            if contaminated {
                cancelArm()
                if settings.isFrontmostAppExcluded() {
                    ZincLog.write("Shift ignored — frontmost app excluded")
                } else if shouldIgnoreForMouse() {
                    ZincLog.write("Shift ignored — mouse button down")
                }
            } else if let until = armedUntil, Date() <= until {
                secondPressStarted = true
                ZincLog.write("second Shift press")
            } else {
                secondPressStarted = false
                armedUntil = nil
            }
        } else if !shiftDown && previousShiftDown {
            let holdDuration = shiftPressStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            shiftPressStartedAt = nil

            if contaminated || otherModifiers {
                cancelArm()
                contaminated = false
            } else if shouldIgnoreForMouse() {
                ZincLog.write("Shift release ignored — mouse button down")
                cancelArm()
            } else if settings.isFrontmostAppExcluded() {
                ZincLog.write("Shift release ignored — frontmost app excluded")
                cancelArm()
            } else if secondPressStarted {
                if isHoldTooLong(holdDuration) {
                    ZincLog.write("second Shift hold too long (\(Int(holdDuration * 1000))ms) — cancelled")
                    cancelArm()
                } else {
                    ZincLog.write("double-Shift recognized")
                    secondPressStarted = false
                    armedUntil = nil
                    triggerCapture()
                }
            } else if isHoldTooLong(holdDuration) {
                ZincLog.write("first Shift hold too long (\(Int(holdDuration * 1000))ms) — not armed")
                cancelArm()
            } else {
                armedUntil = Date().addingTimeInterval(doubleTapWindow)
                secondPressStarted = false
                ZincLog.write("first Shift tap — armed")
            }
        }

        previousShiftDown = shiftDown
    }

    private func shouldIgnoreForMouse() -> Bool {
        settings.ignoreMouseDown && NSEvent.pressedMouseButtons != 0
    }

    private func isHoldTooLong(_ duration: TimeInterval) -> Bool {
        settings.requireShortTaps && duration > settings.maxHoldDuration
    }

    private func cancelArm() {
        armedUntil = nil
        secondPressStarted = false
    }

    private func triggerCapture() {
        guard !isCapturing else { return }

        // Re-check exclusion at fire time in case focus changed while armed.
        if settings.isFrontmostAppExcluded() {
            ZincLog.write("capture skipped — frontmost app excluded")
            return
        }

        isCapturing = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }

            let selection = SelectionCapture.captureSelection()
            defer { self.isCapturing = false }

            guard let selection else {
                ZincLog.write("capture returned nil")
                SaveHUD.showFailure()
                return
            }

            ZincLog.write("captured \(selection.plainText.count) chars")
            let context = ContextResolver.resolve()
            let clip = Clip(
                text: selection.clipText,
                appName: context.appName,
                bundleID: context.bundleID,
                pageURL: context.pageURL,
                pageTitle: context.pageTitle
            )

            ClipStore.shared.add(clip)
            MarkdownExporter.shared.export(selection: selection, clip: clip)
            SaveHUD.show(text: clip.preview, source: clip.contextLabel, clipID: clip.id)
            self.onDoubleShift?()
        }
    }
}
