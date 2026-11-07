# Design decisions

Each decision also notes **what was discarded and why**, so nobody (human or AI) proposes it again without a new reason. The first section lists things that work in a particular way on purpose: changing them breaks something that was measured or seen.

## Do not change

- **Read the CD ahead in big pieces (2 s), from one place only** (`Player/Playback.swift`, `CDPlayerKit/CDTrackReader.swift`). If the disc is read in small pieces (as `AVAudioPlayer` does), or two things read it at once, a USB drive can't keep up and the music cuts out.
- **Bars and meters come from the sound that is already playing, never from the disc.** If they read the disc, the cuts come back.
- **Find drives without `.skipHiddenVolumes`** (`Player/CDDrive.swift`). With it, a CD whose name starts with a dot (*"...But Seriously"*) is not found at launch.
- **Test mode (`APP_STORE`) never touches the drive, the media keys, the DAC, or the file player's sound.** Otherwise tests and snapshots would stop, eject or change what the person is listening to.
- **Snapshots capture the app's own windows, never the whole screen.** A whole-screen capture picks up whatever else is open.
- **VU meters: the dial is drawn once, only the needle moves** (`UI/VUMetersView.swift`). Redrawing everything took CPU from 15 % to 28 %.
- **Equalizer changes always go through the ramp (`EQRamp`), and the unit is bypassed only after half a second flat.** Switching it off at once, or inserting an empty filter mid-sound, clicks (measured).
- **Bell ↔ shelf changes only through `EQDriver`** (band to 0 dB, half a second, switch, back). Switching the shape at once with music gives an audible spike (measured).
- **Bars, VU, peak meters and tube glow listen right after the equalizer.** Before it they would show something other than what you hear, and OVER would miss clips.
- **The DAC is set to the rate of what is playing** (`Player/OutputDevice.swift`, on Play and on reconnect), never in test mode. Without it, macOS resamples silently.
- **When macOS restarts the audio engine** (DAC rate change, unplug, replug), **read the music again from the second it was at** (`Playback.resumeAfterDeviceChange` → `restart`). Restarting only the node leaves silence, because the restart drops what was queued.

## Sound

- **Plays what macOS mounts for an audio CD** (`.aiff` files + `.TOC.plist`). Discarded: talking to the drive directly (far more complex and fragile, and macOS already gives the exact audio).
- **AVAudioEngine with anti-skip memory** (2 s reads, about 12 s ready). Discarded: `AVAudioPlayer` (small reads, too slow on USB drives) and bars from the volume alone (they can't split bass and treble).
- **Read errors:** 3 retries; if it still fails, play everything already read, stop at the exact point with "ERROR DE LECTURA", and Play continues from there. Discarded: silently skipping to the next track, and stopping at once (that threw away up to 12 s of good music).
- **Each song plays at its own sample rate**: the chain and the DAC switch by themselves, CD included (44.1 kHz). There's a short silence between songs of different rates while the DAC switches, none between equal ones. Discarded: converting everything to one fixed rate.
- **No third-party decoders**, only the Mac's own. 16- and 24-bit FLAC come out identical (checked). Discarded: external libraries. Known limit: 32-bit integer WAV/AIFF are not bit-identical (the engine works in floating point); they are very rare.
- **One audio engine per unit, only one plays at a time** (Play on one pauses the other). EQ, OVER, volume and balance are shared; media keys follow the last one that played. Discarded: one shared engine (it would mean rewriting the CD one).
- **No compensation for the DAC's output delay** in the clock and meters: about 25 ms measured, under what is perceptible (~45 ms), and compensating it risks gaps between tracks.
- **Balance works like an amplifier's:** the centre leaves both sides whole, turning lowers only the other side.

## Equalizer

- **Apple's `AVAudioUnitEQ`, 10 one-octave bands (31 Hz–16 kHz), ±12 dB in 0.5 dB steps, LEVEL 0 to −12 dB.** Measured: the same curve as the Audio EQ Cookbook (±0.01 dB), and bit-identical when flat. Discarded: own biquads with vDSP (same curve, more code, no proof it sounds better), linear-phase filters (pre-echo and delay), and 5 bands.
- **The 31 and 16K bands can be shelves** (SHELF switch): bass at 63 Hz, treble at 8 kHz, Apple's standard slope. Discarded: a gentler slope (Apple doesn't allow it), shelves on middle bands, and a knob to move the shelf frequency (not missed once listened to).
- **OVER and a peak meter per channel, measured where the sound reaches the DAC.** The counter counts *hits*: one run of clipped samples = 1, like studio meters. Discarded: counting samples (huge meaningless numbers) and true peak (it would light up with loud masters even with a flat EQ).

## Tube preamp

- **Written into the app:** a hi-fi triode stage, mostly 2nd harmonic, matched loudness, off by default and bit-perfect when off. Discarded: Faust/Guitarix, SwankyAmp and chowdsp_wdf (made for guitar or in another language, and against "no third-party code"), choosing tube models, a power stage, and hum.
- **Before the EQ, in the sound and in the stack.** Four tubes visible, the glow follows each channel. Discarded: the tubes at the very top, and six tubes.
- **Photo-real tubes from AI-generated images** (a cold layer + a light layer). Discarded: polishing the vector drawing (it still looked like an illustration) and 3D models in Blender (a lot of work for little difference).

## Look and use

- **No title bar: the unit is the window, POWER quits.** Discarded: a normal Mac window (it broke the illusion of real gear).
- **The units stay dark in light mode too**, with fixed metal and glass colours. That's the look of real gear, on purpose; window chrome, menus and Settings stay system.
- **The units stack in the order the sound flows** (CD at the bottom, files, tubes, EQ at the top) and move together as child windows. Discarded: loose windows.
- **Own 5×7 dot font** for the VFD look; accents are shown without the mark, like real gear. Discarded: a computer font.
- **Denon-style buttons:** turned metal, symbol printed above, not on the button. Small, quiet panel labels.
- **VU meters as a DISPLAY mode** (elapsed → remaining → bars → VU), not fixed on the front, so the panel stays clean. Own drawing, no copied brand. 0 VU = −16 dBFS average; the needle has a real VU's ~0.3 s inertia.
- **The file player has a colour screen only for the cover**; the rest matches the other units. Discarded: a dot display like the CD.
- **Folders of loose songs become an album named after the folder**, and loose songs inside an album folder join that album. Discarded: trusting only the album tag (it gave dozens of one-song albums).
- **LISTA cycles through four screens** (cover, albums, songs, folders). FOLDERS shows only the first level. Discarded: navigating sub-folders level by level.
- **File-player favourites are a "★ Favoritas" album** at the top of ALBUMS. They are stored on the Mac by relative path, never in the files' tags.
- **The SELECCIÓN knob moves by detents** (one row per 10 pt of turn). Discarded: a knob that spreads the whole list over its travel (too sensitive).
- **Holding ⏮/⏭ seeks 5 s**, and clicking the time line jumps. Discarded: separate ◀◀ ▶▶ buttons (no room).
- **At launch, the file player returns to the song and second where it stopped, paused.** It never starts playing by itself.
- **XENON chrome badge with a moving glint** (every 25 s and following the mouse). Discarded: an engraved plate, gold, a lit emblem.
- **Signing with a stable certificate.** With ad-hoc signing, macOS sees a new app every build and asks again for permission to read the CD.

## Out of scope (for now)

Ripping CDs to files, streaming services, internet radio, cover art from the internet, and a PROGRAM mode.
