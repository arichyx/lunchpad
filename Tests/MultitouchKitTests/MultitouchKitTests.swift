import XCTest
@testable import MultitouchKit

final class MultitouchKitTests: XCTestCase {
    func testParsesCapturedTahoePrecisePathPacket() throws {
        // A one-contact 0x75 report captured from the local AppleMultitouchDevice.
        let packet: [UInt8] = [
            0x75, 0x7b, 0x20, 0x04, 0xcb, 0xaa, 0xa1, 0x0c,
            0x00, 0x02, 0x07, 0x97, 0x03, 0x00, 0x06, 0x00,
            0x1e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
            0x00, 0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x5e, 0x01, 0x30, 0x11, 0x01, 0x00,
            0x05, 0x01, 0x00, 0x00, 0x87, 0xf6, 0xac, 0x00,
            0x00, 0x00, 0x00, 0x00, 0xff, 0x05, 0xd9, 0x01,
            0x65, 0x65, 0x20, 0x00, 0x20, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ]
        let parser = MultitouchPacketParser(sensorWidth: 15_600, sensorHeight: 9_600)

        let frame = try XCTUnwrap(parser.parse(packet))
        let contact = try XCTUnwrap(frame.activeContacts.first)

        XCTAssertEqual(frame.activeContacts.count, 1)
        XCTAssertEqual(contact.identifier, 5)
        XCTAssertEqual(contact.state, 1)
        XCTAssertEqual(contact.x, -2_425.0 / 15_600.0 + 0.5, accuracy: 0.000_001)
        XCTAssertEqual(contact.y, 172.0 / 9_600.0 + 0.5, accuracy: 0.000_001)
    }

    func testRejectsUnsupportedReportType() {
        let parser = MultitouchPacketParser(sensorWidth: 15_600, sensorHeight: 9_600)
        XCTAssertNil(parser.parse([UInt8](repeating: 0, count: 38)))
    }

    func testActiveContactAtSensorEdgeIsNotDiscarded() {
        let contact = MultitouchContact(identifier: 1, state: 2, x: 0, y: 0.5)
        XCTAssertTrue(contact.isActive)
    }

    func testFourFingerContractionTriggersOnceAndRearmsAfterRelease() {
        var recognizer = PinchRecognizer(fingerCount: 4)
        let spread = frame(scale: 1.0)
        let almostContracted = frame(scale: 0.85)
        let contracted = frame(scale: 0.80)

        XCTAssertFalse(recognizer.process(spread, at: 10.0))
        XCTAssertFalse(recognizer.process(almostContracted, at: 10.1))
        XCTAssertTrue(recognizer.process(contracted, at: 10.2))
        XCTAssertFalse(recognizer.process(contracted, at: 10.3))

        XCTAssertFalse(recognizer.process(MultitouchFrame(contacts: []), at: 10.4))
        XCTAssertFalse(recognizer.process(spread, at: 10.5))
        XCTAssertTrue(recognizer.process(contracted, at: 10.7))
    }

    func testTransientFifthContactDoesNotResetFourFingerGesture() {
        var recognizer = PinchRecognizer(fingerCount: 4)
        let extra = MultitouchContact(identifier: 9, state: 2, x: 0.5, y: 0.5)
        let spread = MultitouchFrame(contacts: frame(scale: 1.0).contacts + [extra])
        let contracted = MultitouchFrame(contacts: frame(scale: 0.8).contacts + [extra])

        XCTAssertFalse(recognizer.process(spread, at: 20.0))
        XCTAssertTrue(recognizer.process(contracted, at: 20.2))
    }

    func testFourFingerExpansionTriggersOnceAndRearmsAfterRelease() {
        var recognizer = ExpandRecognizer(fingerCount: 4)
        let close = frame(scale: 0.5)
        let almostExpanded = frame(scale: 0.6)
        let expanded = frame(scale: 0.8)

        XCTAssertFalse(recognizer.process(close, at: 10.0))
        XCTAssertFalse(recognizer.process(almostExpanded, at: 10.1))
        XCTAssertTrue(recognizer.process(expanded, at: 10.2))
        XCTAssertFalse(recognizer.process(expanded, at: 10.3))

        XCTAssertFalse(recognizer.process(MultitouchFrame(contacts: []), at: 10.4))
        XCTAssertFalse(recognizer.process(close, at: 10.5))
        XCTAssertTrue(recognizer.process(expanded, at: 10.7))
    }

    func testTransientFifthContactDoesNotResetFourFingerExpand() {
        var recognizer = ExpandRecognizer(fingerCount: 4)
        let extra = MultitouchContact(identifier: 9, state: 2, x: 0.5, y: 0.5)
        let close = MultitouchFrame(contacts: frame(scale: 0.5).contacts + [extra])
        let expanded = MultitouchFrame(contacts: frame(scale: 0.8).contacts + [extra])

        XCTAssertFalse(recognizer.process(close, at: 20.0))
        XCTAssertTrue(recognizer.process(expanded, at: 20.2))
    }

    func testFourFingerExpandDoesNotFireWhenContactsMoveTogether() {
        var recognizer = ExpandRecognizer(fingerCount: 4)
        let together = frame(scale: 0.5)

        XCTAssertFalse(recognizer.process(together, at: 30.0))
        // Preserved pairwise distances (a swipe, not a spread) never cross the threshold.
        XCTAssertFalse(recognizer.process(together, at: 30.2))
    }

    func testExpandResetsBaselineAfterStationaryWindow() {
        var recognizer = ExpandRecognizer(fingerCount: 4)
        let close = frame(scale: 0.5)
        let expanded = frame(scale: 0.8)

        XCTAssertFalse(recognizer.process(close, at: 40.0))
        // Beyond the three-second window the baseline resets, so the earlier close position
        // no longer applies and a delayed expansion does not fire on its own.
        XCTAssertFalse(recognizer.process(expanded, at: 43.2))
    }

    func testPinchCompletionWaitsUntilFingersAreLifted() {
        var gate = PinchCompletionGate()
        let fourContacts = frame(scale: 0.8)
        let threeContacts = MultitouchFrame(contacts: Array(fourContacts.contacts.prefix(3)))
        let oneContact = MultitouchFrame(contacts: Array(fourContacts.contacts.prefix(1)))

        XCTAssertNil(
            gate.process(
                fourContacts,
                pinchDetected: true,
                expandDetected: false,
                evaluateActivation: { true }
            )
        )
        XCTAssertNil(
            gate.process(
                threeContacts,
                pinchDetected: false,
                expandDetected: false,
                evaluateActivation: { XCTFail("Gesture state was sampled twice"); return true }
            )
        )
        XCTAssertEqual(
            gate.process(
                oneContact,
                pinchDetected: false,
                expandDetected: false,
                evaluateActivation: { XCTFail("Gesture state was sampled twice"); return true }
            ),
            .activate
        )
        XCTAssertNil(
            gate.process(
                MultitouchFrame(contacts: []),
                pinchDetected: false,
                expandDetected: false,
                evaluateActivation: { XCTFail("Release must not start a gesture"); return true }
            )
        )
    }

    func testShowDesktopStateSuppressesOnlyTheCurrentPinch() {
        var gate = PinchCompletionGate()
        let activeFrame = frame(scale: 1.0)
        let firstContactFrame = MultitouchFrame(contacts: Array(activeFrame.contacts.prefix(1)))
        let releasedFrame = MultitouchFrame(contacts: [])

        XCTAssertNil(
            gate.process(
                firstContactFrame,
                pinchDetected: false,
                expandDetected: false,
                evaluateActivation: { false }
            )
        )
        XCTAssertNil(
            gate.process(
                activeFrame,
                pinchDetected: true,
                expandDetected: false,
                evaluateActivation: { XCTFail("Gesture state was sampled after first contact"); return true }
            )
        )
        XCTAssertEqual(
            gate.process(
                releasedFrame,
                pinchDetected: false,
                expandDetected: false,
                evaluateActivation: { XCTFail("Release must not resample state"); return true }
            ),
            .suppress
        )

        XCTAssertNil(
            gate.process(
                activeFrame,
                pinchDetected: true,
                expandDetected: false,
                evaluateActivation: { true }
            )
        )
        XCTAssertEqual(
            gate.process(
                releasedFrame,
                pinchDetected: false,
                expandDetected: false,
                evaluateActivation: { XCTFail("Release must not resample state"); return true }
            ),
            .activate
        )
    }

    func testExpandCompletionWaitsUntilFingersAreLifted() {
        var gate = PinchCompletionGate()
        let fourContacts = frame(scale: 0.8)
        let threeContacts = MultitouchFrame(contacts: Array(fourContacts.contacts.prefix(3)))
        let oneContact = MultitouchFrame(contacts: Array(fourContacts.contacts.prefix(1)))

        XCTAssertNil(
            gate.process(
                fourContacts,
                pinchDetected: false,
                expandDetected: true,
                evaluateActivation: { true }
            )
        )
        XCTAssertNil(
            gate.process(
                threeContacts,
                pinchDetected: false,
                expandDetected: false,
                evaluateActivation: { XCTFail("Gesture state was sampled twice"); return true }
            )
        )
        XCTAssertEqual(
            gate.process(
                oneContact,
                pinchDetected: false,
                expandDetected: false,
                evaluateActivation: { XCTFail("Gesture state was sampled twice"); return true }
            ),
            .dismiss
        )
        XCTAssertNil(
            gate.process(
                MultitouchFrame(contacts: []),
                pinchDetected: false,
                expandDetected: false,
                evaluateActivation: { XCTFail("Release must not start a gesture"); return true }
            )
        )
    }

    func testExpandDismissalIgnoresShowDesktopState() {
        var gate = PinchCompletionGate()
        let fourContacts = frame(scale: 0.8)
        let oneContact = MultitouchFrame(contacts: Array(fourContacts.contacts.prefix(1)))

        // Show Desktop suppression governs activation only; a recognized spread still dismisses.
        XCTAssertNil(
            gate.process(
                fourContacts,
                pinchDetected: false,
                expandDetected: true,
                evaluateActivation: { false }
            )
        )
        XCTAssertEqual(
            gate.process(
                oneContact,
                pinchDetected: false,
                expandDetected: false,
                evaluateActivation: { XCTFail("Release must not resample state"); return true }
            ),
            .dismiss
        )
    }

    func testFirstRecognizedDirectionWinsPerContactSequence() {
        var gate = PinchCompletionGate()
        let fourContacts = frame(scale: 0.8)
        let oneContact = MultitouchFrame(contacts: Array(fourContacts.contacts.prefix(1)))

        // The pinch is recognized first; an expand reported later in the same sequence must not
        // also produce a dismissal.
        XCTAssertNil(
            gate.process(
                fourContacts,
                pinchDetected: true,
                expandDetected: false,
                evaluateActivation: { true }
            )
        )
        XCTAssertEqual(
            gate.process(
                oneContact,
                pinchDetected: false,
                expandDetected: true,
                evaluateActivation: { XCTFail("Release must not resample state"); return true }
            ),
            .activate
        )
    }

    private func frame(scale: Double) -> MultitouchFrame {
        let center = 0.5
        let points = [
            (0.2, 0.2),
            (0.8, 0.2),
            (0.2, 0.8),
            (0.8, 0.8),
        ]
        let contacts = points.enumerated().map { index, point in
            MultitouchContact(
                identifier: UInt8(index + 1),
                state: 2,
                x: center + (point.0 - center) * scale,
                y: center + (point.1 - center) * scale
            )
        }
        return MultitouchFrame(contacts: contacts)
    }
}
