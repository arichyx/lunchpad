import Carbon.HIToolbox
import Foundation

protocol GlobalHotKeyRegistration: AnyObject {}

@MainActor
protocol GlobalHotKeyRegistering {
    func register(
        configuration: HotKeyConfiguration,
        action: @escaping () -> Void
    ) throws -> any GlobalHotKeyRegistration
}

@MainActor
struct CarbonHotKeyRegistrar: GlobalHotKeyRegistering {
    func register(
        configuration: HotKeyConfiguration,
        action: @escaping () -> Void
    ) throws -> any GlobalHotKeyRegistration {
        try GlobalHotKey(configuration: configuration, action: action)
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
    guard hotKey.matches(hotKeyID) else {
        return OSStatus(eventNotHandledErr)
    }
    hotKey.invoke()
    return noErr
}

/// Carbon global hot key that remains available while Lunchpad is not frontmost.
final class GlobalHotKey: GlobalHotKeyRegistration {
    private static let identifierLock = NSLock()
    nonisolated(unsafe) private static var nextIdentifier: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void
    private let hotKeyID: EventHotKeyID

    init(configuration: HotKeyConfiguration, action: @escaping () -> Void) throws {
        self.action = action
        hotKeyID = Self.makeIdentifier()

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

    fileprivate func matches(_ identifier: EventHotKeyID) -> Bool {
        identifier.signature == hotKeyID.signature && identifier.id == hotKeyID.id
    }

    private static func makeIdentifier() -> EventHotKeyID {
        identifierLock.lock()
        defer { identifierLock.unlock() }
        let identifier = nextIdentifier
        nextIdentifier &+= 1
        return EventHotKeyID(signature: OSType(0x4C4E_5044), id: identifier) // LNPD
    }
}
