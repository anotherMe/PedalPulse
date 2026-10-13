# The variation library

## What this folder is

The sound of PedalPulse is split into a small core and this library. The library
has three folders:

- `progressions/` holds the chords the whole band follows: the bass, the pad,
  the arp and the lead all play the same chord at the same time.
- `melodies/` holds the arpeggio and the lead.
- `palettes/` holds the sounds (which instrument plays which part).

Each `.scd` file in a folder is one named variation. Its file name without
`.scd` is its name everywhere: in the post window, over OSC, and in the app's
dropdowns. `classic.scd` in each folder is the original sound,
so picking `classic` always brings it back. Right now the library holds eight
progressions:

- `classic`: the original A-minor groove, one chord (Am) in every bar.
- `anthem`: Am F C G, a new chord every bar.
- `rocker`: Am G F G.
- `lift`: Am F G G.
- `return`: Am C G F.
- `deep`: Am Am F G, with two bars on each chord, so the changes are slower.
- `melancholy`: Am Em F Dm.
- `drama`: Am Dm F E, with a bright major E at the end that leads back to Am.

It also holds `melodies/classic`, `melodies/classic_lead` (the classic arp plus
a faint lead one octave up) and `melodies/classic_lead_loud` (the same lead, but
as loud as the arp so it is easy to hear).

The `palettes/` folder holds seven sound worlds. Each one changes the voices of
the whole band (drums, bass, arp, pad and lead):

- `classic`: the original sounds.
- `supersaw`: a huge, wide wall of detuned saw waves in the pad and the lead, a
  bright saw arp and a saw bass with a sub underneath.
- `acid`: a squelchy 303-style bass that rolls in fast sixteenths, a bright
  resonant arp and a sharp lead.
- `dark`: a deep, long kick, a gritty low bass rolling in sixteenths and a narrow,
  murky arp and pad.
- `pluck`: bright, digital plucked sounds, a bass that pops up and down an octave
  and a tiny, crisp hi-hat.
- `warm`: soft, round and old-analog: triangle and sine waves with a gentle
  wobble, nothing sharp.
- `air`: glassy bells for the arp and the lead, a shimmering pad of pure sine
  waves and a deep, clean sine bass.

`dark` has its own deep kick and `pluck` its own crisp hat; the other drums in
every palette are classic's. Every file also has a `desc` line at the top that
says what it sounds like.

## The one rule

**Never edit, rename or delete a file after it has been committed. Add a new
file instead.** For example, if `classic_lead` is a little loud, do not change
it: add `classic_lead_soft.scd` next to it. That way every earlier variation
stays selectable and sounds exactly as it did. `bash scripts/check.sh` fails
when a committed file was changed.

A name is 1 to 64 characters from lowercase `a-z`, `0-9` and `_`. It does not
start with `_`, and `auto` is reserved (it means "let the engine choose"), as are
`parent` and `proto` (they are special slots of the SuperCollider Event that holds
the library). For
progressions and palettes, `auto` lets the engine rotate by itself (see
"Progressions and Auto" and "Palettes and Auto" below). For melodies it still
plays classic until their own phase arrives.

The `_template.scd` file in each folder is an example for writing a new file.
Copy it to a new name and change the copy. A `_template.scd` can never be
selected.

## Pick a variation from the app

The PedalPulse window has a column on the right with three dropdowns: Palette,
Progression and Melody. Each one starts on Auto. When you open a dropdown it
lists Auto, then `classic`, then every other file in its folder from A to Z,
by file name without `.scd`. Files whose names start with `_` (such as
`_template`) never appear.

A name longer than 20 characters is cut short on the closed dropdown, but it
always shows in full when the dropdown is open.

Opening a dropdown reads the folder again, so a file you just added is there to
pick with no restart. A file you removed is gone from the list the next time
you open it.

Picking a name sends it to the engine, which prints a line in the SuperCollider
post window. A melody or a palette switches at the next bar line. A progression
switches at the end of the progression that is playing (at most 8 bars with the
files that ship, about 15 seconds at 128 BPM) and then stays on the new one.
At every progression change the post window prints
`PedalPulse: progression <name>: <chords>`; use that name when you describe what
you heard. A palette switches at the next bar line and then stays; at every
palette change the post window prints `PedalPulse: palette <name>: <description>`,
so use that name too.

Picking the name that is already selected does nothing, unless the last send of
it failed: then picking it again sends it again. To hear a file again
after you changed it, pick another name and then pick it back, or use the
one-liner below.

The app always starts on Auto; it does not remember what you picked last time.

## Try a variation while the music plays

Open a terminal in the PedalPulse folder, with the engine running, and paste:

```
.venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/melody', 'classic_lead')"
```

That switches the melody to `classic_lead` at the next bar line, without
stopping the music. To go back, send the same line with `'classic'`:

```
.venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/melody', 'classic')"
```

The other two categories work the same way, with their own address:

- Progression: `send_message('/pp/progression', 'classic')`
- Palette: `send_message('/pp/palette', 'classic')`
- Any of the three with `'auto'` lets the engine choose: progressions and
  palettes rotate by themselves, melodies still play classic.

Sending the same name again re-reads the file from disk, so you can save a
change to a new file and hear it at the next bar line without restarting.

A broken file is refused. The post window shows
`PedalPulse ERROR: library file <path> ...` and the music keeps playing what it
was playing. If a file works on load but fails while playing, that bar plays the
classic part, and after 3 failed bars the category goes back to classic.

## Progressions and Auto

A progression is a list of chords that bass, pad, arp and lead all follow. It
always changes at the end of its own cycle (the whole list of chords), never in
the middle, so a pick can take a few seconds to be heard.

When Progression is on Auto:

- After a Start (or a fresh engine) Auto plays `classic` first.
- If you pick Auto in the middle of a ride, it keeps the progression that is
  playing at that moment, for one full stay, and only then starts rotating.
- It then changes progression every 2 to 3 minutes, always at the end of a cycle.
- It never picks the progression that is playing, and never one of the last two
  it played.
- A progression file you add while the engine runs joins the rotation by itself.
- The post window prints `PedalPulse: progression auto seed <n>` once when the
  engine starts. The same seed on a freshly started SuperCollider gives the same
  order, so a ride you liked can be replayed.
- Stop and then Start begins again on `classic`, then picks differently from the
  last run: the draws continue until SuperCollider is restarted.

You can always see what Auto chose in the post window: it prints
`PedalPulse: progression <name>: <chords>` at every change.

## Write a new progression

Copy `progressions/_template.scd` to a new name and change the copy. A
progression is only chord data:

- `chords` is a list of chords. Each chord has a `root` (semitones above A: A is
  0, C 3, D 5, E 7, F 8, G 10) and a `quality`, `\min` or `\maj`. For any other
  chord give `intervals` instead, such as `[0, 3, 7, 10]`.
- `bars` on a chord says how many bars it lasts, or `barsPerChord` on the whole
  file sets it for every chord.
- The whole cycle is at most 16 bars. 8 bars or less keeps a pick quick, because
  a new pick waits for the end of the cycle that is playing.
- The engine always plays in A, so a file only says which chord, never which key.
- Bass, pad, arp and lead follow the chords by themselves. If you want something
  special, `bass` and `pad` generators in the file replace the core's part. A
  `bass` generator is heard only while the `classic` palette plays; every other
  palette plays its own bass style on your chords (see "Bass styles").

## Palettes and Auto

A palette is a whole set of sounds. When Palette is on Auto the engine changes it
by itself, and it changes it on the same bar where a new progression starts, so
the sound and the chords always change together.

- **The first palette.** Auto draws a random palette as soon as the palette files
  are loaded. It is never `classic` first and never the palette that was playing.
  It lands at the start of the next round of chords. After a Start that is the very
  first bar, which is also a progression change. If you pick Auto while the music
  plays (the app does this when it opens), it is the next round start, so the new
  palette comes within a few bars instead of after minutes.
- **How long a palette stays.** Each palette is held for 80 to 128 bars. A bar is
  4 beats, so minutes = bars x 4 / BPM: that is 2.9 to 5.7 minutes at 90 to 110
  BPM (shorter at a higher BPM). After the hold the palette changes at the next
  progression change. Waiting for that adds about 25 bars on average and at most
  64. With Progression on Auto a palette therefore plays about 4.7 to 5.7 minutes
  on average at 90 to 110 BPM, and any single palette anywhere from about 3 to 8.5
  minutes.
- **With a progression picked by name.** The palette changes at the end of that
  progression's round once the hold is over: about 3 to 6 minutes per palette at
  90 to 110 BPM. `classic`'s round is one bar, so with it a palette changes on an
  8-bar line.
- **Only one progression can play.** If Progression is on Auto but only one
  progression can play (for example only `classic` is in the folder), palettes
  change at the end of its round and the post window says
  `PedalPulse: only one progression can play on Auto, so Auto palettes change at the end of its round`
  once.
- **No quick repeats.** Auto never picks the palette that is playing or one of the
  last two it played. A palette file you add while the engine runs joins the
  rotation by itself.
- **A name locks it.** Picking a palette by name keeps it, whatever the
  progressions do, until you pick Auto again. Auto then draws a different palette
  (it does not keep the one you picked) at the next round.
- **Stop then Start** draws a new random palette.
- **Replay.** The `PedalPulse: progression auto seed <n>` line in the post window
  also replays the order of the palettes on a freshly started SuperCollider.
- Notes that are ringing when the palette changes finish by themselves (there is
  no cut), there is no transition effect, and a palette never turns the lead on:
  the Melody choice does.

Every change prints `PedalPulse: palette <name>: <description>` in the post
window. That line is what to read when you want to name the sound you just heard.

## Bass styles

A palette can name its bass rhythm with `bassStyle` in its file:

- `\eighths`: offbeat eighths, the classic bass groove.
- `\sixteenths`: a rolling bass in sixteenths.
- `\octave`: offbeat pops that jump between two octaves.

`acid` and `dark` roll sixteenths, `pluck` pops octaves, and `classic`,
`supersaw`, `warm` and `air` play eighths.

The palette decides the bass rhythm under every progression, the `classic`
progression included (its chord is A minor in every bar). Pick `acid` during the
classic groove and the bass rolls in sixteenths on A. Only the `classic` palette
keeps the progression's own bass, so `classic` in both Palette and Progression is
still exactly the original sound. The palettes that play eighths (`supersaw`,
`warm`, `air`) use classic's bass notes and rhythm under the classic progression.

## Write a new palette

Copy `palettes/_template.scd` to a new name and change the copy.

- Name every voice `pp_<name>_<role>`, for example `pp_dusk_arp` inside
  `dusk.scd`. A palette that uses another palette's voice name is refused.
- The voice contract (see "File contract" below): controls `out`, `amp`, `freq`
  and `gate` (drums: `out` and `amp`), an envelope that ends the synth, and
  `Out.ar(out, ...)` only.
- Keep releases short (about 1.5 seconds at most). If a filter cutoff follows the
  note, clamp it with `.min(12000)`. Put no reverb or delay inside a voice: the
  engine's EPIC effects do that.
- Then level-match it. Run

  ```
  bash scripts/palette_level.sh <name>
  ```

  It plays your palette and `classic` on its own silent test server (never your
  running engine) and prints how much louder or quieter yours is. Change only the
  gain numbers in your file and run it again until the gap to `classic` is 0.75 dB
  or less and every `CHECK OK` line appears. Commit the file only then: a
  committed palette can never be edited, so a gain you got wrong would stay.

## Check everything

```
bash scripts/check.sh
```

This runs the library check, which also measures every palette against `classic`
(`CHECK OK: palette levels`), and then the full smoke test. It takes several
minutes. For the faster part that only covers the library, while you are adding a
variation:

```
bash scripts/check.sh --library-only
```

The library check opens every `.scd` file here, the `_template.scd` files
included, and prints one `LIBCHECK OK: <folder>/<name>` line for each. It also
checks that every committed file is unchanged, and that every palette sound
stays on its own bus (so it always goes through the master limiter), lets go
when the gate closes, and frees itself.

### CPU next to Zwift

To see whether the engine fits next to Zwift on your Mac: quit the PedalPulse
engine, open Zwift (no ride needed), and run

```
bash scripts/palette_cpu.sh
```

It finds the heaviest palette, plays it at the hardest settings (VO2, volume 100)
for about a minute and prints a line like
`PedalPulse meter: cpu <name> mean=... max=... peak=...` and then `CPU PASS` or
`CPU FAIL`. Report the `mean` and `peak` numbers. It passes when the mean is under
25 percent.

## File contract (for authors)

- One Event per file (everything inside one pair of parentheses). Nothing runs
  at load: no `~` variables, no `Pdef` or `Pbindef`, no clocks, no server, no
  files, no `Synth`. The check lints for these and fails the file.
- `desc` is required: one plain sentence saying what it sounds like.
- Read and write Events with `[\key]`, never dot syntax.
- Progressions provide `chords` (chord data; the core plays the bass and the pad
  from it) or, like classic, `bass` and `pad` generators. Melodies provide
  `arp`, `lead` and an optional `init`. Palettes provide `defs` (optional),
  `roles` and optionally `bassStyle`.
- The engine moves a melody's notes onto the current chord: the classic arp's A,
  C, E become the root, third and fifth of each chord. A melody that works out
  its own notes from `plan[\chord]` sets `ownHarmony: true` in its Event, and
  then its notes are left as they are.
- A generator is `{ |plan, state| }` and returns one bar as an Array of
  `[note, dur, amp, legato]` rows. The durs add up to exactly 4 beats over the
  bar. `note` is a MIDI number, a chord (an Array of MIDI numbers) or `\rest`.
  `amp` is 0 to 1.
- `plan` has `bar`, `songBar`, `phraseBar` and `role`, and the harmony keys
  `progression`, `chord`, `nextChord`, `changesNext`, `chordBar`, `chordBars`,
  `cycleBar`, `cycleLen`, `voicing` and `scale`.
- Randomness is allowed (`rrand`, `choose`). It is seeded per (song, bar, role),
  so a restart plays the same bars.
- A missing role falls back to classic, and a missing lead is silent.
- The voice contract for a palette sound: controls `out`, `amp`, `freq` and
  `gate` (drums: `out` and `amp`), an envelope that ends the synth
  (`doneAction: 2`), `Out.ar(out, ...)` only (never bus 0), and a name that
  starts with `pp_<palette>_` (enforced: a file that breaks it is refused; a role
  may still use one of classic's six voices).
- A progression's `bass` generator is heard only while the `classic` palette
  plays; every other palette plays its `bassStyle` on the progression's chords.
- Later phases only add optional keys, so a committed file never needs an edit.
