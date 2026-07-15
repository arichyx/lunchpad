# Lunchpad

Lunchpad brings the classic full-screen macOS app launcher back to macOS 26 Tahoe.

It is built with AppKit and follows the familiar Launchpad experience: open it with a
four-finger pinch, browse apps page by page, search by name, open logical folders, and launch an
app with one click. The name is intentional: Lunchpad is to Launchpad what `reqwest` is to
`request`.

## Highlights

- Native full-screen AppKit interface
- Four-finger pinch activation
- Paged app grid with two-finger horizontal swiping
- Search using localized application names
- Logical folders, including the default Other folder
- Automatic updates when apps are installed, removed, or replaced
- Layout that adapts to the Dock on any screen edge
- Menu bar icon and configurable global hot key
- No cloud service, account, or network connection required

## Requirements

- macOS 26.0 or later
- Apple Silicon
- Swift 6 and the Xcode command-line tools when building from source

The four-finger gesture has currently been verified with a built-in Force Touch trackpad.

## Build and install

Download the latest DMG from
[GitHub Releases](https://github.com/arichyx/lunchpad/releases), open it, and drag Lunchpad to the
Applications folder.

Build a release app bundle from source with:

```bash
cd /absolute/path/to/lunchpad
./Scripts/package-app.sh
```

The script creates:

```text
dist/Lunchpad.app
dist/Lunchpad-0.1.0-macos-arm64.dmg
dist/Lunchpad-0.1.0-macos-arm64.zip
dist/SHA256SUMS.txt
```

Verify the complete package with:

```bash
VERSION=0.1.0 ./Scripts/verify-package.sh
```

Lunchpad uses an ad-hoc signature because the project does not require an Apple Developer
account. A copy downloaded from the internet may need to be approved once in
**System Settings → Privacy & Security** before it can open.

## Using Lunchpad

Lunchpad starts quietly in the menu bar and does not open the full-screen interface at launch.

- Pinch inward with four fingers to show Lunchpad.
- Alternatively, press Control-Shift-Space or left-click the menu bar icon.
- Swipe horizontally with two fingers, use the arrow keys, or click a page dot to change pages.
- Type in the search field to find an app.
- Click an app to close Lunchpad immediately and launch it.
- Click a folder to browse its contents.
- Press Escape or click empty space to leave a folder or close Lunchpad.
- Right-click the menu bar icon for Show and Quit actions.

If macOS performs another action for the same four-finger gesture, change or disable that gesture
in System Settings.

## Change the global hot key

The default hot key is Control-Shift-Space. It can be changed to Control-Option-L or disabled:

```bash
defaults write com.arichyx.Lunchpad globalHotKey -string control-option-l
defaults write com.arichyx.Lunchpad globalHotKey -string disabled
```

Restore the default with:

```bash
defaults delete com.arichyx.Lunchpad globalHotKey
```

## Local data

Lunchpad stores page order and logical folder assignments locally at:

```text
~/Library/Application Support/com.arichyx.Lunchpad/layout.sqlite3
```

Logical folders do not move or modify real `.app` bundles. Removing a logical folder only returns
its apps to the root level.

## Development

Lunchpad is a Swift Package Manager project and does not require an Xcode project.

```bash
swift build --package-path /absolute/path/to/lunchpad
swift test --package-path /absolute/path/to/lunchpad
/absolute/path/to/lunchpad/.build/debug/Lunchpad
```

The trackpad connection and report format are documented in
[`Docs/IOKitMultitouch.md`](Docs/IOKitMultitouch.md). The app bundle is assembled by
[`Scripts/package-app.sh`](Scripts/package-app.sh).

Release tags, branches, and GitHub Release automation are documented in
[`Docs/RELEASING.md`](Docs/RELEASING.md).

## Known limitations

- External Magic Trackpads may use report formats that are not handled yet.
- Keyboard navigation and drag-to-create folder editing are not implemented yet.
- Ad-hoc builds cannot be notarized and may require manual approval after download.
- Confirm that `Assets/AppIcon.png` is licensed for redistribution before publishing binaries.

## License

Lunchpad is available under the [MIT License](LICENSE).
