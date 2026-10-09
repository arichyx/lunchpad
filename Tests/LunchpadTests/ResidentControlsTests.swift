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
        let controller = GestureMonitorController(factory: factory.make) { _, _ in }
        controller.setConfiguration(enabled: true, fingerCount: 4)
        let monitor = try XCTUnwrap(factory.monitors.first)

        controller.setConfiguration(enabled: false, fingerCount: 4)

        XCTAssertEqual(monitor.stopCount, 1)
        XCTAssertFalse(controller.isMonitoring)
        XCTAssertNil(controller.lastErrorDescription)
    }

    func testGestureFailurePreservesIntentForFreshRetry() throws {
        let factory = FakeGestureFactory()
        factory.failNextStart = true
        let controller = GestureMonitorController(factory: factory.make) { _, _ in }

        controller.setConfiguration(enabled: true, fingerCount: 4)
        XCTAssertFalse(controller.isMonitoring)
        XCTAssertNotNil(controller.lastErrorDescription)

        controller.setConfiguration(enabled: true, fingerCount: 4)
        XCTAssertTrue(controller.isMonitoring)
        XCTAssertEqual(factory.monitors.count, 2)
    }

    func testGestureConfigureRunsForEveryFreshMonitor() {
        let factory = FakeGestureFactory()
        var configuredCount = 0
        let controller = GestureMonitorController(factory: factory.make) { _, _ in
            configuredCount += 1
        }

        controller.setConfiguration(enabled: true, fingerCount: 4)
        controller.setConfiguration(enabled: false, fingerCount: 4)
        controller.setConfiguration(enabled: true, fingerCount: 4)

        XCTAssertEqual(configuredCount, 2)
    }

    func testGestureRuntimeErrorReleasesMonitorAndCanRetry() throws {
        let factory = FakeGestureFactory()
        let controller = GestureMonitorController(factory: factory.make) { _, _ in }
        controller.setConfiguration(enabled: true, fingerCount: 4)
        let monitor = try XCTUnwrap(factory.monitors.first)

        controller.reportRuntimeError(TestError.expected, from: monitor)
        XCTAssertFalse(controller.isMonitoring)
        XCTAssertNotNil(controller.lastErrorDescription)

        controller.setConfiguration(enabled: true, fingerCount: 4)
        XCTAssertTrue(controller.isMonitoring)
        XCTAssertEqual(factory.monitors.count, 2)
    }

    func testChangingFingerCountRestartsMonitorWithNewConfiguration() throws {
        let factory = FakeGestureFactory()
        var configuredFingerCounts: [Int] = []
        let controller = GestureMonitorController(factory: factory.make) { _, fingerCount in
            configuredFingerCounts.append(fingerCount)
        }
        controller.setConfiguration(enabled: true, fingerCount: 4)
        let originalMonitor = try XCTUnwrap(factory.monitors.first)

        controller.setConfiguration(enabled: true, fingerCount: 3)

        XCTAssertEqual(originalMonitor.stopCount, 1)
        XCTAssertEqual(factory.monitors.map(\.fingerCount), [4, 3])
        XCTAssertEqual(configuredFingerCounts, [4, 3])
        XCTAssertEqual(controller.activeFingerCount, 3)
        XCTAssertTrue(controller.isMonitoring)
    }

    func testLateErrorFromReplacedMonitorDoesNotStopItsSuccessor() throws {
        let factory = FakeGestureFactory()
        let controller = GestureMonitorController(factory: factory.make) { _, _ in }
        controller.setConfiguration(enabled: true, fingerCount: 4)
        let replacedMonitor = try XCTUnwrap(factory.monitors.first)
        controller.setConfiguration(enabled: true, fingerCount: 3)
        let currentMonitor = try XCTUnwrap(factory.monitors.last)

        controller.reportRuntimeError(TestError.expected, from: replacedMonitor)

        XCTAssertTrue(controller.isMonitoring)
        XCTAssertEqual(controller.activeFingerCount, 3)
        XCTAssertEqual(currentMonitor.stopCount, 0)
        XCTAssertNil(controller.lastErrorDescription)
    }

    func testRestartRebuildsMonitorAfterRuntimeError() throws {
        let factory = FakeGestureFactory()
        let controller = GestureMonitorController(factory: factory.make) { _, _ in }
        controller.setConfiguration(enabled: true, fingerCount: 3)
        controller.reportRuntimeError(TestError.expected, from: try XCTUnwrap(factory.monitors.first))

        controller.restartIfEnabled()

        XCTAssertTrue(controller.isMonitoring)
        XCTAssertEqual(controller.activeFingerCount, 3)
        XCTAssertNil(controller.lastErrorDescription)
        XCTAssertEqual(factory.monitors.count, 2)
    }

    func testRestartReplacesRunningMonitor() throws {
        let factory = FakeGestureFactory()
        let controller = GestureMonitorController(factory: factory.make) { _, _ in }
        controller.setConfiguration(enabled: true, fingerCount: 4)
        let original = try XCTUnwrap(factory.monitors.first)

        controller.restartIfEnabled()

        XCTAssertEqual(original.stopCount, 1)
        XCTAssertEqual(factory.monitors.count, 2)
        XCTAssertTrue(controller.isMonitoring)
    }

    func testRestartKeepsDisabledGesturesStopped() {
        let factory = FakeGestureFactory()
        let controller = GestureMonitorController(factory: factory.make) { _, _ in }
        controller.setConfiguration(enabled: true, fingerCount: 4)
        controller.setConfiguration(enabled: false, fingerCount: 4)

        controller.restartIfEnabled()

        XCTAssertFalse(controller.isMonitoring)
        XCTAssertEqual(factory.monitors.count, 1)
    }

    func testScheduledRestartsCoalesce() {
        let factory = FakeGestureFactory()
        let controller = GestureMonitorController(factory: factory.make) { _, _ in }
        controller.setConfiguration(enabled: true, fingerCount: 4)
        let restarted = expectation(description: "restart")

        controller.scheduleRestart(after: 0.05) { XCTFail("Superseded restart ran") }
        controller.scheduleRestart(after: 0.05) { restarted.fulfill() }

        wait(for: [restarted], timeout: 2)
        XCTAssertEqual(factory.monitors.count, 2)
    }

    func testApplyingSameFingerCountKeepsCurrentMonitor() {
        let factory = FakeGestureFactory()
        let controller = GestureMonitorController(factory: factory.make) { _, _ in }

        controller.setConfiguration(enabled: true, fingerCount: 3)
        controller.setConfiguration(enabled: true, fingerCount: 3)

        XCTAssertEqual(factory.monitors.count, 1)
        XCTAssertEqual(factory.monitors.first?.stopCount, 0)
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

    func make(_ fingerCount: Int) -> any GestureMonitoring {
        let monitor = FakeGestureMonitor(fingerCount: fingerCount)
        monitor.shouldFailStart = failNextStart
        failNextStart = false
        monitors.append(monitor)
        return monitor
    }
}

private final class FakeGestureMonitor: GestureMonitoring {
    let fingerCount: Int
    var shouldActivatePinch: (() -> Bool)?
    var onPinch: (() -> Void)?
    var onExpand: (() -> Void)?
    var onPinchSuppressed: (() -> Void)?
    var onFrame: ((MultitouchFrame) -> Void)?
    var onError: ((MultitouchMonitorError) -> Void)?
    var shouldFailStart = false
    var stopCount = 0

    init(fingerCount: Int) {
        self.fingerCount = fingerCount
    }

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
