import Carbon.HIToolbox
import XCTest
@testable import Lunchpad

@MainActor
final class PreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "LunchpadTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testDefaults() {
        let preferences = LunchpadPreferences(defaults: defaults)

        XCTAssertEqual(preferences.interfaceLanguage, .system)
        XCTAssertEqual(preferences.applicationSortOrder, .name)
        XCTAssertEqual(preferences.hotKey, .configured(.defaultConfiguration))
        XCTAssertTrue(preferences.gestureEnabled)
        XCTAssertEqual(preferences.gestureFingerCount, .four)
    }

    func testLegacyShortcutMigratesAndPersists() {
        defaults.set("control-option-l", forKey: "globalHotKey")
        let preferences = LunchpadPreferences(defaults: defaults)

        XCTAssertEqual(
            preferences.hotKey,
            .configured(HotKeyConfiguration(
                keyCode: UInt32(kVK_ANSI_L),
                modifiers: UInt32(controlKey | optionKey)
            ))
        )
        XCTAssertNotNil(defaults.data(forKey: "globalHotKey"))
    }

    func testInvalidValuesFallBackIndependently() {
        defaults.set("unknown", forKey: "interfaceLanguage")
        defaults.set("unknown", forKey: "applicationSortOrder")
        defaults.set(Data("invalid".utf8), forKey: "globalHotKey")
        defaults.set(false, forKey: "fourFingerPinchEnabled")
        defaults.set(7, forKey: "gestureFingerCount")
        let preferences = LunchpadPreferences(defaults: defaults)

        XCTAssertEqual(preferences.interfaceLanguage, .system)
        XCTAssertEqual(preferences.applicationSortOrder, .name)
        XCTAssertEqual(preferences.hotKey, .configured(.defaultConfiguration))
        XCTAssertFalse(preferences.gestureEnabled)
        XCTAssertEqual(preferences.gestureFingerCount, .four)
    }

    func testGestureFingerCountPersistsAndNotifies() {
        let preferences = LunchpadPreferences(defaults: defaults)
        var changes: [LunchpadPreferenceChange] = []
        preferences.onChange = { changes.append($0) }

        preferences.gestureFingerCount = .three

        XCTAssertEqual(preferences.gestureFingerCount, .three)
        XCTAssertEqual(defaults.integer(forKey: "gestureFingerCount"), 3)
        XCTAssertEqual(changes, [.gestureFingerCount])
    }

    func testLegacyFourFingerEnabledKeyStillControlsGestureIntent() {
        defaults.set(false, forKey: "fourFingerPinchEnabled")

        let preferences = LunchpadPreferences(defaults: defaults)

        XCTAssertFalse(preferences.gestureEnabled)
        XCTAssertEqual(preferences.gestureFingerCount, .four)
    }

    func testStoredTimeOrderingValuesRemainDistinct() {
        defaults.set("modificationDate", forKey: "applicationSortOrder")
        let preferences = LunchpadPreferences(defaults: defaults)

        XCTAssertEqual(preferences.applicationSortOrder, .modificationDate)
        XCTAssertEqual(defaults.string(forKey: "applicationSortOrder"), "modificationDate")

        defaults.set("creationDate", forKey: "applicationSortOrder")
        XCTAssertEqual(preferences.applicationSortOrder, .creationDate)
        XCTAssertEqual(defaults.string(forKey: "applicationSortOrder"), "creationDate")
    }

    func testManualOrderingPersists() {
        let preferences = LunchpadPreferences(defaults: defaults)

        preferences.applicationSortOrder = .manual

        XCTAssertEqual(preferences.applicationSortOrder, .manual)
        XCTAssertEqual(defaults.string(forKey: "applicationSortOrder"), "manual")
    }

    func testLanguageResolution() {
        XCTAssertEqual(
            InterfaceLanguage.system.resolved(preferredLanguages: ["zh-Hant-TW", "en"]),
            .simplifiedChinese
        )
        XCTAssertEqual(
            InterfaceLanguage.system.resolved(preferredLanguages: ["fr", "en"]),
            .english
        )
        XCTAssertEqual(
            InterfaceLanguage.system.resolved(preferredLanguages: ["en", "zh-Hans"]),
            .english
        )
        XCTAssertEqual(
            InterfaceLanguage.english.resolved(preferredLanguages: ["zh-Hans"]),
            .english
        )
    }

    func testLocalizedResourcesResolveBothLanguages() {
        let english = AppLocalizer(language: .english)
        let chinese = AppLocalizer(language: .simplifiedChinese)

        XCTAssertEqual(english.string("settings.title"), "Settings")
        XCTAssertEqual(english.string("settings.language.simplified-chinese"), "Chinese")
        XCTAssertEqual(english.string("settings.application-order.manual"), "Manual")
        XCTAssertEqual(english.string("settings.application-order.creation-date"), "Creation Time")
        XCTAssertEqual(
            english.string("settings.application-order.modification-date"),
            "Modification Time"
        )
        XCTAssertEqual(chinese.string("settings.title"), "设置")
        XCTAssertEqual(chinese.string("settings.language.simplified-chinese"), "中文")
        XCTAssertEqual(chinese.string("settings.application-order.manual"), "手动")
        XCTAssertEqual(chinese.string("settings.application-order.creation-date"), "创建时间")
        XCTAssertEqual(
            chinese.string("settings.application-order.modification-date"),
            "修改时间"
        )
        XCTAssertEqual(english.string("settings.gesture-finger-count.three"), "Three Fingers")
        XCTAssertEqual(chinese.string("settings.gesture-finger-count.three"), "三指")
        XCTAssertEqual(chinese.string("missing.key"), "missing.key")
    }

    func testPackagedAppUsesStandardDefaultsForItsOwnDomain() {
        XCTAssertTrue(
            LunchpadDefaults.make(domain: "com.example.App", bundleIdentifier: "com.example.App")
                === UserDefaults.standard
        )
        XCTAssertFalse(
            LunchpadDefaults.make(domain: "com.example.App", bundleIdentifier: nil)
                === UserDefaults.standard
        )
    }
}
