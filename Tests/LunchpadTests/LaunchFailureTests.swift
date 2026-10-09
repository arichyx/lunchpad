import AppKit
import XCTest
@testable import Lunchpad

@MainActor
final class LaunchFailureTests: XCTestCase {
    func testFailedLaunchClosesFirstAndThenReportsTheApplication() throws {
        let app = AppItem(
            identifier: "app.broken",
            bundleIdentifier: "app.broken",
            name: "Broken",
            url: URL(fileURLWithPath: "/Applications/Broken.app"),
            creationDate: nil,
            modificationDate: nil
        )
        let grid = IconGridView(items: [.app(app)], localizer: AppLocalizer(language: .english))
        var events: [String] = []
        let reported = expectation(description: "launch failure reported")
        grid.applicationOpener = { url, completion in
            events.append("open \(url.lastPathComponent)")
            DispatchQueue.global().async {
                completion(CocoaError(.fileNoSuchFile))
            }
        }
        grid.onLaunch = { events.append("close") }
        grid.onLaunchFailure = { failedApp, _ in
            XCTAssertTrue(Thread.isMainThread)
            events.append("failed \(failedApp.name)")
            reported.fulfill()
        }

        XCTAssertTrue(grid.handleNavigationCommand(.right))
        XCTAssertTrue(grid.activateActiveItemOrFirstSearchResult())

        wait(for: [reported], timeout: 2)
        XCTAssertEqual(events, ["close", "open Broken.app", "failed Broken"])
    }

    func testSuccessfulLaunchReportsNothing() {
        let app = AppItem(
            identifier: "app.fine",
            bundleIdentifier: "app.fine",
            name: "Fine",
            url: URL(fileURLWithPath: "/Applications/Fine.app"),
            creationDate: nil,
            modificationDate: nil
        )
        let grid = IconGridView(items: [.app(app)], localizer: AppLocalizer(language: .english))
        grid.applicationOpener = { _, completion in completion(nil) }
        grid.onLaunchFailure = { _, _ in XCTFail("A successful launch must not report failure") }

        grid.handleNavigationCommand(.right)
        grid.activateActiveItemOrFirstSearchResult()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
