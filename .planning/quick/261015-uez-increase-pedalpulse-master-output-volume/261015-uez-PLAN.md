---
phase: 261015-uez-increase-pedalpulse-master-output-volume
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - supercollider/main.scd
  - supercollider/smoke_test.scd
  - README.md
autonomous: true
requirements: [GUI-03, ENG-02]

estimate:
  tokens: 45000
  raw_tokens: 45000
  tasks: 2
  confidence: low

must_haves:
  truths:
    - "With the app's volume slider at 100, the engine's output is 2.5x the old amplitude (about +8 dB, more than the 'at least double' the rider asked for) wherever the music stays under the limiter: the smoke log's 'output peak at volume 100' at EPIC 10 reads about 0.6 where it read 0.24 before"
    - "The output never goes above the -1 dBFS limiter ceiling (0.892 with tolerance) at EPIC 100 + volume 100 with the boost applied (ENG-02), proven by the smoke suite and by the palette meter's VO2 headroom gate"
    - "The volume slider still follows the same squared taper (volume 50 gives about 0.25 of volume 100's level) and volume 0 is still silent"
    - "The boost is one named constant, ~ppMasterBoost, in supercollider/main.scd; the rider changes it by editing that one line and evaluating the whole file again, and README.md says how"
    - "The Python app and the OSC protocol are unchanged: the boost cannot be set over OSC"
  artifacts:
    - path: "supercollider/main.scd"
      provides: "~ppMasterBoost (2.5) and a boost control in SynthDef(\\ppMaster) applied before the limiter"
      contains: "~ppMasterBoost = 2.5;"
    - path: "supercollider/smoke_test.scd"
      provides: "'master boost' smoke check: config range, live wiring, gain and limiter ceiling with the boost"
      contains: "master boost"
    - path: "README.md"
      provides: "plain-language note on the louder default and how to retune it"
      contains: "ppMasterBoost"
  key_links:
    - from: "supercollider/main.scd (~ppMasterBoost)"
      to: "~ppMasterSynth"
      via: "the \\boost argument in Synth(\\ppMaster, [...])"
      pattern: "\\\\boost, ~ppMasterBoost"
    - from: "SynthDef(\\ppMaster) boost control"
      to: "Limiter.ar(sig, 0.891251, 0.01)"
      via: "boost multiplies sig before the limiter, never after it"
      pattern: "Limiter\\.ar\\(sig, 0\\.891251, 0\\.01\\)"
---

<objective>
Make PedalPulse clearly louder so it can be heard next to Zwift without turning the Mac's volume way up. The user's report: with the app's volume slider at max they still have to raise the OS volume so much that Zwift's sound effects get too loud, and they ask for "at least double" the volume.

Approach: one fixed, documented master makeup gain, `~ppMasterBoost = 2.5` (2.5x amplitude, about +8 dB), applied inside `SynthDef(\ppMaster)` before the existing -1 dBFS limiter. The limiter stays, so the output still cannot clip (ENG-02). The volume taper, the OSC protocol and the Python app do not change.

Why 2.5 (measured from the last passing smoke and palette logs, 2026-10-13): at EPIC 10 and volume 100 the output peak was 0.24, so 2.5x gives about 0.6, still under the limiter. At EPIC 100 and volume 100 the palettes peaked at 0.48 to 0.67, so the loudest hits now go into the limiter by about 3 to 5 dB. That is the job the limiter exists for, and it is light enough to avoid audible pumping. Going above 3.0 would squash the loud EPIC levels harder, and at about 3.5 the smoke check "volume scales output" (it requires the EPIC 10 peak at volume 100 to stay under 0.85) would fail.

Purpose: Core value, the rider actually hears the music move. Memory: the user judges by ear and wants changes to be clearly audible, and wants the app kept simple.
Output: the boost in supercollider/main.scd, a "master boost" smoke check in supercollider/smoke_test.scd, a short README note, and the full engine gate passing.
</objective>

<execution_context>
@.claude/gsd-core/workflows/execute-plan.md
@.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.claude/CLAUDE.md
@supercollider/main.scd
@README.md

<interfaces>
Current master chain in supercollider/main.scd (as of HEAD fce8253):
- line 48: `~preGain = 1.0;` is the D-17 debug pre-limiter gain. It is a debug knob, "Reset to 1.0 afterwards". Do NOT reuse it for the boost: the smoke test sets `\preGain` to 1, 0, 8 and back to `~preGain` on the live master.
- lines 59-63: the GUI-03 comment and `~ppVolumeAmp = { |v| (v / 100).squared };`. The comment still says slider 100 is unity gain and can never raise the level; that claim becomes false with this task.
- lines 112-120: `SynthDef(\ppMaster, { |in, out = 0, preGain = 1, volumeBus = 0| ... var sig = In.ar(in, 2) * preGain * volume; Out.ar(out, Limiter.ar(sig, 0.891251, 0.01)); })`
- line 217: `~ppMasterSynth = Synth(\ppMaster, [\in, ~ppFxBus.index, \out, 0, \preGain, ~preGain, \volumeBus, ~ppVolumeBus.index], ~ppMasterGroup);`
- line 394: the /pp/volume handler log `"PedalPulse: /pp/volume % -> % (gain %)"` prints `~ppVolumeAmp.(~volume)` only. Nothing in scripts/, python_app/ or the tests parses this line.

Smoke harness pieces in supercollider/smoke_test.scd that the new check reuses:
- `checkOk.(name)` prints "CHECK OK: <name>"; `fail.(name, detail)` throws and ends the run with "SMOKE FAIL: <name>: <detail>".
- `\ppDcSource` (test-only) writes a constant 0.5 on both channels of `out`.
- `\ppLevelProbe` (test-only) reports channel 0 of an audio bus at 100 Hz through '/pp/test/ctl'; `ctlOSCdef` appends `[value, count]` to `ctlSamples` while `ctlSamples` is not nil.
- The "volume glides" block (lines ~1588-1647) builds an isolated `\ppMaster` on scratch buses with `\preGain, 1` and NO boost argument, and expects the output at exactly 0.5. The new SynthDef control's default MUST therefore be 1.
- "volume scales output" (lines ~632-687) fails if the EPIC 10 output peak at volume 100 is 0.85 or more. With a 2.5 boost it is about 0.6.
- Watchdog: 480 s (line 32); scripts/smoke_test.sh kills the run at 510 s. Keep the new check under about 3 s of wall time.

supercollider/palette_meter.scd needs NO change. Its level gate reads the post-FX bus, which comes before the master. Its VO2 headroom gate (output peak 0.892 or less and above 0.1) is still guaranteed by the limiter. It runs inside scripts/check.sh.
</interfaces>
</context>

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: Master loudness boost wired end to end (~ppMasterBoost -> \ppMaster -> limiter -> bus 0), proven by a new "master boost" smoke check</name>
  <files>supercollider/main.scd, supercollider/smoke_test.scd</files>
  <behavior>
    - The config gate passes only when ~ppMasterBoost is a number from 2.0 to 3.0. The 2.0 floor is the user's "at least double"; the 3.0 ceiling is the documented squash limit.
    - The running ~ppMasterSynth reports a boost control equal to ~ppMasterBoost (within 1e-4), so the value is really wired into the live master.
    - An isolated scratch \ppMaster with DC 0.5 in, preGain 0.8 / ~ppMasterBoost, boost ~ppMasterBoost and volume 1.0 settles at 0.4 (within 0.01). The same setup without the boost would read 0.16 at a 2.5 boost, so the check catches a boost that is never applied.
    - The same scratch master with preGain 1 (0.5 x boost, at least 1.0 before the limiter) settles from 0.85 up to 0.892: the -1 dBFS ceiling holds with the boost (ENG-02, D-16).
    - Every existing smoke check still passes, in particular "volume glides" (a scratch master without a boost argument stays at unity), "volume scales output", "limiter ceiling" and "max epic max volume no clip".
  </behavior>
  <action>
Write the smoke check first, then change the engine. A red run is optional: the full smoke suite takes several minutes.

1. supercollider/smoke_test.scd: add a new self-contained block named "master boost". Put it directly after the "volume glides" block (which ends with `checkOk.("volume glides");` and `}.value;`) and before the "B6: node-leak bound" block. Copy the local-var / scratch-bus style of "volume glides".
   (a) Config range: fail("master boost", ...) unless `~ppMasterBoost.isNumber` and it is from 2.0 to 3.0 inclusive.
   (b) Live wiring: call `~ppMasterSynth.get(\boost, ...)` with a callback that stores the reply in a local. Poll every 0.02 s for up to 1 s. Fail if there is no reply, or if the value differs from ~ppMasterBoost by 1e-4 or more.
   (c) Gain probe: allocate a scratch stereo audio in bus, a scratch stereo audio out bus, and a scratch control volume bus set to 1.0, plus `Group.new(s, \addToTail)`. Start `\ppDcSource` at the group head writing the in bus. Place `Synth.after(dc, \ppMaster, ...)` with `\in`, `\out` (the scratch buses), `\preGain` equal to `0.8 / ~ppMasterBoost`, `\boost` equal to `~ppMasterBoost` and `\volumeBus` equal to the scratch volume bus index. Put `\ppLevelProbe` at the group tail reading the out bus. Set `ctlSamples = List.new`, wait 0.4 s, then copy ctlSamples into a local list for the gain window.
   (d) Ceiling probe: `.set(\preGain, 1)` on the scratch master. Now 0.5 x boost is at least 1.0 before the limiter. Set `ctlSamples = List.new`, wait 0.4 s, and copy the samples into a second local list.
   (e) Clean up before any assertion, in the same order as "volume glides": free the scratch group, then the three buses, then set `ctlSamples = nil`.
   (f) Assert. Each window must have at least 5 samples. The last 5 gain-window values must each be within 0.01 of 0.4. The last 5 ceiling-window values must each be from 0.85 up to 0.892. Post one informational line in the form "PedalPulse smoke: master boost % -- gain probe %, ceiling probe %" (the boost, the last gain sample, the last ceiling sample). Then `checkOk.("master boost")`.
   Do not change any existing check, threshold, the watchdog, or the test-only SynthDefs. Total added wall time is about 1 s.

2. supercollider/main.scd, the engine change. The Python app and OSC protocol stay untouched. The boost is a file constant only, with no new OSCdef or address.
   (a) Right after the `~ppVolumeAmp` line, add `~ppMasterBoost = 2.5;` at top level with a short plain-language comment block. The comment should say:
      - it is a fixed master loudness boost (makeup gain) that multiplies on top of the volume taper inside \ppMaster, before the -1 dBFS limiter, so the output still never clips (ENG-02, D-16);
      - 2.5 is about +8 dB, more than the "at least double" asked for in quick task 261015-uez, so PedalPulse can be heard next to Zwift without turning the Mac's volume way up;
      - at EPIC 100 + volume 100 the loudest hits now reach the limiter by a few dB, which is intended;
      - to retune, edit this one line and evaluate the whole file again; 1.0 is the original level;
      - keep it at or below 3.0, because higher values make the limiter flatten (pump) the loud EPIC levels, and from about 3.5 the smoke check "volume scales output" fails.
      Unlike ~preGain, this is the shipped default, not a debug knob. Like ~preGain, a re-evaluation re-reads it from the file.
   (b) Rewrite the GUI-03 comment above ~ppVolumeAmp so it no longer says slider 100 is the loudest gain the engine applies. It should say that 100 maps to 1.0, the top of the taper (80 = 0.64, 50 = 0.25), and that ~ppMasterBoost multiplies on top inside \ppMaster. Keep the existing "change only this line" guidance for a linear map. Leave `~ppVolumeAmp` itself unchanged.
   (c) SynthDef(\ppMaster): add a control `boost = 1`. The default MUST be 1 so the smoke test's isolated scratch master, which omits it, stays at unity. Multiply it into `sig` together with preGain and volume, BEFORE `Limiter.ar(sig, 0.891251, 0.01)`. The limiter line stays exactly as it is. Extend the existing comment to say boost is a fixed gain stage before the limiter, like preGain and volume.
   (d) Instantiation of `~ppMasterSynth`: add `\boost, ~ppMasterBoost` to the argument list. Do not touch `\preGain, ~preGain`.
   (e) /pp/volume handler log: print the effective master gain, `(~ppVolumeAmp.(~volume) * ~ppMasterBoost).round(0.001)`, so the post window shows what is really applied. Keep the "PedalPulse: /pp/volume % -> % (gain %)" wording.

3. Run the smoke suite (see verify) and read the measured lines from its log: "output peak at volume 100", "VO2 + volume 100", "peak at preGain 1" and the new "master boost" line. Record them for the SUMMARY.
  </action>
  <verify>
    <automated>bash scripts/smoke_test.sh >/dev/null 2>&1 && grep -qx "CHECK OK: master boost" "${TMPDIR:-/tmp}/pedalpulse-smoke.log" && grep -qx "CHECK OK: volume glides" "${TMPDIR:-/tmp}/pedalpulse-smoke.log" && grep -qx "CHECK OK: max epic max volume no clip" "${TMPDIR:-/tmp}/pedalpulse-smoke.log" && grep -qx "SMOKE PASS" "${TMPDIR:-/tmp}/pedalpulse-smoke.log" && grep -E "master boost|output peak at volume 100|VO2 \+ volume 100" "${TMPDIR:-/tmp}/pedalpulse-smoke.log"</automated>
  </verify>
  <acceptance_criteria>
    - `grep -nF '~ppMasterBoost = 2.5;' supercollider/main.scd` shows the top-level assignment (a line number before the `s.waitForBoot` line)
    - `grep -cF '\boost, ~ppMasterBoost' supercollider/main.scd` >= 1
    - `grep -cF 'Limiter.ar(sig, 0.891251, 0.01)' supercollider/main.scd` >= 1 (ceiling and lookahead unchanged)
    - `grep -cF 'never a boost' supercollider/main.scd` == 0 (the stale unity claim is gone)
    - `grep -cF '"master boost"' supercollider/smoke_test.scd` >= 1
    - `git diff --quiet -- python_app supercollider/palette_meter.scd supercollider/library supercollider/golden` exits 0
    - The smoke log line "output peak at volume 100 = X" has X above 0.4 and below 0.85 (it was 0.24 before the boost)
  </acceptance_criteria>
  <done>scripts/smoke_test.sh ends with SMOKE PASS. The log has "CHECK OK: master boost". The live master runs with boost 2.5 before the unchanged -1 dBFS limiter. The output peak at EPIC 10 and volume 100 rose from about 0.24 to about 0.6, and every existing volume and limiter check still passes.</done>
</task>

<task type="auto">
  <name>Task 2: README retune note, then the full engine gate (palette meter VO2 headroom with the boost)</name>
  <files>README.md</files>
  <action>
1. README.md, section "### 3. Ride": add one short paragraph after the existing paragraphs, in plain language for a rider who is not a SuperCollider musician. It should say three things:
   - PedalPulse now plays about 2.5x louder than before, so it can be heard next to Zwift without turning the Mac's volume way up.
   - If it is still too quiet or too loud, open `supercollider/main.scd`, change the number on the `~ppMasterBoost = 2.5;` line (1.0 is the original level; keep it at 3.0 or below), then select the whole file and evaluate it again.
   - A limiter keeps the sound from clipping at any setting.
   Keep it to 2-4 sentences. Do not touch any other README section.
2. Run the full engine gate, scripts/check.sh. It runs the library guard, library_test.scd, the palette meter over every palette on disk, and the smoke suite. The palette meter's VO2 pass measures bus 0 after the boosted master and must still show an output peak of 0.892 or less and above 0.1 for every palette. Record the "PedalPulse meter: vo2 ..." lines (fxpeak and outpeak per palette) for the SUMMARY. Expect outpeak at or just under about 0.89 for every palette now, because the limiter is catching the loudest hits.
3. If any gate fails, fix the cause in main.scd or smoke_test.scd within this task's intent: do not lower the boost below 2.0 and do not remove or weaken a limiter or headroom gate. Then rerun.
  </action>
  <verify>
    <automated>grep -qF '~ppMasterBoost' README.md && bash scripts/check.sh > "${TMPDIR:-/tmp}/pp-uez-check.out" 2>&1 && grep -qx "CHECK PASS" "${TMPDIR:-/tmp}/pp-uez-check.out" && grep -E "PedalPulse meter: vo2|PALETTE PASS" "${TMPDIR:-/tmp}/pedalpulse-palette.log"</automated>
    <human-check>With the engine (supercollider/main.scd) and the app (./run.sh) running next to Zwift, the app's volume slider at 100 and the Mac's volume at its usual Zwift level: PedalPulse is clearly audible, roughly twice as loud as before or more. Move EPIC from Recovery to VO2: the loud levels sound full, with no crackle, clipping or obvious pumping. The volume slider still turns the level down smoothly, and 0 is silent.</human-check>
  </verify>
  <acceptance_criteria>
    - `grep -cF '~ppMasterBoost' README.md` >= 1
    - `bash scripts/check.sh` exits 0 and its last line is "CHECK PASS"
    - Every "PedalPulse meter: vo2" line in `${TMPDIR:-/tmp}/pedalpulse-palette.log` has outpeak of 0.892 or less and above 0.1
    - `git diff --name-only -- . ':!.planning'` lists exactly README.md, supercollider/main.scd and supercollider/smoke_test.scd
  </acceptance_criteria>
  <done>README.md tells the rider the music is louder and how to retune ~ppMasterBoost. scripts/check.sh passes end to end with the boost in place: library guard, library check, palette meter (VO2 headroom held by the limiter on every palette) and smoke suite. The listening check is recorded for the end-of-task human verification.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Python app -> sclang (OSC/UDP, loopback) | Unchanged. /pp/volume is still clamped to 0-100 and loopback-only (srcID guard). The boost is NOT reachable over OSC. |
| engine -> audio output (speakers or headphones) | A gain change can make the output louder. The -1 dBFS limiter is the safety boundary and stays in place. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-261015-uez-01 | Denial of Service (loud burst / clipping at the output) | SynthDef(\ppMaster) gain stage | medium | mitigate | The boost multiplies sig BEFORE `Limiter.ar(sig, 0.891251, 0.01)`, never after. The new "master boost" smoke check proves the ceiling holds (0.892 or less) with at least 1.0 going into the limiter. The existing "limiter ceiling" and "max epic max volume no clip" checks and the palette meter VO2 outpeak gate (0.892 or less) still run in scripts/check.sh. |
| T-261015-uez-02 | Tampering / Elevation (gain raised remotely) | OSC surface | low | mitigate | ~ppMasterBoost is a file constant only: no new OSCdef, address or Python argument. The existing loopback srcID guards and /pp/volume clamp stay unchanged. Task 1 acceptance checks that python_app is unchanged. |
| T-261015-uez-03 | Denial of Service (limiter squash or pumping) | ~ppMasterBoost value | low | mitigate | The boost is fixed at 2.5 (3-5 dB of limiting only on VO2 transients). The smoke config gate rejects values outside 2.0-3.0, and the main.scd comment documents the 3.0 squash ceiling. |
| T-261015-uez-SC | Tampering | npm/pip/cargo installs | low | accept | This task installs no packages. The only runtime pieces are stock SuperCollider and the existing python-osc. |
</threat_model>

<verification>
- `bash scripts/check.sh` ends with "CHECK PASS". This covers the library guard, library check, palette meter (every palette's VO2 output peak is 0.892 or less with the boost) and the smoke suite (including "master boost", "volume scales output", "volume glides", "limiter ceiling" and "max epic max volume no clip").
- `git diff --name-only -- . ':!.planning'` lists only README.md, supercollider/main.scd and supercollider/smoke_test.scd. The Python app, OSC protocol, palette meter, library and golden files are untouched.
- Human listening check (end of task): next to Zwift with the slider at 100, PedalPulse is clearly audible at a normal Mac volume, and VO2 sounds full without clipping or pumping.
</verification>

<success_criteria>
- The master output is 2.5x the old amplitude (about +8 dB, at least the doubling the user asked for) wherever the music is below the limiter: the EPIC 10 output peak at volume 100 is about 0.6, up from 0.24.
- The -1 dBFS ceiling holds at every EPIC and volume setting (ENG-02). The volume taper and silence at 0 are unchanged (GUI-03).
- One documented constant (~ppMasterBoost) retunes the loudness, and README.md explains it in plain language.
</success_criteria>

<output>
Create `.planning/quick/261015-uez-increase-pedalpulse-master-output-volume/261015-uez-SUMMARY.md` when done, with `status: complete` in the frontmatter. Include the measured before/after numbers:
- smoke "output peak at volume 100": 0.242 before;
- "VO2 + volume 100 ... output peak": 0.522 before;
- each palette's vo2 outpeak: 0.479-0.672 before.
</output>
