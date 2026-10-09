import AppKit
import XCTest
@testable import Lunchpad

@MainActor
final class DiscreteWheelPagingTests: XCTestCase {
    private var collectionView: LunchpadCollectionView!
    private var pageDeltas: [Int] = []

    override func setUp() async throws {
        try await super.setUp()
        collectionView = LunchpadCollectionView()
        pageDeltas = []
        collectionView.onPageDelta = { [weak self] in self?.pageDeltas.append($0) }
    }

    override func tearDown() async throws {
        collectionView = nil
        try await super.tearDown()
    }

    func testOneVerticalNotchTurnsOnePage() {
        collectionView.handleDiscreteWheel(
            deltaX: 0, deltaY: -1, hasPreciseDeltas: false, timestamp: 10
        )
        collectionView.handleDiscreteWheel(
            deltaX: 0, deltaY: 1, hasPreciseDeltas: false, timestamp: 11
        )

        XCTAssertEqual(pageDeltas, [1, -1])
    }

    func testOneHorizontalNotchTurnsOnePage() {
        collectionView.handleDiscreteWheel(
            deltaX: -1, deltaY: 0, hasPreciseDeltas: false, timestamp: 10
        )

        XCTAssertEqual(pageDeltas, [1])
    }

    func testRapidNotchesTurnAtMostOnePagePerInterval() {
        for step in 0..<5 {
            collectionView.handleDiscreteWheel(
                deltaX: 0,
                deltaY: -1,
                hasPreciseDeltas: false,
                timestamp: 10 + Double(step) * 0.05
            )
        }

        XCTAssertEqual(pageDeltas, [1])
    }

    func testPreciseDeltasAccumulateBeforeTurning() {
        collectionView.handleDiscreteWheel(
            deltaX: -10, deltaY: 0, hasPreciseDeltas: true, timestamp: 10
        )
        XCTAssertTrue(pageDeltas.isEmpty)

        collectionView.handleDiscreteWheel(
            deltaX: -15, deltaY: 0, hasPreciseDeltas: true, timestamp: 10.1
        )
        XCTAssertEqual(pageDeltas, [1])
    }

    func testDominantAxisDecidesDirection() {
        collectionView.handleDiscreteWheel(
            deltaX: 2, deltaY: -1, hasPreciseDeltas: false, timestamp: 10
        )

        XCTAssertEqual(pageDeltas, [-1])
    }
}
