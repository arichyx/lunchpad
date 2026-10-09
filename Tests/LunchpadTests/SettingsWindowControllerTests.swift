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
final class SettingsLoginItemApprovalTests: XCTestCase {
    private func makeController(
        service: ApprovalFakeLoginItemService
    ) throws -> SettingsWindowController {
        _ = NSApplication.shared
        let suiteName = "LunchpadSettingsApprovalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = LunchpadPreferences(defaults: defaults)
        let hotKeyController = HotKeyController(
            registrar: SettingsFakeHotKeyRegistrar(),
            environment: [:]
        ) {}
        hotKeyController.start(storedPreference: .disabled)
        return SettingsWindowController(
            preferences: preferences,
            localizer: AppLocalizer(language: .english),
            hotKeyController: hotKeyController,
            loginItemController: LoginItemController(service: service),
            gestureErrorProvider: { nil }
        )
    }

    func testPendingApprovalExplainsAndOffersSystemSettings() throws {
        let service = ApprovalFakeLoginItemService()
        service.requiresApproval = true
        let controller = try makeController(service: service)

        XCTAssertTrue(controller.isShowingLoginItemApproval)
        XCTAssertEqual(
            controller.feedbackText,
            "Launch at Login needs your approval in System Settings › General › Login Items."
        )
    }

    func testApprovalStateRefreshesWhenSettingsRegainFocus() throws {
        let service = ApprovalFakeLoginItemService()
        service.requiresApproval = true
        let controller = try makeController(service: service)

        service.requiresApproval = false
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))

        XCTAssertFalse(controller.isShowingLoginItemApproval)
        XCTAssertNil(controller.feedbackText)
    }

    func testApprovedLoginItemShowsNoApprovalPrompt() throws {
        let controller = try makeController(service: ApprovalFakeLoginItemService())

        XCTAssertFalse(controller.isShowingLoginItemApproval)
    }

    func testControllerForwardsSystemSettingsRequest() {
        let service = ApprovalFakeLoginItemService()
        LoginItemController(service: service).openSystemSettings()

        XCTAssertEqual(service.openedSystemSettings, 1)
    }
}

@MainActor
private final class ApprovalFakeLoginItemService: LoginItemManaging {
    let isAvailable = true
    var isEnabled = true
    var requiresApproval = false
    var openedSystemSettings = 0

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }

    func openSystemSettings() {
        openedSystemSettings += 1
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
