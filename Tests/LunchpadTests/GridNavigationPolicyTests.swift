import XCTest
@testable import Lunchpad

final class GridNavigationPolicyTests: XCTestCase {
    private let columns = 7
    private let rows = 5
    private let pageCapacity = 35

    // MARK: - Entry decisions

    func testEntryActivateFirstForEveryDirectionWithoutSearchQuery() {
        for direction in [.up, .down, .left, .right] as [GridNavigationDirection] {
            XCTAssertEqual(
                GridNavigationPolicy.entryDecision(
                    direction: direction,
                    hasActiveItem: false,
                    visibleItemCount: 5,
                    hasNonEmptySearchQuery: false,
                    caretAtEndOfText: false
                ),
                .activate(index: 0),
                "Expected activate(index: 0) for direction \(direction) without a query"
            )
        }
    }

    func testEntryMoveWhenAnItemIsActiveRegardlessOfQuery() {
        for direction in [.up, .down, .left, .right] as [GridNavigationDirection] {
            XCTAssertEqual(
                GridNavigationPolicy.entryDecision(
                    direction: direction,
                    hasActiveItem: true,
                    visibleItemCount: 5,
                    hasNonEmptySearchQuery: false,
                    caretAtEndOfText: false
                ),
                .move
            )
            XCTAssertEqual(
                GridNavigationPolicy.entryDecision(
                    direction: direction,
                    hasActiveItem: true,
                    visibleItemCount: 5,
                    hasNonEmptySearchQuery: true,
                    caretAtEndOfText: true
                ),
                .move
            )
        }
    }

    func testEntryDownActivatesFirstResultInNonEmptySearch() {
        XCTAssertEqual(
            GridNavigationPolicy.entryDecision(
                direction: .down,
                hasActiveItem: false,
                visibleItemCount: 5,
                hasNonEmptySearchQuery: true,
                caretAtEndOfText: false
            ),
            .activate(index: 0)
        )
    }

    func testEntryRightAtEndOfTextActivatesSecondResultWhenMultipleVisible() {
        XCTAssertEqual(
            GridNavigationPolicy.entryDecision(
                direction: .right,
                hasActiveItem: false,
                visibleItemCount: 5,
                hasNonEmptySearchQuery: true,
                caretAtEndOfText: true
            ),
            .activate(index: 1)
        )
    }

    func testEntryRightAtEndOfTextActivatesFirstResultWhenOnlyOneVisible() {
        XCTAssertEqual(
            GridNavigationPolicy.entryDecision(
                direction: .right,
                hasActiveItem: false,
                visibleItemCount: 1,
                hasNonEmptySearchQuery: true,
                caretAtEndOfText: true
            ),
            .activate(index: 0)
        )
    }

    func testEntryRightNotAtEndOfTextFallsThroughInNonEmptySearch() {
        XCTAssertEqual(
            GridNavigationPolicy.entryDecision(
                direction: .right,
                hasActiveItem: false,
                visibleItemCount: 5,
                hasNonEmptySearchQuery: true,
                caretAtEndOfText: false
            ),
            .fallThrough
        )
    }

    func testEntryLeftAlwaysFallsThroughInNonEmptySearchBeforeEntry() {
        XCTAssertEqual(
            GridNavigationPolicy.entryDecision(
                direction: .left,
                hasActiveItem: false,
                visibleItemCount: 5,
                hasNonEmptySearchQuery: true,
                caretAtEndOfText: true
            ),
            .fallThrough
        )
    }

    func testEntryUpAlwaysFallsThroughInNonEmptySearchBeforeEntry() {
        XCTAssertEqual(
            GridNavigationPolicy.entryDecision(
                direction: .up,
                hasActiveItem: false,
                visibleItemCount: 5,
                hasNonEmptySearchQuery: true,
                caretAtEndOfText: true
            ),
            .fallThrough
        )
    }

    func testEntryFallThroughWhenPageHasNoVisibleItems() {
        for direction in [.up, .down, .left, .right] as [GridNavigationDirection] {
            XCTAssertEqual(
                GridNavigationPolicy.entryDecision(
                    direction: direction,
                    hasActiveItem: false,
                    visibleItemCount: 0,
                    hasNonEmptySearchQuery: false,
                    caretAtEndOfText: false
                ),
                .fallThrough
            )
        }
    }

    // MARK: - Full-page wrapping

    func testVerticalUpFromTopLeftWrapsToBottomRow() {
        // (row 0, column 0) + Up -> (row 4, column 0)
        let destination = GridNavigationPolicy.move(
            direction: .up,
            activeIndex: 0,
            visibleItemCount: pageCapacity,
            columns: columns,
            rows: rows
        )
        XCTAssertEqual(destination, 4 * columns)
    }

    func testVerticalDownFromBottomRowWrapsToTopRow() {
        // (row 4, column 3) + Down -> (row 0, column 3)
        let startIndex = 4 * columns + 3
        let destination = GridNavigationPolicy.move(
            direction: .down,
            activeIndex: startIndex,
            visibleItemCount: pageCapacity,
            columns: columns,
            rows: rows
        )
        XCTAssertEqual(destination, 3)
    }

    func testHorizontalLeftFromFirstColumnWrapsToLastColumn() {
        // (row 2, column 0) + Left -> (row 2, column 6)
        let startIndex = 2 * columns
        let destination = GridNavigationPolicy.move(
            direction: .left,
            activeIndex: startIndex,
            visibleItemCount: pageCapacity,
            columns: columns,
            rows: rows
        )
        XCTAssertEqual(destination, 2 * columns + (columns - 1))
    }

    func testHorizontalRightFromLastColumnWrapsToFirstColumn() {
        // (row 1, column 6) + Right -> (row 1, column 0)
        let startIndex = 1 * columns + (columns - 1)
        let destination = GridNavigationPolicy.move(
            direction: .right,
            activeIndex: startIndex,
            visibleItemCount: pageCapacity,
            columns: columns,
            rows: rows
        )
        XCTAssertEqual(destination, 1 * columns)
    }

    // MARK: - Single-step movement

    func testRightAdvancesOneColumnOnFullPage() {
        let destination = GridNavigationPolicy.move(
            direction: .right,
            activeIndex: 0,
            visibleItemCount: pageCapacity,
            columns: columns,
            rows: rows
        )
        XCTAssertEqual(destination, 1)
    }

    func testDownAdvancesOneRowOnFullPage() {
        let destination = GridNavigationPolicy.move(
            direction: .down,
            activeIndex: 0,
            visibleItemCount: pageCapacity,
            columns: columns,
            rows: rows
        )
        XCTAssertEqual(destination, columns)
    }

    // MARK: - Partial-page empty-cell probing

    func testRightOnPartialLastRowWrapsBackToFirstOccupiedColumn() {
        // Last row has only two items at columns 0 and 1 (30 visible items, 5*7 - 5).
        // (row 4, column 1) + Right -> skips empty columns 2..6 -> (row 4, column 0)
        let startIndex = 4 * columns + 1
        let destination = GridNavigationPolicy.move(
            direction: .right,
            activeIndex: startIndex,
            visibleItemCount: 30,
            columns: columns,
            rows: rows
        )
        XCTAssertEqual(destination, 4 * columns)
    }

    func testLeftOnPartialLastRowSkipsToLastOccupiedColumn() {
        // (row 4, column 0) + Left -> skips empty columns 6..2 -> (row 4, column 1)
        let startIndex = 4 * columns
        let destination = GridNavigationPolicy.move(
            direction: .left,
            activeIndex: startIndex,
            visibleItemCount: 30,
            columns: columns,
            rows: rows
        )
        XCTAssertEqual(destination, 4 * columns + 1)
    }

    func testVerticalMovementOnSparseColumnRetainsActiveItemWhenNoNeighborExists() {
        // Column 6 only has items on rows 0..3 (visibleItemCount = 30, so row 4 col 6 is empty).
        // (row 3, column 6) + Down -> skip empty (row 4, column 6) -> (row 0, column 6)
        let startIndex = 3 * columns + 6
        let destination = GridNavigationPolicy.move(
            direction: .down,
            activeIndex: startIndex,
            visibleItemCount: 30,
            columns: columns,
            rows: rows
        )
        XCTAssertEqual(destination, 6)
    }

    func testHorizontalMovementOnSingleOccupiedRowRetainsActiveItem() {
        // 5 items on a single row at columns 0..4. Cells 5 and 6 are empty.
        // (row 0, column 4) + Right -> wraps past empty 5,6, then 0,1,2,3 are occupied; first hit is 0.
        let destination = GridNavigationPolicy.move(
            direction: .right,
            activeIndex: 4,
            visibleItemCount: 5,
            columns: columns,
            rows: rows
        )
        XCTAssertEqual(destination, 0)
    }

    // MARK: - Edge cases

    func testEmptyPageReturnsActiveIndex() {
        for direction in [.up, .down, .left, .right] as [GridNavigationDirection] {
            XCTAssertEqual(
                GridNavigationPolicy.move(
                    direction: direction,
                    activeIndex: 0,
                    visibleItemCount: 0,
                    columns: columns,
                    rows: rows
                ),
                0
            )
        }
    }

    func testSingleItemPageRetainsActiveItem() {
        for direction in [.up, .down, .left, .right] as [GridNavigationDirection] {
            XCTAssertEqual(
                GridNavigationPolicy.move(
                    direction: direction,
                    activeIndex: 0,
                    visibleItemCount: 1,
                    columns: columns,
                    rows: rows
                ),
                0
            )
        }
    }

    func testInvalidActiveIndexIsReturnedUnchanged() {
        XCTAssertEqual(
            GridNavigationPolicy.move(
                direction: .down,
                activeIndex: 100,
                visibleItemCount: 10,
                columns: columns,
                rows: rows
            ),
            100
        )
    }

    func testZeroDimensionsReturnActiveIndex() {
        XCTAssertEqual(
            GridNavigationPolicy.move(
                direction: .down,
                activeIndex: 0,
                visibleItemCount: 10,
                columns: 0,
                rows: rows
            ),
            0
        )
        XCTAssertEqual(
            GridNavigationPolicy.move(
                direction: .down,
                activeIndex: 0,
                visibleItemCount: 10,
                columns: columns,
                rows: 0
            ),
            0
        )
    }
}
