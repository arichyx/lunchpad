## Why

Lunchpad can be opened with a reserved four-finger inward pinch, but once the launcher is on
screen the only ways to put it away are Escape, clicking empty space repeatedly, the global hot
key, or activating another app. There is no gesture that closes the launcher, so the gesture that
opened it has no symmetric counterpart. Classic Launchpad was dismissed with the inverse spread
gesture, and users coming from that model expect the same here.

## What Changes

- Add four-finger outward-spread (expand / unpinch) recognition to `MultitouchKit`, mirroring the
  existing inward-pinch recognizer but tracking the EXPANSION of mean pairwise distance among four
  tracked contacts instead of its contraction.
- Recognize the spread only while the launcher is visible. The direction plus the launcher's
  visibility disambiguates the gesture: inward pinch opens (launcher hidden), outward spread
  dismisses (launcher visible). A spread performed while the launcher is hidden is ignored by
  Lunchpad and left to macOS.
- Route the recognized spread through the existing dismissal path used by Escape, the global hot
  key, and external-app activation, so the launcher closes with the same fixed-duration close
  animation and rearms afterward.
- Gate the new direction on the existing Four-Finger Pinch preference: it shares the same
  `AppleMultitouchDevice` data stream, so it is available only when Four-Finger Pinch is enabled
  and never keeps the stream open on its own.
- Keep completion separate from threshold detection, consistent with the open path, so the
  system's interactive outward gesture cannot alter Lunchpad's close animation.
- Add focused tests for the new spread-recognition branch of the gesture state machine and the
  visibility/direction guard.

No BREAKING changes. Existing inward-pinch activation, Show Desktop restoration, and all other
dismissal methods are unchanged.

## Capabilities

### New Capabilities

<!-- None. The change extends existing gesture and lifecycle behavior. -->

### Modified Capabilities

- `multitouch-gesture`: Add recognition of a four-finger outward spread that dismisses the
  launcher when it is visible, including the expansion threshold, the move-together (non-spread)
  rejection, the stationary-too-long reset, and the completion/release semantics that mirror the
  inward pinch. Document how the spread direction relates to the existing inward pinch and to
  macOS's own outward-gesture behavior.
- `activation-and-lifecycle`: Add the recognized four-finger spread as a dismissal trigger while
  the launcher is visible, alongside Escape, empty-space clicks, the global hot key, and
  external-app activation, and state that the resident process and its monitors keep running
  afterward.

## Impact

- **`Sources/MultitouchKit/`**: extend the four-finger gesture state machine to track both
  contraction and expansion of mean pairwise distance, add a visible-only spread outcome, and
  keep raw-driver validation (report type, lengths, contact counts) unchanged.
- **Activation wiring**: plumb a dismiss outcome from the recognizer to the launcher's dismissal
  path, guarded by the launcher's current visibility state; ensure callbacks dispatch to the main
  actor as today.
- **Settings/preferences**: no new control; the spread direction inherits the existing Four-Finger
  Pinch enable/disable and the shared driver stream lifecycle.
- **`Tests/`**: new unit tests for the spread-recognition branch and the visibility guard, in the
  style of the existing gesture state machine tests.
- **Documentation**: note the new dismissal gesture in the user-facing README/workflow sections and
  any gesture reference, since it changes a documented user workflow.
- **Hardware verification**: confirm on the current machine that the outward spread is detected
  through the same report ABI and coexists with macOS's outward-gesture behavior while the
  launcher overlay is visible; distinguish verified behavior from assumed behavior per the change
  discipline.
