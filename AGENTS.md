# AGENTS.md

This file defines the working conventions for automated agents and contributors modifying
Lunchpad. It applies to the entire repository.

## Project intent

Lunchpad restores the classic full-screen macOS Launchpad experience on macOS 26 Tahoe. It is a
native AppKit application built with Swift Package Manager. Preserve the lightweight resident-app
model, low-latency interaction, and native macOS behavior.

## Non-negotiable constraints

- Target macOS 26.0 or later on Apple Silicon.
- Use AppKit for the application interface. Do not introduce SwiftUI without an explicit
  architectural decision.
- Keep the project SwiftPM-only. Do not add an Xcode project, storyboard, nib, or generated IDE
  files merely to build the application.
- The main process is an accessory-style resident application with a menu bar item and no
  persistent Dock icon.
- Write code comments, documentation, commit messages, and release notes in English.
- Keep user data local. Do not add accounts, telemetry, or network services unless explicitly
  requested.
- Do not edit or commit `.build/`, `dist/`, local SQLite files, or other generated artifacts.

## Repository map

- `Sources/Lunchpad/`: AppKit application, catalog scanning, UI, persistence, activation, and
  application lifecycle.
- `Sources/MultitouchKit/`: raw trackpad report parsing and four-finger pinch recognition.
- `Sources/DesktopStateKit/`: WindowServer-based Show Desktop state evaluation.
- `Sources/ApplicationMonitorKit/`: FSEvents directory monitoring primitives.
- `Sources/*Probe/`: diagnostic executables. Keep experimental behavior isolated here rather than
  in the main app.
- `Tests/`: focused tests for the reusable kits.
- `Packaging/Info.plist`: source Info.plist copied into the assembled app bundle.
- `Resources/AppIcon.icns`: packaged application icon.
- `Scripts/package-app.sh`: release build, app-bundle assembly, ad-hoc signing, DMG/ZIP creation,
  and checksum generation.
- `Scripts/verify-package.sh`: bundle, architecture, signature, archive, DMG, and checksum
  validation.
- `Docs/IOKitMultitouch.md`: verified trackpad driver path and report format.
- `Docs/RELEASING.md`: versioning, branch, tag, and release procedure.

## Build and validation

The working directory may vary. Always pass `--package-path` to SwiftPM commands.

```bash
swift build --package-path /absolute/path/to/lunchpad
swift test --package-path /absolute/path/to/lunchpad
/absolute/path/to/lunchpad/.build/debug/Lunchpad
```

When packaging or release metadata changes, run the complete package validation with the intended
version:

```bash
VERSION=0.1.1-beta.1 ./Scripts/package-app.sh
VERSION=0.1.1-beta.1 ./Scripts/verify-package.sh
```

Before handing work off, run at least the tests relevant to the change. For a commit-ready review,
run the full Swift test suite, `git diff --check`, and package verification when packaging is in
scope. Report any check that could not be run.

## Architecture and behavioral invariants

### Activation and lifecycle

- Launching the process must not automatically show the full-screen launcher.
- The launcher can be shown through the four-finger pinch, the configured Carbon global hot key,
  or a left-click on the menu bar item.
- Clicking an application must hide Lunchpad immediately before starting the application. Never
  wait for the launched application to finish opening.
- Escape and empty-space clicks leave the current logical folder first, then close Lunchpad at the
  root level.
- Keep Dock interaction available. Lunchpad hides the menu bar while visible but must not treat the
  Dock as part of its own interactive content.

### Four-finger gesture

- The macOS four-finger pinch is reserved before the public AppKit event layer. Do not replace the
  current implementation with `NSEvent`, `CGEventTap`, or magnification-event monitoring; those
  paths cannot reliably receive the system gesture.
- `MultitouchKit` opens `AppleMultitouchDevice` through public IOKit APIs and consumes the private
  driver report ABI. Read `Docs/IOKitMultitouch.md` before modifying this path.
- Treat raw driver input as untrusted. Validate report type, lengths, offsets, contact counts, and
  sensor dimensions before reading data. Unknown formats must be ignored safely.
- Multitouch callbacks run off the main thread. Dispatch AppKit work to the main actor.
- Pinch completion is intentionally separated from threshold detection so the system's interactive
  gesture does not alter Lunchpad's fixed-duration animation.

### Show Desktop interaction

- When macOS is showing the desktop, an inward four-finger pinch restores displaced windows and
  must not open Lunchpad.
- Detect the actual WindowServer state rather than inferring it from a preceding outward gesture.
  Show Desktop can also be entered through a Hot Corner, keyboard shortcut, or wallpaper click.
- Sample Show Desktop state at the beginning of a new contact sequence, before macOS starts moving
  windows back on screen. Suppress only that contact sequence.
- Keep the geometry heuristic and its edge cases covered by `DesktopStateKitTests`.

### Application catalog and monitoring

- Scan `~/Applications`, `/Applications`, and `/System/Applications`. Finder hierarchy is a
  discovery mechanism, not Launchpad folder structure.
- Prefer localized bundle display names. Preserve the fallback order in `AppScanner` unless a
  verified compatibility issue requires changing it.
- A `.app` is a directory and may be observed while still being copied. Do not expose it until its
  `Info.plist` and main executable are present.
- FSEvents is a dirty signal, not a transaction log. Keep event coalescing and the two-identical-
  snapshots stability check so repeated writes do not produce partial catalog updates.
- Dropped events or changed roots require a recovery scan. Do not assume every app change maps to
  exactly one filesystem event.
- App identities should remain stable across path changes when a bundle identifier is available.

### Logical folders and persistence

- Launchpad folders are logical groups stored in SQLite. They are not Finder directories and must
  never move, delete, or rewrite `.app` bundles.
- An application belongs to at most one logical folder. Deleting a folder returns its applications
  to the root level.
- The default Other folder may initially receive utilities, but later reconciliation must preserve
  user assignments rather than continuously mirroring `/Applications/Utilities`.
- The database lives at:

  ```text
  ~/Library/Application Support/com.arichyx.Lunchpad/layout.sqlite3
  ```

- Preserve existing layout data when reconciling scans. If the database is unavailable, the app
  should remain usable with the documented flat-layout fallback.

### AppKit UI and performance

- Keep the fixed paged grid model instead of turning it into a vertically scrolling collection.
- Horizontal two-finger scrolling must be consumed by Lunchpad and must not leak to applications
  below the overlay.
- Use click semantics: activate an icon only when mouse-up completes on the intended item. A drag
  away before release must cancel activation.
- Keep the background and content animations independent. The background must cover the entire
  display immediately and animate opacity without scaling from the center or exposing screen-edge
  gaps.
- Account for the menu bar, display notch, and Dock on every screen edge, including an auto-hidden
  Dock that appears while Lunchpad is open.
- Avoid bundle, filesystem, and Launch Services work during page transitions. Reuse cached icons
  and keep high-frequency AppKit paths on lightweight data.

## Packaging and releases

- Current packages are ad-hoc signed and are not notarized. Never imply that they carry a trusted
  Developer ID signature or bypass Gatekeeper.
- Stable tags use `vMAJOR.MINOR.PATCH`; prereleases use tags such as `v0.1.1-beta.1` or
  `v0.1.1-rc.1`.
- `main` is the only long-lived branch. Use short-lived `feat/*`, `fix/*`, or `docs/*` branches and
  merge through a pull request after CI passes.
- Release tags must point to commits contained in `main`. Never move or reuse a published tag.
- Pushing a valid tag runs `.github/workflows/release.yml`, which tests and packages the tagged
  commit, uploads DMG/ZIP/checksum assets, and creates a Draft GitHub Release. A version containing
  a hyphen is explicitly created with GitHub's prerelease flag.
- Review and smoke-test the Draft before publishing it. `--notes-file` passed to `gh release edit`
  is the Markdown body of the Release. Publishing a prerelease must retain `--prerelease`; stable
  releases must omit it.
- Keep installation requirements, ad-hoc signing status, compatibility notes, and meaningful
  user-visible changes in the Release body.

Follow `Docs/RELEASING.md` for the complete release checklist.

## Change discipline

- Preserve unrelated user changes in a dirty worktree.
- Prefer the smallest change that maintains the invariants above. Avoid broad rewrites while
  fixing a focused regression.
- Add or update tests for parsers, gesture state machines, filesystem event handling, persistence,
  and geometry heuristics whenever practical.
- Do not weaken a safety check merely to make a probe or one hardware sample pass.
- For hardware-specific behavior, distinguish what was verified on the current machine from what
  is assumed to work elsewhere.
- Update README or focused documentation when commands, requirements, paths, limitations, or user
  workflows change.
