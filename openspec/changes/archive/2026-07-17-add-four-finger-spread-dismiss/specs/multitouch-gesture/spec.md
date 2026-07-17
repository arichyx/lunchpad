# multitouch-gesture delta — add-four-finger-spread-dismiss

## ADDED Requirements

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
