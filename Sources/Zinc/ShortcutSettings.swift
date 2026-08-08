import AppKit
import Carbon.HIToolbox
import Foundation

struct HotKeyCombination: Equatable, Codable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let defaultPanel = HotKeyCombination(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(optionKey | shiftKey)
    )

    var displayString: String {
        HotKeyCombination.displayString(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    static func displayString(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyDisplayName(for: keyCode))
        return parts.joined()
    }

    private static func keyDisplayName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A ... kVK_ANSI_Z:
            let scalar = UnicodeScalar(Int(keyCode) - Int(kVK_ANSI_A) + Int(UnicodeScalar("A").value))!
            return String(Character(scalar))
        case kVK_ANSI_0 ... kVK_ANSI_9:
            return String(Int(keyCode) - kVK_ANSI_0)
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            return "Key \(keyCode)"
        }
    }
}

/// User-configurable global shortcut for opening the clip panel.
final class ShortcutSettings: ObservableObject {
    static let shared = ShortcutSettings()

    private enum Keys {
        static let panelKeyCode = "zinc.shortcut.panelKeyCode"
        static let panelModifiers = "zinc.shortcut.panelModifiers"
    }

    @Published var panelHotKey: HotKeyCombination {
        didSet {
            guard panelHotKey != oldValue else { return }
            UserDefaults.standard.set(Int(panelHotKey.keyCode), forKey: Keys.panelKeyCode)
            UserDefaults.standard.set(Int(panelHotKey.carbonModifiers), forKey: Keys.panelModifiers)
            NotificationCenter.default.post(name: .zincShortcutSettingsDidChange, object: nil)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        if let keyCode = defaults.object(forKey: Keys.panelKeyCode) as? Int,
           let modifiers = defaults.object(forKey: Keys.panelModifiers) as? Int {
            panelHotKey = HotKeyCombination(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers))
        } else {
            panelHotKey = .defaultPanel
        }
    }
}

extension Notification.Name {
    static let zincShortcutSettingsDidChange = Notification.Name("ZincShortcutSettingsDidChange")
}
