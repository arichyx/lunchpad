import AppKit
import XCTest
@testable import Lunchpad

final class LunchpadGridMetricsTests: XCTestCase {
    private let notchInsets = NSEdgeInsets(top: 37, left: 0, bottom: 0, right: 0)

    func testRoomyDisplayKeepsClassicMetrics() {
        let metrics = LunchpadGridMetrics.fitting(
            availableWidth: 1728,
            availableHeight: 1117 - 70,
            insets: notchInsets
        )

        XCTAssertEqual(metrics, .standard)
    }

    func testMissingWidthKeepsStandardHorizontalMetrics() {
        let metrics = LunchpadGridMetrics.fitting(
            availableWidth: nil,
            availableHeight: 1000,
            insets: NSEdgeInsets(top: 40, left: 0, bottom: 40, right: 0)
        )

        XCTAssertEqual(metrics.scale, 1)
        XCTAssertEqual(metrics.horizontalPadding, LunchpadGridMetrics.standardHorizontalPadding)
    }

    func testSlightlyShortDisplayShrinksSpacingBeforeItems() {
        let insets = NSEdgeInsets(top: 30, left: 0, bottom: 0, right: 0)
        let metrics = LunchpadGridMetrics.fitting(
            availableWidth: 1440,
            availableHeight: 770,
            insets: insets
        )

        XCTAssertEqual(metrics.scale, 1)
        XCTAssertLessThan(metrics.topPadding, LunchpadGridMetrics.standard.topPadding)
        XCTAssertEqual(totalHeight(of: metrics, insets: insets), 770, accuracy: 0.001)
    }

    func testNarrowDisplayShrinksMarginsBeforeItems() {
        let metrics = LunchpadGridMetrics.fitting(
            availableWidth: 1024,
            availableHeight: 1000,
            insets: NSEdgeInsets()
        )

        XCTAssertEqual(metrics.scale, 1)
        XCTAssertEqual(metrics.horizontalPadding, (1024 - 840) / 2, accuracy: 0.001)
        XCTAssertLessThanOrEqual(totalWidth(of: metrics), 1024)
    }

    /// A 13-inch MacBook Air at its largest-text scaled resolution with a bottom Dock.
    func testSmallScaledDisplayScalesItemsToFit() {
        let height: CGFloat = 665 - 60
        let metrics = LunchpadGridMetrics.fitting(
            availableWidth: 1024,
            availableHeight: height,
            insets: notchInsets
        )

        XCTAssertLessThan(metrics.scale, 1)
        XCTAssertGreaterThanOrEqual(metrics.scale, LunchpadGridMetrics.minimumScale)
        XCTAssertLessThanOrEqual(totalHeight(of: metrics, insets: notchInsets), height + 0.001)
        XCTAssertLessThanOrEqual(totalWidth(of: metrics), 1024)
        XCTAssertEqual(metrics.labelLineLimit, 1)
        XCTAssertGreaterThanOrEqual(metrics.labelFontSize, LunchpadGridMetrics.minimumLabelFontSize)
    }

    func testVeryNarrowDisplayScalesItemsHorizontally() {
        let metrics = LunchpadGridMetrics.fitting(
            availableWidth: 800,
            availableHeight: 1000,
            insets: NSEdgeInsets()
        )

        XCTAssertEqual(metrics.horizontalPadding, LunchpadGridMetrics.minimumHorizontalPadding)
        XCTAssertEqual(metrics.scale, (800 - 48) / 840, accuracy: 0.001)
        XCTAssertLessThanOrEqual(totalWidth(of: metrics), 800 + 0.001)
    }

    func testScaleNeverDropsBelowTheLegibilityFloor() {
        let metrics = LunchpadGridMetrics.fitting(
            availableWidth: 400,
            availableHeight: 300,
            insets: NSEdgeInsets()
        )

        XCTAssertEqual(metrics.scale, LunchpadGridMetrics.minimumScale)
    }

    @MainActor
    func testGridAppliesScaledItemSizeToTheCollectionLayout() throws {
        let grid = IconGridView(items: [], localizer: AppLocalizer(language: .english))

        grid.updateScreenInsets(notchInsets, availableHeight: 605, availableWidth: 1024)

        XCTAssertLessThan(grid.metrics.scale, 1)
        let layout = try XCTUnwrap(
            grid.subviews.compactMap { $0 as? LunchpadCollectionView }.first?
                .collectionViewLayout as? LunchpadGridLayout
        )
        XCTAssertEqual(layout.itemSize, grid.metrics.itemSize)
    }

    private func totalHeight(of metrics: LunchpadGridMetrics, insets: NSEdgeInsets) -> CGFloat {
        insets.top + metrics.topPadding + LunchpadGridMetrics.searchHeight
            + metrics.searchToGridSpacing
            + CGFloat(LunchpadGridMetrics.rows) * metrics.itemSize.height
            + metrics.gridToPageSpacing + LunchpadGridMetrics.pageIndicatorHeight
            + metrics.bottomPadding + insets.bottom
    }

    private func totalWidth(of metrics: LunchpadGridMetrics) -> CGFloat {
        2 * metrics.horizontalPadding
            + CGFloat(LunchpadGridMetrics.columns) * metrics.itemSize.width
    }
}
