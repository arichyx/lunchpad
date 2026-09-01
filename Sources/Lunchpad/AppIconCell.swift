import AppKit

/// NSWorkspace icon loading touches bundles and Launch Services, so page transitions must hit memory.
final class AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    /// Icon loads are filesystem and Launch Services work and must never block the main thread
    /// while the UI is animating (a swipe can enqueue a hundred of them). NSCache is thread-safe.
    private let loadQueue = DispatchQueue(label: "com.arichyx.Lunchpad.icon-cache", qos: .userInitiated)
    /// Pending load state, owned exclusively by `loadQueue`.
    private let loadState = IconLoadState()
    private let iconLoader: (URL) -> NSImage

    init(iconLoader: @escaping (URL) -> NSImage = { url in
        NSWorkspace.shared.icon(forFile: url.path)
    }) {
        self.iconLoader = iconLoader
        cache.countLimit = 512
    }

    /// Synchronous lookup-and-load for code that must have an image now (cell configuration
    /// during reloads). Prewarming normally keeps this a memory hit.
    func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let icon = iconLoader(url)
        icon.size = NSSize(width: 80, height: 80)
        cache.setObject(icon, forKey: key)
        return icon
    }

    /// Memory-only lookup for latency-sensitive UI (swipe page snapshots). A miss never loads
    /// synchronously; the URL joins the background load queue instead, and callers may poll
    /// again later as it fills.
    func cachedIcon(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        enqueueLoads([url])
        return nil
    }

    /// In-place upgrades reuse paths, so path-keyed icons require explicit invalidation.
    func invalidateAll() {
        cache.removeAllObjects()
        loadQueue.async { [cache, loadState] in
            loadState.pendingURLs.removeAll()
            loadState.queuedURLs.removeAll()
            // A load already executing when the immediate invalidation ran may have inserted an
            // obsolete image afterward. Clear again on the serialized load queue before any new
            // prewarm request can run.
            cache.removeAllObjects()
        }
    }

    func invalidate(paths: Set<String>) {
        for path in paths {
            cache.removeObject(forKey: path as NSString)
        }
        loadQueue.async { [cache, loadState] in
            loadState.pendingURLs.removeAll { paths.contains($0.path) }
            for path in paths {
                loadState.queuedURLs.remove(URL(fileURLWithPath: path))
                // Match invalidateAll's second pass: discard a value written by an in-flight
                // loader after the caller's immediate removal.
                cache.removeObject(forKey: path as NSString)
            }
        }
    }

    /// Warms the cache off the main thread; a swipe's just-requested URLs merge into the same
    /// queue rather than competing with it.
    func prewarm(_ apps: [AppItem]) {
        enqueueLoads(apps.map(\.url))
    }

    private func enqueueLoads(_ urls: [URL]) {
        loadQueue.async { [cache, iconLoader, loadState] in
            let fresh = urls.filter { loadState.queuedURLs.insert($0).inserted }
            guard !fresh.isEmpty else { return }
            loadState.pendingURLs.append(contentsOf: fresh)
            while let url = loadState.pendingURLs.first {
                loadState.pendingURLs.removeFirst()
                loadState.queuedURLs.remove(url)
                let key = url.path as NSString
                if cache.object(forKey: key) != nil { continue }
                let icon = iconLoader(url)
                icon.size = NSSize(width: 80, height: 80)
                cache.setObject(icon, forKey: key)
            }
        }
    }

    /// Test synchronization point for deterministic cache-race coverage.
    func waitForPendingLoads() {
        loadQueue.sync {}
    }
}

/// Mutable pending-load state captured by `loadQueue` closures; array and set literals are
/// immutable when captured directly.
private final class IconLoadState {
    var pendingURLs: [URL] = []
    var queuedURLs = Set<URL>()
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

    /// Same as `configure(with:)` but never loads synchronously; a cache miss leaves the tile
    /// empty until a later configure pass repaints it. Used by swipe page snapshots.
    func configureCached(with apps: [AppItem]) {
        for (index, imageView) in imageViews.enumerated() {
            guard index < apps.count else {
                imageView.image = nil
                imageView.isHidden = true
                continue
            }
            imageView.image = AppIconCache.shared.cachedIcon(for: apps[index].url)
            imageView.isHidden = false
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
    private let keyboardFocusLayer = CALayer()

    /// A rounded translucent highlight behind the icon that composes with pressed alpha feedback.
    /// Setting it always re-applies the value, so reused cells cannot retain a stale active state.
    var isKeyboardActive: Bool = false {
        didSet { applyKeyboardActiveAppearance() }
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.imageAlignment = .alignCenter
        iconView.translatesAutoresizingMaskIntoConstraints = false

        folderIconView.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.cell?.truncatesLastVisibleLine = true
        label.cell?.wraps = true
        label.translatesAutoresizingMaskIntoConstraints = false

        // Insert the focus layer behind the icon so it covers applications and folders identically
        // without replacing the pressed-alpha feedback applied directly to the cell's view.
        keyboardFocusLayer.cornerRadius = 18
        keyboardFocusLayer.cornerCurve = .continuous
        keyboardFocusLayer.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        keyboardFocusLayer.borderColor = NSColor.white.withAlphaComponent(0.42).cgColor
        keyboardFocusLayer.borderWidth = 1
        keyboardFocusLayer.opacity = 0

        container.layer?.addSublayer(keyboardFocusLayer)
        container.addSubview(iconView)
        container.addSubview(folderIconView)
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

    override func viewDidLayout() {
        super.viewDidLayout()
        // Align the backing layer frame with the icon area after Auto Layout settles.
        let iconFrame = iconView.frame
        let padding: CGFloat = 8
        keyboardFocusLayer.frame = NSRect(
            x: iconFrame.minX - padding,
            y: iconFrame.minY - padding,
            width: iconFrame.width + padding * 2,
            height: iconFrame.height + padding * 2
        )
    }

    func configure(with item: LunchpadItem) {
        // Reused collection items must not inherit a transfer preview's hidden label or opacity.
        setCrossPageTransferAppearance(false, animated: false)
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

        // Apply the current keyboard-active flag on every configuration so reused cells
        // cannot carry the previous item's highlight.
        applyKeyboardActiveAppearance()
    }

    /// A displaced item remains identifiable at the screen edge, but its reduced opacity and
    /// hidden name distinguish the transfer hint from another occupied grid slot.
    func setCrossPageTransferAppearance(_ isActive: Bool, animated: Bool) {
        label.isHidden = isActive
        let alphaValue: CGFloat = isActive ? 0.42 : 1
        if animated {
            view.animator().alphaValue = alphaValue
        } else {
            view.alphaValue = alphaValue
        }
    }

    private func applyKeyboardActiveAppearance() {
        keyboardFocusLayer.opacity = isKeyboardActive ? 1 : 0
    }
}
