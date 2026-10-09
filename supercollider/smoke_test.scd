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
var sendPlay, instrChildCount, instrDefNames;
var peakVal = 0.0, peakOSCdef;
var sendBpm, waitForTempo, traceGlide, lastTrace;
var sendEpic, traceCtl, readCtl, waitEpicSettled, measureBand;
var ctlSamples, bandSum = 0, bandCount = 0, ctlOSCdef, bandOSCdef;

// Watchdog first, in case anything below hangs. Raised from 120 to 240s:
// the Task 2 glide checks (glide reaches target/upward, retarget mid-glide)
// each wait for an ~8-beat glide to land, adding roughly 40s overall.
SystemClock.sched(240, { "SMOKE FAIL: watchdog timeout".postln; 1.exit; nil });

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
			NetAddr(lanIP, NetAddr.langPort).sendMsg('/pp/bpm', 77);
			NetAddr(lanIP, NetAddr.langPort).sendMsg('/pp/play', 0);
			(~clock.beatDur * 2).wait;
			if ((~ppTempoApplyCount != countBefore) or: { ~clock.tempo != tempoBefore }) {
				fail.("loopback-only", "apply happened after send from non-loopback address %".format(lanIP));
			};
			if ((~ppTransportCount != transportCountBefore) or: { ~ppPlaying.not }) {
				fail.("loopback-only", "/pp/play changed transport state after send from non-loopback address %".format(lanIP));
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
		var measurePeak, peakMix, peak0, peak1, peak8, mixProbe;
		// Generalised to take the bus index to probe (keep the \ppPeakProbe
		// SynthDef); placement stays after ~ppMasterGroup for these
		// post-limiter checks, which always probe bus 0.
		measurePeak = { |busIndex, durSec|
			var probe;
			peakVal = 0.0;
			probe = Synth.after(~ppMasterGroup, \ppPeakProbe, [\in, busIndex]);
			durSec.wait;
			probe.free;
			peakVal;
		};

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
		// so the existing preGain-8 post line reports the EPIC 100 level.
		sendEpic.(100);
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
		sendEpic.(10);
		if (waitEpicSettled.(0.1, 4).not) {
			fail.("limiter ceiling", "smoothed EPIC bus never settled back to the default 0.1 within 4s");
		};
	}.value;

	// --- B8: re-evaluation idempotence (ENG-04 concurrency) ---
	{
		var oldClock = ~clock;
		var oldMaster = ~ppMasterSynth;
		var bpmBeforeReload = ~bpm;
		var elapsed8, countBefore;

		NodeWatcher.register(oldMaster);

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
	}.value;

	"SMOKE PASS".postln;
	s.quit(onComplete: { 0.exit });
	}.try({ |err|
		"SMOKE FAIL: %".format(err.errorString).postln;
		s.quit(onComplete: { 1.exit });
	});
}, AppClock);
)
