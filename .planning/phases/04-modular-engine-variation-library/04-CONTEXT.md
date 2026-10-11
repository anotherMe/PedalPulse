# Phase 4: Modular Engine & Variation Library - Context

**Gathered:** 2026-10-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Split the v1.0 engine into a core (`main.scd` plus `core/` modules) and a `supercollider/library/` of named variation files (`progressions/`, `melodies/`, `palettes/`, each with a `classic.scd`). Add safe loading, select/reload by name over OSC (`/pp/progression`, `/pp/palette`, `/pp/melody` taking `auto` or a file stem), fallback on broken files, a library check run with the smoke suite, and idempotent re-evaluation (ENG-05). Default startup sounds exactly like v1.0. No new musical behaviour (harmony, palettes, melodies, structure) belongs here; those are Phases 6-9. GUI selectors are Phase 5.

</domain>

<decisions>
## Implementation Decisions

### Proving "sounds like v1.0"
- **D-01:** Parity is proven two ways: an **automated note-level comparison** plus a **short listening check by the user** at the end of the phase. The automated check records what v1.0 plays per layer (instrument, notes/midinote, dur, timingOffset, legato, amp and the effective amp, out/group routing) before the split, and asserts the split engine with all-`classic` selections emits the same events. Both are required; neither alone is enough.
- **D-02:** The v1.0 reference must capture the **effective** amp per layer. In v1.0, kick/hat/bass set no `\amp` and get the default event amp 0.1 (overriding the SynthDef default), while clap/arp/pad set `\amp` explicitly (see `supercollider/main.scd` comment above `Pbindef(\ppClap`). The `classic` files must reproduce exactly this, not "fix" it.
- **D-03:** BPM glide, Start/Stop, EPIC zones and volume must behave exactly as in v1.0. The existing smoke checks stay green unchanged, apart from the deliberate addition of the 7th layer to the expected layer sets.

### The 7th layer (lead)
- **D-04:** Add the lead layer `\ppLead` now as the 7th entry in `~ppLayers`, with full wiring: `~ppMixBus` through the limiter, `~ppInstrGroup`, obeys Stop/gate, self-frees, and is covered by the ENG-05 re-evaluation and Stop checks. — **Reversibility:** costly — the layer list and smoke expected-sets are shared by every later phase.
- **D-05:** `library/melodies/classic.scd` = pure v1.0: the lead is **silent** (rests or no events), so all-`classic` is note-for-note v1.0.
- **D-06:** A second melody file, **`library/melodies/classic_lead.scd`**, makes the lead **double the arp line one octave up at a faint level**, well below the arp, adding shimmer without reading as a new part. It reuses the v1.0 arp voice character unless a different simple voice sounds better at the listening check. This is the first non-`classic` library file and doubles as the live proof that selecting by name works.
- **D-07:** **Startup defaults to `classic`** for all three categories, so `main.scd` sounds exactly like v1.0 and the automated parity check runs against the default startup. The user hears the lead by sending `/pp/melody classic_lead` (one OSC message until the Phase 5 GUI selectors exist). The phase should document that one-liner (e.g. via `python_app/osc_client.py` or a tiny script).

### Claude's Discretion
The user didn't discuss these areas. Claude uses the defaults below, and the planner may refine them:
- **Reload semantics:** re-selecting a name (even the current one) re-reads that file from disk. No separate `/pp/reload` address unless planning finds a clear need. `auto` in Phase 4 resolves to `classic`, since only classic-family entries exist. A selection applies on a bar boundary, never mid-bar, with no gap in playback.
- **Broken-file fallback:** if a file fails to load or validate, the engine posts an error naming the file and keeps the **last good copy** of the current selection; if there is none, it uses `classic`. The music never stops. Unknown names or names that break the stem rules (`^[a-z0-9_]+$`, `auto` reserved, path kept inside the library root) are ignored with a warning.
- **Never-overwrite guard (LIB-03):** besides Claude's convention, the library check should **fail if a library file that is already committed in git has been modified** (compared against HEAD), so an accidental overwrite is caught. New, uncommitted files pass. `_template.scd` and dot-files are skipped as selectable entries.
- **Lead level:** the exact `classic_lead` amp is tuned by ear at the listening check, starting faint, roughly -12 dB or more under the arp.
- **Library check shape:** a separate `library_test.scd` (not an extension of the 1,920-line `smoke_test.scd`), run together with the smoke suite from one command. Keep the total runtime reasonable.
- All loader, registry and plan mechanics follow `.planning/research/ARCHITECTURE.md`. The phase includes the research VERIFY probes listed in STATE.md: `Pbindef.quant = 4` surviving `doReset: true`, `thisThread.beats` inside Plazy equal to bar start, and per-(song, bar, role) seeding.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/ROADMAP.md` §"Phase 4: Modular Engine & Variation Library" — goal, 5 success criteria, standing exit gate
- `.planning/REQUIREMENTS.md` — LIB-01..LIB-06, ENG-05; Out of Scope table (no file watcher, no engine→GUI channel)
- `.planning/PROJECT.md` — constraints, Key Decisions table
- `.planning/STATE.md` §Decisions / §Blockers — v1.0 invariants (sole tempo writer `~ppRampStepper`, Stop = gate broadcast, `~ppLayers` list, ≤3 osc + 1 filter, `~ppMixBus` through the limiter) and the Phase 4 research VERIFY flags

### v2.0 research (contract, mechanisms, pitfalls)
- `.planning/research/SUMMARY.md` — consolidated findings and resolved disagreements (folder names, `auto`, stem regex, OptionMenu, separate test file, defs-on-prepare)
- `.planning/research/ARCHITECTURE.md` — core/library split, loader registry `~ppLib[category][stem]`, library file contract per category, conductor/plan, per-layer Plazy rendering, `~ppRoot` capture
- `.planning/research/PITFALLS.md` — P1 `nowExecutingPath` nil in `waitForBoot`, P2 invariant bypass, P4 Pbindef phase drift, P5 routine stacking, P8 smoke runtime, name drift
- `.planning/research/STACK.md` — verified SC 3.14.1 behaviours (`String:load`, Pbindef quant, OSC string args arrive as Symbol, `unset QT_QPA_PLATFORM`)

### Existing engine and tests
- `supercollider/main.scd` — v1.0 engine to split; the source of truth for parity
- `supercollider/smoke_test.scd`, `scripts/smoke_test.sh` — existing headless harness (isolated muted server on port 57140) that must stay green

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `supercollider/main.scd` lines ~35-70: the idempotent re-evaluation block (`~ppWasPlaying`, teardown) is the starting point for ENG-05 across modules.
- `~ppLayers = [\ppKick, \ppHat, \ppClap, \ppBass, \ppArp, \ppPad]` (line 49): the single layer list. `\ppLead` is appended here.
- `~ppStart` / `~ppStop` (line ~316): the transport that every layer and new routine must register with.
- The SynthDefs `\ppKick \ppHat \ppBass \ppClap \ppArp \ppPad` and the per-layer Pbindefs (lines 248-310) become the content of the `classic` files (palette = voices, progression/melody = notes).
- `scripts/smoke_test.sh`: one-command runner pattern (sclang path override, timeout, log) to extend or mirror for the library check.
- `python_app/osc_client.py`: existing send path; it can send the one-off `/pp/melody classic_lead` test message.

### Established Patterns
- OSCdefs are loopback-only (`srcID`), boot-gated, and posted with their port. The new `/pp/progression|palette|melody` addresses follow the same pattern.
- Latest-wins, applied on a musical boundary (from `/pp/bpm`); selections should behave the same way.
- Voices write to `~ppMixBus` in `~ppInstrGroup`, have a `gate` and use `doneAction: 2`. EPIC FX stays in `\ppFx`; only `\ppRampStepper` writes tempo.

### Integration Points
- `main.scd` captures `~ppRoot` at the top and loads `core/*.scd` and the library via absolute paths.
- The smoke expected-layer sets gain `\ppLead`.
- Phase 5 GUI depends only on the folder layout plus the three OSC addresses and their `auto` or stem argument, so freeze both here.

</code_context>

<specifics>
## Specific Ideas

- "Faint, just adds shimmer": the doubled lead should thicken the arp an octave up, not be heard as a separate melody.
- Selecting pure `classic` must always return the exact v1.0 sound. This is the user's "I can always switch back" guarantee.

</specifics>

<deferred>
## Deferred Ideas

None. The discussion stayed within the phase scope. The real lead melody is already planned for Phase 8.

</deferred>

---

*Phase: 04-modular-engine-variation-library*
*Context gathered: 2026-10-11*
