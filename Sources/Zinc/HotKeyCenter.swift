import Carbon
import AppKit

enum HotKeyRegistrationResult: Equatable {
    case success
    case handlerInstallFailed(OSStatus)
    case hotKeyRegisterFailed(OSStatus)

    var failureMessage: String? {
        switch self {
        case .success:
            return nil
        case .handlerInstallFailed(let status), .hotKeyRegisterFailed(let status):
            return "Could not register the panel shortcut (error \(status)). Another app may already be using \(ShortcutSettings.shared.panelHotKey.displayString). Change it in Zinc Settings → Shortcuts."
        }
    }
}

final class HotKeyCenter {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x5A494E43), id: 1)

    var onHotKey: (() -> Void)?

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> HotKeyRegistrationResult {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == center.hotKeyID.signature, hotKeyID.id == center.hotKeyID.id else {
                return noErr
            }

            DispatchQueue.main.async {
                center.onHotKey?()
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            return .handlerInstallFailed(handlerStatus)
        }

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            unregister()
            return .hotKeyRegisterFailed(registerStatus)
        }

        return .success
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}
