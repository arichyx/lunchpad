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
            stop()
            lastErrorDescription = nil
            return
        }
        guard monitor == nil || activeFingerCount != fingerCount else { return }

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

    func reportRuntimeError(_ error: Error) {
        monitor?.stop()
        monitor = nil
        activeFingerCount = nil
        lastErrorDescription = String(describing: error)
    }
}
