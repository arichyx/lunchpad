import CoreGraphics
import XCTest
@testable import DesktopStateKit

final class ShowDesktopStateDetectorTests: XCTestCase {
    private let detector = ShowDesktopStateDetector()
    private let display = CGRect(x: 0, y: 0, width: 1_728, height: 1_080)

    func testVisibleApplicationWindowMeansShowDesktopIsInactive() {
        let windows = [window(bounds: CGRect(x: 200, y: 100, width: 900, height: 700))]

        XCTAssertFalse(
            detector.isActive(
                windows: windows,
                displayBounds: [display],
                ownProcessIdentifier: 999
            )
        )
    }

    func testDisplacedApplicationWindowMeansShowDesktopIsActive() {
        let windows = [window(bounds: CGRect(x: 200, y: 1_095, width: 900, height: 700))]

        XCTAssertTrue(
            detector.isActive(
                windows: windows,
                displayBounds: [display],
                ownProcessIdentifier: 999
            )
        )
    }

    func testVisibleWindowPreventsFalsePositiveFromOffscreenHelperWindow() {
        let windows = [
            window(bounds: CGRect(x: 200, y: 100, width: 900, height: 700)),
            window(bounds: CGRect(x: 200, y: 1_095, width: 900, height: 700)),
        ]

        XCTAssertFalse(
            detector.isActive(
                windows: windows,
                displayBounds: [display],
                ownProcessIdentifier: 999
            )
        )
    }

    func testSmallVisibleResidueDoesNotHideDominantDisplacement() {
        let windows = [
            window(bounds: CGRect(x: 200, y: 100, width: 900, height: 700)),
            window(bounds: CGRect(x: 100, y: 1_095, width: 900, height: 700)),
            window(bounds: CGRect(x: 300, y: 1_095, width: 900, height: 700)),
            window(bounds: CGRect(x: 500, y: 1_095, width: 900, height: 700)),
        ]

        let evaluation = detector.evaluate(
            windows: windows,
            displayBounds: [display],
            ownProcessIdentifier: 999
        )

        XCTAssertTrue(evaluation.isActive)
        XCTAssertEqual(evaluation.visibleWindowCount, 1)
        XCTAssertEqual(evaluation.displacedWindowCount, 3)
    }

    func testVisibleSystemWindowDoesNotHideDisplacedApplicationState() {
        let windows = [
            window(bounds: CGRect(x: 200, y: 1_095, width: 900, height: 700)),
            window(
                bounds: CGRect(x: 0, y: 900, width: 1_728, height: 180),
                isRegularApplication: false
            ),
        ]

        XCTAssertTrue(
            detector.isActive(
                windows: windows,
                displayBounds: [display],
                ownProcessIdentifier: 999
            )
        )
    }

    func testEmptyDesktopDoesNotProduceShowDesktopState() {
        XCTAssertFalse(
            detector.isActive(
                windows: [],
                displayBounds: [display],
                ownProcessIdentifier: 999
            )
        )
    }

    func testOwnAndTinyWindowsAreIgnored() {
        let windows = [
            window(
                processIdentifier: 999,
                bounds: CGRect(x: 200, y: 1_095, width: 900, height: 700)
            ),
            window(bounds: CGRect(x: 200, y: 1_095, width: 50, height: 50)),
        ]

        XCTAssertFalse(
            detector.isActive(
                windows: windows,
                displayBounds: [display],
                ownProcessIdentifier: 999
            )
        )
    }

    func testWindowOnSecondaryDisplayIsVisible() {
        let secondaryDisplay = CGRect(x: 1_728, y: 0, width: 1_440, height: 900)
        let windows = [window(bounds: CGRect(x: 1_900, y: 100, width: 900, height: 700))]

        XCTAssertFalse(
            detector.isActive(
                windows: windows,
                displayBounds: [display, secondaryDisplay],
                ownProcessIdentifier: 999
            )
        )
    }

    func testWindowSnapshotsResolveApplicationPolicyOncePerOwnerProcess() {
        let entries = [
            windowEntry(processIdentifier: 100, bounds: display),
            windowEntry(processIdentifier: 100, bounds: display.offsetBy(dx: 100, dy: 100)),
            windowEntry(processIdentifier: 200, bounds: display),
        ]
        var resolutionCounts: [pid_t: Int] = [:]

        let snapshots = ShowDesktopStateDetector.windowSnapshots(from: entries) {
            resolutionCounts[$0, default: 0] += 1
            return $0 == 100
        }

        XCTAssertEqual(resolutionCounts, [100: 1, 200: 1])
        XCTAssertEqual(snapshots.map(\.isRegularApplication), [true, true, false])
    }

    private func window(
        processIdentifier: pid_t = 100,
        bounds: CGRect,
        isRegularApplication: Bool = true
    ) -> DesktopWindowSnapshot {
        DesktopWindowSnapshot(
            ownerProcessIdentifier: processIdentifier,
            layer: 0,
            alpha: 1,
            bounds: bounds,
            isRegularApplication: isRegularApplication
        )
    }

    private func windowEntry(
        processIdentifier: pid_t,
        bounds: CGRect
    ) -> [CFString: Any] {
        [
            kCGWindowOwnerPID: NSNumber(value: processIdentifier),
            kCGWindowLayer: NSNumber(value: 0),
            kCGWindowAlpha: NSNumber(value: 1),
            kCGWindowBounds: bounds.dictionaryRepresentation,
        ]
    }
}
