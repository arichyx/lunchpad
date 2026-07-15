import XCTest
@testable import Lunchpad

final class ApplicationOrderingPolicyTests: XCTestCase {
    private let locale = Locale(identifier: "en")

    func testNameOrderingPreservesFolderSlotAndSortsMembers() {
        let folder = AppFolder(
            identifier: "folder",
            name: "Folder",
            apps: [app("Zulu"), app("Alpha")],
            isSystem: false
        )
        let items: [LunchpadItem] = [
            .app(app("Zulu")),
            .folder(folder),
            .app(app("Alpha")),
        ]

        let ordered = ApplicationOrderingPolicy.apply(
            to: items,
            order: .name,
            locale: locale,
            otherFolderName: "Other"
        )

        XCTAssertEqual(ordered.map(\.name), ["Alpha", "Folder", "Zulu"])
        guard case .folder(let orderedFolder) = ordered[1] else {
            return XCTFail("Expected the folder to remain in its root slot")
        }
        XCTAssertEqual(orderedFolder.apps.map(\.name), ["Alpha", "Zulu"])
    }

    func testCreationOrderingPlacesUnknownDatesLastAndUsesNameTieBreaker() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let apps = [
            app("Unknown", date: nil),
            app("Beta", date: older),
            app("Zulu", date: newer),
            app("Alpha", date: newer),
        ]

        XCTAssertEqual(
            ApplicationOrderingPolicy.sorted(
                apps,
                order: .creationDate,
                locale: locale
            ).map(\.name),
            ["Alpha", "Zulu", "Beta", "Unknown"]
        )
    }

    func testModificationOrderingIsIndependentFromCreationOrdering() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let apps = [
            app("Created Later", creationDate: newer, modificationDate: older),
            app("Modified Later", creationDate: older, modificationDate: newer),
        ]

        XCTAssertEqual(
            ApplicationOrderingPolicy.sorted(
                apps,
                order: .creationDate,
                locale: locale
            ).map(\.name),
            ["Created Later", "Modified Later"]
        )
        XCTAssertEqual(
            ApplicationOrderingPolicy.sorted(
                apps,
                order: .modificationDate,
                locale: locale
            ).map(\.name),
            ["Modified Later", "Created Later"]
        )
    }

    func testOtherFolderNameUsesInterfaceLocalization() {
        let items: [LunchpadItem] = [.folder(AppFolder(
            identifier: LunchpadLayoutStore.otherFolderIdentifier,
            name: "Other",
            apps: [app("Utility")],
            isSystem: true
        ))]

        let ordered = ApplicationOrderingPolicy.apply(
            to: items,
            order: .name,
            locale: locale,
            otherFolderName: "其他"
        )

        XCTAssertEqual(ordered.map(\.name), ["其他"])
    }

    func testPresentationOrderingDoesNotRewriteStoredPositions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LunchpadOrderingTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LunchpadLayoutStore(
            databaseURL: directory.appendingPathComponent("layout.sqlite3")
        )
        let discovered = [
            DiscoveredApplication(item: app("Alpha", date: .distantPast), shouldDefaultToOther: false),
            DiscoveredApplication(item: app("Zulu", date: .distantFuture), shouldDefaultToOther: false),
        ]
        let canonical = try store.reconcile(discovered)
        let presented = ApplicationOrderingPolicy.apply(
            to: canonical.map { attachDates(to: $0, from: discovered) },
            order: .creationDate,
            locale: locale,
            otherFolderName: "Other"
        )
        let reloaded = try store.reconcile(discovered)

        XCTAssertEqual(canonical.map(\.name), ["Alpha", "Zulu"])
        XCTAssertEqual(presented.map(\.name), ["Zulu", "Alpha"])
        XCTAssertEqual(reloaded.map(\.name), ["Alpha", "Zulu"])
    }

    private func app(
        _ name: String,
        date: Date? = nil,
        creationDate: Date? = nil,
        modificationDate: Date? = nil
    ) -> AppItem {
        AppItem(
            identifier: "app.\(name.lowercased())",
            bundleIdentifier: "app.\(name.lowercased())",
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            creationDate: creationDate ?? date,
            modificationDate: modificationDate
        )
    }

    private func attachDates(
        to item: LunchpadItem,
        from discovered: [DiscoveredApplication]
    ) -> LunchpadItem {
        guard case .app(let stored) = item,
              let source = discovered.first(where: {
                  $0.item.identifier == stored.identifier
              })?.item else {
            return item
        }
        return .app(source)
    }
}
