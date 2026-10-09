import AppKit

/// Sizes the fixed 7x5 launcher grid for one display.
///
/// The classic Launchpad metrics are used whenever they fit. On smaller or scaled displays the
/// outer margins and vertical spacing shrink first; only when that is not enough do items scale
/// down uniformly, never below `minimumScale`, so every cell stays on screen without overlapping
/// the search field, page indicator, or its neighbors.
struct LunchpadGridMetrics: Equatable {
    static let columns = 7
    static let rows = 5

    static let baseItemSize = NSSize(width: 120, height: 112)
    static let baseIconSide: CGFloat = 80
    static let baseLiftedIconSide: CGFloat = 88
    static let baseLabelSpacing: CGFloat = 8
    static let baseLabelFontSize: CGFloat = 12
    static let minimumLabelFontSize: CGFloat = 10
    static let minimumScale: CGFloat = 0.6

    static let searchHeight: CGFloat = 28
    static let pageIndicatorHeight: CGFloat = 22

    static let standardHorizontalPadding: CGFloat = 128
    static let minimumHorizontalPadding: CGFloat = 24
    static let desiredBottomPadding: CGFloat = 88

    private struct VerticalSpacing {
        let top: CGFloat
        let searchToGrid: CGFloat
        let gridToPage: CGFloat
        let minimumBottom: CGFloat

        var total: CGFloat { top + searchToGrid + gridToPage + minimumBottom }
    }

    private static let standardSpacing = VerticalSpacing(
        top: 30,
        searchToGrid: 36,
        gridToPage: 34,
        minimumBottom: 40
    )
    private static let compactSpacing = VerticalSpacing(
        top: 12,
        searchToGrid: 16,
        gridToPage: 12,
        minimumBottom: 16
    )

    /// Uniform item scale; 1 is the classic size.
    let scale: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let searchToGridSpacing: CGFloat
    let gridToPageSpacing: CGFloat
    let bottomPadding: CGFloat

    static let standard = LunchpadGridMetrics(
        scale: 1,
        horizontalPadding: standardHorizontalPadding,
        topPadding: standardSpacing.top,
        searchToGridSpacing: standardSpacing.searchToGrid,
        gridToPageSpacing: standardSpacing.gridToPage,
        bottomPadding: desiredBottomPadding
    )

    var itemSize: NSSize {
        NSSize(
            width: Self.baseItemSize.width * scale,
            height: Self.baseItemSize.height * scale
        )
    }

    var iconSide: CGFloat { Self.baseIconSide * scale }
    var liftedIconSide: CGFloat { Self.baseLiftedIconSide * scale }
    var labelSpacing: CGFloat { Self.baseLabelSpacing * scale }
    var labelFontSize: CGFloat { max(Self.minimumLabelFontSize, Self.baseLabelFontSize * scale) }
    /// A scaled item no longer has room for a second label line.
    var labelLineLimit: Int { scale < 0.9 ? 1 : 2 }

    /// - Parameters:
    ///   - availableWidth: The interaction window width, or nil to keep the standard horizontal
    ///     metrics.
    ///   - availableHeight: The interaction window height.
    ///   - insets: Menu bar, notch, and Dock insets inside that window.
    static func fitting(
        availableWidth: CGFloat?,
        availableHeight: CGFloat,
        insets: NSEdgeInsets
    ) -> LunchpadGridMetrics {
        let baseGridWidth = CGFloat(columns) * baseItemSize.width
        let baseGridHeight = CGFloat(rows) * baseItemSize.height

        var horizontalPadding = standardHorizontalPadding
        var horizontalScale: CGFloat = 1
        if let availableWidth {
            let width = availableWidth - insets.left - insets.right
            if width >= baseGridWidth + 2 * standardHorizontalPadding {
                horizontalPadding = standardHorizontalPadding
            } else if width >= baseGridWidth + 2 * minimumHorizontalPadding {
                horizontalPadding = (width - baseGridWidth) / 2
            } else {
                horizontalPadding = minimumHorizontalPadding
                horizontalScale = (width - 2 * minimumHorizontalPadding) / baseGridWidth
            }
        }

        let chrome = searchHeight + pageIndicatorHeight
        let budget = availableHeight - insets.top - insets.bottom
        let verticalScale = min(1, (budget - chrome - compactSpacing.total) / baseGridHeight)
        let scale = max(minimumScale, min(1, horizontalScale, verticalScale))

        // Spend whatever height the grid leaves on spacing, between the compact and standard sets.
        let remaining = budget - chrome - baseGridHeight * scale
        let progress = min(
            1,
            max(0, (remaining - compactSpacing.total) / (standardSpacing.total - compactSpacing.total))
        )
        func interpolate(_ keyPath: KeyPath<VerticalSpacing, CGFloat>) -> CGFloat {
            compactSpacing[keyPath: keyPath]
                + (standardSpacing[keyPath: keyPath] - compactSpacing[keyPath: keyPath]) * progress
        }
        let topPadding = interpolate(\.top)
        let searchToGridSpacing = interpolate(\.searchToGrid)
        let gridToPageSpacing = interpolate(\.gridToPage)
        let bottomPadding = min(
            desiredBottomPadding,
            max(
                interpolate(\.minimumBottom),
                remaining - topPadding - searchToGridSpacing - gridToPageSpacing
            )
        )

        return LunchpadGridMetrics(
            scale: scale,
            horizontalPadding: horizontalPadding,
            topPadding: topPadding,
            searchToGridSpacing: searchToGridSpacing,
            gridToPageSpacing: gridToPageSpacing,
            bottomPadding: bottomPadding
        )
    }
}
