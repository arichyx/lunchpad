import Foundation
import XCTest

/// Every interface string must exist in each shipped language so no language silently falls back
/// to raw keys or English.
final class LocalizationTests: XCTestCase {
    func testShippedLanguagesDefineTheSameKeys() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Lunchpad/Resources", isDirectory: true)
        let english = try keys(in: resources.appendingPathComponent("en.lproj/Localizable.strings"))
        let chinese = try keys(
            in: resources.appendingPathComponent("zh-Hans.lproj/Localizable.strings")
        )

        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(english.subtracting(chinese).sorted(), [])
        XCTAssertEqual(chinese.subtracting(english).sorted(), [])
    }

    private func keys(in url: URL) throws -> Set<String> {
        let data = try Data(contentsOf: url)
        let strings = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
        return Set(strings.keys)
    }
}
