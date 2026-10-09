// Headless engine + Python-link test harness (D-18).
//
// Run via scripts/smoke_test.sh, or directly:
//   /Applications/SuperCollider.app/Contents/MacOS/sclang -D supercollider/smoke_test.scd
//
// Do NOT set QT_QPA_PLATFORM=offscreen anywhere: verified to abort sclang
// 3.14.1 on macOS with exit 134 (only the cocoa Qt plugin is bundled).
// Plain `sclang -D` runs headless on its own.
//
// Each check prints "CHECK OK: <name>" or "CHECK SKIP: <name> (<reason>)".
// The first failure prints "SMOKE FAIL: <name>: <detail>" and exits 1 after
// s.quit. Only "loopback-only" may print SKIP.

(
var root, venvPython;
var fail, checkOk, checkSkip, sendCli, waitForApplyChange, waitForPlaying;
var sendPlay, instrChildCount, instrDefNames, groupChildDefs;
var peakVal = 0.0, peakOSCdef;
var sendBpm, waitForTempo, traceGlide, lastTrace;
var sendEpic, traceCtl, readCtl, waitEpicSettled, measureBand;
var ctlSamples, bandSum = 0, bandCount = 0, ctlOSCdef, bandOSCdef;
var stepBound;
var measurePeak, sendVolume;

// Watchdog first, in case anything below hangs. Raised from 240 to 300s:
// Phase 3's EPIC checks wait out the 1.5s EPIC lag several times (glide
// up/down/retarget, clamp float settle, fx headroom, re-evaluation).
SystemClock.sched(300, { "SMOKE FAIL: watchdog timeout".postln; 1.exit; nil });

// sclang reports a relative nowExecutingPath when given a relative path
// (verified during planning), so resolve to an absolute path first.
root = File.realpath(thisProcess.nowExecutingPath).dirname.dirname;

// Redirect to an isolated server before loading main.scd, so a live IDE
// server on 57110 is never touched.
Server.default = s = Server(\ppSmoke, NetAddr("127.0.0.1", 57140));

~ppReady = false;

// Throws so a failing check aborts the rest of the test immediately instead
// of falling through to later checks -- the top-level `try` below is what
// actually prints "SMOKE FAIL: ..." and exits.
fail = { |name, detail|
	Error("%: %".format(name, detail)).throw;
};

checkOk = { |name|
	"CHECK OK: %".format(name).postln;
};

checkSkip = { |name, reason|
	"CHECK SKIP: % (%)".format(name, reason).postln;
};

// Raw-send helper: drives python_app/osc_client.py, the real Python -> UDP
// -> sclang path, satisfying D-08 (raw OSC from a test script, not the GUI).
sendCli = { |valuesStr|
	"% %/python_app/osc_client.py % --port %".format(venvPython, root, valuesStr, NetAddr.langPort).systemCmd;
};

// Polls ~ppTempoApplyCount until it differs from `before`, up to `timeoutSec`.
// Returns true if it changed, false on timeout.
waitForApplyChange = { |before, timeoutSec|
	var elapsed = 0;
	while ({ (~ppTempoApplyCount == before) and: { elapsed < timeoutSec } }) {
		0.1.wait;
		elapsed = elapsed + 0.1;
	};
	~ppTempoApplyCount != before;
};

// Polls ~ppPlaying until it equals `want`, up to `timeoutSec`.
// Returns true once it matches, false on timeout.
waitForPlaying = { |want, timeoutSec|
	var elapsed = 0;
	while ({ (~ppPlaying != want) and: { elapsed < timeoutSec } }) {
		0.1.wait;
		elapsed = elapsed + 0.1;
	};
	~ppPlaying == want;
};

// Direct sclang send for /pp/play (Task 2 engine-only checks). The Python
// path through osc_client.py is already covered by the "python stop" /
// "python start" checks above.
sendPlay = { |value| NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/play', value) };

// Direct sclang send for /pp/bpm (Task 2 timing-sensitive glide checks). The
// Python path through osc_client.py stays covered by "python tempo 140" and
// the clamp table.
sendBpm = { |value| NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/bpm', value) };

// Direct sclang send for /pp/epic (EPIC-01/02 timing-sensitive checks). The
// Python path through osc_client.py stays covered by "python epic" and the
// clamp table.
sendEpic = { |value| NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/epic', value) };

// Direct sclang send for /pp/volume (GUI-03 timing-sensitive checks). The
// Python path through osc_client.py stays covered by "python volume" and
// the clamp table.
sendVolume = { |value| NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/volume', value) };

// Measures the peak amplitude on an audio bus over durSec seconds via
// \ppPeakProbe (test-only SynthDef added before main.scd loads). Hoisted
// from B7's local definition (Plan 03) so the new volume checks can use it
// too.
measurePeak = { |busIndex, durSec|
	var probe;
	peakVal = 0.0;
	probe = Synth.after(~ppMasterGroup, \ppPeakProbe, [\in, busIndex]);
	durSec.wait;
	probe.free;
	peakVal;
};

// Traces a control-rate bus for durSec seconds via \ppCtlProbe, running
// `action` (if notNil) after a short pre-roll so the very first samples
// reflect the bus's settled starting value. Returns the collected List of
// [value, pulseCount] pairs.
traceCtl = { |busIndex, durSec, action|
	var probe;
	ctlSamples = List.new;
	probe = Synth.after(~ppMasterGroup, \ppCtlProbe, [\in, busIndex]);
	0.1.wait;  // pre-roll: let the probe's first replies settle before sampling
	if (action.notNil) { action.value; };
	durSec.wait;
	probe.free;
	ctlSamples;
};

// One-shot read of a control-rate bus's current value via traceCtl (0.1s).
readCtl = { |busIndex|
	var samples = traceCtl.(busIndex, 0.1, nil);
	if (samples.isEmpty) {
		fail.("readCtl", "no /pp/test/ctl reply");
	};
	samples.last[0];
};

// Polls readCtl until it is within 0.005 of target (0..1 scale) or
// timeoutSec has elapsed. Returns a Boolean.
waitEpicSettled = { |target, timeoutSec|
	var elapsed = 0, settled = false;
	while ({ settled.not and: { elapsed < timeoutSec } }) {
		settled = (readCtl.(~ppEpicSmoothBus.index) - target).abs < 0.005;
		if (settled.not) {
			0.1.wait;
			elapsed = elapsed + 0.1;
		};
	};
	settled;
};

// Measures the mean high-frequency-band amplitude on an audio bus over
// durSec seconds via \ppBandProbe.
measureBand = { |busIndex, hpfFreq, durSec|
	var probe;
	bandSum = 0;
	bandCount = 0;
	probe = Synth.after(~ppMasterGroup, \ppBandProbe, [\in, busIndex, \hpf, hpfFreq]);
	durSec.wait;
	probe.free;
	if (bandCount == 0) {
		fail.("measureBand", "no /pp/test/band replies");
	};
	bandSum / bandCount;
};

// Polls until the engine has landed exactly on `bpm` (tempo matches within
// 1e-6 AND the ramp rate is back to 0 -- no residual glide), up to
// `timeoutSec`. Returns true or false (timeout). A `timeoutSec` of 0 acts
// as a one-shot "is it already landed" predicate (no wait).
waitForTempo = { |bpm, timeoutSec|
	var elapsed = 0;
	while ({
		(((~clock.tempo * 60 - bpm).abs >= 1e-6) or: { ~ppRampRateBpm != 0 }) and: { elapsed < timeoutSec }
	}) {
		0.05.wait;
		elapsed = elapsed + 0.05;
	};
	((~clock.tempo * 60 - bpm).abs < 1e-6) and: { ~ppRampRateBpm == 0 };
};

// Samples [beat, bpm] every 0.02s into a List until the engine lands on
// `target` (same landed condition as waitForTempo) or `timeoutSec` passes.
// Returns the List (whatever was sampled, even on timeout).
traceGlide = { |target, timeoutSec|
	var samples = List.new, elapsed = 0, landed = false;
	while ({ landed.not and: { elapsed < timeoutSec } }) {
		samples.add([~clock.beats, ~clock.tempo * 60]);
		landed = ((~clock.tempo * 60 - target).abs < 1e-6) and: { ~ppRampRateBpm == 0 };
		0.02.wait;
		elapsed = elapsed + 0.02;
	};
	samples;
};

// Queries the server for the number of direct children of ~ppInstrGroup
// via /g_queryTree, polling up to 1s for the /g_queryTree.reply. Fails if
// no reply arrives. (Verified empirically: for an OSCFunc-received reply,
// msg[0] is the address, msg[1] the echoed flag, msg[2] the queried
// group's node ID, and msg[3] the direct-child count.)
instrChildCount = {
	var replyMsg = nil, oscFunc, elapsed = 0;
	oscFunc = OSCFunc({ |msg| replyMsg = msg; }, '/g_queryTree.reply', s.addr);
	s.sendMsg('/g_queryTree', ~ppInstrGroup.nodeID, 0);
	while ({ replyMsg.isNil and: { elapsed < 1 } }) {
		0.05.wait;
		elapsed = elapsed + 0.05;
	};
	oscFunc.free;
	if (replyMsg.isNil) {
		fail.("instrChildCount", "no /g_queryTree.reply within 1s");
	};
	replyMsg[3];
};

// Queries the server (like instrChildCount, flag 0) and parses the
// /g_queryTree.reply into the SynthDef names of ~ppInstrGroup's direct
// children. Starting at index 4, each child synth occupies three slots
// (node ID, -1, def name) -- the def name is always present at flag 0,
// only the per-control values are gated by the flag. Fails if a child
// reports a value other than -1 at the second slot (a subgroup is not
// expected inside the flat instrument group). Returns a Set of Symbols.
instrDefNames = {
	var replyMsg = nil, oscFunc, elapsed = 0, names, i;
	oscFunc = OSCFunc({ |msg| replyMsg = msg; }, '/g_queryTree.reply', s.addr);
	s.sendMsg('/g_queryTree', ~ppInstrGroup.nodeID, 0);
	while ({ replyMsg.isNil and: { elapsed < 1 } }) {
		0.05.wait;
		elapsed = elapsed + 0.05;
	};
	oscFunc.free;
	if (replyMsg.isNil) {
		fail.("instrDefNames", "no /g_queryTree.reply within 1s");
	};
	names = Set.new;
	i = 4;
	while ({ i < replyMsg.size }) {
		if (replyMsg[i + 1] != -1) {
			fail.("instrDefNames", "child node % reports numChildren % (expected -1, a subgroup is not expected)".format(replyMsg[i], replyMsg[i + 1]));
		};
		names.add(replyMsg[i + 2].asSymbol);
		i = i + 3;
	};
	names;
};

// Like instrDefNames, but for an arbitrary group and returning an ORDERED
// Array of SynthDef-name Symbols (not a Set) -- so callers can assert on
// child order, e.g. "the smoother runs before the FX synth". Fails if a
// child reports a value other than -1 (a subgroup is not expected).
groupChildDefs = { |group|
	var replyMsg = nil, oscFunc, elapsed = 0, names, i;
	oscFunc = OSCFunc({ |msg| replyMsg = msg; }, '/g_queryTree.reply', s.addr);
	s.sendMsg('/g_queryTree', group.nodeID, 0);
	while ({ replyMsg.isNil and: { elapsed < 1 } }) {
		0.05.wait;
		elapsed = elapsed + 0.05;
	};
	oscFunc.free;
	if (replyMsg.isNil) {
		fail.("groupChildDefs", "no /g_queryTree.reply within 1s");
	};
	names = Array.new;
	i = 4;
	while ({ i < replyMsg.size }) {
		if (replyMsg[i + 1] != -1) {
			fail.("groupChildDefs", "child node % reports numChildren % (expected -1, a subgroup is not expected)".format(replyMsg[i], replyMsg[i + 1]));
		};
		names = names.add(replyMsg[i + 2].asSymbol);
		i = i + 3;
	};
	names;
};

// Peak-probe OSCdef: SendReply.kr(... '/pp/test/peak', [peakL, peakR]) ->
// msg = [address, nodeID, replyID, peakL, peakR].
peakOSCdef = OSCdef(\ppPeakProbeReply, { |msg|
	peakVal = max(peakVal, max(msg[3], msg[4]));
}, '/pp/test/peak');

// Control-bus probe OSCdef (EPIC-01/02): SendReply.kr(... '/pp/test/ctl',
// [value, pulseCount]) -> msg = [address, nodeID, replyID, value, count].
// Only collects while a trace is active (ctlSamples notNil).
ctlOSCdef = OSCdef(\ppCtlProbeReply, { |msg|
	if (ctlSamples.notNil) { ctlSamples.add([msg[3], msg[4]]); };
}, '/pp/test/ctl');

// High-frequency-band probe OSCdef (EPIC-01 "brightens output"):
// SendReply.kr(... '/pp/test/band', [ampL, ampR]) -> msg = [address,
// nodeID, replyID, ampL, ampR]. Accumulates a running mean of the louder
// channel while measureBand is active.
bandOSCdef = OSCdef(\ppBandProbeReply, { |msg|
	bandSum = bandSum + max(msg[3], msg[4]);
	bandCount = bandCount + 1;
}, '/pp/test/band');

fork({
	var elapsed, portOk, tempoOk, venvOk, sendResult, applyCountBefore, stopSentAt;

	// Boot our own isolated server first (not one of the named checks below --
	// main.scd's own s.waitForBoot gate is what "boot ready" verifies).
	s.boot;
	elapsed = 0;
	while ({ s.serverRunning.not and: { elapsed < 30 } }) {
		0.5.wait;
		elapsed = elapsed + 0.5;
	};
	if (s.serverRunning.not) {
		"SMOKE FAIL: isolated server never booted within 30s".postln;
		1.exit;
	};

	s.volume.mute;  // automated runs are inaudible; Volume amp synth runs at the root tail

	// Peak-probe SynthDef (test-only; not part of main.scd).
	SynthDef(\ppPeakProbe, { |in = 0|
		var sig = In.ar(in, 2);
		SendReply.kr(Impulse.kr(20), '/pp/test/peak', Peak.ar(sig));
	}).add;

	// Control-bus probe SynthDef (test-only; not part of main.scd): reports
	// a control-rate bus's instantaneous value plus a running pulse count,
	// so traceCtl below can detect a dropped reply (gap > 1) and scale its
	// step-bound tolerance accordingly.
	SynthDef(\ppCtlProbe, { |in = 0|
		var trig = Impulse.kr(50);
		SendReply.kr(trig, '/pp/test/ctl', [In.kr(in), PulseCount.kr(trig)]);
	}).add;

	// High-frequency-band probe SynthDef (test-only; not part of main.scd):
	// measures the amplitude of the signal above hpf on an audio bus.
	SynthDef(\ppBandProbe, { |in = 0, hpf = 4000|
		SendReply.kr(Impulse.kr(20), '/pp/test/band', Amplitude.kr(HPF.ar(In.ar(in, 2), hpf), 0.01, 0.1));
	}).add;

	// DC source SynthDef (test-only; not part of main.scd): a constant 0.5
	// signal for the isolated "volume glides" check below -- an easily
	// checked, unvarying input through a scratch \ppMaster instance.
	SynthDef(\ppDcSource, { |out = 0|
		Out.ar(out, DC.ar(0.5) ! 2);
	}).add;

	// Level probe SynthDef (test-only; not part of main.scd): reports an
	// audio-rate bus's instantaneous (A2K-converted) level plus a running
	// pulse count via the same /pp/test/ctl reply path \ppCtlProbe uses, so
	// the isolated "volume glides" check can reuse ctlSamples collection.
	SynthDef(\ppLevelProbe, { |in = 0|
		var trig = Impulse.kr(100);
		SendReply.kr(trig, '/pp/test/ctl', [A2K.kr(In.ar(in, 1)), PulseCount.kr(trig)]);
	}).add;
	s.sync;

	{

	(root +/+ "supercollider/main.scd").load;

	// Poll ~ppReady up to 30s.
	elapsed = 0;
	while ({ ~ppReady.not and: { elapsed < 30 } }) {
		0.5.wait;
		elapsed = elapsed + 0.5;
	};

	if (~ppReady.not) {
		fail.("boot ready", "engine never posted ready within 30s");
	};
	checkOk.("boot ready");

	portOk = (~ppOscPort == NetAddr.langPort);
	if (portOk.not) {
		fail.("port posted", "~ppOscPort % != NetAddr.langPort %".format(~ppOscPort, NetAddr.langPort));
	};
	checkOk.("port posted");

	tempoOk = ((~clock.tempo * 60 - 120).abs < 1e-6);
	if (tempoOk.not) {
		fail.("initial tempo 120", "got % BPM".format(~clock.tempo * 60));
	};
	checkOk.("initial tempo 120");

	venvPython = root +/+ ".venv/bin/python";
	venvOk = File.exists(venvPython);
	if (venvOk.not) {
		fail.("python tempo 140", (venvPython ++ " does not exist -- create it with "
			++ "`python3.13 -m venv .venv && .venv/bin/pip install -r python_app/requirements.txt`"
			++ ", or `./run.sh --setup` once Plan 02 adds it"));
	};

	applyCountBefore = ~ppTempoApplyCount;
	sendResult = sendCli.("140");
	if (sendResult != 0) {
		fail.("python tempo 140", "osc_client.py exited %".format(sendResult));
	};
	if (waitForApplyChange.(applyCountBefore, 3).not) {
		fail.("python tempo 140", "no apply within 3s");
	};
	if (waitForTempo.(140, 12).not) {
		fail.("python tempo 140", "glide never landed on 140 BPM within 12s");
	};
	tempoOk = ((~clock.tempo * 60 - 140).abs < 1e-6);
	if (tempoOk.not) {
		fail.("python tempo 140", "got % BPM".format(~clock.tempo * 60));
	};
	checkOk.("python tempo 140");

	// --- python stop / python start: real Python -> /pp/play transport (GUI-02) ---
	{
		sendResult = sendCli.("--play 0");
		if (sendResult != 0) {
			fail.("python stop", "osc_client.py exited %".format(sendResult));
		};
		if (waitForPlaying.(false, 3).not) {
			fail.("python stop", "~ppPlaying did not become false within 3s");
		};
		~ppLayers.do { |name|
			if (Pbindef(name).isPlaying) {
				fail.("python stop", "Pbindef(%) still playing after /pp/play 0".format(name));
			};
		};
		checkOk.("python stop");

		sendResult = sendCli.("--play 1");
		if (sendResult != 0) {
			fail.("python start", "osc_client.py exited %".format(sendResult));
		};
		if (waitForPlaying.(true, 3).not) {
			fail.("python start", "~ppPlaying did not become true within 3s");
		};
		~ppLayers.do { |name|
			if (Pbindef(name).isPlaying.not) {
				fail.("python start", "Pbindef(%) not playing after /pp/play 1".format(name));
			};
		};
		checkOk.("python start");
	}.value;

	// --- python epic / epic brightens output: real Python -> /pp/epic
	// -> one smoothed EPIC value -> one FX synth -> limiter (EPIC-01
	// tracer slice) ---
	{
		var countBefore, hfLow, hfHigh, elapsedEp;

		countBefore = ~ppEpicCount;
		sendResult = sendCli.("--epic 0");
		if (sendResult != 0) {
			fail.("python epic", "osc_client.py exited %".format(sendResult));
		};
		elapsedEp = 0;
		while ({ (~ppEpicCount == countBefore) and: { elapsedEp < 3 } }) {
			0.1.wait;
			elapsedEp = elapsedEp + 0.1;
		};
		if (~ppEpicCount == countBefore) {
			fail.("python epic", "~ppEpicCount did not change within 3s for --epic 0");
		};
		if (~epic != 0) {
			fail.("python epic", "expected ~epic == 0, got %".format(~epic));
		};
		if (waitEpicSettled.(0.0, 4).not) {
			fail.("python epic", "smoothed EPIC bus never settled to 0.0 within 4s");
		};
		hfLow = measureBand.(0, 4000, 4);

		countBefore = ~ppEpicCount;
		sendResult = sendCli.("--epic 100");
		if (sendResult != 0) {
			fail.("python epic", "osc_client.py exited %".format(sendResult));
		};
		elapsedEp = 0;
		while ({ (~ppEpicCount == countBefore) and: { elapsedEp < 3 } }) {
			0.1.wait;
			elapsedEp = elapsedEp + 0.1;
		};
		if (~ppEpicCount == countBefore) {
			fail.("python epic", "~ppEpicCount did not change within 3s for --epic 100");
		};
		if (~epic != 100) {
			fail.("python epic", "expected ~epic == 100, got %".format(~epic));
		};
		if (waitEpicSettled.(1.0, 4).not) {
			fail.("python epic", "smoothed EPIC bus never settled to 1.0 within 4s");
		};
		checkOk.("python epic");

		hfHigh = measureBand.(0, 4000, 4);
		"PedalPulse smoke: >4 kHz level at bus 0: EPIC 0 = %, EPIC 100 = %".format(hfLow, hfHigh).postln;
		// Probes bus 0 after ~ppMasterGroup -- what the rider hears, so a
		// master still reading the pre-FX mix bus fails here (Pitfall 3).
		if (hfHigh <= 0.001) {
			fail.("epic brightens output", "EPIC 100 high-frequency level % is at or below the silence threshold 0.001".format(hfHigh));
		};
		if (hfHigh < (4 * hfLow)) {
			fail.("epic brightens output", "EPIC 100 high-frequency level % is not at least 4x EPIC 0's level %".format(hfHigh, hfLow));
		};
		checkOk.("epic brightens output");

		sendEpic.(10);
		if (waitEpicSettled.(0.1, 4).not) {
			fail.("epic brightens output", "smoothed EPIC bus never settled back to the default 0.1 within 4s");
		};
	}.value;

	// --- python volume / volume scales output / volume silent at 0: real
	// Python -> /pp/volume -> a lagged, tapered gain inside \ppMaster,
	// before the limiter (GUI-03 engine half). ---
	{
		var countBefore, elapsedVol, p100, p50, expected, ratio;

		countBefore = ~ppVolumeCount;
		if (sendCli.("--volume 100") != 0) {
			fail.("python volume", "osc_client.py exited non-zero for --volume 100");
		};
		elapsedVol = 0;
		while ({ (~ppVolumeCount == countBefore) and: { elapsedVol < 3 } }) {
			0.1.wait;
			elapsedVol = elapsedVol + 0.1;
		};
		if (~ppVolumeCount == countBefore) {
			fail.("python volume", "~ppVolumeCount did not change within 3s for --volume 100");
		};
		if (~volume != 100) {
			fail.("python volume", "expected ~volume == 100, got %".format(~volume));
		};
		0.5.wait;  // let the 0.2s master lag settle
		p100 = measurePeak.(0, 4);

		countBefore = ~ppVolumeCount;
		if (sendCli.("--volume 50") != 0) {
			fail.("python volume", "osc_client.py exited non-zero for --volume 50");
		};
		elapsedVol = 0;
		while ({ (~ppVolumeCount == countBefore) and: { elapsedVol < 3 } }) {
			0.1.wait;
			elapsedVol = elapsedVol + 0.1;
		};
		if (~ppVolumeCount == countBefore) {
			fail.("python volume", "~ppVolumeCount did not change within 3s for --volume 50");
		};
		if (~volume != 50) {
			fail.("python volume", "expected ~volume == 50, got %".format(~volume));
		};
		0.5.wait;
		p50 = measurePeak.(0, 4);
		checkOk.("python volume");

		expected = ~ppVolumeAmp.(50) / ~ppVolumeAmp.(100);
		ratio = p50 / p100;
		"PedalPulse smoke: output peak at volume 100 = %, at 50 = %, ratio % (expected %)".format(p100, p50, ratio, expected).postln;
		if (p100 <= 0.01) {
			fail.("volume scales output", "peak at volume 100 (%) is at or below the silence floor 0.01".format(p100));
		};
		if (p100 >= 0.85) {
			fail.("volume scales output", "peak at volume 100 (%) is already at or near the limiter -- the ratio would mean nothing".format(p100));
		};
		if ((ratio - expected).abs > 0.1) {
			fail.("volume scales output", "ratio % is not within 0.1 of the expected taper ratio %".format(ratio, expected));
		};
		checkOk.("volume scales output");

		countBefore = ~ppVolumeCount;
		sendVolume.(0);
		elapsedVol = 0;
		while ({ (~ppVolumeCount == countBefore) and: { elapsedVol < 3 } }) {
			0.1.wait;
			elapsedVol = elapsedVol + 0.1;
		};
		if (~ppVolumeCount == countBefore) {
			fail.("volume silent at 0", "~ppVolumeCount did not change within 3s for volume 0");
		};
		0.5.wait;
		if (measurePeak.(0, 2) >= 0.001) {
			fail.("volume silent at 0", "peak % at volume 0 is not below the silence threshold 0.001".format(measurePeak.(0, 2)));
		};
		checkOk.("volume silent at 0");

		countBefore = ~ppVolumeCount;
		sendVolume.(80);
		elapsedVol = 0;
		while ({ (~ppVolumeCount == countBefore) and: { elapsedVol < 3 } }) {
			0.1.wait;
			elapsedVol = elapsedVol + 0.1;
		};
	}.value;

	// --- B1/B2: clamp table + whole-beat quantization (TEMPO-03, D-14) ---
	[
		[300, 180, "clamp 300->180"],
		[10, 60, "clamp 10->60"],
		[59, 60, "clamp 59->60"],
		[181, 180, "clamp 181->180"],
		[60, 60, "clamp 60"],
		[180, 180, "clamp 180"],
		[150.5, 150.5, "float 150.5"],
	].do({ |entry|
		var sent = entry[0], expected = entry[1], name = entry[2];
		var before = ~ppTempoApplyCount;
		sendCli.(sent.asString);
		if (waitForApplyChange.(before, 3).not) {
			fail.(name, "no apply within 3s for sent=%".format(sent));
		};
		if ((~ppRampTargetBpm - expected).abs >= 1e-6) {
			fail.(name, "expected glide target % BPM, got %".format(expected, ~ppRampTargetBpm));
		};
		checkOk.(name);
	});
	if (waitForTempo.(150.5, 12).not) {
		fail.("clamp table settle", "glide never landed on 150.5 BPM within 12s");
	};
	checkOk.("clamp table settle");

	// --- glide starts on beat (TEMPO-01): a glide from rest begins on a
	// whole beat, not before, and lands exactly on the new target ---
	{
		var sendBeat, startBefore, trace;
		sendBeat = ~clock.beats;
		startBefore = ~ppRampStartBeat;
		sendBpm.(120);
		trace = traceGlide.(120, 15);
		lastTrace = trace;
		if (~ppRampStartBeat == startBefore) {
			fail.("glide starts on beat", "~ppRampStartBeat did not change after sending 120");
		};
		if ((~ppRampStartBeat - ~ppRampStartBeat.round).abs >= 1e-6) {
			fail.("glide starts on beat", "~ppRampStartBeat % is not a whole beat".format(~ppRampStartBeat));
		};
		if (~ppRampStartBeat < (sendBeat - 1e-6)) {
			fail.("glide starts on beat", "~ppRampStartBeat % is before the send beat %".format(~ppRampStartBeat, sendBeat));
		};
		trace.do({ |sample|
			if (sample[0] < (~ppRampStartBeat - 0.01)) {
				if ((sample[1] - 150.5).abs >= 1e-6) {
					fail.("glide starts on beat", "tempo % at beat % (before the start beat) is not still 150.5".format(sample[1], sample[0]));
				};
			};
		});
		if (((~clock.tempo * 60 - 120).abs >= 1e-6) or: { ~ppRampRateBpm != 0 }) {
			fail.("glide starts on beat", "engine did not land on 120 BPM (tempo=%, rate=%)".format(~clock.tempo * 60, ~ppRampRateBpm));
		};
		checkOk.("glide starts on beat");
	}.value;

	// --- glide reaches target (TEMPO-01, downward, asserts on the 150.5 ->
	// 120 glide recorded by "glide starts on beat") ---
	{
		var trace = lastTrace;
		var maxStep = 2 * ((150.5 - 120) / 32) + 1e-6;
		var i = 1;
		while ({ i < trace.size }) {
			if ((trace[i][1] - trace[i - 1][1]) > 1e-9) {
				fail.("glide reaches target", "tempo rose between samples % -> % (beat %)".format(trace[i - 1][1], trace[i][1], trace[i][0]));
			};
			if ((trace[i - 1][1] - trace[i][1]).abs > maxStep) {
				fail.("glide reaches target", "sample-to-sample drop % exceeds % BPM (beat %)".format(trace[i - 1][1] - trace[i][1], maxStep, trace[i][0]));
			};
			i = i + 1;
		};
		if (((trace.last[1] - 120).abs >= 1e-6) or: { (~bpm - 120).abs >= 1e-6 }) {
			fail.("glide reaches target", "final tempo % / ~bpm % did not land on 120".format(trace.last[1], ~bpm));
		};
		if (((~ppRampLandBeat - ~ppRampStartBeat) < 6) or: { (~ppRampLandBeat - ~ppRampStartBeat) > 9 }) {
			fail.("glide reaches target", "glide took % beats, expected 6-9".format(~ppRampLandBeat - ~ppRampStartBeat));
		};
		~ppLayers.do { |name|
			if (Pbindef(name).isPlaying.not) {
				fail.("glide reaches target", "Pbindef(%) not playing".format(name));
			};
		};
		checkOk.("glide reaches target");
	}.value;

	// --- glide upward (TEMPO-01, upward direction) ---
	{
		var startBefore, trace, maxStep, i;
		startBefore = ~ppRampStartBeat;
		sendBpm.(170);
		trace = traceGlide.(170, 15);
		maxStep = 2 * (50 / 32) + 1e-6;
		if (~ppRampStartBeat == startBefore) {
			fail.("glide upward", "~ppRampStartBeat did not change after sending 170");
		};
		if ((~ppRampStartBeat - ~ppRampStartBeat.round).abs >= 1e-6) {
			fail.("glide upward", "~ppRampStartBeat % is not a whole beat".format(~ppRampStartBeat));
		};
		i = 1;
		while ({ i < trace.size }) {
			if ((trace[i - 1][1] - trace[i][1]) > 1e-9) {
				fail.("glide upward", "tempo fell between samples % -> % (beat %)".format(trace[i - 1][1], trace[i][1], trace[i][0]));
			};
			if ((trace[i][1] - trace[i - 1][1]).abs > maxStep) {
				fail.("glide upward", "sample-to-sample rise % exceeds % BPM (beat %)".format(trace[i][1] - trace[i - 1][1], maxStep, trace[i][0]));
			};
			i = i + 1;
		};
		if (((~clock.tempo * 60 - 170).abs >= 1e-6) or: { ~ppRampRateBpm != 0 }) {
			fail.("glide upward", "did not land on 170 BPM (tempo=%, rate=%)".format(~clock.tempo * 60, ~ppRampRateBpm));
		};
		if (((~ppRampLandBeat - ~ppRampStartBeat) < 6) or: { (~ppRampLandBeat - ~ppRampStartBeat) > 9 }) {
			fail.("glide upward", "glide took % beats, expected 6-9".format(~ppRampLandBeat - ~ppRampStartBeat));
		};
		~ppLayers.do { |name|
			if (Pbindef(name).isPlaying.not) {
				fail.("glide upward", "Pbindef(%) not playing".format(name));
			};
		};
		checkOk.("glide upward");
	}.value;

	// --- same bpm no-op (TEMPO-01 edge: adjacency) ---
	{
		var countBefore, startBefore, tempoBefore;
		countBefore = ~ppTempoApplyCount;
		startBefore = ~ppRampStartBeat;
		tempoBefore = ~clock.tempo;
		sendBpm.(170);
		if (waitForApplyChange.(countBefore, 3).not) {
			fail.("same bpm no-op", "sending the current tempo did not engage");
		};
		(~clock.beatDur * 2).wait;
		if ((~clock.tempo * 60 - 170).abs >= 1e-6) {
			fail.("same bpm no-op", "tempo drifted from 170 to %".format(~clock.tempo * 60));
		};
		if (~ppRampRateBpm != 0) {
			fail.("same bpm no-op", "a glide started for a same-value BPM send");
		};
		if (~ppRampStartBeat != startBefore) {
			fail.("same bpm no-op", "~ppRampStartBeat changed for a same-value BPM send");
		};
		~ppLayers.do { |name|
			if (Pbindef(name).isPlaying.not) {
				fail.("same bpm no-op", "Pbindef(%) not playing".format(name));
			};
		};
		checkOk.("same bpm no-op");
	}.value;

	// --- retarget mid-glide (TEMPO-02, direction reversal) ---
	{
		var samples, elapsed, retargetStart, countBefore, maxStep, minSampled, maxSampled, i;
		var retargeted = false;
		sendBpm.(100);
		samples = List.new;
		elapsed = 0;
		// Phase 1: sample until the tempo has fallen to 150 or below (a new
		// glide toward 100 is clearly under way), up to a 10s timeout.
		while ({ retargeted.not and: { elapsed < 10 } }) {
			samples.add([~clock.beats, ~clock.tempo * 60]);
			if ((~clock.tempo * 60) <= 150) { retargeted = true };
			0.02.wait;
			elapsed = elapsed + 0.02;
		};
		if (retargeted.not) {
			fail.("retarget mid-glide", "tempo never fell to 150 BPM within 10s of sending 100");
		};
		retargetStart = ~ppRampStartBeat;
		countBefore = ~ppTempoApplyCount;
		sendBpm.(160);
		// Phase 2: keep sampling until the engine lands on 160, up to a 15s timeout.
		elapsed = 0;
		while ({
			(((~clock.tempo * 60 - 160).abs >= 1e-6) or: { ~ppRampRateBpm != 0 }) and: { elapsed < 15 }
		}) {
			samples.add([~clock.beats, ~clock.tempo * 60]);
			0.02.wait;
			elapsed = elapsed + 0.02;
		};
		samples.add([~clock.beats, ~clock.tempo * 60]);
		if (((~clock.tempo * 60 - 160).abs >= 1e-6) or: { ~ppRampRateBpm != 0 }) {
			fail.("retarget mid-glide", "glide never landed on 160 BPM within 15s");
		};

		if (~ppTempoApplyCount != (countBefore + 1)) {
			fail.("retarget mid-glide", "expected exactly 1 apply for the retarget, got %".format(~ppTempoApplyCount - countBefore));
		};
		if (~ppRampStartBeat != retargetStart) {
			fail.("retarget mid-glide", "~ppRampStartBeat changed on retarget (expected %, got %)".format(retargetStart, ~ppRampStartBeat));
		};
		maxStep = 2 * (70 / 32) + 1e-6;
		minSampled = 1000;
		maxSampled = 0;
		i = 1;
		while ({ i < samples.size }) {
			if ((samples[i][1] - samples[i - 1][1]).abs > maxStep) {
				fail.("retarget mid-glide", "sample-to-sample jump % exceeds % BPM (beat %)".format((samples[i][1] - samples[i - 1][1]).abs, maxStep, samples[i][0]));
			};
			i = i + 1;
		};
		samples.do({ |sample| minSampled = min(minSampled, sample[1]); maxSampled = max(maxSampled, sample[1]); });
		if (minSampled <= 101) {
			fail.("retarget mid-glide", "sampled tempo reached % (abandoned target of 100 nearly reached)".format(minSampled));
		};
		if (maxSampled > (170 + 1e-6)) {
			fail.("retarget mid-glide", "sampled tempo exceeded 170 (%)".format(maxSampled));
		};
		if ((~clock.tempo * 60 - 160).abs >= 1e-6) {
			fail.("retarget mid-glide", "did not land exactly on 160 BPM (got %)".format(~clock.tempo * 60));
		};
		if (((~ppRampLandBeat - ~ppLastApplyBeat) < 6) or: { (~ppRampLandBeat - ~ppLastApplyBeat) > 9 }) {
			fail.("retarget mid-glide", "retarget-to-land took % beats, expected 6-9".format(~ppRampLandBeat - ~ppLastApplyBeat));
		};
		~ppLayers.do { |name|
			if (Pbindef(name).isPlaying.not) {
				fail.("retarget mid-glide", "Pbindef(%) not playing".format(name));
			};
		};
		checkOk.("retarget mid-glide");
	}.value;

	// --- all layers playing (ENG-01) ---
	{
		var expected = Set[\ppKick, \ppHat, \ppClap, \ppBass, \ppArp, \ppPad];
		if (~ppLayers.asSet != expected) {
			fail.("all layers playing", "~ppLayers % != expected %".format(~ppLayers.asSet, expected));
		};
		~ppLayers.do { |name|
			if (Pbindef(name).isPlaying.not) {
				fail.("all layers playing", "Pbindef(%) not playing".format(name));
			};
			if (Pbindef(name).player.clock !== ~clock) {
				fail.("all layers playing", "Pbindef(%) player.clock is not ~clock".format(name));
			};
		};
		checkOk.("all layers playing");
	}.value;

	// --- all layers sounding (ENG-01): every SynthDef name observed on the
	// server within 3 bars ---
	{
		var expected = Set[\ppKick, \ppHat, \ppClap, \ppBass, \ppArp, \ppPad];
		var seen = Set.new, elapsedAls = 0, timeoutSec = ~clock.beatDur * 12;
		while ({ (seen.size < expected.size) and: { elapsedAls < timeoutSec } }) {
			seen = seen | instrDefNames.();
			0.05.wait;
			elapsedAls = elapsedAls + 0.05;
		};
		if ((expected - seen).notEmpty) {
			fail.("all layers sounding", "missing SynthDef names on server: %".format(expected - seen));
		};
		checkOk.("all layers sounding");
	}.value;

	// --- B3: latest wins (TEMPO-03, D-14) ---
	applyCountBefore = ~ppTempoApplyCount;
	sendCli.("100 130");
	if (waitForApplyChange.(applyCountBefore, 3).not) {
		fail.("latest wins", "no apply within 3s after sending 100 130");
	};
	if (~ppTempoApplyCount != (applyCountBefore + 1)) {
		fail.("latest wins", "expected exactly 1 apply, got % applies".format(~ppTempoApplyCount - applyCountBefore));
	};
	if (~ppRampTargetBpm != 130) {
		fail.("latest wins", "expected glide target 130, got %".format(~ppRampTargetBpm));
	};
	(~clock.beatDur * 1).wait;  // wait one more beat; must not engage again
	if (~ppTempoApplyCount != (applyCountBefore + 1)) {
		fail.("latest wins", "a second apply happened within 1 beat of the first");
	};
	if (waitForTempo.(130, 12).not) {
		fail.("latest wins", "glide never landed on 130 BPM within 12s");
	};
	checkOk.("latest wins");

	// --- B4: malformed input tolerance ---
	{
		var countBefore = ~ppTempoApplyCount;
		var targetBefore = ~ppRampTargetBpm;
		var tempoBefore = ~clock.tempo;
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/bpm');
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/bpm', "fast");
		sendCli.("nan");
		(~clock.beatDur * 2).wait;
		if (~ppTempoApplyCount != countBefore) {
			fail.("malformed ignored", "apply count changed after malformed input");
		};
		if (~ppRampTargetBpm != targetBefore) {
			fail.("malformed ignored", "glide target changed after malformed input");
		};
		if (~clock.tempo != tempoBefore) {
			fail.("malformed ignored", "tempo changed after malformed input");
		};
		countBefore = ~ppTempoApplyCount;
		sendCli.("128");
		if (waitForApplyChange.(countBefore, 3).not) {
			fail.("malformed ignored", "handler did not engage valid 128 after malformed input");
		};
		// A glide to 128 is now in flight; malformed input mid-glide must
		// not add a second engage or disturb the target (T-02-09).
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/bpm');
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/bpm', "fast");
		sendCli.("nan");
		(~clock.beatDur * 1).wait;
		if (~ppTempoApplyCount != (countBefore + 1)) {
			fail.("malformed ignored", "malformed input mid-glide changed the apply count");
		};
		if (~ppRampTargetBpm != 128) {
			fail.("malformed ignored", "malformed input mid-glide changed the glide target (got %)".format(~ppRampTargetBpm));
		};
		if (waitForTempo.(128, 12).not) {
			fail.("malformed ignored", "glide never landed on 128 BPM within 12s");
		};
		checkOk.("malformed ignored");
	}.value;

	// --- B5: non-loopback rejection (T-01-02) ---
	{
		var lanIP = "ipconfig getifaddr en0".unixCmdGetStdOut.stripWhiteSpace;
		if (lanIP.isEmpty) { lanIP = "ipconfig getifaddr en1".unixCmdGetStdOut.stripWhiteSpace };
		if (lanIP.isEmpty) {
			checkSkip.("loopback-only", "no non-loopback IPv4 found");
		} {
			var countBefore = ~ppTempoApplyCount;
			var tempoBefore = ~clock.tempo;
			var transportCountBefore = ~ppTransportCount;
			var epicCountBefore = ~ppEpicCount;
			var epicBefore = ~epic;
			var volumeCountBefore = ~ppVolumeCount;
			var volumeBefore = ~volume;
			NetAddr(lanIP, NetAddr.langPort).sendMsg('/pp/bpm', 77);
			NetAddr(lanIP, NetAddr.langPort).sendMsg('/pp/play', 0);
			NetAddr(lanIP, NetAddr.langPort).sendMsg('/pp/epic', 55);
			NetAddr(lanIP, NetAddr.langPort).sendMsg('/pp/volume', 5);
			(~clock.beatDur * 2).wait;
			if ((~ppTempoApplyCount != countBefore) or: { ~clock.tempo != tempoBefore }) {
				fail.("loopback-only", "apply happened after send from non-loopback address %".format(lanIP));
			};
			if ((~ppTransportCount != transportCountBefore) or: { ~ppPlaying.not }) {
				fail.("loopback-only", "/pp/play changed transport state after send from non-loopback address %".format(lanIP));
			};
			if ((~ppEpicCount != epicCountBefore) or: { ~epic != epicBefore }) {
				fail.("loopback-only", "/pp/epic changed EPIC after send from non-loopback address %".format(lanIP));
			};
			if ((~ppVolumeCount != volumeCountBefore) or: { ~volume != volumeBefore }) {
				fail.("loopback-only", "/pp/volume changed volume after send from non-loopback address %".format(lanIP));
			};
			checkOk.("loopback-only");
		};
	}.value;

	// --- group gate broadcast (RESEARCH Assumption A3, proven before any
	// Stop below relies on it) ---
	{
		var scratchBus, scratchGroup, failMsgs, failOSCFunc, probe, bassVoice;
		failMsgs = [];
		failOSCFunc = OSCFunc({ |msg| failMsgs = failMsgs.add(msg); }, '/fail', s.addr);

		// Positive control first: prove the collector actually sees /fail
		// replies, so an empty collector below means something. This
		// posts one "FAILURE IN SERVER /n_set Node 999999 not found" line;
		// that is expected.
		s.sendMsg('/n_set', 999999, \gate, 0);
		0.3.wait;
		if (failMsgs.isEmpty) {
			fail.("group gate broadcast", "positive control did not produce a /fail reply");
		};
		failMsgs = [];

		SynthDef(\ppNoGateProbe, { |out = 0, amp = 0.1|
			var sig = SinOsc.ar(440) * amp * Line.kr(1, 1, 3, doneAction: 2);
			Out.ar(out, sig ! 2);
		}).add;
		s.sync;

		scratchBus = Bus.audio(s, 2);
		scratchGroup = Group.new(s);

		probe = Synth(\ppNoGateProbe, [\out, scratchBus], scratchGroup);  // no gate control
		bassVoice = Synth(\ppBass, [\out, scratchBus], scratchGroup);  // gate defaults to 1
		NodeWatcher.register(probe, true);
		NodeWatcher.register(bassVoice, true);

		0.3.wait;
		scratchGroup.set(\gate, 0);
		0.5.wait;

		if (failMsgs.notEmpty) {
			fail.("group gate broadcast", "server sent /fail after group-wide gate broadcast: %".format(failMsgs));
		};
		if (probe.isPlaying.not) {
			fail.("group gate broadcast", "no-gate probe stopped playing after gate broadcast (it must ignore a gate it does not have)");
		};
		if (bassVoice.isPlaying) {
			fail.("group gate broadcast", "gated bass voice still playing after gate broadcast (it must release through its envelope and free)");
		};

		scratchGroup.free;
		scratchBus.free;
		failOSCFunc.free;
		checkOk.("group gate broadcast");
	}.value;

	// --- play idempotent ---
	{
		var countBefore = ~ppTransportCount;
		sendPlay.(1);
		sendPlay.(1);
		0.5.wait;
		if (~ppTransportCount != countBefore) {
			fail.("play idempotent", "transport count changed on repeated /pp/play 1 while already playing");
		};
		~ppLayers.do { |name|
			if (Pbindef(name).isPlaying.not) {
				fail.("play idempotent", "Pbindef(%) stopped playing after repeated /pp/play 1".format(name));
			};
		};
		stopSentAt = Main.elapsedTime;
		sendPlay.(0);
		sendPlay.(0);
		0.5.wait;
		if (~ppTransportCount != (countBefore + 1)) {
			fail.("play idempotent", "expected exactly 1 transport change, got %".format(~ppTransportCount - countBefore));
		};
		if (~ppPlaying) {
			fail.("play idempotent", "~ppPlaying still true after repeated /pp/play 0");
		};
		checkOk.("play idempotent");
	}.value;

	// --- stop releases all ---
	{
		var count = instrChildCount.();
		while ({ (count != 0) and: { (Main.elapsedTime - stopSentAt) < 2.5 } }) {
			0.2.wait;
			count = instrChildCount.();
		};
		if (count != 0) {
			fail.("stop releases all", "instrument group still has % children % s after stop".format(count, Main.elapsedTime - stopSentAt));
		};
		(~clock.beatDur * 2).wait;  // nothing new is scheduled while stopped
		count = instrChildCount.();
		if (count != 0) {
			fail.("stop releases all", "instrument group has % children 2 beats after emptying".format(count));
		};
		checkOk.("stop releases all");
	}.value;

	// --- start on bar: Start re-enters exactly on a quant:4 bar line ---
	{
		var firstGoBeat = nil, nGoOSCFunc, elapsed8b = 0, eventBeat, timeoutSec;
		timeoutSec = (~clock.beatDur * 4) + 1.5;
		nGoOSCFunc = OSCFunc({ |msg|
			if (firstGoBeat.isNil and: { msg[2] == ~ppInstrGroup.nodeID }) {
				firstGoBeat = ~clock.beats;
			};
		}, '/n_go', s.addr);
		sendPlay.(1);
		while ({ firstGoBeat.isNil and: { elapsed8b < timeoutSec } }) {
			0.05.wait;
			elapsed8b = elapsed8b + 0.05;
		};
		if (firstGoBeat.isNil) {
			fail.("start on bar", "no /n_go for ~ppInstrGroup within % s".format(timeoutSec));
		};
		// The notification arrives one server latency after the event's
		// logical time.
		eventBeat = firstGoBeat - ((s.latency ? 0.2) * ~clock.tempo);
		if ((eventBeat - eventBeat.round(4)).abs > 0.15) {
			fail.("start on bar", "event beat % is not within 0.15 of a 4-beat bar line (firstGoBeat %)".format(eventBeat, firstGoBeat));
		};
		if (~ppPlaying.not) {
			fail.("start on bar", "~ppPlaying is false after /pp/play 1");
		};
		~ppLayers.do { |name|
			if (Pbindef(name).isPlaying.not) {
				fail.("start on bar", "Pbindef(%) not playing after /pp/play 1".format(name));
			};
		};
		nGoOSCFunc.free;
		checkOk.("start on bar");
	}.value;

	// --- play malformed ignored ---
	{
		var countBefore = ~ppTransportCount;
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/play');
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/play', "stop");
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/play', 0.0/0.0);
		0.5.wait;
		if (~ppTransportCount != countBefore) {
			fail.("play malformed ignored", "transport count changed after malformed /pp/play input");
		};
		if (~ppPlaying.not) {
			fail.("play malformed ignored", "~ppPlaying became false after malformed /pp/play input");
		};
		~ppLayers.do { |name|
			if (Pbindef(name).isPlaying.not) {
				fail.("play malformed ignored", "Pbindef(%) not playing after malformed /pp/play input".format(name));
			};
		};
		sendPlay.(0);
		0.5.wait;
		if (~ppPlaying) {
			fail.("play malformed ignored", "~ppPlaying still true after /pp/play 0 (handler broken after malformed input)");
		};
		sendPlay.(1);
		if (waitForPlaying.(true, 2).not) {
			fail.("play malformed ignored", "~ppPlaying did not become true again after /pp/play 1");
		};
		checkOk.("play malformed ignored");
	}.value;

	// --- stop cuts held pad (T-02-16): Stop empties the instrument group
	// well inside the pad's own natural tail (dur 4, legato 0.9, 1.2s
	// release -- about 3s at 100 BPM). "FAILURE IN SERVER /n_set Node N
	// not found" lines in the log after this Stop are expected (same race
	// as Plan 01's Stop broadcasts) and are not failures. ---
	{
		var stopAt, count, elapsedSc, naturalEnd, zeroAt = nil;
		sendBpm.(100);
		if (waitForTempo.(100, 12).not) {
			fail.("stop cuts held pad", "glide never landed on 100 BPM within 12s");
		};
		// Wait until 0.35s after the next bar line, so the bar's pad chord
		// has already started on the server.
		((~clock.timeToNextBeat(4) * ~clock.beatDur) + 0.35).wait;
		stopAt = Main.elapsedTime;
		sendPlay.(0);
		count = instrChildCount.();
		elapsedSc = 0;
		while ({ (count != 0) and: { elapsedSc < 4 } }) {
			0.1.wait;
			elapsedSc = elapsedSc + 0.1;
			count = instrChildCount.();
		};
		if (count == 0) { zeroAt = Main.elapsedTime };
		if (zeroAt.isNil) {
			fail.("stop cuts held pad", "instrument group never emptied within 4s after stop");
		};
		if ((zeroAt - stopAt) > 2.0) {
			fail.("stop cuts held pad", "instrument group took % s to empty, expected <= 2.0 s".format(zeroAt - stopAt));
		};
		// This must follow the pad Pbindef/SynthDef (\dur 4, \legato 0.9,
		// 1.2s release) if the pad is retuned -- it proves the check is
		// actually discriminating (the natural tail is well past 2.4s).
		naturalEnd = (4 * 0.9 * ~clock.beatDur) + 1.2 - 0.35;
		if (naturalEnd <= 2.4) {
			fail.("stop cuts held pad", "check not discriminating: naturalEnd % <= 2.4".format(naturalEnd));
		};
		sendPlay.(1);
		if (waitForPlaying.(true, 2).not) {
			fail.("stop cuts held pad", "~ppPlaying did not become true again after /pp/play 1");
		};
		checkOk.("stop cuts held pad");
	}.value;

	// --- stop catches in-flight notes (T-02-16): a Stop scheduled at the
	// exact logical time of a bar line still empties the instrument group,
	// whichever order it and that bar's already-in-flight notes land in.
	// An unreleased in-flight pad chord would ring for about 3.4s at
	// 100 BPM. ---
	{
		var stopAt, count, elapsedSc, playingElapsed = 0;
		~clock.schedAbs(~clock.nextTimeOnGrid(4), { ~ppStop.value; nil });
		while ({ ~ppPlaying and: { playingElapsed < 4 } }) {
			0.1.wait;
			playingElapsed = playingElapsed + 0.1;
		};
		if (~ppPlaying) {
			fail.("stop catches in-flight notes", "~ppPlaying never became false within 4s of the scheduled Stop");
		};
		stopAt = Main.elapsedTime;
		count = instrChildCount.();
		elapsedSc = 0;
		while ({ (count != 0) and: { elapsedSc < 4 } }) {
			0.1.wait;
			elapsedSc = elapsedSc + 0.1;
			count = instrChildCount.();
		};
		if (count != 0) {
			fail.("stop catches in-flight notes", "instrument group still has % children % s after stop".format(count, Main.elapsedTime - stopAt));
		};
		if ((Main.elapsedTime - stopAt) > 2.0) {
			fail.("stop catches in-flight notes", "instrument group took % s to empty, expected <= 2.0 s".format(Main.elapsedTime - stopAt));
		};
		sendPlay.(1);
		if (waitForPlaying.(true, 2).not) {
			fail.("stop catches in-flight notes", "~ppPlaying did not become true again after /pp/play 1");
		};
		checkOk.("stop catches in-flight notes");
	}.value;

	// --- fx chain order (EPIC-01/02): the smoother runs before the FX
	// synth within ~ppFxGroup, so \ppFx always reads this block's fresh
	// smoothed value, never the previous block's stale one. ---
	{
		var order = groupChildDefs.(~ppFxGroup);
		if (order != [\ppEpicSmoother, \ppFx]) {
			fail.("fx chain order", "~ppFxGroup children % != [ppEpicSmoother, ppFx]".format(order));
		};
		checkOk.("fx chain order");
	}.value;

	// stepBound: 1.5x the largest 20ms move a 60dB exponential lag of
	// ~ppEpicLagSecs can make on a full-scale (0..1) change -- about 0.13
	// at 1.5s. Tracks the tuning var. Scaled per-sample-pair by the actual
	// PulseCount gap so a dropped /pp/test/ctl reply can never cause a
	// false failure.
	stepBound = 1.5 * (1 - (0.001 ** (0.02 / ~ppEpicLagSecs)));

	// --- epic glide up (EPIC-02): monotone, bounded, convergent from 0 to
	// 100, with genuine intermediate values (not a step). ---
	{
		var t, i, gap, rise, between = 0;
		sendEpic.(0);
		if (waitEpicSettled.(0.0, 4).not) {
			fail.("epic glide up", "smoothed EPIC bus never settled to 0.0 within 4s");
		};
		t = traceCtl.(~ppEpicSmoothBus.index, 2.5, { sendEpic.(100); });
		if (t.size < 100) {
			fail.("epic glide up", "only % samples collected, expected >= 100".format(t.size));
		};
		if (t.first[0] > 0.01) {
			fail.("epic glide up", "first sample % is not near 0".format(t.first[0]));
		};
		i = 1;
		while ({ i < t.size }) {
			gap = t[i][1] - t[i - 1][1];
			if (gap < 1) {
				fail.("epic glide up", "PulseCount did not advance between samples % and %".format(i - 1, i));
			};
			rise = t[i][0] - t[i - 1][0];
			// -1e-3, not -1e-4: waitEpicSettled's own 0.005 tolerance means
			// the trace's pre-roll samples can still carry a few 1e-4-scale
			// ticks of the PREVIOUS settle's tail decay before the actual
			// glide-up action fires -- this is residual convergence noise,
			// not a real reversal. -1e-3 absorbs that while staying far
			// below stepBound's real-jump scale (~0.1).
			if (rise < -1e-3) {
				fail.("epic glide up", "value fell by % between samples % and % (expected monotone rise)".format(rise, i - 1, i));
			};
			if (rise > (stepBound * gap)) {
				fail.("epic glide up", "value jumped by % (bound %) between samples % and %".format(rise, stepBound * gap, i - 1, i));
			};
			if ((t[i][0] > 0.2) and: { t[i][0] < 0.8 }) { between = between + 1; };
			i = i + 1;
		};
		if (between < 3) {
			fail.("epic glide up", "only % samples strictly between 0.2 and 0.8, expected >= 3".format(between));
		};
		if (t.last[0] < 0.99) {
			fail.("epic glide up", "final sample % did not reach 0.99".format(t.last[0]));
		};
		checkOk.("epic glide up");
	}.value;

	// --- epic glide down (EPIC-02): monotone, bounded, convergent from
	// the settled 1.0 back down to the default 10 (0.10). ---
	{
		var t, i, gap, drop, between = 0;
		t = traceCtl.(~ppEpicSmoothBus.index, 2.5, { sendEpic.(10); });
		i = 1;
		while ({ i < t.size }) {
			gap = t[i][1] - t[i - 1][1];
			if (gap < 1) {
				fail.("epic glide down", "PulseCount did not advance between samples % and %".format(i - 1, i));
			};
			drop = t[i - 1][0] - t[i][0];
			// -1e-3, same reasoning as "epic glide up": absorbs residual
			// settle-tail noise in the pre-roll samples, not a real reversal.
			if (drop < -1e-3) {
				fail.("epic glide down", "value rose by % between samples % and % (expected monotone non-increasing)".format(drop.neg, i - 1, i));
			};
			if (drop > (stepBound * gap)) {
				fail.("epic glide down", "value dropped by % (bound %) between samples % and %".format(drop, stepBound * gap, i - 1, i));
			};
			if ((t[i][0] > 0.25) and: { t[i][0] < 0.85 }) { between = between + 1; };
			i = i + 1;
		};
		if (between < 3) {
			fail.("epic glide down", "only % samples strictly between 0.25 and 0.85, expected >= 3".format(between));
		};
		if ((t.last[0] - 0.10).abs >= 0.005) {
			fail.("epic glide down", "final sample % is not within 0.005 of 0.10".format(t.last[0]));
		};
		checkOk.("epic glide down");
	}.value;

	// --- epic retarget mid-glide (EPIC-02/EPIC-03 adjacency): a second
	// /pp/epic sent mid-glide bends from the current value with no jump,
	// never nearly reaches the abandoned target, and settles on the new one. ---
	{
		var t, i, gap, change, sawAboveHalf = false, maxSample = 0;
		t = traceCtl.(~ppEpicSmoothBus.index, 3.0, { sendEpic.(100); 0.25.wait; sendEpic.(30); });
		i = 1;
		while ({ i < t.size }) {
			gap = t[i][1] - t[i - 1][1];
			if (gap < 1) {
				fail.("epic retarget mid-glide", "PulseCount did not advance between samples % and %".format(i - 1, i));
			};
			change = (t[i][0] - t[i - 1][0]).abs;
			if (change > (stepBound * gap)) {
				fail.("epic retarget mid-glide", "value changed by % (bound %) between samples % and %".format(change, stepBound * gap, i - 1, i));
			};
			if (t[i][0] > 0.5) { sawAboveHalf = true; };
			maxSample = max(maxSample, t[i][0]);
			i = i + 1;
		};
		if (sawAboveHalf.not) {
			fail.("epic retarget mid-glide", "no sample exceeded 0.5 -- the first glide toward 100 never got under way");
		};
		if (maxSample >= 0.9) {
			fail.("epic retarget mid-glide", "max sample % nearly reached the abandoned target of 1.0".format(maxSample));
		};
		if ((t.last[0] - 0.30).abs >= 0.005) {
			fail.("epic retarget mid-glide", "final sample % is not within 0.005 of 0.30".format(t.last[0]));
		};
		checkOk.("epic retarget mid-glide");
	}.value;

	// --- EPIC clamp table (EPIC-01 boundary, one step either side, sent
	// through the real Python CLI like Phase 1's BPM clamp table) ---
	[
		[150, 100, "epic clamp 150->100"],
		[101, 100, "epic clamp 101->100"],
		[100, 100, "epic clamp 100"],
		[0, 0, "epic clamp 0"],
		[-1, 0, "epic clamp -1->0"],
		[-50, 0, "epic clamp -50->0"],
		[37.5, 37.5, "epic float 37.5"],
	].do({ |entry|
		var sent = entry[0], expected = entry[1], name = entry[2];
		var before = ~ppEpicCount;
		var rc, elapsedCl = 0;
		rc = sendCli.("--epic " ++ sent.asString);
		if (rc != 0) {
			fail.(name, "osc_client.py exited %".format(rc));
		};
		while ({ (~ppEpicCount == before) and: { elapsedCl < 3 } }) {
			0.1.wait;
			elapsedCl = elapsedCl + 0.1;
		};
		if (~ppEpicCount == before) {
			fail.(name, "~ppEpicCount did not change within 3s for sent=%".format(sent));
		};
		if ((~epic - expected).abs >= 1e-6) {
			fail.(name, "expected ~epic %, got %".format(expected, ~epic));
		};
		checkOk.(name);
	});
	if (waitEpicSettled.(0.375, 4).not) {
		fail.("epic float 37.5", "smoothed EPIC bus never settled to 0.375 within 4s");
	};

	// --- epic malformed ignored (EPIC-01 input contract) ---
	{
		var countBefore = ~ppEpicCount;
		var epicBefore = ~epic;
		var ctlBefore = readCtl.(~ppEpicSmoothBus.index);
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/epic');
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/epic', "loud");
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/epic', 0.0/0.0);
		sendCli.("--epic nan");
		0.5.wait;
		if (~ppEpicCount != countBefore) {
			fail.("epic malformed ignored", "~ppEpicCount changed after malformed /pp/epic input");
		};
		if (~epic != epicBefore) {
			fail.("epic malformed ignored", "~epic changed after malformed /pp/epic input");
		};
		if ((readCtl.(~ppEpicSmoothBus.index) - ctlBefore).abs > 0.005) {
			fail.("epic malformed ignored", "smoothed EPIC bus moved after malformed /pp/epic input");
		};
		sendEpic.(30);
		{
			var elapsedEp = 0;
			while ({ (~ppEpicCount == countBefore) and: { elapsedEp < 2 } }) {
				0.1.wait;
				elapsedEp = elapsedEp + 0.1;
			};
		}.value;
		if (~ppEpicCount != (countBefore + 1)) {
			fail.("epic malformed ignored", "expected exactly 1 apply for the valid 30 after malformed input, got %".format(~ppEpicCount - countBefore));
		};
		if (~epic != 30) {
			fail.("epic malformed ignored", "expected ~epic == 30, got %".format(~epic));
		};
		checkOk.("epic malformed ignored");
		sendEpic.(10);
		if (waitEpicSettled.(0.1, 4).not) {
			fail.("epic malformed ignored", "smoothed EPIC bus never settled back to the default 0.1 within 4s");
		};
	}.value;

	// --- volume clamp table (GUI-03 boundary, one step either side, sent
	// through the real Python CLI like the EPIC clamp table above) ---
	[
		[150, 100, "volume clamp 150->100"],
		[101, 100, "volume clamp 101->100"],
		[100, 100, "volume clamp 100"],
		[0, 0, "volume clamp 0"],
		[-1, 0, "volume clamp -1->0"],
		[62.5, 62.5, "volume float 62.5"],
	].do({ |entry|
		var sent = entry[0], expected = entry[1], name = entry[2];
		var before = ~ppVolumeCount;
		var rc, elapsedVc = 0;
		rc = sendCli.("--volume " ++ sent.asString);
		if (rc != 0) {
			fail.(name, "osc_client.py exited %".format(rc));
		};
		while ({ (~ppVolumeCount == before) and: { elapsedVc < 3 } }) {
			0.1.wait;
			elapsedVc = elapsedVc + 0.1;
		};
		if (~ppVolumeCount == before) {
			fail.(name, "~ppVolumeCount did not change within 3s for sent=%".format(sent));
		};
		if ((~volume - expected).abs >= 1e-6) {
			fail.(name, "expected ~volume %, got %".format(expected, ~volume));
		};
		if ((readCtl.(~ppVolumeBus.index) - ~ppVolumeAmp.(expected)).abs >= 1e-4) {
			fail.(name, "raw volume bus % does not hold the taper of the clamped value % (expected %)".format(readCtl.(~ppVolumeBus.index), expected, ~ppVolumeAmp.(expected)));
		};
		checkOk.(name);
	});
	{
		var before = ~ppVolumeCount, elapsedVc = 0;
		sendVolume.(80);
		while ({ (~ppVolumeCount == before) and: { elapsedVc < 3 } }) {
			0.1.wait;
			elapsedVc = elapsedVc + 0.1;
		};
	}.value;

	// --- volume malformed ignored (GUI-03 input contract) ---
	{
		var countBefore = ~ppVolumeCount;
		var volumeBefore = ~volume;
		var ctlBefore = readCtl.(~ppVolumeBus.index);
		var elapsedVm;
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/volume');
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/volume', "loud");
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/volume', 0.0/0.0);
		sendCli.("--volume nan");
		0.5.wait;
		if (~ppVolumeCount != countBefore) {
			fail.("volume malformed ignored", "~ppVolumeCount changed after malformed /pp/volume input");
		};
		if (~volume != volumeBefore) {
			fail.("volume malformed ignored", "~volume changed after malformed /pp/volume input");
		};
		if ((readCtl.(~ppVolumeBus.index) - ctlBefore).abs > 1e-4) {
			fail.("volume malformed ignored", "raw volume bus moved after malformed /pp/volume input");
		};
		sendVolume.(70);
		elapsedVm = 0;
		while ({ (~ppVolumeCount == countBefore) and: { elapsedVm < 2 } }) {
			0.1.wait;
			elapsedVm = elapsedVm + 0.1;
		};
		if (~ppVolumeCount != (countBefore + 1)) {
			fail.("volume malformed ignored", "expected exactly 1 apply for the valid 70 after malformed input, got %".format(~ppVolumeCount - countBefore));
		};
		if (~volume != 70) {
			fail.("volume malformed ignored", "expected ~volume == 70, got %".format(~volume));
		};
		checkOk.("volume malformed ignored");
		sendVolume.(80);
	}.value;

	// --- volume glides (GUI-03): an isolated \ppMaster instance on scratch
	// buses proves the 0.2s lag de-zippers a volume step instead of
	// stepping instantly, without touching the real audio chain. ---
	{
		var scratchIn, scratchOut, scratchVol, scratchGroup;
		var dc, masterProbe, levelProbe;
		var samples, preCount, i, monotoneOk = true, between = 0;

		scratchIn = Bus.audio(s, 2);
		scratchOut = Bus.audio(s, 2);
		scratchVol = Bus.control(s, 1);
		scratchVol.set(1.0);
		scratchGroup = Group.new(s, \addToTail);
		ctlSamples = List.new;

		dc = Synth.head(scratchGroup, \ppDcSource, [\out, scratchIn.index]);
		masterProbe = Synth.after(dc, \ppMaster, [\in, scratchIn.index, \out, scratchOut.index, \preGain, 1, \volumeBus, scratchVol.index]);
		levelProbe = Synth.tail(scratchGroup, \ppLevelProbe, [\in, scratchOut.index]);

		0.3.wait;
		preCount = ctlSamples.size;
		scratchVol.set(0);
		0.6.wait;

		scratchGroup.free;
		scratchIn.free;
		scratchOut.free;
		scratchVol.free;
		samples = ctlSamples;
		ctlSamples = nil;

		if (preCount < 5) {
			fail.("volume glides", "only % samples collected before the step, expected >= 5".format(preCount));
		};
		i = max(0, preCount - 5);
		while ({ i < preCount }) {
			if ((samples[i][0] - 0.5).abs > 0.01) {
				fail.("volume glides", "pre-step sample % (index %) is not within 0.01 of 0.5".format(samples[i][0], i));
			};
			i = i + 1;
		};
		i = preCount;
		while ({ i < (samples.size - 1) }) {
			if ((samples[i + 1][0] - samples[i][0]) > 1e-4) {
				monotoneOk = false;
			};
			if ((samples[i][0] > 0.05) and: { samples[i][0] < 0.45 }) { between = between + 1; };
			i = i + 1;
		};
		if (monotoneOk.not) {
			fail.("volume glides", "post-step samples are not monotone non-increasing");
		};
		if (between < 3) {
			fail.("volume glides", "only % post-step samples strictly between 0.05 and 0.45, expected >= 3".format(between));
		};
		if (samples.last[0] >= 0.005) {
			fail.("volume glides", "final sample % is not below 0.005".format(samples.last[0]));
		};
		checkOk.("volume glides");
	}.value;

	// --- B6: node-leak bound ---
	{
		var maxSynths = 0, elapsed6 = 0;
		sendCli.("180");
		if (waitForTempo.(180, 12).not) {
			fail.("node bound", "glide never landed on 180 BPM within 12s");
		};
		while ({ elapsed6 < 8 }) {
			maxSynths = max(maxSynths, s.numSynths);
			0.25.wait;
			elapsed6 = elapsed6 + 0.25;
		};
		"PedalPulse smoke: max synths = %".format(maxSynths).postln;
		// Bound raised from 20 to 22: the two persistent FX-group synths
		// (\ppEpicSmoother, \ppFx) are always counted now; the per-note
		// bound is unchanged.
		if (maxSynths > 22) {
			fail.("node bound", "max synths % exceeds 22".format(maxSynths));
		};
		checkOk.("node bound");
	}.value;

	// --- B7: mix headroom + limiter, no bypass + ceiling (ENG-02, D-16, D-17) ---
	{
		var peakMix, peak0, peak1, peak8, mixProbe;

		// --- fx headroom: at the default EPIC (10, Recovery), the post-FX
		// peak stays under the limiter ceiling, so the limiter stays a
		// safety net rather than doing constant work at ordinary settings.
		// Run before "mix headroom" so EPIC is still the default 10. ---
		peakVal = 0.0;
		{
			var probe = Synth.after(~ppFxGroup, \ppPeakProbe, [\in, ~ppFxBus.index]);
			4.wait;
			probe.free;
		}.value;
		"PedalPulse smoke: post-FX peak at EPIC 10 = %".format(peakVal).postln;
		if (peakVal > 0.891) {
			fail.("fx headroom", "post-FX peak % at EPIC 10 exceeds 0.891".format(peakVal));
		};
		checkOk.("fx headroom");
		// Informational only (Phase 4 soak), not an assertion.
		"PedalPulse smoke: server CPU avg % peak %".format(s.avgCPU, s.peakCPU).postln;

		// --- mix headroom: the pre-limiter sum on ~ppMixBus stays under the
		// limiter ceiling at default gain, so the limiter is a safety net
		// rather than a constant compressor. Probe is placed after
		// ~ppInstrGroup (which writes ~ppMixBus) and before ~ppMasterGroup
		// (which reads and limits it), so it sees the raw sum. ---
		~ppMasterSynth.set(\preGain, 1);
		peakVal = 0.0;
		mixProbe = Synth.after(~ppInstrGroup, \ppPeakProbe, [\in, ~ppMixBus.index]);
		4.wait;
		mixProbe.free;
		peakMix = peakVal;
		"PedalPulse smoke: pre-limiter mix peak = %".format(peakMix).postln;
		if (peakMix > 0.891) {
			fail.("mix headroom", "pre-limiter mix peak % exceeds 0.891".format(peakMix));
		};
		checkOk.("mix headroom");

		~ppMasterSynth.set(\preGain, 0);
		0.5.wait;
		peak0 = measurePeak.(0, 2);
		if (peak0 >= 0.001) {
			fail.("limiter no bypass", "peak % with preGain 0 (expected < 0.001)".format(peak0));
		};
		checkOk.("limiter no bypass");

		~ppMasterSynth.set(\preGain, 1);
		peak1 = measurePeak.(0, 2);
		"PedalPulse smoke: peak at preGain 1 = %".format(peak1).postln;

		// Run the limiter-ceiling check at the hottest FX state (EPIC 100)
		// and at max volume (GUI-03) so the existing preGain-8 post line
		// reports the EPIC 100 + volume 100 level.
		sendEpic.(100);
		{
			var volCountBefore = ~ppVolumeCount, elapsedV2 = 0;
			sendVolume.(100);
			while ({ (~ppVolumeCount == volCountBefore) and: { elapsedV2 < 3 } }) {
				0.1.wait;
				elapsedV2 = elapsedV2 + 0.1;
			};
			0.5.wait;
		}.value;
		if (waitEpicSettled.(1.0, 4).not) {
			fail.("limiter ceiling", "smoothed EPIC bus never settled to 1.0 within 4s");
		};
		~ppMasterSynth.set(\preGain, 8);
		0.5.wait;
		peak8 = measurePeak.(0, 2);
		if ((peak8 > 0.5).not or: { peak8 > 0.90 }) {
			fail.("limiter ceiling", "peak % with preGain 8 at EPIC 100 (expected in (0.5, 0.90])".format(peak8));
		};
		checkOk.("limiter ceiling");

		~ppMasterSynth.set(\preGain, ~preGain);

		// --- max epic max volume no clip (ROADMAP success criterion 4):
		// VO2's EPIC value and the slider maximum, sent together through
		// the real Python path, must never exceed the limiter ceiling. ---
		{
			var epicCountBefore2 = ~ppEpicCount, volCountBefore2 = ~ppVolumeCount;
			var elapsedMx = 0;
			var preLimiterProbe, outPeak;
			if (sendCli.("--epic 100 --volume 100") != 0) {
				fail.("max epic max volume no clip", "osc_client.py exited non-zero for --epic 100 --volume 100");
			};
			while ({ ((~ppEpicCount == epicCountBefore2) or: { ~ppVolumeCount == volCountBefore2 }) and: { elapsedMx < 3 } }) {
				0.1.wait;
				elapsedMx = elapsedMx + 0.1;
			};
			if (~ppEpicCount == epicCountBefore2) {
				fail.("max epic max volume no clip", "~ppEpicCount did not change within 3s");
			};
			if (~ppVolumeCount == volCountBefore2) {
				fail.("max epic max volume no clip", "~ppVolumeCount did not change within 3s");
			};
			if (~epic != 100) {
				fail.("max epic max volume no clip", "expected ~epic == 100, got %".format(~epic));
			};
			if (~volume != 100) {
				fail.("max epic max volume no clip", "expected ~volume == 100, got %".format(~volume));
			};
			if (waitEpicSettled.(1.0, 4).not) {
				fail.("max epic max volume no clip", "smoothed EPIC bus never settled to 1.0 within 4s");
			};
			0.5.wait;  // let the master's 0.2s volume lag settle too

			peakVal = 0.0;
			preLimiterProbe = Synth.after(~ppFxGroup, \ppPeakProbe, [\in, ~ppFxBus.index]);
			4.wait;
			preLimiterProbe.free;

			outPeak = measurePeak.(0, 8);
			"PedalPulse smoke: VO2 + volume 100: pre-limiter peak = %, output peak = %".format(peakVal, outPeak).postln;
			// no-clip threshold is the ceiling (0.891251) plus tolerance:
			if ((outPeak <= 0.892).not) {
				fail.("max epic max volume no clip", "output peak % exceeds the limiter ceiling plus tolerance 0.892".format(outPeak));
			};
			if (outPeak <= 0.1) {
				fail.("max epic max volume no clip", "output peak % is at or below the silence floor 0.1 -- no real audio flowing".format(outPeak));
			};
			checkOk.("max epic max volume no clip");
		}.value;

		sendEpic.(10);
		if (waitEpicSettled.(0.1, 4).not) {
			fail.("limiter ceiling", "smoothed EPIC bus never settled back to the default 0.1 within 4s");
		};
		sendVolume.(80);
	}.value;

	// --- B8: re-evaluation idempotence (ENG-04 concurrency) ---
	{
		var oldClock = ~clock;
		var oldMaster = ~ppMasterSynth;
		var oldFx, oldSmoother, oldFxGroup, oldBuses, oldVolBus;
		var bpmBeforeReload = ~bpm;
		var elapsed8, countBefore;

		NodeWatcher.register(oldMaster, true);

		// EPIC-01/02 leak check: settle on a non-default value so "no glide
		// from 0, no jump to the default on re-evaluation" is discriminating,
		// then capture every FX-related node/group/bus to prove none of it
		// survives the teardown below.
		sendEpic.(75);
		if (waitEpicSettled.(0.75, 4).not) {
			fail.("fx re-evaluation", "smoothed EPIC bus never settled to 0.75 within 4s");
		};
		{
			var volCountBefore3 = ~ppVolumeCount, elapsedV3 = 0;
			sendVolume.(35);
			while ({ (~ppVolumeCount == volCountBefore3) and: { elapsedV3 < 3 } }) {
				0.1.wait;
				elapsedV3 = elapsedV3 + 0.1;
			};
		}.value;
		oldFx = ~ppFxSynth;
		oldSmoother = ~ppEpicSmoother;
		oldFxGroup = ~ppFxGroup;
		oldBuses = [~ppFxBus, ~ppEpicBus, ~ppEpicSmoothBus];
		oldVolBus = ~ppVolumeBus;
		NodeWatcher.register(oldFx, true);
		NodeWatcher.register(oldSmoother, true);

		~ppReady = false;
		(root +/+ "supercollider/main.scd").load;

		elapsed8 = 0;
		while ({ ~ppReady.not and: { elapsed8 < 30 } }) {
			0.5.wait;
			elapsed8 = elapsed8 + 0.5;
		};
		if (~ppReady.not) {
			fail.("re-evaluation", "engine never became ready again after reload");
		};

		if (~ppPlaying.not) {
			fail.("re-evaluation", "~ppPlaying is false after reload (autostart should bring it back up)");
		};
		~ppLayers.do { |name|
			if (Pbindef(name).isPlaying.not) {
				fail.("re-evaluation", "Pbindef(%) not playing after reload (autostart should bring it back up)".format(name));
			};
		};

		if (oldClock.isRunning) {
			fail.("re-evaluation", "old clock still running after reload");
		};
		if (oldMaster.isPlaying) {
			fail.("re-evaluation", "old master synth still playing after reload");
		};
		if (~ppMasterSynth.nodeID == oldMaster.nodeID) {
			fail.("re-evaluation", "master synth node ID unchanged after reload -- not actually replaced");
		};
		// isPlaying/isRunning on a freshly-created, unwatched Node reflects
		// its unset default, not real server state (the n_go notification for
		// its creation already passed before NodeWatcher could observe it).
		// Prove it is genuinely alive behaviorally instead: real audio must
		// flow through it once the loop is playing again.
		{
			var probe;
			peakVal = 0.0;
			probe = Synth.after(~ppMasterGroup, \ppPeakProbe, [\in, 0]);
			1.0.wait;
			probe.free;
			if (peakVal <= 0.0) {
				fail.("re-evaluation", "no audio measured through the new master synth after reload");
			};
		}.value;
		if ((~clock.tempo * 60 - bpmBeforeReload).abs >= 1e-6) {
			fail.("re-evaluation", "tempo changed across reload: expected % got %".format(bpmBeforeReload, ~clock.tempo * 60));
		};

		countBefore = ~ppTempoApplyCount;
		sendCli.("128");
		if (waitForApplyChange.(countBefore, 3).not) {
			fail.("re-evaluation", "glide never engaged after reload");
		};
		if (waitForTempo.(128, 12).not) {
			fail.("re-evaluation", "glide never landed on 128 BPM after reload");
		};
		if (((~ppRampLandBeat - ~ppRampStartBeat) < 6) or: { (~ppRampLandBeat - ~ppRampStartBeat) > 9 }) {
			fail.("re-evaluation", "glide took % beats, expected 6-9 (a stacked second stepper would halve it)".format(~ppRampLandBeat - ~ppRampStartBeat));
		};

		checkOk.("re-evaluation");

		// --- fx re-evaluation (EPIC-01/02 Pitfall 2): the teardown frees
		// the previous FX-related synths, group and buses -- none of it
		// survives a re-evaluation, and the preserved EPIC value reaches
		// the new smoothed bus immediately, with no glide from 0. ---
		if (oldFx.isPlaying) {
			fail.("fx re-evaluation", "old FX synth still playing after reload");
		};
		if (oldSmoother.isPlaying) {
			fail.("fx re-evaluation", "old EPIC smoother still playing after reload");
		};
		oldBuses.do { |bus|
			if (bus.index.notNil) {
				fail.("fx re-evaluation", "old bus % still has a non-nil index % after reload (Bus.free sets it to nil)".format(bus, bus.index));
			};
		};
		if (~ppFxSynth.nodeID == oldFx.nodeID) {
			fail.("fx re-evaluation", "FX synth node ID unchanged after reload -- not actually replaced");
		};
		if (~ppEpicSmoother.nodeID == oldSmoother.nodeID) {
			fail.("fx re-evaluation", "EPIC smoother node ID unchanged after reload -- not actually replaced");
		};
		if (groupChildDefs.(~ppFxGroup) != [\ppEpicSmoother, \ppFx]) {
			fail.("fx re-evaluation", "~ppFxGroup children % != [ppEpicSmoother, ppFx] after reload".format(groupChildDefs.(~ppFxGroup)));
		};
		if (~epic != 75) {
			fail.("fx re-evaluation", "~epic % != 75 after reload (last value should be preserved)".format(~epic));
		};
		if ((readCtl.(~ppEpicSmoothBus.index) - 0.75).abs >= 0.01) {
			fail.("fx re-evaluation", "smoothed EPIC bus % is not within 0.01 of 0.75 immediately after reload (no glide from 0, no jump to the default)".format(readCtl.(~ppEpicSmoothBus.index)));
		};
		checkOk.("fx re-evaluation");

		// --- volume re-evaluation (GUI-03, same leak discipline as EPIC):
		// the old volume bus is freed, the last volume survives reload, and
		// the new bus holds its taper immediately. ---
		if (oldVolBus.index.notNil) {
			fail.("volume re-evaluation", "old volume bus still has a non-nil index % after reload (Bus.free sets it to nil)".format(oldVolBus.index));
		};
		if (~volume != 35) {
			fail.("volume re-evaluation", "~volume % != 35 after reload (last value should be preserved)".format(~volume));
		};
		if (~ppVolumeBus.index.isNil) {
			fail.("volume re-evaluation", "new volume bus has a nil index after reload");
		};
		if ((readCtl.(~ppVolumeBus.index) - ~ppVolumeAmp.(35)).abs >= 1e-4) {
			fail.("volume re-evaluation", "new volume bus % is not within 1e-4 of the taper of 35 (%)".format(readCtl.(~ppVolumeBus.index), ~ppVolumeAmp.(35)));
		};
		checkOk.("volume re-evaluation");
	}.value;

	"SMOKE PASS".postln;
	s.quit(onComplete: { 0.exit });
	}.try({ |err|
		"SMOKE FAIL: %".format(err.errorString).postln;
		s.quit(onComplete: { 1.exit });
	});
}, AppClock);
)
