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
var fail, checkOk, checkSkip, sendCli, waitForApplyChange;
var peakVal = 0.0, peakOSCdef;

// Watchdog first, in case anything below hangs.
SystemClock.sched(120, { "SMOKE FAIL: watchdog timeout".postln; 1.exit; nil });

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

// Peak-probe OSCdef: SendReply.kr(... '/pp/test/peak', [peakL, peakR]) ->
// msg = [address, nodeID, replyID, peakL, peakR].
peakOSCdef = OSCdef(\ppPeakProbeReply, { |msg|
	peakVal = max(peakVal, max(msg[3], msg[4]));
}, '/pp/test/peak');

fork({
	var elapsed, portOk, tempoOk, venvOk, sendResult, applyCountBefore;

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
	tempoOk = ((~clock.tempo * 60 - 140).abs < 1e-6);
	if (tempoOk.not) {
		fail.("python tempo 140", "got % BPM".format(~clock.tempo * 60));
	};
	checkOk.("python tempo 140");

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
		if ((~clock.tempo * 60 - expected).abs >= 1e-6) {
			fail.(name, "expected % BPM, got %".format(expected, ~clock.tempo * 60));
		};
		if ((~ppLastApplyBeat - ~ppLastApplyBeat.round).abs >= 1e-6) {
			fail.("whole-beat apply", "~ppLastApplyBeat % is not on a whole beat (sent=%)".format(~ppLastApplyBeat, sent));
		};
		checkOk.(name);
	});
	checkOk.("whole-beat apply");

	// --- B3: latest wins (TEMPO-03, D-14) ---
	applyCountBefore = ~ppTempoApplyCount;
	sendCli.("100 130");
	if (waitForApplyChange.(applyCountBefore, 3).not) {
		fail.("latest wins", "no apply within 3s after sending 100 130");
	};
	if (~ppTempoApplyCount != (applyCountBefore + 1)) {
		fail.("latest wins", "expected exactly 1 apply, got % applies".format(~ppTempoApplyCount - applyCountBefore));
	};
	(~clock.beatDur * 1).wait;  // wait one more beat; must not apply again
	if (~ppTempoApplyCount != (applyCountBefore + 1)) {
		fail.("latest wins", "a second apply happened within 1 beat of the first");
	};
	if ((~clock.tempo * 60 - 130).abs >= 1e-6) {
		fail.("latest wins", "expected 130 BPM, got %".format(~clock.tempo * 60));
	};
	checkOk.("latest wins");

	// --- B4: malformed input tolerance ---
	{
		var countBefore = ~ppTempoApplyCount;
		var tempoBefore = ~clock.tempo;
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/bpm');
		NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/bpm', "fast");
		sendCli.("nan");
		(~clock.beatDur * 2).wait;
		if (~ppTempoApplyCount != countBefore) {
			fail.("malformed ignored", "apply count changed after malformed input");
		};
		if (~clock.tempo != tempoBefore) {
			fail.("malformed ignored", "tempo changed after malformed input");
		};
		countBefore = ~ppTempoApplyCount;
		sendCli.("128");
		if (waitForApplyChange.(countBefore, 3).not) {
			fail.("malformed ignored", "handler did not apply valid 128 after malformed input");
		};
		if ((~clock.tempo * 60 - 128).abs >= 1e-6) {
			fail.("malformed ignored", "expected 128 BPM after recovery, got %".format(~clock.tempo * 60));
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
			NetAddr(lanIP, NetAddr.langPort).sendMsg('/pp/bpm', 77);
			(~clock.beatDur * 2).wait;
			if ((~ppTempoApplyCount != countBefore) or: { ~clock.tempo != tempoBefore }) {
				fail.("loopback-only", "apply happened after send from non-loopback address %".format(lanIP));
			};
			checkOk.("loopback-only");
		};
	}.value;

	// --- B6: node-leak bound ---
	{
		var maxSynths = 0, elapsed6 = 0;
		sendCli.("180");
		while ({ elapsed6 < 8 }) {
			maxSynths = max(maxSynths, s.numSynths);
			0.25.wait;
			elapsed6 = elapsed6 + 0.25;
		};
		if (maxSynths > 20) {
			fail.("node bound", "max synths % exceeds 20".format(maxSynths));
		};
		checkOk.("node bound");
	}.value;

	// --- B7: limiter, no bypass + ceiling (ENG-02, D-16, D-17) ---
	{
		var measurePeak, peak0, peak1, peak8;
		measurePeak = { |durSec|
			var probe;
			peakVal = 0.0;
			probe = Synth.after(~ppMasterGroup, \ppPeakProbe, [\in, 0]);
			durSec.wait;
			probe.free;
			peakVal;
		};

		~ppMasterSynth.set(\preGain, 0);
		0.5.wait;
		peak0 = measurePeak.(2);
		if (peak0 >= 0.001) {
			fail.("limiter no bypass", "peak % with preGain 0 (expected < 0.001)".format(peak0));
		};
		checkOk.("limiter no bypass");

		~ppMasterSynth.set(\preGain, 1);
		peak1 = measurePeak.(2);
		"PedalPulse smoke: peak at preGain 1 = %".format(peak1).postln;

		~ppMasterSynth.set(\preGain, 8);
		0.5.wait;
		peak8 = measurePeak.(2);
		if ((peak8 > 0.5).not or: { peak8 > 0.90 }) {
			fail.("limiter ceiling", "peak % with preGain 8 (expected in (0.5, 0.90])".format(peak8));
		};
		checkOk.("limiter ceiling");

		~ppMasterSynth.set(\preGain, ~preGain);
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
			fail.("re-evaluation", "pending-apply flag appears wedged: 128 never applied after reload");
		};
		if ((~clock.tempo * 60 - 128).abs >= 1e-6) {
			fail.("re-evaluation", "expected 128 BPM after reload-apply, got %".format(~clock.tempo * 60));
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
