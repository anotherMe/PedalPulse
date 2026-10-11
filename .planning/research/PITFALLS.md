# Pitfalls Research

**Domain:** Adding generative variety, runtime module loading, palette hot-swapping and density control to a live SuperCollider pattern engine (PedalPulse v2.0 "Living Music"), on top of the shipped v1.0 engine
**Researched:** 2026-10-11
**Confidence:** MEDIUM overall. The integration pitfalls are derived from reading the actual `supercollider/main.scd` and the smoke harness (HIGH for "this will happen in this code"). SuperCollider semantics were checked against the official docs where the docs say something (Pbindef merge semantics, nowExecutingPath) and otherwise rest on well-known sclang behaviour that the docs do not spell out (SynthDef re-add, Pdef quant, OSC strings arriving as Symbols). Items marked "(verify)" should be proven with a one-line smoke check before being relied on.

## Phase labels used below

The roadmap decides real phase numbers. These labels are the natural slices of the milestone and are used in the mapping table at the bottom.

| Label | Slice |
|-------|-------|
| **P-Core** | Core/module split, library loader, naming, smoke-test tiers |
| **P-Harmony** | Shared harmony clock, progressions, layers reading chords |
| **P-Palette** | Sound palettes, hot-swap, loudness normalisation, CPU/node budget |
| **P-Melody** | Rule-based evolving melodies |
| **P-Structure** | Fills, sections, build/drop, EPIC density |
| **P-GUI** | Python selectors, Auto/lock, rotation |
| **P-Soak** | Accelerated soak test, ENG-03 closeout |

---

## Critical Pitfalls

### Pitfall 1: Library loader dies because `thisProcess.nowExecutingPath` is nil inside `s.waitForBoot`

**What goes wrong:**
`main.scd` runs almost everything inside `s.waitForBoot({ ... })`, after `0.3.wait` and `s.sync`. A module loader written as `"library/palette/dark.scd".loadRelative` (or `thisProcess.nowExecutingPath.dirname` computed inside that block, or inside an `OSCdef` callback) gets `nil`, and the load fails with a confusing "nil does not understand dirname/+/+" error. It works when you test it at the top of the file and breaks once moved into the routine. A second variant: evaluating a selected region of an unsaved IDE document also gives nil.

**Why it happens:**
`nowExecutingPath` is only populated while the interpreter is synchronously executing the file. Once a Routine resumes after a `wait`/`sync`, or a callback fires later, the value is gone (docs: it is also nil outside the IDE/SuperCollider.app/scel). `loadRelative` depends on it. The smoke test already knows the related trap (it resolves `File.realpath(thisProcess.nowExecutingPath)` at the very top, before anything async).

**How to avoid:**
- At the very top of `main.scd`, outside `waitForBoot`, capture once: `~ppRoot = thisProcess.nowExecutingPath.dirname;` (use `File.realpath` like the smoke test, and fall back to a `~ppRoot` already set by the smoke test or a `Platform.userHomeDir`-independent explicit override). Never call `loadRelative` or `nowExecutingPath` anywhere else.
- Build the loader from absolute paths only: `(~ppRoot +/+ "library" +/+ category +/+ name ++ ".scd").load`.
- Keep `~ppRoot` across re-evaluation with the same `x = x ? default` idiom, but refresh it whenever `nowExecutingPath` is non-nil (the file may have moved).
- Make the loader return `nil` + warning (not throw) when the path is missing, so the engine keeps playing.

**Warning signs:**
"nil does not understand" on startup; works when run from the smoke test but not from the IDE (or vice versa); library list empty in the post window.

**Phase to address:** P-Core (first thing built; prove with a smoke check that loads a fixture module from inside the waitForBoot routine and from an OSCdef-triggered fork).

---

### Pitfall 2: Library files that write to bus 0, ignore `out`/`group`, or omit `gate`/`amp` bypass the mix, limiter and Stop

**What goes wrong:**
Three failure modes from the same cause (library files are authored by Claude from plain-language feedback, one file at a time, without the engine's invariants in mind):
1. A palette SynthDef hardcodes `Out.ar(0, ...)` or a pattern sets `\out, 0`. That voice goes straight to hardware, bypassing the EPIC FX chain **and the -1 dBFS limiter** (the limiter only reads `~ppFxBus`). The only symptom is a loud, unfiltered voice.
2. A voice has no `gate` argument or an envelope without `doneAction: 2` that releases on gate. `~ppStop` only does `~ppInstrGroup.set(\gate, 0)`, so that voice never ends: Stop leaves a drone, and during a 60-minute ride with rotating palettes un-freed nodes accumulate (this is the classic SuperCollider node leak).
3. A Pbindef without `\amp`. The existing code documents the trap: with no `\amp` key the event sends the default `0.1`, overriding the SynthDef's own `\amp` default (the original kick was designed at 0.5). A new layer whose file forgot `\amp` is 4x quieter than intended and nobody notices until the mix is wrong.

**Why it happens:**
In v1.0 the engine author wired `out`/`group` by hand per layer. Moving that wiring into content files hands the invariants to every future author.

**How to avoid:**
- Core owns wiring. Library files return only musical data and SynthDef names; a core function `~ppMakeLayer` injects `\out` (= `~ppMixBus`), `\group` (= `~ppInstrGroup`) and `\amp` from a per-role table, *after* the file's keys so the file cannot override them.
- Make library files side-effect free: the file's last expression returns an `Event`/`Dictionary` (e.g. `(name: ..., voices: ..., params: ...)`). The loader validates it (required keys, types, ranges) and only then registers it. A half-failed file therefore never leaves partial state behind.
- Validate each SynthDef after `.add` + `s.sync` via `SynthDescLib.global[\name].controlNames`: must contain `out`, `gate`, `amp`, `freq` (or the role's required set); reject otherwise with a warning and keep the previous palette.
- Smoke: for every library file, play one note of every voice for 2 bars, call `~ppStop`, wait release + 0.5 s, assert `~ppInstrGroup.numChildren == 0` (use the existing `instrChildCount` helper).

**Warning signs:**
Stop leaves a sound; `s.numSynths` creeping up between samples; a voice louder at low volume settings; voice unaffected by EPIC brightness.

**Phase to address:** P-Core (validation schema + `~ppMakeLayer`), enforced again in P-Palette (every new palette goes through the same validator).

---

### Pitfall 3: Layers read the harmony at different times, so bass/arp/pad/lead clash across chord changes

**What goes wrong:**
A "shared harmony clock" implemented as a mutable global (`~ppChord = ...`) updated by a routine, with each Pbindef reading `~ppChord` in a `Pfunc`. Layers have different `dur`, `timingOffset` and sustain: the bass plays on the offbeat 8th (offset 0.5), the arp on 16ths, the pad has `dur 4, legato 0.9` plus a 1.2 s release. At the bar line the routine updates the chord some microseconds before or after each layer's event is generated, so on the changeover bar one layer plays the old chord and its neighbour the new one. The pad's 1.2 s release tail also holds the old chord under the new one. Result: audible dissonance exactly at every chord change, which sounds like "the song is out of tune" and is hard to reproduce.

**Why it happens:**
Event generation is lookahead-driven (`Pbind` computes the next event when the previous finishes, up to `s.latency` ahead of its sounding time), so "what is the current chord" depends on who asks when. Mutable shared state plus asynchronous readers is a race by construction.

**How to avoid:**
- Make harmony a **pure function of musical time**, not state: `~ppChordAt = { |beat| progression.chordAtBar((beat / 4).floor) }`. Every layer asks with its **own event beat** (`thisThread.clock.beats` inside the `Pfunc`, plus its timingOffset). Same beat, same answer, regardless of who asks first.
- Provide one harmony API that returns MIDI notes (root, chord tones, scale) so all layers use `\midinote`; do not mix `\degree` (default root C, octave 5) in one layer and `\midinote` in another, or layers end up in different keys.
- Progression/scale changes are *pending* values applied only at a phrase boundary (same pattern as `~ppRampPendingBpm`): the OSC handler sets the pending name, a bar-aligned scheduler commits it. Never mutate the active progression from an OSC callback.
- Pad: release shorter than the shortest chord overlap, or voice-lead (keep common tones); cap `legato` below 1 and let the pad release start before the bar line.
- Bass and lead must obey chord-tone-on-strong-beat rules; non-chord scale tones only on weak beats.
- Smoke test (language only, no audio): for 32 bars, query every layer's note at its event beats and assert that on each beat the set of simultaneous pitch classes belongs to the current chord's allowed set (chord tones + declared passing tones).

**Warning signs:**
Dissonance only on bar 1 of each chord; fine when listening to a single layer solo'd; more audible at fast BPM (smaller margin).

**Phase to address:** P-Harmony (design the API before any melody work; P-Melody consumes it).

---

### Pitfall 4: Pattern swaps land out of phase (Pbindef quant, merge semantics, leftover keys)

**What goes wrong:**
- `Pbindef(\ppArp, \midinote, newPattern)` takes effect at the proxy's `quant` (default: next beat), not the bar line, and the new `Pseq` starts from its first element at that beat. If a pattern's length is not a whole number of bars, or different layers are swapped on different calls, layers end up shifted against each other for the rest of the session.
- **Pbindef merges.** `Pbindef(\x, \key, val)` changes only that key; keys from the previous style not mentioned by the new one stay active (the docs state this; `nil` removes a key). A melody style that sets `\detune` or `\legato` or `\ctranspose` leaves them behind when the next style does not. v1.0's re-evaluation relies on this merge being harmless because the keys are identical every time; library files make it harmful.
- `Pbindef(\x).stop` followed by `Pbindef(\x, ...)` "does not resume now" (docs) - an update during Stop is silently stored.
- Fills implemented by replacing the kick/hat Pbindef for a bar and then restoring it: a missed restore (error, Stop, tempo glide re-quantisation) leaves the drum layer stuck in the fill.

**Why it happens:**
Treating a Pbindef as "the current pattern" instead of "a proxy whose source I patch".

**How to avoid:**
- Do not swap Pbindef sources for content. Keep each layer as one permanent Pbindef whose keys are `Pfunc`/`Pdefn` lookups into the current scene data (stream-time lookup). A palette or style change is then a data change that takes effect on the layer's next event, atomically.
- Apply scene changes only from a bar-aligned scheduler on `~clock` (`~clock.schedAbs(~clock.nextTimeOnGrid(4), ...)`, or a conductor routine that waits whole bars), all layers in one function call, so they share a logical time.
- All content patterns are whole bars (or a declared phrase of 4/8 bars); validate lengths in the loader.
- When a layer's definition really must be rebuilt, use `Pdef(\x, Pbind(...))`/`.source =` or explicitly `nil` the keys, never rely on merge; and set `Pbindef(\x).quant = 4` explicitly for any layer that is swapped.
- Fills and risers are **overlay layers** (separate `\ppFill`, `\ppRiser`) plus a mute mask on the base layers; never edit the base layer and restore it.
- Smoke: swap palette and progression 10 times at random beats and assert every layer's next event beat modulo 4 equals the same offset before and after.

**Warning signs:**
Kick and hat flam after a swap; groove "feels one 16th late" until Stop/Start (Start's `doReset: true, quant: 4` re-aligns everything, which masks the bug in short tests); leftover brightness/detune after switching style.

**Phase to address:** P-Core (scene-data pattern and bar-aligned apply function), reused by P-Palette, P-Melody, P-Structure.

---

### Pitfall 5: New voice sources escape `~ppLayers` and `~ppStop` (music keeps playing after Stop, conductor stacks on re-evaluation)

**What goes wrong:**
v2.0 adds sources that are not simple Pbindefs: a conductor/section routine, fill and riser generators, rotation timer, one-shot `Synth(...)` calls for impacts. `~ppStop` only stops `~ppLayers` Pbindefs and gates the instrument group. A fill generated by a Routine keeps scheduling notes after Stop. A conductor that keeps running while stopped advances section counters silently, so pressing Start lands in the middle of a drop. On re-evaluation, a conductor routine that is not stopped in the teardown (as `~ppRampStepper` is) stacks a second copy: sections now change twice as often, fills double.

**Why it happens:**
v1.0 invariant "`~ppLayers` is the single list of layers" does not cover non-Pbindef sources. The `0.3.wait` teardown frees nodes and stops known objects only.

**How to avoid:**
- Extend the invariant: one registry `~ppSources` (Pbindefs, Routines, Tdefs) that Start, Stop and teardown all iterate. Anything new registers itself or the loader rejects it.
- Conductor: a keyed `Tdef(\ppConductor)` (or a Routine stopped in teardown), playing **on `~clock`** in beats - never `SystemClock`/`AppClock`, never its own `TempoClock` (the existing anti-pattern; a second clock drifts through glides). It pauses (or resets to a defined opening section) when `~ppPlaying` is false, and Start resets structure position.
- One-shot Synths go into `~ppInstrGroup` so the gate broadcast and group free reach them.
- Rotation timer counts bars on `~clock`, not wall-clock `SystemClock.sched`. If wall-clock minutes are wanted, check elapsed time at section boundaries.
- Smoke: re-evaluate `main.scd` 3 times, then count live Routines/Tdefs (`Tdef.all.keys`, `AppClock`/`~clock` queue size where available) and assert unchanged; Stop mid-fill and assert the group is empty 1 s later.

**Warning signs:**
Sound after Stop; section changes that "speed up" after each re-evaluation; Start begins with a huge drop.

**Phase to address:** P-Structure (conductor, fills), with the registry introduced in P-Core.

---

### Pitfall 6: Node, buffer and CPU growth from per-palette FX, extra layers and palette rotation (ENG-03 gets worse)

**What goes wrong:**
- A palette file creates its own persistent FX (reverb, delay, chorus) on load. Each palette swap/rotation adds one more synth (and any `Buffer.alloc`/`LocalBuf` delay line) that nobody frees. With Auto rotation every few minutes, a 60+ minute ride accumulates dozens of idle but running FX synths: CPU creeps up until Zwift stutters.
- Each added layer (lead, counter-line, fill, riser) multiplies voices: 16th-note arp x 2-4 detuned oscillators x filter x release overlap. CPU peaks precisely at VO2 + densest palette + a fill + a drop, the combination the rider hits at the hardest moment.
- Reverb/delay UGens draw from the server's real-time memory (`s.options.memSize`, default 8192 KB) and `maxNodes` (1024). Exceeding them produces "alloc failed" / silent missing notes, not an error in the app.
- Re-adding SynthDefs on every swap (`.add` each time) grows `SynthDescLib` churn and floods the server with `d_recv`.
- `postln` per note at 16ths (debug output) bloats the IDE post buffer over an hour and slows the IDE.

**Why it happens:**
v1.0 had one fixed set of persistent synths freed by a single teardown; palettes make the persistent set variable.

**How to avoid:**
- **FX live in core, palettes only set parameters.** Reverb, delay, drive, the EPIC chain stay in `\ppFx`; a palette can supply parameter values via a small set of control buses (or settings sent to `\ppFx`), never create persistent synths. If a palette truly needs its own persistent synth, it declares it in its returned Event and the core creates/frees it through a registry on swap.
- Load once, cache: keep `~ppLoaded[category][name] = (mtime, data)`; a swap reuses it. `SynthDef.add` only on first load (or when mtime changes).
- Per-role voice budget: define the maximum simultaneous voices per layer and a UGen-count ceiling per SynthDef (documented in the library template). Prefer 2 detuned oscillators over 5 for the arp (16th-note, highest event rate).
- Pre-compute generative state in language-side arrays; keep OSC handlers trivial (set pending, return) because they and all pattern lookups share the one sclang thread.
- Add CPU/node observability to the engine: a 60 s status line (`s.avgCPU`, `s.peakCPU`, `s.numSynths`, `s.numGroups`, `s.numSynthDefs`) to the post window and optionally a log file. The smoke test already prints `avgCPU/peakCPU`; turn that into an assertion with a budget (propose avg < 25%, to be calibrated on the user's Mac with Zwift running).
- Worst-case test: VO2, densest palette, fill + drop simultaneously, `s.avgCPU` budget asserted.

**Warning signs:**
`s.numSynths` at the end of a rotation cycle greater than at the start; avgCPU rising monotonically in the 60 s log; notes occasionally missing at VO2; "alloc failed" in the post window.

**Phase to address:** P-Palette (budget + FX-in-core rule), P-Soak (accelerated rotation leak test).

---

### Pitfall 7: Loudness jumps between palettes and density levels; the limiter does not normalise loudness

**What goes wrong:**
The -1 dBFS limiter only prevents clipping. A palette that is 6 dB hotter than the previous one passes the limiter untouched, so the rider hears a sudden level jump at rotation time. Conversely a palette hotter than headroom is *squashed* by the limiter (audible pumping/distortion) and, at high EPIC, `drive` (up to 3.5x) plus `softclip` flattens differences at VO2 while leaving them obvious at Recovery. Density makes it worse: more layers at VO2 sum to a louder bus feeding the same drive stage. Bass-heavy palettes read louder on a meter than perceptually.

**Why it happens:**
Authoring "by feel" in isolation; nobody compares palette A to palette B; peak-based checks (the existing `measurePeak`) test only the ceiling.

**How to avoid:**
- Per-palette `trim` (dB) in the returned Event, applied in the core as a gain on that palette's layers; per-role `amp` table owned by core (Pitfall 2).
- Measure RMS, not just peak: extend the probe to report short-term RMS (`Amplitude.kr`/`RunningSum`) over 8 bars at a fixed EPIC (e.g. 30 and 75) and require every library palette within +/-1.5 dB of the reference palette. This is also how Claude should set `trim` when authoring a new palette (print the measured RMS, adjust, re-measure).
- Level headroom budget: sum of all layer peaks at maximum density must stay under the pre-limiter ceiling with the limiter *rarely* engaged (gain reduction under ~3 dB). Check with the existing `preGain` debug knob in the opposite direction (reduce, do not only boost).
- Palette swap is crossfaded over one bar (ramp the trim/amp on the incoming layers), never a hard cut; density changes ramp layer amp over a beat instead of switching.
- Keep a `LeakDC` plus a high-pass (~30 Hz) in sub-bass voices: DC or sub-30 Hz energy eats limiter headroom with no audible benefit.

**Warning signs:**
Rotation at minute N "gets louder"; limiter-pumping on kicks at VO2; volume slider needs retouching after each palette change.

**Phase to address:** P-Palette (trim + RMS audit), revisited in P-Structure (density sums).

---

### Pitfall 8: Library name drift between Python and SuperCollider (silent, because the app is send-only)

**What goes wrong:**
Python lists `supercollider/library/palette/*.scd` at app start; SuperCollider loaded its registry at engine start. Mismatches that all fail *silently* (UDP, no reply channel):
- A file added after SuperCollider started: the GUI offers "Dark_v2", the engine has never heard of it, the selection is ignored and the rider thinks the lock is active while rotation continues.
- Identity defined twice: filename `dark.scd` vs a `name: "Dark"` field inside the file. Python shows one, SC keys by the other.
- Display name vs id: "Deep Dark" (display) vs `deep_dark` (file). Spaces/hyphens/case/Unicode (`\deep-dark` is not a valid symbol literal; `'deep-dark'` is, but typing differs); macOS filesystems may be case-insensitive.
- OSC strings arrive in sclang as **Symbols** (verify), not Strings; handlers written like the existing numeric ones (`raw.isNumber`) or comparing with `==` against a String reject or mismatch valid names.
- The reserved selector "Auto" collides with a library file named `auto.scd`.
- Python lists junk: `.DS_Store`, `._dark.scd` AppleDouble files, editor swap files, `_template.scd`, subfolders, or lists in filesystem order.
- Python resolves the folder relative to the current working directory, which differs between `./run.sh`, pytest and an IDE.
- After an engine restart the engine is back at Auto while the GUI still shows a locked palette (the W2 "no resync" debt, now with visible consequences).

**Why it happens:**
Two processes derive the same vocabulary from the same folder at different times with no shared contract.

**How to avoid:**
- **The filename stem is the one identity.** Id regex `^[a-z0-9_]+$` (lowercase, underscore), enforced by both sides; the GUI may prettify for display (`deep_dark` -> "Deep dark") but always sends the id. No in-file `name` field.
- **Disk is the single source of truth; SC loads on demand.** The `/pp/palette <id>` handler resolves `library/palette/<id>.scd` at request time (cached by mtime), so a file added during the ride works without rescan. Unknown id: print `PedalPulse WARNING`, keep the current selection.
- Auto is a separate reserved id that cannot be a valid file stem (e.g. the literal `auto` is rejected by the stem validator in Python and SC, or use a distinct address/flag).
- Accept both Symbol and String in the handler (`msg[1].asString`), validate the regex before touching the filesystem.
- Python lister: `Path(__file__).resolve().parent.parent / "supercollider" / "library"`, only `*.scd` files not starting with `.` or `_`, sorted, case-folded duplicates flagged, category dirs that do not exist yield an empty list with Auto still available.
- The GUI re-sends all current selections on Start and after every user selection (cheap, idempotent, engine already tolerates repeats) so an engine restart is healed by the next click. The engine keeps selections across re-evaluation (`~ppLock = ~ppLock ? nil`).
- Contract tests on both sides use the same fixture folder: pytest asserts the lister output and message strings; the smoke test asserts the engine accepts every real library id and rejects a bad one.
- Optional "library is append-only" check (script or test) that fails if a tracked file under `library/` is modified instead of added, to honour the never-overwrite rule.

**Warning signs:**
A GUI item that does nothing; locked palette that still rotates; lock label disagreeing with what is heard after restarting SuperCollider.

**Phase to address:** P-Core (naming contract + loader), P-GUI (lister + resend), contract tests in both.

---

### Pitfall 9: Randomness that is aimless or still repetitive

**What goes wrong:**
- Uniform random over the scale (`Prand`, `rrand`) produces noodling: no direction, no repeats, no hook. After a minute it sounds like noise with nice pitches; the rider cannot name or ask for any of it.
- Fixed deterministic loops (v1.0's 4-note arp) "same 5 notes for an hour" - but a 64-bar loop with a fixed rhythm and fixed palette is the same problem moved up.
- Varying pitch while rhythm and sections never change: statistically different, perceptually the same piece.
- Everything varying at once (new progression + new palette + new melody + new section) at the same bar: reads as a chaotic restart, not evolution.
- Regular, jitter-free change intervals (exactly every 16 bars) become predictable again after 20 minutes.
- Mutation without memory drifts away and never returns; without a return, no motif is ever recognised.

**Why it happens:**
"Random" is easy; "constrained random with memory" takes design. Without a way to *listen* quickly, authors also cannot tell a good rule set from a bad one.

**How to avoid:**
- Motif engine: generate a 1-2 bar motif once (contour + rhythm fixed), then **repeat it N times unchanged, mutate one attribute per repeat** (one note by a step, one rhythm shift, an octave jump, an inversion), and **periodically return to the original** (A A A' A / A A' A B). Mutation operates on a stored motif, not a fresh draw.
- Melodic rules: chord tone on strong beats, stepwise motion with 1 leap per phrase followed by a step back, range limit (about an octave), resolve to a chord tone at phrase end, rests are part of the motif (silence is the cheapest variety).
- Layered timescales (micro: ornament every few beats; bar: fill; phrase 4/8 bars: motif mutation; section 16-32 bars: arrangement; ride: palette/progression rotation) with the stagger rule "at most one major change (progression, palette, melody style) per section boundary".
- Jitter on structure: pick section lengths from a small set (e.g. 8/16/24/32 bars) with weights, no consecutive repeats of the same section length.
- Reproducibility: seed each section (`thisThread.randSeed`/`Pseed`) and print the seed with the section/motif/palette names. Feedback like "the melody around minute 20 was great" is then actionable and reproducible by Claude.
- Language-only quality tests (milliseconds, no server): generate 64 bars per melody style and assert note range, chord-tone ratio on strong beats, repeat ratio between roughly 20-80% for consecutive bars, and a minimum number of distinct motifs over 64 bars. Not a musical-quality proof, but catches the all-random and the stuck-on-one-note extremes.

**Warning signs:**
Melody changes every bar; or the same two bars heard for five minutes; or the user's feedback is "I cannot say what changed".

**Phase to address:** P-Melody (rules, seeds, tests), P-Structure (stagger and jitter policy). Final judgement is a listening UAT; list it as such.

---

### Pitfall 10: Hot-loading from an OSC callback: no Routine, blocking compile, async SynthDef race

**What goes wrong:**
- `s.sync` / `wait` inside an `OSCdef` callback throws "must be called from within a Routine"; the handler works for names already cached and breaks on first load of a new file.
- `SynthDef(...).add` is asynchronous. Creating or pattern-playing a Synth right after `.add` without `s.sync` produces "SynthDef not found" (`FAILURE IN SERVER /s_new`) and a missing note; the first bar of a new palette is silent or the old voice sounds.
- Compiling and loading a big library file blocks the single sclang thread; every pattern event generated meanwhile is late. The 0.2 s `s.latency` absorbs ~100-200 ms; a load during a busy bar can push events past it (audible stutter).
- Re-adding a SynthDef with the same name: notes already sounding keep the old definition; only new notes use the new one (verify). Not harmful by itself, but combined with a changed control set, patterns keep sending removed args ("Parameter not found" spam).
- Load error halfway through a file leaves the registry half-updated.

**How to avoid:**
- OSC handler only sets a pending request (`~ppPendingPalette = id`) and returns. A bar-aligned fork (`fork { ... }` on `~clock` or a Task) does `load -> validate -> add -> s.sync -> commit` and applies at the next phrase boundary.
- Pre-load ahead of rotation (N bars before the planned swap), in a fork that yields (`0.01.wait` between steps), so commit is instant.
- `try { ... } { |err| warning; keep previous }` around every load; loader returns `nil` on parse error (sclang's `.load` posts the error and returns nil - check for nil explicitly).
- Unique SynthDef names per palette (`\ppArp_dark`) so a later "improved" palette never changes the timbre of the earlier one and "switch back to the old one" really is the old one; roles are stable only in the *interface* (controls), not in the names.
- Smoke: load a fixture palette from an OSC-triggered path while the groove plays; assert no "SynthDef not found" in the log and the new palette audibly sounds (peak probe).

**Warning signs:**
First selection of a new palette is silent for a bar; "SynthDef ... not found"; a stutter when a new file loads; the second selection works but the first does not.

**Phase to address:** P-Core (load pipeline), P-Palette (swap commit).

---

### Pitfall 11: EPIC density causes flapping, pops and conflicts with section logic

**What goes wrong:**
- Layers gated directly on the raw EPIC value flap if EPIC is near a threshold, and are toggled mid-bar: a hat or arp appears/disappears in the middle of a bar with a click or an abrupt entry.
- Rapid zone clicking (Tempo -> VO2 -> Recovery -> Threshold within seconds) retriggers density changes repeatedly. Brightness glides for 1.5 s on the server while density is applied on the language side at the next bar: the two timescales visibly disagree.
- Section logic and EPIC density fight: a "drop" at Recovery should not equal a drop at VO2; a "breakdown" that removes layers *and* EPIC Recovery removes layers can leave only a kick or nothing.
- Recovery goes so sparse that the pulse disappears; for cycling the rider needs the beat.

**How to avoid:**
- Density = a table of per-layer thresholds with hysteresis (enter above X, leave below X-10), evaluated only at bar boundaries from the *latest* EPIC value; layer amp ramps over a beat (Pitfall 7) instead of switching.
- Explicit precedence: effective layer level = `epicLevel(layer) * sectionLevel(layer)`, with a floor: kick and bass pulse always present; sections scale *relative to* the EPIC baseline (a drop at Recovery is "slightly fuller", at VO2 "everything").
- Density changes and section transitions go through the same bar-aligned apply function (Pitfall 4).
- Smoke: for each of the five zones x each section type, assert the set of active layers is non-empty and includes the pulse layers; spam EPIC 20 times in 2 s and assert only one apply per bar.

**Warning signs:**
Layers stuttering in and out; silent bars at Recovery; drops that sound the same in every zone.

**Phase to address:** P-Structure.

---

### Pitfall 12: Smoke test runtime blow-up with many library files

**What goes wrong:**
The existing suite is one 1,920-line `( ... )` block, 67 checks, already needed its watchdog raised from 240 s to 300 s (and `scripts/smoke_test.sh` times out at 330 s). Naively adding "play each palette for 5 s at 3 EPIC levels" grows linearly with library size (50 palettes x 3 x 5 s = 12 minutes) and trips the watchdog, producing false failures that teach everyone to ignore the test. Adding checks to the single block also risks hitting sclang's limits on local variables per function (the block already declares ~40 `var`s). Every re-evaluation inside the suite costs the 0.3 s teardown plus loading every library file at startup.

**How to avoid:**
- Three tiers:
  1. **Lint (language-only, every run, seconds):** load every library file, validate schema, SynthDef controls (Pitfall 2), pure-language melody/harmony checks (Pitfalls 3 and 9), name regex. No audio.
  2. **Canary audio (every run, bounded):** default palette + the newest-by-mtime palette + one random palette, 2 bars each, with level and node-count assertions. Fixed cost regardless of library size.
  3. **Full audit (on demand, separate script `scripts/library_audit.sh`):** every palette's RMS vs reference and stop-cleanliness (Pitfalls 2 and 7). Run when a library file is added or changed (file list from `git diff --name-only` against the last audit marker) and before a ride session.
- New suites are **separate files** each with its own watchdog, run by `scripts/smoke_test.sh` in sequence; do not extend the giant block.
- Watchdog derived from work (`base + perFile * n`) rather than a constant, and the failure message prints which check was running.
- Lazy loading (Pitfall 8) keeps engine startup constant instead of loading all N files.
- Accelerated test timing: use the 180 BPM clamp and short musical lengths so 8 bars take about 11 s.

**Warning signs:**
"watchdog timeout" with no check named; suite creeping past 5 minutes; people running only part of the suite.

**Phase to address:** P-Core (tiering and file split), maintained in every later phase.

---

## Moderate Pitfalls

### Pitfall 13: Auto-rotation and lock race, and badly timed swaps

**What goes wrong:** A rotation timer fires after the GUI sent a lock and overrides it; rotation swaps during a drop/climax (jarring) instead of a breakdown (masked); rotation measured in wall-clock minutes drifts relative to bars during a tempo glide; Auto picks the same palette twice in a row or an incompatible combination (very dark palette with a bright progression).
**Prevention:** One state record `~ppSel = (palette: \auto, progression: \auto, melody: \auto)` read by the rotation logic at each decision (lock = non-auto value is never rotated); decisions only at section boundaries, preferring breakdown/intro; a shuffle-bag so a palette is not repeated until the rest have played; optional `tags`/`mood` in the library Event used only to avoid clashing combinations.
**Phase:** P-GUI (state and lock), P-Structure (boundary choice).

### Pitfall 14: Tempo glide vs seconds-based timing in new voices and FX

**What goes wrong:** Risers with fixed second-long envelopes, delay lines with fixed delay time, and reverb pre-delay all assume a tempo. During the 8-beat glide delay lines chirp (pitch-shift) if modulated, or sit off the grid at the new BPM; a 4-second riser ends mid-bar at 150 BPM.
**Prevention:** Derive durations from `~clock.beatDur` at note-on or express them in beats and stretch the envelope (`timeScale`); keep echo times beat-based via a lagged control (`Lag` of at least a beat) rather than a hard set; the tempo stepper remains the only writer of `~clock.tempo` (writing a *bus* from it is fine, writing tempo from a new place is not).
**Phase:** P-Structure (risers/fills), P-Palette (delays).

### Pitfall 15: Reverb tail cut or doubled by palette swap

**What goes wrong:** If the swapped-in palette owns its reverb, the outgoing reverb is freed with its tail (click/cut) or both run for a while (CPU spike, wash).
**Prevention:** Shared reverb in core (Pitfall 6); palettes only change send levels; crossfade over a bar.
**Phase:** P-Palette.

### Pitfall 16: Pbindef global namespace collisions

**What goes wrong:** `Pbindef`/`Pdef`/`Tdef` names are global; a library file that reuses `\ppLead` or a generic name (`\bass`) edits the live layer. Two library files with the same `Pdef` key overwrite each other, violating the never-overwrite rule at runtime even though the files differ.
**Prevention:** Library files never create Pdefs/Pbindefs/Tdefs; they only return data (Pitfall 2). Core owns the proxy names (`pp` prefix).
**Phase:** P-Core.

### Pitfall 17: Bass register runs away under transposition / key change

**What goes wrong:** Progressions in other keys push the bass below about MIDI 33 (inaudible on laptop speakers, lots of limiter energy) or into mud.
**Prevention:** Fold bass notes into a fixed window (e.g. MIDI 33-45) after transposition; keep pad/arp/lead in their own windows; test every progression through all layers' register windows in the language-only lint.
**Phase:** P-Harmony.

### Pitfall 18: Smoke/engine state split on re-evaluation with new state

**What goes wrong:** New state (`~ppSel`, loaded cache, section position, pending palette) is either reset on re-evaluation (selection silently reverts to Auto) or kept stale (a cache entry pointing at freed buses/synths).
**Prevention:** Follow v1.0's idiom explicitly: user-facing selections use `x = x ? default`; derived runtime objects (cache of *data*, scheduled forks) are rebuilt or stopped in teardown; document each new variable in a short table in the teardown comment. Keep the loaded cache data-only so it survives re-evaluation without referencing server objects.
**Phase:** P-Core.

### Pitfall 19: Python selector widgets send spurious or duplicate messages

**What goes wrong:** Tk `Combobox` fires `<<ComboboxSelected>>` on programmatic `.set`; initial population sends a message; mouse-wheel over the box changes the selection by accident during a ride; the lister reads the disk on each redraw.
**Prevention:** Send only on a real user change (the `PlayController` pattern: compare to last sent), `readonly` state, scan the folder once at start plus on an explicit refresh; keep logic in a testable controller class like `BpmController`/`EpicController`.
**Phase:** P-GUI.

### Pitfall 20: Accidental Cmd-. in the IDE mid-ride

**What goes wrong:** Cmd-. stops all non-permanent routines and frees all synths; with a conductor, rotation fork and preloader all stopped, the clock is permanent but the music is gone and state is inconsistent.
**Prevention:** Register a `CmdPeriod.add` hook that sets `~ppPlaying = false`-equivalent state, and document "re-evaluate `main.scd`" as the recovery; or mark long-lived tasks so re-evaluation rebuilds all of them (already the idempotent design).
**Phase:** P-Soak.

---

## Minor Pitfalls

### Pitfall 21: Non-ASCII or long text in OSC strings / names
**What goes wrong:** Unicode filenames with accents arrive differently normalised (macOS NFD vs NFC), so the id Python sends does not match the file path SC builds.
**Prevention:** The id regex (Pitfall 8) excludes non-ASCII; Claude names files with ASCII only.

### Pitfall 22: Post window spam
**What goes wrong:** Per-event or per-bar `postln` over an hour makes the IDE sluggish and buries warnings.
**Prevention:** Log only transitions (section, palette, progression, seed) and the 60 s health line; gate verbose logging behind `~ppDebug`.

### Pitfall 23: Fills/riser one-shots created with default `\amp`
**What goes wrong:** Same as Pitfall 2.3 for one-shot Synths: no `\amp` means the SynthDef default, but `Synth(...)` from code never receives the Pbindef default of 0.1, so fills and Pbindef layers disagree on level.
**Prevention:** Route every one-shot through `~ppMakeLayer`/the role amp table.

### Pitfall 24: Hat/clap `WhiteNoise` voices with no seed in the language-only test
**What goes wrong:** Level tests become flaky run to run (noise RMS varies slightly).
**Prevention:** Compare with a tolerance of at least 1 dB and average over 8 bars.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Library files register themselves by side effect (set globals, create Pbindefs) | Easiest for Claude to write | Half-applied state on error, name collisions, cannot validate before commit | Never. Return data; core registers |
| Load all library files at startup | Simple, no on-demand path | Startup time and SynthDef count grow with every experiment; a single broken file breaks boot | Only for the first 5-10 files, and only if wrapped in try/catch |
| Single global `~ppChord` mutated by a routine | 5 lines | Chord races across layers (Pitfall 3) | Never |
| Verify new palettes only by ear | Fast | Loudness jumps, leaks, stuck notes reach the ride | Only for taste; correctness and level must be measured |
| Extend the single big smoke block | No new harness | Variable limit, watchdog creep, slow feedback | Never; add separate files |
| Hard-coded `Out.ar(0, ...)`/`\out, 0` in a quick test voice | Hear it instantly | Bypasses limiter | Only in a scratch file never placed in `library/` |
| Selecting a palette by editing and re-evaluating `main.scd` | No handler needed | Stops/glitches the music, defeats the point of runtime loading | Only for debugging |
| Skip seeds/logging of generative choices | Less code | Impossible to reproduce the good moment the rider liked | Never; log seed and names per section |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Python lister <-> SC loader | Two independent name sources (file name vs in-file name, display vs id) | Filename stem is the only id; regex on both sides; on-demand load by path |
| Python -> OSC string arg | Assuming sclang receives a String | Accept Symbol and String (`.asString`), validate before use |
| Python selection state <-> engine after restart | GUI keeps a lock the engine lost | Resend selections on Start and on every change; engine keeps state across re-evaluation |
| Library file <-> core wiring | File sets `\out`, `\group`, `\amp` itself | Core injects them last from role tables |
| Loader <-> `s.waitForBoot` | `loadRelative`/`nowExecutingPath` inside the routine or callback | Capture `~ppRoot` once at top of `main.scd` |
| OSCdef callback <-> async server work | `s.sync` in the callback | Callback sets pending; a fork does the loading |
| Conductor <-> TempoClock | Own clock or SystemClock timing | Play on `~clock` in beats, pause when stopped |
| New SynthDefs <-> Stop | No `gate`, so Stop cannot release | Validate `gate` control and `doneAction: 2` envelope |
| Palette FX <-> EPIC FX chain | Palette brings its own reverb/drive after the limiter's input | Palette sets parameters only; FX stays in `\ppFx` before the limiter |
| Smoke harness <-> library growth | Per-file audio checks in the main run | Lint tier always, canary subset always, full audit on demand |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| One persistent FX per palette load | avgCPU climbs after each rotation; `numSynths` grows | FX in core; registry for any persistent palette synth | After roughly 10-20 rotations (30-60 min) |
| 16th-note arp with heavy voice (multiple oscillators + resonant filter + long release) | CPU peaks at VO2, missing notes | UGen ceiling per role; short releases on the highest-rate layer | Densest palette at VO2, 160+ BPM |
| Fill + drop + riser at the same time | CPU spike on transitions | Budget test of the worst combination; stagger | Section transitions at VO2 |
| `postln` per note | IDE lag over time | Log transitions only | After 30-60 min |
| Re-adding SynthDefs on every swap | `d_recv` bursts, hiccups | Cache by mtime; add once | Each rotation |
| Heavy language-side generation inside OSC handlers or inside `Pfunc` per 16th | Late events | Precompute per phrase in the conductor fork; handlers only set pending | Large rule sets at fast BPM |
| Server memory (`memSize`, `maxNodes`) exhaustion | Silent "alloc failed", missing voices | Raise `s.options.memSize` (e.g. 32768) before boot if delay lines are used; watch node count | Delay/reverb-heavy palettes |
| Smoke test linear in library size | Watchdog timeouts | Tiered suites (Pitfall 12) | About 15-20 palettes if every one is audio-tested |

## Security Mistakes

The attack surface is small (loopback-only OSC, single user). Two items still matter because the engine now builds file paths from received strings and `.load`s them.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Building a path from the OSC name without validation (`"../../x"`) and `.load`-ing it | Executing an arbitrary `.scd` file from anywhere on disk (loopback-only, but any local process can send) | Regex `^[a-z0-9_]+$` on the id; resolve to the library root and verify the path stays inside it; keep the existing `srcID` loopback guard |
| `.load` of an untrusted or accidentally-copied file in `library/` runs arbitrary code | A broken file can hang the interpreter (infinite loop in top-level code) | Loader runs in a fork with try/catch; lint tier loads every file before any ride; files are only ever authored by Claude and reviewed in git |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| GUI shows a lock the engine does not have | Rider believes a palette is locked, hears rotation | Resend on Start/selection; document restart behaviour |
| Item listed but failed to load | Selecting does nothing, no feedback (send-only) | Loader falls back and keeps the previous palette; the post window carries the warning; lint tier catches it before a ride |
| Feedback cannot be tied to a moment | "The thing at minute 20" is unreproducible | Print palette, progression, melody style, seed at each section; names are the vocabulary |
| Too many changes at once | Music feels random instead of evolving | One major change per section; stagger |
| Selector dropdowns grab the mouse wheel | Accidental change mid-ride | Read-only comboboxes, ignore wheel events, or use radio-style lists |
| Palette lists change order between runs | Muscle memory lost | Sorted, stable order; Auto always first |
| Rotation interval invisible | Rider does not know when change is coming | Optional (not required, send-only): none; accept for v2.0 |

## "Looks Done But Isn't" Checklist

- [ ] **Library loader:** Often missing the `~ppRoot` capture - verify a palette loads when requested from an OSC handler after the first bar, not only at startup
- [ ] **New palette:** Often missing a gate/doneAction check - verify `~ppInstrGroup.numChildren == 0` shortly after Stop with that palette active
- [ ] **New palette:** Often missing loudness trim - verify RMS within +/-1.5 dB of reference at EPIC 30 and 75
- [ ] **Palette rotation:** Often missing leak check - verify `s.numSynths`, `s.numGroups`, `s.numSynthDefs` after 20 accelerated rotations equal the first-rotation values
- [ ] **Harmony clock:** Often missing the changeover bars - verify all layer notes on bar boundaries belong to the chord for that bar in the language-only test
- [ ] **Swap timing:** Often missing the phase check - verify next-event beats mod 4 are identical before and after a swap, including during a tempo glide
- [ ] **Stop:** Often missing non-Pbindef sources - verify silence after Stop during a fill, a riser and a section transition
- [ ] **Re-evaluation x3:** Often missing the conductor/rotation stop - verify section cadence does not speed up and the live Routine/Tdef count is unchanged
- [ ] **EPIC density:** Often missing the floor - verify every zone x section keeps the pulse layers
- [ ] **GUI selectors:** Often missing resend and name regex - verify a selector id equals the file stem and that an unknown id is ignored with a warning
- [ ] **Empty/garbage folders:** Often missing - verify GUI works with an empty category dir, `.DS_Store`, and `_template.scd`
- [ ] **Smoke suite:** Often missing the time budget - verify full run time stays under the script timeout with the current library, and a deliberately broken library file is reported by name
- [ ] **Soak (ENG-03):** Often missing for the new engine - verify 2-3 minute accelerated soak (180 BPM, 4-bar rotation, forced fills) with bounded CPU and node counts, then one real 60-minute ride with the 60 s health log

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Library file broke playback mid-ride | LOW | Loader keeps previous palette; GUI select another; re-evaluate `main.scd` (state kept) |
| Stuck/leaked nodes | LOW | Re-evaluate `main.scd` (teardown frees groups); find the offending file via per-file stop-cleanliness audit and fix as a new version |
| Palette too loud | LOW | Lower the volume slider; author `<name>_v2` with a corrected trim (never edit the original) |
| Harmony clash discovered late | MEDIUM | Fix the harmony API once (pure function), re-run the language-only lint for all progressions |
| Name drift between GUI and engine | LOW | Restart the app (re-lists), Start (resend); fix the id in the file name |
| Out-of-phase layers | LOW | Stop/Start re-aligns (`doReset: true, quant: 4`); then fix the offending swap path |
| Conductor stacked after re-evaluation | LOW | Re-evaluate once more after the fix; the keyed Tdef/stop in teardown replaces it |
| Smoke watchdog false failures | MEDIUM | Split suites, move the full audit to the on-demand script |
| Never-overwrite rule broken (file edited in place) | LOW | `git checkout` the file; add the improved version under a new name |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1 nowExecutingPath nil in routines | P-Core | Fixture module loaded from waitForBoot routine and from OSC-triggered fork |
| 2 Bus 0 / missing gate / missing amp | P-Core, P-Palette | Schema validation + stop-cleanliness check per library file |
| 3 Layers read harmony at different times | P-Harmony | Language-only simultaneity test across layers over 32 bars |
| 4 Out-of-phase swaps, Pbindef merge | P-Core, P-Palette, P-Melody | Beat-offset-before/after check across 10 random swaps |
| 5 Sources escape Stop / stack on re-eval | P-Core (registry), P-Structure | Silence after Stop mid-fill; 3x re-evaluation Routine count |
| 6 Node/CPU/memory growth | P-Palette, P-Soak | avgCPU assertion; accelerated rotation leak test; 60 s health log on a real ride |
| 7 Loudness jumps | P-Palette, P-Structure | RMS audit tier, +/-1.5 dB; limiter gain reduction under about 3 dB |
| 8 Name drift Python/SC | P-Core, P-GUI | Shared fixture contract tests; unknown id ignored with warning |
| 9 Aimless / repetitive randomness | P-Melody, P-Structure | Language-only melody metrics + seeded logging + listening UAT |
| 10 Hot-load in callback / async SynthDef | P-Core, P-Palette | Load-from-OSC smoke check with no "SynthDef not found" |
| 11 EPIC density flapping/precedence | P-Structure | Zone x section matrix; EPIC spam test |
| 12 Smoke runtime blow-up | P-Core | Tiered suites; total time budget; broken file reported by name |
| 13 Rotation vs lock race | P-GUI, P-Structure | Lock sent during pending rotation holds |
| 14 Seconds-based timing vs glide | P-Structure, P-Palette | Riser/delay checks during a glide |
| 15 Reverb tail cut | P-Palette | Listening check at swap; shared reverb in core |
| 16 Pdef namespace collisions | P-Core | Lint: library files create no proxies |
| 17 Bass register | P-Harmony | Register-window lint for all progressions |
| 18 State split on re-evaluation | P-Core | Existing re-evaluation checks extended to selections |
| 19 Spurious Tk sends | P-GUI | pytest on controller: no send on programmatic set |
| 20 Cmd-. recovery | P-Soak | Documented recovery |

## Sources

- Project code and records (HIGH): `supercollider/main.scd` (waitForBoot structure, 0.3 s teardown, `~ppLayers`, Pbindef `\amp` comment, limiter/FX bus chain), `supercollider/smoke_test.scd` (single 1,920-line block, watchdog 300 s, `File.realpath(thisProcess.nowExecutingPath)` at top, avgCPU print), `scripts/smoke_test.sh` (330 s timeout), `.planning/PROJECT.md` (decisions, ENG-03 open, W2 debt), `.planning/RETROSPECTIVE.md` (smoke harness lessons)
- [SuperCollider Pbindef docs](https://doc.sccode.org/Classes/Pbindef.html) - key-wise merge, `nil` removes a key, changes scheduled to the beat, "does not resume" after stop (MEDIUM, official docs)
- [SuperCollider Pdef / EventPatternProxy docs](https://docs.supercollider.online/Classes/Pdef.html) and [Quant docs](https://docs.supercollider.online/Classes/Quant.html) - quant/phase/offset model, swaps quantised to the beat (MEDIUM)
- [SuperCollider Process docs](https://doc.sccode.org/Classes/Process.html) and sc-users list threads ([2007](https://listarc.cal.bham.ac.uk/lists/sc-users-2007/msg08249.html), [2009](https://listarc.cal.bham.ac.uk/lists/sc-users-2009/msg52303.html)) - `nowExecutingPath` only available synchronously during file execution; capture at top of file (MEDIUM)
- [SuperCollider SynthDef docs](https://doc.sccode.org/Classes/SynthDef.html) - `add` is in-memory; docs silent on replacement of running synths (LOW for that detail; verify)
- Unverified from docs, based on known sclang behaviour (LOW-MEDIUM, listed with "(verify)"): OSC strings arriving as Symbols; `s.sync` requiring a Routine; sclang `.load` returning nil on compile errors; running synths keeping the old SynthDef definition after re-add; local-variable limit per function. Each should get a one-line smoke check in P-Core before being relied on.

---
*Pitfalls research for: generative variety, runtime module loading, palette hot-swap and density control in a live SuperCollider pattern engine (PedalPulse v2.0)*
*Researched: 2026-10-11*
