import AppKit
import Carbon.HIToolbox
import Foundation
import ZincCore

enum DoubleTapTriggerKey: String, CaseIterable, Identifiable, Codable {
    case shift
    case command
    case control

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shift: "Shift"
        case .command: "Command"
        case .control: "Control"
        }
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .command: .command
        case .control: .control
        }
    }

    var virtualKeyCodes: [Int] {
        switch self {
        case .shift: [kVK_Shift, kVK_RightShift]
        case .command: [kVK_Command, kVK_RightCommand]
        case .control: [kVK_Control, kVK_RightControl]
        }
    }

    func otherModifierFlags(from flags: NSEvent.ModifierFlags) -> Bool {
        let mask = flags.intersection(.deviceIndependentFlagsMask)
        switch self {
        case .shift:
            return mask.contains(.command) || mask.contains(.control) || mask.contains(.option)
        case .command:
            return mask.contains(.shift) || mask.contains(.control) || mask.contains(.option)
        case .control:
            return mask.contains(.shift) || mask.contains(.command) || mask.contains(.option)
        }
    }
}

/// User-configurable filters for the global double-modifier capture trigger.
final class ShiftFilterSettings: ObservableObject {
    static let shared = ShiftFilterSettings()

    private enum Keys {
        static let doubleShiftEnabled = "zinc.shift.doubleShiftEnabled"
        static let triggerKey = "zinc.shift.triggerKey"
        static let doubleTapWindowMs = "zinc.shift.doubleTapWindowMs"
        static let ignoreMouseDown = "zinc.shift.ignoreMouseDown"
        static let requireShortTaps = "zinc.shift.requireShortTaps"
        static let maxHoldDurationMs = "zinc.shift.maxHoldDurationMs"
        static let excludedBundleIDs = "zinc.shift.excludedBundleIDs"
    }

    static let defaultMaxHoldDurationMs = 200
    static let minHoldDurationMs = 50
    static let maxHoldDurationMs = 500

    static let defaultDoubleTapWindowMs = 550
    static let minDoubleTapWindowMs = 200
    static let maxDoubleTapWindowMs = 1000

    @Published var doubleShiftEnabled: Bool {
        didSet { UserDefaults.standard.set(doubleShiftEnabled, forKey: Keys.doubleShiftEnabled) }
    }

    @Published var triggerKey: DoubleTapTriggerKey {
        didSet { UserDefaults.standard.set(triggerKey.rawValue, forKey: Keys.triggerKey) }
    }

    @Published var doubleTapWindowMs: Int {
        didSet {
            let clamped = Self.clampDoubleTapWindow(doubleTapWindowMs)
            if clamped != doubleTapWindowMs {
                doubleTapWindowMs = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.doubleTapWindowMs)
        }
    }

    @Published var ignoreMouseDown: Bool {
        didSet { UserDefaults.standard.set(ignoreMouseDown, forKey: Keys.ignoreMouseDown) }
    }

    @Published var requireShortTaps: Bool {
        didSet { UserDefaults.standard.set(requireShortTaps, forKey: Keys.requireShortTaps) }
    }

    /// Maximum modifier key hold time (ms) that still counts as a tap when `requireShortTaps` is on.
    @Published var maxHoldDurationMs: Int {
        didSet {
            let clamped = Self.clampHoldDuration(maxHoldDurationMs)
            if clamped != maxHoldDurationMs {
                maxHoldDurationMs = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.maxHoldDurationMs)
        }
    }

    @Published private(set) var excludedBundleIDs: [String] {
        didSet { UserDefaults.standard.set(excludedBundleIDs, forKey: Keys.excludedBundleIDs) }
    }

    var maxHoldDuration: TimeInterval {
        TimeInterval(maxHoldDurationMs) / 1000.0
    }

    var doubleTapWindow: TimeInterval {
        TimeInterval(doubleTapWindowMs) / 1000.0
    }

    private init() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Keys.doubleShiftEnabled) == nil {
            doubleShiftEnabled = true
        } else {
            doubleShiftEnabled = defaults.bool(forKey: Keys.doubleShiftEnabled)
        }

        if let raw = defaults.string(forKey: Keys.triggerKey),
           let key = DoubleTapTriggerKey(rawValue: raw) {
            triggerKey = key
        } else {
            triggerKey = .shift
        }

        let storedTapMs = defaults.object(forKey: Keys.doubleTapWindowMs) as? Int
        doubleTapWindowMs = Self.clampDoubleTapWindow(storedTapMs ?? Self.defaultDoubleTapWindowMs)

        if defaults.object(forKey: Keys.ignoreMouseDown) == nil {
            ignoreMouseDown = true
        } else {
            ignoreMouseDown = defaults.bool(forKey: Keys.ignoreMouseDown)
        }

        if defaults.object(forKey: Keys.requireShortTaps) == nil {
            requireShortTaps = true
        } else {
            requireShortTaps = defaults.bool(forKey: Keys.requireShortTaps)
        }

        let storedMs = defaults.object(forKey: Keys.maxHoldDurationMs) as? Int
        maxHoldDurationMs = Self.clampHoldDuration(storedMs ?? Self.defaultMaxHoldDurationMs)

        excludedBundleIDs = defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? []
    }

    func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    func shouldSuppressDoubleShiftTrigger(
        frontmostBundleID: String? = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    ) -> Bool {
        Self.shouldSuppressDoubleShiftTrigger(
            frontmostBundleID: frontmostBundleID,
            zincBundleID: Bundle.main.bundleIdentifier,
            excludedBundleIDs: excludedBundleIDs
        )
    }

    static func shouldSuppressDoubleShiftTrigger(
        frontmostBundleID: String?,
        zincBundleID: String?,
        excludedBundleIDs: [String]
    ) -> Bool {
        DoubleShiftTriggerPolicy.shouldSuppress(
            frontmostBundleID: frontmostBundleID,
            zincBundleID: zincBundleID,
            excludedBundleIDs: excludedBundleIDs
        )
    }

    func addExcludedBundleID(_ bundleID: String) {
        guard !bundleID.isEmpty, !excludedBundleIDs.contains(bundleID) else { return }
        excludedBundleIDs.append(bundleID)
        excludedBundleIDs.sort { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending }
    }

    func removeExcludedBundleIDs(_ bundleIDs: Set<String>) {
        excludedBundleIDs.removeAll { bundleIDs.contains($0) }
    }

    func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }

    func appIcon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    static func clampHoldDuration(_ ms: Int) -> Int {
        min(max(ms, minHoldDurationMs), maxHoldDurationMs)
    }

    static func clampDoubleTapWindow(_ ms: Int) -> Int {
        min(max(ms, minDoubleTapWindowMs), maxDoubleTapWindowMs)
    }
}
