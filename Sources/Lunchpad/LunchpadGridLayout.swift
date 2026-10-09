import AppKit

/// Distributes a fixed 7x5 grid across the available area without scrollable content.
final class LunchpadGridLayout: NSCollectionViewLayout {
    private let columns: Int
    private let rows: Int
    /// Scaled by `LunchpadGridMetrics` on small displays.
    var itemSize: NSSize {
        didSet {
            guard itemSize != oldValue else { return }
            invalidateLayout()
        }
    }
    private var cachedAttributes: [NSCollectionViewLayoutAttributes] = []

    init(columns: Int, rows: Int, itemSize: NSSize) {
        self.columns = columns
        self.rows = rows
        self.itemSize = itemSize
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }

        let count = collectionView.numberOfItems(inSection: 0)
        cachedAttributes = (0..<count).map { item in
            let attributes = NSCollectionViewLayoutAttributes(
                forItemWith: IndexPath(item: item, section: 0)
            )
            attributes.frame = frameForSlot(at: item)
            return attributes
        }
    }

    override var collectionViewContentSize: NSSize {
        collectionView?.bounds.size ?? .zero
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        cachedAttributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        cachedAttributes.first { $0.indexPath == indexPath }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        true
    }

    /// The frame a grid slot occupies for the current bounds, valid for empty slots too.
    /// Drag feedback highlights positions that hold no collection-view item.
    func frameForSlot(at index: Int) -> NSRect {
        let bounds = collectionView?.bounds ?? .zero
        let horizontalGap = spacing(
            available: bounds.width,
            slots: columns,
            itemLength: itemSize.width
        )
        let verticalGap = spacing(
            available: bounds.height,
            slots: rows,
            itemLength: itemSize.height
        )
        let row = index / columns
        let column = index % columns
        return NSRect(
            x: CGFloat(column) * (itemSize.width + horizontalGap),
            y: CGFloat(row) * (itemSize.height + verticalGap),
            width: itemSize.width,
            height: itemSize.height
        )
    }

    private func spacing(available: CGFloat, slots: Int, itemLength: CGFloat) -> CGFloat {
        guard slots > 1 else { return 0 }
        return max(0, (available - CGFloat(slots) * itemLength) / CGFloat(slots - 1))
    }
}
