import AppKit
import XCTest
@testable import Lunchpad

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testSettingsWindowIsReusableAndRelocalizesInPlace() throws {
        _ = NSApplication.shared
        let suiteName = "LunchpadSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = LunchpadPreferences(defaults: defaults)
        let localizer = AppLocalizer(language: .english)
        let hotKeyController = HotKeyController(
            registrar: SettingsFakeHotKeyRegistrar(),
            environment: [:]
        ) {}
        hotKeyController.start(storedPreference: preferences.hotKey)
        let loginItemController = LoginItemController(
            service: SettingsFakeLoginItemService()
        )
        let controller = SettingsWindowController(
            preferences: preferences,
            localizer: localizer,
            hotKeyController: hotKeyController,
            loginItemController: loginItemController,
            gestureErrorProvider: { nil }
        )
        let originalWindow = try XCTUnwrap(controller.window)
        XCTAssertTrue(originalWindow.collectionBehavior.contains(.moveToActiveSpace))

        controller.show()
        XCTAssertTrue(controller.window === originalWindow)
        XCTAssertEqual(originalWindow.title, "Settings")

        localizer.setLanguage(.simplifiedChinese)
        controller.refreshLocalizedContent()
        XCTAssertTrue(controller.window === originalWindow)
        XCTAssertEqual(originalWindow.title, "设置")
        controller.close()
    }
}

@MainActor
private struct SettingsFakeHotKeyRegistrar: GlobalHotKeyRegistering {
    func register(
        configuration: HotKeyConfiguration,
        action: @escaping () -> Void
    ) throws -> any GlobalHotKeyRegistration {
        SettingsFakeHotKeyToken()
    }
}

private final class SettingsFakeHotKeyToken: GlobalHotKeyRegistration {}

@MainActor
private final class SettingsFakeLoginItemService: LoginItemManaging {
    let isAvailable = false
    var isEnabled = false

    func setEnabled(_ enabled: Bool) throws {}
}
