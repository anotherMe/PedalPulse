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
var harmonyCheck, enumVoicings, voicingCost, strictChordCheck;

// Watchdog first, in case anything below hangs. 300 s: the Phase 6 harmony tiers
// record every chord-data progression on disk (two cycles plus a restart each).
SystemClock.sched(300, {
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

// harmonyCheck.(name, rws, layers): every note of every row of the given layers
// has its pitch class inside the chord of its own bar (the entry the engine
// played from, ~ppHarmonyEntry), plus the chord's extraPcs (classic's documented
// passing F). Bars are the recording's relative bars, which are the song bars.
harmonyCheck = { |name, rws, layers|
	rws.do { |r|
		if (layers.includes(r[0])) {
			var b = barOf.(r[1]), entry = ~ppHarmonyEntry.(b), chord, allowed, notes;
			if (entry.isNil) {
				fail.(name, "no harmony entry for bar % (layer %)".format(b, r[0]));
			};
			chord = entry[\chord];
			allowed = chord[\pcs] ++ (chord[\extraPcs] ? []);
			notes = if (r[3].isArray) { r[3] } { [r[3]] };
			notes.do { |note|
				if (allowed.includes(note.round.asInteger % 12).not) {
					fail.(name, "% bar % plays note % outside chord % of progression %".format(r[0], b, note, chord[\name], entry[\progression]));
				};
			};
		};
	};
};

// enumVoicings.(pcs, window): every close-position voicing of the pitch classes
// inside the window, found independently of the core's inversion search: the
// lowest note is each window note whose pitch class is in the chord, and every
// other pitch class sits at the one note above it within the next 11 semitones.
// Returns Arrays of ascending notes. (HARM-03: the oracle for "nearest voicing".)
enumVoicings = { |pcs, window|
	var out = List.new;
	(window[0]..window[1]).do { |lo|
		if (pcs.includes(lo % 12)) {
			var v = [lo] ++ pcs.reject { |p| p == (lo % 12) }.collect { |p| lo + ((p - lo) % 12) };
			v = v.sort;
			if (v.last <= window[1]) { out.add(v) };
		};
	};
	out.asArray
};

// voicingCost.(voicing, prev): summed note-by-note movement, as the core counts it.
voicingCost = { |v, prev|
	var c = 0;
	v.do { |n, i| c = c + (n - prev[min(i, prev.size - 1)]).abs };
	c
};

// strictChordCheck.(label, stem, mod, add): the strict rule for a chord-data
// progression (HARM-01, HARM-03). Two full cycles are walked with explicit pure
// entries (never the live memo, so every file is checked the same way) and the
// bass, pad and arp are rendered through ~ppRenderBar's 5-argument form. There is
// no allowance for chord data: every sounding note is in its bar's chord. Only
// classic's implicit Am carries the passing-F allowance, and it is not chord data.
// Failures go to add; each kind of failure is reported once per role.
strictChordCheck = { |label, stem, mod, add|
	var cyc, len, prev = nil, ents = List.new, logBefore, seen = Set.new, once, padPrev, figure;
	once = { |key, text|
		var k = key.asString;
		if (seen.includes(k).not) {
			seen.add(k);
			add.(text);
		};
	};
	cyc = ~ppHarmCycle.(stem, mod);
	len = cyc[\len];
	// RESEARCH Open Question 5: a long cycle is a warning, never a failure.
	if (len > 8) {
		"CHECK WARN: % cycle is % bars; a pick waits up to % bars".format(label, len, len).postln;
	};
	(2 * len).do { |b|
		var cb = b % len, nf, en;
		nf = if (cb == (len - 1)) { cyc[\spans][0][\chord] } { nil };
		en = ~ppHarmEntry.(cyc, cb, prev, nf);
		prev = en[\voicing];
		ents.add(en);
	};
	figure = [57, 60, 64, 60];
	logBefore = ~ppLogCount;
	[\bass, \pad, \arp].do { |role|
		var ls = ();
		ents.do { |en, b|
			var rows, plain, why, sounding, chord = en[\chord], where, onsets, t0 = 0, want, legato;
			where = "% % bar %".format(label, role, b);
			rows = ~ppRenderBar.(role, b, b, ls, en);
			plain = rows.collect { |r| r.copyToEnd(1) };
			why = ~ppRowsValid.(plain);
			if (why.notNil) { once.([role, \rows], "%: %".format(where, why)) };
			sounding = rows.select { |r| r[1] !== \rest };
			sounding.do { |r|
				var notes = if (r[1].isArray) { r[1] } { [r[1]] };
				notes.do { |nn|
					if (chord[\pcs].includes(nn.round.asInteger % 12).not) {
						once.([role, \chord], "%: note % is not in chord %".format(where, nn, chord[\name]));
					};
				};
			};
			if (role == \bass) {
				onsets = rows.collect { |r| var o = t0; t0 = t0 + r[2]; o };
				if (sounding.size != 4) {
					once.([role, \count], "%: sounds % notes, expected 4 offbeat notes".format(where, sounding.size));
				};
				rows.do { |r, i|
					if ((r[1] !== \rest) and: { ((onsets[i] % 1) - 0.5).abs > 1e-6 }) {
						once.([role, \offbeat], "%: a note starts at beat % which is not an offbeat".format(where, onsets[i]));
					};
				};
			};
			if (role == \arp) {
				want = Array.fill(16, { |i| ~ppFollowNote.(figure.wrapAt(i), chord) });
				if (sounding.collect { |r| r[1] } != want) {
					once.([role, \figure], "%: notes are % instead of the classic figure on %: %".format(where, sounding.collect { |r| r[1] }, chord[\name], want));
				};
			};
			if (role == \pad) {
				if (en[\chordBar] == 0) {
					if (sounding.size != 1) {
						once.([role, \count], "%: sounds % rows on a chord's first bar, expected 1".format(where, sounding.size));
					} {
						legato = min(0.9 * en[\chordBars], en[\chordBars] - 0.25);
						if ((sounding[0][4] - legato).abs > 1e-9) {
							once.([role, \legato], "%: legato is % instead of %".format(where, sounding[0][4], legato));
						};
						// The gate closes at least one beat before the next chord.
						if ((sounding[0][2] * sounding[0][4]) > ((en[\chordBars] * 4) - 1 + 1e-6)) {
							once.([role, \gate], "%: the gate closes less than one beat before the next chord".format(where));
						};
						if (sounding[0][1] != en[\voicing]) {
							once.([role, \voicing], "%: sounds % instead of the entry's voicing %".format(where, sounding[0][1], en[\voicing]));
						};
					};
				} {
					if (sounding.size != 0) {
						once.([role, \hold], "%: sounds % rows inside a held chord, expected none".format(where, sounding.size));
					};
				};
			};
		};
	};
	// Every pad change is the nearest close voicing and stays inside the window.
	padPrev = ~ppPadHome;
	ents.do { |en, b|
		if (en[\chordBar] == 0) {
			var v = en[\voicing], cands, best;
			cands = enumVoicings.(en[\chord][\pcs], ~ppPadWindow);
			if (cands.isEmpty) {
				once.([\pad, \cands], "% pad bar %: no voicing of % fits the window".format(label, b, en[\chord][\name]));
			} {
				best = cands.collect { |x| voicingCost.(x, padPrev) }.minItem;
				if ((v.first < ~ppPadWindow[0]) or: { v.last > ~ppPadWindow[1] }) {
					once.([\pad, \window], "% pad bar %: voicing % leaves %".format(label, b, v, ~ppPadWindow));
				};
				if (voicingCost.(v, padPrev) != best) {
					once.([\pad, \nearest], "% pad bar %: voicing % moves % semitones, the nearest moves %".format(label, b, v, voicingCost.(v, padPrev), best));
				};
			};
			padPrev = v;
		};
	};
	if (newLogs.(logBefore).any { |l| l.find("playing classic for this bar").notNil }) {
		add.("% fell back to classic while rendering: %".format(label, newLogs.(logBefore).select { |l| l.find("playing classic for this bar").notNil }.join(" | ")));
	};
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

					// (c2) chord-data progressions: the strict harmony rule, two full cycles.
					// No allowance for chord data (only classic's implicit Am has one).
					if ((cat == \progressions) and: { mod[\chords].notNil }) {
						try {
							strictChordCheck.(label, stem, mod, add);
						} { |err|
							add.("% strict chord check threw: %".format(label, err.errorString));
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
						// Files never share a harmony memo: every file renders bars 0-3 on this clock.
						~ppHarmReset.value;
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
						~ppHarmReset.value;
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
	var sfail, bad, cp, expectFailure, wrs, cf;

	// ============================================================
	// Static tier (LIB-06, LIB-02): no server yet. Every .scd file under
	// supercollider/library, the _template.scd files included, is loaded
	// and checked; the result is one LIBCHECK OK line per file.
	// ============================================================
	{
		~ppRoot = root +/+ "supercollider";
		~ppLibRoot = ~ppRoot +/+ "library";
		["validate.scd", "loader.scd", "harmony.scd", "render.scd"].do { |name|
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
		// Chord-data fixtures (T-06-01, T-06-04): each is a valid desc plus one defect.
		// cf.(extraKeys, chordsText) -> a progression file's text.
		cf = { |extra, chordsText| "(\ndesc: \"chord fixture\",\n%chords: [%]\n)\n".format(extra, chordsText) };
		wrs.("progressions/bad_root.scd", cf.("", "(root: 12, quality: \\min)"));
		wrs.("progressions/bad_quality.scd", cf.("", "(root: 0, quality: \\dim7)"));
		wrs.("progressions/bad_intervals.scd", cf.("", "(root: 0, intervals: [0, 3])"));
		wrs.("progressions/empty_chords.scd", cf.("", ""));
		wrs.("progressions/too_many.scd", cf.("", 17.collect { "(root: 0, quality: \\min)" }.join(", ")));
		wrs.("progressions/zero_bars.scd", cf.("", "(root: 0, quality: \\min, bars: 0), (root: 8, quality: \\maj)"));
		wrs.("progressions/long_cycle.scd", cf.("barsPerChord: 8,\n", "(root: 0, quality: \\min), (root: 8, quality: \\maj), (root: 3, quality: \\maj)"));
		// A valid chord file whose own bass plays a note outside its chord: the strict branch must refuse it.
		wrs.("progressions/strict_bass.scd", "(\ndesc: \"bass outside the chord\",\nbass: { |plan, state| [[34, 4, 0.1, 0.8]] },\nchords: [(root: 0, quality: \\min)]\n)\n");

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
		expectFailure.("a chord root of 12", "chord 1 root is not an Integer from 0 to 11");
		expectFailure.("an unknown chord quality", "chord 1 quality is not one of: maj, min");
		expectFailure.("bad chord intervals", "chord 1 intervals are not 3 or 4 rising Integers from 0 to 11 starting at 0");
		expectFailure.("an empty chord list", "chords is empty");
		expectFailure.("17 chords", "chords has 17 entries, more than 16");
		expectFailure.("0 bars on a chord", "chord 1 bars is not an Integer from 1 to 8");
		expectFailure.("a 24-bar cycle", "the cycle is 24 bars, more than 16");
		expectFailure.("a bass note outside its chord", "progressions/strict_bass bass bar 0: note 34 is not in chord Am");
		if (bad.any { |f| f.beginsWith("melodies/classic") or: { f.beginsWith("palettes/classic") } }) {
			fail.("static check catches bad files", "a good classic file failed in the temporary library: %".format(bad));
		};
		("rm -rf" + shq.(staticTmp)).systemCmd;
		staticTmp = nil;
		checkOk.("static check catches bad files");

		// ---- Harmony units (HARM-01, HARM-03, D-01..D-14): no server needed ----
		// The rules of core/harmony.scd pinned by exact values (the tables of
		// 06-02-PLAN.md), the classic rows proven byte-identical, ownHarmony, and the
		// memo proven shared, bounded and cycle-aligned.
		{
			var req, tbl, chordNamed, pickups, specs, walk, home, window, mod, ls;
			var cyc, ents, changes, voicings, prev, rows, sounding, onsets, t0;
			var entA, entDeep, entF, centry, direct, ownMod, mapMod, own, before, e1, e2, lg, nm, want, ownFn;

			req = { |ok, what| if (ok.not) { fail.("harmony units", what) } };
			home = ~ppPadHome;
			window = ~ppPadWindow;

			// name, root, quality, pcs, arp from 57 60 64 60, bass root, third
			tbl = [
				["Am", 0, \min, [9, 0, 4], [57, 60, 64, 60], 33, 36],
				["F", 8, \maj, [5, 9, 0], [53, 57, 60, 57], 41, 45],
				["C", 3, \maj, [0, 4, 7], [60, 64, 67, 64], 36, 40],
				["G", 10, \maj, [7, 11, 2], [55, 59, 62, 59], 43, 47],
				["Dm", 5, \min, [2, 5, 9], [62, 65, 69, 65], 38, 41],
				["Em", 7, \min, [4, 7, 11], [52, 55, 59, 55], 40, 43],
				["E", 7, \maj, [4, 8, 11], [52, 56, 59, 56], 40, 44]
			];
			chordNamed = { |n|
				var t = tbl.detect { |x| x[0] == n };
				~ppChordExpand.((root: t[1], quality: t[2]))
			};
			// current, next, the bass pickup note on the last eighth
			pickups = [
				["Am", "F", 40], ["F", "C", 36], ["C", "G", 43], ["G", "Am", 35], ["Am", "G", 45],
				["G", "F", 43], ["F", "G", 45], ["Am", "C", 36], ["F", "Am", 33], ["Am", "Em", 40],
				["Em", "F", 40], ["F", "Dm", 36], ["Dm", "Am", 33], ["Am", "Dm", 36], ["Dm", "F", 41],
				["F", "E", 41], ["E", "Am", 32]
			];
			// stem, barsPerChord, chords [root, quality], the pad path (one voicing per chord change)
			specs = [
				[\unit_anthem, 1, [[0, \min], [8, \maj], [3, \maj], [10, \maj]],
					[[45, 48, 52], [45, 48, 53], [43, 48, 52], [43, 47, 50]]],
				[\unit_rocker, 1, [[0, \min], [10, \maj], [8, \maj], [10, \maj]],
					[[45, 48, 52], [43, 47, 50], [45, 48, 53], [43, 47, 50]]],
				[\unit_lift, 1, [[0, \min], [8, \maj], [10, \maj], [10, \maj]],
					[[45, 48, 52], [45, 48, 53], [43, 47, 50]]],
				[\unit_return, 1, [[0, \min], [3, \maj], [10, \maj], [8, \maj]],
					[[45, 48, 52], [43, 48, 52], [43, 47, 50], [45, 48, 53]]],
				[\unit_deep, 2, [[0, \min], [0, \min], [8, \maj], [10, \maj]],
					[[45, 48, 52], [45, 48, 53], [43, 47, 50]]],
				[\unit_melancholy, 1, [[0, \min], [7, \min], [8, \maj], [5, \min]],
					[[45, 48, 52], [43, 47, 52], [45, 48, 53], [45, 50, 53]]],
				[\unit_drama, 1, [[0, \min], [5, \min], [8, \maj], [7, \maj]],
					[[45, 48, 52], [45, 50, 53], [45, 48, 53], [44, 47, 52]]]
			];

			// entries for nCycles passes through a cycle, voicing chained from the home voicing
			// and the cycle's own first chord as the next chord of its last bar.
			walk = { |cycle, nCycles|
				var pv = nil, out = List.new;
				(nCycles * cycle[\len]).do { |b|
					var cb = b % cycle[\len], nf, en;
					nf = if (cb == (cycle[\len] - 1)) { cycle[\spans][0][\chord] } { nil };
					en = ~ppHarmEntry.(cycle, cb, pv, nf);
					pv = en[\voicing];
					out.add(en);
				};
				out.asArray
			};

			// Setup: the real classic files and the seven in-test progressions.
			~ppLib = (progressions: (), melodies: (), palettes: ());
			~ppSel = (progressions: \classic, melodies: \classic, palettes: \classic);
			~ppRenderErrors = ();
			[[\progressions, \classic], [\melodies, \classic], [\melodies, \classic_lead], [\palettes, \classic]].do { |p|
				mod = ~ppLibLoad.(p[0], p[1]);
				req.(mod.notNil, "could not load %/%".format(p[0], p[1]));
				mod[\rev] = 1;
				~ppLib[p[0]].put(p[1], mod);
			};
			specs.do { |sp|
				mod = ();
				mod.put(\desc, "unit progression");
				mod.put(\barsPerChord, sp[1]);
				mod.put(\chords, sp[2].collect { |p| (root: p[0], quality: p[1]) });
				mod.put(\name, sp[0]);
				mod.put(\rev, 1);
				~ppLib[\progressions].put(sp[0], mod);
			};

			// a. chord names and pitch classes, a four-note chord, intervals over quality, the scale.
			tbl.do { |t|
				var c = chordNamed.(t[0]);
				req.(c[\name] == t[0], "chord (%, %) is named % instead of %".format(t[1], t[2], c[\name], t[0]));
				req.(c[\pcs] == t[3], "chord % has pitch classes % instead of %".format(t[0], c[\pcs], t[3]));
			};
			e1 = ~ppChordExpand.((root: 0, intervals: [0, 3, 7, 10]));
			req.(e1[\name] == "A(0,3,7,10)", "the four-note chord is named % instead of A(0,3,7,10)".format(e1[\name]));
			req.(e1[\pcs] == [9, 0, 4, 7], "the four-note chord has pitch classes % instead of [9, 0, 4, 7]".format(e1[\pcs]));
			e1 = ~ppChordExpand.((root: 0, quality: \maj, intervals: [0, 3, 7]));
			req.(e1[\name] == "Am", "intervals did not win over quality: the chord is named %".format(e1[\name]));
			cyc = ~ppHarmCycle.(\unit_e, (desc: "e", chords: [(root: 7, quality: \maj)]));
			e1 = ~ppHarmEntry.(cyc, 0, nil, nil);
			req.(e1[\scale] == [0, 2, 4, 5, 7, 8, 9, 11], "the E major scale is % instead of [0, 2, 4, 5, 7, 8, 9, 11]".format(e1[\scale]));

			// b. arp, lead and non-chord tones.
			tbl.do { |t|
				var c = chordNamed.(t[0]);
				[57, 60, 64, 60].do { |x, i|
					req.(~ppFollowNote.(x, c) == t[4][i], "arp note % under % is % instead of %".format(x, t[0], ~ppFollowNote.(x, c), t[4][i]));
				};
				[69, 72, 76, 72].do { |x, i|
					req.(~ppFollowNote.(x, c) == (t[4][i] + 12), "lead note % under % is % instead of %".format(x, t[0], ~ppFollowNote.(x, c), t[4][i] + 12));
				};
			};
			[["Am", 62, 60], ["Am", 65, 64], ["Am", 59, 60], ["F", 52, 48]].do { |q|
				req.(~ppFollowNote.(q[1], chordNamed.(q[0])) == q[2], "non-chord tone % under % maps to % instead of %".format(q[1], q[0], ~ppFollowNote.(q[1], chordNamed.(q[0])), q[2]));
			};

			// c. bass roots, thirds and pickups.
			tbl.do { |t|
				var c = chordNamed.(t[0]);
				req.(~ppBassRoot.(c) == t[5], "bass root of % is % instead of %".format(t[0], ~ppBassRoot.(c), t[5]));
				req.((~ppBassRoot.(c) + c[\intervals][1]) == t[6], "bass third of % is % instead of %".format(t[0], ~ppBassRoot.(c) + c[\intervals][1], t[6]));
			};
			pickups.do { |pk|
				var got = ~ppBassPickup.(chordNamed.(pk[0]), chordNamed.(pk[1]));
				req.(got == pk[2], "bass pickup % to % is % instead of %".format(pk[0], pk[1], got, pk[2]));
			};

			// d. voicing: the table's path in two cycles, and the nearest voicing inside 40-64.
			specs.do { |sp|
				var stem = sp[0], expect = sp[3], n = sp[3].size;
				cyc = ~ppHarmCycle.(stem, ~ppLib[\progressions][stem]);
				ents = walk.(cyc, 2);
				changes = ents.select { |en| en[\chordBar] == 0 };
				voicings = changes.collect { |en| en[\voicing] };
				req.(voicings.size == (2 * n), "% has % chord changes in two cycles, expected %".format(stem, voicings.size, 2 * n));
				req.(voicings.copyRange(0, n - 1) == expect, "% pad path of the first cycle is % instead of %".format(stem, voicings.copyRange(0, n - 1), expect));
				req.(voicings.copyRange(n, (2 * n) - 1) == expect, "% pad path of the second cycle is % instead of %".format(stem, voicings.copyRange(n, (2 * n) - 1), expect));
				prev = home;
				changes.do { |en, i|
					var v = en[\voicing], cands, best, mv;
					cands = enumVoicings.(en[\chord][\pcs], window);
					best = cands.collect { |x| voicingCost.(x, prev) }.minItem;
					mv = voicingCost.(v, prev);
					req.((v.first >= window[0]) and: { v.last <= window[1] }, "% change % voicing % leaves %".format(stem, i, v, window));
					req.(cands.any { |x| x == v }, "% change % voicing % is not a close-position voicing of %".format(stem, i, v, en[\chord][\name]));
					req.(mv == best, "% change % moves % semitones, the nearest voicing moves %".format(stem, i, mv, best));
					req.(mv <= 6, "% change % moves % semitones, more than 6".format(stem, i, mv));
					prev = v;
				};
			};
			// The precision edge: equal movement goes to the voicing nearest the home mean, then the lower.
			e1 = ~ppNearestVoicing.(chordNamed.("F"), [43, 47, 50]);
			req.(e1 == [45, 48, 53], "after G the F chord is voiced % instead of [45, 48, 53]".format(e1));
			req.((voicingCost.([41, 45, 48], [43, 47, 50]) == voicingCost.([45, 48, 53], [43, 47, 50])), "the G to F tie case is not a tie any more");
			// The boundary edge: previous voicings at and beyond both edges of the window.
			[[40, 40, 40], [64, 64, 64], [38, 42, 45], [66, 70, 73]].do { |pv|
				tbl.do { |t|
					var c = chordNamed.(t[0]), v, best;
					v = ~ppNearestVoicing.(c, pv);
					best = enumVoicings.(c[\pcs], window).collect { |x| voicingCost.(x, pv) }.minItem;
					req.((v.first >= window[0]) and: { v.last <= window[1] }, "voicing % of % after % leaves the window".format(v, t[0], pv));
					req.(voicingCost.(v, pv) == best, "voicing % of % after % is not the nearest (cost % vs %)".format(v, t[0], pv, voicingCost.(v, pv), best));
				};
			};

			// e. cycles.
			cyc = ~ppHarmCycle.(\unit_lift, ~ppLib[\progressions][\unit_lift]);
			req.(cyc[\names] == "Am F G G", "unit_lift names are '%' instead of 'Am F G G'".format(cyc[\names]));
			req.(cyc[\spans].collect { |sp| sp[\chord][\name] } == ["Am", "F", "G"], "unit_lift spans are not Am F G");
			req.(cyc[\spans].collect { |sp| sp[\bars] } == [1, 1, 2], "unit_lift span bars are % instead of [1, 1, 2]".format(cyc[\spans].collect { |sp| sp[\bars] }));
			req.(cyc[\len] == 4, "unit_lift is % bars instead of 4".format(cyc[\len]));
			cyc = ~ppHarmCycle.(\unit_deep, ~ppLib[\progressions][\unit_deep]);
			req.(cyc[\names] == "Am Am F G", "unit_deep names are '%' instead of 'Am Am F G'".format(cyc[\names]));
			req.(cyc[\spans].collect { |sp| sp[\chord][\name] } == ["Am", "F", "G"], "unit_deep spans are not Am F G");
			req.(cyc[\spans].collect { |sp| sp[\bars] } == [4, 2, 2], "unit_deep span bars are % instead of [4, 2, 2]".format(cyc[\spans].collect { |sp| sp[\bars] }));
			req.(cyc[\len] == 8, "unit_deep is % bars instead of 8".format(cyc[\len]));
			cyc = ~ppHarmCycle.(\classic, ~ppLib[\progressions][\classic]);
			req.((cyc[\spans].size == 1) and: { cyc[\spans][0][\chord] === ~ppClassicChord } and: { cyc[\spans][0][\bars] == 1 }, "classic is not one Am span of 1 bar: %".format(cyc[\spans]));
			req.((cyc[\spans][0][\chord][\extraPcs] == [5]) and: { cyc[\len] == 1 } and: { cyc[\names] == "Am" } and: { cyc[\classic] == true }, "classic cycle record is wrong: len % names % classic %".format(cyc[\len], cyc[\names], cyc[\classic]));
			cyc = ~ppHarmCycle.(\unit_gen, (desc: "generators only", bass: { |plan, state| [[\rest, 4, 0, 1]] }));
			req.((cyc[\spans].size == 1) and: { cyc[\spans][0][\chord] === ~ppClassicChord } and: { cyc[\len] == 1 } and: { cyc[\classic] == false }, "a generator-only module is not one Am span with classic false: %".format(cyc[\spans]));

			// f. entries on unit_deep.
			cyc = ~ppHarmCycle.(\unit_deep, ~ppLib[\progressions][\unit_deep]);
			entDeep = walk.(cyc, 1);
			req.((entDeep[0][\chordBar] == 0) and: { entDeep[0][\chordBars] == 4 } and: { entDeep[0][\changesNext] == false }, "unit_deep cycle bar 0 is wrong: chordBar % chordBars % changesNext %".format(entDeep[0][\chordBar], entDeep[0][\chordBars], entDeep[0][\changesNext]));
			req.((entDeep[3][\changesNext] == true) and: { entDeep[3][\nextChord][\name] == "F" }, "unit_deep cycle bar 3 should change to F: changesNext % next %".format(entDeep[3][\changesNext], entDeep[3][\nextChord][\name]));
			e1 = chordNamed.("Em");
			e2 = ~ppHarmEntry.(cyc, 7, [43, 47, 50], e1);
			req.(e2[\nextChord] === e1, "unit_deep cycle bar 7 did not take the next cycle's first chord");

			// g. the core's default bass and pad through the renderer, with explicit entries.
			rows = ~ppRenderBar.(\pad, 0, 0, (), entDeep[0]);
			sounding = rows.select { |r| r[1] !== \rest };
			req.(sounding.size == 1, "unit_deep pad bar 0 sounds % rows, expected 1".format(sounding.size));
			req.(sounding[0][1] == [45, 48, 52], "unit_deep pad bar 0 notes are % instead of [45, 48, 52]".format(sounding[0][1]));
			req.(((sounding[0][3] - 0.06).abs < 1e-9) and: { (sounding[0][4] - 3.6).abs < 1e-9 }, "unit_deep pad bar 0 amp % legato % instead of 0.06 and 3.6".format(sounding[0][3], sounding[0][4]));
			(1..3).do { |cb|
				rows = ~ppRenderBar.(\pad, cb, cb, (), entDeep[cb]);
				req.(rows.every { |r| r[1] === \rest }, "unit_deep pad bar % is not silent: %".format(cb, rows));
			};
			entDeep = walk.(cyc, 1);
			rows = ~ppRenderBar.(\pad, 4, 4, (), entDeep[4]);
			sounding = rows.select { |r| r[1] !== \rest };
			req.((sounding.size == 1) and: { (sounding[0][4] - 1.75).abs < 1e-9 }, "unit_deep pad bar 4 (F, 2 bars) is %, expected one row with legato 1.75".format(sounding));
			entA = walk.(~ppHarmCycle.(\unit_anthem, ~ppLib[\progressions][\unit_anthem]), 1);
			rows = ~ppRenderBar.(\pad, 1, 1, (), entA[1]);
			sounding = rows.select { |r| r[1] !== \rest };
			req.((sounding.size == 1) and: { (sounding[0][4] - 0.75).abs < 1e-9 }, "unit_anthem pad bar 1 (F, 1 bar) is %, expected one row with legato 0.75".format(sounding));
			rows = ~ppRenderBar.(\bass, 0, 0, (), entDeep[0]);
			sounding = rows.select { |r| r[1] !== \rest };
			t0 = 0;
			onsets = rows.collect { |r| var o = t0; t0 = t0 + r[2]; o };
			req.(sounding.collect { |r| r[1] } == [33, 33, 33, 36], "unit_deep bass bar 0 notes are % instead of [33, 33, 33, 36]".format(sounding.collect { |r| r[1] }));
			req.(sounding.every { |r| (r[2] == 0.5) and: { (r[3] - 0.1).abs < 1e-9 } and: { (r[4] - 0.8).abs < 1e-9 } }, "unit_deep bass bar 0 rows are not eighths at amp 0.1 legato 0.8: %".format(sounding));
			req.(rows.collect { |r, i| if (r[1] === \rest) { nil } { onsets[i] } }.reject { |x| x.isNil } == [0.5, 1.5, 2.5, 3.5], "unit_deep bass bar 0 is not on the offbeats");
			rows = ~ppRenderBar.(\bass, 3, 3, (), entDeep[3]);
			sounding = rows.select { |r| r[1] !== \rest };
			req.(sounding.last[1] == 40, "unit_deep bass bar 3 ends on % instead of 40".format(sounding.last[1]));

			// h. classic identity: the rendered rows after the instrument are the frozen generators' rows.
			~ppSel[\melodies] = \classic_lead;
			centry = ~ppHarmClassicEntry.();
			[[\bass, \progressions, \classic], [\pad, \progressions, \classic], [\arp, \melodies, \classic_lead], [\lead, \melodies, \classic_lead]].do { |rl|
				2.do { |b|
					var gen = ~ppLib[rl[1]][rl[2]][rl[0]], got;
					got = ~ppRenderBar.(rl[0], b, b, (), centry);
					direct = gen.value(~ppPlanFor.(b, b, rl[0]), ());
					req.(same.(got.collect { |r| r.copyToEnd(1) }, direct), "classic % bar % differs from the frozen generator's rows: % vs %".format(rl[0], b, got, direct));
				};
			};
			rows = ~ppRenderBar.(\pad, 1, 1, (), centry);
			req.(rows[0][1] == [45, 48, 53], "classic pad on the odd bar is % instead of [45, 48, 53]".format(rows[0][1]));

			// i. ownHarmony: a melody that declares it keeps its own notes, one that does not is mapped.
			ownFn = ~ppLib[\melodies][\classic][\arp];
			ownMod = (desc: "own harmony", arp: ownFn, ownHarmony: true);
			mapMod = (desc: "mapped", arp: ownFn);
			ownMod.put(\name, \unit_own); ownMod.put(\rev, 1);
			mapMod.put(\name, \unit_map); mapMod.put(\rev, 1);
			~ppLib[\melodies].put(\unit_own, ownMod);
			~ppLib[\melodies].put(\unit_map, mapMod);
			~ppSel[\melodies] = \unit_own;
			rows = ~ppRenderBar.(\arp, 1, 1, (), entA[1]);
			req.(rows.collect { |r| r[1] } == Array.fill(16, { |i| [57, 60, 64, 60][i % 4] }), "ownHarmony arp under F is % instead of 57 60 64 60".format(rows.collect { |r| r[1] }));
			~ppSel[\melodies] = \unit_map;
			rows = ~ppRenderBar.(\arp, 1, 1, (), entA[1]);
			req.(rows.collect { |r| r[1] } == Array.fill(16, { |i| [53, 57, 60, 57][i % 4] }), "mapped arp under F is % instead of 53 57 60 57".format(rows.collect { |r| r[1] }));
			~ppSel[\melodies] = \classic;

			// j. the memo is shared, bounded and cycle-aligned.
			~ppHarmReset.value;
			~ppSel[\progressions] = \classic;
			before = ~ppLogCount;
			e1 = ~ppHarmonyFor.(1005, 5);
			e2 = ~ppHarmonyFor.(1005, 5);
			req.(e1 === e2, "two calls for the same bar returned different entries");
			lg = ~ppHarmCycleLog.();
			req.(lg.size > 0 and: { lg[0][\start] == 5 }, "a fresh run did not start where it was first asked (5): %".format(lg));
			req.(~ppHarm[\entries].size == 1, "the memo holds % entries after one bar".format(~ppHarm[\entries].size));
			600.do { |i| ~ppHarmonyFor.(1006 + i, 6 + i) };
			req.(~ppHarm[\entries].size <= 64, "the memo holds % entries after 600 bars, more than 64".format(~ppHarm[\entries].size));
			req.(~ppHarmCycleLog.().size <= 256, "the cycle log holds % records after 600 bars, more than 256".format(~ppHarmCycleLog.().size));
			nm = newLogs.(before).count { |l| l == "PedalPulse: progression classic: Am" };
			req.(nm == 1, "% 'progression classic: Am' lines over 600 bars, expected exactly 1".format(nm));
			~ppHarmonyFor.(3000, 0);
			lg = ~ppHarmCycleLog.();
			req.(lg.size > 0 and: { lg[0][\start] == 0 }, "a call with another base did not start a new run at 0: %".format(lg));

			~ppHarmReset.value;
			~ppSel[\progressions] = \unit_deep;
			nm = List.new;
			16.do { |b| nm.add(~ppHarmonyFor.(b, b)[\chord][\name]) };
			want = ["Am", "Am", "Am", "Am", "F", "F", "G", "G"];
			req.(nm.asArray == (want ++ want), "unit_deep plays % instead of two cycles of Am Am Am Am F F G G".format(nm.asArray));
			req.(~ppHarmCycleLog.().collect { |r| r[\start] } == [0, 8], "unit_deep cycle starts are % instead of [0, 8]".format(~ppHarmCycleLog.().collect { |r| r[\start] }));

			// A pick made mid-cycle waits for the cycle end ...
			~ppHarmReset.value;
			~ppSel[\progressions] = \unit_anthem;
			6.do { |b| ~ppHarmonyFor.(b, b) };
			~ppSel[\progressions] = \classic;
			(6..12).do { |b| ~ppHarmonyFor.(b, b) };
			lg = ~ppHarmCycleLog.();
			req.((lg[0][\stem] == \unit_anthem) and: { lg[0][\start] == 0 } and: { lg[1][\stem] == \unit_anthem } and: { lg[1][\start] == 4 } and: { lg[2][\stem] == \classic } and: { lg[2][\start] == 8 }, "a pick at bar 5 should give unit_anthem at 0 and 4 then classic at 8: %".format(lg));
			req.(lg.copyToEnd(2).every { |r| r[\stem] == \classic }, "cycles after the pick are not all classic: %".format(lg));
			// ... and one made after the cycle's last bar was planned waits one more cycle.
			~ppHarmReset.value;
			~ppSel[\progressions] = \unit_anthem;
			8.do { |b| ~ppHarmonyFor.(b, b) };
			~ppSel[\progressions] = \classic;
			(8..16).do { |b| ~ppHarmonyFor.(b, b) };
			lg = ~ppHarmCycleLog.();
			req.((lg[0][\stem] == \unit_anthem) and: { lg[0][\start] == 0 } and: { lg[1][\start] == 4 } and: { lg[2][\stem] == \unit_anthem } and: { lg[2][\start] == 8 } and: { lg[3][\stem] == \classic } and: { lg[3][\start] == 12 }, "a pick after the last bar was planned should wait: unit_anthem at 0, 4, 8 then classic from 12: %".format(lg));
			req.(lg.copyToEnd(3).every { |r| r[\stem] == \classic }, "cycles after the late pick are not all classic: %".format(lg));

			~ppHarmReset.value;
			~ppSel[\progressions] = \classic;
			~ppSel[\melodies] = \classic;
			checkOk.("harmony units");
		}.value;

		// ---- Shipped progressions (HARM-02, D-04..D-07): the real files on disk ----
		// What every shipped progression must play, pinned by name, cycle length and
		// (where it matters) the span of each chord. A wrong root number in a file is
		// caught here, before the file is frozen by its commit.
		{
			var req, table, descs, mod, cyc;

			req = { |ok, what| if (ok.not) { fail.("shipped progressions", what) } };
			descs = List.new;
			// stem, names, len, spans [name, bars] or nil, last chord pitch classes or nil
			table = [
				[\anthem, "Am F C G", 4, nil, nil],
				[\rocker, "Am G F G", 4, nil, nil],
				[\lift, "Am F G G", 4, [["Am", 1], ["F", 1], ["G", 2]], nil],
				[\return, "Am C G F", 4, nil, nil],
				[\deep, "Am Am F G", 8, [["Am", 4], ["F", 2], ["G", 2]], nil],
				[\melancholy, "Am Em F Dm", 4, nil, nil],
				[\drama, "Am Dm F E", 4, nil, [4, 8, 11]]
			];
			table.do { |row|
				var stem = row[0];
				mod = ~ppLibLoad.(\progressions, stem);
				req.(mod.notNil, "could not load progressions/%".format(stem));
				cyc = ~ppHarmCycle.(stem, mod);
				req.(cyc[\names] == row[1], "% plays % instead of %".format(stem, cyc[\names], row[1]));
				req.(cyc[\len] == row[2], "% has a cycle of % bars instead of %".format(stem, cyc[\len], row[2]));
				req.(cyc[\len] <= 8, "% has a cycle of % bars, more than 8".format(stem, cyc[\len]));
				req.(cyc[\spans][0][\chord][\name] == "Am", "% starts on % instead of Am".format(stem, cyc[\spans][0][\chord][\name]));
				if (row[3].notNil) {
					var got = cyc[\spans].collect { |sp| [sp[\chord][\name], sp[\bars]] };
					req.(got == row[3], "% spans are % instead of %".format(stem, got, row[3]));
				};
				if (row[4].notNil) {
					var last = cyc[\spans].last[\chord];
					req.(last[\pcs] == row[4], "% last chord % has pitch classes % instead of %".format(stem, last[\name], last[\pcs], row[4]));
				};
				descs.add(mod[\desc]);
			};
			mod = ~ppLibLoad.(\progressions, \classic);
			req.(mod.notNil, "could not load progressions/classic");
			descs.add(mod[\desc]);
			req.(descs.size == 8, "expected 8 descriptions, found %".format(descs.size));
			req.(descs.asArray.as(Set).size == 8, "the 8 descriptions are not all different: %".format(descs));
			checkOk.("shipped progressions");
		}.value;

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

			// 9. chord follow <stem> (HARM-01, HARM-03, D-01..D-03, D-11..D-14): for
			// EVERY chord-data progression on disk (every stem except classic and the
			// _ templates, so a new file is covered automatically), bass, arp, pad and
			// lead sit on the same chord every bar through two cycles, a tempo change
			// and a restart. The real library folder is read here, before any
			// temporary root is set.
			{
				var stems;
				stems = listStems.(~ppLibRoot +/+ "progressions").reject { |n| (n == "classic") or: { n[0] == $_ } };
				if (stems.isEmpty) {
					fail.("chord follow", "no chord-data progression on disk to check");
				};
				stems.do { |stemStr|
					var stem = stemStr.asSymbol, name = "chord follow " ++ stemStr;
					var cyc, len, nBars, rc, rc2, rws, before, padRows, pitched, fresh, got, want, perBar, mod, spanAt, first, cname;
					sendSel.('/pp/progression', stem);
					sendSel.('/pp/melody', 'classic_lead');
					if (waitFor.({ (~ppSel[\progressions] == stem) and: { ~ppSel[\melodies] == \classic_lead } }, 3).not) {
						fail.(name, "the selections never became % and classic_lead: %".format(stem, ~ppSel));
					};
					mod = ~ppLib[\progressions][stem];
					if (mod.isNil or: { mod[\chords].isNil }) {
						// A generator-only progression has no chords to follow: the static tier checks it.
						"CHECK SKIP: % (no chord data)".format(name).postln;
					} {
						cyc = ~ppHarmCycle.(stem, mod);
						len = cyc[\len];
						nBars = (2 * len) + 4;
						spanAt = { |cb|
							cyc[\spans].detect { |sp| (cb >= sp[\start]) and: { cb < (sp[\start] + sp[\bars]) } }
						};
						before = ~ppLogCount;
						rc = recordBars.(nBars, 16, { |recClock, startBeat|
							while { recClock.beats < (startBeat + 20) } { 0.02.wait };  // bar 5
							recClock.tempo = 23;
							while { recClock.beats < (startBeat + 36) } { 0.02.wait };  // bar 9
							recClock.tempo = 16;
						});
						rws = rc[\rows];
						harmonyCheck.(name, rws, [\ppBass, \ppArp, \ppPad, \ppLead]);
						nBars.do { |b|
							var e = ~ppHarmonyEntry.(b), sp, arpRows, bassRows, padB, chord, c0;
							if (e.isNil or: { e[\progression] != stem }) {
								fail.(name, "bar % is not %: %".format(b, stem, e !? { e[\progression] }));
							};
							sp = spanAt.(b % len);
							if (e[\chord][\name] != sp[\chord][\name]) {
								fail.(name, "bar % plays chord %, the file says %".format(b, e[\chord][\name], sp[\chord][\name]));
							};
							chord = e[\chord];
							perBar = (ppBass: 4, ppArp: 16, ppLead: 16);
							perBar.keysValuesDo { |layer, n|
								var got2 = rws.count { |r| (r[0] == layer) and: { barOf.(r[1]) == b } };
								if (got2 != n) { fail.(name, "% bar % holds % rows, expected %".format(layer, b, got2, n)) };
							};
							// The arp of every bar is the classic figure mapped onto that bar's chord.
							arpRows = rws.select { |r| (r[0] == \ppArp) and: { barOf.(r[1]) == b } };
							want = Array.fill(16, { |i| ~ppFollowNote.([57, 60, 64, 60].wrapAt(i), chord) });
							if (arpRows.collect { |r| r[3] } != want) {
								fail.(name, "arp bar % under % is % instead of %".format(b, chord[\name], arpRows.collect { |r| r[3] }, want));
							};
							// The bass: the chord's root three times, then the pickup or the third.
							bassRows = rws.select { |r| (r[0] == \ppBass) and: { barOf.(r[1]) == b } };
							c0 = ~ppBassRoot.(chord);
							want = [c0, c0, c0, if (e[\changesNext] == true) { ~ppBassPickup.(chord, e[\nextChord]) } { c0 + chord[\intervals][1] }];
							if (bassRows.collect { |r| r[3] } != want) {
								fail.(name, "bass bar % under % is % instead of %".format(b, chord[\name], bassRows.collect { |r| r[3] }, want));
							};
							// The pad sounds once on a chord's first bar, in the voicing the entry chose,
							// and never on a later bar of the same chord.
							padB = rws.select { |r| (r[0] == \ppPad) and: { barOf.(r[1]) == b } };
							if (e[\chordBar] == 0) {
								if (padB.size != 1) {
									fail.(name, "pad bar % (a chord start) holds % rows, expected 1".format(b, padB.size));
								};
								first = padB[0];
								if (first[3] != e[\voicing]) {
									fail.(name, "pad bar % plays % instead of the entry's voicing %".format(b, first[3], e[\voicing]));
								};
								if ((first[3].first < ~ppPadWindow[0]) or: { first[3].last > ~ppPadWindow[1] }) {
									fail.(name, "pad bar % voicing % leaves the window %".format(b, first[3], ~ppPadWindow));
								};
								want = 4 * min(0.9 * e[\chordBars], e[\chordBars] - 0.25);
								if ((first[7] - want).abs > 1e-6) {
									fail.(name, "pad bar % sustains % beats, expected %".format(b, first[7], want));
								};
								if ((first[1] + first[7]) > (((b + e[\chordBars]) * 4) - 1 + 1e-6)) {
									fail.(name, "pad bar % closes its gate at beat % but the next chord starts at beat % (less than a beat)".format(b, first[1] + first[7], (b + e[\chordBars]) * 4));
								};
							} {
								if (padB.size != 0) {
									fail.(name, "pad bar % (inside a chord) holds % rows, expected none".format(b, padB.size));
								};
							};
						};
						// Anthem's literal bass pickups: Am to F 40, F to C 36, C to G 43, G to Am 35.
						if (stemStr == "anthem") {
							rws.select { |r| (r[0] == \ppBass) and: { (r[1] % 4) > 3.4 } }.do { |r|
								var w = [40, 36, 43, 35][barOf.(r[1]) % 4];
								if (r[3] != w) { fail.(name, "bass pickup in bar % is %, expected %".format(barOf.(r[1]), r[3], w)) };
							};
						};
						// The lead is the arp 12 semitones up.
						leadDiffs.(rws).do { |d|
							if (d[1] != 12) { fail.(name, "lead bar % is % semitones above the arp, expected 12".format(d[0], d[1])) };
						};
						// The post window says what plays.
						fresh = newLogs.(before);
						cname = "PedalPulse: progression %: %".format(stem, cyc[\names]);
						if (fresh.any { |l| l == cname }.not) {
							fail.(name, "no '%' line in %".format(cname, fresh));
						};

						// A restart begins at the first chord and replays the same pitched rows.
						rc2 = recordBars.(len, 32);
						got = ~ppHarmonyEntry.(0);
						if (got.isNil or: { got[\progression] != stem } or: { got[\cycleBar] != 0 } or: { got[\chord][\name] != cyc[\spans][0][\chord][\name] }) {
							fail.(name, "a restart did not begin at %, cycle bar 0: %".format(cyc[\spans][0][\chord][\name], got !? { [got[\progression], got[\cycleBar], got[\chord][\name]] }));
						};
						pitched = { |r|
							r.select { |x| [\ppBass, \ppArp, \ppPad, \ppLead].includes(x[0]) and: { x[1] < ((len * 4) - 1e-6) } }.collect { |x| [x[0], x[1], x[3], x[4], x[8], x[6]] }
						};
						got = pitched.(rc2[\rows]);
						want = pitched.(rws);
						if (same.(got, want).not) {
							fail.(name, "the restart did not replay the first % bars: % rows vs %".format(len, got.size, want.size));
						};
						checkOk.(name);
					};
				};

				sendSel.('/pp/progression', 'classic');
				sendSel.('/pp/melody', 'classic');
				if (waitFor.({ (~ppSel[\progressions] == \classic) and: { ~ppSel[\melodies] == \classic } }, 3).not) {
					fail.("chord follow", "selections did not return to classic: %".format(~ppSel));
				};
			}.value;

			// 10. named progression switches at the cycle end (HARM-04): a pick in the
			// middle of a cycle waits for the cycle boundary and then stays.
			{
				var name = "named progression switches at the cycle end";
				var rc, rws, before, names, cyc, fresh, s1, s2, lines, i;
				names = ["Am", "F", "C", "G"];
				sendSel.('/pp/progression', 'anthem');
				sendSel.('/pp/melody', 'classic_lead');
				if (waitFor.({ (~ppSel[\progressions] == \anthem) and: { ~ppSel[\melodies] == \classic_lead } }, 3).not) {
					fail.(name, "the selections never became anthem and classic_lead: %".format(~ppSel));
				};
				before = ~ppLogCount;
				rc = recordBars.(20, 16, { |recClock, startBeat|
					while { recClock.beats < (startBeat + 22) } { 0.02.wait };  // bar 5, inside the second anthem cycle
					sendSel.('/pp/progression', 'classic');
					if (waitFor.({ ~ppSel[\progressions] == \classic }, 3).not) {
						fail.(name, "~ppSel[\\progressions] never became classic");
					};
					while { recClock.beats < (startBeat + 54) } { 0.02.wait };  // bar 13
					sendSel.('/pp/progression', 'anthem');
					if (waitFor.({ ~ppSel[\progressions] == \anthem }, 3).not) {
						fail.(name, "~ppSel[\\progressions] never became anthem again");
					};
				});
				rws = rc[\rows];
				cyc = ~ppHarmCycleLog.();
				// Contiguous cycles from bar 0.
				cyc.do { |c, k|
					if (k == 0) {
						if (c[\start] != 0) { fail.(name, "the first cycle starts at %, not 0: %".format(c[\start], cyc)) };
					} {
						if (c[\start] != (cyc[k - 1][\start] + cyc[k - 1][\len])) {
							fail.(name, "cycle % starts at %, not at the end of the previous one: %".format(k, c[\start], cyc));
						};
					};
				};
				if ((cyc[0][\stem] != \anthem) or: { cyc[1][\stem] != \anthem } or: { cyc[1][\start] != 4 }) {
					fail.(name, "the first two cycles are not anthem at 0 and 4: %".format(cyc));
				};
				i = cyc.detectIndex { |c| c[\stem] == \classic };
				if (i.isNil) { fail.(name, "no classic cycle after the pick: %".format(cyc)) };
				s1 = cyc[i][\start];
				if ((s1 != 8) and: { s1 != 12 }) {
					fail.(name, "the classic cycle starts at bar %, not on a cycle boundary (8 or 12): %".format(s1, cyc));
				};
				i = cyc.detectIndex { |c| (c[\start] > s1) and: { c[\stem] == \anthem } };
				if (i.isNil) { fail.(name, "anthem never came back after the second pick: %".format(cyc)) };
				s2 = cyc[i][\start];
				if ((s2 < 14) or: { s2 > 16 }) {
					fail.(name, "anthem came back at bar %, expected 14 to 16: %".format(s2, cyc));
				};
				cyc.do { |c|
					if ((c[\start] >= s1) and: { c[\start] < s2 } and: { c[\stem] != \classic }) {
						fail.(name, "cycle at bar % is % between the picks, expected classic: %".format(c[\start], c[\stem], cyc));
					};
					if ((c[\start] >= s2) and: { c[\stem] != \anthem }) {
						fail.(name, "cycle at bar % is % after the second pick, expected anthem (it stays): %".format(c[\start], c[\stem], cyc));
					};
					if ((c[\start] >= s2) and: { ((c[\start] - s2) % 4) != 0 }) {
						fail.(name, "the anthem cycle at bar % is not S2 + 4k (S2 = %): %".format(c[\start], s2, cyc));
					};
				};
				20.do { |b|
					var e = ~ppHarmonyEntry.(b), wantStem, wantChord;
					if (e.isNil) { fail.(name, "no harmony entry for bar %".format(b)) };
					if (b < s1) {
						wantStem = \anthem; wantChord = names[b % 4];
					} {
						if (b < s2) {
							wantStem = \classic; wantChord = "Am";
						} {
							wantStem = \anthem; wantChord = names[(b - s2) % 4];
						};
					};
					if ((e[\progression] != wantStem) or: { e[\chord][\name] != wantChord }) {
						fail.(name, "bar % plays % %, expected % %".format(b, e[\progression], e[\chord][\name], wantStem, wantChord));
					};
				};
				harmonyCheck.(name, rws, [\ppBass, \ppArp, \ppPad, \ppLead]);
				fresh = newLogs.(before);
				lines = fresh.select { |l| l.beginsWith("PedalPulse: progression ") };
				if (lines != ["PedalPulse: progression anthem: Am F C G", "PedalPulse: progression classic: Am", "PedalPulse: progression anthem: Am F C G"]) {
					fail.(name, "the progression lines are %".format(lines));
				};
				if (fresh.any { |l| l.find("switches at the end of the current progression cycle").notNil }.not) {
					fail.(name, "no 'switches at the end of the current progression cycle' line in %".format(fresh));
				};
				sendSel.('/pp/progression', 'classic');
				sendSel.('/pp/melody', 'classic');
				if (waitFor.({ (~ppSel[\progressions] == \classic) and: { ~ppSel[\melodies] == \classic } }, 3).not) {
					fail.(name, "selections did not return to classic: %".format(~ppSel));
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
