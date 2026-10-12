# Phase 6: Shared Harmony & Progressions - Context

**Gathered:** 2026-10-12
**Status:** Ready for planning

<domain>
## Phase Boundary

One chord progression drives every pitched layer. Bass, arp and pad (and the lead layer that already exists) play over the same current chord, with no clashes at chord changes, including during BPM glides and after Stop/Start. Pad chords move to the nearest voicing of the next chord. At least 6 named progressions plus `classic` ship in `supercollider/library/progressions/`. On Auto the engine rotates progressions itself. A named pick switches at the end of the current progression cycle and stays until another choice is made. The standing exit gate holds (Stop silences everything, re-evaluation stacks nothing, smoke suite and library check pass).

Not in this phase: new arp patterns or a real lead melody (Phase 8), palette/sound changes (Phase 7), sections, density and fills (Phase 9), key lifts (HARM-05).

</domain>

<decisions>
## Implementation Decisions

### Arp and lead under new chords
- **D-01:** When a non-classic progression plays and Melody is `classic` (or any existing melody file written for A minor), **the arp follows the chords**. The engine maps the melody's notes onto the current chord: the classic A3–C4–E4–C4 shape becomes root–third–fifth–third of whatever chord is playing. Under the `classic` progression the result must be note-for-note identical to v1.0. The frozen melody files are **not edited**; the core does the mapping. — **Reversibility:** costly — every later melody file (Phase 8) and the chord-follow smoke check will rely on how chord-relative mapping works.
- **D-02:** The **same rule applies to the lead** (`classic_lead`, `classic_lead_loud`): its notes follow the current chord exactly like the arp's, so nothing pitched ever clashes with the progression.
- **D-03:** Phase 6 changes **only the notes**, not the rhythm or pattern. The arp keeps its 16th-note shape. New arp patterns stay in Phase 8 (MEL-02).

### Progression content
- **D-04:** The first progressions are a **broad trance mix**: mostly uplifting and driving (the research list's Anthem i–VI–III–VII, Rocker i–VII–VI–VII, Lift i–VI–VII–VII, Return i–III–VII–VI), plus at least one deep/hypnotic one (e.g. Deep i–i–VI–VII) and one dark/melancholy one (e.g. Melancholy i–v–VI–iv). At least 6 named files plus `classic`. Each must sound clearly distinct (the "variations must be audible" rule).
- **D-05:** **Drama (i–iv–VI–V, Am Dm F E) ships too**, with the E **major** chord (G#). The chord data must therefore carry each chord's actual notes, not just "a degree of A minor". The arp and pad play the G# on that chord. Phase 8's lead will need per-chord scales because of this; the plan should expose enough chord information (actual pitch classes per chord) for that.
- **D-06:** **Chord pace is set per file**: driving progressions change chord every bar (4-bar cycle), deeper ones every 2 bars (8-bar cycle). Pace is part of what makes files sound different.
- **D-07:** **Everything plays in the key of A**, as in v1. Progression files are written relative to the key (key-independent), and the engine supplies the key root A. Switching progressions never jumps key. Key lifts stay deferred (HARM-05).

### Auto behaviour
- **D-08:** On Auto, one progression plays for **about 2–3 minutes** (a few complete cycles, roughly 32–64 bars at ride tempos), and the change always lands **at the end of a cycle**, never mid-cycle.
- **D-09:** **Start on `classic`, then rotate.** On Auto the first progression is `classic` (familiar opening; all-classic still sounds exactly like v1.0), then Auto moves on to the others. `classic` stays part of the rotation.
- **D-10:** Auto picks the next progression by **shuffle with no quick repeats**: random, but never the current one or the last couple played. Any new progression file in the library joins the rotation automatically, with no list to maintain.
- **D-11:** Each progression change (Auto or manual) **prints a post-window line naming the progression and its chords** (e.g. `progression anthem: Am F C G`), so the rider can name what they heard when giving feedback. The app stays send-only.

### Bass and pad
- **D-12:** The bass keeps the **v1 rolling offbeat-eighths rhythm**, now on each chord's **root**. Bass variety (rolling 16ths, octave pops) belongs to palettes and density (Phases 7 and 9), not to progression files.
- **D-13:** Like v1's C on the last eighth of the bar, the bass plays a **pickup note on the last eighth before a chord change that steps toward the next chord**. When the chord doesn't change, it plays whatever the planner judges to fit v1's feel. Under `classic` the bass must stay exactly v1 (A1 ×3, C2 at the bar end).
- **D-14:** The pad **holds each chord for as long as the chord lasts** (2 bars on a 2-bar chord), using the voicing nearest the previous chord (HARM-03). It re-attacks only when the chord changes. Under `classic` the pad must stay exactly v1 (Am / Am with passing F, one per bar).

### Claude's Discretion
- **Data shape of a progression file:** follow `.planning/research/ARCHITECTURE.md` "Progression" (chords as key-relative roots plus quality or explicit intervals, bars per chord), adjusted so out-of-key chords like Drama's E major are representable (D-05). Planning decides whether bass/pad stay per-file generators reading `plan[\chord]` or become core defaults that progression files can still override. Either way the existing generator contract (`{ |plan, state| }` → rows) and the validator must keep accepting the frozen `classic.scd`, which has no chord data.
- **`classic` progression's chord:** `progressions/classic.scd` is frozen and has only bass/pad generators. The core must treat it as "Am every bar" (implicit chord data supplied by the core, or an equivalent) so arp/lead mapping (D-01) is the identity under classic.
- **How notes are mapped onto chords (D-01/D-02):** e.g. interpret notes relative to Am (the key chord) as chord-tone positions and re-voice them on the current chord in the same register. Notes that are not Am chord tones (passing tones) need a sensible rule. Planning picks the rule; the bar is "no clashes, and identical to v1 under classic".
- **Same-beat ordering:** STATE.md flags a spike on harmony-vs-layer ordering at the same beat across Stop/Start and tempo glide. Follow the research "memoized per-bar plan, layers pull" pattern (no mutable current-chord variable), and include that spike.
- **Cycle-end switching:** a named pick waits for the current cycle's end (HARM-04). The longest cycle should stay short enough for auditioning (about 8 bars, ≈15 s at 128 BPM; flag it if a file is longer). How `auto` interacts with the Phase 4 `~ppSelect` code (which today posts "resolves to classic") is the planner's call.
- **Progression file names:** lowercase stems in the research spirit (`anthem`, `rocker`, `lift`, `return`, `deep`, `melancholy`, `drama`). Final names are up to the planner, within the stem rule `^[a-z0-9_]+$`.
- **Exact Auto timing:** "a few cycles ≈ 2–3 minutes", counted in song bars so Stop pauses it. Jitter is optional.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements and scope
- `.planning/REQUIREMENTS.md` — HARM-01..04 (this phase); HARM-05/06 and MEL-05 deferred
- `.planning/ROADMAP.md` §"Phase 6: Shared Harmony & Progressions" — success criteria and the standing exit gate
- `.planning/STATE.md` §"Blockers/Concerns" — Phase 6 spike on same-beat ordering of harmony vs layers across Stop/Start and tempo glide

### Design research
- `.planning/research/ARCHITECTURE.md` — library file contract (§"Progression"), plan schema (`chord`, `nextChord`, `scale`), Pattern 1 "memoized per-bar plan, layers pull", Pattern 2 selection/rotation policy, Anti-Pattern 2 (no mutable current chord), chord-follow smoke check
- `.planning/research/FEATURES.md` §"Progressions common in the genre" — the progression list (Anthem, Rocker, Lift, Return, Late arrival, Deep, Melancholy, Drama), pad voice-leading, chord pace
- `.planning/research/PITFALLS.md` — pitfalls for the engine work (seeding, bar-boundary races)

### Prior phase decisions
- `.planning/phases/04-modular-engine-variation-library/04-CONTEXT.md` — classic parity (D-01/D-02), lead layer (D-04..D-07), reload/fallback semantics
- `.planning/phases/05-library-selectors-in-the-gui/05-CONTEXT.md` — GUI sends `auto` at launch, exact stems, rescan on open
- `supercollider/library/README.md` — the never-edit rule and how the rider picks variations (needs a Phase 6 update for progressions and Auto)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `supercollider/core/render.scd` `~ppPlanFor`: today returns `(bar, songBar, phraseBar, role)`. It is the documented seam for adding optional keys (`chord`, `nextChord`, `scale`, cycle position). Existing keys never change meaning.
- `supercollider/core/render.scd` `~ppRenderBar` / `~ppRunGenerator`: per-bar rendering with try/fallback to classic and per-(song, bar, role) seeding. The arp/lead chord mapping (D-01/D-02) hooks in here or in the plan.
- `supercollider/core/render.scd` `~ppResolveStem`: maps `\auto` to `classic` today. Auto rotation (D-08..D-10) replaces this for progressions.
- `supercollider/core/loader.scd` `~ppSelect`: request tokens, load-then-select, refusal keeps the last good copy. Today it applies on the next bar. Phase 6 must defer progression switches to the cycle end (HARM-04).
- `supercollider/core/validate.scd`: the progression check currently requires a bass or pad generator. It must accept chord-data files and the frozen `classic.scd`.
- `supercollider/library/progressions/_template.scd`: must gain a chord-data example (new template content; `_template` is not a selectable entry).

### Established Patterns
- Committed library files are never edited (`scripts/check.sh` guards against HEAD), so `classic.scd` stays as it is and new behaviour comes from the core plus new files.
- Layers are `Pbindef`s in `~ppLayers` driven by a per-bar `Prout` on `~clock`, `quant = 4`. Changes land on bar lines.
- `role -> category`: bass/pad come from `progressions`, arp/lead from `melodies` (`~ppRoleCategory`).
- Startup default in `main.scd`: `~ppSel = (progressions: \classic, ...)`; the GUI then sends `auto` for all three at launch.
- Post-window messages go through `~ppLog` with the `PedalPulse:` prefix.

### Integration Points
- `supercollider/main.scd` OSC `/pp/progression` → `~ppSelect` (frozen address, unchanged).
- `supercollider/smoke_test.scd` and `supercollider/library_test.scd` via `bash scripts/check.sh`: add the chord-follow check (every pitched event's pitch class is in its own bar's chord) and checks for every new progression file.
- Python app: no changes expected. New files appear in the Progression dropdown automatically (Phase 5).

</code_context>

<specifics>
## Specific Ideas

- The user is not a SuperCollider musician and judges by ear in plain words. Each progression must sound clearly different, and the post-window line (name + chords) is how they name what they heard.
- "Classic always brings back v1" stays absolute: all-classic is note-for-note v1.0, including bass pickup and pad passing tone.
- The user chose to include Drama now, even though its E major chord means the Phase 8 lead needs per-chord scales.

</specifics>

<deferred>
## Deferred Ideas

- Files choosing their own key: rejected for now. Everything stays in A; key lifts remain HARM-05.
- Per-progression arp shapes or bass rhythms: rejected for this phase. Arp patterns are Phase 8 (MEL-02); bass variety goes with palettes and density (Phases 7 and 9).

</deferred>

---

*Phase: 06-shared-harmony-progressions*
*Context gathered: 2026-10-12*
