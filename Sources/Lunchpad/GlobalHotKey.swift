import Carbon.HIToolbox
import Foundation

struct HotKeyConfiguration {
    static let preferencesDomain = "com.arichyx.Lunchpad"
    static let preferencesKey = "globalHotKey"

    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static func load() -> HotKeyConfiguration? {
        let environment = ProcessInfo.processInfo.environment["LUNCHPAD_HOTKEY"]
        let preference = UserDefaults(suiteName: preferencesDomain)?.string(
            forKey: preferencesKey
        )
        let name = (environment ?? preference ?? "control-shift-space").lowercased()

        switch name {
        case "control-shift-space", "ctrl-shift-space":
            return HotKeyConfiguration(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(controlKey | shiftKey),
                displayName: "⌃⇧Space"
            )
        case "control-option-l", "ctrl-option-l", "ctrl-alt-l":
            return HotKeyConfiguration(
                keyCode: UInt32(kVK_ANSI_L),
                modifiers: UInt32(controlKey | optionKey),
                displayName: "⌃⌥L"
            )
        case "disabled", "off", "none":
            return nil
        default:
            print("⚠️ 未知快捷键配置 \(name)，回退到 ⌃⇧Space")
            return HotKeyConfiguration(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(controlKey | shiftKey),
                displayName: "⌃⇧Space"
            )
        }
    }
}

private let globalHotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

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
    guard status == noErr else { return status }

    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
    hotKey.invoke()
    return noErr
}

/// Carbon global hot key that remains available while Lunchpad is not frontmost.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void

    init(configuration: HotKeyConfiguration, action: @escaping () -> Void) throws {
        self.action = action

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyEventHandler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandler
        )
        guard installStatus == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(installStatus))
        }
        eventHandlerRef = installedHandler

        var registeredHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4E_5044), id: 1) // LNPD
        let registerStatus = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )
        guard registerStatus == noErr else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
            }
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(registerStatus))
        }
        hotKeyRef = registeredHotKey
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    fileprivate func invoke() {
        action()
    }
}
