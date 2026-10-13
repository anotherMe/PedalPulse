// PedalPulse core: shared harmony (Phase 6, HARM-01 / HARM-03 / HARM-04).
//
// Loaded by main.scd (~ppLoadCore) at top level, after loader.scd and before
// render.scd. Server-free at load: definitions only. No Routine, no clock, no
// scheduling anywhere in this module (ENG-05); it plays nothing.
//
// Design: a memoized per-bar entry that the layers PULL. There is no mutable
// "current chord" variable that a layer could read before or after another layer
// moved it. Every layer (bass, arp, pad, lead and, since Phase 7, the three drum
// layers) asks ~ppHarmonyFor for the entry of its own (run, song bar); the first
// layer to ask builds it and the rest read the same stored Event, so all layers
// of a bar see one chord and one palette by construction. This also resolves the
// STATE.md same-beat spike (layers whose bar-start events land on the same beat
// in any order).
//
// The entry also says which sound palette the bar uses (entry[\palette], Phase 7).
// It is decided once per (run, song bar), here, so a palette change lands on one
// bar line for all seven layers: the kick can never be on the old palette while
// the bass is already on the new one. ~ppHarmPaletteFor is the single place that
// decides it.
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
// ~ppAutoPicks counts every random draw since the interpreter started. It lives
// here, not in the per-run state, so Stop then Start continues the sequence
// instead of replaying the same order; a fresh interpreter with the same seed
// replays a heard order from the start.
~ppAutoHoldBars = ~ppAutoHoldBars ? [32, 64];
~ppAutoSeed = ~ppAutoSeed ? (Date.getDate.rawSeconds % 1000000).asInteger;
~ppAutoHistoryCap = 8;
~ppAutoPicks = ~ppAutoPicks ? 0;
// Palette Auto (Phase 7, D-05): how many song bars Auto holds one palette, as [low,
// high], and the draw counter of palette picks. ~ppPalAutoPicks is global for the
// same reason as ~ppAutoPicks (Stop then Start continues the sequence) and has its
// own seed salt, so palette draws never change the replayable progression order.
// Real timing, so nobody has to guess: minutes = bars x 4 / BPM. The hold of 80 to
// 128 bars is 2.9 to 5.7 minutes at 90 to 110 BPM (faster at a higher BPM). With
// Progression on Auto the change then waits for the next progression change, which
// adds about 25 bars on average and at most one 64-bar progression stay, so a
// palette plays about 4.7 to 5.7 minutes on average at 90 to 110 BPM (D-05's 4 to
// 6) and anywhere from about 2.9 to 8.5 minutes for a single palette. With a named
// progression the change waits for the end of its round: about 3 to 6 minutes.
~ppPalHoldBars = ~ppPalHoldBars ? [80, 128];
~ppPalAutoPicks = ~ppPalAutoPicks ? 0;

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
// The state lives in ~ppHarm[\auto] = (current:, holdLeft:, history:), so a new
// run (Start, restart) begins a new rotation, always on classic (D-09). The draw
// counter ~ppAutoPicks is not part of it, so each run draws different picks.

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
		thisThread.randSeed = ((~ppAutoSeed * 1000003) + (~ppAutoPicks * 7919) + 104729) & 0x7FFFFFFF;
		~ppAutoPicks = ~ppAutoPicks + 1;
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

// --- Palette stage (Phase 7, PAL-02, PAL-03, D-05 to D-11) ---
// Palette Auto first (D-05 to D-08), then ~ppHarmPaletteFor, the single place that
// decides the bar's palette (named pick: D-09, D-10, D-11).
// The state lives in the run: ~ppHarm[\palAuto] = (current:, holdLeft:, history:,
// soloNoted:), so a Start begins a new rotation. The draw counter ~ppPalAutoPicks
// is not part of it. Unlike progression Auto, palette Auto does not open on
// classic: its first pick is random (D-08).

// -> the palettes Auto may pick, sorted by name (Dictionary order is not stable):
// every registered palette with a valid name whose file is in the current library
// root. classic stays in (D-08). Palettes never fail at render time, so there is no
// render-error filter as for progressions.
~ppPalAutoCandidates = {
	var names;
	names = ~ppLib[\palettes].keys.asArray.collect { |k| k.asString }.sort;
	names.select { |n|
		~ppStemValid.(n) and: { File.exists(~ppLibPath.(\palettes, n)) }
	}.collect { |n| n.asSymbol }
};

// b, cyc, cycleBar, progChanged -> the stem Auto plays for song bar b. Called once
// per (run, song bar) by ~ppHarmPaletteFor, in bar order.
//  - chapter: progChanged, a cycle starts with a different progression than the last
//    one (true on a run's first bar). phraseLine: the cycle starts here and is at
//    least 4 bars long, or the bar is a multiple of 8 (classic's one-bar cycle would
//    otherwise allow a change on any bar, which is not a phrase boundary).
//  - Engage (no current: run start, Auto newly selected, or Auto after a named
//    pick): at the first bar that is a chapter or a phraseLine while no palette scan
//    is queued or running, draw from the candidates minus the palette playing
//    (~ppPalPlaying). Until then the music keeps the palette it plays (classic when
//    that one is not loaded), and each such bar queues a palette scan so new files
//    are found. This is explicit exception 1 to D-06, limited to a rotation's
//    opening pick and made for D-08's "random from the start": a run's first bar is
//    always a chapter, so after a Start with the files loaded the opening pick is on
//    a progression change anyway; it lands on a plain round start only on a cold
//    start (files still loading) or when Auto is selected mid-run. Auto picked after
//    a named lock does not adopt the locked palette: it draws a different one.
//  - Rotation: holdLeft counts down once per built bar (song bars, so Stop pauses
//    it, D-05). A change is due when it is <= 0 or the current palette is no longer
//    a candidate. With the progression selection \auto it lands only on a chapter
//    (D-06, exact: progression Auto always changes within its 32-64-bar stay when it
//    has another candidate, so there is no bar-count fallback). Explicit exception 2,
//    narrow: progression Auto but no progression other than the playing one can be
//    picked (evaluated only on cycle-start bars while a change is due), so progression
//    Auto can never change; the change then lands on a phraseLine as with a named
//    progression (D-07) and the post window says so once per run. With a named
//    progression it lands on a chapter or a phraseLine (D-07).
//  - Pick: candidates minus the current and the last two played (asArray.keep(-2),
//    never List.last(2)); if empty, minus the current only; if still empty, keep the
//    current with a new hold. The hold is rrand(lo, hi).round bars. Randomness is
//    only the calling thread's seed, set right before each draw (the pick with
//    choose, then the hold with rrand); the layers' generators re-seed their own
//    thread, so nothing leaks.
~ppPalAutoNext = { |b, cyc, cycleBar, progChanged|
	var a, sel, cands, playing, cur, chapter, phraseLine, stem, due, lands, alone, recent, pool;
	var keepPlaying, drawHold, seedFor, remember, pickFrom;
	a = ~ppHarm[\palAuto];
	if (a.isNil) {
		a = (current: nil, holdLeft: 0, history: List.new, soloNoted: false);
		~ppHarm[\palAuto] = a;
	};
	sel = if (~ppSel.notNil) { ~ppSel[\progressions] } { nil };
	playing = ~ppPalPlaying;
	chapter = (progChanged == true);
	phraseLine = (cycleBar == 0) and: { (cyc[\len] >= 4) or: { (b % 8) == 0 } };
	cands = ~ppPalAutoCandidates.value;
	cur = a[\current];
	// The palette that keeps playing while nothing is drawn.
	keepPlaying = {
		if (playing.notNil and: { ~ppLib[\palettes][playing].notNil }) { playing } { \classic }
	};
	seedFor = {
		thisThread.randSeed = ((~ppAutoSeed * 1000003) + (~ppPalAutoPicks * 7919) + 15485863) & 0x7FFFFFFF;
		~ppPalAutoPicks = ~ppPalAutoPicks + 1;
	};
	drawHold = {
		max(1, rrand(~ppPalHoldBars[0].asFloat, ~ppPalHoldBars[1].asFloat).round.asInteger)
	};
	remember = { |st|
		a[\history].add(st);
		while { a[\history].size > ~ppAutoHistoryCap } { a[\history].removeAt(0) };
	};
	// pool -> the drawn stem (an empty pool keeps the current with a new hold).
	pickFrom = { |from|
		var st;
		seedFor.value;
		if (from.isEmpty) {
			st = cur;
			a[\holdLeft] = drawHold.value;
		} {
			st = from.choose;
			a[\holdLeft] = drawHold.value;
			a[\current] = st;
			remember.(st);
		};
		~ppAutoPrefetch.(\palettes);
		st
	};
	if (cur.isNil) {
		// Engage.
		stem = keepPlaying.value;
		if (chapter or: { phraseLine }) {
			if (~ppAutoBusy.(\palettes).not) {
				pool = cands.reject { |c| c == playing };
				if (pool.isEmpty) {
					// Nothing else to play yet: look for new files.
					~ppAutoPrefetch.(\palettes);
				} {
					stem = pickFrom.(pool);
				};
			};
		};
	} {
		// Hold, then rotate.
		a[\holdLeft] = a[\holdLeft] - 1;
		due = (a[\holdLeft] <= 0) or: { cands.includes(cur).not };
		stem = cur;
		if (due) {
			lands = false;
			if (sel == \auto) {
				if (chapter) {
					lands = true;
				} {
					if (cycleBar == 0) {
						// Exception 2: can progression Auto ever change?
						alone = ~ppAutoCandidates.value.reject { |c| c == cyc[\stem] }.isEmpty;
						if (alone) {
							if (a[\soloNoted] != true) {
								a[\soloNoted] = true;
								~ppLog.("PedalPulse: only one progression can play on Auto, so Auto palettes change at the end of its round");
							};
							lands = phraseLine;
						};
					};
				};
			} {
				lands = chapter or: { phraseLine };
			};
			if (lands) {
				recent = a[\history].asArray.keep(-2);
				pool = cands.reject { |c| (c == cur) or: { recent.includes(c) } };
				if (pool.isEmpty) { pool = cands.reject { |c| c == cur } };
				stem = pickFrom.(pool);
			};
		};
	};
	stem
};

// b, cyc, cycleBar, progChanged -> the palette stem the song bar b plays. On \auto
// the Auto rotation above; otherwise the selected palette when it is a loaded
// Symbol; anything else (nil, not loaded) is classic. A named pick also ends the
// Auto state, so a later Auto engages fresh. A stem that is not registered becomes
// classic. It reads ~ppSel and ~ppLib defensively.
~ppHarmPaletteFor = { |b, cyc, cycleBar, progChanged|
	var sel, stem, registered;
	sel = if (~ppSel.notNil) { ~ppSel[\palettes] } { nil };
	registered = { |st|
		st.notNil and: { ~ppLib.notNil and: { ~ppLib[\palettes].notNil and: { ~ppLib[\palettes][st].notNil } } }
	};
	if (sel == \auto) {
		stem = try {
			~ppPalAutoNext.(b, cyc, cycleBar, progChanged)
		} { |err|
			var keep = if (registered.(~ppPalPlaying)) { ~ppPalPlaying } { \classic };
			~ppLog.("PedalPulse ERROR: Auto palette pick failed: % -- keeping %".format(err.errorString, keep));
			keep
		};
		if (registered.(stem).not) { stem = \classic };
	} {
		if (~ppHarm.notNil and: { ~ppHarm[\palAuto].notNil }) { ~ppHarm[\palAuto][\current] = nil };
		stem = if (sel.isKindOf(Symbol) and: { registered.(sel) }) { sel } { \classic };
	};
	stem
};

// --- The memo ---
// ~ppHarm is the running schedule: (sig:, entries:, last:, cycle:, pending:,
// voicing:, cycleLog:, lastStem:, auto:, lastPalette:, palLog:, palAuto:). Only this module and
// ~ppHarmReset write it.
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
	var clock, base, h, n, from, cyc, cycleBar, nextFirst, entry, stem, progChanged, palStem, palMod;
	clock = thisThread.clock;
	base = bar - songBar;
	h = ~ppHarm;
	if (h.isNil or: { (h[\sig][0] !== clock) or: { h[\sig][1] != base } }) {
		h = (
			sig: [clock, base], entries: Dictionary.new, last: nil, cycle: nil,
			pending: nil, voicing: nil, cycleLog: List.new, lastStem: nil,
			auto: (current: nil, holdLeft: 0, history: List.new),
			lastPalette: nil, palLog: List.new,
			palAuto: (current: nil, holdLeft: 0, history: List.new, soloNoted: false)
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
				// A cycle start whose progression differs from the last one: a "new
				// chapter" (read before lastStem moves, for the palette stage below).
				progChanged = (cycleBar == 0) and: { cyc[\stem] != h[\lastStem] };
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
				// The bar's palette, decided once here for every layer (D-10).
				palStem = try {
					~ppHarmPaletteFor.(b, cyc, cycleBar, progChanged)
				} { |err|
					~ppLog.("PedalPulse ERROR: palette for bar % failed: % -- playing classic".format(b, err.errorString));
					\classic
				};
				entry[\palette] = palStem;
				if (palStem != h[\lastPalette]) {
					palMod = if (~ppLib.notNil and: { ~ppLib[\palettes].notNil }) { ~ppLib[\palettes][palStem] } { nil };
					~ppLog.("PedalPulse: palette %: %".format(palStem, if (palMod.notNil) { palMod[\desc] ? "" } { "" }));
					h[\lastPalette] = palStem;
					h[\palLog].add((bar: b, stem: palStem));
					while { h[\palLog].size > ~ppHarmLogCap } { h[\palLog].removeAt(0) };
				};
				// The palette sounding now (palette Auto and the meter read it).
				~ppPalPlaying = palStem;
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

// The palette log of the current run as an Array of (bar:, stem:), one entry per
// change (the first built bar of the run included); [] when there is no run. Bars
// are song bars. For the tests.
~ppHarmPaletteLog = {
	if (~ppHarm.isNil) { [] } { ~ppHarm[\palLog].asArray }
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
// these; a file may still define its own to override the core's pad, and (since
// Phase 7, D-02) its bass only while the classic palette plays: the bar's palette
// decides the bass rhythm, see "Bass styles" below.

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

// The bass note that ends the bar, one rule for every bass style so they cannot
// drift apart: the pickup toward the next chord when the chord changes at the next
// bar, the chord's third otherwise.
~ppBassLast = { |plan|
	var chord = plan[\chord];
	if (plan[\changesNext] == true) {
		~ppBassPickup.(chord, plan[\nextChord])
	} {
		~ppBassRoot.(chord) + chord[\intervals][1]
	}
};

// Offbeat eighths on the chord's root, as in classic; the last eighth is the
// pickup toward the next chord when the chord changes at the next bar, and the
// chord's third otherwise.
~ppDefaultBass = { |plan, state|
	var chord = plan[\chord], root, last;
	root = ~ppBassRoot.(chord);
	last = ~ppBassLast.(plan);
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

// --- Bass styles (Phase 7, D-02) ---
// A palette file may name its bass rhythm with the optional key bassStyle (the
// names are ~ppBassStyleNames in validate.scd). Each style is a plain bass
// generator { |plan, state| } for the bar's chord and keeps the Phase 6 rules: every
// sounding note is a tone of the chord, the first sounding note is the chord's
// root, and the last sounding note is ~ppBassLast (the pickup toward the next chord
// when it changes at the next bar, the chord's third otherwise). The styles keep no
// state.
//   eighths     offbeat eighths on the root (the core default bass itself)
//   sixteenths  rolling sixteenths, a rest on each beat's first sixteenth (12 notes)
//   octave      offbeat eighths: root, root an octave up, root, last
// Who plays the bass since Phase 7: the classic palette plays the progression's own
// bass (its generator, else ~ppDefaultBass for chord data), every other palette
// plays its style under EVERY progression, the classic progression included (its
// implicit chord is A minor every bar). A progression's own bass generator (only
// classic.scd has one) is therefore heard only under the classic palette.
~ppBassStyles = (
	eighths: ~ppDefaultBass,
	sixteenths: { |plan, state|
		var root = ~ppBassRoot.(plan[\chord]), last = ~ppBassLast.(plan), rows = List.new;
		4.do { |beat|
			rows.add([\rest, 0.25, 0.1, 0.6]);
			3.do { |k|
				rows.add([if ((beat == 3) and: { k == 2 }) { last } { root }, 0.25, 0.1, 0.6]);
			};
		};
		rows.asArray
	},
	octave: { |plan, state|
		var root = ~ppBassRoot.(plan[\chord]), last = ~ppBassLast.(plan);
		[
			[\rest, 0.5, 0.1, 0.8],
			[root, 0.5, 0.1, 0.8],
			[\rest, 0.5, 0.1, 0.8],
			[root + 12, 0.5, 0.1, 0.8],
			[\rest, 0.5, 0.1, 0.8],
			[root, 0.5, 0.1, 0.8],
			[\rest, 0.5, 0.1, 0.8],
			[last, 0.5, 0.1, 0.8]
		]
	}
);

// palStem -> the bass generator of that palette: ~ppBassStyles[its bassStyle], or
// the eighths style when the key is missing, the stem is nil or the palette is not
// registered.
~ppBassStyleFor = { |palStem|
	var pal = nil, name = nil;
	if (palStem.notNil and: { ~ppLib.notNil } and: { ~ppLib[\palettes].notNil }) {
		pal = ~ppLib[\palettes][palStem];
	};
	if (pal.notNil) { name = pal[\bassStyle] };
	~ppBassStyles[name ? \eighths] ? ~ppDefaultBass
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
