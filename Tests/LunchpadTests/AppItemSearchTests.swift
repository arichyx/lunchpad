import XCTest
@testable import Lunchpad

final class AppItemSearchTests: XCTestCase {
    // MARK: - searchAliases(_:rawBundleDisplayName:rawBundleName:)

    func testSearchAliasesRetainsBothDistinctRawValues() {
        let aliases = AppItem.searchAliases(
            displayName: "计算器",
            rawBundleDisplayName: "Calculator",
            rawBundleName: "Calc"
        )
        XCTAssertEqual(aliases, ["Calculator", "Calc"])
    }

    func testSearchAliasesDropsDisplayNameDuplicateCaseInsensitively() {
        let aliases = AppItem.searchAliases(
            displayName: "Calculator",
            rawBundleDisplayName: "calculator",
            rawBundleName: "Calc"
        )
        XCTAssertEqual(aliases, ["Calc"])
    }

    func testSearchAliasesDropsDuplicateBetweenRawValues() {
        let aliases = AppItem.searchAliases(
            displayName: "计算器",
            rawBundleDisplayName: "Calculator",
            rawBundleName: "calculator"
        )
        XCTAssertEqual(aliases, ["Calculator"])
    }

    func testSearchAliasesIgnoresEmptyRawValues() {
        let aliases = AppItem.searchAliases(
            displayName: "Calculator",
            rawBundleDisplayName: nil,
            rawBundleName: nil
        )
        XCTAssertTrue(aliases.isEmpty)
    }

    func testSearchAliasesPreservesInsertionOrderDisplayNameThenBundleName() {
        let aliases = AppItem.searchAliases(
            displayName: "Displayed",
            rawBundleDisplayName: "Beta",
            rawBundleName: "Alpha"
        )
        XCTAssertEqual(aliases, ["Beta", "Alpha"])
    }

    func testSearchAliasesHandlesEmptyDisplayNameByRetainingBothDistinctRawValues() {
        let aliases = AppItem.searchAliases(
            displayName: "",
            rawBundleDisplayName: "Calculator",
            rawBundleName: "Calc"
        )
        XCTAssertEqual(aliases, ["Calculator", "Calc"])
    }

    // MARK: - matchesSearchQuery(_:)

    private func app(
        name: String,
        aliases: [String] = []
    ) -> AppItem {
        AppItem(
            identifier: "app.\(name.lowercased())",
            bundleIdentifier: "app.\(name.lowercased())",
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            creationDate: nil,
            modificationDate: nil,
            searchAliases: aliases
        )
    }

    func testMatchesQueryAgainstLocalizedDisplayName() {
        let appItem = app(name: "计算器")
        XCTAssertTrue(appItem.matchesSearchQuery("计算"))
        XCTAssertTrue(appItem.matchesSearchQuery("计算器"))
    }

    func testMatchesQueryAgainstBundleNameAlias() {
        let appItem = app(name: "计算器", aliases: ["Calculator"])
        XCTAssertTrue(appItem.matchesSearchQuery("Calculator"))
    }

    func testMatchesQueryCaseInsensitivelyAgainstBundleNameAlias() {
        let appItem = app(name: "计算器", aliases: ["Calculator"])
        XCTAssertTrue(appItem.matchesSearchQuery("calculator"))
        XCTAssertTrue(appItem.matchesSearchQuery("CALC"))
    }

    func testMatchesQueryAsSubstringOfDisplayName() {
        let appItem = app(name: "Calculator", aliases: [])
        XCTAssertTrue(appItem.matchesSearchQuery("alc"))
    }

    func testMatchesQueryAsSubstringOfAlias() {
        let appItem = app(name: "计算器", aliases: ["Calculator"])
        XCTAssertTrue(appItem.matchesSearchQuery("alc"))
    }

    func testDoesNotMatchWhenQueryMatchesNeitherNameNorAlias() {
        let appItem = app(name: "计算器", aliases: ["Calculator"])
        XCTAssertFalse(appItem.matchesSearchQuery("Safari"))
        XCTAssertFalse(appItem.matchesSearchQuery("xyz"))
    }

    func testMatchesAtMostOnceEvenWhenMultipleNamesMatch() {
        // The matcher returns a single Bool; the filter that uses it emits each app at most once.
        // This test verifies the matcher itself returns true (not a count) when multiple names
        // match the same query, satisfying the single-result contract.
        let appItem = app(name: "Calculator", aliases: ["Calculator App", "Calc"])
        XCTAssertTrue(appItem.matchesSearchQuery("Cal"))
    }
}
