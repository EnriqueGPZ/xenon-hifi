# Sound: the path, the algorithms, and the quality

*[Leer en español](SONIDO.md)*

This page explains what XENON does to the sound, step by step, and how each claim is checked. Short version: **with the tubes and crossfeed off, the EQ flat and the volume at maximum, the music reaches your DAC exactly as it is on the disc or in the file, at its own sample rate.** Everything the app adds is optional, and the tests measure it.

## The path

```
CD (.aiff from macOS) ─┐                                                     ┌─► meters
                       ├─► reader ─► player ─► tubes + crossfeed ─► equalizer ─► mixer (volume) ─► Core Audio ─► DAC
FLAC/ALAC/WAV/AIFF/MP3 ┘   (anti-skip) (balance)      (TP-4)            (EQ-10)
```

Inside, everything runs as **32-bit floating point**, the native format of macOS audio. A 32-bit float holds every 16-bit and 24-bit sample exactly, so carrying the music this way loses nothing.

## 1. Reading the music

**CD.** For an audio CD, macOS shows each track as an `.aiff` file with the exact samples from the disc, at 44.1 kHz and 16 bits. XENON reads those files directly with its own small AIFF reader (`CDPlayerKit/CDTrackReader.swift`), not through a player that guesses or converts.

**Anti-skip memory.** USB CD drives are fast with big reads and very slow with many small ones. The app reads the disc **2 seconds at a time** (half a second for the very first read, so play starts quickly) and keeps about **12 seconds ready ahead** of what you hear. Nothing else reads the disc while it plays: the meters listen to the sound that is already playing. If a read fails (a scratch, a loose cable), it retries 3 times. If it still fails, everything already read plays out, and the player stops at the exact point with "ERROR DE LECTURA".

**Files.** FLAC, ALAC, WAV, AIFF and MP3 are decoded by **the Mac's own decoders** (`CDPlayerKit/FileTrackReader.swift`), at the file's own sample rate and without resampling. 16- and 24-bit FLAC come out identical to their source, and the tests check it. Mono files play on both channels.

## 2. The DAC at the music's own rate

Before each song plays, the app sets your DAC to that song's sample rate (`Player/OutputDevice.swift`): 44.1 kHz for a CD, 96 kHz for a 96 kHz file, and so on. Without this, macOS would silently resample everything to whatever rate the DAC was set to. Between songs of different rates there's a short silence while the DAC switches; between songs of the same rate there's no gap.

If the DAC changes rate, is unplugged or comes back, macOS restarts the audio engine and drops what was queued. XENON then reads the music again from the exact second it was at.

**Holding the DAC (optional).** With *Settings ▸ Sonido ▸ Usar el DAC en exclusiva*, XENON takes the DAC for itself while music plays (Core Audio's *hog mode*, `ExclusiveOutput` in `Player/OutputDevice.swift`). No alert, video or other app can mix into the music or change the DAC's rate. macOS sends the other sounds to another output (the Mac's speakers) until you pause or stop; then the DAC is free again, and if the app quits, macOS frees it by itself. Taking the DAC makes macOS move the system's default output, and AVAudioEngine follows the default output a moment later, so XENON waits about 0.3 s and then pins its engine to the DAC: that is the short pause when you press play. It's off by default, and it has been tested with one USB DAC; it uses a standard macOS feature, so other DACs should behave the same.

## 3. Balance

It works like an amplifier's balance: at the centre both channels stay at full level, and turning it lowers only the other channel. At the centre it is a pass-through.

## 4. The tube stage (TP-4)

A software model of **one hi-fi triode stage**, the kind of ECC88/12AU7 stage found in a valve preamp (`CDPlayerKit/Tube.swift`).

- **Why it sounds warm.** A triode amplifies one half of the wave a little more than the other. That uneven bend adds mostly **even harmonics**, above all the 2nd (one octave up). The ear hears these as warmth and body, not as distortion.
- **The curve.** A biased hyperbolic tangent, `tanh(u + b) − tanh(b)`, the classic model of a triode near its working point. It is computed as `tanh(u) / (1 + t·tanh(u))` with `t = tanh(b) = 0.5`, which is the same curve but numerically cleaner. It is scaled to **gain 1 for quiet sound**, so the loudness stays the same and only the colour changes.
- **WARMTH** sets the drive. At 100 %, a tone at −6 dBFS gets about **4 % of 2nd harmonic (−28 dB)**, with the 3rd harmonic at least 20 dB below it. At 50 %, it's about half. Quiet passages get much less, as in a real stage.
- **Oversampling, so nothing false appears.** A curve creates new, higher harmonics. At CD rate, those above 22 kHz would fold back into the audible band as false tones (aliasing). So the stage runs at **4× the rate up to 48 kHz, 2× up to 96 kHz, and 1× above**. The filters are polyphase windowed-sinc filters (Kaiser window, β 8.96, 64 taps per phase). The cost is about 1.5 ms of delay.
- **DC filter.** The uneven bend also adds a small steady offset. Only the part the curve *adds* goes through a 2 Hz filter that removes it; the music itself is not filtered there.
- **Off means off.** When switched off, the stage returns the input untouched, bit for bit. Switching on or off crossfades over 30 ms, so it never clicks.
- **The glow** follows each channel's RMS level between −40 and −10 dBFS, and the tubes take 4 seconds to warm up.

What the tests measure (`Tests/CDPlayerKitTests/TubeTests.swift`):

| Check | Result required |
|---|---|
| Off | bit-identical to the input |
| Level of quiet sound | within 0.05 dB |
| Level of music | within 0.3 dB |
| 2nd harmonic, −6 dBFS tone, WARMTH 100 % | between −32 and −24 dB |
| 3rd harmonic | more than 20 dB below the 2nd |
| A 14.1 kHz tone at 44.1 kHz: false tones from folding | below −80 dB |
| An 18 kHz tone | level within 0.1 dB |
| Switching on/off | no clicks |

On a real 24-bit/176.4 kHz album at 100 % warmth, the average level changed by about 0.01 dB.

### Crossfeed (TP-4), for headphones

With speakers, each ear hears both: the left speaker reaches the right ear too, around the head, a fraction of a millisecond later, softer and without its highs. On headphones each ear hears only its own channel, so the music sits inside the head, and anything mixed to one side only (common on 1960s stereo records) sits glued to one ear. CROSSFEED gives each ear a little of the other channel, the way the head would (`CDPlayerKit/Crossfeed.swift`):

```
left  = L + g · (low(R) − low(L))
right = R + g · (low(L) − low(R))
```

- `low` is a gentle lowpass (6 dB/octave at 650–700 Hz): the highs barely cross, and its phase delays what crosses by `1/(2π·cutoff)`, about **0.23 ms** in the bass, close to the time sound takes around the head. No separate delay is needed.
- Only the **difference** between the channels crosses, so whatever is the same on both (a voice in the centre) comes out **bit-identical**: no louder, no bass boost. In the bass, a sound mixed fully to one side reaches the other ear `feed` dB softer than its own: `g = a/(1+a)` with `a = 10^(−feed/20)`.
- Three classic levels: **SUAVE** (Jan Meier, 650 Hz, 9.5 dB), **MEDIO** (Chu Moy, 700 Hz, 6 dB), **FUERTE** (Bauer, 700 Hz, 4.5 dB). Off by default.
- It sits in the preamp's audio link, after the tubes. The equalizer treats both channels alike, so this sounds the same as putting it last. Off, it's untouched; switching or changing level glides over 30 ms.
- Measured in the tests: off is bit-identical, the centre is bit-identical, the far ear is `feed` dB down (±0.3 dB) in the bass, a 10 kHz tone crosses more than 20 dB down, the delay is 0.23 ms, switching on mid-song doesn't click, and it works at 192 kHz.

## 5. The equalizer (EQ-10)

- **Ten bands an octave apart** (31 Hz to 16 kHz, the ISO centres), ±12 dB in 0.5 dB steps, plus a LEVEL control from 0 to −12 dB to make room for boosts.
- **The filters** are Apple's `AVAudioUnitEQ`: minimum-phase peaking filters (biquads), one octave wide. Measured against the *Audio EQ Cookbook* (the standard reference for these filters), the curve matches within **±0.01 dB**. The two end bands can be **shelves** (bass at 63 Hz, treble at 8 kHz, standard slope S = 1), measured within 0.03 dB.
- **Flat is bit-perfect.** With every band at 0 dB, the output is bit-identical to the input. After half a second flat, the EQ is bypassed altogether.
- **No clicks.** Every change goes through a ramp of 6 steps, about a tenth of a second. Switching a band between bell and shelf first brings it to 0 dB, switches, and goes back.
- **Not chosen:** linear-phase filters. They cause pre-echo and delay, and nothing showed they sound better here.

## 6. Volume

The volume knob is **digital**: it multiplies the samples, in 32-bit float, after the EQ. Below maximum, the samples change; that's what any digital volume does. For the cleanest signal, leave the knob at maximum and the Mac's own volume for the DAC at maximum, and set the loudness on your DAC or amplifier.

## 7. The meters show what you hear

The bars, the VU needles, the tube glow and the OVER lights all listen **after the equalizer**. The peak meters and OVER listen where the sound reaches the DAC, after balance and volume.

- **Spectrum bars.** A 2048-point FFT (Hann window, Apple's Accelerate), split into 24 bands spaced evenly in octaves from 40 Hz to 16 kHz. There is a small lift toward the treble so the high bars move too, as on a real analyzer.
- **VU meters.** RMS level, with **0 VU = −16 dBFS**. The needle has a real VU's ballistics, reaching 99 % of a step in 0.3 s. The scale is printed in voltage, like a real meter.
- **OVER.** It counts *hits*, like studio meters: one run of samples over full scale counts as 1, even across blocks. The light stays on for 2 seconds. It doesn't count *true peak* (between samples), which would light up on loud masters even with a flat EQ.

## What is bit-perfect, exactly

With **the tubes and crossfeed off, the EQ flat, the balance centred and the volume at maximum**, every stage in the app is a pass-through, and the tests prove each one. The music leaves XENON exactly as it came in, at its own rate. From there, Core Audio hands it to your DAC in the DAC's own format.

Known limit: 32-bit *integer* WAV/AIFF files (very rare) are not bit-identical, because the engine works in 32-bit float.

## What makes the biggest difference

The app keeps the signal clean, but you hear your **DAC, amplifier and headphones or speakers**. XENON gives them the untouched music at its own rate, and it adds colour only when you ask for it.
