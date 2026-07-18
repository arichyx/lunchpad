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

    /// Verifies that the scanner retains a distinct raw bundle name as a search alias when the
    /// localized display name differs, and drops empty or case-insensitive duplicate aliases.
    func testDiscoveryRetainsDistinctBundleNameAsSearchAlias() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LunchpadScannerAliasTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let root = directory.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // Distinct raw names: CFBundleDisplayName is a non-ASCII value unlikely to collide with
        // any filesystem-derived localized name, and CFBundleName is a separate ASCII value.
        let distinctAppURL = root.appendingPathComponent("Distinct.app", isDirectory: true)
        try writeFixtureApp(
            at: distinctAppURL,
            bundleIdentifier: "test.distinct",
            executableName: "Distinct",
            bundleDisplayName: "计算器",
            bundleName: "Calculator"
        )

        // Duplicate raw names: both raw values are identical and should yield a single alias
        // (or none, if either happens to match the resolved display name).
        let duplicateAppURL = root.appendingPathComponent("Duplicate.app", isDirectory: true)
        try writeFixtureApp(
            at: duplicateAppURL,
            bundleIdentifier: "test.duplicate",
            executableName: "Duplicate",
            bundleDisplayName: "SharedName",
            bundleName: "SharedName"
        )

        // Empty raw names: no aliases should be retained.
        let emptyAppURL = root.appendingPathComponent("EmptyRaw.app", isDirectory: true)
        try writeFixtureApp(
            at: emptyAppURL,
            bundleIdentifier: "test.emptyraw",
            executableName: "EmptyRaw",
            bundleDisplayName: "   ",
            bundleName: ""
        )

        let discovered = AppScanner(roots: [root]).discoverApplications()

        let distinct = try XCTUnwrap(discovered.first {
            $0.item.bundleIdentifier == "test.distinct"
        }).item
        // The displayed name is whatever the bundle resolves to (typically "计算器" through the
        // raw CFBundleDisplayName fallback). Whichever raw value it equals, the other must be
        // retained as an alias and the matching one must be dropped.
        let distinctLowercasedName = distinct.name.lowercased()
        if distinctLowercasedName == "计算器" {
            XCTAssertEqual(distinct.searchAliases, ["Calculator"])
        } else if distinctLowercasedName == "calculator" {
            XCTAssertEqual(distinct.searchAliases, ["计算器"])
        } else {
            // Display name came from neither raw value (e.g. the filename). Both raw values
            // must be retained as aliases, in insertion order.
            XCTAssertEqual(distinct.searchAliases, ["计算器", "Calculator"])
        }

        let duplicate = try XCTUnwrap(discovered.first {
            $0.item.bundleIdentifier == "test.duplicate"
        }).item
        // Either zero or one alias: zero if the display name matches the shared raw name,
        // one if the display name came from elsewhere.
        XCTAssertLessThanOrEqual(duplicate.searchAliases.count, 1)
        if let onlyAlias = duplicate.searchAliases.first {
            XCTAssertNotEqual(onlyAlias.lowercased(), duplicate.name.lowercased())
        }

        let empty = try XCTUnwrap(discovered.first {
            $0.item.bundleIdentifier == "test.emptyraw"
        }).item
        XCTAssertTrue(empty.searchAliases.isEmpty, "Empty raw bundle names must not yield aliases")
    }

    /// Verifies that the scanner resolves a localized display name through InfoPlist.loctable,
    /// retains the raw `CFBundleName` as a search alias, and propagates both through SQLite
    /// reconciliation. Unlike `testDiscoveryRetainsDistinctBundleNameAsSearchAlias`, this fixture
    /// does not put the localized name into raw `CFBundleDisplayName`, so the loctable parsing and
    /// the `scanApplications(using:)` alias backfill are genuinely exercised.
    func testLoctableDisplayNameAndSQLiteReconciliationRetainBundleNameAlias() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LunchpadScannerLoctableTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let root = directory.appendingPathComponent("Applications", isDirectory: true)
        let appURL = root.appendingPathComponent("Localized.app", isDirectory: true)
        try writeLocalizedFixtureApp(at: appURL)

        let scanner = AppScanner(roots: [root])

        // First verify through discoverApplications() that the loctable path is exercised:
        // the display name must NOT be "Calculator" (the raw CFBundleName fallback).
        let discovered = scanner.discoverApplications()
        let discoveredApp = try XCTUnwrap(discovered.first {
            $0.item.bundleIdentifier == "test.localized"
        }).item

        XCTAssertNotEqual(
            discoveredApp.name,
            "Calculator",
            "Display name should come from InfoPlist.loctable, not the raw CFBundleName fallback"
        )
        XCTAssertTrue(
            ["LocalizedApp", "计算器"].contains(discoveredApp.name),
            "Display name should be a loctable value; got \(discoveredApp.name)"
        )
        XCTAssertEqual(discoveredApp.searchAliases, ["Calculator"])

        // Now verify through scanApplications(using:) that aliases survive SQLite reconciliation.
        // This is the path ApplicationCatalogSynchronizer uses for the live catalog; the enrich
        // step must copy aliases from discovered items onto items loaded from the database.
        let store = try LunchpadLayoutStore(
            databaseURL: directory.appendingPathComponent("layout.sqlite3")
        )
        let reconciled = try scanner.scanApplications(using: store)
        let reconciledApp = try XCTUnwrap(reconciled.lazy.compactMap { item -> AppItem? in
            guard case .app(let app) = item,
                  app.bundleIdentifier == "test.localized" else {
                return nil
            }
            return app
        }.first)

        XCTAssertEqual(reconciledApp.name, discoveredApp.name)
        XCTAssertEqual(
            reconciledApp.searchAliases,
            ["Calculator"],
            "Aliases must be backfilled from discovered items during SQLite enrichment"
        )
    }

    private func writeFixtureApp(
        at appURL: URL,
        bundleIdentifier: String,
        executableName: String,
        bundleDisplayName: String,
        bundleName: String
    ) throws {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let executableDirectory = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(
            at: executableDirectory,
            withIntermediateDirectories: true
        )

        var info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleExecutable": executableName,
        ]
        if !bundleDisplayName.isEmpty {
            info["CFBundleDisplayName"] = bundleDisplayName
        }
        if !bundleName.isEmpty {
            info["CFBundleName"] = bundleName
        }
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        XCTAssertTrue(FileManager.default.createFile(
            atPath: executableDirectory.appendingPathComponent(executableName).path,
            contents: Data()
        ))
    }

    /// Writes a fixture whose display name is resolved only through `InfoPlist.loctable`.
    /// Raw `CFBundleName` is "Calculator" and raw `CFBundleDisplayName` is intentionally absent so
    /// a broken loctable path would fall through to "Calculator" and produce an empty alias list.
    private func writeLocalizedFixtureApp(at appURL: URL) throws {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let executableDirectory = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(
            at: executableDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: resourcesURL,
            withIntermediateDirectories: true
        )

        // CFBundleLocalizations advertises the available localizations so
        // Bundle.preferredLocalizations can match against the user's preferred languages.
        let info: [String: Any] = [
            "CFBundleIdentifier": "test.localized",
            "CFBundleExecutable": "Localized",
            "CFBundleName": "Calculator",
            "CFBundleDevelopmentRegion": "en",
            "CFBundleLocalizations": ["en", "zh_CN", "zh-Hans"],
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        // The loctable provides the only source of the displayed name. Both localizations differ
        // from the raw CFBundleName so either one yields the same alias list.
        let loctable: [String: Any] = [
            "en": ["CFBundleDisplayName": "LocalizedApp"] as [String: Any],
            "zh_CN": ["CFBundleDisplayName": "计算器"] as [String: Any],
            "zh-Hans": ["CFBundleDisplayName": "计算器"] as [String: Any],
        ]
        let loctableData = try PropertyListSerialization.data(
            fromPropertyList: loctable,
            format: .xml,
            options: 0
        )
        try loctableData.write(to: resourcesURL.appendingPathComponent("InfoPlist.loctable"))

        XCTAssertTrue(FileManager.default.createFile(
            atPath: executableDirectory.appendingPathComponent("Localized").path,
            contents: Data()
        ))
    }
}
