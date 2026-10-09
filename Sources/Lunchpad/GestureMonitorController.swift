import Foundation
import MultitouchKit

protocol GestureMonitoring: AnyObject {
    var shouldActivatePinch: (() -> Bool)? { get set }
    var onPinch: (() -> Void)? { get set }
    var onExpand: (() -> Void)? { get set }
    var onPinchSuppressed: (() -> Void)? { get set }
    var onFrame: ((MultitouchFrame) -> Void)? { get set }
    var onError: ((MultitouchMonitorError) -> Void)? { get set }

    func start() throws
    func stop()
}

extension MultitouchMonitor: GestureMonitoring {}

@MainActor
final class GestureMonitorController {
    typealias Factory = (Int) -> any GestureMonitoring
    typealias Configure = (any GestureMonitoring, Int) -> Void

    private let factory: Factory
    private let configure: Configure
    private var monitor: (any GestureMonitoring)?

    private(set) var lastErrorDescription: String?
    private(set) var activeFingerCount: Int?
    /// The finger count the user asked for, or nil while gestures are disabled. Recovery restarts
    /// use it after a failed or lost monitor has been released.
    private var requestedFingerCount: Int?
    private var scheduledRestart: DispatchWorkItem?
    var isMonitoring: Bool { monitor != nil }

    init(
        factory: @escaping Factory = { MultitouchMonitor(fingerCount: $0) },
        configure: @escaping Configure
    ) {
        self.factory = factory
        self.configure = configure
    }

    func setConfiguration(enabled: Bool, fingerCount: Int) {
        guard enabled else {
            requestedFingerCount = nil
            scheduledRestart?.cancel()
            scheduledRestart = nil
            stop()
            lastErrorDescription = nil
            return
        }
        requestedFingerCount = fingerCount
        guard monitor == nil || activeFingerCount != fingerCount else { return }
        startMonitor(fingerCount: fingerCount)
    }

    /// Rebuilds the monitor for the requested configuration. The driver stream may not survive
    /// sleep, and a trackpad can disappear and return; a disabled configuration stays stopped.
    func restartIfEnabled() {
        scheduledRestart?.cancel()
        scheduledRestart = nil
        guard let requestedFingerCount else { return }
        startMonitor(fingerCount: requestedFingerCount)
    }

    /// Coalesces bursts of wake and device notifications into one restart once the device has
    /// had time to settle. `completion` runs after the restart attempt.
    func scheduleRestart(after delay: TimeInterval = 1.0, completion: @escaping () -> Void = {}) {
        guard requestedFingerCount != nil else { return }
        scheduledRestart?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.restartIfEnabled()
                completion()
            }
        }
        scheduledRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startMonitor(fingerCount: Int) {
        stop()

        let candidate = factory(fingerCount)
        configure(candidate, fingerCount)
        do {
            try candidate.start()
            monitor = candidate
            activeFingerCount = fingerCount
            lastErrorDescription = nil
        } catch {
            candidate.stop()
            monitor = nil
            activeFingerCount = nil
            lastErrorDescription = String(describing: error)
        }
    }

    func stop() {
        monitor?.stop()
        monitor = nil
        activeFingerCount = nil
    }

    /// Records a stream failure from `source`. A late error from a monitor that was already
    /// replaced must not stop its successor.
    func reportRuntimeError(_ error: Error, from source: any GestureMonitoring) {
        guard let current = monitor, current === source else { return }
        current.stop()
        monitor = nil
        activeFingerCount = nil
        lastErrorDescription = String(describing: error)
    }
}
