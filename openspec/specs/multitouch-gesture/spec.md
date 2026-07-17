# Multitouch Gesture Specification

## Purpose

Define the four-finger inward-pinch activation path, its recognition semantics, and its safe
fallback behavior on unsupported trackpads or driver changes.
## Requirements
### Requirement: Direct trackpad data stream

When Four-Finger Pinch is enabled, Lunchpad SHALL attempt to read contact frames from
`AppleMultitouchDeviceUserClient` through IOKit without depending on `MultitouchSupport.framework`.
When the preference is disabled, Lunchpad SHALL NOT keep the driver data stream open.

#### Scenario: Compatible trackpad is present

- **WHEN** Four-Finger Pinch is enabled and the AppleMultitouchDevice service can be opened and its shared IODataQueue can be mapped
- **THEN** Lunchpad starts the data stream on a dedicated background queue

#### Scenario: Service cannot be opened

- **WHEN** Four-Finger Pinch is enabled but no compatible service exists or an IOKit operation fails
- **THEN** Lunchpad keeps running, records the gesture path as unavailable, and leaves menu bar and global-hot-key activation available

#### Scenario: Gesture activation is disabled

- **WHEN** Lunchpad starts or runs with Four-Finger Pinch disabled
- **THEN** it does not open or retain an AppleMultitouchDevice data stream and leaves the other activation methods available

#### Scenario: User disables an active monitor

- **WHEN** the user turns Four-Finger Pinch off while monitoring is active
- **THEN** Lunchpad stops the stream and clears any pending contact sequence without activating the launcher

#### Scenario: User re-enables gesture activation

- **WHEN** the user turns Four-Finger Pinch on after it was disabled
- **THEN** Lunchpad attempts to start a fresh monitor without requiring a process restart

### Requirement: Bounded report parsing

Lunchpad SHALL parse only supported `0x75` precise-path reports and SHALL reject malformed or unsupported packets without reading beyond their declared bounds.

#### Scenario: Valid precise-path frame arrives

- **WHEN** a `0x75` packet has consistent header, contact count, and contact-record lengths
- **THEN** Lunchpad emits contacts normalized against the trackpad's reported sensor dimensions

#### Scenario: Unsupported report arrives

- **WHEN** a packet has another report type or inconsistent lengths
- **THEN** Lunchpad ignores the packet without terminating the read loop

### Requirement: Four-finger inward-pinch recognition

Lunchpad SHALL recognize an inward pinch from the contraction of mean pairwise distance among four tracked active contacts.

#### Scenario: Four contacts contract sufficiently

- **WHEN** four tracked contacts begin sufficiently spread apart and contract to 82 percent or less of their observed maximum distance within three seconds
- **THEN** Lunchpad marks one pinch activation as pending

#### Scenario: Four contacts move together without contracting

- **WHEN** a four-finger swipe preserves the contacts' pairwise distances
- **THEN** Lunchpad does not recognize it as an inward pinch

#### Scenario: Driver briefly reports a fifth contact

- **WHEN** a fifth active contact appears while the original four remain present
- **THEN** Lunchpad continues tracking the original four without resetting the gesture

#### Scenario: Gesture remains stationary too long

- **WHEN** the active four-finger sequence exceeds three seconds without triggering
- **THEN** Lunchpad resets the distance baseline to prevent a delayed activation

### Requirement: Activation after contact release

Lunchpad SHALL defer launcher presentation until a recognized pinch has completed and the user has lifted the gesture contacts.

#### Scenario: Threshold is reached while fingers remain down

- **WHEN** contraction crosses the recognition threshold but at least two active contacts remain
- **THEN** Lunchpad keeps the activation pending and does not show the launcher yet

#### Scenario: User releases the recognized gesture

- **WHEN** the active contact count drops below two after a recognized pinch
- **THEN** Lunchpad emits exactly one activation and rearms only after the contact sequence resets

### Requirement: Show Desktop restoration

Lunchpad SHALL preserve the system's Show Desktop restoration gesture by sampling the actual
WindowServer state at the beginning of each four-finger contact sequence. The decision SHALL apply
only to that contact sequence and SHALL NOT be inferred from a previous outward gesture.

#### Scenario: Show Desktop is active

- **GIVEN** sizeable normal application windows are present in the on-screen WindowServer list but their centres are predominantly displaced beyond every active display
- **WHEN** the user begins and completes an inward four-finger pinch
- **THEN** Lunchpad suppresses launcher activation for that contact sequence so macOS can restore the windows

#### Scenario: A sticky window remains visible

- **GIVEN** at least three regular application windows are displaced and outnumber the remaining visible windows by at least three to one
- **WHEN** the user completes an inward four-finger pinch
- **THEN** Lunchpad treats the dominant displacement as Show Desktop and suppresses launcher activation

#### Scenario: Show Desktop was entered without a trackpad gesture

- **GIVEN** Show Desktop was entered through a Hot Corner, keyboard shortcut, or wallpaper click
- **WHEN** WindowServer reports the displaced-window state and the user completes an inward pinch
- **THEN** Lunchpad suppresses launcher activation for that contact sequence

#### Scenario: Previous outward gesture did not reveal the desktop

- **GIVEN** a previous outward gesture failed and normal application windows remain visible
- **WHEN** the user completes an inward four-finger pinch
- **THEN** Lunchpad emits its normal launcher activation

#### Scenario: A later ordinary pinch occurs

- **GIVEN** a Show Desktop restore pinch was previously suppressed
- **WHEN** a new contact sequence begins while normal application windows are visible and completes as an inward pinch
- **THEN** Lunchpad emits its normal launcher activation

### Requirement: Hardware compatibility boundary

Lunchpad SHALL fail safely when a trackpad or macOS release does not provide the verified report format.

#### Scenario: External trackpad uses a different report format

- **WHEN** contact packets do not match the supported `0x75` layout
- **THEN** four-finger activation remains unavailable while all non-gesture launcher features continue operating

### Requirement: Four-finger outward-spread recognition

Lunchpad SHALL recognize an outward spread (expand / unpinch) from the expansion of mean pairwise
distance among four tracked active contacts, as the symmetric counterpart of the inward-pinch
recognition. The spread direction SHALL be recognized through the same `AppleMultitouchDevice`
report stream and the same bounded `0x75` parsing path as the inward pinch; Lunchpad SHALL NOT use
`NSEvent`, `CGEventTap`, or magnification-event monitoring to detect it.

#### Scenario: Four contacts expand sufficiently

- **WHEN** four tracked contacts begin sufficiently close together and expand to 122 percent or more of their observed minimum mean pairwise distance within three seconds
- **THEN** Lunchpad marks one spread dismissal as pending

#### Scenario: Four contacts move together without expanding

- **WHEN** a four-finger swipe preserves the contacts' pairwise distances while the launcher is visible
- **THEN** Lunchpad does not recognize it as an outward spread

#### Scenario: Driver briefly reports a fifth contact

- **WHEN** a fifth active contact appears while the original four remain present during an outward spread
- **THEN** Lunchpad continues tracking the original four without resetting the gesture

#### Scenario: Gesture remains stationary too long

- **WHEN** the active four-finger sequence exceeds three seconds without the spread triggering
- **THEN** Lunchpad resets the distance baseline to prevent a delayed dismissal

### Requirement: Direction and visibility gating

Lunchpad SHALL disambiguate the reserved four-finger gesture by direction together with the
launcher's visibility. The inward pinch SHALL be honored as an activation only while the launcher is
hidden, and the outward spread SHALL be honored as a dismissal only while the launcher is visible.
An outward spread performed while the launcher is hidden SHALL NOT activate or dismiss Lunchpad and
SHALL be left to macOS, and SHALL NOT be used to infer Show Desktop state for a later inward pinch.

#### Scenario: Spread while the launcher is hidden

- **WHEN** the launcher is hidden and the user performs a four-finger outward spread
- **THEN** Lunchpad does not show or dismiss the launcher and leaves the gesture to macOS

#### Scenario: Spread while the launcher is visible

- **WHEN** the launcher is visible and the user performs a four-finger outward spread that reaches the recognition threshold
- **THEN** Lunchpad marks the spread as a pending dismissal for the current contact sequence

#### Scenario: Pinch while the launcher is visible

- **WHEN** the launcher is already visible and the user performs a four-finger inward pinch
- **THEN** Lunchpad does not show the launcher again and the gesture does not dismiss it

#### Scenario: Outward spread does not affect a later activation

- **GIVEN** the launcher is hidden and a previous contact sequence was an outward spread
- **WHEN** a new contact sequence begins with normal application windows visible and completes as an inward pinch
- **THEN** Lunchpad samples the actual WindowServer state for that sequence and emits its normal launcher activation or suppression decision without inferring state from the earlier spread

### Requirement: Dismissal after contact release

Lunchpad SHALL defer launcher dismissal until a recognized outward spread has completed and the user
has lifted the gesture contacts, mirroring the inward pinch's separation of threshold detection
from completion so the system's interactive outward gesture does not alter Lunchpad's fixed-duration
close animation.

#### Scenario: Threshold is reached while fingers remain down

- **WHEN** expansion crosses the recognition threshold but at least two active contacts remain
- **THEN** Lunchpad keeps the dismissal pending and does not close the launcher yet

#### Scenario: User releases the recognized spread

- **WHEN** the active contact count drops below two after a recognized outward spread and the launcher is still visible
- **THEN** Lunchpad emits exactly one dismissal and rearms only after the contact sequence resets

#### Scenario: Launcher is no longer visible at release

- **WHEN** the active contact count drops below two after a recognized outward spread but the launcher was already dismissed by another path during the gesture
- **THEN** Lunchpad emits no further dismissal for that contact sequence

