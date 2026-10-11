# Pitfalls Research

**Domain:** SuperCollider generative music engine controlled via OSC from a Python Tkinter app on macOS, running alongside Zwift
**Researched:** 2026-10-08
**Confidence:** MEDIUM-HIGH (SuperCollider server/clock/pattern mechanics and Tkinter/Tk version issues are HIGH confidence, backed by official docs and GitHub issue tracker discussion; macOS CoreAudio multi-app sharing and generative-music-fatigue mitigations are MEDIUM confidence, synthesized from community discussion and general composition theory rather than a single authoritative source)

## Critical Pitfalls

### Pitfall 1: Hardcoding OSC port 57120 in the Python client

**What goes wrong:**
The Python app assumes sclang always listens on UDP port 57120. If that port was already bound (e.g. a previous sclang process didn't exit cleanly, or another audio tool grabbed it), sclang silently falls back to a different port. The Python app then sends `/bpm` and `/epic` messages into the void — no error, no connection refused (UDP is connectionless), the GUI just stops having any audible effect and there is no feedback that anything is wrong.

**Why it happens:**
UDP has no "port in use" handshake visible to the sender. Developers test once with a fresh SC boot (port is always 57120 on a clean start), ship that assumption, then months later a crashed sclang process or a second SC instance left running silently shifts the port and breaks the connection with zero error output.

**How to avoid:**
- In the SC patch, explicitly log the active port at startup: `NetAddr.langPort.postln;` — make this visible/obvious in the SC post window.
- Document that the user should check the SC post window if the GUI "does nothing," and that the fix is usually `killall sclang` + reboot the server/patch, or restarting SC.
- Optionally let the Python side's config/settings expose the target port as an editable field (defaulting to 57120) rather than burying it as a magic constant, so it's a one-line fix if it ever drifts.
- Favor designs where the SC patch is the only thing ever running — document "quit any old SC window before starting a new one" as a known operational step, since this project intentionally doesn't manage SC's lifecycle from Python (per PROJECT.md constraints).

**Warning signs:**
GUI slider changes are silently ignored; music never responds to BPM/EPIC changes even though the Python app reports no errors; multiple SC/sclang processes visible in Activity Monitor.

**Phase to address:**
Engine/OSC-bridge phase (when OSCdef listeners and the Python OSC client are first wired together) — bake the port-visibility and port-mismatch recovery into that phase's acceptance check, not left as a late-stage bug hunt.

---

### Pitfall 2: Changing TempoClock tempo mid-pattern causes clicks, drift, or instant jumps instead of smooth ramps

**What goes wrong:**
`TempoClock.tempo_()` changes the clock's tempo instantly at the logical-time boundary of the next scheduled event, not smoothly. A naive `/bpm` handler that just does `myClock.tempo = newBPM/60` on every OSC message will cause audible tempo jumps (not the "ramps smoothly over a few bars" requirement from PROJECT.md), and if done while patterns have already-scheduled events in flight, can cause phase drift between independently-running Pbind/Pdef streams that assumed a given beat grid. Additionally, swapping a Pdef's source pattern without quantization causes it to cut in immediately mid-phrase, producing an audible click/jump instead of a clean handoff.

**Why it happens:**
Tempo and quant are easy to misunderstand: `TempoClock` has both a "logical time" (beat-based, used for scheduling) and "physical time" (wall-clock); changing `.tempo` shifts the mapping between them instantly, and any already-scheduled OSC bundles sent to the server at old-tempo-implied times won't retroactively reschedule. `Pdef`'s own quant/clock handling has long-standing quirks (e.g. quant set on a Pdef is not always respected when swapped under certain conditions — documented SuperCollider GitHub issues), so developers who copy a simple "set tempo directly" example don't realize they need an explicit ramping strategy and consistent quant on every Pdef that changes.

**How to avoid:**
- Never set `.tempo` directly to a new value. Implement a ramp: schedule small incremental tempo steps via a `Routine`/`Task` or use `TempoClock`'s own scheduling to interpolate from current to target BPM over N beats (e.g. linearly step every beat/bar for 4–8 bars). Several community approaches wrap this in a small helper function invoked from the OSC handler instead of touching `.tempo` directly from the handler.
- Keep exactly **one** TempoClock for the whole patch (per the user's own design sketch) and make every Pbind/Pdef/Ptpar reference it explicitly — never let a pattern default to `TempoClock.default` while another part of the patch uses a different clock instance.
- Give every Pdef that can be swapped a consistent `quant` (e.g. 4 or 8 beats) so swaps always land on a bar boundary; test swaps while music is playing, not just at start.
- When the BPM ramp changes the clock across a Pdef swap, order operations so the ramp routine and any pattern swap share the same quantization grid — do the ramp and the swap relative to the same bar count so they don't fight.

**Warning signs:**
Audible "gear shift" instead of smooth tempo glide; drums and bass audibly fall out of phase with each other after a few tempo changes; Pdef swaps click or jump mid-phrase instead of cutting in cleanly at the next bar.

**Phase to address:**
Core engine / TempoClock phase (where BPM-ramp logic is built) — this is explicitly called out in PROJECT.md's Active requirements ("BPM changes ramp smoothly over a few bars"), so this phase's UAT must include listening-test verification of tempo changes during active playback, not just at idle.

---

### Pitfall 3: `s.latency` / server boot timing causes early OSC messages to be dropped or scheduled wrong

**What goes wrong:**
If the Python app or the SC patch's own OSCdef setup sends messages before `s.boot` has fully completed (server not yet responding), those early messages can be silently lost — especially relevant since the SC patch is started separately and the user may start Python before SC is ready, or vice versa. Separately, every Pbind/Pattern event scheduled on the server inherits a default `s.latency` (0.2s) to compensate for network/scheduling jitter; if a custom clock or pattern bypasses this (e.g. direct `s.sendBundle` calls with `0` latency) notes can arrive late to the hardware output or stutter under system load — particularly relevant with Zwift also competing for CPU/audio resources on the same Mac.

**Why it happens:**
Developers test on an idle machine where the server boots in under a second and CPU is never contended, masking timing issues that appear only under real load (Zwift running + screen capture/video + network). The default latency exists specifically to buffer against this but is easy to accidentally override or ignore when writing custom scheduling code.

**How to avoid:**
- Keep the default `s.latency` (~0.2s) rather than setting it to 0 for "snappier" feel — it exists to absorb exactly the kind of system jitter this project will encounter (Zwift + SC on one Mac).
- Gate OSCdef registration and pattern start behind a `s.waitForBoot { ... }` or `ServerBoot`/`ServerTree` callback so nothing in the patch tries to act before the server is actually ready.
- Document (and ideally detect) the startup order: SC patch should finish booting before the Python app is expected to send meaningful `/bpm`/`/epic` values; consider having the SC patch post a clear "ready" line, and have the Python app's first send be harmless/idempotent so an early message that lands before boot is not catastrophic if later messages resync state correctly.
- Load-test with Zwift actually running (not just SC in isolation) before declaring the audio pipeline solid — CPU contention from Zwift's rendering is the realistic worst case for timing jitter, not a quiet dev machine.

**Warning signs:**
First `/bpm` or `/epic` message after starting the Python app appears to be ignored; audio stutters or notes arrive slightly late only when Zwift is also running; works fine on repeated local testing but flaky on first boot each session.

**Phase to address:**
Engine bootstrap / OSC listener phase, with explicit verification during the integration phase that includes running alongside Zwift (matches PROJECT.md constraint: "audio engine must be light enough not to disturb Zwift" — the inverse, Zwift disturbing the engine's timing, must also be checked).

---

### Pitfall 4: Missing `doneAction: 2` (or misuse) causes node leaks, rising CPU, and eventual audio glitching over a long session

**What goes wrong:**
Any SynthDef used for one-shot or enveloped sounds (drum hits, arpeggio notes, pad swells) that doesn't free itself when its envelope finishes leaves a "dead" running synth on the server. One leaked node per note, repeated continuously for an hour-long workout, accumulates into hundreds or thousands of resident nodes — CPU usage climbs steadily, eventually causing audio dropouts, clicks, or the server hitting its node/CPU ceiling mid-ride. This is especially dangerous for a *generative, long-running* engine (this project explicitly wants hour-plus continuous generation) versus a short demo patch where the leak never has time to matter.

**Why it happens:**
It's easy to write and test a SynthDef that sounds correct for the first few notes (leaked nodes are inaudible individually) and only discover the problem after a long run — exactly the scenario a quick dev-loop test won't catch, but a 45–90 minute Zwift session will.

**How to avoid:**
- Every enveloped SynthDef must use `EnvGen.kr(env, doneAction: 2)` (or `Line.kr`/`XLine.kr` equivalent with `doneAction: 2`) so the synth frees itself automatically — never rely on manual `.free` calls for per-note synths played via patterns.
- For sustained/pad voices controlled by `Pmono`/`Pbind` with `\sustain`, verify the gate-driven envelope actually reaches its release stage and frees — a bug in gate logic (e.g. gate never set to 0) is a common cause of leaks that looks identical to a missing doneAction.
- Add a dev-time health check: periodically post `s.numSynths` (or watch the scope/meter window's node count) during an extended soak test and confirm it stays flat over 30+ minutes of continuous generative playback, not just rising briefly during note attacks and returning to baseline.
- Treat "run the engine continuously for the length of a real workout and watch CPU/node count" as a required pre-ship test, not optional polish.

**Warning signs:**
`s.numSynths` (or Activity Monitor CPU for the scsynth process) trends upward over a session instead of staying roughly flat; audio quality degrades (clicks, dropouts) only after 20+ minutes of continuous play, not at startup.

**Phase to address:**
SynthDef/sound-design phase (drums, bass, arps, pads) should bake doneAction into every enveloped SynthDef from the start; a dedicated "soak test" step belongs in the integration/polish phase before calling v1 done, given the hour-long session use case.

---

### Pitfall 5: No clipping/limiter protection on the master bus — generative/stochastic layering produces unpredictable loud peaks

**What goes wrong:**
A generative engine that layers drums, bass, arpeggios, and pads with randomized note choices, densities, and EPIC-driven "drive"/distortion amounts can — by design — produce combinations of simultaneous loud elements that a fixed, hand-tuned composition would never hit. Without headroom protection, this causes hard digital clipping (harsh, unpleasant distortion) at unpredictable moments, which is especially bad for a background workout soundtrack where the user can't easily see/interact with the SC patch to diagnose it.

**Why it happens:**
During development, a composer tests a handful of combinations by ear and it sounds fine; they don't exhaustively test every permutation the generative system can produce, especially combinations that only emerge at high EPIC levels (more density, more drive) which are also the least-tested states because they're less fun to iterate on repeatedly.

**How to avoid:**
- Put a limiter (`Limiter.ar`) or soft clipper (`.softclip`) on the final master bus output as a non-negotiable safety net — standard practice is `Limiter.ar(signal, 0.99, 0.01)` or similar, placed after all synth/FX busses sum but before `Out.ar(0, ...)`.
- Prefer a limiter over a hard digital clip: a limiter with a short lookahead/attack smooths the peak instead of just truncating the waveform into harsh distortion.
- Specifically test the *highest* EPIC levels (max density/drive/brightness) since that's where headroom problems concentrate — don't just tune at moderate settings.
- Consider a secondary, gentler per-bus gain-staging pass (keep individual synth amplitudes conservative) so the limiter is a safety net, not doing constant heavy-handed work — a limiter that's working hard all the time will audibly squash dynamics.

**Warning signs:**
Occasional harsh crackle/distortion that appears only at high EPIC levels or with specific randomized note combinations; master meter pinning at 0dB or clipping indicator lighting during generative peaks.

**Phase to address:**
Master bus / mixing phase — should be one of the first things wired up (even a stub chain) once more than one synth voice exists simultaneously, not deferred to "polish." EPIC-level high-end stress testing belongs in the EPIC-mapping phase's UAT.

---

### Pitfall 6: Tkinter slider spams OSC on every pixel of drag, flooding the network/UDP buffer and causing audible stutter or lag

**What goes wrong:**
A Tkinter `Scale`/slider widget's `command=` callback fires continuously as the user drags — potentially dozens of times per second. If each callback sends an OSC message immediately and unconditionally, sclang's OSC responder queue (or the Python send loop) can be flooded with near-duplicate `/bpm` or `/epic` values. Even though localhost UDP is fast and usually won't literally overflow, every message triggers the SC-side handler logic (potentially re-triggering tempo-ramp routines, recomputing FX parameters, etc.), and firing that handler 30+ times/second instead of a few times/second causes redundant/competing ramps, wasted CPU, and can produce audible "stepping" or fighting ramps instead of one smooth change.

**Why it happens:**
It's the simplest possible wiring (`scale.config(command=send_osc)`) and works fine in a quick manual test where the developer clicks once or drags slowly; it only becomes a problem under a fast real drag gesture, which may not be how the developer tests during initial development.

**How to avoid:**
- Rate-limit/debounce slider-driven OSC sends: either (a) use a short timer (e.g. 30–50ms) that coalesces rapid updates and sends only the latest value, or (b) only send when the value has changed by more than a minimum delta from the last sent value.
- On the SC side, make the `/bpm` and `/epic` OSCdef handlers idempotent/cheap to re-trigger with the same or very close value (e.g. if a ramp to the same target is already running, don't restart it from scratch) so even if a few redundant messages do arrive, they don't cause audible artifacts.
- Separate "live preview while dragging" (cheap, local GUI feedback only) from "commit to OSC" (debounced) if finer UX polish is wanted later — not required for v1 but worth noting as the natural evolution.

**Warning signs:**
Dragging the BPM/EPIC slider produces a "stuttering" or "flickering" audible effect instead of one smooth glide; SC post window logs show many more `/bpm` messages arriving than expected for the drag gesture performed.

**Phase to address:**
GUI phase (BPM/EPIC controls) — the debounce logic should be part of the initial slider implementation, verified by a UAT step that explicitly tests "drag the slider quickly end to end" as well as "nudge it slightly," since those are different stress patterns.

---

### Pitfall 7: Tkinter mainloop blocked or crashed by doing OSC I/O on the GUI thread, or OSC server/client code touching Tk widgets from a background thread

**What goes wrong:**
Tkinter's Tcl interpreter is only safe to call from the thread that created it (the main thread running `mainloop()`). Two opposite mistakes are common: (1) running a blocking OSC send/receive call directly inside a button/slider callback on the main thread, which — if it ever blocks (e.g. DNS resolution oddity, or a receive-and-wait pattern) — freezes the whole GUI (spinning cursor, unresponsive window); (2) if the app ever needs to *receive* OSC (e.g. a future "connection status" ping-back from SC), spawning a background thread for the OSC server and then having that thread directly update a Tkinter widget (e.g. a status label) — which is unsafe and can crash or corrupt the UI, since only the main thread should touch Tk widgets.

**Why it happens:**
UDP `sendto()` on localhost is so fast in practice that blocking-call mistakes rarely show symptoms during development, so this risk is invisible until a weird environment (DNS misconfiguration, firewall prompt, odd network state) stalls a call just once at the wrong moment, or until the design is extended to add any receive-side feedback.

**How to avoid:**
- For v1 (fire-and-forget `/bpm`, `/epic` sends only, no listening in Python), use a non-blocking UDP client (e.g. `python-osc`'s `udp_client.SimpleUDPClient`, which is just a thin wrapper over a non-blocking `socket.sendto`) called directly from the main thread — this is safe and simple, no threading needed at all for sending.
- If/when a receive path is added (status feedback from SC), run the OSC server in a background thread (e.g. `python-osc`'s `ThreadingOSCUDPServer` or `BlockingOSCUDPServer` in its own thread) but never update Tk widgets directly from that thread's handler — instead push received values into a thread-safe `queue.Queue` and have the Tk main loop poll it periodically via `root.after(...)`, which is the standard safe pattern for crossing from a worker thread into Tkinter.
- Keep this asymmetry explicit in the architecture: v1 needs zero threading (pure outbound sends); only add a background thread when inbound OSC is actually needed, and when you do, follow the queue+`after()` pattern rather than touching widgets from the OSC thread.

**Warning signs:**
GUI occasionally freezes or shows the spinning "beachball" cursor briefly on slider movement; (if/when receive is added) intermittent crashes or garbled widget state that only reproduces occasionally, tied to timing of incoming OSC messages.

**Phase to address:**
GUI/OSC-client phase — establish the non-blocking send pattern from the start; flag the thread-safe receive pattern as a documented constraint for any future phase that adds feedback/status from SC to Python (explicitly out of scope for v1 per PROJECT.md, but worth noting now to avoid a redesign later).

---

### Pitfall 8: macOS Tkinter/Tcl-Tk version mismatches between Homebrew, pyenv, and system Python break the GUI or make it look broken

**What goes wrong:**
On macOS, Tkinter is a thin wrapper around a system Tcl/Tk installation, and the Python interpreter must be built against a compatible Tcl/Tk version. Common failure modes: (1) the macOS-bundled Tk (historically 8.5, deprecated/unsupported by Python docs) causes bad font rendering, resize bugs, or crashes on some macOS versions; (2) installing Python via `pyenv` without Tcl/Tk headers present at build time silently produces a Python with no working Tkinter, failing with `ModuleNotFoundError: No module named '_tkinter'` only when the app is actually run; (3) more recently, Homebrew moved its `tcl-tk` formula to version 9.0, while a pyenv-built Python still expects and is linked against 8.6 — causing a library-version mismatch (`tk.h version (8.6) doesn't match libtk.a version (8.5)`-style errors) if Homebrew's Tcl/Tk is upgraded after Python was built.

**Why it happens:**
Tkinter's native-library dependency is invisible until it breaks — `pip install` never fails for missing Tkinter (it's part of the stdlib, not a pip package), so the first signal is often a runtime import error or, worse, a GUI that launches but renders incorrectly (wrong fonts, broken widget styling) without crashing, which is easy to mistake for "that's just how Tkinter looks" rather than a version bug.

**How to avoid:**
- Decide and document one supported Python provisioning path for this project (e.g. "Homebrew python3" or a specific pyenv + `tcl-tk` combination) rather than assuming whatever Python the user already has will "just work" with Tkinter.
- If using `pyenv`, install/pin Tcl-Tk 8.6 via Homebrew *before* building the Python version, and pass the explicit `PYTHON_CONFIGURE_OPTS` pointing at the 8.6 headers/libs, to avoid an unintentional pickup of Homebrew's newer 9.0 formula.
- Add a one-line startup self-check in the app (or a setup doc step) that verifies `tkinter.TkVersion` / `Tcl` version at launch and prints a clear error if it's below a known-good threshold, rather than letting a user hit a cryptic crash or garbled UI with no explanation.
- Test the actual GUI visually on the target machine early — don't assume "it imported without error" means "it renders correctly"; broken ttk theming is a silent, visual-only failure mode.

**Warning signs:**
`ModuleNotFoundError: No module named '_tkinter'` on launch; GUI opens but fonts/widgets look visibly wrong (stretched, wrong color, missing themeing) compared to a reference screenshot; works on one machine/Python install and not another with no code change.

**Phase to address:**
Project setup / environment phase (very first phase) — this should be verified once, early, as part of "GUI shell exists and renders correctly," before any OSC wiring is built on top of it, since debugging this later is confusing when mixed with actual feature bugs.

---

### Pitfall 9: No feedback when SuperCollider isn't running — UDP sends succeed from Python's point of view even when nothing is listening

**What goes wrong:**
`sendto()` over UDP to localhost will return successfully (no exception) even if nothing is bound to the destination port — there is no connection, so there is no "connection refused" signal the way there might be over TCP (and even ICMP port-unreachable responses are commonly swallowed/unreliable on loopback). This means if the user forgets to start the SC patch, or it crashed, or it's still booting, the Python GUI reports complete success on every `/bpm`/`/epic` send while nothing happens musically — and because the whole point of this app is "move a slider, hear the music change," total silence (because SC isn't running) looks identical, from the Python side, to "it's working but the musical mapping happens to be subtle."

**Why it happens:**
This is a structural property of UDP/OSC, not a bug — it's the same reason OSC is attractive for this kind of low-latency local control (no handshake overhead) but it means the burden of liveness detection falls entirely on the application, and it's easy to skip building that because "it worked when I tested it" (SC was always already running during dev).

**How to avoid:**
- Treat "detect whether SC is actually listening" as a first-class v1 feature, not a nice-to-have: have the SC patch register a simple OSC responder (e.g. `/ping` → replies on `/pong`) and have the Python app send a periodic heartbeat and show a clear connected/disconnected indicator in the GUI (e.g. a colored dot or status text) based on whether a `/pong` was received within a timeout window.
- Since receiving in Python requires the thread-safe receive pattern (see Pitfall 7), implement the heartbeat listener using the queue+`root.after()` polling approach from the start, rather than bolting it on later.
- Fail loud in the UI, not silent: if the heartbeat times out, visibly say "SuperCollider not detected" rather than leaving the GUI looking identical to the connected state.
- This directly serves the project's stated success bar ("Python → OSC → SuperCollider works") — without liveness feedback, there is no way for the user (or for testing/UAT) to distinguish "the chain is broken" from "the chain works but this particular change is hard to hear."

**Warning signs:**
User reports "I moved the slider and nothing happened" and the first debugging question is always "is SC actually running?" — if that question has to be asked at all, the feedback gap is the problem, not (necessarily) the audio mapping.

**Phase to address:**
GUI/OSC-bridge phase — should be part of the MVP, not deferred, specifically because this project's core value proposition (per PROJECT.md) *is* the end-to-end chain working, and connection-status feedback is the only way to verify that claim without staring at the SC post window during every test.

---

### Pitfall 10: Generative music becomes monotonous (feels like a static loop) or produces harmonic clashes between independently-generated layers

**What goes wrong:**
Two related failure modes for a multi-layer generative engine (drums, bass, arpeggios, pads each on their own Pbind/Pdef): (1) **Monotony** — if each pattern's randomization (`Prand`, `Pwrand`, etc.) only ever picks from the same small pool of values without any longer-timescale structure, the piece feels directionless and repetitive over a 30–60+ minute session even though technically "nothing repeats exactly," because the *statistical character* never changes. (2) **Harmonic clash** — if bass, arpeggio, and pad layers each independently choose notes/scale degrees from their own random process without a shared harmonic reference (current chord/scale), they will periodically produce dissonant combinations that sound like a mistake rather than an intentional musical choice — especially audible in melodic techno/trance where harmonic layers are foregrounded, per PROJECT.md's stated genre target.

**Why it happens:**
It's natural to build each synth voice's pattern in isolation (easiest to reason about one Pbind at a time), but that isolation is exactly what causes both problems: no shared state means no large-scale evolution (monotony) and no shared harmonic truth (clashes). This is a very common failure in first attempts at generative music because random-per-layer feels "generative enough" during a short test listen but reveals its flaws only over a longer unsupervised listen — which is exactly this project's actual use case (full workout sessions).

**How to avoid:**
- Maintain a single shared harmonic state (current scale/key, and ideally a current chord or scale-degree "center") that all pitched layers (bass, arps, pads) read from, rather than each generating pitches independently. A shared `Pfunc`-readable global (or a conductor process) that periodically updates "current chord" is the standard pattern mentioned in the user's own design sketch (`Pchain`, scenes/intensity layer).
- Introduce structure at multiple timescales: short-term variation (note-to-note randomization within a Pbind) nested inside medium-term evolution (chord/scene changes every N bars) nested inside long-term arcs (the EPIC-level progression over the workout, which this project already has as a first-class control). Don't rely on note-level randomness alone to carry 60 minutes of interest.
- Constrain randomization to musically-valid choices relative to the shared harmony (e.g. generate arpeggio notes from "current chord tones + occasional scale-degree passing tones" rather than "any note in the scale with equal probability") so clashes become intentional tension rather than accidental wrongness.
- Use weighted/Markov-like choice (`Pwrand`, or hand-tuned transition weights) rather than uniform `Prand` for anything pitch-related, biasing toward smooth voice-leading and occasional surprise rather than uniform randomness, which is statistically guaranteed to eventually produce a bad-sounding leap.
- Validate this with long-listen tests (run the full engine for 20–30+ minutes while actually listening, not just glancing at code) — this class of problem is categorically invisible in a 30-second test loop.

**Warning signs:**
A 5-minute listen sounds great; a 30-minute listen feels like "the same thing on shuffle"; occasional notes/chords sound like mistakes rather than musical tension; changing EPIC level changes brightness/energy but the piece still feels harmonically aimless underneath.

**Phase to address:**
Core generative composition phase (after basic SynthDefs and OSC wiring work, when the actual Pbind/Pdef musical logic is built) — this is a musicality/design concern more than a technical bug, so it should be explicitly called out as a UAT criterion ("listen for at least 15–20 minutes continuously and confirm it doesn't feel static or dissonant") rather than assumed to be covered by functional testing alone.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|-----------------|------------------|
| Set `.tempo` directly instead of building a ramp helper | Faster to wire up BPM control initially | Violates the "smooth ramp over a few bars" requirement; audible jolts | Never for shipped v1 — this is an explicit PROJECT.md requirement, not optional polish |
| Skip the SC "is it running" heartbeat/ping | Simpler v1 scope, less code | Debugging "nothing happens" sessions is painful; undermines confidence in the core value prop | Only acceptable for a throwaway first spike, never for the shipped v1 |
| Send OSC on every Tkinter slider pixel without debounce | Trivial to implement | Audible stuttering during fast drags, wasted CPU on redundant handler re-triggers | Acceptable briefly during early spike/demo, must be fixed before calling BPM/EPIC controls "done" |
| Use `Prand` uniformly for all pitch content instead of harmonic-aware weighting | Gets *some* generative sound playing fastest | Harmonic clashes and eventual monotony over long sessions | Acceptable for the very first "does audio come out" milestone, not for the final generative engine |
| No limiter on master bus during early synth-design iteration | One less thing to configure while tuning individual sounds | Risk of shipping a patch that can clip unpredictably at high EPIC/density | Acceptable only while actively soloing/tuning one voice at a time; must be added back before any multi-voice integration test |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|-----------------|-------------------|
| Python → sclang OSC | Hardcoding port 57120 with no visibility into actual port | Log `NetAddr.langPort` in SC on boot; treat the port as configurable, not a magic constant |
| Tkinter ↔ OSC send/receive | Blocking calls or cross-thread widget updates | Use non-blocking `udp_client` for sends on main thread; if receiving, use a background server thread + `queue.Queue` + `root.after()` polling |
| SC server boot ↔ OSC listeners | Registering OSCdefs or sending messages before `s.boot` completes | Gate setup on `s.waitForBoot{}` / `ServerBoot` and document startup order between SC and Python |
| macOS audio device ↔ Zwift | Assuming SC's chosen output device/sample rate matches what's actually active, especially with Bluetooth or AirPlay devices Zwift might also want | Set `ServerOptions` device/sample rate explicitly to match the system's active output device; re-check after any device/sample-rate change (Bluetooth connect, AirPods auto-switch) since `ServerOptions` changes only take effect after a server reboot |
| Homebrew / pyenv / system Python ↔ Tkinter | Assuming any installed Python has working Tkinter | Pin a known-good Python+Tcl/Tk combination for this project and verify `tkinter.TkVersion` at startup |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|-----------------|
| Missing `doneAction: 2` on enveloped synths | CPU/node count slowly climbs during continuous play | Every enveloped SynthDef uses `doneAction: 2`; soak-test for 30+ min | After 20–60+ minutes of continuous generative playback (a full workout) |
| No debounce on slider→OSC sends | Audible stutter only during fast drag gestures | Debounce/coalesce rapid slider updates (30–50ms) | Immediately on any fast manual drag; not visible with slow/careful testing |
| Over-firing OSC heartbeat/ping at too-high frequency | Needless CPU/network overhead, though unlikely to be severe on localhost | Keep heartbeat interval modest (e.g. 1–2s), not per-frame | Only matters if other real-time-sensitive OSC traffic shares the same loop |
| Running the limiter very hard as the primary gain-staging tool | Pumping/squashed dynamics audible under generative load spikes | Keep individual synth levels conservative; let the limiter be a safety net, not primary leveling | At high EPIC/density settings where many voices sound simultaneously |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Binding the OSC server (if receive is ever added) to `0.0.0.0` instead of `127.0.0.1` | Any device on the local network could send control messages to the SC engine (or spoof heartbeat replies to the GUI) | Bind both the sclang OSC listener and any future Python-side OSC receiver explicitly to loopback (`127.0.0.1`), since this is a single-machine, same-Mac design per PROJECT.md constraints — there's no legitimate reason for this traffic to leave localhost |
| No validation on incoming OSC argument types/ranges in OSCdef handlers | A malformed or out-of-range `/bpm`/`/epic` value (e.g. negative BPM, EPIC > 100) could crash the ramp logic or produce absurd audio (e.g. extremely fast tempo) | Clamp/validate every incoming OSC argument in the SC-side handler before using it (e.g. `bpm.clip(20, 200)`, `epic.clip(0, 100)`) — don't trust the sender even though it's "your own" GUI, since bugs in the Python side are just as capable of sending bad values as a hostile sender |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-------------------|
| No visible connection status to SC | User can't tell if "nothing happened" means broken chain vs. subtle audio change | Add a connected/disconnected indicator driven by an OSC heartbeat (Pitfall 9) |
| Slider jolts the tempo instantly | Jarring mid-ride experience, breaks immersion during a workout | Always ramp BPM changes over several bars (Pitfall 2), never set tempo instantly from a GUI event |
| EPIC preset buttons and fine-tune slider fight each other (e.g. slider doesn't reflect current preset, or pressing a preset doesn't move the slider) | Confusing control state; user loses track of actual EPIC value | Keep preset buttons and the fine-tune slider as two views on one underlying EPIC value — pressing a preset should visibly move the slider to match, and dragging the slider should implicitly "deselect" any highlighted preset |
| GUI gives no indication the SC patch needs to be started separately first | New/returning user confusion about why nothing happens on first run | Since starting SC is explicitly out of scope for Python to manage (PROJECT.md), the GUI should at least passively communicate "waiting for SuperCollider..." via the connection-status indicator rather than looking identically "ready" whether or not SC is up |

## "Looks Done But Isn't" Checklist

- [ ] **BPM ramp:** Often "works" only tested as a single tempo change at idle — verify it still ramps smoothly when changed again mid-ramp (double-tap the slider) and while other patterns/Pdef swaps are also quantized against the same clock.
- [ ] **OSC wiring "done":** Often verified only with SC already running and warmed up — verify behavior cold (SC not started yet, or SC started after Python) and verify the port-mismatch and no-feedback failure modes (Pitfalls 1 and 9) explicitly, not just the happy path.
- [ ] **Synth cleanup "done":** Often verified by listening for a minute or two — verify via an actual node-count/CPU soak test across a realistic session length (30–60+ min), not a quick smoke test.
- [ ] **Generative variety "done":** Often verified by a short listen that sounds pleasantly random — verify with a genuinely long, uninterrupted listen (20–30+ min) specifically checking for monotony and harmonic clashes, which only emerge over time.
- [ ] **Master bus safety "done":** Often verified only at moderate EPIC/density settings — verify specifically at maximum EPIC/density/drive settings, where headroom problems concentrate.
- [ ] **GUI "done" on dev machine:** Often verified only on the developer's own Python install — verify Tkinter actually renders/launches correctly on a fresh or differently-provisioned Python environment (Homebrew vs. pyenv vs. system Python), since this is a silent, environment-dependent failure mode.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|----------------|------------------|
| OSC port drifted from 57120 | LOW | Kill stray sclang processes, restart SC patch fresh, confirm `NetAddr.langPort` posts 57120, or update Python's target port to match |
| Audible node-leak CPU creep discovered late | MEDIUM | Audit every SynthDef for missing `doneAction: 2`/gate-release paths; add a soak-test script that runs the engine headless for N minutes and asserts `s.numSynths` stays flat |
| Harmonic clashes discovered after layers were built independently | HIGH | Introduce a shared harmonic-state object/Pfunc after the fact and retrofit each pattern's pitch-selection logic to read from it — effectively a rework of the pitch-generation layer, so cheaper to design shared harmony in from the start |
| Tkinter broken due to Tcl/Tk version mismatch | LOW–MEDIUM | Reinstall/rebuild Python against a pinned Tcl-Tk 8.6 via Homebrew + `PYTHON_CONFIGURE_OPTS`, or switch to a known-good Python distribution (e.g. python.org installer, which bundles a compatible Tk) |
| Master bus clipping discovered after synths were tuned without a limiter | LOW | Add `Limiter.ar` (or `.softclip`) at the final output stage; re-balance individual synth levels only if the limiter is working audibly hard |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|----------------|
| OSC port drift / no port visibility (1) | Engine/OSC-bridge phase | `NetAddr.langPort` is posted/logged on SC boot; Python target port is a visible config value, not buried |
| Tempo ramp / Pdef swap clicks (2) | Core engine / TempoClock phase | Listening test: change BPM repeatedly, including mid-ramp and during Pdef swaps, confirm no jolts or clicks |
| Server boot timing / s.latency (3) | Engine bootstrap phase | Patch gates on `s.waitForBoot`; integration test run alongside Zwift confirms no dropped/late first messages |
| doneAction / node leaks (4) | SynthDef / sound-design phase | 30–60 min soak test shows flat `s.numSynths` / stable CPU |
| Master bus clipping (5) | Master bus / mixing phase | No audible distortion at maximum EPIC/density settings |
| Slider OSC spam (6) | GUI phase (BPM/EPIC controls) | Fast slider drag produces smooth audio change, not stutter; SC post window message rate is reasonable during a drag |
| Tkinter thread-safety (7) | GUI/OSC-client phase | Sends are non-blocking from main thread; any future receive path uses queue+`after()` pattern (documented even if not built in v1) |
| macOS Tk/Tcl version mismatch (8) | Project setup phase | GUI renders correctly (fonts, ttk theming) on the actual target Python install, verified visually, not just "imports without error" |
| No feedback when SC isn't running (9) | GUI/OSC-bridge phase | Visible connected/disconnected indicator driven by an OSC heartbeat; verified by actually not starting SC and confirming the GUI reflects that |
| Generative monotony / harmonic clash (10) | Core generative composition phase | 20–30+ minute continuous listening test confirms variety over time and no unintended dissonance across layers |

## Sources

- [OSC Communication (official SC docs)](https://doc.sccode.org/Guides/OSC_communication.html)
- [Changing the listening port on Supercollider (sc-users mailing list)](https://sc-users.bham.ac.narkive.com/xCNBVZsb/changing-the-listening-port-on-supercollider)
- [Pdef (official class docs)](https://doc.sccode.org/Classes/Pdef.html)
- [Pdef quantization doesn't work when set as source to an Ndef — GitHub issue #4767](https://github.com/supercollider/supercollider/issues/4767)
- [Pdef.play should use clock (and quant) if set in the instance — GitHub issue #4803](https://github.com/supercollider/supercollider/issues/4803)
- [TempoClock (official class docs)](https://doc.sccode.org/Classes/TempoClock.html)
- [Scheduling and Server timing (official SC guide)](https://doc.sccode.org/Guides/ServerTiming.html)
- [Precise timing in SC: latency, bundles, OffsetOut](https://composerprogrammer.com/teaching/supercollider/sctutorial/8.1%20Precise%20Timing%20in%20SC.html)
- [supernova: OSC messages received while booting are queued — GitHub issue #7733](https://github.com/supercollider/supercollider/issues/7733)
- [Node (official class docs, doneAction behavior)](https://doc.sccode.org/Classes/Node.html)
- [Audio device selection (official SC reference)](https://doc.sccode.org/Reference/AudioDeviceSelection.html)
- [Sample Rate Mismatch, server won't boot — TOPLAP forum](https://forum.toplap.org/t/sample-rate-mismatch-server-wont-boot/2048)
- [Failure to boot to specified sample rate — GitHub issue #4409](https://github.com/supercollider/supercollider/issues/4409)
- [Create an Aggregate Device to combine multiple audio devices — Apple Support](https://support.apple.com/en-us/102171)
- [Way to limit maximum output volume — scsynth forum](https://scsynth.org/t/way-to-limit-maximum-output-volume/2392)
- [Limiter class or another solution — scsynth forum](https://scsynth.org/t/limiter-class-or-another-solution/3225)
- [Issue 11077: Tkinter is not thread safe — Python bug tracker](https://bugs.python.org/issue11077)
- [python-osc Server documentation](https://python-osc.readthedocs.io/en/latest/server.html)
- [python-osc on PyPI](https://pypi.org/project/python-osc/)
- [Automatic support or clearer docs for tcl-tk on macOS — pyenv issue #1545](https://github.com/pyenv/pyenv/issues/1545)
- [tcl-tk from homebrew is now 9.0, not 8.6 — pyenv issue #3116](https://github.com/pyenv/pyenv/issues/3116)
- [Unable to install python 3.11.0 with tkinter on macOS — pyenv issue #2790](https://github.com/pyenv/pyenv/issues/2790)
- [Install tkinter on macOS — blog.lanzani.nl](https://blog.lanzani.nl/2020/install-tkinter-macos/)
- [How Generative Music Works — teropa.info](https://teropa.info/loop/)
- [Six Techniques for Algorithmic Music Composition — Peter S. Langston](https://www.langston.com/Papers/amc.pdf)

---
*Pitfalls research for: SuperCollider + Python/Tkinter OSC-controlled generative music engine (PedalPulse)*
*Researched: 2026-10-08*
