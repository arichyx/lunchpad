import XCTest
@testable import Lunchpad

final class SpaceChangeDismissalPolicyTests: XCTestCase {
    func testVisibleAndIdleDismisses() {
        XCTAssertEqual(
            SpaceChangeDismissalPolicy.decision(isVisible: true, isAnimatingClose: false),
            .dismiss
        )
    }

    func testHiddenIgnores() {
        XCTAssertEqual(
            SpaceChangeDismissalPolicy.decision(isVisible: false, isAnimatingClose: false),
            .ignore
        )
    }

    func testVisibleButAlreadyClosingIgnoresToKeepCloseIdempotent() {
        // Race with another dismissal: the window's close() path is already in flight.
        XCTAssertEqual(
            SpaceChangeDismissalPolicy.decision(isVisible: true, isAnimatingClose: true),
            .ignore
        )
    }

    func testHiddenAndAnimatingCloseIgnores() {
        XCTAssertEqual(
            SpaceChangeDismissalPolicy.decision(isVisible: false, isAnimatingClose: true),
            .ignore
        )
    }
}
