# CDPlayer stories

Snapshot page for every story: `player` (`tools/snap.sh`). The real disc
used for manual checks: "The Best Of Sade" (16 tracks, disc ID
`OKHpuyKx9Fy7jvHkgynIA3faxgI-`).

## M1 Play a real CD

### S-001 See the inserted CD on the display
As the user, I put a CD in the USB drive and the display shows it.
Acceptance:
- [unit] The table of contents (`.TOC.plist`) gives the MusicBrainz disc ID and each track's length.
- [manual] With a CD in, the app opens showing "1 / 16", the first title, and the disc's total time.
- [manual] Inserting a CD while the app is open loads it without a restart.
- [snap] With no disc, the display reads "SIN DISCO" and "Introduce un CD".
Status: done

### S-002 Play, pause, and stop the CD
As the user, I press play and hear the disc; pause holds the position; stop goes back to 00:00.
Depends: S-001
Acceptance:
- [manual] Sound comes out within a second of pressing play; the time counts up.
- [self] play/pause/stop change the state; stop resets the time.
- [manual] Space bar plays and pauses.
Status: done

### S-003 Move through the disc
As the user, I skip to the next or previous track and fast-forward or rewind inside a track.
Depends: S-002
Acceptance:
- [self] Next and previous change the track; previous after 3 s restarts the track.
- [manual] Fast-forward and rewind jump 8 s and the sound follows.
- [manual] At the end of a track the next one starts by itself; at the end of the disc it stops (or starts over with repeat).
Status: done

### S-004 Eject
As the user, I press eject and the disc comes out; with no disc, eject opens the tray.
Acceptance:
- [manual] Eject stops the sound and the drive ejects the CD; the display shows "SIN DISCO".
Status: doing (built; eject not tried on the real drive yet)

### S-005 Change the volume with the knob
As the user, I drag the knob up or down and the sound follows; the app remembers the level.
Acceptance:
- [manual] Dragging up raises the volume, down lowers it; the level survives a restart.
- [manual] The arrow keys turn the knob while it has focus.
Status: doing (built; drag and arrow keys not tried by hand yet)

### S-006 See real titles from MusicBrainz
As the user, I see the album, artist, and track titles, looked up once and kept offline.
Depends: S-001
Acceptance:
- [unit] A MusicBrainz reply gives album, artist, year, and every track title.
- [manual] The first time a disc goes in, the display shows "Buscando títulos…" and then the real titles.
- [manual] Without internet, the titles macOS gives the tracks are used instead.
- [manual] The second time the same disc goes in, no lookup happens.
Status: done

## M2 Favorites and modes

### S-007 Mark a favorite track
As the user, I press the star while a track plays and it stays a favorite for that disc.
Acceptance:
- [self] Starring marks the current track; it is still a favorite after ejecting and reinserting.
Status: done

### S-008 Play only the favorites
As the user, I turn on "solo favoritas" and only the starred tracks play.
Depends: S-007
Acceptance:
- [self] With favorites-only on, next skips tracks that are not starred.
- [manual] With no favorites, the display says so instead of playing.
Status: done

### S-009 Shuffle and repeat
As the user, I turn on shuffle or repeat and the order follows; their lights show on the display.
Acceptance:
- [self] With repeat on, next after the last track goes to the first.
- [snap] Active modes light up on the display.
Status: done

### S-010 Change what the display shows
As the user, I press display to cycle elapsed time, remaining time, and the disc's total.
Acceptance:
- [self] Each press moves to the next mode and wraps around.
Status: done

## M3 Mac touches

### S-011 Control it from the keyboard and the media keys
As the user, I use the menu shortcuts and the Mac's play/pause/next keys, and see the track in Control Center.
Acceptance:
- [manual] The "Reproducción" menu lists every action with its shortcut.
- [manual] The keyboard's media keys work while another app is in front.
Status: doing (menu done; media keys not tried by hand yet)

### S-012 Long titles scroll
As the user, I can read a long title: it scrolls across the display like a real player.
Acceptance:
- [manual] A title wider than the display scrolls slowly and loops; a short one stays still.
Status: doing (built; not seen scrolling on a real long title yet)

## Dropped
- Ripping tracks to files: not in version one (brief).
- Local audio files: CD only (brief).
- Program order, equalizer, number pad: not in version one (brief).
- Accounts, sync, sharing: one user, one Mac.
