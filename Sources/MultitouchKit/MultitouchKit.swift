import Foundation
import IOKit

/// One contact from an AppleMultitouchDevice precise-path report.
public struct MultitouchContact: Sendable {
    public let identifier: UInt8
    public let state: UInt8
    public let x: Double
    public let y: Double

    public init(identifier: UInt8, state: UInt8, x: Double, y: Double) {
        self.identifier = identifier
        self.state = state
        self.x = x
        self.y = y
    }

    /// State 0 is idle and state 7 is leaving; intermediate states remain active.
    public var isActive: Bool {
        state != 0 && state != 7
    }
}

/// A frame of touch data normalized to the 0...1 coordinate space.
public struct MultitouchFrame: Sendable {
    public let contacts: [MultitouchContact]

    public init(contacts: [MultitouchContact]) {
        self.contacts = contacts
    }

    public var activeContacts: [MultitouchContact] {
        contacts.filter(\.isActive)
    }
}

/// Parses 0x75 (V4 Precise Path + Image) reports from Tahoe's built-in trackpad.
public struct MultitouchPacketParser: Sendable {
    private let sensorWidth: Double
    private let sensorHeight: Double

    public init(sensorWidth: Double, sensorHeight: Double) {
        self.sensorWidth = sensorWidth
        self.sensorHeight = sensorHeight
    }

    public func parse(_ bytes: [UInt8]) -> MultitouchFrame? {
        guard bytes.count >= 32, bytes[0] == 0x75 else { return nil }

        let headerSize = Int(bytes[2])
        let pathHeaderSize = Int(littleEndianUInt16(bytes, at: 14))
        let contactDataSize = Int(littleEndianUInt16(bytes, at: 16))
        let contactCount = Int(bytes[22])
        let contactDataOffset = headerSize + pathHeaderSize

        guard headerSize >= 32,
              contactDataOffset <= bytes.count,
              contactDataOffset + contactDataSize <= bytes.count else {
            return nil
        }

        guard contactCount > 0 else {
            return MultitouchFrame(contacts: [])
        }

        guard contactDataSize.isMultiple(of: contactCount) else { return nil }
        let stride = contactDataSize / contactCount
        guard stride >= 16 else { return nil }

        var contacts: [MultitouchContact] = []
        contacts.reserveCapacity(contactCount)

        for index in 0..<contactCount {
            let offset = contactDataOffset + index * stride
            guard offset + 15 < bytes.count else { return nil }

            // Precise Path coordinates are signed 16-bit values relative to the sensor center.
            // Offsets +12/+14 are contact ellipse axes, not positions.
            let rawX = Double(Int16(bitPattern: littleEndianUInt16(bytes, at: offset + 4)))
            let rawY = Double(Int16(bitPattern: littleEndianUInt16(bytes, at: offset + 6)))
            contacts.append(
                MultitouchContact(
                    identifier: bytes[offset],
                    state: bytes[offset + 1],
                    x: rawX / sensorWidth + 0.5,
                    y: rawY / sensorHeight + 0.5
                )
            )
        }

        return MultitouchFrame(contacts: contacts)
    }

    private func littleEndianUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }
}

/// Detects an inward pinch using the mean pairwise distance between all tracked contacts.
public struct PinchRecognizer: Sendable {
    public let fingerCount: Int
    public let contractionThreshold: Double
    public let minimumStartingDistance: Double
    public let maximumDuration: TimeInterval

    private var maximumDistance: Double?
    private var startedAt: TimeInterval?
    private var hasTriggered = false
    private var trackedIdentifiers: Set<UInt8>?

    public init(
        fingerCount: Int = 4,
        contractionThreshold: Double = 0.82,
        minimumStartingDistance: Double = 0.06,
        maximumDuration: TimeInterval = 3.0
    ) {
        self.fingerCount = fingerCount
        self.contractionThreshold = contractionThreshold
        self.minimumStartingDistance = minimumStartingDistance
        self.maximumDuration = maximumDuration
    }

    public mutating func process(
        _ frame: MultitouchFrame,
        at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        let activeContacts = frame.activeContacts
        guard activeContacts.count >= fingerCount else {
            reset()
            return false
        }

        let contacts: [MultitouchContact]
        if let trackedIdentifiers {
            let tracked = activeContacts.filter { trackedIdentifiers.contains($0.identifier) }
            if tracked.count == fingerCount {
                contacts = tracked
            } else {
                // The driver may alternate between four and five contacts. Rebuild the
                // baseline only when a locked contact disappears.
                reset()
                contacts = Array(activeContacts.prefix(fingerCount))
                self.trackedIdentifiers = Set(contacts.map(\.identifier))
            }
        } else {
            contacts = Array(activeContacts.prefix(fingerCount))
            trackedIdentifiers = Set(contacts.map(\.identifier))
        }

        let distance = meanPairwiseDistance(of: contacts)
        if startedAt == nil {
            startedAt = timestamp
            maximumDistance = distance
            return false
        }

        guard let startedAt else { return false }
        if timestamp - startedAt > maximumDuration {
            // Reset the baseline after a long stationary period to prevent delayed triggers.
            self.startedAt = timestamp
            maximumDistance = distance
            hasTriggered = false
            return false
        }

        maximumDistance = max(maximumDistance ?? distance, distance)
        guard !hasTriggered,
              let maximumDistance,
              maximumDistance >= minimumStartingDistance,
              distance / maximumDistance <= contractionThreshold else {
            return false
        }

        hasTriggered = true
        return true
    }

    private mutating func reset() {
        maximumDistance = nil
        startedAt = nil
        hasTriggered = false
        trackedIdentifiers = nil
    }

    private func meanPairwiseDistance(of contacts: [MultitouchContact]) -> Double {
        var total = 0.0
        var pairCount = 0
        for first in contacts.indices {
            for second in contacts.indices where second > first {
                total += hypot(
                    contacts[first].x - contacts[second].x,
                    contacts[first].y - contacts[second].y
                )
                pairCount += 1
            }
        }
        return pairCount == 0 ? 0 : total / Double(pairCount)
    }
}

/// Detects an outward spread (expand / unpinch) using the mean pairwise distance between all
/// tracked contacts. It is the symmetric counterpart to `PinchRecognizer`: instead of tracking the
/// maximum distance reached and firing on contraction, it tracks the minimum distance reached and
/// fires once when the current distance expands past the expansion threshold relative to that
/// minimum. The four-contact identifier lock, fifth-contact tolerance, and stationary-too-long
/// baseline reset mirror the pinch recognizer. A dismissal gesture is only meaningful while the
/// launcher is already visible; visibility is enforced by the app layer, not here.
public struct ExpandRecognizer: Sendable {
    public let fingerCount: Int
    public let expansionThreshold: Double
    public let minimumStartingDistance: Double
    public let maximumDuration: TimeInterval

    private var minimumDistance: Double?
    private var startedAt: TimeInterval?
    private var hasTriggered = false
    private var trackedIdentifiers: Set<UInt8>?

    public init(
        fingerCount: Int = 4,
        // Approximately the inverse of the pinch contraction threshold (1 / 0.82).
        expansionThreshold: Double = 1.22,
        minimumStartingDistance: Double = 0.06,
        maximumDuration: TimeInterval = 3.0
    ) {
        self.fingerCount = fingerCount
        self.expansionThreshold = expansionThreshold
        self.minimumStartingDistance = minimumStartingDistance
        self.maximumDuration = maximumDuration
    }

    public mutating func process(
        _ frame: MultitouchFrame,
        at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        let activeContacts = frame.activeContacts
        guard activeContacts.count >= fingerCount else {
            reset()
            return false
        }

        let contacts: [MultitouchContact]
        if let trackedIdentifiers {
            let tracked = activeContacts.filter { trackedIdentifiers.contains($0.identifier) }
            if tracked.count == fingerCount {
                contacts = tracked
            } else {
                // The driver may alternate between four and five contacts. Rebuild the
                // baseline only when a locked contact disappears.
                reset()
                contacts = Array(activeContacts.prefix(fingerCount))
                self.trackedIdentifiers = Set(contacts.map(\.identifier))
            }
        } else {
            contacts = Array(activeContacts.prefix(fingerCount))
            trackedIdentifiers = Set(contacts.map(\.identifier))
        }

        let distance = meanPairwiseDistance(of: contacts)
        if startedAt == nil {
            startedAt = timestamp
            minimumDistance = distance
            return false
        }

        guard let startedAt else { return false }
        if timestamp - startedAt > maximumDuration {
            // Reset the baseline after a long stationary period to prevent delayed triggers.
            self.startedAt = timestamp
            minimumDistance = distance
            hasTriggered = false
            return false
        }

        minimumDistance = min(minimumDistance ?? distance, distance)
        guard !hasTriggered,
              let minimumDistance,
              minimumDistance >= minimumStartingDistance,
              distance / minimumDistance >= expansionThreshold else {
            return false
        }

        hasTriggered = true
        return true
    }

    private mutating func reset() {
        minimumDistance = nil
        startedAt = nil
        hasTriggered = false
        trackedIdentifiers = nil
    }

    private func meanPairwiseDistance(of contacts: [MultitouchContact]) -> Double {
        var total = 0.0
        var pairCount = 0
        for first in contacts.indices {
            for second in contacts.indices where second > first {
                total += hypot(
                    contacts[first].x - contacts[second].x,
                    contacts[first].y - contacts[second].y
                )
                pairCount += 1
            }
        }
        return pairCount == 0 ? 0 : total / Double(pairCount)
    }
}

/// Separates reaching the pinch threshold from completing the gesture.
/// The system performs an interactive animation while the reserved four-finger gesture is
/// active. Waiting for contact release prevents that remaining progress from affecting
/// Lunchpad's fixed-duration animation.
enum PinchCompletionAction: Sendable, Equatable {
    case activate
    case suppress
    case dismiss
}

/// Samples activation policy at the beginning of a contact sequence and waits for release before
/// returning the result. Sampling on the first contact preserves the pre-restore desktop state.
///
/// Both the inward pinch and the outward spread flow through this gate. Whichever direction reaches
/// its threshold first becomes the pending outcome for that contact sequence; the other is ignored
/// until the sequence resets, so a single gesture emits at most one action. The activation policy
/// (Show Desktop suppression) is sampled on the first contact and consulted only for the pinch
/// outcome; a dismissal never depends on it.
struct PinchCompletionGate: Sendable {
    private var pending = PendingGesture.none
    private var activationAllowed: Bool?

    mutating func process(
        _ frame: MultitouchFrame,
        pinchDetected: Bool,
        expandDetected: Bool,
        evaluateActivation: () -> Bool
    ) -> PinchCompletionAction? {
        let activeContactCount = frame.activeContacts.count

        // Sample once on the first contact of a sequence, before macOS restores displaced windows.
        // This value is read only when emitting a pinch activation; dismissals ignore it.
        if activationAllowed == nil, activeContactCount > 0 {
            activationAllowed = evaluateActivation()
        }

        // The first direction to reach its threshold wins for this contact sequence.
        if pending == .none {
            if pinchDetected {
                pending = .pinch
            } else if expandDetected {
                pending = .expand
            }
        }

        if pending != .none, activeContactCount < 2 {
            let action: PinchCompletionAction
            switch pending {
            case .none:
                action = .activate
            case .pinch:
                action = activationAllowed == false ? .suppress : .activate
            case .expand:
                action = .dismiss
            }
            pending = .none
            activationAllowed = nil
            return action
        }

        if activeContactCount == 0 {
            activationAllowed = nil
        }
        return nil
    }
}

private enum PendingGesture: Sendable {
    case none
    case pinch
    case expand
}

public enum MultitouchMonitorError: Error, CustomStringConvertible {
    case serviceNotFound
    case call(String, kern_return_t)
    case invalidQueueAddress

    public var description: String {
        switch self {
        case .serviceNotFound:
            return "AppleMultitouchDevice not found"
        case let .call(name, result):
            return "\(name) failed (0x\(String(UInt32(bitPattern: result), radix: 16)))"
        case .invalidQueueAddress:
            return "Driver returned an invalid data queue address"
        }
    }
}

/// Connects directly to AppleMultitouchDeviceUserClient and consumes its shared IODataQueue.
/// Callbacks run on a dedicated background queue; UI clients must return to the main actor.
public final class MultitouchMonitor: @unchecked Sendable {
    private struct ReadLoopContext: @unchecked Sendable {
        let connection: io_connect_t
        let port: mach_port_t
        let queueAddress: mach_vm_address_t
        let dataQueue: UnsafeMutablePointer<IODataQueueMemory>
        let maximumPacketSize: Int
        let parser: MultitouchPacketParser
    }

    public var onFrame: ((MultitouchFrame) -> Void)?
    public var onPinch: (() -> Void)?
    public var onExpand: (() -> Void)?
    public var onPinchSuppressed: (() -> Void)?
    public var shouldActivatePinch: (() -> Bool)?
    public var onError: ((MultitouchMonitorError) -> Void)?

    private let worker = DispatchQueue(
        label: "com.arichyx.lunchpad.multitouch",
        qos: .userInteractive
    )
    private let stateLock = NSLock()
    private var recognizer: PinchRecognizer
    private var expandRecognizer: ExpandRecognizer
    private var completionGate = PinchCompletionGate()
    private var running = false
    private var connection: io_connect_t = 0
    private var notificationPort: mach_port_t = 0

    public init(fingerCount: Int = 4) {
        recognizer = PinchRecognizer(fingerCount: fingerCount)
        expandRecognizer = ExpandRecognizer(fingerCount: fingerCount)
    }

    public func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !running else { return }

        guard let matching = IOServiceMatching("AppleMultitouchDevice") else {
            throw MultitouchMonitorError.serviceNotFound
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else {
            throw MultitouchMonitorError.serviceNotFound
        }
        defer { IOObjectRelease(service) }

        var openedConnection: io_connect_t = 0
        var result = IOServiceOpen(service, mach_task_self_, 0, &openedConnection)
        guard result == KERN_SUCCESS else {
            throw MultitouchMonitorError.call("IOServiceOpen", result)
        }

        let port = IODataQueueAllocateNotificationPort()
        guard port != 0 else {
            IOServiceClose(openedConnection)
            throw MultitouchMonitorError.call("IODataQueueAllocateNotificationPort", KERN_RESOURCE_SHORTAGE)
        }

        result = IOConnectSetNotificationPort(openedConnection, 0, port, 0)
        guard result == KERN_SUCCESS else {
            mach_port_destruct(mach_task_self_, port, 0, 0)
            IOServiceClose(openedConnection)
            throw MultitouchMonitorError.call("IOConnectSetNotificationPort", result)
        }

        var queueAddress: mach_vm_address_t = 0
        var queueSize: mach_vm_size_t = 0
        result = IOConnectMapMemory(
            openedConnection,
            0,
            mach_task_self_,
            &queueAddress,
            &queueSize,
            IOOptionBits(kIOMapAnywhere)
        )
        guard result == KERN_SUCCESS else {
            mach_port_destruct(mach_task_self_, port, 0, 0)
            IOServiceClose(openedConnection)
            throw MultitouchMonitorError.call("IOConnectMapMemory", result)
        }

        guard let dataQueue = UnsafeMutablePointer<IODataQueueMemory>(
            bitPattern: UInt(queueAddress)
        ) else {
            IOConnectUnmapMemory(openedConnection, 0, mach_task_self_, queueAddress)
            mach_port_destruct(mach_task_self_, port, 0, 0)
            IOServiceClose(openedConnection)
            throw MultitouchMonitorError.invalidQueueAddress
        }

        var enabled: UInt64 = 1
        result = IOConnectCallScalarMethod(openedConnection, 0, &enabled, 1, nil, nil)
        guard result == KERN_SUCCESS else {
            IOConnectUnmapMemory(openedConnection, 0, mach_task_self_, queueAddress)
            mach_port_destruct(mach_task_self_, port, 0, 0)
            IOServiceClose(openedConnection)
            throw MultitouchMonitorError.call("Start touch data stream", result)
        }

        let sensorWidth = Self.numberProperty(service, key: "Sensor Surface Width") ?? 15_600
        let sensorHeight = Self.numberProperty(service, key: "Sensor Surface Height") ?? 9_600
        let maximumPacketSize = Int(Self.numberProperty(service, key: "Max Packet Size") ?? 4_096)
        let parser = MultitouchPacketParser(sensorWidth: sensorWidth, sensorHeight: sensorHeight)

        connection = openedConnection
        notificationPort = port
        running = true

        let context = ReadLoopContext(
            connection: openedConnection,
            port: port,
            queueAddress: queueAddress,
            dataQueue: dataQueue,
            maximumPacketSize: maximumPacketSize,
            parser: parser
        )
        worker.async { [weak self, context] in
            self?.readLoop(context)
        }
    }

    /// Normally called only during termination; destroying the notification port wakes the waiter.
    public func stop() {
        stateLock.lock()
        guard running else {
            stateLock.unlock()
            return
        }
        running = false
        let openedConnection = connection
        let port = notificationPort
        notificationPort = 0
        stateLock.unlock()

        var disabled: UInt64 = 0
        _ = IOConnectCallScalarMethod(openedConnection, 0, &disabled, 1, nil, nil)
        if port != 0 {
            mach_port_destruct(mach_task_self_, port, 0, 0)
        }
    }

    private func readLoop(_ context: ReadLoopContext) {
        let openedConnection = context.connection
        let port = context.port
        let queueAddress = context.queueAddress
        let dataQueue = context.dataQueue
        let maximumPacketSize = context.maximumPacketSize
        let parser = context.parser

        defer {
            IOConnectUnmapMemory(openedConnection, 0, mach_task_self_, queueAddress)
            IOServiceClose(openedConnection)
            // stop() may already have destroyed the port; a second destroy only returns
            // an invalid-right error and is safe to ignore.
            _ = mach_port_destruct(mach_task_self_, port, 0, 0)
            stateLock.lock()
            if connection == openedConnection {
                connection = 0
                notificationPort = 0
                running = false
            }
            stateLock.unlock()
        }

        while isRunning {
            let result = IODataQueueWaitForAvailableData(dataQueue, port)
            guard result == KERN_SUCCESS else {
                if isRunning {
                    onError?(.call("Wait for touch data", result))
                }
                break
            }

            while isRunning && IODataQueueDataAvailable(dataQueue) {
                var bytes = [UInt8](repeating: 0, count: maximumPacketSize)
                var size = UInt32(bytes.count)
                let dequeueResult = bytes.withUnsafeMutableBytes { buffer in
                    IODataQueueDequeue(dataQueue, buffer.baseAddress, &size)
                }
                guard dequeueResult == KERN_SUCCESS else {
                    onError?(.call("Read touch data", dequeueResult))
                    break
                }

                bytes.removeSubrange(Int(size)..<bytes.count)
                guard let frame = parser.parse(bytes) else { continue }
                let pinchDetected = recognizer.process(frame)
                let expandDetected = expandRecognizer.process(frame)
                onFrame?(frame)
                let completionAction = completionGate.process(
                    frame,
                    pinchDetected: pinchDetected,
                    expandDetected: expandDetected
                ) { [weak self] in
                    self?.shouldActivatePinch?() ?? true
                }
                if let completionAction {
                    switch completionAction {
                    case .activate:
                        onPinch?()
                    case .suppress:
                        onPinchSuppressed?()
                    case .dismiss:
                        onExpand?()
                    }
                }
            }
        }
    }

    private var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    private static func numberProperty(_ service: io_service_t, key: String) -> Double? {
        guard let rawValue = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }
        return (rawValue.takeRetainedValue() as? NSNumber)?.doubleValue
    }
}
