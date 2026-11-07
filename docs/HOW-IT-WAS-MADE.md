# How it was made

*[Leer en español](COMO-SE-HIZO.md)*

XENON was made by someone who **does not write code**. They described what they wanted, sent photos of gear they liked, listened to the result, and said what was wrong. The code, the tests and the checks were written by an AI coding assistant ([Claude Code](https://claude.com/claude-code)) working in this folder on a Mac.

From the empty template to the four units took **two working sessions over two days**, in 31 commits.

## The idea

It started with a USB CD drive on a Mac mini and a wish: *play my CDs like on a real hi-fi CD player*. The person sent a photo of a Denon CD player as the reference. The first brief ([docs/BRIEF.md](BRIEF.md)) asked for just that: one window that looks like the front of a CD player, a dot-matrix display, round metal buttons, a volume knob, and favourite songs per disc. Ripping CDs, music files and an equalizer were explicitly left out of version one.

Then the app kept growing, one wish at a time:

| When | What was asked | What it became |
|---|---|---|
| Day 1 | "Play my CD, make it look like the Denon" | The CD player, its dot display, MusicBrainz titles |
| Day 1 | "Show the sound" | Spectrum bars, then analog VU meters with real needle inertia |
| Day 1 | "The music cuts out" | Anti-skip memory: read the disc 2 seconds at a time, 12 seconds ahead |
| Day 1 | "Left/right balance" | A balance knob that clicks at the centre |
| Day 2 | "An equalizer, as a second unit" | The EQ-10, stacked on top, with peak meters and OVER lights |
| Day 2 | "Like an audiophile streamer, but for my FLAC and MP3 disks" | The file player, with automatic DAC rate switching |
| Day 2 | "CDPLAYER is ugly, I want a shiny badge" | The XENON chrome logo with a moving glint |
| Day 2 | "The warmth of hi-fi tubes, and tubes that glow with the sound" | The tube preamp, first drawn, then with photo-real tubes |

## The method

The same short loop, again and again:

1. **A wish, in plain words.** "The knob is too sensitive", "it's silent when the next song is higher quality", "the tubes don't look real".
2. **For anything big, a short plan first:** the goal, what goes in, what stays out, and how it will be checked. Nothing is built until the person says OK. Small things are just done.
3. **Questions only about the product, never about code.** "Four tubes or six?", "where in the stack?", "favourites as a filter or as their own album?" The assistant decides the technical details itself.
4. **Build in small steps that can be checked.**
5. **Prove it works before saying it does.** Every change goes through:
   - **unit tests** of the logic and the sound (`swift test`): the tube stage, for example, is measured for harmonics, level, aliasing and clicks;
   - **a self-test** that drives the real app on a throw-away store (`tools/selftest.sh`);
   - **snapshots** in light and dark (`tools/snap.sh`), which the assistant looks at itself;
   - **a 4-point grid check** of the layout (`tools/grid-lint.sh`).
6. **Say honestly what was not checked.** Tests cannot hear. Each step ends with a list like *"not tried by ear: the gap between songs, unplugging the DAC while it plays"*. Then the human tries those things with real discs, the real DAC and their ears.
7. **Write it down.** The project kept three notes (not published, because they are personal):
   - a **log** of what was asked and how it was solved;
   - a **status** file: what is done, what is still to be checked by hand, what is still to be decided;
   - a **decisions** file, where every decision also records **what was discarded and why**, so a later session does not propose it again.

   The design decisions are summarised in [DESIGN-DECISIONS.md](DESIGN-DECISIONS.md).

Bigger features (the file player, a full review of the sound engine) were also checked by separate **review agents**: a second AI pass that only looks for bugs. Their findings were fixed, and then reviewed again.

## Things that were hard, and how they were solved

- **The USB drive cut the music.** Small reads, many times a second, were too much for the drive. The fix: read the disc in big 2-second pieces, keep 12 seconds ready ahead, and let nothing else read the disc at the same time. The bars and meters now listen to the sound that is already playing, never to the disc.
- **A CD whose name starts with a dot** (like *"...But Seriously"*) was not found when the app opened, because macOS treats it as a hidden volume. The drive search must not skip hidden volumes.
- **macOS asked again for permission to read the CD after every build.** An ad-hoc signature looks like a new app each time. The fix: sign with a certificate that stays the same.
- **Silence when the next song had a higher sample rate.** Changing the DAC's rate makes macOS restart the audio engine, and the player lost what it had queued. Now the app reads again from the exact second it was at.
- **Tubes that looked drawn.** Vector shapes never looked like glass. Four photo-real pictures were generated with an image AI. The human chose two of them. A script turned the background to pure black and split the amber filament light into its own layer. In the app, the light layer rises and falls with the music over the cold tube.

## What the human did that the AI could not

- Choose what the app should be, and say no.
- Listen. Tests can measure the 2nd harmonic of the tube stage, but only a person can say whether it sounds good.
- Try real hardware: scratched discs, double CDs, unplugging the DAC while it plays.
- Notice what looked wrong ("the tubes don't look real") and what felt wrong ("the knob jumps several albums at once").

## Doing the same

You don't need to know how to code. You need to know what you want, to try what you get, and to say clearly what is wrong. Ask for a plan before big changes, ask for proof before believing "it works", and keep a short record of every decision and of what you discarded.

To change this app, open the folder with your AI assistant. `CLAUDE.md` / `AGENTS.md` tell it how the project works.
