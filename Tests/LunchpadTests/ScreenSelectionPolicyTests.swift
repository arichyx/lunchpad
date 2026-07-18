import XCTest
@testable import Lunchpad

final class ScreenSelectionPolicyTests: XCTestCase {
    func testSelectsMainScreenWhenPointerOnMain() {
        let main = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let other = NSRect(x: 1440, y: 0, width: 1080, height: 1920)

        let index = ScreenSelectionPolicy.selectedIndex(
            pointerLocation: NSPoint(x: 500, y: 400),
            screenFrames: [main, other],
            mainScreenIndex: 0
        )

        XCTAssertEqual(index, 0)
    }

    func testSelectsNonMainScreenWhenPointerWithinIt() {
        let main = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let other = NSRect(x: 1440, y: 0, width: 1080, height: 1920)

        let index = ScreenSelectionPolicy.selectedIndex(
            pointerLocation: NSPoint(x: 1800, y: 800),
            screenFrames: [main, other],
            mainScreenIndex: 0
        )

        XCTAssertEqual(index, 1)
    }

    func testSelectsFirstMatchingScreenWhenPointerWithinSeveral() {
        // Overlapping frames are unusual in production but the policy must remain deterministic.
        let first = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let second = NSRect(x: 600, y: 0, width: 1440, height: 900)

        let index = ScreenSelectionPolicy.selectedIndex(
            pointerLocation: NSPoint(x: 1000, y: 400),
            screenFrames: [first, second],
            mainScreenIndex: 0
        )

        XCTAssertEqual(index, 0)
    }

    func testSelectsNegativeOriginScreenWhenPointerWithinIt() {
        let main = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let left = NSRect(x: -1080, y: 0, width: 1080, height: 1920)

        let index = ScreenSelectionPolicy.selectedIndex(
            pointerLocation: NSPoint(x: -500, y: 400),
            screenFrames: [main, left],
            mainScreenIndex: 0
        )

        XCTAssertEqual(index, 1)
    }

    func testSelectsVerticallyStackedScreenWhenPointerWithinIt() {
        let main = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let top = NSRect(x: 0, y: 900, width: 1440, height: 900)

        let index = ScreenSelectionPolicy.selectedIndex(
            pointerLocation: NSPoint(x: 500, y: 1200),
            screenFrames: [main, top],
            mainScreenIndex: 0
        )

        XCTAssertEqual(index, 1)
    }

    func testUnmatchedPointerFallsBackToMainScreen() {
        let main = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let other = NSRect(x: 1440, y: 0, width: 1080, height: 1920)

        let index = ScreenSelectionPolicy.selectedIndex(
            pointerLocation: NSPoint(x: 10_000, y: 10_000),
            screenFrames: [main, other],
            mainScreenIndex: 1
        )

        XCTAssertEqual(index, 1)
    }

    func testUnmatchedPointerFallsBackToMainScreenWhenMainIsNotFirst() {
        let other = NSRect(x: 1440, y: 0, width: 1080, height: 1920)
        let main = NSRect(x: 0, y: 0, width: 1440, height: 900)

        let index = ScreenSelectionPolicy.selectedIndex(
            pointerLocation: NSPoint(x: -5_000, y: -5_000),
            screenFrames: [other, main],
            mainScreenIndex: 1
        )

        XCTAssertEqual(index, 1)
    }

    func testUnmatchedPointerWithoutMainScreenIndexReturnsNil() {
        let main = NSRect(x: 0, y: 0, width: 1440, height: 900)

        let index = ScreenSelectionPolicy.selectedIndex(
            pointerLocation: NSPoint(x: 10_000, y: 10_000),
            screenFrames: [main],
            mainScreenIndex: nil
        )

        XCTAssertNil(index)
    }

    func testOutOfBoundsMainScreenIndexReturnsNilWhenPointerUnmatched() {
        let main = NSRect(x: 0, y: 0, width: 1440, height: 900)

        let index = ScreenSelectionPolicy.selectedIndex(
            pointerLocation: NSPoint(x: 10_000, y: 10_000),
            screenFrames: [main],
            mainScreenIndex: 5
        )

        XCTAssertNil(index)
    }

    func testEmptyScreenListReturnsNilEvenWithMainScreenIndex() {
        let index = ScreenSelectionPolicy.selectedIndex(
            pointerLocation: NSPoint(x: 100, y: 100),
            screenFrames: [],
            mainScreenIndex: 0
        )

        XCTAssertNil(index)
    }
}
