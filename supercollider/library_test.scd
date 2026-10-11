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
var sendSel, waitFor, venvPython, newLogs, barOf;
var tmpRoot, realLibRoot, cleanupTmp, wr, shq, expectClassicBars, leadDiffs, freshText;
var staticCheck, stripSource, forbiddenTokens, staticTmp, listStems;

// Watchdog first, in case anything below hangs.
SystemClock.sched(200, {
	"LIBRARY FAIL: watchdog timeout".postln;
	cleanupTmp.value;
	1.exit;
	nil
});

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

// --- Selection tier helpers (LIB-02, LIB-05) ---
// sendSel sends one OSC message to this interpreter's own language port, from
// loopback, exactly like the app does. A nil value sends the address alone.
sendSel = { |address, value|
	var addr = NetAddr("127.0.0.1", NetAddr.langPort);
	if (value.isNil) { addr.sendMsg(address) } { addr.sendMsg(address, value) };
};

// Poll every 0.05 s until cond holds or timeoutSec passes. Call from a Routine.
waitFor = { |cond, timeoutSec|
	var t = 0;
	while { cond.value.not and: { t < timeoutSec } } {
		0.05.wait;
		t = t + 0.05;
	};
	cond.value
};

venvPython = root +/+ ".venv/bin/python";

// The log lines written since ~ppLogCount was countBefore (the list itself is
// capped at 100, so its size cannot be used to count).
newLogs = { |countBefore|
	var a = ~ppLogLines.asArray;
	var n = (~ppLogCount - countBefore).min(a.size);
	if (n <= 0) { [] } { a.copyRange(a.size - n, a.size - 1) }
};

barOf = { |relBeat| (relBeat / 4 + 1e-6).floor.asInteger };

// --- Fallback tier helpers (LIB-04, LIB-05) ---
// The temporary library root is created by the tier itself. cleanupTmp puts
// ~ppLibRoot back and removes only the two temporary folders; it is also run on
// a failure and by the watchdog, so a failed run does not leave them behind.
shq = { |str| "'" ++ str ++ "'" };
cleanupTmp = {
	if (realLibRoot.notNil) { ~ppLibRoot = realLibRoot };
	if (tmpRoot.notNil and: { tmpRoot.find("pedalpulse-libtest-").notNil }) {
		("rm -rf" + shq.(tmpRoot) + shq.(tmpRoot ++ "_outside")).systemCmd;
	};
	if (staticTmp.notNil and: { staticTmp.find("pedalpulse-statictest-").notNil }) {
		("rm -rf" + shq.(staticTmp)).systemCmd;
	};
};

// wr.(relativePath, text): write a fixture inside the temporary library root.
wr = { |rel, text|
	File.use(tmpRoot +/+ rel, "w", { |f| f.write(text) });
};

// A melody whose arp is classic's and whose lead is the arp's notes + offset at
// amp 0.02.
freshText = { |desc, offset|
	"(\ndesc: \"%\",\narp: { |plan, state| var notes = [57, 60, 64, 60]; Array.fill(16, { |i| [notes.wrapAt(i), 0.25, 0.1, 0.6] }) },\nlead: { |plan, state| var notes = [57, 60, 64, 60]; Array.fill(16, { |i| [notes.wrapAt(i) + %, 0.25, 0.02, 0.6] }) }\n)\n".format(desc, offset)
};

// expectClassicBars.(name, rows, nBars): every one of nBars bars holds the
// classic event count for each of the six sounding layers (kick 4, hat 4, clap
// 2, bass 4, arp 16, pad 1). The music never stopped.
expectClassicBars = { |name, rws, nBars|
	var perBar = (ppKick: 4, ppHat: 4, ppClap: 2, ppBass: 4, ppArp: 16, ppPad: 1);
	var counts = ();
	rws.do { |r|
		var k = "%_%".format(r[0], barOf.(r[1])).asSymbol;
		counts[k] = (counts[k] ? 0) + 1;
	};
	perBar.keysValuesDo { |layer, n|
		nBars.do { |b|
			var got = counts["%_%".format(layer, b).asSymbol] ? 0;
			if (got != n) {
				fail.(name, "% bar % holds % events, expected % (the music stopped or changed)".format(layer, b, got, n));
			};
		};
	};
};

// leadDiffs.(rows) -> Array of [bar, lead note - arp note at the same beat].
leadDiffs = { |rws|
	var arp = rws.select { |r| r[0] == \ppArp };
	rws.select { |r| r[0] == \ppLead }.collect { |r|
		var a = arp.detect { |x| (x[1] - r[1]).abs < 1e-6 };
		if (a.isNil) { fail.("lead check", "no arp row at beat %".format(r[1])) };
		[barOf.(r[1]), r[3] - a[3]]
	}
};

// --- Static tier (LIB-06, LIB-02): every library file, no server needed ---
// Source with comments removed and string contents blanked, so the lint looks
// at code only (a desc that happens to say "File" is not a file access).
stripSource = { |src|
	var out = String.new, i = 0, n = src.size, c, c2, closed;
	while { i < n } {
		c = src[i];
		c2 = if ((i + 1) < n) { src[i + 1] } { $  };
		if ((c == $/) and: { c2 == $/ }) {
			while { (i < n) and: { src[i] != $\n } } { i = i + 1 };
		} {
			if ((c == $/) and: { c2 == $* }) {
				i = i + 2;
				closed = false;
				while { (i < n) and: { closed.not } } {
					if ((src[i] == $*) and: { ((i + 1) < n) and: { src[i + 1] == $/ } }) { closed = true };
					i = i + 1;
				};
				i = i + 1;
				out = out ++ " ";
			} {
				if (c == $") {
					out = out ++ "\"";
					i = i + 1;
					while { (i < n) and: { src[i] != $" } } {
						if (src[i] == $\\) { i = i + 2 } { i = i + 1 };
					};
					out = out ++ "\"";
					i = i + 1;
				} {
					if (c == $$) {
						out = out ++ "  ";
						i = i + 2;
					} {
						out = out ++ c;
						i = i + 1;
					};
				};
			};
		};
	};
	out
};

// What a library file may never contain: environment variables, patterns,
// clocks, the server, synths, OSC, files and shell. A file is data plus pure
// functions.
forbiddenTokens = [
	"~", "Pbindef", "Pdef", "Tdef", "Ndef", "Pbind", ".play", "fork", ".wait",
	"Routine", "Task", "TempoClock", "SystemClock", "AppClock", "Server",
	"Synth(", "Synth.", "OSCdef", "OSCFunc", "NetAddr", "unixCmd", "systemCmd",
	"File", "Pipe", ".load", "thisProcess", "interpret"
];

// The stems (file names without .scd) in a folder: classic first, then sorted.
listStems = { |dir|
	var stems;
	stems = (dir +/+ "*.scd").pathMatch.collect { |p| PathName(p).fileNameWithoutExtension };
	stems = stems.reject { |n| n.beginsWith(".") }.sort;
	if (stems.any { |n| n == "classic" }) { ["classic"] ++ stems.reject { |n| n == "classic" } } { stems }
};

// staticCheck.(libRoot, quiet) -> Array of failure Strings (empty means every
// file passed). Uses the same ~ppLibLoad, ~ppValidate, ~ppRowsValid,
// ~ppValidateVoices and ~ppRenderBar the engine uses. Prints one
// "LIBCHECK OK: <category>/<stem>" per file unless quiet. Order: progressions,
// melodies, palettes; in each, classic first, then sorted names.
staticCheck = { |libRoot, quiet|
	var failures = List.new, savedRoot, add, roleGens;
	var snapKeys, snapPdef, snapTdef, snapOsc, newKeys, grown, logBefore;
	var src, hit, mod, state, passA, passB, runPass, reasons, rendered, direct, fresh;
	var stem, ok, nfail, path, dir, stems, sel, pre, names, ls;

	savedRoot = ~ppLibRoot;
	~ppLibRoot = libRoot;
	~ppLib = (progressions: (), melodies: (), palettes: ());
	~ppSel = (progressions: \classic, melodies: \classic, palettes: \classic);
	~ppRenderErrors = ();
	add = { |text| failures.add(text) };
	roleGens = (progressions: [\bass, \pad], melodies: [\arp, \lead]);

	// Every classic first: the round trip needs the fallback in place.
	~ppLibCategories.do { |cat|
		pre = if (File.exists(~ppLibPath.(cat, \classic))) { ~ppLibLoad.(cat, \classic) } { nil };
		if (pre.notNil) {
			pre[\rev] = 1;
			~ppLib[cat].put(\classic, pre);
			if ((cat == \palettes) and: { pre[\defs].isFunction }) {
				try { pre[\defs].value } { |err| add.("palettes/classic defs threw: %".format(err.errorString)) };
			};
		};
	};

	~ppLibCategories.do { |cat|
		dir = libRoot +/+ cat.asString;
		stems = listStems.(dir);
		if (stems.any { |n| n == "classic" }.not) { add.("% has no classic.scd".format(cat)) };
		stems.do { |stemStr|
			var selectable = (stemStr[0] != $_);
			var label = "%/%".format(cat, stemStr);
			nfail = failures.size;
			if (selectable and: { ~ppStemValid.(stemStr).not }) {
				add.("% breaks the naming rules (1-64 characters of a-z, 0-9 and _; auto is reserved)".format(label));
			} {
				stem = stemStr.asSymbol;
				path = ~ppLibPath.(cat, stem);

				// (a) loads, validates, and leaves nothing behind.
				snapKeys = currentEnvironment.keys.copy;
				snapPdef = Pdef.all.size;
				snapTdef = Tdef.all.size;
				snapOsc = OSCdef.all.size;
				logBefore = ~ppLogCount;
				mod = ~ppLibLoad.(cat, stem);
				if (mod.isNil) {
					add.("% did not load or validate: %".format(label, newLogs.(logBefore).select { |l| l.find("ERROR").notNil }.join(" | ")));
				};
				newKeys = currentEnvironment.keys.reject { |k| snapKeys.includes(k) or: { [\ppLogLines, \ppLogCount].includes(k) } };
				if (newKeys.size > 0) {
					add.("% has load-time side effects: new environment variable(s) %".format(label, newKeys.asArray));
					newKeys.do { |k| currentEnvironment.removeAt(k) };
				};
				if ((Pdef.all.size != snapPdef) or: { Tdef.all.size != snapTdef } or: { OSCdef.all.size != snapOsc }) {
					add.("% has load-time side effects: it created a Pdef, Tdef or OSCdef".format(label));
				};

				// (b) lint the code (comments and string contents removed).
				src = try { stripSource.(File.readAllString(path)) } { nil };
				if (src.isNil) {
					add.("% could not be read for the lint".format(label));
				} {
					forbiddenTokens.do { |tok|
						if (src.find(tok).notNil) {
							add.("% uses the forbidden token \"%\" (a library file is data plus pure functions)".format(label, tok));
						};
					};
				};

				if (mod.notNil) {
					// (c) generators: 16 bars, every one a valid 4-beat bar, replayable.
					if (roleGens[cat].notNil) {
						roleGens[cat].do { |role|
							if (mod[role].isFunction) {
								runPass = {
									var st = (), bars = List.new;
									if (mod[\init].isFunction) {
										thisThread.randSeed = ~ppSeedFor.(~ppSongSeed, 0, role);
										mod[\init].value(st);
									};
									16.do { |b|
										thisThread.randSeed = ~ppSeedFor.(~ppSongSeed, b, role);
										bars.add(mod[role].value(~ppPlanFor.(b, b, role), st));
									};
									bars.asArray
								};
								passA = try { runPass.value } { |err| add.("% % threw: %".format(label, role, err.errorString)); nil };
								if (passA.notNil) {
									passA.do { |rows, b|
										var why = ~ppRowsValid.(rows);
										if (why.notNil) { add.("% % bar %: %".format(label, role, b, why)) };
									};
									passB = try { runPass.value } { |err| nil };
									if (same.(passA, passB).not) {
										add.("% % does not replay the same bars from the same seed".format(label, role));
									};
								};
							};
						};
					};

					// (d) palette voices exist with the right controls.
					if (cat == \palettes) {
						if (mod[\defs].isFunction) {
							try { mod[\defs].value } { |err| add.("% defs threw: %".format(label, err.errorString)) };
						};
						reasons = ~ppValidateVoices.(mod);
						reasons.do { |r| add.("% %".format(label, r)) };
					};

					// (e) round trip through the primary use path (selectable stems only).
					if (selectable) {
						mod[\rev] = 1;
						~ppLib[cat].put(stem, mod);
						~ppSel[cat] = stem;
						logBefore = ~ppLogCount;
						try {
							if (cat == \palettes) {
								(~ppDrumRoles ++ ~ppPitchedRoles).do { |role|
									ls = ();
									4.do { |b|
										var rows = ~ppRenderBar.(role, b, b, ls);
										var entry = mod[\roles][role];
										if (entry.notNil) {
											rows.do { |r|
												if (r[0] != entry[\instrument]) {
													add.("% role % renders voice % instead of %".format(label, role, r[0], entry[\instrument]));
												};
											};
										};
									};
								};
							} {
								roleGens[cat].do { |role|
									ls = ();
									rendered = 4.collect { |b| ~ppRenderBar.(role, b, b, ls) };
									if (mod[role].isFunction) {
										state = ();
										if (mod[\init].isFunction) {
											thisThread.randSeed = ~ppSeedFor.(~ppSongSeed, 0, role);
											mod[\init].value(state);
										};
										direct = 4.collect { |b|
											thisThread.randSeed = ~ppSeedFor.(~ppSongSeed, b, role);
											mod[role].value(~ppPlanFor.(b, b, role), state)
										};
										rendered.do { |rows, b|
											if (same.(rows.collect { |r| r.copyToEnd(1) }, direct[b]).not) {
												add.("% % bar %: the rendered rows differ from the generator's own rows".format(label, role, b));
											};
										};
									};
								};
							};
						} { |err|
							add.("% round trip threw: %".format(label, err.errorString));
						};
						fresh = newLogs.(logBefore);
						if (fresh.any { |l| l.find("playing classic for this bar").notNil }) {
							add.("% fell back to classic while playing: %".format(label, fresh.select { |l| l.find("playing classic for this bar").notNil }.join(" | ")));
						};
						~ppSel[cat] = \classic;
					};
				};
			};
			if ((failures.size == nfail) and: { quiet.not }) {
				"LIBCHECK OK: %".format(label).postln;
			};
		};
	};

	~ppLibRoot = savedRoot;
	failures.asArray
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
	var gold4, matchGold4, restoreAll;
	var sfail, bad, cp, expectFailure, wrs;

	// ============================================================
	// Static tier (LIB-06, LIB-02): no server yet. Every .scd file under
	// supercollider/library, the _template.scd files included, is loaded
	// and checked; the result is one LIBCHECK OK line per file.
	// ============================================================
	{
		~ppRoot = root +/+ "supercollider";
		~ppLibRoot = ~ppRoot +/+ "library";
		["validate.scd", "loader.scd", "render.scd"].do { |name|
			var r = (~ppRoot +/+ "core" +/+ name).load;
			if (r.isNil) { fail.("static", "core module % failed to load".format(name)) };
		};

		sfail = staticCheck.(~ppLibRoot, false);
		if (sfail.size > 0) {
			fail.("static", sfail.join(" || "));
		};
		checkOk.("static check");

		// Negative controls: six kinds of bad file must each fail the check.
		// The fixtures live in a temporary root, never in supercollider/library.
		staticTmp = Platform.defaultTempDir +/+ ("pedalpulse-statictest-" ++ Date.getDate.stamp);
		["progressions", "melodies", "palettes"].do { |c| File.mkdir(staticTmp +/+ c) };
		cp = { |rel|
			var rc = ("cp" + shq.(~ppLibRoot +/+ rel) + shq.(staticTmp +/+ rel)).systemCmd;
			if (rc != 0) { fail.("static setup", "cp of % failed with %".format(rel, rc)) };
		};
		cp.("melodies/classic.scd");
		cp.("palettes/classic.scd");
		// progressions/ stays empty: no classic.scd there.
		wrs = { |rel, text| File.use(staticTmp +/+ rel, "w", { |f| f.write(text) }) };
		wrs.("melodies/empty_rows.scd", "(desc: \"empty bar\", arp: { |plan, state| [] })\n");
		wrs.("melodies/side_effect.scd", "~ppStaticProbeVar = 1;\n(desc: \"side effect\", arp: { |plan, state| [[60, 4, 0.1, 0.5]] })\n");
		wrs.("melodies/forbidden_call.scd", "(desc: \"forbidden call\", arp: { |plan, state| [[60, 4, 0.1, 0.5]] }, helper: { Synth(\\default) })\n");
		wrs.("melodies/Bad Name.scd", "(desc: \"bad name\", arp: { |plan, state| [[60, 4, 0.1, 0.5]] })\n");
		wrs.("melodies/auto.scd", "(desc: \"reserved name\", arp: { |plan, state| [[60, 4, 0.1, 0.5]] })\n");

		bad = staticCheck.(staticTmp, true);
		currentEnvironment.removeAt(\ppStaticProbeVar);
		expectFailure = { |what, needle|
			if (bad.any { |f| f.find(needle).notNil }.not) {
				fail.("static check catches bad files", "no failure for % (looked for \"%\"), got: %".format(what, needle, bad));
			};
		};
		expectFailure.("a category without classic.scd", "progressions has no classic.scd");
		expectFailure.("a generator returning an empty bar", "melodies/empty_rows");
		expectFailure.("a load-time side effect", "melodies/side_effect has load-time side effects");
		expectFailure.("a forbidden call", "melodies/forbidden_call uses the forbidden token \"Synth(\"");
		expectFailure.("a file name with a space and capitals", "melodies/Bad Name breaks the naming rules");
		expectFailure.("the reserved name auto", "melodies/auto breaks the naming rules");
		if (bad.any { |f| f.beginsWith("melodies/classic") or: { f.beginsWith("palettes/classic") } }) {
			fail.("static check catches bad files", "a good classic file failed in the temporary library: %".format(bad));
		};
		("rm -rf" + shq.(staticTmp)).systemCmd;
		staticTmp = nil;
		checkOk.("static check catches bad files");

		// main.scd must start from the D-07 defaults, which parity depends on.
		~ppSel = nil;
		~ppLib = nil;
		~ppRenderErrors = nil;
		~ppRoleNotes = nil;
	}.try({ |err|
		"LIBRARY FAIL: %".format(err.errorString).postln;
		cleanupTmp.value;
		1.exit;
	});

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

		// ============================================================
		// Voice tier (LIB-06, T-04-13): every palette voice, on a BARE server
		// (main.scd is not loaded yet, so nothing but a bad voice can write
		// to bus 0). A voice must write only to its own out bus (so it always
		// goes through the limiter), release when its gate closes and free
		// itself.
		// ============================================================
		if (recordMode.not) {
			var peaks, childCount, voiceContract, voiceContractMany;
			var palStems, negResults, negNames;

			~ppLibRoot = root +/+ "supercollider/library";
			peaks = IdentityDictionary.new;

			SynthDef(\ppLibPeak, { |in = 0, id = 0|
				SendReply.kr(Impulse.kr(20), '/pp/test/libpeak', Peak.ar(In.ar(in, 2)), id);
			}).add;
			// msg = [address, nodeID, replyID, peakL, peakR]; the maximum per replyID.
			OSCdef(\ppLibPeakReply, { |msg|
				peaks[msg[2]] = max(peaks[msg[2]] ? 0, max(msg[3], msg[4]));
			}, '/pp/test/libpeak');

			// Direct children of a group, through /g_queryTree (same pattern as
			// instrChildCount in smoke_test.scd). -1 when the server never replied.
			childCount = { |g|
				var replyMsg = nil, oscFunc, waited = 0;
				oscFunc = OSCFunc({ |msg| if (msg[2] == g.nodeID) { replyMsg = msg } }, '/g_queryTree.reply', s.addr);
				s.sendMsg('/g_queryTree', g.nodeID, 0);
				while { replyMsg.isNil and: { waited < 1 } } {
					0.05.wait;
					waited = waited + 0.05;
				};
				oscFunc.free;
				if (replyMsg.isNil) { -1 } { replyMsg[3] }
			};

			// voiceContractMany.(pairs) -> one Array of failure reasons per
			// [instrument, pitched] pair. The voices of one call run side by
			// side, each in its own group, on its own bus, with its own peak
			// probes (one on the private bus, one on bus 0), so the whole batch
			// takes about 3 s.
			voiceContractMany = { |pairs|
				var entries, nextId = 1;
				entries = pairs.collect { |p|
					var inst = p[0], pitched = p[1], desc, need, e;
					e = (inst: inst, pitched: pitched, reasons: List.new);
					desc = SynthDescLib.global.at(inst);
					if (desc.isNil) {
						e[\reasons].add("is not a known SynthDef");
					} {
						need = [\out, \amp] ++ if (pitched) { [\freq, \gate] } { [] };
						need.do { |c|
							if (desc.controlDict[c].isNil) { e[\reasons].add("has no % control".format(c)) };
						};
					};
					e
				};
				entries.do { |e|
					if (e[\reasons].isEmpty) {
						e[\grp] = Group.new(s);
						e[\bus] = Bus.audio(s, 2);
						e[\idBus] = nextId;
						e[\id0] = nextId + 1;
						nextId = nextId + 2;
						peaks[e[\idBus]] = 0;
						peaks[e[\id0]] = 0;
					};
				};
				s.sync;
				entries.do { |e|
					if (e[\grp].notNil) {
						e[\probeBus] = Synth.after(e[\grp], \ppLibPeak, [\in, e[\bus].index, \id, e[\idBus]]);
						e[\probe0] = Synth.after(e[\grp], \ppLibPeak, [\in, 0, \id, e[\id0]]);
						Synth(e[\inst], [\out, e[\bus].index, \amp, 0.1] ++ if (e[\pitched]) { [\freq, 220] } { [] }, e[\grp]);
					};
				};
				0.6.wait;
				entries.do { |e| if (e[\grp].notNil) { e[\grp].set(\gate, 0) } };
				2.0.wait;
				entries.do { |e|
					var n;
					if (e[\grp].notNil) {
						n = childCount.(e[\grp]);
						if (peaks[e[\idBus]] <= 0) { e[\reasons].add("no signal on its out bus") };
						if (peaks[e[\id0]] > 0) { e[\reasons].add("writes to bus 0 (bypasses the limiter)") };
						if (n < 0) { e[\reasons].add("the server never answered /g_queryTree") };
						if (n > 0) { e[\reasons].add("% node(s) left after gate 0 (ignores gate or never frees)".format(n)) };
						e[\probeBus].free;
						e[\probe0].free;
						e[\grp].free;
						e[\bus].free;
					};
				};
				s.sync;
				entries.collect { |e| e[\reasons].asArray }
			};
			voiceContract = { |inst, pitched| voiceContractMany.([[inst, pitched]])[0] };

			// Every palette file (classic first, then sorted), templates included.
			palStems = listStems.(~ppLibRoot +/+ "palettes");
			palStems.do { |stemStr|
				var mod, pairs = List.new, results, bad = List.new;
				mod = ~ppLibLoad.(\palettes, stemStr.asSymbol);
				if (mod.isNil) { fail.("voices %".format(stemStr), "the palette did not load") };
				if (mod[\defs].isFunction) {
					try { mod[\defs].value } { |err| fail.("voices %".format(stemStr), "defs threw: %".format(err.errorString)) };
				};
				s.sync;
				(~ppDrumRoles ++ ~ppPitchedRoles).do { |role|
					var entry = mod[\roles][role], inst, found;
					if (entry.notNil) {
						inst = entry[\instrument];
						found = pairs.detect { |pr| pr[0] === inst };
						if (found.isNil) {
							pairs.add([inst, ~ppPitchedRoles.includes(role)]);
						} {
							if (~ppPitchedRoles.includes(role)) { found[1] = true };
						};
					};
				};
				results = voiceContractMany.(pairs.asArray);
				results.do { |reasons, i|
					if (reasons.size > 0) {
						bad.add("% (role instrument %): %".format(stemStr, pairs[i][0], reasons.join("; ")));
					};
				};
				if (bad.size > 0) { fail.("voices %".format(stemStr), bad.join(" | ")) };
				checkOk.("voices %".format(stemStr));
			};

			// Negative controls: three bad voices (test-only; never in library/)
			// must each fail the contract, or the contract proves nothing.
			SynthDef(\ppBadBus0, { |out = 0, amp = 0.1, freq = 220, gate = 1|
				var env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.7, 0.1), gate, doneAction: 2);
				Out.ar(0, (SinOsc.ar(freq) * env * amp) ! 2);  // ignores out: straight to the hardware bus
			}).add;
			SynthDef(\ppBadNoDone, { |out = 0, amp = 0.1, freq = 220, gate = 1|
				var env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.7, 0.1), gate);  // no doneAction
				Out.ar(out, (SinOsc.ar(freq) * env * amp) ! 2);
			}).add;
			SynthDef(\ppBadNoGate, { |out = 0, amp = 0.1, freq = 220, gate = 1|
				Out.ar(out, (SinOsc.ar(freq) * amp) ! 2);  // gate declared, never used
			}).add;
			s.sync;
			negNames = [\ppBadBus0, \ppBadNoDone, \ppBadNoGate];
			negResults = voiceContractMany.(negNames.collect { |n| [n, true] });
			negResults.do { |reasons, i|
				if (reasons.size < 1) {
					fail.("voice contract catches bad voices", "voice contract cannot fail: % passed the contract".format(negNames[i]));
				};
			};
			if (negResults[0].any { |r| r.find("bypasses the limiter").notNil }.not) {
				fail.("voice contract catches bad voices", "voice contract cannot fail: ppBadBus0 was not caught writing to bus 0 (%)".format(negResults[0]));
			};
			[1, 2].do { |i|
				if (negResults[i].any { |r| r.find("node(s) left").notNil }.not) {
					fail.("voice contract catches bad voices", "voice contract cannot fail: % was not caught as a voice that never frees (%)".format(negNames[i], negResults[i]));
				};
			};
			// Single-voice form of the same check, as a sanity run on a good voice.
			if (voiceContract.(\ppKick, false).size > 0) {
				fail.("voice contract catches bad voices", "the good voice ppKick failed the single-voice contract");
			};
			checkOk.("voice contract catches bad voices");
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

		// RESEARCH VERIFY flag: every layer keeps quant 4 (bar-quantized) after
		// a Stop and a Start with doReset.
		if (recordMode.not) {
			var quantAll = { |when|
				if (~ppLayers.size != 7) {
					fail.("quant 4 survives restart", "~ppLayers has % entries %, expected 7".format(~ppLayers.size, when));
				};
				~ppLayers.do { |n|
					if (Pbindef(n).quant != 4) {
						fail.("quant 4 survives restart", "% has quant % %, expected 4".format(n, Pbindef(n).quant, when));
					};
				};
			};
			// A Stop while a bar-quantized start is still pending can raise inside
			// SuperCollider, so wait until every layer is really playing first.
			var playing = {
				waitFor.({ ~ppLayers.every { |n| var pl = Pbindef(n).player; pl.notNil and: { pl.nextBeat.notNil } } }, 8)
			};
			quantAll.("at start");
			if (playing.value.not) { fail.("quant 4 survives restart", "the layers never started playing") };
			~ppStop.value;
			~ppStart.value;
			quantAll.("after Stop and Start");
			if (playing.value.not) { fail.("quant 4 survives restart", "the layers never restarted after Start") };
			checkOk.("quant 4 survives restart");
		};

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

			// ============================================================
			// Selection tier (LIB-02, LIB-05): real OSC on the language
			// port. The engine's layers are stopped by recordBars; the
			// selection works either way, and every recording below
			// restarts them on a private clock.
			// ============================================================

			// The golden's first 4 bars: what a restart on classic must play.
			gold4 = golden.select { |r| r[1] < (16 - 1e-6) };

			// Record 4 bars and require them to equal the golden's first 4 bars.
			matchGold4 = { |name|
				var rc, rws;
				rc = recordBars.(4, 32);
				rws = rc[\rows];
				if (rws.any { |r| r[0] == \ppLead }) {
					fail.(name, "the lead played while every category resolves to classic");
				};
				if (rws.size != gold4.size) {
					fail.(name, "% rows != % golden rows for the first 4 bars".format(rws.size, gold4.size));
				};
				rws.do { |r, i|
					if (same.(r, gold4[i]).not) {
						fail.(name, "row % differs from the golden: got % want %".format(i, r, gold4[i]));
					};
				};
			};

			// Put every category back on classic and wait until it has taken.
			restoreAll = { |name|
				sendSel.('/pp/progression', 'classic');
				sendSel.('/pp/palette', 'classic');
				sendSel.('/pp/melody', 'classic');
				if (waitFor.({ ~ppLibCategories.every { |c| ~ppSel[c] == \classic } }, 5).not) {
					fail.(name, "selections did not return to classic: %".format(~ppSel));
				};
			};

			// 1. select melody by name (LIB-05, D-06, D-07), and edge LIB-02 adjacency.
			{
				var name = "select melody by name";
				var rc, rws, lead, arp, bars, first, lastBar, keys;
				rc = recordBars.(24, 16, { |recClock, startBeat|
					while { recClock.beats < (startBeat + 16) } { 0.02.wait };  // bar 4
					sendSel.('/pp/melody', 'classic_lead');
					if (waitFor.({ ~ppSel[\melodies] == \classic_lead }, 2).not) {
						fail.(name, "~ppSel[\\melodies] never became classic_lead");
					};
					while { recClock.beats < (startBeat + 56) } { 0.02.wait };  // bar 14
					sendSel.('/pp/melody', 'classic');
					if (waitFor.({ ~ppSel[\melodies] == \classic }, 2).not) {
						fail.(name, "~ppSel[\\melodies] never returned to classic");
					};
				});
				rws = rc[\rows];
				lead = rws.select { |r| r[0] == \ppLead };
				arp = rws.select { |r| r[0] == \ppArp };
				if (lead.isEmpty) { fail.(name, "no lead rows after selecting classic_lead") };

				first = lead[0][1];
				if ((((first / 4).round - (first / 4)).abs > 1e-6) or: { barOf.(first) < 4 } or: { barOf.(first) > 6 }) {
					fail.(name, "first lead row at beat % is not a bar line in bars 4-6".format(first));
				};

				bars = Dictionary.new;
				lead.do { |r|
					var b = barOf.(r[1]);
					bars[b] = (bars[b] ? List.new).add(r);
				};
				keys = bars.keys.asArray.sort;
				keys.do { |b|
					if (bars[b].size != 16) {
						fail.(name, "bar % holds % lead rows, expected 16".format(b, bars[b].size));
					};
				};
				if ((keys.last - keys.first + 1) != keys.size) {
					fail.(name, "lead bars are not contiguous: %".format(keys));
				};
				lastBar = keys.last;
				if (bars[lastBar].size != 16) {
					fail.(name, "the last lead bar % is incomplete".format(lastBar));
				};
				if (lead.any { |r| barOf.(r[1]) >= 20 }) {
					fail.(name, "lead rows still playing in bars 20-23");
				};
				lead.do { |r|
					var a = arp.detect { |x| (x[1] - r[1]).abs < 1e-6 };
					if (a.isNil) { fail.(name, "no arp row at beat %".format(r[1])) };
					if (r[3] != (a[3] + 12)) { fail.(name, "lead note % is not the arp's % + 12 at beat %".format(r[3], a[3], r[1])) };
					if (same.(r[4], a[4]).not) { fail.(name, "lead dur % != arp dur % at beat %".format(r[4], a[4], r[1])) };
					if ((r[8] - 0.025).abs > 1e-9) { fail.(name, "lead amp % != 0.025 at beat %".format(r[8], r[1])) };
					if (r[2] != \ppArp) { fail.(name, "lead instrument % != ppArp".format(r[2])) };
					if (r[9] != \mix) { fail.(name, "lead out % != mix".format(r[9])) };
					if (r[10] != \instr) { fail.(name, "lead group % != instr".format(r[10])) };
				};

				// No missing or doubled arp sixteenth across both switches.
				if (arp.size != 384) { fail.(name, "% arp rows, expected 384".format(arp.size)) };
				arp.do { |r, i|
					if ((r[1] - (i * 0.25)).abs > 1e-6) {
						fail.(name, "arp row % at beat % is not at %".format(i, r[1], i * 0.25));
					};
				};

				// Adjacency: only the melody selection changed.
				if ((~ppSel[\progressions] != \classic) or: { ~ppSel[\palettes] != \classic }) {
					fail.(name, "a melody selection changed another category: %".format(~ppSel));
				};
				checkOk.(name);
			}.value;

			// 2. reselect reloads (LIB-05): re-sending a name re-reads its file.
			{
				var name = "reselect reloads";
				var rev0;
				rev0 = ~ppLib[\melodies][\classic_lead][\rev];
				sendSel.('/pp/melody', 'classic_lead');
				if (waitFor.({ ~ppLib[\melodies][\classic_lead][\rev] > rev0 }, 2).not) {
					fail.(name, "rev stayed at % after re-sending classic_lead".format(rev0));
				};
				sendSel.('/pp/melody', 'classic');
				if (waitFor.({ ~ppSel[\melodies] == \classic }, 2).not) {
					fail.(name, "~ppSel[\\melodies] never returned to classic");
				};
				checkOk.(name);
			}.value;

			// 3. python one-liner (D-07): the command the library README documents.
			{
				var name = "python one-liner";
				var cmd, rc;
				cmd = "\"%\" -c \"from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', %).send_message('/pp/melody', 'classic_lead')\"".format(venvPython, NetAddr.langPort);
				rc = cmd.systemCmd;
				if (rc != 0) { fail.(name, "python exited with %: %".format(rc, cmd)) };
				if (waitFor.({ ~ppSel[\melodies] == \classic_lead }, 3).not) {
					fail.(name, "~ppSel[\\melodies] never became classic_lead after the python message");
				};
				sendSel.('/pp/melody', 'classic');
				if (waitFor.({ ~ppSel[\melodies] == \classic }, 2).not) {
					fail.(name, "~ppSel[\\melodies] never returned to classic");
				};
				checkOk.(name);
			}.value;

			// 4. auto plays classic (RESEARCH open question 3).
			{
				var name = "auto plays classic";
				sendSel.('/pp/melody', 'auto');
				sendSel.('/pp/progression', 'auto');
				sendSel.('/pp/palette', 'auto');
				if (waitFor.({ ~ppLibCategories.every { |c| ~ppSel[c] == \auto } }, 2).not) {
					fail.(name, "selections did not become auto: %".format(~ppSel));
				};
				matchGold4.(name);
				restoreAll.(name);
				checkOk.(name);
			}.value;

			// 5. select palette and progression: both reload and the groove is unchanged.
			{
				var name = "select palette and progression";
				var palRev, progRev;
				palRev = ~ppLib[\palettes][\classic][\rev];
				sendSel.('/pp/palette', 'classic');
				if (waitFor.({ ~ppLib[\palettes][\classic][\rev] > palRev }, 3).not) {
					fail.(name, "palette rev stayed at % after re-sending classic".format(palRev));
				};
				progRev = ~ppLib[\progressions][\classic][\rev];
				sendSel.('/pp/progression', 'classic');
				if (waitFor.({ ~ppLib[\progressions][\classic][\rev] > progRev }, 3).not) {
					fail.(name, "progression rev stayed at % after re-sending classic".format(progRev));
				};
				matchGold4.(name);
				checkOk.(name);
			}.value;

			// 6. invalid names ignored (edges LIB-02 empty and encoding, T-04-05).
			{
				var name = "invalid names ignored";
				var snap, before, fresh, warnings;
				snap = ~ppSel.copy;
				before = ~ppLogCount;
				sendSel.('/pp/melody', nil);
				sendSel.('/pp/melody', "");
				sendSel.('/pp/melody', 3);
				sendSel.('/pp/melody', 2.5);
				sendSel.('/pp/melody', 'Classic');
				sendSel.('/pp/melody', "classic\n");
				sendSel.('/pp/melody', "clássico");
				sendSel.('/pp/melody', "my lead");
				sendSel.('/pp/melody', "../x");
				sendSel.('/pp/melody', "_template");
				sendSel.('/pp/melody', String.fill(65, $a));
				sendSel.('/pp/palette', "../../main");
				1.wait;
				~ppLibCategories.do { |c|
					if (~ppSel[c] != snap[c]) {
						fail.(name, "% selection changed from % to %".format(c, snap[c], ~ppSel[c]));
					};
				};
				fresh = newLogs.(before);
				warnings = fresh.count { |l| l.find("WARNING: ignoring").notNil };
				if (warnings < 12) {
					fail.(name, "% WARNING lines, expected at least 12: %".format(warnings, fresh));
				};
				if (fresh.any { |l| l.find("loading").notNil }) {
					fail.(name, "a library path was built for an invalid name: %".format(fresh));
				};
				checkOk.(name);
			}.value;

			// 7. unknown name: a well-formed name with no file is refused loudly.
			{
				var name = "unknown name";
				var snap, before, path;
				snap = ~ppSel[\melodies];
				before = ~ppLogCount;
				path = ~ppLibRoot +/+ "melodies/nope.scd";
				sendSel.('/pp/melody', 'nope');
				if (waitFor.({
					newLogs.(before).any { |l| l.find("ERROR").notNil and: { l.find(path).notNil } }
				}, 2).not) {
					fail.(name, "no ERROR line naming % in %".format(path, newLogs.(before)));
				};
				if (~ppSel[\melodies] != snap) {
					fail.(name, "~ppSel[\\melodies] changed to % after an unknown name".format(~ppSel[\melodies]));
				};
				checkOk.(name);
			}.value;

			// 8. latest wins (edge LIB-02 concurrency): two back-to-back selections.
			{
				var name = "latest wins";
				var rc, arp;
				rc = recordBars.(12, 16, { |recClock, startBeat|
					while { recClock.beats < (startBeat + 16) } { 0.02.wait };  // bar 4
					sendSel.('/pp/melody', 'classic_lead');
					sendSel.('/pp/melody', 'classic');
					1.wait;
				});
				if (~ppSel[\melodies] != \classic) {
					fail.(name, "~ppSel[\\melodies] is % after classic_lead then classic".format(~ppSel[\melodies]));
				};
				arp = rc[\rows].select { |r| r[0] == \ppArp };
				if (arp.size != 192) { fail.(name, "% arp rows, expected 192".format(arp.size)) };
				arp.do { |r, i|
					if ((r[1] - (i * 0.25)).abs > 1e-6) {
						fail.(name, "arp row % at beat % is not at %".format(i, r[1], i * 0.25));
					};
				};
				checkOk.(name);
			}.value;

			// The tier leaves every category on classic.
			~ppLibCategories.do { |c|
				if (~ppSel[c] != \classic) {
					fail.("selection tier", "% left on % instead of classic".format(c, ~ppSel[c]));
				};
			};

			// ============================================================
			// Fallback tier (LIB-04, LIB-05): broken, hostile and changing
			// files in a TEMPORARY library root. Nothing is ever written
			// inside supercollider/library/.
			// ============================================================
			realLibRoot = ~ppLibRoot;
			tmpRoot = Platform.defaultTempDir +/+ ("pedalpulse-libtest-" ++ Date.getDate.stamp);
			["progressions", "melodies", "palettes"].do { |c| File.mkdir(tmpRoot +/+ c) };
			File.mkdir(tmpRoot ++ "_outside");
			[
				"progressions/classic.scd", "melodies/classic.scd",
				"melodies/classic_lead.scd", "palettes/classic.scd"
			].do { |rel|
				var rc = ("cp" + shq.(realLibRoot +/+ rel) + shq.(tmpRoot +/+ rel)).systemCmd;
				if (rc != 0) { fail.("fallback setup", "cp of % failed with %".format(rel, rc)) };
			};
			~ppLibRoot = tmpRoot;

			// Broken and hostile fixtures.
			wr.("melodies/broken_syntax.scd", "(\ndesc: \"broken syntax\",\narp: { |plan, state| [[60, 4, 0.1, 0.5]] }\n");
			wr.("melodies/throws_on_load.scd", "Error(\"boom at load\").throw;\n(desc: \"throws on load\", arp: { |plan, state| [[60, 4, 0.1, 0.5]] })\n");
			wr.("melodies/empty.scd", "");
			wr.("melodies/comment_only.scd", "// nothing but a comment\n");
			wr.("melodies/not_event.scd", "42\n");
			wr.("melodies/no_desc.scd", "(arp: { |plan, state| [[60, 4, 0.1, 0.5]] })\n");
			wr.("melodies/wrong_shape.scd", "(desc: \"wrong shape\", arp: 5)\n");
			File.use(tmpRoot ++ "_outside/escape_target.scd", "w", { |f|
				f.write("(desc: \"outside the library\", arp: { |plan, state| [[60, 4, 0.1, 0.5]] })\n");
			});
			("ln -s" + shq.(tmpRoot ++ "_outside/escape_target.scd") + shq.(tmpRoot +/+ "melodies/escape.scd")).systemCmd;
			wr.("palettes/bad_defs.scd", "(desc: \"bad defs\", defs: { Error(\"boom in defs\").throw }, roles: (arp: (instrument: 'ppArp')))\n");
			wr.("palettes/ghost_voice.scd", "(desc: \"ghost voice\", roles: (arp: (instrument: 'pp_ghost_arp')))\n");
			wr.("progressions/not_function.scd", "(desc: \"not a function\", bass: \"not a function\")\n");

			// 1. broken files refused (LIB-04, edge LIB-02 empty file).
			{
				var name = "broken files refused";
				var snap, rc, fixtures;
				snap = ~ppSel.copy;
				fixtures = [
					['/pp/melody', \broken_syntax, "melodies/broken_syntax.scd"],
					['/pp/melody', \throws_on_load, "melodies/throws_on_load.scd"],
					['/pp/melody', \empty, "melodies/empty.scd"],
					['/pp/melody', \comment_only, "melodies/comment_only.scd"],
					['/pp/melody', \not_event, "melodies/not_event.scd"],
					['/pp/melody', \no_desc, "melodies/no_desc.scd"],
					['/pp/melody', \wrong_shape, "melodies/wrong_shape.scd"],
					['/pp/melody', \escape, "melodies/escape.scd"],
					['/pp/palette', \bad_defs, "palettes/bad_defs.scd"],
					['/pp/palette', \ghost_voice, "palettes/ghost_voice.scd"],
					['/pp/progression', \not_function, "progressions/not_function.scd"],
					['/pp/melody', \nope2, "melodies/nope2.scd"]
				];
				rc = recordBars.(40, 16, { |recClock, startBeat|
					while { recClock.beats < (startBeat + 8) } { 0.02.wait };
					fixtures.do { |f|
						var before = ~ppLogCount;
						var path = tmpRoot +/+ f[2];
						sendSel.(f[0], f[1]);
						if (waitFor.({
							newLogs.(before).any { |l| l.find("ERROR").notNil and: { l.find(path).notNil } }
						}, 2).not) {
							fail.(name, "no ERROR line naming % in %".format(path, newLogs.(before)));
						};
						0.1.wait;
						~ppLibCategories.do { |c|
							if (~ppSel[c] != snap[c]) {
								fail.(name, "% selection changed from % to % after %".format(c, snap[c], ~ppSel[c], f[1]));
							};
						};
					};
				});
				if (rc[\rows].any { |r| r[0] == \ppLead }) {
					fail.(name, "the lead played while every category stayed on classic");
				};
				expectClassicBars.(name, rc[\rows], 40);
				checkOk.(name);
			}.value;

			// 2. added file selectable (LIB-05): a valid file written while the engine runs.
			{
				var name = "added file selectable";
				var rc, lead, arp, first;
				wr.("melodies/fresh.scd", freshText.("fresh", 24));
				rc = recordBars.(12, 16, { |recClock, startBeat|
					while { recClock.beats < (startBeat + 8) } { 0.02.wait };  // bar 2
					sendSel.('/pp/melody', 'fresh');
					if (waitFor.({ ~ppSel[\melodies] == \fresh }, 2).not) {
						fail.(name, "~ppSel[\\melodies] never became fresh");
					};
				});
				lead = rc[\rows].select { |r| r[0] == \ppLead };
				arp = rc[\rows].select { |r| r[0] == \ppArp };
				if (lead.isEmpty) { fail.(name, "no lead rows after selecting fresh") };
				first = lead[0][1];
				if (((first / 4).round - (first / 4)).abs > 1e-6) {
					fail.(name, "first lead row at beat % is not on a bar line".format(first));
				};
				leadDiffs.(rc[\rows]).do { |d|
					if (d[1] != 24) { fail.(name, "lead note is arp + % in bar %, expected + 24".format(d[1], d[0])) };
				};
				if (arp.size != 192) { fail.(name, "% arp rows, expected 192".format(arp.size)) };
				checkOk.(name);
			}.value;

			// 3. changed file reloads on whole bars (edge LIB-05 concurrency).
			{
				var name = "changed file reloads on whole bars";
				var rc, arp, diffs, byBar, keys, switchBar;
				rc = recordBars.(16, 16, { |recClock, startBeat|
					var rev0;
					while { recClock.beats < (startBeat + 8) } { 0.02.wait };  // bar 2
					rev0 = ~ppLib[\melodies][\fresh][\rev];
					wr.("melodies/fresh.scd", freshText.("fresh", 19));
					sendSel.('/pp/melody', 'fresh');
					if (waitFor.({ ~ppLib[\melodies][\fresh][\rev] > rev0 }, 2).not) {
						fail.(name, "the rev of fresh never rose after the file changed");
					};
				});
				arp = rc[\rows].select { |r| r[0] == \ppArp };
				diffs = leadDiffs.(rc[\rows]);
				byBar = Dictionary.new;
				diffs.do { |d| byBar[d[0]] = (byBar[d[0]] ? List.new).add(d[1]) };
				keys = byBar.keys.asArray.sort;
				if (keys.size != 16) { fail.(name, "lead plays in % of 16 bars: %".format(keys.size, keys)) };
				switchBar = nil;
				keys.do { |b|
					var vals = byBar[b];
					if (vals.size != 16) { fail.(name, "bar % holds % lead rows, expected 16".format(b, vals.size)) };
					if (vals.any { |v| v != vals[0] }) {
						fail.(name, "bar % mixes rows of the old and the new copy: %".format(b, vals));
					};
					if (switchBar.isNil) {
						if (vals[0] == 19) {
							switchBar = b;
						} {
							if (vals[0] != 24) { fail.(name, "bar % has lead offset %".format(b, vals[0])) };
						};
					} {
						if (vals[0] != 19) { fail.(name, "bar % went back to offset % after the switch".format(b, vals[0])) };
					};
				};
				if (switchBar.isNil) { fail.(name, "the lead never switched to the changed file") };
				if (switchBar < 2) { fail.(name, "the lead switched in bar % before the file changed".format(switchBar)) };
				if (arp.size != 256) { fail.(name, "% arp rows, expected 256".format(arp.size)) };
				arp.do { |r, i|
					if ((r[1] - (i * 0.25)).abs > 1e-6) {
						fail.(name, "arp row % at beat % is not at %".format(i, r[1], i * 0.25));
					};
				};
				checkOk.(name);
			}.value;

			// 4. broken edit keeps last good (CONTEXT discretion: last good copy).
			{
				var name = "broken edit keeps last good";
				var before, path, rev0, rc, diffs;
				before = ~ppLogCount;
				path = tmpRoot +/+ "melodies/fresh.scd";
				rev0 = ~ppLib[\melodies][\fresh][\rev];
				wr.("melodies/fresh.scd", "(\ndesc: \"fresh, now broken\",\narp: { |plan, state| [[60, 4, 0.1, 0.5]] }\n");
				sendSel.('/pp/melody', 'fresh');
				if (waitFor.({
					newLogs.(before).any { |l| l.find("ERROR").notNil and: { l.find(path).notNil } }
				}, 2).not) {
					fail.(name, "no ERROR line naming % in %".format(path, newLogs.(before)));
				};
				0.2.wait;
				if (~ppSel[\melodies] != \fresh) {
					fail.(name, "~ppSel[\\melodies] is % after the broken edit, expected fresh".format(~ppSel[\melodies]));
				};
				if (~ppLib[\melodies][\fresh][\rev] != rev0) {
					fail.(name, "the registry copy of fresh changed (rev % -> %)".format(rev0, ~ppLib[\melodies][\fresh][\rev]));
				};
				rc = recordBars.(4, 32);
				diffs = leadDiffs.(rc[\rows]);
				if (diffs.size != 64) { fail.(name, "% lead rows, expected 64 from the last good copy".format(diffs.size)) };
				diffs.do { |d|
					if (d[1] != 19) { fail.(name, "lead is arp + % in bar %, expected the last good copy (+ 19)".format(d[1], d[0])) };
				};
				checkOk.(name);
			}.value;

			// 5. broken never wins a race (edge LIB-04 concurrency).
			{
				var name = "broken never wins a race";
				var before, path, rc;
				sendSel.('/pp/melody', 'classic');
				if (waitFor.({ ~ppSel[\melodies] == \classic }, 3).not) {
					fail.(name, "~ppSel[\\melodies] never returned to classic");
				};
				("cp" + shq.(tmpRoot +/+ "melodies/classic_lead.scd") + shq.(tmpRoot +/+ "melodies/fresh2.scd")).systemCmd;
				before = ~ppLogCount;
				path = tmpRoot +/+ "melodies/broken_syntax.scd";
				sendSel.('/pp/melody', 'fresh2');
				sendSel.('/pp/melody', 'broken_syntax');
				1.wait;
				if (~ppSel[\melodies] == \broken_syntax) {
					fail.(name, "the broken file became the melody selection");
				};
				if (([\fresh2, \classic].includes(~ppSel[\melodies])).not) {
					fail.(name, "~ppSel[\\melodies] is %, expected fresh2 or classic".format(~ppSel[\melodies]));
				};
				if (newLogs.(before).any { |l| l.find("ERROR").notNil and: { l.find(path).notNil } }.not) {
					fail.(name, "no ERROR line naming % in %".format(path, newLogs.(before)));
				};
				rc = recordBars.(4, 32);
				expectClassicBars.(name, rc[\rows], 4);
				checkOk.(name);
			}.value;

			// ============================================================
			// Containment tier (LIB-04, LIB-06): a file that loads fine but
			// misbehaves while playing. Same temporary library root.
			// ============================================================

			// 6. rows validation (edge LIB-06 adjacency): 4.0 within 1e-6 passes.
			{
				var name = "rows validation";
				var good, bad, r;
				good = [
					["16 rows of a sixteenth", Array.fill(16, { [60, 0.25, 0.1, 0.5] })],
					["4.0000005 beats", [[60, 2, 0.1, 0.5], [60, 2.0000005, 0.1, 0.5]]],
					["a rest and a chord", [[\rest, 2, 0, 1], [[45, 48, 52], 2, 0.06, 0.9]]]
				];
				good.do { |g|
					r = ~ppRowsValid.(g[1]);
					if (r.notNil) { fail.(name, "% should pass but got: %".format(g[0], r)) };
				};
				bad = [
					["3.5 beats", [[60, 3.5, 0.1, 0.5]]],
					["4.5 beats", [[60, 4.5, 0.1, 0.5]]],
					["no rows", []],
					["a dur of 0", [[60, 0, 0.1, 0.5], [60, 4, 0.1, 0.5]]],
					["an amp of 1.5", [[60, 4, 1.5, 0.5]]],
					["a note \"x\"", [["x", 4, 0.1, 0.5]]],
					["a row of 3 items", [[60, 4, 0.1]]],
					["not an Array", 5],
					["a nan dur", [[60, 0 / 0, 0.1, 0.5]]]
				];
				bad.do { |b|
					r = ~ppRowsValid.(b[1]);
					if (r.isKindOf(String).not) { fail.(name, "% should fail but passed".format(b[0])) };
				};
				if (~ppRowsValid.([[60, 3.5, 0.1, 0.5]]).find("3.5").isNil) {
					fail.(name, "the 3.5 beat reason does not say 3.5");
				};
				checkOk.(name);
			}.value;

			// 7. generator error falls back (LIB-04): a generator that throws at play time.
			{
				var name = "generator error falls back";
				var before, path, rc, arp, fresh, notes;
				notes = [57, 60, 64, 60];
				wr.("melodies/gen_throws.scd", "(desc: \"arp throws\", arp: { |plan, state| Error(\"boom in arp\").throw })\n");
				path = tmpRoot +/+ "melodies/gen_throws.scd";
				before = ~ppLogCount;
				rc = recordBars.(10, 16, { |recClock, startBeat|
					while { recClock.beats < (startBeat + 8) } { 0.02.wait };  // bar 2
					sendSel.('/pp/melody', 'gen_throws');
					if (waitFor.({ ~ppSel[\melodies] == \gen_throws }, 2).not) {
						fail.(name, "~ppSel[\\melodies] never became gen_throws");
					};
				});
				arp = rc[\rows].select { |r| r[0] == \ppArp };
				if (arp.size != 160) { fail.(name, "% arp rows, expected 160: the layer went silent".format(arp.size)) };
				arp.do { |r, i|
					if ((r[1] - (i * 0.25)).abs > 1e-6) { fail.(name, "arp row % at beat % is not at %".format(i, r[1], i * 0.25)) };
					if (r[3] != notes[i % 4]) { fail.(name, "arp row % is note %, expected the classic %".format(i, r[3], notes[i % 4])) };
				};
				fresh = newLogs.(before);
				if (fresh.count { |l| l.find("playing classic for this bar").notNil and: { l.find(path).notNil } } > 3) {
					fail.(name, "more than 3 fallback ERROR lines for %: %".format(path, fresh));
				};
				if (fresh.count { |l| l.find("playing classic for this bar").notNil and: { l.find(path).notNil } } < 1) {
					fail.(name, "no fallback ERROR line naming %: %".format(path, fresh));
				};
				if (fresh.any { |l| l.find("failed 3 times -- melodies back to classic").notNil }.not) {
					fail.(name, "no 'failed 3 times -- melodies back to classic' line: %".format(fresh));
				};
				if (~ppSel[\melodies] != \classic) {
					fail.(name, "~ppSel[\\melodies] is % at the end, expected classic".format(~ppSel[\melodies]));
				};
				checkOk.(name);
			}.value;

			// 8. short bar falls back: rows that fill 3.5 beats, not 4.
			{
				var name = "short bar falls back";
				var before, path, rc, arp, fresh, notes, mine;
				notes = [57, 60, 64, 60];
				wr.("melodies/gen_short.scd", "(desc: \"short bar\", arp: { |plan, state| Array.fill(14, { [60, 0.25, 0.1, 0.5] }) })\n");
				path = tmpRoot +/+ "melodies/gen_short.scd";
				before = ~ppLogCount;
				rc = recordBars.(10, 16, { |recClock, startBeat|
					while { recClock.beats < (startBeat + 8) } { 0.02.wait };  // bar 2
					sendSel.('/pp/melody', 'gen_short');
					if (waitFor.({ ~ppSel[\melodies] == \gen_short }, 2).not) {
						fail.(name, "~ppSel[\\melodies] never became gen_short");
					};
				});
				arp = rc[\rows].select { |r| r[0] == \ppArp };
				if (arp.size != 160) { fail.(name, "% arp rows, expected 160: the layer went silent".format(arp.size)) };
				arp.do { |r, i|
					if ((r[1] - (i * 0.25)).abs > 1e-6) { fail.(name, "arp row % at beat % is not at %".format(i, r[1], i * 0.25)) };
					if (r[3] != notes[i % 4]) { fail.(name, "arp row % is note %, expected the classic %".format(i, r[3], notes[i % 4])) };
				};
				fresh = newLogs.(before);
				mine = fresh.select { |l| l.find("playing classic for this bar").notNil and: { l.find(path).notNil } };
				if ((mine.size < 1) or: { mine.size > 3 }) {
					fail.(name, "% fallback ERROR lines naming %, expected 1 to 3: %".format(mine.size, path, fresh));
				};
				if (mine.any { |l| l.find("3.5").isNil }) {
					fail.(name, "a fallback ERROR line does not say 3.5: %".format(mine));
				};
				if (fresh.any { |l| l.find("failed 3 times -- melodies back to classic").notNil }.not) {
					fail.(name, "no 'failed 3 times -- melodies back to classic' line: %".format(fresh));
				};
				if (~ppSel[\melodies] != \classic) {
					fail.(name, "~ppSel[\\melodies] is % at the end, expected classic".format(~ppSel[\melodies]));
				};
				checkOk.(name);
			}.value;

			// 9. seeded generators replay (VERIFY flag: per-(song, bar, role) seeding).
			{
				var name = "seeded generators replay";
				var rc1, rc2, n1, n2, s1, s2;
				wr.("melodies/seedprobe.scd", "(desc: \"random arp\", arp: { |plan, state| Array.fill(16, { [rrand(60, 72), 0.25, 0.05, 0.5] }) })\n");
				sendSel.('/pp/melody', 'seedprobe');
				if (waitFor.({ ~ppSel[\melodies] == \seedprobe }, 3).not) {
					fail.(name, "~ppSel[\\melodies] never became seedprobe");
				};
				rc1 = recordBars.(4, 32);
				rc2 = recordBars.(4, 32);
				n1 = rc1[\rows].select { |r| r[0] == \ppArp }.collect { |r| r[3] };
				n2 = rc2[\rows].select { |r| r[0] == \ppArp }.collect { |r| r[3] };
				if (n1.size != 64) { fail.(name, "% arp rows, expected 64".format(n1.size)) };
				if (n1 != n2) { fail.(name, "two restarts played different notes: % vs %".format(n1, n2)) };
				if (n1.copyRange(0, 15) == n1.copyRange(16, 31)) {
					fail.(name, "bar 0 and bar 1 play the same notes: the seed does not follow the bar");
				};
				s1 = ~ppSeedFor.(0, 5, \lead);
				s2 = ~ppSeedFor.(0, 5, \lead);
				if ((s1 != s2) or: { s1.isInteger.not } or: { s1 < 0 } or: { s1 > 0x7FFFFFFF }) {
					fail.(name, "~ppSeedFor gave % and % (expected one Integer in 0..0x7FFFFFFF)".format(s1, s2));
				};
				sendSel.('/pp/melody', 'classic');
				if (waitFor.({ ~ppSel[\melodies] == \classic }, 3).not) {
					fail.(name, "~ppSel[\\melodies] never returned to classic");
				};
				checkOk.(name);
			}.value;

			// 10. plan bar is the played bar (VERIFY flag: thisThread.beats at the bar start),
			// across a tempo change.
			{
				var name = "plan bar is the played bar";
				var rc, arp;
				wr.("melodies/barprobe.scd", "(desc: \"bar number probe\", arp: { |plan, state| [[60 + (plan[\\bar] % 12), 4, 0.05, 0.5]] })\n");
				sendSel.('/pp/melody', 'barprobe');
				if (waitFor.({ ~ppSel[\melodies] == \barprobe }, 3).not) {
					fail.(name, "~ppSel[\\melodies] never became barprobe");
				};
				rc = recordBars.(12, 16, { |recClock, startBeat|
					while { recClock.beats < (startBeat + 20) } { 0.02.wait };  // bar 5
					recClock.tempo = 23;
				});
				arp = rc[\rows].select { |r| r[0] == \ppArp };
				if (arp.size != 12) { fail.(name, "% arp rows, expected 12".format(arp.size)) };
				arp.do { |r|
					var absBar = ((rc[\startBeat] + r[1]) / 4 + 1e-6).floor.asInteger;
					if ((r[3] - 60) != (absBar % 12)) {
						fail.(name, "the arp row at beat % is note %, but the played bar is % (expected %)".format(r[1], r[3], absBar, 60 + (absBar % 12)));
					};
				};
				sendSel.('/pp/melody', 'classic');
				if (waitFor.({ ~ppSel[\melodies] == \classic }, 3).not) {
					fail.(name, "~ppSel[\\melodies] never returned to classic");
				};
				checkOk.(name);
			}.value;

			// Back to the real library: classic everywhere, then the two
			// temporary folders (and only those) removed.
			~ppLibRoot = realLibRoot;
			{
				var revs = ();
				~ppLibCategories.do { |c| revs[c] = ~ppLib[c][\classic][\rev] };
				sendSel.('/pp/progression', 'classic');
				sendSel.('/pp/palette', 'classic');
				sendSel.('/pp/melody', 'classic');
				~ppLibCategories.do { |c|
					if (waitFor.({ ~ppLib[c][\classic][\rev] > revs[c] }, 5).not) {
						fail.("fallback cleanup", "classic % was not reloaded from the real library".format(c));
					};
				};
				~ppLibCategories.do { |c|
					if (~ppSel[c] != \classic) {
						fail.("fallback cleanup", "% left on % instead of classic".format(c, ~ppSel[c]));
					};
				};
			}.value;
			cleanupTmp.value;
			tmpRoot = nil;

			"LIBRARY PASS".postln;
			s.quit(onComplete: { 0.exit });
		};
	}.try({ |err|
		"LIBRARY FAIL: %".format(err.errorString).postln;
		cleanupTmp.value;
		s.quit(onComplete: { 1.exit });
	});
}, AppClock);
)
