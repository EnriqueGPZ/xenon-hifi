# XENON Hi-Fi (CDPlayer)

A native macOS app (Swift 6.2, SwiftUI, macOS 26) that looks and behaves like a stack of hi-fi units: CD player, music file player, tube preamp and graphic equalizer. It runs on this Mac only. There's no server: a local SwiftData store, and the internet is used only for MusicBrainz disc titles.

Read `README.md` for what the app does and `docs/DESIGN-DECISIONS.md` before changing anything important. Its **Do not change** section lists behaviour that was measured or seen to break.

## Layout

- `Package.swift`: a Swift package, no Xcode project. Targets: `CDPlayer` (the app, main-actor by default) and `CDPlayerKit` (pure logic, no SwiftUI, unit-tested).
- `Sources/CDPlayer/App.swift`: windows, menus, keyboard shortcuts, the store location.
- `Sources/CDPlayer/Models.swift`: app state; builds the two playbacks, the EQ and the tube model.
- `Sources/CDPlayer/Player/`: sound and hardware.
  - `Playback.swift`: one AVAudioEngine per unit, chain `source → tube → EQ → mixer`, meter taps after the EQ.
  - `CDDrive.swift`: finding the audio CD.
  - `OutputDevice.swift`: the DAC sample rate.
  - `TubeUnit.swift`: the tube stage as an in-process `AUAudioUnit`.
  - `*Model.swift`: the state behind each unit.
- `Sources/CDPlayer/UI/`: the units' looks.
  - `Tokens.swift`: every size, colour and duration of the units.
  - `Grid.swift`: the 4 pt spacing.
  - `UnitStack.swift`: stacking the units as child windows.
  - One view per unit: `ContentView` (CD), `FilePlayerView`, `TubeView`, `EqualizerView`.
- `Sources/CDPlayerKit/`: logic that can be tested without the app.
  - Disc TOC and disc ID, MusicBrainz parsing.
  - The track readers (anti-skip memory), the music library.
  - Spectrum, VU, balance, EQ curves.
  - `Tube.swift`: the tube DSP.
- `Tests/CDPlayerKitTests/`: Swift Testing tests, including sound measurements (harmonics, level, aliasing, clicks).
- `Resources/Tubes/`: the tube pictures (cold + glow layers), made by `tools/tube_layers.py`.
- `Icon/AppIcon.icon`: Icon Composer file, compiled by `tools/make_icon.sh` (needs Xcode's `actool`; skipped without it).
- `docs/`: the original brief, user stories, design decisions, and how it was made.

## Build and check

- **Build and install:** `./build.sh`. It installs `~/Applications/CDPlayer.app`; add `--open` to restart it with the new build.
  - Settings: `SIGN_IDENTITY` (signing certificate; the default is Apple Development, then ad hoc) and `BUNDLE_ID`.
  - Fix any warnings it shows.
- **Release package:** `tools/release.sh` writes `dist/CDPlayer.app` and `dist/XENON-HiFi-<version>-macOS.zip` (universal, ad hoc unless `SIGN_IDENTITY`), without installing anything. The version is `CFBundleShortVersionString` in `Info.plist.in`.
- **Unit tests:** `swift test --scratch-path ~/Library/Developer/CDPlayer/test-build`.
- **Self-test:** `tools/selftest.sh` runs the real app's functions on a /tmp store and exits 0 when every check passes. Add a check in `SelfTest.swift` for any new logic.
- **Snapshots, after every UI change:** run `tools/snap.sh`, then look at `/tmp/CDPlayer-shots/*-light.png` and `*-dark.png`.
  - Limit the pages with `APP_SNAPSHOT_PAGES=player,spectrum,vu,files,tubes,eq,settings`.
  - For a new panel, add a capture to `Snapshot.swift`.
- **Grid:** `tools/grid-lint.sh` and `swift tools/check-layout.swift /tmp/CDPlayer-shots/*-layout.json` must both print PASS.
  - A deliberate off-grid drawing detail gets `// grid: ok <reason>`.
- **A change is done when:** the build is clean, the tests and self-test pass, the grid checks pass, and you looked at the snapshots.
- **Trap:** a change only to comments may not relink the binary, and the self-test then refuses a stale build. Delete `~/Library/Developer/CDPlayer/build/release/CDPlayer` and build again.

## Safety rules for tests

- Snapshots, seed data and the self-test refuse to run without `APP_STORE` pointing into /tmp. Never test against the real store in `~/Library/Application Support/CDPlayer/`.
- In test mode the app must never touch the CD drive, the media keys or the DAC, and must never play the file player's sound. The person may be listening to music while you work.
- Capture the app's own windows only (`screencapture -l`), never the whole screen.

## Design rules

- **The units are real gear.** They stay dark in light mode too, with fixed metal and glass colours from `Tokens.swift`. Never hard-code sizes, colours or durations in views.
- **Window chrome stays system:** menus, Settings and sheets. The units themselves have no title bar.
- **Spacing:** `Space` in `UI/Grid.swift`, on a 4 pt grid.
- **Shortcuts:** every action has a menu item and a keyboard shortcut.
- **Language:** panel labels are Spanish, in capitals, like the gear the app imitates.
- **Sound changes never click:** ramps and crossfades, as the EQ and tube stage do.
- **Bit-perfect when off:** with the tubes off and the EQ flat, the sound must pass bit for bit, with tests that prove it.
- **No third-party audio code:** only Apple's frameworks.

## Working style

- For a big change, write a short plan first (goal, what's in, what's out, how it will be checked) and wait for an OK.
- Prove it works before saying it does, and say clearly what you could not check (tests can't hear).
- When a design decision is made, add it to `docs/DESIGN-DECISIONS.md` with what was discarded and why.
- Commit after each working change, with a message that says what the user can now do.

## Optional

The project was started from the template of the *bama* Claude Code plugin. If you have it, its skills (`mac-design`, `layout-grid`, `swift-swiftui`, `build-and-verify`, `test-mac-app`, `app-icon`…) fit this project. Nothing here needs them.
