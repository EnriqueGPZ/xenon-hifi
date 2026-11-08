# XENON Hi-Fi

**A hi-fi stack for the Mac: a CD player, a music file player, a tube preamp and a graphic equalizer, each one built to look and behave like real audio gear.**

*[Leer en español](README.es.md)*

<p align="center">
  <a href="https://github.com/EnriqueGPZ/xenon-hifi/releases/latest"><img src="https://img.shields.io/github/v/release/EnriqueGPZ/xenon-hifi?label=Download%20for%20Mac&style=for-the-badge&logo=apple&color=d4893a" alt="Download for Mac"></a>
  <br><sub>macOS 26 or later · Apple silicon and Intel · free and open source</sub>
</p>

![XENON playing: the needles move, the tubes glow and the equalizer meters follow the music](docs/images/xenon-demo.gif)

XENON is a native macOS app (Swift and SwiftUI) that plays physical CDs from a USB drive and high-resolution music files (FLAC, ALAC, WAV, AIFF, MP3). It shows them on a dot-matrix display, VU meters and a cover screen, and it can colour the sound with a tube stage and a 10-band equalizer.

It was made by someone who does not write code, by talking with an AI coding assistant (Claude Code). [How it was made](docs/HOW-IT-WAS-MADE.md) tells that story and the method behind it.

## The four units

| Unit | What it does |
|---|---|
| **Compact Disc Player CDP-1** | Plays the CD in a USB drive. It recognises the disc by its fingerprint (MusicBrainz disc ID) and fetches the album, artist and song titles once. It reads the disc ahead in big pieces (anti-skip memory), so a slow USB drive never cuts the music. It shows elapsed and remaining time, spectrum bars and analog VU meters. It also has favourites per disc, shuffle, repeat, and a balance knob. |
| **Music File Player MF-1** | Plays the music folder or disk you choose: FLAC, ALAC, WAV, AIFF and MP3. The DAC switches to each song's own sample rate by itself, so a 24-bit/176.4 kHz file reaches it untouched. It has a colour screen for the cover, album, song and folder lists, a selector knob with detents, ★ favourites, and it remembers the song and second where you stopped. |
| **Tube Preamplifier TP-4** | Adds the warmth of a hi-fi triode stage, mostly 2nd harmonic, without changing the loudness. A WARMTH knob sets how much. When off, the sound passes bit for bit. Four photo-real tubes glow with each channel's music. It also has **CROSSFEED** for headphones, with three classic levels: each ear gets a little of the other channel, as with speakers, while the centre stays untouched. |
| **Graphic Equalizer EQ-10** | Ten bands with shelving ends, saved presets, the curve on its display, and peak meters with OVER lights that count clips the way studio meters do. |

The units stack on top of each other in the order the sound flows through them, and they move together as one. All four come up when the app starts.

![The XENON stack: equalizer, tube preamp, file player and CD player with VU meters](docs/images/stack.jpg)

The **Help menu (⌘?)** opens a guide, in Spanish, to every unit, every button and shortcut, and how the sound is treated.

![Spectrum bars](docs/images/stack-spectrum.jpg)

<p align="center">
  <img src="docs/images/tube-preamp.jpg" alt="The tube preamp" width="100%"><br>
  <img src="docs/images/tubes-closeup.jpg" alt="The tubes, close up" width="70%">
</p>

![File player with the song list](docs/images/file-player-list.jpg)

## How the sound flows

```
CD (USB drive) ─┐
                ├─► player ─► tubes + crossfeed ─► equalizer ─► volume ─► your DAC
Music files ────┘   (balance)        (TP-4)           (EQ-10)
```

- **Bit-perfect with the tubes and crossfeed off, the EQ flat and the volume at maximum.** The chain runs at the music's own sample rate, and the app sets the DAC to that rate before it plays. Nothing is resampled on the way.
- **The tube stage** (`Sources/CDPlayerKit/Tube.swift`) uses a biased `tanh` curve, the classic model of a triode near its working point. It is scaled so quiet sound keeps exactly its level and only the colour changes. It runs 4× oversampled at CD rates, so high notes do not fold back as false tones. Switching it on or off fades over 30 ms.
- **Crossfeed** (`Sources/CDPlayerKit/Crossfeed.swift`) feeds each channel the lowpassed *difference* of the other, so the centre comes out bit-identical and what crosses arrives about 0.23 ms late, as around a head.
- **The DAC, exclusively (optional).** In Settings, XENON can hold the DAC while music plays, so no other Mac sound mixes in or changes its rate.
- **Meters show what you hear.** The bars, the needles, the tube glow and the OVER lights all listen after the equalizer.

The tests measure all of this: the harmonics, the level, the folding and the clicks. They are in `Tests/CDPlayerKitTests/`.

**[Sound: the path, the algorithms and the quality](docs/SOUND.md)** explains every step in detail: the anti-skip reader, the DAC rate switching, the tube model and its oversampling, the EQ filters, the volume, the meters, and exactly when the sound is bit-perfect.

## Install

You need a Mac with **macOS 26** (Tahoe) or later, Apple silicon or Intel. A USB CD/DVD drive is optional: the file player works without one.

### Download (easiest)

1. Download **XENON-HiFi-…-macOS.zip** from the [latest release](https://github.com/EnriqueGPZ/xenon-hifi/releases/latest) and double-click it.
2. Drag **CDPlayer.app** to your Applications folder.
3. Open it. The first time, macOS says it can't check the developer, because the app is free and not signed by Apple. Click **Done**, then go to **System Settings ▸ Privacy & Security**, scroll down and click **Open Anyway** next to CDPlayer. You only do this once.

### Build it yourself

You also need **Xcode 26**, or just its Command Line Tools (`xcode-select --install`), with Swift 6.2. Then:

```bash
git clone https://github.com/EnriqueGPZ/xenon-hifi.git
cd xenon-hifi
./build.sh --open
```

`build.sh` compiles the app, signs it and installs it as `~/Applications/CDPlayer.app`, and `--open` starts it.

- **Signing.** It uses your Apple Development certificate if you have one. Without one, it signs "ad hoc", which works, but macOS may ask again for permission to read the CD after each new build. To avoid that, make a code-signing certificate in Keychain Access (Certificate Assistant ▸ Create a Certificate ▸ Code Signing) and pass its name: `SIGN_IDENTITY="My Name" ./build.sh`.
- **Bundle ID.** The default is `io.github.enriquegpz.xenon`. Change it with `BUNDLE_ID=com.you.xenon ./build.sh`.

### Build it with your AI

The repository includes `CLAUDE.md` and `AGENTS.md` with everything an AI coding assistant (Claude Code, Codex, Cursor…) needs: the layout, how to build, the tests, the snapshot checks and the design rules. Open the folder with your assistant and ask it to *"build and install the app"*, or to change something.

## Use

- **CD player:** put a CD in. ⏯ plays, DISPLAY changes the screen (time, remaining, bars, VU), and the menus list every shortcut.
- **More units:** the *Reproducción* and *Archivos* menus open the file player (⌥⌘M), the tube preamp (⌥⌘V) and the equalizer (⌥⌘E).
- **File player:** press MÚSICA and choose the disk or folder with your music. LISTA goes through cover, albums, songs and folders, and the SELECCIÓN knob moves through them.
- **Tubes:** V turns them on or off. ⌥⌘↑ and ⌥⌘↓ change the warmth.
- **Crossfeed:** C turns it on or off, ⇧C goes to the next level (SUAVE, MEDIO, FUERTE). For headphones only.
- **File player lists:** ↑ and ↓ move through albums and songs after you click the file player.
- **Help:** ⌘? opens the guide.

The interface is in Spanish, like the panel of the gear it imitates.

## Check your changes

```bash
swift test --scratch-path ~/Library/Developer/CDPlayer/test-build   # logic and sound tests
tools/selftest.sh                                                   # the app's real functions, on a test store
tools/snap.sh                                                       # light/dark snapshots in /tmp/CDPlayer-shots
tools/grid-lint.sh                                                  # 4-pt grid check
```

Tests and snapshots use a demo disc and library and never touch your saved settings, your music or your DAC.

## What it does not do

- No streaming services, internet radio, or cover art from the internet.
- No ripping CDs to files.
- The download is not notarized by Apple, so macOS asks you to confirm it once (see Install). Building it yourself avoids that.

## Credits

- Album and song titles: [MusicBrainz](https://musicbrainz.org) (open music database).
- The tube pictures are AI-generated (nano-banana via kie.ai) and then split into a cold layer and a light layer by `tools/tube_layers.py`.
- The look takes its inspiration from Japanese hi-fi gear of the 90s and 2000s. XENON is a made-up brand.
- Built with [Claude Code](https://claude.com/claude-code).

## License

[MIT](LICENSE): use it, change it, share it, keeping the notice.
