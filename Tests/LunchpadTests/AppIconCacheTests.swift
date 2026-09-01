import AppKit
import XCTest
@testable import Lunchpad

final class AppIconCacheTests: XCTestCase {
    func testInvalidationRemovesValueStoredByAlreadyRunningLoad() {
        let url = URL(fileURLWithPath: "/Applications/Changing.app")
        let firstLoadStarted = DispatchSemaphore(value: 0)
        let allowFirstLoadToFinish = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var loadCount = 0

        let cache = AppIconCache { _ in
            lock.lock()
            loadCount += 1
            let currentLoad = loadCount
            lock.unlock()

            if currentLoad == 1 {
                firstLoadStarted.signal()
                _ = allowFirstLoadToFinish.wait(timeout: .now() + 2)
            }
            return NSImage(size: NSSize(width: 80, height: 80))
        }
        let app = AppItem(
            identifier: "app.changing",
            bundleIdentifier: "app.changing",
            name: "Changing",
            url: url,
            creationDate: nil,
            modificationDate: nil
        )

        cache.prewarm([app])
        XCTAssertEqual(firstLoadStarted.wait(timeout: .now() + 1), .success)
        cache.invalidate(paths: [url.path])
        allowFirstLoadToFinish.signal()
        cache.waitForPendingLoads()

        // If the in-flight load repopulated the invalidated entry, this is a cache hit and the
        // loader remains at one call. The serialized second removal requires a fresh load.
        _ = cache.icon(for: url)
        lock.lock()
        let finalLoadCount = loadCount
        lock.unlock()
        XCTAssertEqual(finalLoadCount, 2)
    }
}
