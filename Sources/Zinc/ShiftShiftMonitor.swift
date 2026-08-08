import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import ZincCore

/// Detects a clean double-tap of a modifier key via NSEvent monitors.
final class ShiftShiftMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var accessibilityPollTimer: Timer?

    private var previousModifierDown = false
    private var armedUntil: Date?
    private var secondPressStarted = false
    private var contaminated = false
    private var isCapturing = false
    private var modifierPressStartedAt: Date?

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
        guard settings.doubleShiftEnabled else {
            isMonitoring = false
            return
        }
        guard Permissions.isAccessibilityTrusted else {
            isMonitoring = false
            ZincLogger.info("Accessibility not trusted — modifier monitor deferred")
            return
        }

        previousModifierDown = NSEvent.modifierFlags.contains(settings.triggerKey.modifierFlag)

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
            return event
        }

        isMonitoring = globalMonitor != nil

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
                if self.globalMonitor == nil, self.settings.doubleShiftEnabled {
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
        guard settings.doubleShiftEnabled else { return }

        switch event.type {
        case .keyDown:
            if previousModifierDown || armedUntil != nil {
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
        let trigger = settings.triggerKey
        let keyCode = Int(event.keyCode)
        let isTriggerKey = trigger.virtualKeyCodes.contains(keyCode)

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifierDown = flags.contains(trigger.modifierFlag)
        let otherModifiers = trigger.otherModifierFlags(from: flags)

        let isModifierEdge = isTriggerKey || (modifierDown != previousModifierDown)

        if !isModifierEdge {
            if otherModifiers && (previousModifierDown || armedUntil != nil) {
                cancelArm()
                contaminated = true
            }
            previousModifierDown = modifierDown
            return
        }

        if modifierDown && !previousModifierDown {
            modifierPressStartedAt = Date()
            contaminated = otherModifiers || shouldIgnoreForMouse() || settings.shouldSuppressDoubleShiftTrigger()
            if contaminated {
                cancelArm()
            } else if let until = armedUntil, Date() <= until {
                secondPressStarted = true
            } else {
                secondPressStarted = false
                armedUntil = nil
            }
        } else if !modifierDown && previousModifierDown {
            let holdDuration = modifierPressStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            modifierPressStartedAt = nil

            if contaminated || otherModifiers {
                cancelArm()
                contaminated = false
            } else if shouldIgnoreForMouse() {
                cancelArm()
            } else if settings.shouldSuppressDoubleShiftTrigger() {
                cancelArm()
            } else if secondPressStarted {
                if isHoldTooLong(holdDuration) {
                    cancelArm()
                } else {
                    secondPressStarted = false
                    armedUntil = nil
                    triggerCapture()
                }
            } else if isHoldTooLong(holdDuration) {
                cancelArm()
            } else {
                armedUntil = Date().addingTimeInterval(settings.doubleTapWindow)
                secondPressStarted = false
            }
        }

        previousModifierDown = modifierDown
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

        if settings.shouldSuppressDoubleShiftTrigger() {
            return
        }

        isCapturing = true

        Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 120_000_000)

            async let selectionTask = SelectionCapture.captureSelection()
            async let contextTask = ContextResolver.resolve()
            let selection = await selectionTask
            let context = await contextTask

            await MainActor.run {
                defer { self.isCapturing = false }

                guard let selection else {
                    ZincLogger.info("capture returned nil")
                    SaveHUD.showFailure()
                    return
                }

                if CaptureExclusions.shouldRefuseCapture(bundleID: context.bundleID)
                    || self.settings.isExcluded(bundleID: context.bundleID) {
                    ZincLogger.info("capture skipped — source app excluded (\(context.bundleID))")
                    SaveHUD.showFailure()
                    return
                }

                ZincLogger.info("captured \(selection.plainText.count) chars")
                let clip = Clip(
                    text: selection.clipText,
                    appName: context.appName,
                    bundleID: context.bundleID,
                    pageURL: context.pageURL,
                    pageTitle: context.pageTitle
                )

                switch ClipStore.shared.add(clip) {
                case .added(let indexSaved):
                    MarkdownExporter.shared.export(selection: selection, clip: clip) { result in
                        switch result {
                        case .success:
                            guard indexSaved else { return }
                            SaveHUD.show(text: clip.preview, source: clip.contextLabel, clipID: clip.id)
                        case .failure(let error):
                            ErrorReporter.report(error)
                        }
                    }
                case .deduplicated(let existingID):
                    SaveHUD.showAlreadySaved(text: clip.preview, source: clip.contextLabel, clipID: existingID)
                }
                self.onDoubleShift?()
            }
        }
    }
}
