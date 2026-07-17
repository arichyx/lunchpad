## Context

The reserved four-finger gesture is detected entirely in `MultitouchKit` from the private
`AppleMultitouchDevice` `0x75` report stream, never through `NSEvent`/`CGEventTap`/magnification
(see `AGENTS.md` "Four-finger gesture" and `Docs/IOKitMultitouch.md`). Today only the INWARD
direction is recognized:

- `PinchRecognizer` (`Sources/MultitouchKit/MultitouchKit.swift:100-199`) tracks the maximum mean
  pairwise distance among four locked contacts and fires once on contraction to ≤ 82 % of that
  maximum (`contractionThreshold = 0.82`, `minimumStartingDistance = 0.06`,
  `maximumDuration = 3.0 s`), with fifth-contact tolerance and a stationary-too-long baseline reset.
- `PinchCompletionGate` (`:212-242`) separates threshold from completion: it samples the Show
  Desktop activation policy on the first contact of a sequence and emits `.activate`/`.suppress`
  only once the active contact count drops below two.
- `MultitouchMonitor` (`:263-482`) runs the read loop on a `.userInteractive` background queue and
  exposes `onFrame`, `onPinch`, `onPinchSuppressed`, `shouldActivatePinch`, `onError`.
- `AppDelegate.configureMultitouchMonitor(_:)` (`Sources/Lunchpad/AppDelegate.swift:262-301`)
  wires `shouldActivatePinch` to the Show Desktop detector and `onPinch` to `showLunchpad()`
  (`:303-308`), which guards on `!window.isVisible`.
- The single animated dismissal path is `LunchpadWindow.close()` (`Sources/Lunchpad/LunchpadWindow.swift:278-310`),
  already used by Escape, empty-space click, app launch, external-app activation, and the hot-key
  toggle. It guards on `isVisible && !isAnimatingClose` and runs the fixed-duration fade-out.

This change adds the symmetric OUTWARD direction so a spread performed while the launcher is
visible dismisses it. The recognizer runs on the same off-main background queue, so any AppKit work
must be dispatched to the main actor (existing invariant).

## Goals / Non-Goals

**Goals:**
- Recognize a four-finger outward spread through the existing driver stream, symmetric to the
  inward pinch, with the same bounded parsing, four-contact lock, fifth-contact tolerance, and
  stationary-reset discipline.
- Route a completed spread to the existing `LunchpadWindow.close()` dismissal path, only when the
  launcher is visible.
- Keep completion separated from threshold detection (defer to contact release), consistent with
  the reserved-gesture invariant.
- Leave the reserved inward-pinch path, Show Desktop restoration, and all other dismissal methods
  byte-for-byte unchanged in behavior.

**Non-Goals:**
- No `NSEvent`/`CGEventTap`/magnification path. No new IOKit report types.
- No new preference; the spread inherits the existing Four-Finger Pinch enable/disable and shared
  stream lifecycle.
- No change to inward-pinch-while-visible behavior beyond the visibility guard already implied by
  `showLunchpad()`.
- No custom close animation; reuse the fixed-duration fade-out.

## Decisions

### Decision 1: Add a sibling `ExpandRecognizer` rather than generalize `PinchRecognizer`

A separate `ExpandRecognizer` struct mirrors `PinchRecognizer` but tracks the MINIMUM mean pairwise
distance as its baseline and fires on expansion past the threshold. It duplicates the
`meanPairwiseDistance(of:)` arithmetic and the four-contact identifier lock, fifth-contact
tolerance, and stationary-reset logic rather than refactoring `PinchRecognizer`, so the reserved
pinch path is untouched.

**Rationale:** `PinchRecognizer` is a delicate reserved path with passing tests and a documented
hardware-verified contract. Generalizing it to carry two baselines and a typed outcome touches the
hot recognition loop and risks regressing the open gesture. A sibling recognizer is additive and
isolated; the existing pinch tests stay green unchanged.

**Alternatives considered:**
- Generalize `PinchRecognizer` to return `enum { none, activate, dismiss }` with both a `maximumDistance`
  and `minimumDistance` baseline. Rejected: higher regression risk on the reserved path for little
  structural gain.

### Decision 2: Extend the completion gate to carry a `.dismiss` action, still deferred to release

Add `case dismiss` to `PinchCompletionAction`. Extend `PinchCompletionGate` so the pending outcome
is whichever direction's recognizer fires first within a contact sequence; it still emits only after
`activeContactCount < 2`. At most one action is pending per sequence (first direction to threshold
wins); the gate rearms when the sequence resets. Show Desktop suppression stays specific to
activation: the activation policy is still sampled once on the first contact of a sequence (the
pinch path needs it before macOS restores displaced windows), but the dismiss outcome never
consults it.

**Rationale:** This preserves the project's explicit invariant that threshold detection stays
separate from completion so the system's interactive gesture cannot alter Lunchpad's fixed-duration
animation. It also gives a clean "exactly one dismissal, rearm after reset" guarantee symmetric to
the open path's wording.

**Alternatives considered:**
- Dismiss immediately on threshold crossing. Snappier, but reintroduces the mid-gesture conflict
  the invariant was written to prevent (the system animates during the outward gesture) and loses
  the symmetric rearm guarantee. Rejected; revisit only if hardware testing shows defer-to-release
  feels wrong.

### Decision 3: Gate on visibility in `AppDelegate`, keep `MultitouchKit` policy-free

Add an `onExpand: (() -> Void)?` callback to `MultitouchMonitor` and the `GestureMonitoring`
protocol, alongside `onPinch`. `MultitouchKit` only reports that a spread completed. AppDelegate
wires `onExpand` to a `dismissLunchpad()` helper symmetric to `showLunchpad()`, which guards on
`window.isVisible` and then calls `window.close()`. This mirrors how `onPinch` → `showLunchpad()`
(whose `!window.isVisible` guard already makes pinch-while-visible a no-op).

**Rationale:** Keeps the recognition kit free of app/window state and reuses the one dismissal
path. A spread while hidden fires `onExpand`, AppDelegate ignores it, and macOS's own outward
gesture is undisturbed.

**Alternatives considered:**
- Pass a visibility callback into the recognizer/gate so detection only happens when visible.
  Rejected: couples the kit to app state and would suppress detection logging/debugging while
  hidden for no behavioral gain (the AppDelegate guard already makes it safe).

### Decision 4: Symmetric, tunable thresholds; verify on hardware

Default `expansionThreshold = 1.22` (expand to ≥ 122 % of the observed minimum, approximately the
inverse of the 0.82 contraction threshold), and reuse the pinch's `minimumStartingDistance = 0.06`
as a floor on the minimum-distance baseline — mirroring the pinch's floor on its maximum-distance
baseline, which rejects degenerate near-zero baselines and tiny jitter. Also reuse `fingerCount = 4`
and `maximumDuration = 3.0 s`. No separate starting-distance ceiling is needed: the expansion ratio
alone distinguishes a real spread from a swipe that preserves pairwise distances. These are
constructor parameters (like the pinch's) so they can be tuned without touching the recognizer body
and exercised by tests.

**Rationale:** Symmetry with the verified pinch constants is the safest default; the exact numbers
are a hardware-tuning detail. Per `AGENTS.md`, distinguish what is verified on the current machine
from what is assumed.

### Decision 5: A spread dismisses the launcher entirely (it does not do folder-first)

`dismissLunchpad()` calls `LunchpadWindow.close()` directly, exiting the launcher even when a
logical folder page is open. This is the symmetric inverse of the open gesture (which presents the
root page), and matches the "get me out" intent of a spread.

**Alternatives considered:**
- Escape-style folder-first (leave the open folder, then close on a second spread). Rejected as
  surprising for a single dismiss gesture; Escape already owns that semantics.

## Risks / Trade-offs

- **Coexistence with macOS's own outward gesture while the overlay is visible** → The system may
  animate Show Desktop underneath as the user spreads. Mitigation: only honor dismiss when visible;
  defer to release so Lunchpad's fade never runs mid-system-animation; verify on hardware that the
  revealed desktop state is acceptable, and that a subsequent inward pinch still samples live
  WindowServer state correctly (the spec forbids inferring state from a prior outward gesture).
- **False dismissal from an accidental spread** → Mitigation: symmetric threshold, starting-distance
  floor, three-second window, four-contact identifier lock, fifth-contact tolerance, and
  visibility-only honoring. Covered by new state-machine tests.
- **Regression of the reserved pinch path** → Mitigation: additive sibling recognizer; completion
  gate extended, not rewritten; `PinchRecognizer` contraction logic untouched; existing
  `MultitouchKitTests` remain green.
- **Double outcome within one sequence** → Mitigation: the completion gate holds at most one pending
  action per sequence and rearms on reset.
- **Defer-to-release may feel less immediate than classic Launchpad's spread** → Mitigation:
  documented as Decision 2; fallback to threshold-immediate is a localized change if hardware
  testing demands it.

## Open Questions

- Final `expansionThreshold` value — defaulted to `1.22` (≈ 1 / 0.82); tune on the current machine
  during hardware verification.
- Whether defer-to-release feels right for dismissal on real hardware, or whether threshold-immediate
  is preferred (see Decision 2 / Risks).
- Confirm on hardware that spreading to dismiss while the overlay is up does not leave the desktop
  in an unexpected state or interfere with the next open pinch.
