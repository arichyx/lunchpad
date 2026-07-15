# Releasing Lunchpad

Lunchpad uses a tag-driven GitHub Actions workflow. Release artifacts are always built from the
tagged source on GitHub's Apple Silicon macOS 26 runner rather than uploaded from a developer
machine.

## Versioning

Release tags and user-visible versions use `vMAJOR.MINOR.PATCH`, for example `v0.1.0`.

- Increment PATCH for compatible bug fixes.
- Increment MINOR for user-visible features.
- Reserve `v1.0.0` for a broadly tested stable release.
- Never move or reuse a published tag. Publish a new patch version instead.

The release workflow removes the leading `v` and writes the remaining version to
`CFBundleShortVersionString`. `CFBundleVersion` uses the monotonically increasing GitHub Actions
run number.

## Branch policy

`main` is the only long-lived branch and must remain releasable. Work is developed on short-lived
`feat/*`, `fix/*`, or `docs/*` branches and merged through pull requests after CI passes. Release
tags must point to commits contained in `main`.

## Before tagging

1. Confirm CI passes on `main`.
2. Confirm the working tree is clean and up to date with `origin/main`.
3. Review user-facing changes and known limitations.
4. Confirm the application icon and every bundled asset are licensed for redistribution.
5. Run a local packaging smoke test when packaging code changed:

   ```bash
   VERSION=0.1.0 ./Scripts/package-app.sh
   VERSION=0.1.0 ./Scripts/verify-package.sh
   ```

## Create a release

Create and push an annotated tag from `main`:

```bash
git switch main
git pull --ff-only
git tag -a v0.1.0 -m "Lunchpad 0.1.0"
git push origin v0.1.0
```

The Release workflow then:

1. Validates the tag and its relationship to `main`.
2. Runs the test suite.
3. Builds an ad-hoc-signed app bundle.
4. Creates versioned DMG and ZIP archives plus `SHA256SUMS.txt`.
5. Creates a Draft GitHub Release with generated release notes.

Download the draft DMG, drag Lunchpad to Applications, and perform a final smoke test. Review the
generated notes, add installation and compatibility details when necessary, then publish the
draft from GitHub.

## Signing status

Current releases use an ad-hoc signature and cannot be notarized. Release notes must tell users
that macOS may require manual approval on first launch. The DMG is an installation container and
does not bypass Gatekeeper.

If Developer ID distribution is added later, the release workflow should import the signing
certificate from GitHub Actions secrets, enable the hardened runtime, sign nested code before the
outer app bundle, submit the archive with `notarytool`, and staple the notarization ticket before
publishing the final assets.
