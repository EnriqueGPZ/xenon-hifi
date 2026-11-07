#!/bin/zsh
# Builds CDPlayer and installs it to ~/Applications/CDPlayer.app.
# Build products live in ~/Library/Developer/CDPlayer, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
#
# Usage: ./build.sh            release build, install
#        ./build.sh --debug    debug build, install
#        ./build.sh --open     install, then quit the running copy and open the new one
set -euo pipefail
here=${0:A:h}
name="CDPlayer"
scratch="$HOME/Library/Developer/$name/build"
config=release
[[ " $* " == *" --debug "* ]] && config=debug

# Sign with a certificate that stays the same from build to build, so macOS
# remembers permissions (like reading the CD) instead of asking after every
# build. Ad hoc signing changes identity each time. Uses SIGN_IDENTITY if set
# (any code-signing certificate in your keychain, even a self-made one),
# else an Apple Development certificate, else ad hoc (works, but macOS may
# ask again for permission to read the CD after each build).
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
  identity=$(grep -m1 -o '"Apple Development: [^"]*"' <<<"$identities" | tr -d '"' || true)
fi
[[ -n "$identity" ]] || identity=-

swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error|warning|Build complete" | grep -v "^\[" || true
bin="$scratch/$config/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  echo "build failed: binary is older than $stale"
  swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error" | head -20
  exit 1
fi

app="$HOME/Applications/$name.app"
mkdir -p "$HOME/Applications"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" -e "s/__BUNDLE_ID__/${BUNDLE_ID:-io.github.enriquegpz.xenon}/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# The icon: Icon/AppIcon.icon -> Resources/Assets.car + AppIcon.icns, rebuilt when it changed.
if [[ -d "$here/Icon/AppIcon.icon" ]]; then
  car="$here/Resources/Assets.car"
  # Rebuilt only when the .icon changed and Xcode's actool is there; the
  # compiled icon ships in Resources/, so Command Line Tools alone are enough.
  if [[ ! -f "$car" || -n "$(find "$here/Icon/AppIcon.icon" -newer "$car" | head -1)" ]] \
     && xcrun -f actool >/dev/null 2>&1; then
    "$here/tools/make_icon.sh"
  fi
  cp -X "$car" "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
fi
# The tube pictures of the tube preamp (made by tools/tube_layers.py).
cp -X "$here"/Resources/Tubes/*.png "$app/Contents/Resources/"
xattr -cr "$app"
codesign --force --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
echo "installed $app (signed: ${identity})"

if [[ " $* " == *" --open "* ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  open "$app"
fi
