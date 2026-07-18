import ApplicationMonitorKit
import Foundation

/// Coalesces frequent, non-transactional filesystem events into a stable Lunchpad catalog.
final class ApplicationCatalogSynchronizer: @unchecked Sendable {
    /// Bool reports catalog metadata changes. Set contains icon paths to invalidate; nil means all.
    var onCatalogRefresh: (@MainActor ([LunchpadItem], Bool, Set<String>?) -> Void)?

    private let scanner: AppScanner
    private var layoutStore: LunchpadLayoutStore?
    private let monitor: ApplicationDirectoryMonitor
    private let queue = DispatchQueue(
        label: "com.arichyx.lunchpad.application-catalog-synchronizer",
        qos: .utility
    )
    private let eventGenerationLock = NSLock()
    private let quietDelay: TimeInterval
    private let stabilityDelay: TimeInterval

    private var observedEventGeneration: UInt64 = 0
    private var scheduledQuietScan: DispatchWorkItem?
    private var scheduledStabilityScan: DispatchWorkItem?
    private var lastCatalogSignature: [String]?
    private var pendingIconInvalidationPaths = Set<String>()
    private var shouldInvalidateAllIcons = false
    private var isRunning = false

    init(
        scanner: AppScanner,
        layoutStore: LunchpadLayoutStore?,
        quietDelay: TimeInterval = 1.0,
        stabilityDelay: TimeInterval = 0.9
    ) {
        self.scanner = scanner
        self.layoutStore = layoutStore
        self.quietDelay = quietDelay
        self.stabilityDelay = stabilityDelay
        monitor = ApplicationDirectoryMonitor(
            paths: scanner.monitoredRoots,
            latency: 0.5
        )
    }

    deinit {
        stop()
    }

    /// Start monitoring before the initial scan so changes during startup are not lost.
    func start() throws {
        queue.sync {
            isRunning = true
        }
        monitor.onEvents = { [weak self] batch in
            self?.receive(batch)
        }
        do {
            try monitor.start()
        } catch {
            queue.sync {
                isRunning = false
            }
            throw error
        }
    }

    func stop() {
        monitor.stop()
        queue.sync {
            isRunning = false
            scheduledQuietScan?.cancel()
            scheduledStabilityScan?.cancel()
            scheduledQuietScan = nil
            scheduledStabilityScan = nil
        }
    }

    /// Initial loading uses the same serial queue to avoid concurrent SQLite reconciliation.
    func loadInitialCatalog() -> [LunchpadItem] {
        queue.sync {
            do {
                let items = try loadCatalog()
                lastCatalogSignature = catalogSignature(items)
                return items
            } catch {
                // Preserve the flat-layout fallback after initial database setup fails.
                print("⚠️ 布局数据库不可用，使用平铺布局：\(error)")
                layoutStore = nil
                let items = scanner.scanApplicationsFlat()
                lastCatalogSignature = catalogSignature(items)
                return items
            }
        }
    }

    private func receive(_ batch: ApplicationDirectoryChangeBatch) {
        guard batch.containsRealChanges else { return }

        let changedBundlePaths = Set(batch.events.compactMap {
            applicationBundlePath(containing: $0.path)
        })
        let requiresAllIconInvalidation = batch.requiresFullRescan
            || changedBundlePaths.isEmpty

        eventGenerationLock.lock()
        observedEventGeneration &+= 1
        let generation = observedEventGeneration
        eventGenerationLock.unlock()

        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            if requiresAllIconInvalidation {
                self.shouldInvalidateAllIcons = true
                self.pendingIconInvalidationPaths.removeAll(keepingCapacity: true)
            } else if !self.shouldInvalidateAllIcons {
                self.pendingIconInvalidationPaths.formUnion(changedBundlePaths)
            }
            if batch.requiresFullRescan {
                print("应用目录事件丢失或根目录变化，将执行恢复性全量扫描")
            }
            if batch.requiresStreamRestart {
                // Rebuild monitoring from the nearest existing parent after a root moves or disappears.
                self.monitor.stop()
                do {
                    try self.monitor.start()
                } catch {
                    print("⚠️ 重建应用目录监听失败：\(error)")
                }
            }
            self.scheduleFirstSnapshot(for: generation, after: self.quietDelay)
        }
    }

    private func scheduleFirstSnapshot(for generation: UInt64, after delay: TimeInterval) {
        scheduledQuietScan?.cancel()
        scheduledStabilityScan?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.captureFirstSnapshot(for: generation)
        }
        scheduledQuietScan = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func captureFirstSnapshot(for generation: UInt64) {
        guard isRunning, isLatest(generation) else { return }
        let firstSnapshot = scanner.captureStabilitySnapshot()

        let work = DispatchWorkItem { [weak self] in
            self?.finishStabilityCheck(
                firstSnapshot: firstSnapshot,
                generation: generation
            )
        }
        scheduledStabilityScan = work
        queue.asyncAfter(deadline: .now() + stabilityDelay, execute: work)
    }

    private func finishStabilityCheck(
        firstSnapshot: [ApplicationBundleFingerprint],
        generation: UInt64
    ) {
        guard isRunning, isLatest(generation) else { return }
        let secondSnapshot = scanner.captureStabilitySnapshot()

        guard firstSnapshot == secondSnapshot else {
            // Keep waiting while key files change, even if FSEvents is temporarily quiet.
            scheduleFirstSnapshot(for: generation, after: stabilityDelay)
            return
        }

        do {
            let items = try loadCatalog()
            // Discard this result if another event arrives during scanning; the next generation
            // will perform a fresh stability check.
            guard isLatest(generation) else { return }

            let signature = catalogSignature(items)
            let catalogChanged = signature != lastCatalogSignature
            lastCatalogSignature = signature
            let invalidatedIconPaths: Set<String>? = shouldInvalidateAllIcons
                ? nil
                : pendingIconInvalidationPaths
            shouldInvalidateAllIcons = false
            pendingIconInvalidationPaths.removeAll(keepingCapacity: true)
            DispatchQueue.main.async { [weak self] in
                self?.onCatalogRefresh?(items, catalogChanged, invalidatedIconPaths)
            }
        } catch {
            // A database error must not crash the resident process. Preserve the current UI
            // and retry after the next directory event.
            print("⚠️ 更新应用目录失败：\(error)")
        }
    }

    private func loadCatalog() throws -> [LunchpadItem] {
        if let layoutStore {
            return try scanner.scanApplications(using: layoutStore)
        }
        return scanner.scanApplicationsFlat()
    }

    private func isLatest(_ generation: UInt64) -> Bool {
        eventGenerationLock.lock()
        defer { eventGenerationLock.unlock() }
        return observedEventGeneration == generation
    }

    private func applicationBundlePath(containing eventPath: String) -> String? {
        var url = URL(fileURLWithPath: eventPath).standardizedFileURL
        while url.path != "/" {
            if url.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame {
                return url.path
            }
            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path else { return nil }
            url = parent
        }
        return nil
    }

    /// Includes order, display names, paths, folder assignments, and search aliases; icons load
    /// on demand. Aliases are joined in deterministic insertion order so an alias-only bundle
    /// update refreshes an active search.
    private func catalogSignature(_ items: [LunchpadItem]) -> [String] {
        items.flatMap { item -> [String] in
            switch item {
            case .app(let app):
                return [
                    "app\u{0}\(app.identifier)\u{0}\(app.name)\u{0}\(app.url.path)"
                        + "\u{0}\(app.creationDate?.timeIntervalSinceReferenceDate ?? -1)"
                        + "\u{0}\(app.modificationDate?.timeIntervalSinceReferenceDate ?? -1)"
                        + "\u{0}\(app.searchAliases.joined(separator: "\u{1}"))",
                ]
            case .folder(let folder):
                return [
                    "folder\u{0}\(folder.identifier)\u{0}\(folder.name)\u{0}\(folder.isSystem)",
                ] + folder.apps.map {
                    "member\u{0}\(folder.identifier)\u{0}\($0.identifier)\u{0}\($0.name)"
                        + "\u{0}\($0.url.path)"
                        + "\u{0}\($0.creationDate?.timeIntervalSinceReferenceDate ?? -1)"
                        + "\u{0}\($0.modificationDate?.timeIntervalSinceReferenceDate ?? -1)"
                        + "\u{0}\($0.searchAliases.joined(separator: "\u{1}"))"
                }
            }
        }
    }
}
