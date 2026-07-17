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
    typealias Factory = () -> any GestureMonitoring
    typealias Configure = (any GestureMonitoring) -> Void

    private let factory: Factory
    private let configure: Configure
    private var monitor: (any GestureMonitoring)?

    private(set) var lastErrorDescription: String?
    var isMonitoring: Bool { monitor != nil }

    init(
        factory: @escaping Factory = { MultitouchMonitor(fingerCount: 4) },
        configure: @escaping Configure
    ) {
        self.factory = factory
        self.configure = configure
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled else {
            stop()
            lastErrorDescription = nil
            return
        }
        guard monitor == nil else { return }

        let candidate = factory()
        configure(candidate)
        do {
            try candidate.start()
            monitor = candidate
            lastErrorDescription = nil
        } catch {
            candidate.stop()
            monitor = nil
            lastErrorDescription = String(describing: error)
        }
    }

    func stop() {
        monitor?.stop()
        monitor = nil
    }

    func reportRuntimeError(_ error: Error) {
        monitor?.stop()
        monitor = nil
        lastErrorDescription = String(describing: error)
    }
}
