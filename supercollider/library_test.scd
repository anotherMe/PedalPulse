// Headless variation-library test harness (Phase 4, LIB-01 / LIB-06).
//
// Run via scripts/check.sh (which also runs the library guard and the smoke
// suite), or directly:
//   /Applications/SuperCollider.app/Contents/MacOS/sclang -D supercollider/library_test.scd
//
// Do NOT set QT_QPA_PLATFORM=offscreen anywhere: verified to abort sclang
// 3.14.1 on macOS with exit 134 (only the cocoa Qt plugin is bundled).
// Plain `sclang -D` runs headless on its own.
//
// Record mode (once, from the UNMODIFIED engine only):
//   PP_GOLDEN_RECORD=1 sclang -D supercollider/library_test.scd
// writes supercollider/golden/shipped_groove.scd and refuses to overwrite an
// existing one. The golden is frozen: never edit it, never re-record it from a
// split engine (scripts/check.sh's guard fails if it changes).
//
// Compare mode (the default): loads the golden, checks it against its own
// known shape ("golden self-check"), then records 16 bars of the running
// engine and compares every column row by row ("parity").
//
// Line protocol (same style as the smoke test):
//   CHECK OK: <name>                              one per passed check
//   PedalPulse libtest: parity rows=<n> mismatches=0
//   GOLDEN WRITTEN: <n> rows                      record mode only
//   LIBRARY PASS                                  last line on success, exit 0
//   LIBRARY FAIL: <name>: <detail>                first failure, exit 1
//   LIBRARY FAIL: watchdog timeout                a hang, exit 1
//
// Isolation (never disturbs a running engine): this file boots its own muted
// server on port 57141 and never addresses 57110 or 57120. Any OSC it sends
// later goes to NetAddr("127.0.0.1", NetAddr.langPort).
//
// Golden / recording row format (one row per SOUNDING event; rests never
// reach the event type):
//   [layer, relBeat, instrument, midinote, dur, timingOffset, legato,
//    sustain, effectiveAmp, outRole, groupRole]
// outRole is \mix when the event's \out is the engine's mix bus, groupRole is
// \instr when its \group is the instrument group; anything else is kept as is.

(
var root, goldenPath, recordMode;
var fail, checkOk;
var log, mixRef, instrRef;
var recordBars, same, selfCheck, rowSortKey;
var expectCounts, expectAmps;

// Watchdog first, in case anything below hangs.
SystemClock.sched(200, { "LIBRARY FAIL: watchdog timeout".postln; 1.exit; nil });

// sclang reports a relative nowExecutingPath when given a relative path, so
// resolve to an absolute path first (before any wait).
root = File.realpath(thisProcess.nowExecutingPath).dirname.dirname;
goldenPath = root +/+ "supercollider/golden/shipped_groove.scd";
recordMode = ("PP_GOLDEN_RECORD".getenv == "1");

// Redirect to an isolated server before loading main.scd, so a live engine on
// 57110 / 57120 is never touched.
Server.default = s = Server(\ppLib, NetAddr("127.0.0.1", 57141));

~ppReady = false;
// The load must see a fresh interpreter's nil transport state (D-15 autostart).
~ppPlaying = nil;

// Throws so a failing check aborts the rest immediately; the top-level `try`
// below prints "LIBRARY FAIL: ..." and exits.
fail = { |name, detail|
	Error("%: %".format(name, detail)).throw;
};

checkOk = { |name|
	"CHECK OK: %".format(name).postln;
};

// --- Recorder (test-only; never defined in main.scd) ---
// Appends one row per sounding event. mixRef / instrRef are closure variables
// captured from ~ppMixBus / ~ppInstrGroup once the engine is ready: inside an
// event-type function, ~vars resolve against the EVENT, not the interpreter.
log = List.new;
mixRef = nil;
instrRef = nil;

Event.addEventType(\ppRecord, { |server|
	log.add([
		~ppRecLayer, thisThread.beats, ~instrument, ~midinote.value, ~dur,
		~timingOffset, ~legato, ~sustain.value, ~amp.value,
		if (~out === mixRef) { \mix } { ~out },
		if (~group === instrRef) { \instr } { ~group }
	]);
});

// Sort key for stable ordering: onset beat rounded to 1e-6 (clock float jitter
// must never reorder simultaneous events), then layer name.
rowSortKey = { |row| (row[1] * 1e6).round.asInteger };

// recordBars.(nBars, tempo, during) -> (rows: rows, startBeat: startBeat)
// Plays every layer of ~ppLayers on a private fast clock with the recording
// event type, keeps the events of the nBars bars after the first bar line and
// returns them as rows with the beat made relative to that bar line.
// `during`, when a Function, is called as during.(recClock, startBeat) right
// after the layers are started (later plans wait for a bar and send OSC).
recordBars = { |nBars, tempo = 32, during|
	var recClock, startBeat, endBeat, rows, attempt = 0, started = false;

	while ({ started.not }, {
		attempt = attempt + 1;
		if (attempt > 5) {
			fail.("recorder", "could not start every layer on the first bar line in 5 attempts");
		};
		~ppLayers.do { |n| Pbindef(n).stop };
		log.clear;
		recClock = TempoClock(tempo, 0.5);  // beats start at 0.5 so the first bar line (beat 4) is never "now"
		startBeat = recClock.nextTimeOnGrid(4);
		~ppLayers.do { |n|
			Pbindef(n).play(
				recClock,
				protoEvent: Event.default.copy.put(\type, \ppRecord).put(\ppRecLayer, n),
				quant: 4,
				doReset: true
			);
		};
		// Every quantization was resolved before the first bar line, so every
		// layer starts exactly on it. Otherwise (a slow moment) start over.
		if (recClock.beats < startBeat) {
			started = true;
		} {
			"PedalPulse libtest: recorder start raced (beats % >= bar line %), retrying".format(recClock.beats, startBeat).postln;
			~ppLayers.do { |n| Pbindef(n).stop };
			recClock.stop;
			0.05.wait;
		};
	});

	endBeat = startBeat + (nBars * 4);
	if (during.isFunction) { during.value(recClock, startBeat) };

	// Margin of 8 beats (0.25 s at the default tempo) so every queued event
	// before endBeat has run before the players stop.
	while ({ recClock.beats < (endBeat + 8) }, { 0.02.wait });
	~ppLayers.do { |n| Pbindef(n).stop };
	recClock.stop;
	// Leave the engine's players with the normal event type again.
	~ppLayers.do { |n| Pbindef(n).player !? { |p| p.event = Event.default } };

	rows = log.select { |r| (r[1] >= startBeat) and: { r[1] < endBeat } }.collect { |r|
		var row = r.copy;
		row[1] = r[1] - startBeat;
		row
	};
	rows = rows.asArray.sort({ |a, b|
		var ka = rowSortKey.(a), kb = rowSortKey.(b);
		(ka < kb) or: { (ka == kb) and: { a[0] <= b[0] } }
	});
	(rows: rows, startBeat: startBeat)
};

// Deep equality: numbers within 1e-9, arrays element by element, the rest ==.
same = { |a, b|
	if (a.isNumber and: { b.isNumber }) {
		(a - b).abs < 1e-9
	} {
		if (a.isArray and: { b.isArray }) {
			(a.size == b.size) and: { a.size.collect { |i| same.(a[i], b[i]) }.every(_ == true) }
		} {
			a == b
		}
	}
};

// What 16 bars of the shipped groove must contain (D-02: effective amps are
// captured as they are, not "fixed").
expectCounts = (ppKick: 64, ppHat: 64, ppClap: 32, ppBass: 64, ppArp: 256, ppPad: 16);
expectAmps = (ppKick: 0.1, ppHat: 0.1, ppClap: 0.25, ppBass: 0.1, ppArp: 0.1, ppPad: 0.06);

selfCheck = { |rows|
	var counts = ();
	rows.do { |r|
		counts[r[0]] = (counts[r[0]] ? 0) + 1;
		if (expectCounts[r[0]].isNil) {
			fail.("golden self-check", "row for unexpected layer %".format(r[0]));
		};
		if ((r[8] - expectAmps[r[0]]).abs > 1e-9) {
			fail.("golden self-check", "% effective amp % != %".format(r[0], r[8], expectAmps[r[0]]));
		};
	};
	expectCounts.keysValuesDo { |layer, n|
		if ((counts[layer] ? 0) != n) {
			fail.("golden self-check", "% has % rows, expected %".format(layer, counts[layer] ? 0, n));
		};
	};
};

fork({
	var elapsed, golden, rec, rows, mismatches, shown, mark;

	s.boot;
	elapsed = 0;
	while ({ s.serverRunning.not and: { elapsed < 30 } }) {
		0.5.wait;
		elapsed = elapsed + 0.5;
	};
	if (s.serverRunning.not) {
		"LIBRARY FAIL: isolated server never booted within 30s".postln;
		1.exit;
	};

	s.volume.mute;  // automated runs are inaudible

	{
		// Refuse before doing any work if a golden would be overwritten.
		if (recordMode and: { File.exists(goldenPath) }) {
			fail.("record", "golden exists -- delete it only to re-record from the unmodified engine");
		};

		(root +/+ "supercollider/main.scd").load;

		elapsed = 0;
		while ({ ~ppReady.not and: { elapsed < 30 } }) {
			0.5.wait;
			elapsed = elapsed + 0.5;
		};
		if (~ppReady.not) {
			fail.("engine ready", "~ppReady never became true within 30s");
		};
		mixRef = ~ppMixBus;
		instrRef = ~ppInstrGroup;
		checkOk.("engine ready");

		if (recordMode) {
			var f;
			rec = recordBars.(16, 32);
			rows = rec[\rows];
			selfCheck.(rows);
			checkOk.("golden self-check");
			File.mkdir(root +/+ "supercollider/golden");
			f = File(goldenPath, "w");
			f.write("// Frozen record of what the shipped (v1.0) engine plays: 16 bars of the six layers.\n");
			f.write("// Recorded from the UNMODIFIED supercollider/main.scd by library_test.scd record mode\n");
			f.write("// (PP_GOLDEN_RECORD=1). NEVER edit this file and never re-record it from the split engine:\n");
			f.write("// the parity check compares the split engine against it, and scripts/check.sh fails\n");
			f.write("// if it changes.\n");
			f.write("// Row: [layer, relBeat, instrument, midinote, dur, timingOffset, legato, sustain,\n");
			f.write("//       effectiveAmp, outRole, groupRole]\n");
			f.write("[\n");
			rows.do { |r, i|
				f.write(r.asCompileString);
				f.write(if (i < (rows.size - 1)) { ",\n" } { "\n" });
			};
			f.write("]\n");
			f.close;
			"GOLDEN WRITTEN: % rows".format(rows.size).postln;
			s.quit(onComplete: { 0.exit });
		} {
			// --- Compare mode ---
			if (File.exists(goldenPath).not) {
				fail.("golden missing", goldenPath);
			};
			golden = goldenPath.load;
			if (golden.isNil) {
				fail.("golden missing", "% evaluated to nil".format(goldenPath));
			};

			selfCheck.(golden);
			checkOk.("golden self-check");

			rec = recordBars.(16, 32);
			rows = rec[\rows];
			mismatches = 0;
			shown = 0;
			mark = { |i, got, want|
				mismatches = mismatches + 1;
				if (shown < 5) {
					shown = shown + 1;
					"PedalPulse libtest: mismatch row %: got % want %".format(i, got, want).postln;
				};
			};
			if (rows.size != golden.size) {
				"PedalPulse libtest: row count % != golden %".format(rows.size, golden.size).postln;
				mismatches = mismatches + (rows.size - golden.size).abs;
			};
			min(rows.size, golden.size).do { |i|
				// Columns 0-10 all compared (layer ... groupRole).
				if (same.(rows[i], golden[i]).not) { mark.(i, rows[i], golden[i]) };
			};
			rows.do { |r, i|
				if ((r[9] != \mix) or: { r[10] != \instr }) {
					fail.("parity", "row % has out % / group % (expected the mix bus and instrument group)".format(i, r[9], r[10]));
				};
			};
			if (mismatches > 0) {
				fail.("parity", "% mismatches against the golden".format(mismatches));
			};
			"PedalPulse libtest: parity rows=% mismatches=0".format(rows.size).postln;
			checkOk.("parity");

			"LIBRARY PASS".postln;
			s.quit(onComplete: { 0.exit });
		};
	}.try({ |err|
		"LIBRARY FAIL: %".format(err.errorString).postln;
		s.quit(onComplete: { 1.exit });
	});
}, AppClock);
)
