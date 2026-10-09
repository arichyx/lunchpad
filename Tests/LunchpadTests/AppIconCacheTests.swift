import AppKit
import XCTest
@testable import Lunchpad

final class AppIconCacheTests: XCTestCase {
    func testInvalidationRemovesValueStoredByAlreadyRunningLoad() {
        let url = URL(fileURLWithPath: "/Applications/Changing.app")
        let firstLoadStarted = DispatchSemaphore(value: 0)
        let allowFirstLoadToFinish = DispatchSemaphore(value: 0)
        let loadCount = LoadCounter()

        let cache = AppIconCache { _ in
            let currentLoad = loadCount.increment()

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
        XCTAssertEqual(loadCount.value, 2)
    }

    func testRasterizedIconHasOneBitmapAtTheRequestedPixelSize() throws {
        let source = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.systemRed.setFill()
            rect.fill()
            return true
        }

        let icon = AppIconCache.rasterized(source, pointSize: 88, scale: 2)

        XCTAssertEqual(icon.size, NSSize(width: 88, height: 88))
        XCTAssertEqual(icon.representations.count, 1)
        let representation = try XCTUnwrap(icon.representations.first)
        XCTAssertEqual(representation.pixelsWide, 176)
        XCTAssertEqual(representation.pixelsHigh, 176)
    }

    func testWorkspaceIconRasterizesOffTheMainThread() throws {
        let appPath = "/System/Applications/Calculator.app"
        guard FileManager.default.fileExists(atPath: appPath) else {
            throw XCTSkip("Calculator is not installed")
        }
        var rasterized: NSImage?
        DispatchQueue.global(qos: .userInitiated).sync {
            rasterized = AppIconCache.rasterized(
                NSWorkspace.shared.icon(forFile: appPath),
                scale: 2
            )
        }

        let icon = try XCTUnwrap(rasterized)
        var rect = NSRect(origin: .zero, size: icon.size)
        let image = try XCTUnwrap(icon.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: image)
        let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        XCTAssertGreaterThan(center.alphaComponent, 0.5)
    }
}

private final class LoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
