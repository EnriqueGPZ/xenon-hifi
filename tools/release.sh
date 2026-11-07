#!/bin/zsh
# Packages CDPlayer.app for a GitHub release, without installing it:
#   dist/CDPlayer.app and dist/XENON-HiFi-<version>-macOS.zip
# Universal (Apple silicon + Intel) when the toolchain can do it, else this Mac's arch.
# Signed with SIGN_IDENTITY if set, else ad hoc (people open it once with
# System Settings > Privacy & Security > Open Anyway).
#
# Usage: tools/release.sh
set -euo pipefail
here=${0:A:h:h}
name="CDPlayer"
scratch="$HOME/Library/Developer/$name/release-build"
dist="$here/dist"
version=$(grep -o 'CFBundleShortVersionString</key><string>[^<]*' "$here/Info.plist.in" | sed 's/.*<string>//')

if swift build -c release --package-path "$here" --scratch-path "$scratch" --arch arm64 --arch x86_64 2>&1 | grep -E "error|Build complete"; then
  bin="$(swift build -c release --package-path "$here" --scratch-path "$scratch" --arch arm64 --arch x86_64 --show-bin-path)/$name"
else
  echo "universal build not available, building for $(uname -m) only"
  swift build -c release --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error|Build complete"
  bin="$(swift build -c release --package-path "$here" --scratch-path "$scratch" --show-bin-path)/$name"
fi
[[ -x "$bin" ]] || { echo "build failed: no binary at $bin"; exit 1; }

rm -rf "$dist"
app="$dist/$name.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" -e "s/__BUNDLE_ID__/${BUNDLE_ID:-io.github.enriquegpz.xenon}/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
cp -X "$here/Resources/Assets.car" "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
cp -X "$here"/Resources/Tubes/*.png "$app/Contents/Resources/"
xattr -cr "$app"
codesign --force --sign "${SIGN_IDENTITY:--}" "$app"
codesign --verify --strict "$app"

zip="$dist/XENON-HiFi-$version-macOS.zip"
ditto -c -k --keepParent "$app" "$zip"
echo "archs: $(lipo -archs "$app/Contents/MacOS/$name")"
echo "packaged $zip ($(du -h "$zip" | cut -f1))"
