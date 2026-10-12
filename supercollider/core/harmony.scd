// PedalPulse core: shared harmony (Phase 6, HARM-01 / HARM-03 / HARM-04).
//
// Loaded by main.scd (~ppLoadCore) at top level, after loader.scd and before
// render.scd. Server-free at load: definitions only. No Routine, no clock, no
// scheduling anywhere in this module (ENG-05); it plays nothing.
//
// Design: a memoized per-bar entry that the layers PULL. There is no mutable
// "current chord" variable that a layer could read before or after another layer
// moved it. Every pitched layer (bass, arp, pad, lead) asks ~ppHarmonyFor for the
// entry of its own (run, song bar); the first layer to ask builds it and the rest
// read the same stored Event, so all four layers of a bar see one chord by
// construction. This also resolves the STATE.md same-beat spike (layers whose
// bar-start events land on the same beat in any order).
//
// A "run" is the stretch between two (re)starts of the groove. It is keyed by the
// calling thread's clock and by (bar - songBar), so a fresh recording clock, a
// restart, or a tempo change (beats keep counting) behave exactly as the layers do.
//
// A "cycle" is one pass through a progression's chords. The selection is read at
// the cycle boundary only (HARM-04): ~ppHarmDecide captures the module from
// ~ppLib at that moment, so neither a reload nor a new pick changes a cycle that
// already started. The next cycle is decided on the current cycle's last bar,
// because the bass pickup needs the next cycle's first chord; a pick that arrives
// after that point waits one more cycle, still never mid-cycle.
//
// Re-evaluating this module mid-ride keeps the running schedule: it never assigns
// ~ppHarm, and the tunables below use the ~x = ~x ? default idiom.
//
// Events are always accessed with [\key], never dot syntax.

// --- Tunables ---
// The key (D-07): the one place it lives. Chord roots in library files are
// semitones above this pitch class (9 = A). The scale is natural minor, relative
// to the key (D-05: the scale a chord tone may leave, exposed to Phase 8 melodies).
~ppKeyRoot = ~ppKeyRoot ? 9;
~ppKeyScale = ~ppKeyScale ? [0, 2, 3, 5, 7, 8, 10];
~ppPcNames = ~ppPcNames ? ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
// The pad: where its first chord sits, the MIDI window every voicing stays in
// (HARM-03), and the number of beats between its gate closing and the next chord.
~ppPadHome = ~ppPadHome ? [45, 48, 52];
~ppPadWindow = ~ppPadWindow ? [40, 64];
~ppPadGapBeats = ~ppPadGapBeats ? 1;
// The bass: the MIDI window for its pickup note.
~ppBassWindow = ~ppBassWindow ? [28, 52];
// How many song bars the memo keeps, and how many cycles the cycle log keeps.
~ppHarmKeepBars = ~ppHarmKeepBars ? 64;
~ppHarmLogCap = ~ppHarmLogCap ? 256;
// Auto (D-08, D-10): how many bars Auto holds one progression, as [low, high] (a
// whole number of cycles that adds up to about this many), the seed that makes the
// order of an engine's rides replayable, and how many past picks Auto remembers.
~ppAutoHoldBars = ~ppAutoHoldBars ? [32, 64];
~ppAutoSeed = ~ppAutoSeed ? (Date.getDate.rawSeconds % 1000000).asInteger;
~ppAutoHistoryCap = 8;

// --- Chords ---
// A chord record: (rootPc:, intervals:, pcs:, name:, extraPcs:). rootPc and pcs
// are real pitch classes (0 = C), already moved into the key. Takes a validated
// chord-data Event (root plus quality or intervals).
~ppChordExpand = { |c|
	var intervals, rootPc, pcs, name;
	intervals = if (c[\intervals].notNil) { c[\intervals] } { ~ppChordTypes[c[\quality]] };
	rootPc = (~ppKeyRoot + c[\root]) % 12;
	pcs = intervals.collect { |i| (rootPc + i) % 12 };
	name = ~ppPcNames[rootPc] ++ if (intervals == ~ppChordTypes[\min]) {
		"m"
	} {
		if (intervals == ~ppChordTypes[\maj]) { "" } { "(" ++ intervals.join(",") ++ ")" }
	};
	(rootPc: rootPc, intervals: intervals, pcs: pcs, name: name, extraPcs: [])
};

~ppChordSame = { |a, b|
	(a[\rootPc] == b[\rootPc]) and: { a[\intervals] == b[\intervals] }
};

// Classic is "Am every bar" (D-07). The frozen classic pad plays a passing F (pc 5)
// on odd song bars, which is not a tone of Am. extraPcs lets the chord-follow check
// allow exactly that note for this implicit chord and nowhere else. Do not "fix"
// it: classic.scd is frozen and the golden depends on that F (RESEARCH Pitfall 3).
~ppClassicChord = ~ppChordExpand.((root: 0, quality: \min));
~ppClassicChord[\extraPcs] = [5];

// --- Cycles ---
// stem, module -> a cycle record:
//   (stem:, mod:, classic:, spans:, len:, names:)
// spans are the chord changes: (chord:, bars:, start:) with adjacent identical
// chords merged (the pad re-attacks only on a real change, D-14). len is the cycle
// length in bars. names is every chord as written in the file, one name per chord
// entry, unmerged (D-11), for the post window line.
// A nil module or one without chords is one bar of the implicit classic chord.
~ppHarmCycle = { |stem, mod|
	var classic, spans, namesList, pos, bpc, last, chord, bars;
	classic = (stem == \classic);
	if (mod.isNil or: { mod[\chords].isNil }) {
		(
			stem: stem, mod: mod, classic: classic,
			spans: [(chord: ~ppClassicChord, bars: 1, start: 0)],
			len: 1, names: ~ppClassicChord[\name]
		)
	} {
		spans = List.new;
		namesList = List.new;
		pos = 0;
		bpc = mod[\barsPerChord] ? 1;
		mod[\chords].do { |c|
			chord = ~ppChordExpand.(c);
			bars = c[\bars] ? bpc;
			namesList.add(chord[\name]);
			last = if (spans.size > 0) { spans[spans.size - 1] } { nil };
			if (last.notNil and: { ~ppChordSame.(last[\chord], chord) }) {
				last[\bars] = last[\bars] + bars;
			} {
				spans.add((chord: chord, bars: bars, start: pos));
			};
			pos = pos + bars;
		};
		(
			stem: stem, mod: mod, classic: classic,
			spans: spans.asArray, len: pos, names: namesList.join(" ")
		)
	}
};

// --- Pad voicing (HARM-03) ---
// chord, previous voicing -> the close-position voicing of the chord nearest the
// previous one, every note inside ~ppPadWindow. Candidates: every inversion (the
// sorted chord tones with the lowest i tones raised an octave) at every octave.
// Cost: summed note-by-note distance to prev. Ties go to the voicing whose mean is
// nearest the home voicing's mean (so the pad never drifts down over many cycles),
// then to the lower one. prev nil means ~ppPadHome. Returns a sorted Array.
~ppNearestVoicing = { |chord, prev|
	var base, homeMean, best = nil, bestCost = inf, bestDist = inf, bestSum = inf;
	prev = prev ? ~ppPadHome;
	homeMean = ~ppPadHome.sum / ~ppPadHome.size;
	base = chord[\intervals].collect { |i| chord[\rootPc] + i };
	chord[\intervals].size.do { |inv|
		var tones = if (inv == 0) { base } { base.copyToEnd(inv) ++ (base.copyFromStart(inv - 1) + 12) };
		8.do { |k|
			var v = tones + (12 * k), cost, dist, sum;
			if ((v.first >= ~ppPadWindow[0]) and: { v.last <= ~ppPadWindow[1] }) {
				cost = 0;
				v.do { |n, i| cost = cost + (n - prev[min(i, prev.size - 1)]).abs };
				sum = v.sum;
				dist = ((sum / v.size) - homeMean).abs;
				if ((cost < bestCost)
					or: { (cost == bestCost) and: { (dist < bestDist) or: { (dist == bestDist) and: { sum < bestSum } } } }) {
					best = v;
					bestCost = cost;
					bestDist = dist;
					bestSum = sum;
				};
			};
		};
	};
	// Every chord has a voicing somewhere in 24 semitones; the home voicing is the
	// last resort so a pad row is never empty.
	best ? ~ppPadHome
};

// --- Entries ---
// cycle, bar inside the cycle, previous voicing, first chord of the following
// cycle (nil means this cycle repeats) -> the entry every layer reads for one bar:
//   (progression:, mod:, classic:, chord:, nextChord:, changesNext:, chordBar:,
//    chordBars:, cycleBar:, cycleLen:, voicing:, scale:)
// chordBar is the bar's index inside its span (0 = the chord starts here);
// changesNext compares chords, so a cycle that ends and restarts on the same chord
// gets the bass's third rather than a repeated root.
~ppHarmEntry = { |cycle, cycleBar, prevVoicing, nextFirstChord|
	var spanAt, span, nextSpan, nextChord, chord, chordBar, voicing, scale;
	spanAt = { |b|
		cycle[\spans].detect { |sp| (b >= sp[\start]) and: { b < (sp[\start] + sp[\bars]) } }
	};
	span = spanAt.(cycleBar);
	chord = span[\chord];
	chordBar = cycleBar - span[\start];
	nextChord = if ((cycleBar + 1) < cycle[\len]) {
		nextSpan = spanAt.(cycleBar + 1);
		nextSpan[\chord]
	} {
		nextFirstChord ? cycle[\spans][0][\chord]
	};
	voicing = if (chordBar == 0) { ~ppNearestVoicing.(chord, prevVoicing) } { prevVoicing ? ~ppPadHome };
	scale = (~ppKeyScale.collect { |i| (~ppKeyRoot + i) % 12 } ++ chord[\pcs]).asSet.asArray.sort;
	(
		progression: cycle[\stem], mod: cycle[\mod], classic: cycle[\classic],
		chord: chord, nextChord: nextChord, changesNext: ~ppChordSame.(chord, nextChord).not,
		chordBar: chordBar, chordBars: span[\bars], cycleBar: cycleBar, cycleLen: cycle[\len],
		voicing: voicing, scale: scale
	)
};

// --- Auto (D-08, D-09, D-10, D-11) ---
// The state lives in ~ppHarm[\auto] = (current:, holdLeft:, history:, picks:), so a
// new run (Start, restart) begins a new rotation, always on classic (D-09).

// -> the candidates for Auto's next pick, sorted by name (Dictionary order is not
// stable): every registered progression with a valid name whose file is in the
// current library root and that has not failed 3 times while playing.
~ppAutoCandidates = {
	var errs, names;
	errs = if (~ppRenderErrors.notNil) { ~ppRenderErrors[\progressions] } { nil };
	errs = errs ? ();
	names = ~ppLib[\progressions].keys.asArray.collect { |k| k.asString }.sort;
	names.select { |n|
		~ppStemValid.(n)
			and: { File.exists(~ppLibPath.(\progressions, n)) }
			and: { (errs[n.asSymbol] ? 0) < 3 }
	}.collect { |n| n.asSymbol }
};

// cycleStart -> the stem Auto plays for the cycle that starts there. Called by
// ~ppHarmDecide on the previous cycle's last bar (or at a run start), so a change
// only ever lands at the end of a cycle.
//  - Engage (no current, or a named pick moved the music since): adopt the
//    progression that is ending, or classic at a run start (D-09), and hold it for
//    a fresh hold. This is the planner decision for RESEARCH Open Question 4.
//  - Hold: keep the current progression while hold cycles are left.
//  - Pick: a seeded random choice among the candidates, never the current one and
//    never one of the last two played (D-10); then a new hold.
// The hold is H = max(1, round(rrand(lo, hi) / cycleLen)) whole cycles. Randomness
// is only the calling thread's seed, set right before each draw; the layers'
// generators re-seed their own thread, so nothing leaks (RESEARCH Pitfall 6).
~ppHarmAutoNext = { |cycleStart|
	var a, ending, endStem, cur, cands, recent, pool, stem, seedFor, holdFor;
	a = ~ppHarm[\auto];
	ending = ~ppHarm[\cycle];
	endStem = if (ending.notNil) { ending[\stem] } { nil };
	seedFor = {
		thisThread.randSeed = ((~ppAutoSeed * 1000003) + (a[\picks] * 7919) + 104729) & 0x7FFFFFFF;
		a[\picks] = a[\picks] + 1;
	};
	holdFor = { |st|
		var len = ~ppHarmCycle.(st, ~ppLib[\progressions][st])[\len];
		max(1, (rrand(~ppAutoHoldBars[0].asFloat, ~ppAutoHoldBars[1].asFloat) / len).round.asInteger)
	};
	cur = a[\current];
	cands = ~ppAutoCandidates.value;
	if (cur.isNil or: { cur != endStem }) {
		// Engage.
		stem = endStem ? \classic;
		seedFor.value;
		a[\holdLeft] = holdFor.(stem) - 1;
		a[\current] = stem;
		a[\history].add(stem);
		while { a[\history].size > ~ppAutoHistoryCap } { a[\history].removeAt(0) };
		~ppAutoPrefetch.value;
	} {
		if ((a[\holdLeft] > 0) and: { cands.includes(cur) }) {
			a[\holdLeft] = a[\holdLeft] - 1;
			stem = cur;
		} {
			// Pick. asArray.keep(-2), never List.last(2) (RESEARCH Pitfall 7).
			recent = a[\history].asArray.keep(-2);
			pool = cands.reject { |c| (c == cur) or: { recent.includes(c) } };
			if (pool.isEmpty) { pool = cands.reject { |c| c == cur } };
			seedFor.value;
			stem = if (pool.isEmpty) { cur } { pool.choose };
			a[\holdLeft] = holdFor.(stem) - 1;
			a[\current] = stem;
			a[\history].add(stem);
			while { a[\history].size > ~ppAutoHistoryCap } { a[\history].removeAt(0) };
			~ppAutoPrefetch.value;
		};
	};
	stem
};

// cycleStart -> the cycle that starts at that song bar, with \start set. The
// selected progression when it is a loaded Symbol other than \auto; on \auto the
// progression Auto chose (~ppHarmAutoNext); anything else (nil, not loaded) is
// classic. The module is captured from ~ppLib now. A planning error is logged and
// classic harmony plays instead.
~ppHarmDecide = { |cycleStart|
	var sel, stem = \classic, mod, cyc, auto;
	sel = if (~ppSel.notNil) { ~ppSel[\progressions] } { nil };
	mod = if (~ppLib.notNil) { ~ppLib[\progressions][\classic] } { nil };
	auto = (sel == \auto) and: { ~ppHarm.notNil and: { ~ppHarm[\auto].notNil and: { ~ppLib.notNil } } };
	if (auto) {
		stem = try {
			~ppHarmAutoNext.(cycleStart)
		} { |err|
			~ppLog.("PedalPulse ERROR: Auto progression pick failed: % -- playing classic".format(err.errorString));
			\classic
		};
		if (~ppLib[\progressions][stem].isNil) { stem = \classic };
		mod = ~ppLib[\progressions][stem];
	} {
		if (sel.isKindOf(Symbol) and: { (sel != \auto) and: { ~ppLib.notNil and: { ~ppLib[\progressions][sel].notNil } } }) {
			stem = sel;
			mod = ~ppLib[\progressions][sel];
		};
		// A named pick ends Auto's hold: a later Auto adopts what plays then.
		if (~ppHarm.notNil and: { ~ppHarm[\auto].notNil }) { ~ppHarm[\auto][\current] = nil };
	};
	cyc = try {
		~ppHarmCycle.(stem, mod)
	} { |err|
		~ppLog.("PedalPulse ERROR: progression % could not be planned: % -- playing classic harmony".format(stem, err.errorString));
		~ppHarmCycle.(\classic, if (~ppLib.notNil) { ~ppLib[\progressions][\classic] } { nil })
	};
	cyc[\start] = cycleStart;
	cyc
};

// --- The memo ---
// ~ppHarm is the running schedule: (sig:, entries:, last:, cycle:, pending:,
// voicing:, cycleLog:, lastStem:, auto:). Only this module and ~ppHarmReset write it.
// A restart (main.scd's ~ppStart and teardown) calls ~ppHarmReset so a Start
// always begins a new run at the selected progression's first chord.
~ppHarmReset = { ~ppHarm = nil };

// An entry of the classic cycle, for a request the memo cannot answer (a song bar
// older than the memo keeps) and as the safe fallback in the renderer.
~ppHarmClassicEntry = {
	var cyc = ~ppHarmCycle.(\classic, if (~ppLib.notNil) { ~ppLib[\progressions][\classic] } { nil });
	cyc[\start] = 0;
	~ppHarmEntry.(cyc, 0, ~ppPadHome, nil)
};

// bar, songBar -> the entry for that song bar of the current run. Builds strictly
// in order from last + 1 so cycle decisions land on cycle boundaries; a fresh run,
// or a gap of more than ~ppHarmKeepBars, starts the schedule at songBar itself and
// never backfills from 0. Keeps at most ~ppHarmKeepBars song bars.
~ppHarmonyFor = { |bar, songBar|
	var clock, base, h, n, from, cyc, cycleBar, nextFirst, entry, stem;
	clock = thisThread.clock;
	base = bar - songBar;
	h = ~ppHarm;
	if (h.isNil or: { (h[\sig][0] !== clock) or: { h[\sig][1] != base } }) {
		h = (
			sig: [clock, base], entries: Dictionary.new, last: nil, cycle: nil,
			pending: nil, voicing: nil, cycleLog: List.new, lastStem: nil,
			auto: (current: nil, holdLeft: 0, history: List.new, picks: 0)
		);
		~ppHarm = h;
	};
	if (h[\entries].includesKey(songBar)) {
		h[\entries][songBar]
	} {
		if (h[\last].notNil and: { songBar <= h[\last] }) {
			// Older than the memo keeps (or before the run's start).
			~ppHarmClassicEntry.()
		} {
			from = if (h[\last].isNil) { songBar } { h[\last] + 1 };
			if (h[\last].notNil and: { (songBar - h[\last]) > ~ppHarmKeepBars }) {
				h[\entries] = Dictionary.new;
				h[\cycle] = nil;
				h[\pending] = nil;
				from = songBar;
			};
			(from..songBar).do { |b|
				// Which cycle does bar b belong to?
				if (h[\cycle].isNil) {
					h[\cycle] = ~ppHarmDecide.(b);
				} {
					if (b == (h[\cycle][\start] + h[\cycle][\len])) {
						// An explicit if: `?` evaluates its argument eagerly, and a decision now
						// has side effects (Auto's hold and history).
						h[\cycle] = if (h[\pending].notNil) { h[\pending] } { ~ppHarmDecide.(b) };
						h[\pending] = nil;
					};
				};
				cyc = h[\cycle];
				cycleBar = b - cyc[\start];
				if (cycleBar == 0) {
					h[\cycleLog].add((start: b, stem: cyc[\stem], len: cyc[\len]));
					while { h[\cycleLog].size > ~ppHarmLogCap } { h[\cycleLog].removeAt(0) };
					if (cyc[\stem] != h[\lastStem]) {
						~ppLog.("PedalPulse: progression %: %".format(cyc[\stem], cyc[\names]));
						h[\lastStem] = cyc[\stem];
					};
				};
				// On the cycle's last bar the next cycle is decided first: the bass
				// pickup needs its first chord.
				nextFirst = nil;
				if (cycleBar == (cyc[\len] - 1)) {
					h[\pending] = ~ppHarmDecide.(b + 1);
					nextFirst = h[\pending][\spans][0][\chord];
				};
				entry = ~ppHarmEntry.(cyc, cycleBar, h[\voicing], nextFirst);
				h[\entries][b] = entry;
				h[\voicing] = entry[\voicing];
				h[\last] = b;
				h[\entries].removeAt(b - ~ppHarmKeepBars);
			};
			h[\entries][songBar]
		}
	}
};

// songBar -> the stored entry, or nil. Never builds. For the tests.
~ppHarmonyEntry = { |songBar|
	if (~ppHarm.isNil) { nil } { ~ppHarm[\entries][songBar] }
};

// The cycle log of the current run as an Array of (start:, stem:, len:); [] when
// there is no run. For the tests.
~ppHarmCycleLog = {
	if (~ppHarm.isNil) { [] } { ~ppHarm[\cycleLog].asArray }
};

// --- Chord following for the melodic layers (D-01, D-02, D-03) ---
// Notes only: dur, amp and legato never change. A melody keeps writing its figure
// against the Am chord-tone ladder (A C E in every octave); the core re-reads each
// note's ladder position off the current chord's root, third and fifth. Passing
// tones therefore become chord tones, and the classic A3 C4 E4 C4 figure becomes
// the chord's root, third, fifth, third.

// The octave of the chord's root: the triad's mean is nearest Am's (60.333), ties
// to the lower root.
~ppChordCenterRoot = { |chord|
	var best = nil, bestDist = inf, tri;
	tri = chord[\intervals].copyRange(0, 2);
	[36, 48, 60, 72].do { |b|
		var root = b + chord[\rootPc], dist;
		dist = ((root + (tri.sum / 3)) - 60.3333333333).abs;
		if (dist < (bestDist - 1e-9)) {
			best = root;
			bestDist = dist;
		};
	};
	best
};

// x -> the same ladder position on the chord. The Am ladder note nearest x (ties
// to the lower note) gives a ladder index k (three steps per octave); the result
// is the chord's tone k, with floored arithmetic so negative k works.
~ppFollowNote = { |x, chord|
	var o, bestNote = nil, bestDist = inf, bestK = 0, ladder = [0, 3, 7], center, iv;
	o = ((x - 57) / 12).floor.asInteger;
	((o - 1)..(o + 1)).do { |oct|
		3.do { |i|
			var note = 57 + ladder[i] + (12 * oct), dist = (note - x).abs;
			if (dist < bestDist) {
				bestNote = note;
				bestDist = dist;
				bestK = (3 * oct) + i;
			};
		};
	};
	center = ~ppChordCenterRoot.(chord);
	iv = chord[\intervals];
	center + iv[bestK % 3] + (12 * (bestK / 3).floor.asInteger)
};

// rows -> the rows with every note followed onto the chord. \rest stays, a Number
// is mapped, an Array (a chord) is mapped element by element.
~ppFollowRows = { |rows, chord|
	rows.collect { |r|
		var n = r[0];
		if (n === \rest) {
			r
		} {
			if (n.isKindOf(Array)) {
				[n.collect { |x| ~ppFollowNote.(x, chord) }, r[1], r[2], r[3]]
			} {
				[~ppFollowNote.(n, chord), r[1], r[2], r[3]]
			}
		}
	}
};

// --- Core default bass and pad (D-12, D-13, D-14) ---
// A progression file with chord data and no bass or pad generator is played by
// these; a file may still define its own to override the core's part.

// The chord's root as a bass note: the A1-based octave (MIDI 33 to 44).
~ppBassRoot = { |chord|
	33 + ((chord[\rootPc] - 33) % 12)
};

// The pickup note on the last eighth when the chord changes at the next bar: among
// the current chord's tones, the pitch class closest (circular semitone distance)
// to the next chord's root, the current root counting 0.5 more. It is played in
// the octave nearest the next chord's bass root inside ~ppBassWindow, ties to the
// lower note. Always a tone of the current chord.
~ppBassPickup = { |chord, next|
	var bestPc = nil, bestDist = inf, target, best = nil, bestGap = inf;
	chord[\pcs].do { |pc, i|
		var d = (pc - next[\rootPc]) % 12, dist;
		dist = min(d, 12 - d) + if (i == 0) { 0.5 } { 0 };
		if (dist < bestDist) {
			bestDist = dist;
			bestPc = pc;
		};
	};
	target = ~ppBassRoot.(next);
	(~ppBassWindow[0]..~ppBassWindow[1]).do { |m|
		var gap = (m - target).abs;
		if (((m % 12) == bestPc) and: { gap < bestGap }) {
			best = m;
			bestGap = gap;
		};
	};
	best
};

// Offbeat eighths on the chord's root, as in classic; the last eighth is the
// pickup toward the next chord when the chord changes at the next bar, and the
// chord's third otherwise.
~ppDefaultBass = { |plan, state|
	var chord = plan[\chord], root, last;
	root = ~ppBassRoot.(chord);
	last = if (plan[\changesNext] == true) {
		~ppBassPickup.(chord, plan[\nextChord])
	} {
		root + chord[\intervals][1]
	};
	[
		[\rest, 0.5, 0.1, 0.8],
		[root, 0.5, 0.1, 0.8],
		[\rest, 0.5, 0.1, 0.8],
		[root, 0.5, 0.1, 0.8],
		[\rest, 0.5, 0.1, 0.8],
		[root, 0.5, 0.1, 0.8],
		[\rest, 0.5, 0.1, 0.8],
		[last, 0.5, 0.1, 0.8]
	]
};

// One attack per chord, held across the chord in the voicing nearest the previous
// one. The row is 4 beats long and the later bars of a longer chord are a silent
// bar, so the legato spans the chord. The gate closes at least ~ppPadGapBeats
// beats before the next chord (RESEARCH Pitfall 4): legato is the smaller of 0.9
// x chordBars and chordBars - (gap / 4), i.e. 0.75 for a 1-bar chord, 1.75 for 2
// bars and 3.6 for 4. The frozen pad voice's 1.2 s release still fades under the
// start of the next chord; that tail is judged by ear (Plan 05's listening check).
// This is the core's rule only: classic's frozen pad generator keeps legato 0.9.
~ppDefaultPad = { |plan, state|
	var legato;
	if (plan[\chordBar] == 0) {
		legato = min(0.9 * plan[\chordBars], plan[\chordBars] - (~ppPadGapBeats / 4));
		[[plan[\voicing], 4, 0.06, legato]]
	} {
		[[\rest, 4, 0, 1]]
	}
};

\ppHarmony
