import Carbon.HIToolbox
import XCTest
@testable import Lunchpad

@MainActor
final class HotKeyControllerTests: XCTestCase {
    func testAvailableCandidateReplacesActiveRegistration() throws {
        let registrar = FakeHotKeyRegistrar()
        let controller = HotKeyController(registrar: registrar, environment: [:]) {}
        controller.start(storedPreference: .configured(.defaultConfiguration))
        let oldToken = try XCTUnwrap(registrar.tokens.first)
        let candidate = HotKeyConfiguration(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(controlKey | optionKey)
        )

        XCTAssertNoThrow(try controller.apply(.configured(candidate)).get())
        XCTAssertEqual(controller.activeConfiguration, candidate)
        XCTAssertEqual(registrar.configurations.count, 2)
        XCTAssertNil(oldToken.value)
    }

    func testConflictPreservesActiveRegistration() throws {
        let registrar = FakeHotKeyRegistrar()
        let controller = HotKeyController(registrar: registrar, environment: [:]) {}
        controller.start(storedPreference: .configured(.defaultConfiguration))
        let oldToken = try XCTUnwrap(registrar.tokens.first)
        registrar.nextError = NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(eventHotKeyExistsErr)
        )
        let candidate = HotKeyConfiguration(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(controlKey | optionKey)
        )

        XCTAssertThrowsError(try controller.apply(.configured(candidate)).get()) { error in
            XCTAssertEqual(error as? HotKeyUpdateError, .conflict)
        }
        XCTAssertEqual(controller.activeConfiguration, .defaultConfiguration)
        XCTAssertNotNil(oldToken.value)
    }

    func testApplyingActiveShortcutIsNoOp() {
        let registrar = FakeHotKeyRegistrar()
        let controller = HotKeyController(registrar: registrar, environment: [:]) {}
        controller.start(storedPreference: .configured(.defaultConfiguration))

        XCTAssertNoThrow(try controller.apply(.configured(.defaultConfiguration)).get())
        XCTAssertEqual(registrar.configurations.count, 1)
    }

    func testClearingReleasesRegistration() throws {
        let registrar = FakeHotKeyRegistrar()
        let controller = HotKeyController(registrar: registrar, environment: [:]) {}
        controller.start(storedPreference: .configured(.defaultConfiguration))
        let token = try XCTUnwrap(registrar.tokens.first)

        XCTAssertNoThrow(try controller.apply(.disabled).get())
        XCTAssertNil(controller.activeConfiguration)
        XCTAssertNil(token.value)
    }

    func testDevelopmentOverridePreventsEditing() {
        let registrar = FakeHotKeyRegistrar()
        let controller = HotKeyController(
            registrar: registrar,
            environment: ["LUNCHPAD_HOTKEY": "control-option-l"]
        ) {}
        controller.start(storedPreference: .configured(.defaultConfiguration))

        XCTAssertTrue(controller.isExternallyManaged)
        XCTAssertThrowsError(try controller.apply(.disabled).get()) { error in
            XCTAssertEqual(error as? HotKeyUpdateError, .managedByEnvironment)
        }
        XCTAssertEqual(controller.activeConfiguration?.displayName, "⌃⌥L")
    }

    func testStartupRegistrationFailureIsExposed() {
        let registrar = FakeHotKeyRegistrar()
        registrar.nextError = NSError(domain: NSOSStatusErrorDomain, code: -1)
        let controller = HotKeyController(registrar: registrar, environment: [:]) {}

        controller.start(storedPreference: .configured(.defaultConfiguration))

        XCTAssertNil(controller.activeConfiguration)
        XCTAssertEqual(controller.lastError, .unavailable)
    }

    func testShortcutValidationAcceptsModifiedKeysAndFunctionKeys() {
        XCTAssertNotNil(ShortcutRecorderView.configuration(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: [.command, .shift]
        ))
        XCTAssertNotNil(ShortcutRecorderView.configuration(
            keyCode: UInt16(kVK_F8),
            modifierFlags: []
        ))
    }

    func testShortcutValidationRejectsTypingAndShiftOnlyKeys() {
        XCTAssertNil(ShortcutRecorderView.configuration(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: []
        ))
        XCTAssertNil(ShortcutRecorderView.configuration(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: [.shift]
        ))
    }

    func testShortcutDisplayUsesNormalizedMacGlyphs() {
        let shortcut = HotKeyConfiguration(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )

        XCTAssertEqual(shortcut.displayName, "⌃⌥⇧⌘L")
    }
}

@MainActor
private final class FakeHotKeyRegistrar: GlobalHotKeyRegistering {
    var configurations: [HotKeyConfiguration] = []
    var tokens: [WeakHotKeyToken] = []
    var nextError: Error?

    func register(
        configuration: HotKeyConfiguration,
        action: @escaping () -> Void
    ) throws -> any GlobalHotKeyRegistration {
        configurations.append(configuration)
        if let nextError {
            self.nextError = nil
            throw nextError
        }
        let token = FakeHotKeyToken()
        tokens.append(WeakHotKeyToken(token))
        return token
    }
}

private final class FakeHotKeyToken: GlobalHotKeyRegistration {}

private final class WeakHotKeyToken {
    weak var value: FakeHotKeyToken?

    init(_ value: FakeHotKeyToken) {
        self.value = value
    }
}
