## 1. MultitouchKit — outward-spread recognition

- [x] 1.1 Add an `ExpandRecognizer` value type in `Sources/MultitouchKit/MultitouchKit.swift` mirroring `PinchRecognizer`: lock the first four contact identifiers, tolerate a transient fifth contact, reset when below four, track the MINIMUM mean pairwise distance as baseline, and fire once when the current distance reaches the expansion threshold within the duration window, with the stationary-too-long baseline reset. The `meanPairwiseDistance(of:)` arithmetic and tracking logic are duplicated rather than refactoring `PinchRecognizer`, so the reserved pinch path stays untouched.
- [x] 1.2 Give `ExpandRecognizer` constructor parameters `fingerCount = 4`, `expansionThreshold = 1.22` (≈ 1 / 0.82), `minimumStartingDistance = 0.06` (the same floor the pinch uses on its maximum-distance baseline, applied here as a floor on the minimum-distance baseline to reject degenerate near-zero values), and `maximumDuration = 3.0 s`. No separate starting-distance ceiling is needed.
- [x] 1.3 Add `case dismiss` to `PinchCompletionAction` (`Sources/MultitouchKit/MultitouchKit.swift`).
- [x] 1.4 Extend `PinchCompletionGate` to accept both a pinch-detected and an expand-detected flag, hold at most one pending action per contact sequence (first direction to threshold wins), and emit `.activate`/`.suppress`/`.dismiss` once `activeContactCount < 2`, then rearm on sequence reset. The activation policy is still sampled once on the first contact (the pinch path needs it before macOS restores windows), but the dismiss outcome never consults it.

## 2. MultitouchKit — monitor pipeline & callback

- [x] 2.1 Add `public var onExpand: (() -> Void)?` to `MultitouchMonitor` alongside `onPinch`.
- [x] 2.2 In `readLoop(_:)`, construct and hold an `ExpandRecognizer` next to the existing `PinchRecognizer`, feed every parsed frame to both, pass both detected flags to the updated `PinchCompletionGate`, and dispatch `onExpand` for `.dismiss` (and continue dispatching `onPinch`/`onPinchSuppressed` for `.activate`/`.suppress`). Raw-report validation is unchanged.

## 3. App layer — wiring the dismissal

- [x] 3.1 Add `var onExpand: (() -> Void)? { get set }` to the `GestureMonitoring` protocol in `Sources/Lunchpad/GestureMonitorController.swift`.
- [x] 3.2 Add a `dismissLunchpad()` helper in `Sources/Lunchpad/AppDelegate.swift`, symmetric to `showLunchpad()`, that guards on `window?.isVisible == true` and then calls `window.close()`; wire `monitor.onExpand` in `configureMultitouchMonitor(_:)` to dispatch it on the main actor (`Task { @MainActor … }`), mirroring the `onPinch` wiring.
- [x] 3.3 Confirm the spread is covered by the existing Four-Finger Pinch preference (shared stream): with `fourFingerPinchEnabled == false`, `GestureMonitorController.setEnabled(false)` stops the monitor so no spread is recognized. No new preference key.

## 4. Tests

- [x] 4.1 In `Tests/MultitouchKitTests/MultitouchKitTests.swift`, add `ExpandRecognizer` tests using the existing `frame(scale:)` helper: fires once on sufficient expansion; does not fire when four contacts move together without expanding; tolerates a transient fifth contact; resets the baseline after the three-second stationary window.
- [x] 4.2 In `Tests/MultitouchKitTests/MultitouchKitTests.swift`, extend the `PinchCompletionGate` tests for the new `.dismiss` outcome: a recognized spread emits `.dismiss` only after the active contact count drops below two; emits exactly one dismissal per sequence and rearms after reset; a sequence does not emit both an activate and a dismiss (first direction wins); a dismissal ignores Show Desktop state.
- [x] 4.3 Extend `FakeGestureMonitor` in `Tests/LunchpadTests/ResidentControlsTests.swift` with `onExpand` so the test target compiles against the updated protocol. Direct `AppDelegate` dismissal coverage follows the project's existing boundary (AppDelegate is not unit-tested; `showLunchpad()` is not either), so the behavior is covered by the gate tests plus the symmetric `dismissLunchpad()` implementation.

## 5. Documentation & validation

- [x] 5.1 Update the user-facing README to list the four-finger outward spread as a dismissal gesture, paired with the inward pinch to open (highlights and "Using Lunchpad" sections).
- [x] 5.2 Run `swift build --package-path <repo>` and `swift test --package-path <repo>`; the existing pinch tests and new tests pass (68 tests, 0 failures) and `git diff --check` is clean.
- [x] 5.3 Verify on the current machine that the spread dismisses through the real driver stream, that disabling Four-Finger Pinch disables it, and that the dismiss coexists with macOS's own outward-gesture behavior and does not corrupt the next open pinch; record what was verified versus assumed per `AGENTS.md`. *(Verified locally by the user on the real trackpad.)*
