# Phase 7: Sound Palettes - Context

**Gathered:** 2026-10-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Ship at least 5 named sound palettes plus `classic` in `supercollider/library/palettes/`. Each palette is a coherent set of lead, bass, pad, arp and drum sounds and can also choose a bass-rhythm flavour. On Auto, palettes rotate by themselves, landing on progression changes. Picking a named palette locks it until Auto is picked again. Palettes are loudness-matched (measured, then checked by ear), never bypass the limiter, and the heaviest one at VO2 stays within an agreed CPU budget next to Zwift. The library-hardening items WR-01 and WR-02 from Phase 4 are fixed here.

Not in this phase: new arp/lead patterns (Phase 8), transition effects, fills, and EPIC-driven density (Phase 9), and any GUI change (the Palette dropdown already exists from Phase 5).

</domain>

<decisions>
## Implementation Decisions

### Palette characters
- **D-01:** The first palettes are a **broad trance mix** of about 6 clearly different sound worlds: `anthem` (big supersaw pad and lead), `acid` (squelchy 303-style bass), `warm` (soft analog, round bass), `pluck` (bright digital plucks, crisp drums), `dark` (minimal, gritty, deep kick) and `air` (ethereal, glassy bells, soft pads). Names are working stems; the planner may adjust them within `^[a-z0-9_]+$`. Each must be recognisably different in the full mix (see the "variations must be audible" rule).
- **D-02:** A palette changes **its sounds plus its bass style**. It can pick a bass-pattern flavour such as rolling offbeat eighths (v1), rolling 16ths or octave pops. Phase 6 D-12 handed bass variety to palettes. Drum and arp rhythms stay as they are. Bass notes still follow the chord root and the Phase 6 pickup rule (D-13); `classic` must stay exactly v1. — **Reversibility:** costly — this adds a rhythm-affecting key to the palette file contract, which every later palette and the validator rely on.
- **D-03:** **Every palette has its own pitched voices** (bass, arp, pad, lead). Drums change only where the character needs it (e.g. `dark` gets a deeper kick); roles left out fall back to classic's voice, as the existing `~ppInstrumentFor` already does.
- **D-04:** **A palette supplies only the lead sound.** Whether the lead plays is still decided by the Melody selection (the `classic` melody keeps the lead silent; `classic_lead_loud` makes it audible). A palette never forces the lead on.

### Auto rotation
- **D-05:** On Auto, one palette holds for **about 4–6 minutes**, roughly every second progression change. Count the hold in song bars so Stop pauses it, like progressions.
  - *Approved 2026-10-13 (plan review):* the hold is 80–128 bars (2.9–5.7 min at 90–110 BPM) plus the wait for the next progression change, about 4.7–5.7 min per palette on average and roughly 3–8.5 min for a single palette.
- **D-06:** **A palette change always lands on a progression change**, on the same bar a new progression cycle starts, so the music has a single "new chapter" moment.
  - *Approved exceptions 2026-10-13 (plan review):* (1) the first random palette after Start (D-08) comes in at the next round start rather than waiting for a progression change; (2) if Progression Auto has only one progression it can play, palettes change at the end of its round (as in D-07) and the post window says so once.
- **D-07:** If the progression is locked (no progression changes happen), Palette Auto still rotates on the same ~4–6 min timing, **landing at the end of the locked progression's cycle**.
- **D-08:** **Random from the start.** Palette Auto does *not* open on `classic` (unlike progressions, Phase 6 D-09); the first palette after Start is a random pick. After that it shuffles with no quick repeats (never the current one or the last couple played), and any new palette file joins the rotation automatically. `classic` stays in the rotation. Engine startup with no GUI still defaults to `classic` (Phase 4 D-07), so the all-`classic` parity check is unaffected.
- **D-09:** Every palette change (Auto or manual) **prints a post-window line with the palette's name and its `desc`** (e.g. `palette acid: squelchy 303 bass, ...`), so the rider can name what they heard. The app stays send-only.

### How a switch sounds
- **D-10:** **Old notes ring out naturally.** Notes already playing finish their own release while the new palette's notes start on the downbeat: no hard cut, no gap, no click.
- **D-11:** **A named pick takes over from the next bar** (quick audition, matching the Phase 4 rule). It does not wait for the phrase or cycle end. Only Auto rotation waits for a progression change or cycle end (D-06/D-07).
- **D-12:** **No transition effect.** No sweep or riser on a palette change; transitions belong to Phase 9.

### Loudness & CPU
- **D-13:** **Loudness matching is measured, then checked by ear.** The library check renders each palette headlessly at a fixed EPIC level, compares its level with `classic`, and fails if the gap is more than about 1.5 dB (the planner picks the metric, e.g. RMS over a few bars). After that the rider does a short listening pass, switching palettes, at UAT. VO2 at volume 100 on the loudest palette must still never clip.
- **D-14:** **CPU budget: scsynth `s.avgCPU` below 25%** with the heaviest palette at VO2, calibrated on the riding Mac.
- **D-15:** **Measuring CPU takes one command plus a quick Zwift check.** A script/command locks the heaviest palette at VO2 for about 1 minute and prints average and peak CPU. The rider runs it once with Zwift open (no ride needed) and reports the numbers at UAT. The headless library check also probes CPU per palette and warns before a ride.

### Library hardening
- **D-16:** **Phase 7 fixes both deferred Phase 4 review items.** WR-01: add upper bounds on row values in the validator. WR-02: a refused palette must not leave its SynthDefs behind, and the fallback must restore the classic voices. Both matter once 6+ palettes rotate automatically.

### Claude's Discretion
- **How the bass style reaches the bass layer:** bass rows today come from the progression's generator (`~ppRoleCategory` maps bass to `\progressions`). The planner decides how a palette's bass flavour applies, e.g. a palette key the core bass generator reads, or a palette-supplied rhythm the core combines with the chord roots. The frozen `progressions/classic.scd` and `palettes/classic.scd` must keep producing exactly v1.
- **How Auto palette state works with the progression Auto:** e.g. share the harmony module's cycle-end hook and hold counter, or keep a separate state. The draw counter must survive Stop/Start, like `~ppAutoPicks` (Phase 6 WR-02). Seeding must stay replayable.
- **Prepare ahead:** run a palette's `defs` + `s.sync` before its switch bar (research: one phrase ahead), so the switch bar never waits on the server.
- **A pad held across a next-bar manual switch:** whether the old pad rings to its release and the new pad enters on the switch bar, or waits for the next chord. Either way, no gap and no click (D-10).
- **Voice design:** follow the voice contract in `palettes/_template.scd` and the research CPU guidance (few detuned oscillators on the 16th-note arp, no per-voice reverb/delay; FX stay in the shared `\ppFx`).
- **Exact numbers:** hold-time jitter within 4–6 min, the loudness tolerance (~1.5 dB) and the level metric, and the CPU warning threshold in the headless check.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — PAL-01..PAL-04 (and ENG-05 standing gate)
- `.planning/ROADMAP.md` §"Phase 7: Sound Palettes" — goal and 5 success criteria; standing exit gate for engine phases
- `.planning/PROJECT.md` §Key Decisions — palettes rotate + lockable; WR-01/WR-02 marked "Revisit before Phase 7"

### Architecture & research
- `.planning/research/ARCHITECTURE.md` §"Palette (`library/palettes/<name>.scd`)" — palette file shape, voice contract, prepare-on-demand rationale; library_test CPU probe description
- `.planning/research/PITFALLS.md` Pitfall 6 (node/CPU growth from palettes and rotation) and the loudness/headroom pitfall — budgets, FX-in-core rule
- `.planning/research/STACK.md` item 10 — CPU guidance on the Zwift Mac

### Prior phase decisions
- `.planning/phases/06-shared-harmony-progressions/06-CONTEXT.md` — Auto rotation rules (D-08..D-11), bass rhythm/pickup (D-12, D-13), pad hold (D-14)
- `.planning/phases/05-library-selectors-in-the-gui/05-CONTEXT.md` — GUI sends `auto` on startup; dropdown lists stems
- `.planning/phases/04-modular-engine-variation-library/04-CONTEXT.md` — never-overwrite rule, broken-file fallback, startup defaults to classic
- `.planning/phases/04-modular-engine-variation-library/04-REVIEW.md` and `04-REVIEW-DISPOSITION.md` — WR-01 and WR-02 details

### Library contract
- `supercollider/library/palettes/_template.scd` — voice contract (controls, doneAction 2, Out to bus only, `pp_<palette>_` prefix)
- `supercollider/library/README.md` — how library files are written and checked

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `supercollider/library/palettes/classic.scd`: the reference palette (v1 voices); every new palette is a sibling file.
- `~ppInstrumentFor` in `supercollider/core/render.scd`: resolves role → instrument with classic fallback; already covers D-03's "roles left out use classic".
- Progression Auto in `supercollider/core/harmony.scd` (`~ppHarmAutoNext`, `~ppAutoCandidates`, `~ppAutoHoldBars`, seeded draws via `~ppAutoSeed`/`~ppAutoPicks`, history cap): the pattern to mirror or extend for palette Auto.
- `~ppAutoPrefetch` in `supercollider/core/loader.scd`: loads files on disk ahead of an Auto pick without blocking the bar.
- `~ppSelect` and `~ppSelReq` in `loader.scd`: handle `/pp/palette` names and `auto`. Today palette `auto` "resolves to classic"; this must change.
- `supercollider/core/validate.scd`: has a palette-specific branch and voice checks, the place for WR-01 bounds and palette checks.
- `supercollider/library_test.scd` and `scripts/check.sh`: where the per-palette voice, loudness and CPU checks go.

### Established Patterns
- Memoized per-bar plan; layers pull, and selections are captured at plan time (bar-quantized swaps).
- Library files are never edited once committed (guarded by `check.sh`); a new sound is a new file.
- Every voice goes through `~ppMixBus` → `\ppFx` → `\ppMaster` limiter, in `~ppInstrGroup` so Stop's gate broadcast releases it.
- Post-window lines are the rider's feedback channel; the Python app is send-only.

### Integration Points
- `~ppResolveStem.(\palettes)` currently returns `classic` for `\auto`; palette Auto resolution plugs in here (or into the plan).
- Bass generator path (`~ppRoleCategory`: bass → progressions) for the palette bass flavour (D-02).
- The harmony cycle-start / Auto-change moment, for D-06/D-07 alignment.

</code_context>

<specifics>
## Specific Ideas

- Sound-world references: anthem = big supersaw, acid = squelchy 303 bass, warm = soft analog round bass, pluck = bright digital plucks with crisp drums, dark = minimal gritty deep kick, air = ethereal glassy bells and soft pads.
- The rider is not a SuperCollider musician and gives plain-language feedback; differences must be obvious in the full mix (a faint, 12 dB-down change was inaudible in Phase 4).

</specifics>

<deferred>
## Deferred Ideas

- Transition effects on palette changes (filter sweep, riser): rejected for Phase 7; belongs to song structure in Phase 9.
- A palette forcing the lead on: rejected; the lead stays controlled by the Melody selection (the real lead comes in Phase 8).

</deferred>

---

*Phase: 07-sound-palettes*
*Context gathered: 2026-10-13*
