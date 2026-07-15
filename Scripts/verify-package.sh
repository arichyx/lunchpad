#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"

app_name="Lunchpad"
version="${VERSION:-0.1.0}"
version_pattern='^([0-9]+\.[0-9]+\.[0-9]+)(-([0-9A-Za-z-]+\.)*[0-9A-Za-z-]+)?$'
if [[ ! "$version" =~ $version_pattern ]]; then
    echo "VERSION must use MAJOR.MINOR.PATCH or a SemVer prerelease: $version" >&2
    exit 1
fi
bundle_version_expected="${BASH_REMATCH[1]}"
target_arch="${TARGET_ARCH:-arm64}"
output_dir="${OUTPUT_DIR:-$project_root/dist}"
archive_base="$app_name-$version-macos-$target_arch"
app_bundle="$output_dir/$app_name.app"
zip_path="$output_dir/$archive_base.zip"
dmg_path="$output_dir/$archive_base.dmg"
checksum_path="$output_dir/SHA256SUMS.txt"
resource_bundle_name="Lunchpad_Lunchpad.bundle"

verify_localizations() {
    local bundle="$1/Contents/Resources/$resource_bundle_name"
    test -f "$bundle/en.lproj/Localizable.strings"
    test -f "$bundle/zh-hans.lproj/Localizable.strings"
    plutil -lint "$bundle/en.lproj/Localizable.strings" >/dev/null
    plutil -lint "$bundle/zh-hans.lproj/Localizable.strings" >/dev/null
}

for path in "$app_bundle" "$zip_path" "$dmg_path" "$checksum_path"; do
    if [[ ! -e "$path" ]]; then
        echo "Missing release artifact: $path" >&2
        exit 1
    fi
done

bundle_version="$(
    /usr/libexec/PlistBuddy \
        -c "Print :CFBundleShortVersionString" \
        "$app_bundle/Contents/Info.plist"
)"

if [[ "$bundle_version" != "$bundle_version_expected" ]]; then
    echo "Bundle version mismatch: expected $bundle_version_expected, found $bundle_version" >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_bundle"
lipo "$app_bundle/Contents/MacOS/$app_name" -verify_arch "$target_arch"
verify_localizations "$app_bundle"
hdiutil verify "$dmg_path"

(
    cd "$output_dir"
    shasum -a 256 -c "$(basename "$checksum_path")"
)

zip_root="$(mktemp -d "${TMPDIR:-/tmp}/lunchpad-zip-verify.XXXXXX")"
mount_point="$(mktemp -d "${TMPDIR:-/tmp}/lunchpad-dmg-verify.XXXXXX")"
mounted=false
cleanup() {
    if [[ "$mounted" == true ]]; then
        hdiutil detach -quiet "$mount_point" || true
    fi
    rm -rf "$zip_root"
    rmdir "$mount_point" 2>/dev/null || true
}
trap cleanup EXIT

ditto -x -k "$zip_path" "$zip_root"
test -d "$zip_root/$app_name.app"
codesign --verify --deep --strict "$zip_root/$app_name.app"
verify_localizations "$zip_root/$app_name.app"

hdiutil attach \
    -quiet \
    -readonly \
    -nobrowse \
    -mountpoint "$mount_point" \
    "$dmg_path"
mounted=true

test -d "$mount_point/$app_name.app"
test -L "$mount_point/Applications"
test "$(readlink "$mount_point/Applications")" = "/Applications"
test -f "$mount_point/LICENSE.txt"
codesign --verify --deep --strict "$mount_point/$app_name.app"
verify_localizations "$mount_point/$app_name.app"

echo "Verified release package: $archive_base"
