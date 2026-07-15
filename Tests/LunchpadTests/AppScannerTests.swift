import Foundation
import XCTest
@testable import Lunchpad

final class AppScannerTests: XCTestCase {
    func testDiscoveryReadsBundleCreationAndModificationDates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LunchpadScannerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let root = directory.appendingPathComponent("Applications", isDirectory: true)
        let appURL = root.appendingPathComponent("Fixture.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let executableDirectory = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(
            at: executableDirectory,
            withIntermediateDirectories: true
        )

        let info: [String: Any] = [
            "CFBundleIdentifier": "test.fixture",
            "CFBundleName": "Fixture",
            "CFBundleExecutable": "Fixture",
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        XCTAssertTrue(FileManager.default.createFile(
            atPath: executableDirectory.appendingPathComponent("Fixture").path,
            contents: Data()
        ))

        let expected = try XCTUnwrap(
            appURL.resourceValues(forKeys: [.creationDateKey]).creationDate
        )
        let expectedModification = try XCTUnwrap(
            appURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        )
        let discovered = AppScanner(roots: [root]).discoverApplications()
        let fixture = try XCTUnwrap(discovered.first {
            $0.item.bundleIdentifier == "test.fixture"
        })

        XCTAssertEqual(fixture.item.creationDate, expected)
        XCTAssertEqual(fixture.item.modificationDate, expectedModification)
    }
}
