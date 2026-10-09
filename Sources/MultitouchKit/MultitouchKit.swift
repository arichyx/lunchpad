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
    /// Contacts that are neither idle nor leaving. Computed once because every recognizer and
    /// the completion gate read it for each report.
    public let activeContacts: [MultitouchContact]

    public init(contacts: [MultitouchContact]) {
        self.contacts = contacts
        activeContacts = contacts.filter(\.isActive)
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
        bytes.withUnsafeBytes { parse($0) }
    }

    /// Parses one report in place, so the read loop can reuse a single dequeue buffer.
    func parse(_ bytes: UnsafeRawBufferPointer) -> MultitouchFrame? {
        // Coordinates are normalized by the sensor size; an unusable size cannot produce
        // meaningful contacts.
        guard sensorWidth.isFinite, sensorWidth > 0,
              sensorHeight.isFinite, sensorHeight > 0 else {
            return nil
        }
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

    private func littleEndianUInt16(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }
}

/// The shared state machine behind `PinchRecognizer` and `ExpandRecognizer`.
///
/// It locks onto the configured contact identifiers, measures their mean pairwise distance, and
/// fires once when that distance moves far enough from the extreme reached during the contact
/// sequence: the maximum for a contraction, the minimum for an expansion. Losing a locked contact
/// rebuilds the baseline, and a baseline older than `maximumDuration` is restarted so a long
/// stationary hold cannot trigger late.
struct ContactSpreadTracker: Sendable {
    enum Direction: Sendable {
        case contraction
        case expansion
    }

    let fingerCount: Int
    let maximumContactCount: Int
    let direction: Direction
    /// Ratio of the current distance to the extreme distance that completes the gesture.
    let threshold: Double
    let minimumStartingDistance: Double
    let maximumDuration: TimeInterval

    private var extremeDistance: Double?
    private var startedAt: TimeInterval?
    private var hasTriggered = false
    private var trackedIdentifiers: Set<UInt8>?

    /// Three-finger mode must not claim a deliberate four-finger system gesture. Four-finger mode
    /// tolerates a transient fifth driver contact by tracking the original four identifiers.
    static func defaultMaximumContactCount(forFingerCount fingerCount: Int) -> Int {
        fingerCount == 4 ? 5 : fingerCount
    }

    init(
        fingerCount: Int,
        maximumContactCount: Int?,
        direction: Direction,
        threshold: Double,
        minimumStartingDistance: Double,
        maximumDuration: TimeInterval
    ) {
        self.fingerCount = fingerCount
        self.maximumContactCount = maximumContactCount
            ?? Self.defaultMaximumContactCount(forFingerCount: fingerCount)
        self.direction = direction
        self.threshold = threshold
        self.minimumStartingDistance = minimumStartingDistance
        self.maximumDuration = maximumDuration
    }

    mutating func process(_ frame: MultitouchFrame, at timestamp: TimeInterval) -> Bool {
        let activeContacts = frame.activeContacts
        guard activeContacts.count >= fingerCount,
              activeContacts.count <= maximumContactCount else {
            reset()
            return false
        }

        let contacts: [MultitouchContact]
        if let trackedIdentifiers {
            let tracked = activeContacts.filter { trackedIdentifiers.contains($0.identifier) }
            if tracked.count == fingerCount {
                contacts = tracked
            } else {
                // Rebuild the baseline only when one of the locked contacts disappears.
                reset()
                contacts = Array(activeContacts.prefix(fingerCount))
                self.trackedIdentifiers = Set(contacts.map(\.identifier))
            }
        } else {
            contacts = Array(activeContacts.prefix(fingerCount))
            trackedIdentifiers = Set(contacts.map(\.identifier))
        }

        let distance = Self.meanPairwiseDistance(of: contacts)
        guard let startedAt else {
            startedAt = timestamp
            extremeDistance = distance
            return false
        }

        if timestamp - startedAt > maximumDuration {
            // Reset the baseline after a long stationary period to prevent delayed triggers.
            self.startedAt = timestamp
            extremeDistance = distance
            hasTriggered = false
            return false
        }

        let extreme: Double
        switch direction {
        case .contraction:
            extreme = max(extremeDistance ?? distance, distance)
        case .expansion:
            extreme = min(extremeDistance ?? distance, distance)
        }
        extremeDistance = extreme

        guard !hasTriggered,
              extreme >= minimumStartingDistance,
              thresholdReached(ratio: distance / extreme) else {
            return false
        }

        hasTriggered = true
        return true
    }

    private func thresholdReached(ratio: Double) -> Bool {
        switch direction {
        case .contraction:
            ratio <= threshold
        case .expansion:
            ratio >= threshold
        }
    }

    private mutating func reset() {
        extremeDistance = nil
        startedAt = nil
        hasTriggered = false
        trackedIdentifiers = nil
    }

    static func meanPairwiseDistance(of contacts: [MultitouchContact]) -> Double {
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

/// Detects an inward pinch using the mean pairwise distance between all tracked contacts. It
/// fires once when the distance contracts below `contractionThreshold` of the maximum reached.
public struct PinchRecognizer: Sendable {
    private var tracker: ContactSpreadTracker

    public var fingerCount: Int { tracker.fingerCount }
    public var maximumContactCount: Int { tracker.maximumContactCount }
    public var contractionThreshold: Double { tracker.threshold }
    public var minimumStartingDistance: Double { tracker.minimumStartingDistance }
    public var maximumDuration: TimeInterval { tracker.maximumDuration }

    public init(
        fingerCount: Int = 4,
        maximumContactCount: Int? = nil,
        contractionThreshold: Double = 0.82,
        minimumStartingDistance: Double = 0.06,
        maximumDuration: TimeInterval = 3.0
    ) {
        tracker = ContactSpreadTracker(
            fingerCount: fingerCount,
            maximumContactCount: maximumContactCount,
            direction: .contraction,
            threshold: contractionThreshold,
            minimumStartingDistance: minimumStartingDistance,
            maximumDuration: maximumDuration
        )
    }

    public mutating func process(
        _ frame: MultitouchFrame,
        at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        tracker.process(frame, at: timestamp)
    }
}

/// Detects an outward spread (expand / unpinch), the symmetric counterpart to `PinchRecognizer`:
/// it fires once when the distance expands past `expansionThreshold` of the minimum reached. A
/// dismissal gesture is only meaningful while the launcher is already visible; visibility is
/// enforced by the app layer, not here.
public struct ExpandRecognizer: Sendable {
    private var tracker: ContactSpreadTracker

    public var fingerCount: Int { tracker.fingerCount }
    public var maximumContactCount: Int { tracker.maximumContactCount }
    public var expansionThreshold: Double { tracker.threshold }
    public var minimumStartingDistance: Double { tracker.minimumStartingDistance }
    public var maximumDuration: TimeInterval { tracker.maximumDuration }

    public init(
        fingerCount: Int = 4,
        maximumContactCount: Int? = nil,
        // Approximately the inverse of the pinch contraction threshold (1 / 0.82).
        expansionThreshold: Double = 1.22,
        minimumStartingDistance: Double = 0.06,
        maximumDuration: TimeInterval = 3.0
    ) {
        tracker = ContactSpreadTracker(
            fingerCount: fingerCount,
            maximumContactCount: maximumContactCount,
            direction: .expansion,
            threshold: expansionThreshold,
            minimumStartingDistance: minimumStartingDistance,
            maximumDuration: maximumDuration
        )
    }

    public mutating func process(
        _ frame: MultitouchFrame,
        at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        tracker.process(frame, at: timestamp)
    }
}

/// Separates reaching the pinch threshold from completing the gesture.
/// A system gesture may perform an interactive animation while the contacts are active. Waiting
/// for release prevents that remaining progress from affecting Lunchpad's fixed-duration
/// animation.
enum PinchCompletionAction: Sendable, Equatable {
    case activate
    case suppress
    case dismiss
}

/// Samples activation policy at the beginning of a multi-finger contact sequence and waits for
/// release before returning the result. Sampling when the second contact lands preserves the
/// pre-restore desktop state: a single contact (pointer movement, taps, clicks) can never become a
/// multi-finger gesture, and the second contact still lands before any multi-finger motion lets
/// macOS restore displaced windows. Skipping single-contact sequences keeps ordinary pointer use
/// from querying WindowServer.
///
/// Both the inward pinch and the outward spread flow through this gate. Whichever direction reaches
/// its threshold first becomes the pending outcome for that contact sequence; the other is ignored
/// until the sequence resets, so a single gesture emits at most one action. The activation policy
/// (Show Desktop suppression) is sampled once per sequence and consulted only for the pinch
/// outcome; a dismissal never depends on it.
///
/// A sequence that exceeds the configured contact policy is rejected until every contact lifts.
/// This lets strict three-finger mode avoid claiming the tail of a four-finger system gesture.
struct PinchCompletionGate: Sendable {
    /// The active contact count at which a sequence first samples the activation policy.
    static let activationSamplingContactCount = 2

    private var pending = PendingGesture.none
    private var activationAllowed: Bool?
    private var ignoringUntilRelease = false

    mutating func process(
        _ frame: MultitouchFrame,
        pinchDetected: Bool,
        expandDetected: Bool,
        sequenceEligible: Bool = true,
        evaluateActivation: () -> Bool
    ) -> PinchCompletionAction? {
        let activeContactCount = frame.activeContacts.count

        if ignoringUntilRelease {
            if activeContactCount == 0 {
                ignoringUntilRelease = false
                pending = .none
                activationAllowed = nil
            }
            return nil
        }

        guard sequenceEligible else {
            pending = .none
            activationAllowed = nil
            ignoringUntilRelease = activeContactCount > 0
            return nil
        }

        // Sample once per sequence, when the second contact lands and before macOS can restore
        // displaced windows. This value is read only when emitting a pinch activation; dismissals
        // ignore it.
        if activationAllowed == nil,
           activeContactCount >= Self.activationSamplingContactCount {
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
    private let maximumContactCount: Int
    private var completionGate = PinchCompletionGate()
    private var running = false
    private var connection: io_connect_t = 0
    private var notificationPort: mach_port_t = 0

    public init(fingerCount: Int = 4) {
        maximumContactCount = ContactSpreadTracker.defaultMaximumContactCount(
            forFingerCount: fingerCount
        )
        recognizer = PinchRecognizer(
            fingerCount: fingerCount,
            maximumContactCount: maximumContactCount
        )
        expandRecognizer = ExpandRecognizer(
            fingerCount: fingerCount,
            maximumContactCount: maximumContactCount
        )
    }

    public func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !running else { return }

        let service = try Self.preferredMultitouchService()
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

        // Registry values come from the driver and are untrusted; fall back to the verified
        // built-in trackpad values when they are missing or unusable.
        let sensorWidth = Self.validatedSensorDimension(
            Self.numberProperty(service, key: "Sensor Surface Width"),
            fallback: 15_600
        )
        let sensorHeight = Self.validatedSensorDimension(
            Self.numberProperty(service, key: "Sensor Surface Height"),
            fallback: 9_600
        )
        let maximumPacketSize = Self.validatedPacketSize(
            Self.numberProperty(service, key: "Max Packet Size")
        )
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

        // One reusable dequeue buffer; reports are parsed in place.
        var buffer = [UInt8](repeating: 0, count: maximumPacketSize)

        while isRunning {
            let result = IODataQueueWaitForAvailableData(dataQueue, port)
            guard result == KERN_SUCCESS else {
                if isRunning {
                    onError?(.call("Wait for touch data", result))
                }
                break
            }

            // This loop is one long-lived dispatch work item, so libdispatch cannot drain its
            // autorelease pool until monitoring stops. Bound AppKit and Core Foundation
            // temporaries created by callbacks to each batch of queued reports.
            let keepReading = autoreleasepool { () -> Bool in
                while isRunning && IODataQueueDataAvailable(dataQueue) {
                    var size = UInt32(buffer.count)
                    let dequeueResult = buffer.withUnsafeMutableBytes { bytes in
                        IODataQueueDequeue(dataQueue, bytes.baseAddress, &size)
                    }
                    guard dequeueResult == KERN_SUCCESS, Int(size) <= buffer.count else {
                        // A failed dequeue leaves the report in the queue, so waiting again would
                        // return immediately and spin. Stop and report instead.
                        onError?(.call("Read touch data", dequeueResult))
                        return false
                    }

                    let frame = buffer.withUnsafeBytes { bytes in
                        parser.parse(UnsafeRawBufferPointer(rebasing: bytes[0..<Int(size)]))
                    }
                    guard let frame else { continue }
                    process(frame)
                }
                return true
            }
            guard keepReading else { break }
        }
    }

    private func process(_ frame: MultitouchFrame) {
        let pinchDetected = recognizer.process(frame)
        let expandDetected = expandRecognizer.process(frame)
        onFrame?(frame)
        let completionAction = completionGate.process(
            frame,
            pinchDetected: pinchDetected,
            expandDetected: expandDetected,
            sequenceEligible: frame.activeContacts.count <= maximumContactCount
        ) { [weak self] in
            self?.shouldActivatePinch?() ?? true
        }
        switch completionAction {
        case .activate:
            onPinch?()
        case .suppress:
            onPinchSuppressed?()
        case .dismiss:
            onExpand?()
        case nil:
            break
        }
    }

    private var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    /// Returns the built-in trackpad when several multitouch devices are attached. A Magic Mouse
    /// or external trackpad also publishes `AppleMultitouchDevice`, but only the built-in report
    /// format is verified, so registry order must not decide which device is monitored.
    private static func preferredMultitouchService() throws -> io_service_t {
        guard let matching = IOServiceMatching("AppleMultitouchDevice") else {
            throw MultitouchMonitorError.serviceNotFound
        }
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else {
            throw MultitouchMonitorError.call("IOServiceGetMatchingServices", result)
        }
        defer { IOObjectRelease(iterator) }

        var services: [io_service_t] = []
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            services.append(service)
        }
        let builtInFlags = services.map { boolProperty($0, key: "MT Built-In") }
        guard let index = preferredDeviceIndex(builtInFlags: builtInFlags) else {
            throw MultitouchMonitorError.serviceNotFound
        }
        for (offset, service) in services.enumerated() where offset != index {
            IOObjectRelease(service)
        }
        return services[index]
    }

    /// Prefers the first built-in device and otherwise keeps registry order.
    static func preferredDeviceIndex(builtInFlags: [Bool?]) -> Int? {
        builtInFlags.firstIndex(of: true) ?? (builtInFlags.isEmpty ? nil : 0)
    }

    /// A sensor dimension normalizes coordinates, so it must be a positive, finite number.
    static func validatedSensorDimension(_ reported: Double?, fallback: Double) -> Double {
        guard let reported, reported.isFinite, reported > 0 else { return fallback }
        return reported
    }

    /// The dequeue buffer must hold at least one report header and stay reasonably bounded.
    static func validatedPacketSize(_ reported: Double?) -> Int {
        let fallback = 4_096
        guard let reported, reported.isFinite, reported >= 64, reported <= 1_048_576 else {
            return fallback
        }
        return Int(reported)
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

    private static func boolProperty(_ service: io_service_t, key: String) -> Bool? {
        guard let rawValue = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }
        return (rawValue.takeRetainedValue() as? NSNumber)?.boolValue
    }
}

/// Reports `AppleMultitouchDevice` arrivals and removals. A monitor whose device disappears may
/// never receive another report, and a reconnected trackpad needs a fresh user-client connection,
/// so the app rebuilds its monitor when this observer fires.
public final class MultitouchDeviceObserver {
    private let onChange: () -> Void
    private var notificationPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    /// `onChange` runs on `queue` for every arrival or removal after the observer starts;
    /// devices that already exist are not reported.
    public init(queue: DispatchQueue = .main, onChange: @escaping () -> Void) throws {
        self.onChange = onChange
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            throw MultitouchMonitorError.call("IONotificationPortCreate", KERN_RESOURCE_SHORTAGE)
        }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, queue)

        let callback: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let observer = Unmanaged<MultitouchDeviceObserver>
                .fromOpaque(refcon)
                .takeUnretainedValue()
            // Draining the iterator re-arms the notification.
            MultitouchDeviceObserver.drain(iterator)
            observer.onChange()
        }

        for notificationType in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            guard let matching = IOServiceMatching("AppleMultitouchDevice") else {
                invalidate()
                throw MultitouchMonitorError.serviceNotFound
            }
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port,
                notificationType,
                matching,
                callback,
                Unmanaged.passUnretained(self).toOpaque(),
                &iterator
            )
            guard result == KERN_SUCCESS else {
                invalidate()
                throw MultitouchMonitorError.call("IOServiceAddMatchingNotification", result)
            }
            iterators.append(iterator)
            // The initial contents describe devices that already exist; consume them silently.
            Self.drain(iterator)
        }
    }

    deinit {
        invalidate()
    }

    private func invalidate() {
        iterators.forEach { IOObjectRelease($0) }
        iterators.removeAll()
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
    }

    private static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            IOObjectRelease(service)
        }
    }
}
