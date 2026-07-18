## Context

`LunchpadWindow.show()` currently reads `NSScreen.main` and uses that screen for the interaction
window, backdrop window, optional menu-bar Dock-corner window, safe-area insets, and grid layout.
The four-finger gesture callback reaches `AppDelegate` off the main thread and already dispatches
presentation work to the main actor. The application observes external application activation for
dismissal, but it does not observe `NSWorkspace.activeSpaceDidChangeNotification`; all launcher
windows can join every Space.

The change must preserve AppKit main-thread access, the reusable window model, the fixed-duration
presentation and dismissal animations, Dock interaction, and existing behavior for status-item and
global-hot-key activation.

## Goals / Non-Goals

**Goals:**

- Present a pinch-activated launcher on the connected display containing the pointer when the
  pinch completes.
- Configure every launcher-owned presentation window from one explicit screen so the backdrop,
  hit-testing surface, safe areas, and menu-bar corner cannot diverge.
- Close a visible launcher through the existing dismissal path whenever macOS reports that the
  active Space changed.
- Make the screen-selection policy and visible-state dismissal gate testable without depending on
  a particular physical display arrangement.

**Non-Goals:**

- Changing the target screen selected by the status item or global hot key.
- Following the pointer to another display after presentation has begun.
- Replacing AppKit screen APIs, changing Mission Control preferences, or identifying private Space
  IDs.
- Changing gesture recognition thresholds, Show Desktop suppression, animation durations, or
  launcher persistence.

## Decisions

### Resolve the pinch target on the main actor from the global pointer location

After the gesture callback dispatches to the main actor, `AppDelegate` will sample
`NSEvent.mouseLocation` and select the first current `NSScreen` whose global frame contains that
point. If no screen matches, it will use `NSScreen.main`; if AppKit temporarily exposes no main
screen, the existing window frame remains a final defensive fallback.

This uses the same AppKit coordinate space for the pointer and screen frames and avoids reading
AppKit state from the multitouch callback thread. Sampling at completed activation reflects where
the user is acting when Lunchpad opens. Resolving a display from the gesture device itself was
rejected because the raw trackpad stream has no display association, and using the key or main
screen was rejected because it does not express pointer intent on a multi-display desktop.

Screen containment will be isolated as a deterministic geometry policy so arrangements with
negative origins, vertically stacked displays, and an unmatched point can be unit tested.

### Pass the selected screen explicitly into presentation

`AppDelegate.showLunchpad` and `LunchpadWindow.show` will accept a target-screen argument for pinch
activation. `LunchpadWindow` will derive the interaction frame, backdrop frame, Dock corner,
safe-area insets, and available grid height exclusively from that argument. Existing activation
callers that do not provide a target will retain their current main-screen behavior.

Passing one screen through the presentation boundary is preferred to independently asking each
window for its current screen because the windows are reusable and may still report their previous
display before their frames move. It also provides a stable target if the pointer moves while the
opening animation is running.

### Observe public active-Space notifications for dismissal

`AppDelegate` will register a main-queue observer for
`NSWorkspace.activeSpaceDidChangeNotification` during startup and remove it during termination.
The handler will check whether the launcher is visible and, only then, invoke the same close path
used by Escape and other dismissals. It will not terminate the resident process, stop monitors, or
change settings-window behavior.

Using the public workspace notification avoids polling and private Space identifiers. Relying only
on window collection behavior was rejected because automatic movement or hiding would not complete
Lunchpad's own logical dismissal state or persistence work. The existing idempotent close guard
handles a Space change racing with another dismissal event.

This notification fires after the Space transition has completed rather than at its start; the
launcher therefore remains visible through the Mission Control animation. The "detect transition
start" alternative below was investigated and rejected, so the post-transition notification is
treated as the public-API ceiling.

### Retain current window collection behavior

The launcher windows will keep `.canJoinAllSpaces`, `.fullScreenAuxiliary`, and `.stationary`.
Changing those flags is not required to detect a Space transition and could alter presentation on
full-screen apps or separate-Spaces display configurations. The explicit notification instead owns
the lifecycle decision.

## Alternatives Considered

### Detect transition start via a hidden occlusion-sentinel window — rejected

To close the launcher as soon as a Space transition *begins* (rather than after it completes), a
hidden "sentinel" `NSWindow` with `collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary,
.ignoresCycle]`, `ignoresMouseEvents = true`, a 1×1 transparent content surface ordered into the
target screen, and `NSWindow.didChangeOcclusionStateNotification` observation was investigated as
a way to receive a `visible → occluded` edge before the final workspace notification arrives.

A throwaway diagnostic (`Sources/SpaceTransitionProbe/`) was built to measure the timing against
`NSWorkspace.activeSpaceDidChangeNotification` across the macOS trigger paths. The measured results
on macOS 26 ruled the approach out:

- **Three-finger horizontal swipe** — the most common Space switch path — produced no sentinel
  occlusion edge at all. The `WORKSPACE` notification fired on time, but the sentinel never moved
  off `.visible`. `.moveToActiveSpace` does not imply "the system tears the window down at
  transition start"; it only governs where the window re-arms on the next activation.
- **Mission Control / coverage-style transitions** produced a sentinel edge, but it arrived
  *simultaneously* with the workspace notification (≤ 1 ms apart, sometimes later), delivering no
  measurable head start.
- The sentinel edges that did fire coincided with other windows occluding the sentinel, so they
  would also fire under Mission Control, Stage Manager, or full-screen app layering — i.e. they
  are not equivalent to a Space transition signal and would introduce false-positive dismissals.

The probe was removed after the measurement so the repository does not carry tooling for an
approach that was not adopted. The post-transition `activeSpaceDidChangeNotification` is therefore
the only signal used; "close at transition start" is treated as not achievable within public
AppKit APIs. Private `CGS*` Space APIs were not considered because they conflict with the project's
non-negotiable constraint against private Mission Control / Space APIs.

## Risks / Trade-offs

- **The cursor is temporarily outside every reported screen during display reconfiguration** →
  fall back to the current main screen and keep presentation usable.
- **A Space notification arrives while another close animation is in progress** → rely on the
  existing visibility and `isAnimatingClose` guards so close remains idempotent.
- **`.canJoinAllSpaces` can briefly expose the launcher during the system's Space animation** →
  dismiss as soon as the public notification is delivered; avoid private APIs or collection
  behavior changes with broader full-screen side effects.
- **AppKit notification delivery is difficult to exercise as a true Mission Control integration
  test** → isolate the visibility gate for unit coverage and include a manual multi-Space smoke
  test.
- **`activeSpaceDidChangeNotification` fires after the transition, not at its start, so the
  launcher remains visible through the Mission Control animation** → accepted as the public-API
  ceiling; the sentinel-based "transition start" alternative was measured and rejected (see
  Alternatives Considered). The launcher still closes through its normal path as soon as macOS
  reports the completed change.

## Migration Plan

No data or persistence migration is required. Implement the screen resolver and explicit
presentation target first, then add the Space observer and tests. Rollback consists of removing the
observer and returning pinch presentation to the existing no-argument main-screen path.

## Open Questions

None.
