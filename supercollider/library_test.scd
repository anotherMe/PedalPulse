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

// Watchdog first, in case anything below hangs. 420 s: the Phase 6 harmony tiers
// record every chord-data progression on disk (two cycles plus a restart each),
// and since Phase 7 the palette Auto tier adds long recordings (the check took
// 2:49 against the old 300 s limit after Wave 3).
SystemClock.sched(420, {
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
	var stem, ok, nfail, path, dir, stems, sel, pre, names, ls, defsRes;

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
				// Palette defs only ever run through the engine's own guard (WR-02).
				defsRes = ~ppPaletteDefs.(pre, \classic, nil);
				defsRes[\reasons].do { |r| add.("palettes/classic %".format(r)) };
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
							defsRes = ~ppPaletteDefs.(mod, stem, ~ppLib[cat][stem]);
							defsRes[\reasons].do { |r| add.("% %".format(label, r)) };
							if (defsRes[\reasons].size > 0) { defsRes[\undo].value };
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
								// D-02: the bass under the classic progression (the one every Start
								// plays first). The classic palette keeps the progression's own
								// frozen bass; every other palette plays its bassStyle on the
								// bar's chord (A minor here). Rows are compared without the
								// instrument column.
								if (~ppLib[\progressions][\classic].notNil) {
									ls = ();
									4.do { |b|
										var rows = ~ppRenderBar.(\bass, b, b, ls);
										var entry = ~ppHarmonyEntry.(b);
										var plan = ~ppPlanFor.(b, b, \bass, entry);
										var want, styleFn;
										if (stem == \classic) {
											want = ~ppLib[\progressions][\classic][\bass].value(plan, ());
										} {
											styleFn = if (~ppBassStyles.notNil) { ~ppBassStyles[mod[\bassStyle] ? \eighths] } { nil };
											want = (styleFn ? ~ppDefaultBass).value(plan, ());
										};
										if (same.(rows.collect { |r| r.copyToEnd(1) }, want).not) {
											if (stem == \classic) {
												add.("% changes the classic bass (bar %)".format(label, b));
											} {
												add.("% bass under the classic progression does not follow its bassStyle (bar %)".format(label, b));
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
	var brokenCount = 0;  // ERROR lines for the broken progression fixture, summed over the Auto checks

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
		// WR-02: a palette whose role uses another palette's voice (the stem is foreign_role).
		wrs.("palettes/foreign_role.scd", "(\ndesc: \"uses another palette's voice\",\ndefs: {\n\tSynthDef(\\pp_other_arp, { |out = 0, amp = 0.1, freq = 440, gate = 1| var env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.5, 0.2), gate, doneAction: 2); Out.ar(out, (SinOsc.ar(freq) * env * amp) ! 2) }).add;\n},\nroles: (arp: (instrument: \\pp_other_arp))\n)\n");
		// D-02: a palette's bassStyle must be one of the known style Symbols; a typo or
		// a String refuses the file (T-07-07). Each fixture has an own voice for one role.
		wrs.("palettes/bad_style.scd", "(\ndesc: \"unknown bass style\",\ndefs: {\n\tSynthDef(\\pp_bad_style_arp, { |out = 0, amp = 0.1, freq = 440, gate = 1| var env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.5, 0.2), gate, doneAction: 2); Out.ar(out, (SinOsc.ar(freq) * env * amp) ! 2) }).add;\n},\nbassStyle: \\waltz,\nroles: (arp: (instrument: \\pp_bad_style_arp))\n)\n");
		wrs.("palettes/string_style.scd", "(\ndesc: \"bass style given as a String\",\ndefs: {\n\tSynthDef(\\pp_string_style_arp, { |out = 0, amp = 0.1, freq = 440, gate = 1| var env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.5, 0.2), gate, doneAction: 2); Out.ar(out, (SinOsc.ar(freq) * env * amp) ! 2) }).add;\n},\nbassStyle: \"sixteenths\",\nroles: (arp: (instrument: \\pp_string_style_arp))\n)\n");

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
		expectFailure.("a palette using another palette's voice", "does not start with pp_foreign_role_");
		// Each bad style fixture must fail on its own file, with the list of valid styles.
		["bad_style", "string_style"].do { |fx|
			if (bad.any { |f| f.beginsWith("palettes/" ++ fx) and: { f.find("bassStyle is not one of: eighths, octave, sixteenths").notNil } }.not) {
				fail.("static check catches bad files", "no failure for palettes/% (looked for \"bassStyle is not one of: eighths, octave, sixteenths\"), got: %".format(fx, bad));
			};
		};
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

		// ---- Bass styles follow the chord (PAL-01, D-02): server-free ----
		// Every bass style a palette can name keeps the Phase 6 chord rules: each
		// sounding note is a tone of the bar's chord, the first sounding note is the
		// chord's root, and the last sounding note is the pickup toward the next chord
		// when the chord changes at the next bar and the chord's third otherwise. The
		// eighths style is the core default bass itself, and on classic's implicit A
		// minor it is exactly the classic progression's frozen bass.
		{
			var req, tbl, chordNamed, pickups, planFor, sounding, mod, cEntry, cPlan, want, got, savedLib;

			req = { |ok, what| if (ok.not) { fail.("bass styles follow the chord", what) } };
			req.(~ppBassStyles.notNil, "~ppBassStyles does not exist");
			req.(~ppBassStyleNames.notNil, "~ppBassStyleNames does not exist");
			req.(~ppBassStyleNames.asArray.sort == [\eighths, \octave, \sixteenths], "the style names are % instead of [eighths, octave, sixteenths]".format(~ppBassStyleNames));
			req.(~ppBassStyles.keys.asArray.sort == ~ppBassStyleNames.asArray.sort, "~ppBassStyles has the styles % instead of the names %".format(~ppBassStyles.keys.asArray.sort, ~ppBassStyleNames));
			req.(~ppBassStyles[\eighths] === ~ppDefaultBass, "the eighths style is not the core default bass");
			req.(~ppBassStyleFor.(nil) === ~ppDefaultBass, "an unknown palette stem does not give the eighths style");

			tbl = [["Am", 0, \min], ["F", 8, \maj], ["C", 3, \maj], ["G", 10, \maj], ["Dm", 5, \min], ["Em", 7, \min], ["E", 7, \maj]];
			chordNamed = { |n|
				var t = tbl.detect { |x| x[0] == n };
				~ppChordExpand.((root: t[1], quality: t[2]))
			};
			// current, next, the pickup note on the last slot (the same table as harmony units)
			pickups = [
				["Am", "F", 40], ["F", "C", 36], ["C", "G", 43], ["G", "Am", 35], ["Am", "G", 45],
				["G", "F", 43], ["F", "G", 45], ["Am", "C", 36], ["F", "Am", 33], ["Am", "Em", 40],
				["Em", "F", 40], ["F", "Dm", 36], ["Dm", "Am", 33], ["Am", "Dm", 36], ["Dm", "F", 41],
				["F", "E", 41], ["E", "Am", 32]
			];
			planFor = { |chord, next, changes|
				(chord: chord, nextChord: next, changesNext: changes, chordBar: 0, chordBars: 1, voicing: ~ppPadHome)
			};
			sounding = { |rows| rows.select { |r| r[0] !== \rest } };

			~ppBassStyleNames.do { |style|
				var fn = ~ppBassStyles[style];
				req.(fn.isFunction, "style % is not a Function".format(style));
				// changesNext true: the table's pickups.
				pickups.do { |pk|
					var chord = chordNamed.(pk[0]), rows, snd, why, where;
					where = "% % to %".format(style, pk[0], pk[1]);
					rows = fn.value(planFor.(chord, chordNamed.(pk[1]), true), ());
					why = ~ppRowsValid.(rows);
					req.(why.isNil, "% rows are refused: %".format(where, why));
					snd = sounding.(rows);
					req.(snd.size > 0, "% sounds nothing".format(where));
					snd.do { |r|
						req.(chord[\pcs].includes(r[0].round.asInteger % 12), "% plays note % outside the chord".format(where, r[0]));
					};
					req.(snd.first[0] == ~ppBassRoot.(chord), "% starts on % instead of the root %".format(where, snd.first[0], ~ppBassRoot.(chord)));
					req.(snd.last[0] == pk[2], "% ends on % instead of the pickup %".format(where, snd.last[0], pk[2]));
				};
				// changesNext false: the chord's third last.
				tbl.do { |t|
					var chord = chordNamed.(t[0]), rows, snd, why, where;
					where = "% on % (no change)".format(style, t[0]);
					rows = fn.value(planFor.(chord, chord, false), ());
					why = ~ppRowsValid.(rows);
					req.(why.isNil, "% rows are refused: %".format(where, why));
					snd = sounding.(rows);
					snd.do { |r|
						req.(chord[\pcs].includes(r[0].round.asInteger % 12), "% plays note % outside the chord".format(where, r[0]));
					};
					req.(snd.first[0] == ~ppBassRoot.(chord), "% starts on % instead of the root".format(where, snd.first[0]));
					req.(snd.last[0] == (~ppBassRoot.(chord) + chord[\intervals][1]), "% ends on % instead of the third %".format(where, snd.last[0], ~ppBassRoot.(chord) + chord[\intervals][1]));
				};
			};

			// The shapes. Am to F: root 33, pickup 40; Am staying: root 33, third 36.
			got = ~ppBassStyles[\sixteenths].value(planFor.(chordNamed.("Am"), chordNamed.("F"), true), ());
			req.(got.size == 16, "sixteenths returns % rows instead of 16".format(got.size));
			req.(got.every { |r| (r[1] == 0.25) and: { (r[2] - 0.1).abs < 1e-9 } and: { (r[3] - 0.6).abs < 1e-9 } }, "sixteenths rows are not dur 0.25, amp 0.1, legato 0.6: %".format(got));
			req.([0, 4, 8, 12].every { |i| got[i][0] === \rest }, "sixteenths does not rest on each beat's first sixteenth");
			req.(got.count { |r| r[0] !== \rest } == 12, "sixteenths sounds % notes instead of 12".format(got.count { |r| r[0] !== \rest }));
			req.(got.collect { |r, i| if (r[0] === \rest) { i } { nil } }.reject { |x| x.isNil } == [0, 4, 8, 12], "sixteenths rests at the wrong rows");
			got = ~ppBassStyles[\octave].value(planFor.(chordNamed.("Am"), chordNamed.("F"), true), ());
			req.(got.size == 8, "octave returns % rows instead of 8".format(got.size));
			req.(got.every { |r| (r[1] == 0.5) and: { (r[2] - 0.1).abs < 1e-9 } and: { (r[3] - 0.8).abs < 1e-9 } }, "octave rows are not dur 0.5, amp 0.1, legato 0.8: %".format(got));
			req.([0, 2, 4, 6].every { |i| got[i][0] === \rest }, "octave does not rest on the downbeats");
			req.([1, 3, 5, 7].collect { |i| got[i][0] } == [33, 45, 33, 40], "octave plays % instead of [33, 45, 33, 40]".format([1, 3, 5, 7].collect { |i| got[i][0] }));
			got = ~ppBassStyles[\sixteenths].value(planFor.(chordNamed.("Am"), chordNamed.("Am"), false), ());
			req.(sounding.(got).collect { |r| r[0] }.as(Set) == Set[33, 36], "sixteenths on a staying Am plays % instead of 33 and 36".format(sounding.(got).collect { |r| r[0] }.as(Set)));

			// Eighths on classic's implicit chord is exactly the classic progression's frozen bass.
			mod = ~ppLibLoad.(\progressions, \classic);
			req.(mod.notNil, "could not load progressions/classic");
			cEntry = ~ppHarmClassicEntry.();
			cPlan = ~ppPlanFor.(0, 0, \bass, cEntry);
			want = mod[\bass].value(cPlan, ());
			got = ~ppBassStyles[\eighths].value(cPlan, ());
			req.(same.(got, want), "eighths on classic's A minor is % instead of the classic progression's own bass %".format(got, want));
			req.(same.(got, [[\rest, 0.5, 0.1, 0.8], [33, 0.5, 0.1, 0.8], [\rest, 0.5, 0.1, 0.8], [33, 0.5, 0.1, 0.8], [\rest, 0.5, 0.1, 0.8], [33, 0.5, 0.1, 0.8], [\rest, 0.5, 0.1, 0.8], [36, 0.5, 0.1, 0.8]]), "eighths on classic's A minor is not v1's rows: %".format(got));

			// ~ppBassStyleFor: a registered palette's style, else eighths.
			savedLib = ~ppLib;
			~ppLib = (progressions: (), melodies: (), palettes: ());
			~ppLib[\palettes].put(\unit_roll, (desc: "roll", bassStyle: \sixteenths, name: \unit_roll));
			~ppLib[\palettes].put(\unit_none, (desc: "none", name: \unit_none));
			req.(~ppBassStyleFor.(\unit_roll) === ~ppBassStyles[\sixteenths], "a palette with bassStyle sixteenths does not give that style");
			req.(~ppBassStyleFor.(\unit_none) === ~ppDefaultBass, "a palette without bassStyle does not give the eighths style");
			req.(~ppBassStyleFor.(\unit_missing) === ~ppDefaultBass, "an unregistered palette does not give the eighths style");
			~ppLib = savedLib;
			checkOk.("bass styles follow the chord");
		}.value;

		// ---- Shipped rows within bounds (WR-01, D-16): server-free ----
		// Every row the core's own pad and bass generators can return, for each
		// chord length from 1 to 8 bars (the pad legato reaches 7.2 on an 8-bar
		// chord), must pass the new upper bounds of ~ppRowsValid. The reviewer's
		// suggested legato cap of 4 would have refused a legal progression's pad.
		{
			var req, mod, cyc, chord, nextChord, plan, rows, why;

			req = { |ok, what| if (ok.not) { fail.("shipped rows within bounds", what) } };
			mod = ~ppLibLoad.(\progressions, \anthem);
			req.(mod.notNil, "could not load progressions/anthem");
			cyc = ~ppHarmCycle.(\anthem, mod);
			chord = cyc[\spans][0][\chord];
			nextChord = cyc[\spans][1][\chord];
			(1..8).do { |bars|
				plan = (chord: chord, nextChord: nextChord, changesNext: true, chordBar: 0, chordBars: bars, voicing: ~ppPadHome);
				rows = ~ppDefaultPad.(plan, ());
				why = ~ppRowsValid.(rows);
				req.(why.isNil, "the default pad on a % bar chord is refused: %".format(bars, why));
			};
			plan = (chord: chord, nextChord: nextChord, changesNext: true, chordBar: 1, chordBars: 2, voicing: ~ppPadHome);
			why = ~ppRowsValid.(~ppDefaultPad.(plan, ()));
			req.(why.isNil, "the default pad's silent bar is refused: %".format(why));
			[true, false].do { |changes|
				plan = (chord: chord, nextChord: nextChord, changesNext: changes, chordBar: 0, chordBars: 1, voicing: ~ppPadHome);
				why = ~ppRowsValid.(~ppDefaultBass.(plan, ()));
				req.(why.isNil, "the default bass (changesNext %) is refused: %".format(changes, why));
			};
			checkOk.("shipped rows within bounds");
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

		// ---- Shipped palettes (PAL-01, D-03, D-04): the real files on disk ----
		// What every shipped palette must be, pinned by name: its own bass, arp,
		// pad and lead voices (four different ones, the lead its own sound and not
		// the arp's), exactly the drum voices it lists and none other (a drum role
		// left out falls back to classic's), and its bass style. Wrong voice names
		// are caught here, before the file is frozen by its commit. Plans 03 and 05
		// add rows. Row: [stem, bassStyle or nil, the palette's own drum roles].
		{
			var req, table, descs, mod, classicMod;

			req = { |ok, what| if (ok.not) { fail.("shipped palettes", what) } };
			descs = List.new;
			table = [
				[\supersaw, nil, []],
				[\acid, \sixteenths, []],
				[\dark, \sixteenths, [\kick]]
			];
			classicMod = ~ppLibLoad.(\palettes, \classic);
			req.(classicMod.notNil, "could not load palettes/classic");
			descs.add(classicMod[\desc]);
			table.do { |row|
				var stem = row[0], prefix = "pp_%_".format(stem), insts;
				mod = ~ppLibLoad.(\palettes, stem);
				req.(mod.notNil, "could not load palettes/%".format(stem));
				insts = ~ppPitchedRoles.collect { |role|
					var entry = mod[\roles][role];
					req.(entry.notNil, "% has no % voice".format(stem, role));
					req.(entry[\instrument].asString.beginsWith(prefix), "% % voice % does not start with %".format(stem, role, entry[\instrument], prefix));
					entry[\instrument]
				};
				req.(insts.as(Set).size == insts.size, "% bass, arp, pad and lead voices are not four different ones: %".format(stem, insts));
				~ppDrumRoles.do { |role|
					var entry = mod[\roles][role];
					if (row[2].includes(role)) {
						req.(entry.notNil, "% should have its own % voice".format(stem, role));
						req.(entry[\instrument].asString.beginsWith(prefix), "% % voice % does not start with %".format(stem, role, entry[\instrument], prefix));
					} {
						req.(entry.isNil, "% names a % voice but the table says it plays classic's".format(stem, role));
					};
				};
				req.(mod[\bassStyle] == row[1], "% bassStyle is % instead of %".format(stem, mod[\bassStyle], row[1]));
				descs.add(mod[\desc]);
			};
			req.(descs.size == (table.size + 1), "expected % descriptions, found %".format(table.size + 1, descs.size));
			req.(descs.asArray.as(Set).size == descs.size, "the % descriptions are not all different: %".format(descs.size, descs));
			checkOk.("shipped palettes");
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
				var mod, pairs = List.new, results, bad = List.new, defsRes;
				mod = ~ppLibLoad.(\palettes, stemStr.asSymbol);
				if (mod.isNil) { fail.("voices %".format(stemStr), "the palette did not load") };
				if (mod[\defs].isFunction) {
					// The same guard the engine uses (WR-02): a palette's defs only
					// define voices under its own name.
					defsRes = ~ppPaletteDefs.(mod, stemStr.asSymbol, nil);
					if (defsRes[\reasons].size > 0) {
						fail.("voices %".format(stemStr), "defs refused: %".format(defsRes[\reasons].join("; ")));
					};
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

			// 4. auto plays classic (RESEARCH open question 3). Melody and progression
			// only: since Phase 7 (D-08) palette Auto starts on a random palette, so it
			// no longer plays classic; the palette Auto checks cover it.
			{
				var name = "auto plays classic";
				sendSel.('/pp/melody', 'auto');
				sendSel.('/pp/progression', 'auto');
				if (waitFor.({ (~ppSel[\melodies] == \auto) and: { ~ppSel[\progressions] == \auto } }, 2).not) {
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

			// 10b. palette bass styles (PAL-01, D-02): the palette decides the bass
			// rhythm under EVERY progression, the classic progression included (every
			// Start plays it first). One table of rows [stem, style, sounding bass notes
			// per bar]; Plan 05 adds rows. Pass 1 plays the rows under anthem, pass 2
			// under the classic progression (the bar's chord is A minor every bar, so the
			// notes are A1 roots and C2 last). In both: the palette's own bass voice, the
			// expected number of sounding notes per bar, and every bar's notes, onsets,
			// durs, legatos and amps equal what the style function writes for that bar's
			// entry. Under classic an eighths row also equals the classic progression's
			// own bass rows (v1's rhythm and notes).
			{
				var table, runPass, expectOf, near;
				table = [
					[\supersaw, \eighths, 4],
					[\acid, \sixteenths, 12],
					[\dark, \sixteenths, 12]
				];
				near = { |a, b| (a - b).abs < 1e-6 };
				// genRows -> [onset, note, dur, legato, amp] for every sounding row.
				expectOf = { |genRows|
					var t = 0, out = List.new;
					genRows.do { |g|
						if (g[0] !== \rest) { out.add([t, g[0], g[1], g[3], g[2]]) };
						t = t + g[1];
					};
					out.asArray
				};
				runPass = { |prog, name|
					var nBars = 8;
					sendSel.('/pp/progression', prog);
					if (waitFor.({ ~ppSel[\progressions] == prog }, 3).not) {
						fail.(name, "~ppSel[\\progressions] never became %".format(prog));
					};
					table.do { |row|
						var stem = row[0], style = row[1], count = row[2], rc, rws, inst, label;
						label = "% % (%)".format(name, stem, style);
						sendSel.('/pp/palette', stem);
						if (waitFor.({ ~ppSel[\palettes] == stem }, 5).not) {
							fail.(label, "~ppSel[\\palettes] never became %: %".format(stem, ~ppSel));
						};
						rc = recordBars.(nBars, 16);
						rws = rc[\rows];
						inst = "pp_%_bass".format(stem).asSymbol;
						rws.select { |r| r[0] == \ppBass }.do { |r|
							if (r[2] != inst) {
								fail.(label, "a bass row in bar % uses % instead of %".format(barOf.(r[1]), r[2], inst));
							};
						};
						nBars.do { |b|
							var e = ~ppHarmonyEntry.(b), plan, genRows, want, got, classicRows;
							if (e.isNil) { fail.(label, "no harmony entry for bar %".format(b)) };
							if (e[\palette] != stem) { fail.(label, "bar % plays palette % instead of %".format(b, e[\palette], stem)) };
							if (e[\progression] != prog) { fail.(label, "bar % plays progression % instead of %".format(b, e[\progression], prog)) };
							plan = ~ppPlanFor.(b, b, \bass, e);
							genRows = ~ppBassStyles[style].value(plan, ());
							want = expectOf.(genRows);
							got = rws.select { |r| (r[0] == \ppBass) and: { barOf.(r[1]) == b } }.collect { |r| [r[1] - (4 * b), r[3], r[4], r[6], r[8]] };
							if (got.size != count) {
								fail.(label, "bar % holds % sounding bass notes, expected %".format(b, got.size, count));
							};
							if ((got.size != want.size) or: { got.every { |g, i| want[i].every { |x, k| near.(g[k], x) } }.not }) {
								fail.(label, "bar % bass is % instead of the style's %".format(b, got, want));
							};
							// Under the classic progression the entry's chord is A minor every bar:
							// A1 roots and C2 last, and an eighths row is v1's bass exactly.
							if (prog == \classic) {
								if (e[\chord][\name] != "Am") { fail.(label, "bar % chord is % instead of Am".format(b, e[\chord][\name])) };
								if (got.last[1] != 36) { fail.(label, "bar % ends on % instead of C2 (36)".format(b, got.last[1])) };
								if (got.every { |g, i| (i == (got.size - 1)) or: { g[1] == 33 } }.not) {
									fail.(label, "bar % has a bass note that is not A1 (33): %".format(b, got));
								};
								if (style == \eighths) {
									classicRows = expectOf.(~ppLib[\progressions][\classic][\bass].value(plan, ()));
									if ((classicRows.size != got.size) or: { got.every { |g, i| classicRows[i].every { |x, k| near.(g[k], x) } }.not }) {
										fail.(label, "bar % bass is % instead of the classic progression's own %".format(b, got, classicRows));
									};
								};
							};
						};
						harmonyCheck.(label, rws, [\ppBass, \ppArp, \ppPad, \ppLead]);
						if (stem == \dark) {
							rws.select { |r| r[0] == \ppKick }.do { |r|
								if (r[2] != \pp_dark_kick) {
									fail.(label, "a kick row in bar % uses % instead of pp_dark_kick".format(barOf.(r[1]), r[2]));
								};
							};
						};
					};
				};

				sendSel.('/pp/melody', 'classic_lead');
				if (waitFor.({ ~ppSel[\melodies] == \classic_lead }, 3).not) {
					fail.("palette bass styles", "~ppSel[\\melodies] never became classic_lead");
				};
				runPass.(\anthem, "palette bass styles under anthem");
				checkOk.("palette bass styles under anthem");
				runPass.(\classic, "palette bass styles under classic");
				checkOk.("palette bass styles under classic");

				sendSel.('/pp/palette', 'classic');
				sendSel.('/pp/progression', 'classic');
				sendSel.('/pp/melody', 'classic');
				if (waitFor.({ (~ppSel[\palettes] == \classic) and: { ~ppSel[\progressions] == \classic } and: { ~ppSel[\melodies] == \classic } }, 5).not) {
					fail.("palette bass styles", "selections did not return to classic: %".format(~ppSel));
				};
			}.value;

			// 11. auto rotates progressions (HARM-04, HARM-02, D-08 to D-11): with a
			// short hold, Auto starts on classic, then changes progression by itself,
			// only at cycle ends, never back to one of the last two it played.
			{
				var name = "auto rotates progressions";
				var savedHold, savedSeed, rc, rws, cyc, runs, before, fresh, valid, lines;
				savedHold = ~ppAutoHoldBars;
				savedSeed = ~ppAutoSeed;
				~ppAutoHoldBars = [4, 8];
				~ppAutoSeed = 11;
				valid = listStems.(~ppLibRoot +/+ "progressions").reject { |n| n[0] == $_ };
				if (valid.size != 8) {
					fail.(name, "expected 8 valid progression stems on disk, found %: %".format(valid.size, valid));
				};
				before = ~ppLogCount;
				sendSel.('/pp/melody', 'classic_lead');
				sendSel.('/pp/progression', 'auto');
				if (waitFor.({
					(~ppSel[\progressions] == \auto) and: { (~ppSel[\melodies] == \classic_lead)
						and: { valid.every { |n| ~ppLib[\progressions][n.asSymbol].notNil } } }
				}, 5).not) {
					fail.(name, "the selections never became auto and classic_lead with every progression loaded: % / %".format(~ppSel, ~ppLib[\progressions].keys));
				};
				rc = recordBars.(48, 32);
				rws = rc[\rows];
				cyc = ~ppHarmCycleLog.();
				// Contiguous cycles, the first is classic at bar 0.
				cyc.do { |c, k|
					if (k == 0) {
						if ((c[\start] != 0) or: { c[\stem] != \classic }) {
							fail.(name, "the first cycle is % at %, expected classic at 0: %".format(c[\stem], c[\start], cyc));
						};
					} {
						if (c[\start] != (cyc[k - 1][\start] + cyc[k - 1][\len])) {
							fail.(name, "cycle % starts at %, not at the end of the previous one: %".format(k, c[\start], cyc));
						};
					};
				};
				// Runs: consecutive cycles of one progression.
				runs = List.new;
				cyc.do { |c|
					if (runs.size > 0 and: { runs[runs.size - 1][\stem] == c[\stem] }) {
						runs[runs.size - 1][\len] = runs[runs.size - 1][\len] + c[\len];
					} {
						runs.add((stem: c[\stem], start: c[\start], len: c[\len]));
					};
				};
				runs.do { |r, k|
					if ((k < (runs.size - 1)) and: { (r[\len] < 4) or: { r[\len] > 8 } }) {
						fail.(name, "the run of % at bar % lasts % bars, expected 4 to 8: %".format(r[\stem], r[\start], r[\len], runs));
					};
					if ((k >= 1) and: { r[\stem] == runs[k - 1][\stem] }) {
						fail.(name, "run % repeats the previous progression %: %".format(k, r[\stem], runs));
					};
					if ((k >= 2) and: { r[\stem] == runs[k - 2][\stem] }) {
						fail.(name, "run % goes back to % within two changes: %".format(k, r[\stem], runs));
					};
				};
				if (runs.collect { |r| r[\stem] }.asSet.size < 3) {
					fail.(name, "fewer than 3 different progressions played in 48 bars: %".format(runs));
				};
				fresh = newLogs.(before);
				lines = fresh.select { |l| l.beginsWith("PedalPulse: progression ") and: { l.find("auto seed").isNil } };
				if (lines.size != runs.size) {
					fail.(name, "% progression lines for % runs: %".format(lines.size, runs.size, lines));
				};
				runs.do { |r|
					if (lines.any { |l| l.beginsWith("PedalPulse: progression " ++ r[\stem] ++ ":") }.not) {
						fail.(name, "no progression line for the run of % in %".format(r[\stem], lines));
					};
				};
				harmonyCheck.(name, rws, [\ppBass, \ppArp, \ppPad, \ppLead]);
				if (fresh.any { |l| l.find("rotates progressions").notNil }.not) {
					fail.(name, "the auto selection line does not say 'rotates progressions': %".format(fresh));
				};
				~ppAutoHoldBars = savedHold;
				~ppAutoSeed = savedSeed;
				sendSel.('/pp/progression', 'classic');
				sendSel.('/pp/melody', 'classic');
				if (waitFor.({ (~ppSel[\progressions] == \classic) and: { ~ppSel[\melodies] == \classic } }, 3).not) {
					fail.(name, "selections did not return to classic: %".format(~ppSel));
				};
				checkOk.(name);
			}.value;

			// 12. auto keeps the playing progression first (planner decision, RESEARCH
			// Open Question 4): Auto picked in the middle of a ride adopts what plays.
			{
				var name = "auto keeps the playing progression first";
				var savedHold, savedSeed, rc, cyc, firstOther;
				savedHold = ~ppAutoHoldBars;
				savedSeed = ~ppAutoSeed;
				~ppAutoHoldBars = [4, 4];
				~ppAutoSeed = 11;
				sendSel.('/pp/progression', 'anthem');
				if (waitFor.({ ~ppSel[\progressions] == \anthem }, 3).not) {
					fail.(name, "~ppSel[\\progressions] never became anthem");
				};
				rc = recordBars.(24, 16, { |recClock, startBeat|
					while { recClock.beats < (startBeat + 20) } { 0.02.wait };  // bar 5
					sendSel.('/pp/progression', 'auto');
					if (waitFor.({ ~ppSel[\progressions] == \auto }, 3).not) {
						fail.(name, "~ppSel[\\progressions] never became auto");
					};
				});
				cyc = ~ppHarmCycleLog.();
				cyc.do { |c, k|
					if ((k > 0) and: { c[\start] != (cyc[k - 1][\start] + cyc[k - 1][\len]) }) {
						fail.(name, "cycle % starts at %, not at the end of the previous one: %".format(k, c[\start], cyc));
					};
				};
				[0, 4, 8].do { |st|
					var c = cyc.detect { |x| x[\start] == st };
					if (c.isNil or: { c[\stem] != \anthem }) {
						fail.(name, "the cycle at bar % is %, expected anthem (adopted by Auto): %".format(st, if (c.isNil) { nil } { c[\stem] }, cyc));
					};
				};
				firstOther = cyc.detect { |c| c[\stem] != \anthem };
				if (firstOther.isNil) {
					fail.(name, "Auto never left anthem: %".format(cyc));
				};
				if ((firstOther[\start] != 12) and: { firstOther[\start] != 16 }) {
					fail.(name, "the first other progression starts at bar %, expected 12 or 16: %".format(firstOther[\start], cyc));
				};
				~ppAutoHoldBars = savedHold;
				~ppAutoSeed = savedSeed;
				sendSel.('/pp/progression', 'classic');
				sendSel.('/pp/melody', 'classic');
				if (waitFor.({ (~ppSel[\progressions] == \classic) and: { ~ppSel[\melodies] == \classic } }, 3).not) {
					fail.(name, "selections did not return to classic: %".format(~ppSel));
				};
				checkOk.(name);
			}.value;

			// 13. auto stays bounded (ENG-03, T-06-10): 1200 Auto bars in a pure run keep
			// the memo, the cycle log and Auto's history at their caps; no error line.
			{
				var name = "auto stays bounded";
				var savedHold, savedSeed, before, valid, lastStart = nil, lastStem = nil, changes = 0;
				var lineCount = 0, errorCount = 0, log, last, chunk, h;
				savedHold = ~ppAutoHoldBars;
				savedSeed = ~ppAutoSeed;
				valid = listStems.(~ppLibRoot +/+ "progressions").reject { |n| n[0] == $_ };
				~ppHarmReset.value;
				~ppSel[\progressions] = \auto;
				~ppAutoHoldBars = [4, 4];
				~ppAutoSeed = 5;
				before = ~ppLogCount;
				1200.do { |i|
					~ppHarmonyFor.(5000 + i, i);
					last = ~ppHarmCycleLog.().last;
					if (last.notNil and: { last[\start] != lastStart }) {
						if (last[\stem] != lastStem) { changes = changes + 1 };
						lastStart = last[\start];
						lastStem = last[\stem];
					};
					// ~ppLogLines keeps only 100: count in chunks of 100 bars.
					if (((i + 1) % 100) == 0) {
						chunk = newLogs.(before);
						lineCount = lineCount + chunk.count { |l| l.beginsWith("PedalPulse: progression ") and: { l.find("auto seed").isNil } };
						errorCount = errorCount + chunk.count { |l| l.find("ERROR").notNil };
						before = ~ppLogCount;
					};
				};
				if (waitFor.({ ~ppAutoPrefetching != true }, 3).not) {
					fail.(name, "the Auto scan never finished");
				};
				h = ~ppHarm;
				if (h[\entries].size > 64) {
					fail.(name, "the memo holds % entries, expected at most 64".format(h[\entries].size));
				};
				if (~ppHarmCycleLog.().size > 256) {
					fail.(name, "the cycle log holds % records, expected at most 256".format(~ppHarmCycleLog.().size));
				};
				if (h[\auto][\history].size > 8) {
					fail.(name, "Auto remembers % picks, expected at most 8".format(h[\auto][\history].size));
				};
				if (~ppLib[\progressions].size != valid.size) {
					fail.(name, "the registry holds % progressions, expected the % on disk: %".format(~ppLib[\progressions].size, valid.size, ~ppLib[\progressions].keys));
				};
				if (changes < 100) {
					fail.(name, "only % progression changes in 1200 bars, Auto is not rotating".format(changes));
				};
				if (lineCount != changes) {
					fail.(name, "% progression lines for % progression changes".format(lineCount, changes));
				};
				if (errorCount > 0) {
					fail.(name, "% ERROR lines during the Auto run".format(errorCount));
				};
				~ppHarmReset.value;
				~ppSel[\progressions] = \classic;
				~ppAutoHoldBars = savedHold;
				~ppAutoSeed = savedSeed;
				checkOk.(name);
			}.value;

			// 14. Palette Auto tier (PAL-02, PAL-03, D-05 to D-08, D-11). Palette Auto
			// starts on a random palette, changes it together with the chords, and a
			// named pick locks it. The palettes are counted from disk (never a
			// hardcoded number). Every check saves and restores the tunables it sets
			// and puts all three selections back on classic.
			{
				var palStems, palAt, chapterAt, roundAt, prepare, checkVoices, saveT, restoreT;
				var noteLine;
				noteLine = "PedalPulse: only one progression can play on Auto, so Auto palettes change at the end of its round";
				palStems = listStems.(~ppLibRoot +/+ "palettes").reject { |n| n[0] == $_ };

				// The palette of song bar x: the last palette record with bar <= x.
				palAt = { |plog, x|
					var st = nil;
					plog.do { |e| if (e[\bar] <= x) { st = e[\stem] } };
					st
				};
				// True when a cycle with a different progression starts at bar (the run's
				// first cycle counts).
				chapterAt = { |cyc, bar|
					var i = cyc.detectIndex { |c| c[\start] == bar };
					i.notNil and: { (i == 0) or: { cyc[i][\stem] != cyc[i - 1][\stem] } }
				};
				// A round start: a chapter, or a cycle start that is a phrase line (a cycle
				// of at least 4 bars, or a multiple of 8).
				roundAt = { |cyc, bar|
					var c = cyc.detect { |x| x[\start] == bar };
					c.notNil and: { chapterAt.(cyc, bar) or: { (c[\len] >= 4) or: { (bar % 8) == 0 } } }
				};
				// Selections in place, every palette on disk registered, no palette scan
				// queued or running.
				prepare = { |name, prog, pal|
					sendSel.('/pp/melody', 'classic_lead');
					sendSel.('/pp/progression', prog);
					sendSel.('/pp/palette', pal);
					if (waitFor.({
						(~ppSel[\melodies] == \classic_lead) and: { (~ppSel[\progressions] == prog) and: { (~ppSel[\palettes] == pal)
							and: { (palStems.every { |n| ~ppLib[\palettes][n.asSymbol].notNil })
								and: { (~ppAutoBusy.isNil or: { ~ppAutoBusy.(\palettes) != true }) and: { ~ppAutoPrefetching != true } } } } }
					}, 8).not) {
						fail.(name, "the selections never became classic_lead, % and % with every palette loaded and no scan running: % / %".format(prog, pal, ~ppSel, ~ppLib[\palettes].keys));
					};
				};
				// Every row of every layer uses the voice its role gets from its bar's palette.
				checkVoices = { |name, rws, plog, nBars|
					rws.do { |r|
						var b = barOf.(r[1]), st = palAt.(plog, b), want;
						want = ~ppInstrumentFor.(~ppLayerRole[r[0]], st);
						if (r[2] != want) {
							fail.(name, "% bar % plays % instead of % (palette % there)".format(r[0], b, r[2], want, st));
						};
					};
					if (rws.count { |r| r[0] == \ppKick } != (4 * nBars)) {
						fail.(name, "% kick rows in % bars (the music stopped)".format(rws.count { |r| r[0] == \ppKick }, nBars));
					};
				};
				saveT = { (hold: ~ppAutoHoldBars, seed: ~ppAutoSeed, pal: ~ppPalHoldBars) };
				restoreT = { |t|
					~ppAutoHoldBars = t[\hold];
					~ppAutoSeed = t[\seed];
					~ppPalHoldBars = t[\pal];
				};

				// 14a. auto palette rotates, and lands on a progression change.
				{
					var name = "auto palette rotates";
					var saved, rc, rws, plog, cyc, before, fresh, lines, stems;
					saved = saveT.value;
					~ppAutoHoldBars = [4, 8];
					~ppAutoSeed = 11;
					~ppPalHoldBars = [4, 4];
					before = ~ppLogCount;
					prepare.(name, \auto, \auto);
					rc = recordBars.(64, 32);
					rws = rc[\rows];
					plog = ~ppHarmPaletteLog.();
					cyc = ~ppHarmCycleLog.();
					if (plog.isEmpty or: { plog[0][\bar] != 0 }) {
						fail.(name, "the first palette record is not at bar 0: %".format(plog));
					};
					if (plog[0][\stem] == \classic) {
						fail.(name, "the first palette is classic, the palette that was playing before: %".format(plog));
					};
					stems = plog.collect { |e| e[\stem] };
					if (stems.asSet.size < 3) {
						fail.(name, "fewer than 3 different palettes in 64 bars: %".format(plog));
					};
					plog.do { |e, k|
						if ((k >= 1) and: { e[\stem] == plog[k - 1][\stem] }) {
							fail.(name, "palette record % repeats the previous palette %: %".format(k, e[\stem], plog));
						};
						if ((k >= 2) and: { e[\stem] == plog[k - 2][\stem] }) {
							fail.(name, "palette record % goes back to % within two changes: %".format(k, e[\stem], plog));
						};
						if ((k >= 1) and: { chapterAt.(cyc, e[\bar]).not }) {
							fail.(name, "palette record % starts at bar %, where no different progression starts: % / %".format(k, e[\bar], plog, cyc));
						};
					};
					checkVoices.(name, rws, plog, 64);
					fresh = newLogs.(before);
					lines = fresh.select { |l| l.beginsWith("PedalPulse: palette ") };
					if (lines.size != plog.size) {
						fail.(name, "% palette lines for % palette records: %".format(lines.size, plog.size, lines));
					};
					plog.do { |e, k|
						if (lines[k].beginsWith("PedalPulse: palette " ++ e[\stem] ++ ": ").not) {
							fail.(name, "palette line % is '%', expected the palette %".format(k, lines[k], e[\stem]));
						};
					};
					if (fresh.any { |l| l.find("rotates palettes").notNil }.not) {
						fail.(name, "the palette auto selection line does not say 'rotates palettes': %".format(fresh));
					};
					restoreT.(saved);
					restoreAll.(name);
					checkOk.(name);
					checkOk.("auto palette lands on a progression change");
				}.value;

				// 14b. auto palette with a locked progression (D-07) and with only one
				// progression able to play (explicit exception 2 to D-06).
				{
					var name = "auto palette with a locked progression";
					var saved, rc, rws, plog, before, base = 41000, orig, cyc, fresh, bars;
					saved = saveT.value;
					~ppAutoHoldBars = [4, 8];
					~ppAutoSeed = 11;
					~ppPalHoldBars = [4, 4];

					// anthem picked by name: its cycle is 4 bars, a change lands on a multiple of 4.
					prepare.(name, \anthem, \auto);
					rc = recordBars.(32, 32);
					plog = ~ppHarmPaletteLog.();
					if (plog.isEmpty or: { plog[0][\bar] != 0 }) {
						fail.(name, "anthem: the first palette record is not at bar 0: %".format(plog));
					};
					if (plog.size < 4) {
						fail.(name, "anthem: fewer than 3 palette changes in 32 bars: %".format(plog));
					};
					plog.do { |e, k|
						if ((k >= 1) and: { (e[\bar] % 4) != 0 }) {
							fail.(name, "anthem: palette record % at bar % is not on an anthem cycle start: %".format(k, e[\bar], plog));
						};
					};
					checkVoices.(name, rc[\rows], plog, 32);

					// classic picked by name: a one-bar cycle, a change lands on a multiple of 8.
					prepare.(name, \classic, \auto);
					rc = recordBars.(32, 32);
					plog = ~ppHarmPaletteLog.();
					if (plog.isEmpty or: { plog[0][\bar] != 0 }) {
						fail.(name, "classic: the first palette record is not at bar 0: %".format(plog));
					};
					if (plog.size < 3) {
						fail.(name, "classic: fewer than 2 palette changes in 32 bars: %".format(plog));
					};
					plog.do { |e, k|
						if ((k >= 1) and: { (e[\bar] % 8) != 0 }) {
							fail.(name, "classic: palette record % at bar % is not on a multiple of 8: %".format(k, e[\bar], plog));
						};
					};
					checkVoices.(name, rc[\rows], plog, 32);
					restoreT.(saved);
					restoreAll.(name);
					checkOk.(name);

					// Exception 2, pure: progression Auto but only classic can play.
					name = "auto palette with a single progression";
					saved = saveT.value;
					orig = ~ppAutoCandidates;
					{
						~ppAutoCandidates = { [\classic] };
						~ppAutoHoldBars = [4, 4];
						~ppAutoSeed = 11;
						~ppPalHoldBars = [4, 4];
						waitFor.({ (~ppAutoBusy.isNil or: { ~ppAutoBusy.(\palettes) != true }) and: { ~ppAutoPrefetching != true } }, 3);
						~ppHarmReset.value;
						~ppSel[\progressions] = \auto;
						~ppSel[\palettes] = \auto;
						~ppPalPlaying = \classic;
						before = ~ppLogCount;
						64.do { |i| ~ppHarmonyFor.(base + i, i) };
						plog = ~ppHarmPaletteLog.();
						cyc = ~ppHarmCycleLog.();
						fresh = newLogs.(before);
						if (cyc.any { |c| c[\stem] != \classic }) {
							fail.(name, "a cycle is not classic although only classic can play: %".format(cyc));
						};
						if (plog.isEmpty or: { plog[0][\bar] != 0 }) {
							fail.(name, "the first palette record is not at bar 0: %".format(plog));
						};
						if (plog.size < 3) {
							fail.(name, "fewer than 2 palette changes in 64 bars: %".format(plog));
						};
						plog.do { |e, k|
							if ((k >= 1) and: { (e[\bar] % 8) != 0 }) {
								fail.(name, "palette record % at bar % is not on a multiple of 8: %".format(k, e[\bar], plog));
							};
						};
						if (fresh.count { |l| l == noteLine } != 1) {
							fail.(name, "expected exactly one '%' line in %".format(noteLine, fresh));
						};
					}.protect({
						~ppAutoCandidates = orig;
						~ppHarmReset.value;
						~ppSel[\progressions] = \classic;
						~ppSel[\palettes] = \classic;
						restoreT.(saved);
					});
					checkOk.(name);
					checkOk.("auto palette with a locked progression");
				}.value;

				// 14c. named palette locks (PAL-03, D-11) and Auto after it draws a
				// different palette at the next round start.
				{
					var name = "named palette locks";
					var saved, rc, rws, plog, cyc, locked = nil, lockRec, next, changes;
					saved = saveT.value;
					~ppAutoHoldBars = [4, 8];
					~ppAutoSeed = 11;
					~ppPalHoldBars = [4, 4];
					prepare.(name, \auto, \auto);
					rc = recordBars.(56, 16, { |recClock, startBeat|
						while { recClock.beats < (startBeat + 26) } { 0.02.wait };  // bar 6.5
						// supersaw, unless Auto is playing it just now (then dark): the pick
						// must be a change.
						locked = if (~ppPalPlaying == \supersaw) { \dark } { \supersaw };
						sendSel.('/pp/palette', locked);
						if (waitFor.({ ~ppSel[\palettes] == locked }, 3).not) {
							fail.(name, "~ppSel[\\palettes] never became %".format(locked));
						};
						while { recClock.beats < (startBeat + 130) } { 0.02.wait };  // bar 32.5
						sendSel.('/pp/palette', 'auto');
						if (waitFor.({ ~ppSel[\palettes] == \auto }, 3).not) {
							fail.(name, "~ppSel[\\palettes] never became auto again");
						};
					});
					rws = rc[\rows];
					plog = ~ppHarmPaletteLog.();
					cyc = ~ppHarmCycleLog.();
					lockRec = plog.detect { |e| (e[\stem] == locked) and: { (e[\bar] >= 7) and: { e[\bar] <= 9 } } };
					if (lockRec.isNil) {
						fail.(name, "% never took over in bars 7 to 9 (picked in bar 6.5): %".format(locked, plog));
					};
					if (plog.any { |e| (e[\bar] > lockRec[\bar]) and: { e[\bar] <= 32 } }) {
						fail.(name, "another palette record while % was locked: %".format(locked, plog));
					};
					changes = cyc.count { |c| (c[\start] > lockRec[\bar]) and: { (c[\start] <= 32) and: { chapterAt.(cyc, c[\start]) } } };
					if (changes < 2) {
						fail.(name, "the progression changed only % times while the palette was locked: %".format(changes, cyc));
					};
					next = plog.detect { |e| e[\bar] > 32 };
					if (next.isNil or: { next[\bar] > 48 }) {
						fail.(name, "Auto drew no new palette in bars 33 to 48: %".format(plog));
					};
					if (next[\stem] == locked) {
						fail.(name, "Auto after the lock drew the locked palette % again: %".format(locked, plog));
					};
					if (roundAt.(cyc, next[\bar]).not) {
						fail.(name, "the new palette starts at bar %, which is not a round start: % / %".format(next[\bar], plog, cyc));
					};
					checkVoices.(name, rws, plog, 56);
					restoreT.(saved);
					restoreAll.(name);
					checkOk.(name);
				}.value;
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

			// 5b. named palette plays from the next bar (PAL-03 next-bar half, D-03,
			// D-09, D-10, D-11): a fixture palette that replaces ALL seven voices is
			// picked by name and dropped again while the music runs. Every layer,
			// the three drum layers included, switches on the same bar line (never
			// mid-bar, never one layer a bar late), the music never stops, and the
			// post window names each change once.
			{
				var name = "named palette plays from the next bar";
				var roles, drums, voice, defsText, rolesText, classicInst, probeInst, wantInst;
				var rc, logBefore, s1, s2, plog, fresh, probeLine, probeAt, classicAfter, classicDesc, rowsOf, layerNames;
				roles = [\kick, \hat, \clap, \bass, \arp, \pad, \lead];
				drums = [\kick, \hat, \clap];
				voice = { |role|
					if (drums.includes(role)) {
						"SynthDef(\\pp_probe_pal_%, { |out = 0, amp = 0.1| var env = EnvGen.kr(Env.perc(0.001, 0.1), doneAction: 2); Out.ar(out, (SinOsc.ar(200) * env * amp) ! 2) }).add;".format(role)
					} {
						"SynthDef(\\pp_probe_pal_%, { |out = 0, amp = 0.1, freq = 220, gate = 1| var env = EnvGen.kr(Env.adsr(0.005, 0.05, 0.5, 0.1), gate, doneAction: 2); Out.ar(out, (Saw.ar(freq) * env * amp) ! 2) }).add;".format(role)
					}
				};
				defsText = roles.collect { |r| voice.(r) }.join("\n");
				rolesText = roles.collect { |r| "%: (instrument: \\pp_probe_pal_%)".format(r, r) }.join(", ");
				wr.("palettes/probe_pal.scd", "(\ndesc: \"probe palette\",\ndefs: {\n%\n},\nroles: (%)\n)\n".format(defsText, rolesText));
				// What each role plays under classic, and under the fixture.
				classicInst = (kick: \ppKick, hat: \ppHat, clap: \ppClap, bass: \ppBass, arp: \ppArp, pad: \ppPad, lead: \ppArp);
				probeInst = { |role| ("pp_probe_pal_" ++ role).asSymbol };
				layerNames = [\ppKick, \ppHat, \ppClap, \ppBass, \ppArp, \ppPad, \ppLead];

				sendSel.('/pp/melody', 'classic_lead');
				if (waitFor.({ ~ppSel[\melodies] == \classic_lead }, 3).not) {
					fail.(name, "~ppSel[\\melodies] never became classic_lead");
				};
				logBefore = ~ppLogCount;
				rc = recordBars.(16, 16, { |recClock, startBeat|
					while { recClock.beats < (startBeat + 18) } { 0.02.wait };  // bar 4.5
					sendSel.('/pp/palette', 'probe_pal');
					if (waitFor.({ ~ppSel[\palettes] == \probe_pal }, 3).not) {
						fail.(name, "~ppSel[\\palettes] never became probe_pal: %".format(newLogs.(logBefore)));
					};
					while { recClock.beats < (startBeat + 42) } { 0.02.wait };  // bar 10.5
					sendSel.('/pp/palette', 'classic');
					if (waitFor.({ ~ppSel[\palettes] == \classic }, 3).not) {
						fail.(name, "~ppSel[\\palettes] never returned to classic");
					};
				});

				// S1: the first bar with any fixture voice. S2: the first later bar
				// that is back on classic voices.
				s1 = nil;
				rc[\rows].do { |r|
					if (r[2].asString.beginsWith("pp_probe_pal_")) {
						s1 = if (s1.isNil) { barOf.(r[1]) } { min(s1, barOf.(r[1])) };
					};
				};
				if (s1.isNil) { fail.(name, "no row ever used a pp_probe_pal_ voice: %".format(newLogs.(logBefore))) };
				if ((s1 < 5) or: { s1 > 7 }) { fail.(name, "the fixture palette took over in bar %, expected bar 5 to 7 (sent in bar 4.5)".format(s1)) };
				s2 = nil;
				rc[\rows].do { |r|
					var b = barOf.(r[1]);
					if ((b > s1) and: { r[2].asString.beginsWith("pp_probe_pal_").not }) {
						s2 = if (s2.isNil) { b } { min(s2, b) };
					};
				};
				if (s2.isNil) { fail.(name, "the music never went back to classic voices after bar %".format(s1)) };
				if ((s2 < 11) or: { s2 > 13 }) { fail.(name, "classic took over again in bar %, expected bar 11 to 13 (sent in bar 10.5)".format(s2)) };

				// Every row of every layer: classic voice before S1 and from S2, the
				// fixture's voice for ITS role in between. One bar, one palette.
				rc[\rows].do { |r|
					var b = barOf.(r[1]), role = ~ppLayerRole[r[0]];
					wantInst = if ((b >= s1) and: { b < s2 }) { probeInst.(role) } { classicInst[role] };
					if (r[2] != wantInst) {
						fail.(name, "% bar % plays % instead of % (the palette changed in bar % and back in bar %)".format(r[0], b, r[2], wantInst, s1, s2));
					};
				};
				// Each of the seven layers is actually heard in all three stretches
				// (otherwise "every row matches" would prove nothing for it).
				rowsOf = { |layer, from, to| rc[\rows].count { |r| (r[0] == layer) and: { (barOf.(r[1]) >= from) and: { barOf.(r[1]) < to } } } };
				layerNames.do { |layer|
					[[0, s1], [s1, s2], [s2, 16]].do { |span|
						if (rowsOf.(layer, span[0], span[1]) == 0) {
							fail.(name, "% plays nothing in bars % to %".format(layer, span[0], span[1] - 1));
						};
					};
				};
				expectClassicBars.(name, rc[\rows], 16);

				// The bar's palette is decided once per bar in the harmony memo.
				plog = ~ppHarmPaletteLog.();
				if (plog.isNil) { fail.(name, "~ppHarmPaletteLog does not exist") };
				if (plog.collect { |e| e[\stem] } != [\classic, \probe_pal, \classic]) {
					fail.(name, "the palette log is %, expected classic, probe_pal, classic".format(plog));
				};
				if (plog.collect { |e| e[\bar] } != [0, s1, s2]) {
					fail.(name, "the palette log bars are %, expected [0, %, %]".format(plog.collect { |e| e[\bar] }, s1, s2));
				};

				// The post window names every change, once (D-09).
				fresh = newLogs.(logBefore);
				probeLine = "PedalPulse: palette probe_pal: probe palette";
				if (fresh.count { |l| l == probeLine } != 1) {
					fail.(name, "expected exactly one line '%' in %".format(probeLine, fresh));
				};
				probeAt = fresh.detectIndex { |l| l == probeLine };
				classicDesc = ~ppLib[\palettes][\classic][\desc];
				classicAfter = fresh.copyToEnd(probeAt + 1).select { |l| l.beginsWith("PedalPulse: palette classic: ") };
				if (classicAfter != ["PedalPulse: palette classic: " ++ classicDesc]) {
					fail.(name, "after the fixture line expected exactly one classic line with its desc, got %".format(classicAfter));
				};

				sendSel.('/pp/melody', 'classic');
				if (waitFor.({ ~ppSel[\melodies] == \classic }, 3).not) {
					fail.(name, "~ppSel[\\melodies] never returned to classic");
				};
				if (~ppSel[\palettes] != \classic) {
					fail.(name, "~ppSel[\\palettes] is % at the end, expected classic".format(~ppSel[\palettes]));
				};
				checkOk.(name);
			}.value;

			// 5c. palette voice namespace (WR-02, D-16): a palette can only own voices
			// under its own pp_<name>_ prefix, and a refused palette leaves no
			// voices behind and restores what it touched. Three fixtures in the
			// temporary root, each selected by name while the engine runs. The
			// compiled bytes of a SynthDef are the proof that a voice is the
			// owner's again.
			{
				var descBytes, voice, palText, refused, errLine, restoreSel;
				var path, before, bytesBefore, rev1, bytes1, name;

				descBytes = { |nm| SynthDescLib.global.synthDescs[nm] !? { |d| d.def.asBytes } };
				voice = { |nm, wave|
					"SynthDef('%', { |out = 0, amp = 0.1, freq = 440, gate = 1| var env = EnvGen.kr(Env.adsr(0.005, 0.05, 0.5, 0.1), gate, doneAction: 2); Out.ar(out, (%.ar(freq) * env * amp) ! 2) }).add;".format(nm, wave)
				};
				palText = { |desc, defsText, inst|
					"(\ndesc: \"%\",\ndefs: {\n%\n},\nroles: (arp: (instrument: '%'))\n)\n".format(desc, defsText, inst)
				};
				// The selection routine's last line for a refused pick, logged after the
				// guard's undo and its s.sync.
				refused = { |since, stem|
					waitFor.({ newLogs.(since).any { |l| l.find("/pp/palette % refused".format(stem)).notNil } }, 3)
				};
				errLine = { |since, path, needle|
					newLogs.(since).any { |l| l.find("ERROR").notNil and: { l.find(path).notNil } and: { l.find(needle).notNil } }
				};
				restoreSel = { |nm|
					sendSel.('/pp/palette', 'classic');
					if (waitFor.({ ~ppSel[\palettes] == \classic }, 3).not) {
						fail.(nm, "~ppSel[\\palettes] never returned to classic");
					};
				};

				// palette defs stay in their prefix: redefining classic's ppArp refuses
				// the file, removes what it added and puts classic's voice back.
				name = "palette defs stay in their prefix";
				bytesBefore = descBytes.(\ppArp);
				if (bytesBefore.isNil) { fail.(name, "classic's ppArp is not defined before the fixture") };
				wr.("palettes/clobber.scd", palText.("clobbers classic's arp", voice.("pp_clobber_arp", "SinOsc") ++ "\n" ++ voice.("ppArp", "Saw"), "pp_clobber_arp"));
				path = tmpRoot +/+ "palettes/clobber.scd";
				before = ~ppLogCount;
				sendSel.('/pp/palette', 'clobber');
				if (refused.(before, "clobber").not) { fail.(name, "no refusal line for clobber in %".format(newLogs.(before))) };
				if (errLine.(before, path, "ppArp").not) { fail.(name, "no ERROR line naming % and ppArp in %".format(path, newLogs.(before))) };
				if (SynthDescLib.global.synthDescs[\pp_clobber_arp].notNil) { fail.(name, "pp_clobber_arp was left behind by the refused palette") };
				if (descBytes.(\ppArp) != bytesBefore) { fail.(name, "ppArp is not classic's again after the refusal") };
				if (~ppSel[\palettes] != \classic) { fail.(name, "the palette selection changed to %".format(~ppSel[\palettes])) };
				checkOk.(name);

				// refused palette leaves no voices: defs adds a voice, then throws.
				name = "refused palette leaves no voices";
				wr.("palettes/half_defs.scd", palText.("adds a voice then throws", voice.("pp_half_defs_arp", "SinOsc") ++ "\nError(\"boom after adding\").throw;", "pp_half_defs_arp"));
				path = tmpRoot +/+ "palettes/half_defs.scd";
				before = ~ppLogCount;
				sendSel.('/pp/palette', 'half_defs');
				if (refused.(before, "half_defs").not) { fail.(name, "no refusal line for half_defs in %".format(newLogs.(before))) };
				if (errLine.(before, path, "boom after adding").not) { fail.(name, "no ERROR line naming % in %".format(path, newLogs.(before))) };
				if (SynthDescLib.global.synthDescs[\pp_half_defs_arp].notNil) { fail.(name, "pp_half_defs_arp was left behind by the refused palette") };
				if (~ppSel[\palettes] != \classic) { fail.(name, "the palette selection changed to %".format(~ppSel[\palettes])) };
				checkOk.(name);

				// refused reload restores the last good voices: a loaded palette is
				// rewritten into a bad file; its last good voices keep playing.
				name = "refused reload restores the last good voices";
				wr.("palettes/fixpal.scd", palText.("fixture palette", voice.("pp_fixpal_arp", "SinOsc"), "pp_fixpal_arp"));
				path = tmpRoot +/+ "palettes/fixpal.scd";
				sendSel.('/pp/palette', 'fixpal');
				if (waitFor.({ ~ppSel[\palettes] == \fixpal }, 3).not) { fail.(name, "~ppSel[\\palettes] never became fixpal") };
				bytes1 = descBytes.(\pp_fixpal_arp);
				if (bytes1.isNil) { fail.(name, "pp_fixpal_arp is not defined after the first load") };
				rev1 = ~ppLib[\palettes][\fixpal][\rev];
				1.1.wait;  // the file's modification time must change
				wr.("palettes/fixpal.scd", palText.("fixture palette, now broken", voice.("pp_fixpal_arp", "Saw") ++ "\n" ++ voice.("pp_fixpal_extra", "Saw") ++ "\nError(\"boom after redefining\").throw;", "pp_fixpal_arp"));
				before = ~ppLogCount;
				sendSel.('/pp/palette', 'fixpal');
				if (refused.(before, "fixpal").not) { fail.(name, "no refusal line for the rewritten fixpal in %".format(newLogs.(before))) };
				if (errLine.(before, path, "boom after redefining").not) { fail.(name, "no ERROR line naming % in %".format(path, newLogs.(before))) };
				if (~ppSel[\palettes] != \fixpal) { fail.(name, "the selection is % instead of fixpal".format(~ppSel[\palettes])) };
				if (~ppLib[\palettes][\fixpal][\rev] != rev1) { fail.(name, "the registry copy changed from rev % to %".format(rev1, ~ppLib[\palettes][\fixpal][\rev])) };
				if (descBytes.(\pp_fixpal_arp) != bytes1) { fail.(name, "pp_fixpal_arp is not the first version's again") };
				if (SynthDescLib.global.synthDescs[\pp_fixpal_extra].notNil) { fail.(name, "pp_fixpal_extra was left behind by the refused reload") };
				restoreSel.(name);
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
					["a rest and a chord", [[\rest, 2, 0, 1], [[45, 48, 52], 2, 0.06, 0.9]]],
					// WR-01 bounds (Phase 7 Plan 02): the edges themselves are allowed.
					["64 rows of 1/16", Array.fill(64, { [60, 1/16, 0.1, 0.5] })],
					["legato exactly 8", [[60, 4, 0.1, 8]]],
					["notes -12 and 127", [[-12, 2, 0.1, 0.5], [127, 2, 0.1, 0.5]]],
					["a chord of 8 notes", [[[40, 44, 47, 52, 56, 59, 64, 68], 4, 0.06, 0.9]]],
					["a dur of exactly 1/32", [[60, 1/32, 0.1, 0.5], [60, 4 - (1/32), 0.1, 0.5]]]
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
					["a nan dur", [[60, 0 / 0, 0.1, 0.5]]],
					// WR-01 bounds, each with the words its reason must contain.
					["65 rows of 4/65", Array.fill(65, { [60, 4 / 65, 0.1, 0.5] }), "65 rows, more than 64"],
					["400000 rows of 1e-5", Array.fill(400000, { [60, 1e-5, 0.1, 0.5] }), "more than 64"],
					["a dur of 1/64", [[60, 1/64, 0.1, 0.5], [60, 4 - (1/64), 0.1, 0.5]], "shorter than 1/32"],
					["legato 8.5", [[60, 4, 0.1, 8.5]], "more than 8"],
					["note 128", [[128, 4, 0.1, 0.5]], "outside -12 to 127"],
					["note -13", [[-13, 4, 0.1, 0.5]], "outside -12 to 127"],
					["a chord of 9 notes", [[[40, 44, 47, 52, 56, 59, 64, 68, 71], 4, 0.06, 0.9]], "more than 8"],
					["a chord containing 200", [[[60, 200], 4, 0.06, 0.9]], "outside -12 to 127"]
				];
				bad.do { |b|
					r = ~ppRowsValid.(b[1]);
					if (r.isKindOf(String).not) { fail.(name, "% should fail but passed".format(b[0])) };
					if (b[2].notNil and: { r.find(b[2]).isNil }) {
						fail.(name, "% should say \"%\" but said: %".format(b[0], b[2], r));
					};
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

			// 11. auto adds a new progression file (D-10, LIB-05): a progression file
			// written while Auto runs joins the rotation by itself, no restart.
			{
				var name = "auto adds a new progression file";
				var savedHold, savedSeed, rc, cyc, runs, fp, rcode, before;
				savedHold = ~ppAutoHoldBars;
				savedSeed = ~ppAutoSeed;
				before = ~ppLogCount;
				rcode =("cp" + shq.(realLibRoot +/+ "progressions/anthem.scd") + shq.(tmpRoot +/+ "progressions/anthem.scd")).systemCmd;
				if (rcode != 0) { fail.(name, "cp of anthem.scd failed with %".format(rcode)) };
				~ppAutoHoldBars = [4, 4];
				~ppAutoSeed = 11;
				sendSel.('/pp/progression', 'auto');
				if (waitFor.({ ~ppSel[\progressions] == \auto }, 3).not) {
					fail.(name, "~ppSel[\\progressions] never became auto");
				};
				rc = recordBars.(24, 16, { |recClock, startBeat|
					while { recClock.beats < (startBeat + 18) } { 0.02.wait };  // bar 4.5
					wr.("progressions/fresh_prog.scd", "(\ndesc: \"fresh\",\nbarsPerChord: 1,\nchords: [\n\t(root: 0, quality: \\min),\n\t(root: 5, quality: \\min)\n]\n)\n");
				});
				cyc = ~ppHarmCycleLog.();
				cyc.do { |c, k|
					if ((k > 0) and: { c[\start] != (cyc[k - 1][\start] + cyc[k - 1][\len]) }) {
						fail.(name, "cycle % starts at %, not at the end of the previous one: %".format(k, c[\start], cyc));
					};
				};
				runs = List.new;
				cyc.do { |c|
					if (runs.size > 0 and: { runs[runs.size - 1][\stem] == c[\stem] }) {
						runs[runs.size - 1][\len] = runs[runs.size - 1][\len] + c[\len];
					} {
						runs.add((stem: c[\stem], start: c[\start], len: c[\len]));
					};
				};
				if ((runs.size < 3)
					or: { (runs[0][\stem] != \classic) or: { (runs[0][\start] != 0) or: { runs[0][\len] != 4 } } }
					or: { (runs[1][\stem] != \anthem) or: { (runs[1][\start] != 4) or: { runs[1][\len] != 4 } } }
					or: { (runs[2][\stem] != \classic) or: { (runs[2][\start] != 8) or: { runs[2][\len] != 4 } } }) {
					fail.(name, "the first runs are not classic 0-3, anthem 4-7, classic 8-11: %".format(runs));
				};
				fp = cyc.detect { |c| c[\stem] == \fresh_prog };
				if (fp.isNil) {
					fail.(name, "fresh_prog.scd never joined the rotation: %".format(cyc));
				};
				if (fp[\start] > 20) {
					fail.(name, "fresh_prog started at bar %, expected at or before 20: %".format(fp[\start], cyc));
				};
				harmonyCheck.(name, rc[\rows], [\ppBass, \ppArp, \ppPad, \ppLead]);
				// For "auto reports a broken file once": the broken fixture's ERROR lines so far.
				brokenCount = newLogs.(before).count { |l| l.find("ERROR").notNil and: { l.find(tmpRoot +/+ "progressions/not_function.scd").notNil } };
				~ppAutoHoldBars = savedHold;
				~ppAutoSeed = savedSeed;
				sendSel.('/pp/progression', 'classic');
				if (waitFor.({ ~ppSel[\progressions] == \classic }, 3).not) {
					fail.(name, "~ppSel[\\progressions] never returned to classic");
				};
				checkOk.(name);
			}.value;

			// 12. auto skips a failing progression (T-06-09): a progression whose bars
			// fail leaves the rotation after three failures; the music never stops.
			{
				var name = "auto skips a failing progression";
				var savedHold, savedSeed, rc, cyc, before, fresh, mine, bassNotes;
				savedHold = ~ppAutoHoldBars;
				savedSeed = ~ppAutoSeed;
				File.delete(tmpRoot +/+ "progressions/anthem.scd");
				File.delete(tmpRoot +/+ "progressions/fresh_prog.scd");
				wr.("progressions/gen_fail.scd", "(\ndesc: \"bass throws\",\nbarsPerChord: 1,\nchords: [\n\t(root: 0, quality: \\min),\n\t(root: 8, quality: \\maj),\n\t(root: 3, quality: \\maj),\n\t(root: 10, quality: \\maj)\n],\nbass: { |plan, state| Error(\"boom in bass\").throw }\n)\n");
				~ppAutoHoldBars = [4, 4];
				~ppAutoSeed = 11;
				before = ~ppLogCount;
				sendSel.('/pp/progression', 'auto');
				if (waitFor.({ (~ppSel[\progressions] == \auto) and: { ~ppLib[\progressions][\gen_fail].notNil } }, 3).not) {
					fail.(name, "gen_fail was never registered by the Auto scan: %".format(newLogs.(before)));
				};
				rc = recordBars.(28, 16);
				cyc = ~ppHarmCycleLog.();
				cyc.do { |c, k|
					if ((k > 0) and: { c[\start] != (cyc[k - 1][\start] + cyc[k - 1][\len]) }) {
						fail.(name, "cycle % starts at %, not at the end of the previous one: %".format(k, c[\start], cyc));
					};
				};
				if (cyc.select { |c| c[\start] < 4 }.any { |c| c[\stem] != \classic }) {
					fail.(name, "bars 0 to 3 are not classic: %".format(cyc));
				};
				if ((cyc.select { |c| c[\stem] == \gen_fail }.collect { |c| c[\start] }) != [4]) {
					fail.(name, "gen_fail is not exactly the cycle at bar 4: %".format(cyc));
				};
				if (cyc.select { |c| c[\start] >= 8 }.any { |c| c[\stem] == \gen_fail }) {
					fail.(name, "Auto picked gen_fail again from bar 8 on: %".format(cyc));
				};
				28.do { |b|
					bassNotes = rc[\rows].count { |r| (r[0] == \ppBass) and: { (barOf.(r[1]) == b) and: { r[3] != \rest } } };
					if (bassNotes != 4) {
						fail.(name, "the bass sounds % notes in bar %, expected 4 (the music stopped)".format(bassNotes, b));
					};
				};
				fresh = newLogs.(before);
				mine = fresh.select { |l| l.find("gen_fail.scd").notNil and: { l.find("playing classic for this bar").notNil } };
				if (mine.size < 3) {
					fail.(name, "% 'playing classic for this bar' lines naming gen_fail.scd, expected at least 3: %".format(mine.size, fresh));
				};
				brokenCount = brokenCount + fresh.count { |l| l.find("ERROR").notNil and: { l.find(tmpRoot +/+ "progressions/not_function.scd").notNil } };
				~ppAutoHoldBars = savedHold;
				~ppAutoSeed = savedSeed;
				sendSel.('/pp/progression', 'classic');
				if (waitFor.({ ~ppSel[\progressions] == \classic }, 3).not) {
					fail.(name, "~ppSel[\\progressions] never returned to classic");
				};
				checkOk.(name);
			}.value;

			// 13. auto reports a broken file once (T-06-08): several Auto scans ran,
			// yet the broken fixture was reported once; it is reported again only
			// after the file changes.
			{
				var name = "auto reports a broken file once";
				var path, before, n;
				path = tmpRoot +/+ "progressions/not_function.scd";
				if (brokenCount != 1) {
					fail.(name, "the broken file was reported % times by the earlier Auto scans, expected exactly 1".format(brokenCount));
				};
				waitFor.({ ~ppAutoPrefetching != true }, 3);
				1.1.wait;  // the file's modification time has a one second resolution
				wr.("progressions/not_function.scd", "(desc: \"not a function\", bass: \"not a function\")\n");
				before = ~ppLogCount;
				~ppAutoPrefetch.value;
				if (waitFor.({ ~ppAutoPrefetching != true }, 3).not) {
					fail.(name, "the Auto scan never finished");
				};
				1.wait;
				n = newLogs.(before).count { |l| l.find("ERROR").notNil and: { l.find(path).notNil } };
				if (n != 1) {
					fail.(name, "the changed broken file was reported % times, expected exactly 1: %".format(n, newLogs.(before)));
				};
				before = ~ppLogCount;
				~ppAutoPrefetch.value;
				waitFor.({ ~ppAutoPrefetching != true }, 3);
				1.wait;
				n = newLogs.(before).count { |l| l.find("ERROR").notNil and: { l.find(path).notNil } };
				if (n != 0) {
					fail.(name, "the unchanged broken file was reported again % times".format(n));
				};
				~ppAutoHoldBars = [32, 64];
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
