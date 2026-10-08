// Headless engine + Python-link test harness (D-18).
//
// Run via scripts/smoke_test.sh, or directly:
//   /Applications/SuperCollider.app/Contents/MacOS/sclang -D supercollider/smoke_test.scd
//
// Do NOT set QT_QPA_PLATFORM=offscreen anywhere: verified to abort sclang
// 3.14.1 on macOS with exit 134 (only the cocoa Qt plugin is bundled).
// Plain `sclang -D` runs headless on its own.

(
var root, venvPython;

// Watchdog first, in case anything below hangs.
SystemClock.sched(120, { "SMOKE FAIL: watchdog timeout".postln; 1.exit; nil });

// sclang reports a relative nowExecutingPath when given a relative path
// (verified during planning), so resolve to an absolute path first.
root = File.realpath(thisProcess.nowExecutingPath).dirname.dirname;

// Redirect to an isolated server before loading main.scd, so a live IDE
// server on 57110 is never touched.
Server.default = s = Server(\ppSmoke, NetAddr("127.0.0.1", 57140));

~ppReady = false;

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

	(root +/+ "supercollider/main.scd").load;

	// Poll ~ppReady up to 30s.
	elapsed = 0;
	while ({ ~ppReady.not and: { elapsed < 30 } }) {
		0.5.wait;
		elapsed = elapsed + 0.5;
	};

	if (~ppReady.not) {
		"SMOKE FAIL: boot ready: engine never posted ready within 30s".postln;
		s.quit(onComplete: { 1.exit });
	} {
		"CHECK OK: boot ready".postln;

		portOk = (~ppOscPort == NetAddr.langPort);
		if (portOk.not) {
			"SMOKE FAIL: port posted: ~ppOscPort % != NetAddr.langPort %".format(~ppOscPort, NetAddr.langPort).postln;
			s.quit(onComplete: { 1.exit });
		} {
			"CHECK OK: port posted".postln;

			tempoOk = ((~clock.tempo * 60 - 120).abs < 1e-6);
			if (tempoOk.not) {
				"SMOKE FAIL: initial tempo 120: got % BPM".format(~clock.tempo * 60).postln;
				s.quit(onComplete: { 1.exit });
			} {
				"CHECK OK: initial tempo 120".postln;

				venvPython = root +/+ ".venv/bin/python";
				venvOk = File.exists(venvPython);
				if (venvOk.not) {
					("SMOKE FAIL: python tempo 140: " ++ venvPython ++ " does not exist -- create it with "
						++ "`python3.13 -m venv .venv && .venv/bin/pip install -r python_app/requirements.txt`"
						++ ", or `./run.sh --setup` once Plan 02 adds it").postln;
					s.quit(onComplete: { 1.exit });
				} {
					applyCountBefore = ~ppTempoApplyCount;
					sendResult = "% %/python_app/osc_client.py 140 --port %".format(venvPython, root, NetAddr.langPort).systemCmd;

					if (sendResult != 0) {
						"SMOKE FAIL: python tempo 140: osc_client.py exited %".format(sendResult).postln;
						s.quit(onComplete: { 1.exit });
					} {
						elapsed = 0;
						while ({ (~ppTempoApplyCount == applyCountBefore) and: { elapsed < 3 } }) {
							0.1.wait;
							elapsed = elapsed + 0.1;
						};

						tempoOk = ((~clock.tempo * 60 - 140).abs < 1e-6);
						if (tempoOk.not) {
							"SMOKE FAIL: python tempo 140: got % BPM".format(~clock.tempo * 60).postln;
							s.quit(onComplete: { 1.exit });
						} {
							"CHECK OK: python tempo 140".postln;
							"SMOKE PASS".postln;
							s.quit(onComplete: { 0.exit });
						};
					};
				};
			};
		};
	};
}, AppClock);
)
