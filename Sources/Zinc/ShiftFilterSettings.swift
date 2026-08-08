import AppKit
import Foundation
import ZincCore

/// User-configurable filters for the global double-Shift capture trigger.
final class ShiftFilterSettings: ObservableObject {
    static let shared = ShiftFilterSettings()

    private enum Keys {
        static let ignoreMouseDown = "zinc.shift.ignoreMouseDown"
        static let requireShortTaps = "zinc.shift.requireShortTaps"
        static let maxHoldDurationMs = "zinc.shift.maxHoldDurationMs"
        static let excludedBundleIDs = "zinc.shift.excludedBundleIDs"
    }

    static let defaultMaxHoldDurationMs = 200
    static let minHoldDurationMs = 50
    static let maxHoldDurationMs = 500

    /// Well-known password managers shipped as the initial exclusion list.
    static let defaultExcludedBundleIDs = CaptureExclusions.defaultExcludedBundleIDs

    @Published var ignoreMouseDown: Bool {
        didSet { UserDefaults.standard.set(ignoreMouseDown, forKey: Keys.ignoreMouseDown) }
    }

    @Published var requireShortTaps: Bool {
        didSet { UserDefaults.standard.set(requireShortTaps, forKey: Keys.requireShortTaps) }
    }

    /// Maximum Shift key hold time (ms) that still counts as a tap when `requireShortTaps` is on.
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

    private init() {
        let defaults = UserDefaults.standard

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

        if let stored = defaults.stringArray(forKey: Keys.excludedBundleIDs) {
            excludedBundleIDs = stored
        } else {
            excludedBundleIDs = Self.defaultExcludedBundleIDs
        }
    }

    func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return excludedBundleIDs.contains(bundleID)
            || CaptureExclusions.shouldRefuseCapture(bundleID: bundleID)
    }

    func isFrontmostAppExcluded() -> Bool {
        isExcluded(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
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
}
