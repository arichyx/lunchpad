import AppKit

/// NSWorkspace icon loading touches bundles and Launch Services, so page transitions must hit memory.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private var pendingURLs: [URL] = []
    private var isPrewarming = false

    private init() {
        cache.countLimit = 512
    }

    func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 80, height: 80)
        cache.setObject(icon, forKey: key)
        return icon
    }

    /// In-place upgrades reuse paths, so path-keyed icons require explicit invalidation.
    func invalidateAll() {
        cache.removeAllObjects()
        pendingURLs.removeAll(keepingCapacity: true)
    }

    func invalidate(paths: Set<String>) {
        for path in paths {
            cache.removeObject(forKey: path as NSString)
        }
        pendingURLs.removeAll { paths.contains($0.path) }
    }

    /// Load at most two icons per main-queue turn to preheat without blocking animation frames.
    func prewarm(_ apps: [AppItem]) {
        pendingURLs = apps.map(\.url)
        guard !isPrewarming else { return }
        isPrewarming = true
        DispatchQueue.main.async { [weak self] in
            self?.prewarmNextBatch()
        }
    }

    private func prewarmNextBatch() {
        for _ in 0..<2 {
            guard let url = pendingURLs.first else {
                isPrewarming = false
                return
            }
            pendingURLs.removeFirst()
            _ = icon(for: url)
        }
        DispatchQueue.main.async { [weak self] in
            self?.prewarmNextBatch()
        }
    }
}

/// A classic 3x3 Lunchpad folder preview.
final class FolderIconView: NSView {
    private let imageViews: [NSImageView] = (0..<9).map { _ in
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        layer?.borderWidth = 1

        imageViews.forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let inset: CGFloat = 7
        let gap: CGFloat = 3
        let length = (bounds.width - inset * 2 - gap * 2) / 3

        for (index, imageView) in imageViews.enumerated() {
            let column = index % 3
            let row = 2 - index / 3
            imageView.frame = NSRect(
                x: inset + CGFloat(column) * (length + gap),
                y: inset + CGFloat(row) * (length + gap),
                width: length,
                height: length
            )
        }
    }

    func configure(with apps: [AppItem]) {
        for (index, imageView) in imageViews.enumerated() {
            if index < apps.count {
                imageView.image = AppIconCache.shared.icon(for: apps[index].url)
                imageView.isHidden = false
            } else {
                imageView.image = nil
                imageView.isHidden = true
            }
        }
    }
}

/// One cell contains an 80-point icon and a name truncated to two lines.
/// Created in code through `register(_:forItemWithIdentifier:)` and `loadView`, without a nib.
final class AppIconCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("AppIconCell")

    private let iconView = NSImageView()
    private let folderIconView = FolderIconView()
    private let label = NSTextField(labelWithString: "")

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.imageAlignment = .alignCenter
        iconView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconView)

        folderIconView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(folderIconView)

        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.cell?.truncatesLastVisibleLine = true
        label.cell?.wraps = true
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 80),
            iconView.heightAnchor.constraint(equalToConstant: 80),

            folderIconView.topAnchor.constraint(equalTo: container.topAnchor),
            folderIconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            folderIconView.widthAnchor.constraint(equalToConstant: 80),
            folderIconView.heightAnchor.constraint(equalToConstant: 80),

            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])

        view = container
    }

    func configure(with item: LunchpadItem) {
        label.stringValue = item.name

        switch item {
        case .app(let app):
            iconView.image = AppIconCache.shared.icon(for: app.url)
            iconView.isHidden = false
            folderIconView.isHidden = true
        case .folder(let folder):
            iconView.image = nil
            iconView.isHidden = true
            folderIconView.configure(with: Array(folder.apps.prefix(9)))
            folderIconView.isHidden = false
        }
    }
}
