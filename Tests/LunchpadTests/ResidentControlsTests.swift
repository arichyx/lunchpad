import MultitouchKit
import XCTest
@testable import Lunchpad

@MainActor
final class ResidentControlsTests: XCTestCase {
    func testLoginItemSuccessUsesReportedSystemState() throws {
        let service = FakeLoginItemService()
        let controller = LoginItemController(service: service)

        let state = try controller.setEnabled(true).get()

        XCTAssertTrue(state)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(service.requests, [true])
    }

    func testLoginItemFailureRollsBackToReportedState() {
        let service = FakeLoginItemService()
        service.nextError = TestError.expected
        let controller = LoginItemController(service: service)

        XCTAssertThrowsError(try controller.setEnabled(true).get())
        XCTAssertFalse(controller.isEnabled)
    }

    func testLoginItemIsUnavailableForDevelopmentExecutable() {
        let service = FakeLoginItemService()
        service.isAvailable = false
        let controller = LoginItemController(service: service)

        XCTAssertThrowsError(try controller.setEnabled(true).get()) { error in
            XCTAssertEqual(error as? LoginItemUpdateError, .unavailable)
        }
        XCTAssertTrue(service.requests.isEmpty)
    }

    func testGestureDisableStopsAndReleasesCurrentMonitor() throws {
        let factory = FakeGestureFactory()
        let controller = GestureMonitorController(factory: factory.make) { _ in }
        controller.setEnabled(true)
        let monitor = try XCTUnwrap(factory.monitors.first)

        controller.setEnabled(false)

        XCTAssertEqual(monitor.stopCount, 1)
        XCTAssertFalse(controller.isMonitoring)
        XCTAssertNil(controller.lastErrorDescription)
    }

    func testGestureFailurePreservesIntentForFreshRetry() throws {
        let factory = FakeGestureFactory()
        factory.failNextStart = true
        let controller = GestureMonitorController(factory: factory.make) { _ in }

        controller.setEnabled(true)
        XCTAssertFalse(controller.isMonitoring)
        XCTAssertNotNil(controller.lastErrorDescription)

        controller.setEnabled(true)
        XCTAssertTrue(controller.isMonitoring)
        XCTAssertEqual(factory.monitors.count, 2)
    }

    func testGestureConfigureRunsForEveryFreshMonitor() {
        let factory = FakeGestureFactory()
        var configuredCount = 0
        let controller = GestureMonitorController(factory: factory.make) { _ in
            configuredCount += 1
        }

        controller.setEnabled(true)
        controller.setEnabled(false)
        controller.setEnabled(true)

        XCTAssertEqual(configuredCount, 2)
    }

    func testGestureRuntimeErrorReleasesMonitorAndCanRetry() {
        let factory = FakeGestureFactory()
        let controller = GestureMonitorController(factory: factory.make) { _ in }
        controller.setEnabled(true)

        controller.reportRuntimeError(TestError.expected)
        XCTAssertFalse(controller.isMonitoring)
        XCTAssertNotNil(controller.lastErrorDescription)

        controller.setEnabled(true)
        XCTAssertTrue(controller.isMonitoring)
        XCTAssertEqual(factory.monitors.count, 2)
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemManaging {
    var isAvailable = true
    var isEnabled = false
    var nextError: Error?
    var requests: [Bool] = []

    func setEnabled(_ enabled: Bool) throws {
        requests.append(enabled)
        if let nextError {
            self.nextError = nil
            throw nextError
        }
        isEnabled = enabled
    }
}

@MainActor
private final class FakeGestureFactory {
    var failNextStart = false
    var monitors: [FakeGestureMonitor] = []

    func make() -> any GestureMonitoring {
        let monitor = FakeGestureMonitor()
        monitor.shouldFailStart = failNextStart
        failNextStart = false
        monitors.append(monitor)
        return monitor
    }
}

private final class FakeGestureMonitor: GestureMonitoring {
    var shouldActivatePinch: (() -> Bool)?
    var onPinch: (() -> Void)?
    var onExpand: (() -> Void)?
    var onPinchSuppressed: (() -> Void)?
    var onFrame: ((MultitouchFrame) -> Void)?
    var onError: ((MultitouchMonitorError) -> Void)?
    var shouldFailStart = false
    var stopCount = 0

    func start() throws {
        if shouldFailStart { throw TestError.expected }
    }

    func stop() {
        stopCount += 1
    }
}

private enum TestError: Error {
    case expected
}
