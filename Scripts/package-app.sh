#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"

app_name="Lunchpad"
executable_name="Lunchpad"
configuration="${CONFIGURATION:-release}"
version="${VERSION:-0.1.0}"
build_number="${BUILD_NUMBER:-1}"
target_arch="${TARGET_ARCH:-arm64}"
output_dir="${OUTPUT_DIR:-$project_root/dist}"
app_bundle="$output_dir/$app_name.app"
archive_base="$app_name-$version-macos-$target_arch"
zip_path="$output_dir/$archive_base.zip"
dmg_path="$output_dir/$archive_base.dmg"
checksum_path="$output_dir/SHA256SUMS.txt"

version_pattern='^([0-9]+\.[0-9]+\.[0-9]+)(-([0-9A-Za-z-]+\.)*[0-9A-Za-z-]+)?$'
if [[ ! "$version" =~ $version_pattern ]]; then
    echo "VERSION must use MAJOR.MINOR.PATCH or a SemVer prerelease: $version" >&2
    exit 1
fi
bundle_version="${BASH_REMATCH[1]}"

if [[ ! "$build_number" =~ ^[0-9]+$ ]]; then
    echo "BUILD_NUMBER must contain digits only: $build_number" >&2
    exit 1
fi

if [[ "$target_arch" != "arm64" ]]; then
    echo "Lunchpad currently supports arm64 release builds only: $target_arch" >&2
    exit 1
fi

swift build \
    --package-path "$project_root" \
    --configuration "$configuration" \
    --arch "$target_arch" \
    --product "$executable_name"

bin_dir="$(
    swift build \
        --package-path "$project_root" \
        --configuration "$configuration" \
        --arch "$target_arch" \
        --show-bin-path
)"
executable_path="$bin_dir/$executable_name"
resource_bundle_name="Lunchpad_Lunchpad.bundle"
resource_bundle_path="$bin_dir/$resource_bundle_name"

if [[ ! -x "$executable_path" ]]; then
    echo "Missing executable: $executable_path" >&2
    exit 1
fi

if [[ ! -f "$resource_bundle_path/en.lproj/Localizable.strings" ]]; then
    echo "Missing English localization: $resource_bundle_path" >&2
    exit 1
fi

if [[ ! -f "$resource_bundle_path/zh-hans.lproj/Localizable.strings" ]]; then
    echo "Missing Simplified Chinese localization: $resource_bundle_path" >&2
    exit 1
fi

mkdir -p "$output_dir"
rm -rf \
    "$app_bundle" \
    "$zip_path" \
    "$dmg_path" \
    "$checksum_path" \
    "$output_dir/$app_name.zip"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"

cp "$executable_path" "$app_bundle/Contents/MacOS/$executable_name"
ditto "$resource_bundle_path" "$app_bundle/Contents/Resources/$resource_bundle_name"
cp "$project_root/Packaging/Info.plist" "$app_bundle/Contents/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$app_bundle/Contents/Resources/AppIcon.icns"
cp "$project_root/LICENSE" "$app_bundle/Contents/Resources/LICENSE.txt"
chmod 755 "$app_bundle/Contents/MacOS/$executable_name"

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $bundle_version" \
    "$app_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion $build_number" \
    "$app_bundle/Contents/Info.plist"

plutil -lint "$app_bundle/Contents/Info.plist"

# Ad-hoc signing requires no Apple Developer account. It seals the local bundle but does not
# establish a trusted developer identity and cannot be used for Apple notarization.
codesign \
    --force \
    --sign - \
    --timestamp=none \
    "$app_bundle"

codesign --verify --deep --strict --verbose=2 "$app_bundle"

ditto \
    -c \
    -k \
    --sequesterRsrc \
    --keepParent \
    "$app_bundle" \
    "$zip_path"

dmg_root="$(mktemp -d "${TMPDIR:-/tmp}/lunchpad-dmg.XXXXXX")"
cleanup() {
    rm -rf "$dmg_root"
}
trap cleanup EXIT

ditto "$app_bundle" "$dmg_root/$app_name.app"
ln -s /Applications "$dmg_root/Applications"
cp "$project_root/LICENSE" "$dmg_root/LICENSE.txt"

hdiutil create \
    -quiet \
    -volname "$app_name" \
    -srcfolder "$dmg_root" \
    -format UDZO \
    -ov \
    "$dmg_path"

hdiutil verify "$dmg_path"

(
    cd "$output_dir"
    shasum -a 256 \
        "$(basename "$dmg_path")" \
        "$(basename "$zip_path")" \
        > "$(basename "$checksum_path")"
)

echo
echo "Built: $app_bundle"
echo "DMG: $dmg_path"
echo "ZIP: $zip_path"
echo "Checksums: $checksum_path"
