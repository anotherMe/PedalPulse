---
phase: quick-261010-hyl
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - supercollider/main.scd
  - supercollider/smoke_test.scd
autonomous: true
requirements:
  - GUI-02

estimate:
  tokens: 40000
  raw_tokens: 40000
  tasks: 2
  confidence: low

must_haves:
  truths:
    - "The first evaluation of main.scd in a fresh interpreter (~ppPlaying is nil) still autostarts the groove (D-15)"
    - "Re-evaluating main.scd after Stop leaves the groove stopped: ~ppPlaying is false, no Pbindef layer is playing, and no instrument notes sound on the server"
    - "After a stopped re-evaluation, the next /pp/play 1 (the GUI Start button) starts the groove. The OSCdef \\pp_play idempotency guard no longer swallows it"
    - "Re-evaluating main.scd while playing keeps the groove playing, and the existing teardown/replace guarantees (clock, master, FX, buses, BPM/EPIC/volume preserved) still hold"
    - "The post window's ready line reports whether the groove is playing or stopped after each evaluation"
  artifacts:
    - path: "supercollider/main.scd"
      provides: "Transport state captured before the re-evaluation teardown, and an autostart that runs only if the groove was playing"
      contains: "~ppWasPlaying = ~ppPlaying ? true"
    - path: "supercollider/smoke_test.scd"
      provides: "Headless checks 'autostart', 're-evaluation' (hardened to keep playing) and 're-evaluation stays stopped'"
      contains: "re-evaluation stays stopped"
  key_links:
    - from: "supercollider/main.scd capture line (first statement inside s.waitForBoot)"
      to: "supercollider/main.scd transport init block (the former unconditional autostart)"
      via: "~ppWasPlaying read after the teardown, before ~ppPlaying is reset to false"
      pattern: "~ppWasPlaying"
    - from: "supercollider/main.scd stopped re-evaluation (~ppPlaying = false)"
      to: "OSCdef(\\pp_play) guard `want == ~ppPlaying`"
      via: "the next /pp/play 1 sees want != ~ppPlaying and calls ~ppStart"
      pattern: "want == ~ppPlaying"
---

<objective>
Fix audit finding W1 (GUI-02 tech debt from .planning/v1.0-MILESTONE-AUDIT.md). Today main.scd always autostarts on every evaluation: it sets `~ppPlaying = false; ~ppTransportCount = 0; ~ppStart.value;` with no condition. So when the rider presses Stop and then re-evaluates main.scd, the groove plays again while the GUI still shows "Start", and the next Start click (/pp/play 1) looks like a no-op because the engine already counts as playing.

After this fix, main.scd remembers the transport state across a re-evaluation, the same way it already keeps `~bpm`, `~epic` and `~volume`. The first-ever evaluation still autostarts (D-15). A re-evaluation after Stop stays stopped. A re-evaluation while playing keeps playing. The headless smoke test proves all three.

Purpose: keep the engine's transport in step with the GUI's Start/Stop label, so the GUI → OSC → SC chain behaves as the rider expects (Core Value).
Output: a conditional autostart in supercollider/main.scd, plus three transport smoke checks in supercollider/smoke_test.scd. The Python side does not change: the app stays send-only.
</objective>

<execution_context>
@/Users/marcogiordano/Documents/personali/lab/PedalPulse/.claude/gsd-core/workflows/execute-plan.md
@/Users/marcogiordano/Documents/personali/lab/PedalPulse/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/v1.0-MILESTONE-AUDIT.md
@supercollider/main.scd
@scripts/smoke_test.sh

<interfaces>
Facts observed in the live code at planning time. Use them directly; there is no need to re-explore.

supercollider/main.scd (422 lines):
- Lines 34-422: everything server-side runs inside `s.waitForBoot({ ... })`. The function has NO `var` declarations. Its first statements are the teardown: line 43 `~ppLayers = [...]`, line 44 `~ppLayers.do { |name| Pbindef(name).stop };`, then stepper/clock stop, `0.3.wait`, and frees of master/fx/smoother/groups/buses (lines 53-63).
- Nothing in the teardown writes `~ppPlaying`. Today it is reset only at line 346.
- Lines 310-315: `~ppStart` plays every layer with quant 4, sets `~ppPlaying = true`, increments `~ppTransportCount`, and posts "PedalPulse: started -- groove re-enters on the next bar".
- Lines 317-344: `~ppStop` stops the layers, sets `~ppPlaying = false`, increments `~ppTransportCount`, broadcasts `\gate, 0` to `~ppInstrGroup`, and schedules a second guarded broadcast on SystemClock about 0.25 s later.
- Lines 346-348: the unconditional block this plan replaces. `~ppPlaying = false;`, then `~ppTransportCount = 0;`, then `~ppStart.value;  // D-15: autostart ...`.
- Lines 368-381: OSCdef `\pp_play`. Its guard `if (want == ~ppPlaying)` posts "already playing/stopped" and does nothing.
- Line 420: `"PedalPulse: ready -- groove playing at % BPM, EPIC %, volume % (...)".format(~bpm, ~epic, ~volume).postln;`. "playing" is hardcoded.
- Existing persistence idiom: `~epic = ~epic ? 10;`, `~volume = ~volume ? 80;`, `~bpm = ~bpm ? 120;`. `nil ? x` gives x, and `false ? true` gives false.

supercollider/smoke_test.scd (1830 lines):
- Line 38: `~ppReady = false;` is set before the first load. `~ppPlaying` is never set before the first load.
- Helpers available inside the fork: `fail.(name, detail)` (throws), `checkOk.(name)`, `sendPlay.(int)` (direct /pp/play), `waitForPlaying.(want, timeoutSec)` returns a Boolean, `instrChildCount.()` (/g_queryTree child count of `~ppInstrGroup`), `sendCli.(str)`, `waitForApplyChange`, `waitForTempo`, and `root` (the repo root).
- Line 357: first `(root +/+ "supercollider/main.scd").load;`. Lines 359-369: poll `~ppReady` for up to 30 s, then `checkOk.("boot ready")`. Lines 377-381: "initial tempo 120" check, ending with `checkOk.("initial tempo 120");`.
- Lines 1676-1821: block B8 `{ ... }.value;`. It sends EPIC 75 / volume 35 and captures the old objects. At lines 1710-1711, `~ppReady = false;` then `.load`. It polls ready, then at lines 1722-1729 asserts `~ppPlaying` and every `Pbindef(name).isPlaying`. Both fail messages end with "(autostart should bring it back up)". It then checks the old clock/master/FX/buses/tempo/glide, and ends with `checkOk.("re-evaluation")`, `checkOk.("fx re-evaluation")` and `checkOk.("volume re-evaluation")`.
- Line 1823: `"SMOKE PASS".postln;`. Watchdog at line 28: 300 s. scripts/smoke_test.sh: `timeout 330`, log at `${TMPDIR:-/tmp}/pedalpulse-smoke.log`, exit 0 only on rc 0 plus "SMOKE PASS".
- Every existing `~ppTransportCount` use is a delta (`countBefore` and similar). Nothing depends on its absolute value, so resetting it to 0 on every evaluation stays safe.
- The last green log (2026-10-09) has 65 `CHECK OK:` lines and no SKIP.
</interfaces>
</context>

<source_audit>
| Source | Item | Covered by |
|--------|------|------------|
| GOAL | Engine does not autostart after Stop when main.scd is re-evaluated | Task 1 |
| REQ | GUI-02 (Start/Stop transport): W1 debt | Tasks 1 and 2 |
| CONTEXT | D-15: first evaluation autostarts through the same `~ppStart` path /pp/play uses | Task 1 (conditional keeps the `~ppStart` path), Task 2 ("autostart" check) |
| AUDIT | W1 checks (a) first eval autostarts, (b) re-eval after Stop stays stopped, (c) re-eval while playing keeps playing | (b) Task 1; (a) and (c) Task 2 |
| AUDIT | Keep the `~ppTransportCount` reset-to-0 semantics | Task 1 keeps the reset; Tasks 1 and 2 assert absolute counts |
| SCOPE | Python side needs no changes (send-only app, MEMORY: keep app simple) | No Python files in files_modified |
| OUT | W2 (no resync after an engine restart) and W3 (loopback guard untested) | Not in scope. Separate audit items |
</source_audit>

<tasks>

<task type="tracer">
  <name>Task 1: Stop survives a re-evaluation (engine fix plus "re-evaluation stays stopped" check)</name>
  <precondition>/Applications/SuperCollider.app/Contents/MacOS/sclang is executable (or SCLANG is set) and .venv/bin/python exists. scripts/smoke_test.sh exits 1 without them.</precondition>
  <files>supercollider/smoke_test.scd, supercollider/main.scd</files>
  <action>
This slice runs end to end through both layers this task touches: the engine entry file and its headless regression harness. Do the steps in this order, so the new check is shown to catch W1 before the fix lands.

Step A, the red check (supercollider/smoke_test.scd). Add a new block between the closing `}.value;` of block B8 (just after `checkOk.("volume re-evaluation");`) and `"SMOKE PASS".postln;`. Use the same `{ var ...; ... }.value;` local-block style as its neighbours, and give every failure the check name "re-evaluation stays stopped". The block does the following in order:
1. `sendPlay.(0)`. If `waitForPlaying.(false, 3)` is false, fail with a precondition message saying /pp/play 0 did not stop the engine within 3 s.
2. `0.5.wait`. This lets the SystemClock second gate broadcast that `~ppStop` schedules fire before the teardown frees `~ppInstrGroup`.
3. Set `~ppReady = false`. Load `(root +/+ "supercollider/main.scd")`, then poll `~ppReady` for up to 30 s in 0.5 s steps, using the same loop shape as B8. If it never becomes ready, fail.
4. Assert that the reload left the transport stopped. Fail if `~ppPlaying != false`. This is a strict comparison, so nil also fails. Fail if any `Pbindef(name).isPlaying` is true for a name in `~ppLayers`. Fail if `~ppTransportCount != 0`, meaning `~ppStart` ran during the reload. Each message must include the actual value.
5. Wait `~clock.beatDur * 6` seconds. That is past the next bar line, where a quant-4 autostart would have entered. Then fail if `instrChildCount.()` is not 0. The message should report how many instrument nodes are sounding after a stopped re-evaluation.
6. Prove that the rider's next Start is not swallowed. Call `sendPlay.(1)`. Fail if `waitForPlaying.(true, 3)` is false. Fail if any layer's `Pbindef(name).isPlaying` is false. Fail if `~ppTransportCount != 1`, which would mean the Start did not go through `~ppStart` exactly once.
7. `checkOk.("re-evaluation stays stopped")`.

Then run the unfixed engine once: `scripts/smoke_test.sh`. It must FAIL, and the log must contain `SMOKE FAIL: re-evaluation stays stopped:` (step 4 trips on `~ppPlaying` being true). Record this red result in the SUMMARY. If the run fails anywhere else, or passes, the check is not discriminating. Fix the check before you touch main.scd.

Step B, the fix (supercollider/main.scd), per the W1 audit suggestion and D-15:
1. Make the very first statement inside the `s.waitForBoot({` function, before `~ppLayers = [...]` and before any teardown line, this: `~ppWasPlaying = ~ppPlaying ? true;`. Add a comment explaining it. It is read before the teardown, so nothing can reset it first. nil (a fresh interpreter, the first-ever evaluation) maps to true, which keeps the D-15 autostart. false (the rider pressed Stop) keeps the engine stopped, so it matches the GUI's "Start" label. The `? default` idiom is the same one used for `~epic`, `~volume` and `~bpm`. Use an environment variable, not a function-local `var`. That keeps it consistent with the file's all-`~` style, and the post window can inspect it.
2. Replace the unconditional transport init (the `~ppPlaying = false;` / `~ppTransportCount = 0;` / `~ppStart.value;` lines just above the `/pp/bpm` OSCdef). Keep `~ppPlaying = false;` and `~ppTransportCount = 0;` exactly as they are, so the count semantics do not change. Then add `if (~ppWasPlaying) { ~ppStart.value } { ... }`. The true branch keeps the existing `// D-15: autostart through the same path /pp/play uses` comment. The false branch posts `PedalPulse: was stopped before re-evaluation -- staying stopped (press Start in the app or send /pp/play 1)`. Do not call `~ppStop` in the false branch. The teardown has already stopped every Pbindef and freed the old instrument group, so a `~ppStop` call would only add a spurious count increment and a gate broadcast.
3. Line 420, the ready line: replace the hardcoded word "playing" in `groove playing at` with a format argument, `if (~ppPlaying) { "playing" } { "stopped" }`. Use the same inline-if-in-format style as the `\pp_play` handler. The line then reads `PedalPulse: ready -- groove playing at ...` or `PedalPulse: ready -- groove stopped at ...`. Leave the rest of the line unchanged.
4. Update the "Idempotent re-evaluation" header comment at the top of the waitForBoot function with one sentence: the transport state (playing/stopped) also survives re-evaluation, like `~bpm`, `~epic` and `~volume`.

Do not change any OSCdef, `~ppStart`, `~ppStop`, SynthDef, Pbindef or anything in python_app/.

Then run `scripts/smoke_test.sh` again (use `time scripts/smoke_test.sh` and note the wall time in the SUMMARY). It must pass. Contingency: if a run dies with `SMOKE FAIL: watchdog timeout`, or the wall time comes within 30 s of the 300 s watchdog, raise the watchdog at smoke_test.scd line 28 from 300 to 330. Also raise both the `timeout` and `gtimeout` limits in scripts/smoke_test.sh from 330 to 360, keeping the 30 s gap (the same precedent as Phase 3 plan 03-01). List scripts/smoke_test.sh in the SUMMARY if you touch it.
  </action>
  <verify>
    <automated>awk '/~ppWasPlaying = ~ppPlaying \? true/ && !c {c=NR} /Pbindef\(name\)\.stop/ && !t {t=NR} END {exit !(c && t && c < t)}' supercollider/main.scd && scripts/smoke_test.sh && grep -qx 'CHECK OK: re-evaluation stays stopped' "${TMPDIR:-/tmp}/pedalpulse-smoke.log" && grep -q '^PedalPulse: ready -- groove stopped at' "${TMPDIR:-/tmp}/pedalpulse-smoke.log" && grep -q '^PedalPulse: was stopped before re-evaluation -- staying stopped' "${TMPDIR:-/tmp}/pedalpulse-smoke.log"</automated>
    <human-check>Evaluate main.scd in the SC IDE and launch the app with ./run.sh. Press Stop, then re-evaluate main.scd. The music stays silent, the app still shows "Start", and the post window shows "groove stopped". Click Start: the groove re-enters on the next bar.</human-check>
  </verify>
  <done>
- The red run (new check, unfixed main.scd) failed with `SMOKE FAIL: re-evaluation stays stopped:`, and this is recorded in the SUMMARY.
- `~ppWasPlaying = ~ppPlaying ? true;` is the first statement inside `s.waitForBoot`, before the first `Pbindef(name).stop` teardown line.
- The autostart runs only when `~ppWasPlaying` is true.
- The ready line reports playing or stopped.
- `scripts/smoke_test.sh` exits 0, and the log contains `CHECK OK: re-evaluation stays stopped`, the "staying stopped" post line and a `groove stopped at` ready line.
- All 65 previously passing checks still pass.
  </done>
</task>

<task type="auto">
  <name>Task 2: Prove first-evaluation autostart and keep-playing re-evaluation (checks a and c)</name>
  <files>supercollider/smoke_test.scd</files>
  <action>
Extend supercollider/smoke_test.scd so the two remaining W1 cases are explicit and discriminating. Do not edit main.scd in this task.

1. First-ever evaluation precondition (check a). On the line after `~ppReady = false;` near the top of the file (before the fork), add `~ppPlaying = nil;`. Add a one-line comment: the first load must see a fresh interpreter's nil transport state, which proves the D-15 default rather than a leftover value.
2. "autostart" check (check a). Add a `{ ... }.value;` block right after `checkOk.("initial tempo 120");` and before `venvPython = ...`. Its check name is "autostart". It fails if `~ppPlaying != true` (the first evaluation did not autostart; include the value). It fails if any `Pbindef(name).isPlaying` is false for a name in `~ppLayers`. It fails if `~ppTransportCount != 1` (exactly one `~ppStart` is expected on the first evaluation; include the value). It ends with `checkOk.("autostart")`. No wait is needed: `~ppStart` runs before `~ppReady` is set.
3. Harden the B8 "re-evaluation" block (check c). B8 is the block with `NodeWatcher.register(oldMaster, true)`.
   - Add a precondition immediately before B8's own `~ppReady = false;` / `(root +/+ "supercollider/main.scd").load;` pair. If `~ppPlaying != true`, fail "re-evaluation" with a message saying the engine is not playing before the reload, so the keep-playing assertion would prove nothing.
   - In the two existing post-reload failure messages, the `~ppPlaying.not` one and the per-layer `Pbindef(%) not playing after reload` one, replace the parenthetical "(autostart should bring it back up)" with "(re-evaluation while playing must keep playing)".
   - Right after that per-layer loop, add an assertion that `~ppTransportCount == 1`. A playing re-evaluation resets the count to 0 and then runs `~ppStart` exactly once. The failure message includes the actual count.
   - Leave every other B8, "fx re-evaluation" and "volume re-evaluation" assertion unchanged.

Run `scripts/smoke_test.sh`. If it fails, fix the check that is wrong. Do not weaken an assertion to get it to pass. If a real engine bug shows up, record it in the SUMMARY.
  </action>
  <verify>
    <automated>scripts/smoke_test.sh && L="${TMPDIR:-/tmp}/pedalpulse-smoke.log" && grep -qx 'CHECK OK: autostart' "$L" && grep -qx 'CHECK OK: re-evaluation' "$L" && grep -qx 'CHECK OK: re-evaluation stays stopped' "$L" && grep -qx 'CHECK OK: fx re-evaluation' "$L" && grep -qx 'CHECK OK: volume re-evaluation' "$L" && [ "$(grep -c '^CHECK OK:' "$L")" -ge 67 ] && [ "$(grep -c 're-evaluation while playing must keep playing' supercollider/smoke_test.scd)" -ge 2 ] && grep -q '^~ppPlaying = nil;' supercollider/smoke_test.scd</automated>
  </verify>
  <done>
- `scripts/smoke_test.sh` exits 0 with at least 67 `CHECK OK:` lines (65 before, plus "autostart", plus "re-evaluation stays stopped").
- "autostart" proves that the first-ever evaluation, starting from nil, plays every layer with `~ppTransportCount == 1`.
- "re-evaluation" now asserts that the engine was playing before the reload and that exactly one `~ppStart` ran across it.
- Together with Task 1's check, all three W1 cases (a, b, c) are covered headlessly.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Python app → sclang (UDP 127.0.0.1:57120) | Unchanged. /pp/play stays loopback-only through the existing `srcID` guard. This plan adds no OSC path. |
| Rider → SC IDE (re-evaluating main.scd) | A trusted local action. The plan changes only how transport state carries across it. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-hyl-01 | Tampering | main.scd transport state across re-evaluation | low | mitigate | The prior `~ppPlaying` is captured into `~ppWasPlaying` as the first waitForBoot statement, before any teardown (awk ordering gate in Task 1). nil maps to true (D-15). The smoke checks "autostart", "re-evaluation" and "re-evaluation stays stopped" assert the absolute `~ppPlaying` and `~ppTransportCount` values. |
| T-hyl-02 | Denial of Service | Stopped re-evaluation leaves the engine silent | low | mitigate | It is silent only when the rider had pressed Stop, which matches the GUI. The engine posts "was stopped before re-evaluation -- staying stopped (press Start ...)" and a "groove stopped" ready line. The smoke test proves the next /pp/play 1 starts the groove (step 6 of Task 1). |
| T-hyl-03 | Spoofing | OSCdef \pp_play | low | accept | Not modified. The loopback-only `srcID: NetAddr("127.0.0.1", nil)` guard is untouched. Testing it (audit W3) is out of scope. |
| T-hyl-SC | Tampering | npm/pip/cargo installs | low | accept | This plan installs no packages, so there is nothing to vet. |
</threat_model>

<verification>
- `scripts/smoke_test.sh` exits 0, the log ends with `SMOKE PASS`, and it has at least 67 `CHECK OK:` lines, including `autostart`, `re-evaluation`, `re-evaluation stays stopped`, `fx re-evaluation` and `volume re-evaluation`.
- Task 1's red run is recorded: the new check failed against the unfixed main.scd.
- `git diff --stat` touches only supercollider/main.scd and supercollider/smoke_test.scd, plus scripts/smoke_test.sh only if the watchdog contingency fired. Nothing under python_app/ changes.
</verification>

<success_criteria>
- Pressing Stop and then re-evaluating main.scd leaves the music stopped, and the GUI's next Start click starts it (W1 closed).
- The first evaluation in a fresh interpreter still autostarts (D-15).
- Re-evaluating while playing still keeps playing, with BPM, EPIC and volume preserved and no leaked nodes or buses (the existing B8 checks stay green).
- All 65 previously passing smoke checks still pass, and 2 new ones pass.
</success_criteria>

<output>
Create `.planning/quick/261010-hyl-fix-w1-keep-transport-state-across-main-/261010-hyl-SUMMARY.md` when done. Include the red-run evidence, the smoke wall time, and the final `CHECK OK:` count.
</output>
