# CLAUDE.md

This file orients Claude Code when working in this repository.

## Read AGENTS.md first

`AGENTS.md` is the single source of truth for working conventions. It is not a
subset of this file — it is the authoritative spec. Read it before making changes:

- Project intent and non-negotiable constraints (macOS 26 / Apple Silicon, AppKit-only,
  SwiftPM-only, resident accessory app, English for all prose).
- Repository map of `Sources/`, `Tests/`, `Packaging/`, `Scripts/`, and `Docs/`.
- Build and validation commands (always pass `--package-path` — the working directory
  may vary).
- Architecture and behavioral invariants: activation & lifecycle, the reserved
  four-finger pinch, Show Desktop interaction, catalog scanning & FSEvents,
  logical folders & SQLite persistence, AppKit UI & performance.
- Packaging and release discipline (ad-hoc signed, tag scheme, `main`-only policy).
- Change discipline (smallest change, tests for parsers/state machines/geometry,
  preserve unrelated dirty-worktree changes).

When this file and `AGENTS.md` disagree, `AGENTS.md` wins. Do not duplicate
`AGENTS.md` content here — update `AGENTS.md` instead.

## Spec-driven workflow (OpenSpec)

Behavior is specified under `openspec/` (configured by `openspec/config.yaml`).
Specs in `openspec/specs/` describe externally observable behavior; proposed
changes live in `openspec/changes/` and are archived once landed.

This project ships custom slash commands that drive that loop. Prefer them for
non-trivial behavior changes:

- `/opsx:propose` — draft a change proposal with spec deltas
- `/opsx:apply` — implement an agreed proposal against the specs
- `/opsx:archive` — move a landed change into the spec archive
- `/opsx:sync` — reconcile specs with the current code
- `/opsx:explore` — search specs and changes

Normative requirements in specs use SHALL / MUST with concrete scenarios.
Keep private multitouch driver details in the multitouch capability spec rather
than duplicating them.

## Quick build / test

```bash
swift build --package-path /Users/arichyx/Documents/proj/lunchpad
swift test  --package-path /Users/arichyx/Documents/proj/lunchpad
```

Run packaging validation (with the intended version) whenever packaging or
release metadata changes — see `AGENTS.md` for the full command and
`Docs/RELEASING.md` for the release checklist.

## Commits

`main` is the only long-lived branch. Use short-lived `feat/*`, `fix/*`, or
`docs/*` branches and merge through a pull request after CI passes. Write commit
messages in English.
