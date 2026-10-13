// PedalPulse core: per-bar renderer (Phase 4, LIB-01 / LIB-02).
//
// Loaded by main.scd (~ppLoadCore) at top level. Server-free at load:
// definitions only. Every layer is one Pbindef whose Prout renders one bar at
// each bar start from the currently selected library module, so a change of
// selection always lands on a bar line.
//
// Frozen row contract. A generator { |plan, state| } returns one bar as an
// Array of [note, dur, amp, legato] rows. note is a Number, an Array of
// Numbers (a chord) or \rest; the durs sum to 4.0. plan is
// (bar:, songBar:, phraseBar:, role:), built by ~ppPlanFor. This is the seam
// later phases extend with optional keys; existing keys never change meaning.
// Phase 6 adds the optional harmony keys of a pitched role's plan: progression,
// chord, nextChord, changesNext, chordBar, chordBars, cycleBar, cycleLen, voicing
// and scale (core/harmony.scd explains each). Drum plans never carry them.
// Phase 7: every layer, the drums too, reads its voice from the bar's palette,
// entry[\palette] in the same memoized entry, so all seven layers change sound on
// the same bar line.
// Events are always accessed with [\key], never dot syntax.

// layer name -> role. A role is what a generator or a palette is asked for.
// The lead (D-04) is the 7th layer. Its pitched fallback is the same as the
// arp's: the module's generator, then classic's, then one silent bar. Classic
// has no lead, so under classic the lead plays rests (D-05).
~ppLayerRole = (ppKick: \kick, ppHat: \hat, ppClap: \clap, ppBass: \bass, ppArp: \arp, ppPad: \pad, ppLead: \lead);

// role -> number of sounding rows (note not \rest) rendered since the engine
// started; the Stop check reads it.
~ppRoleNotes = ~ppRoleNotes ? IdentityDictionary.new;

// The fixed drum grid is owned by the core, not by the library (a drum role
// has no category). Row: [note, dur, amp, legato]; the note column is unused
// (the shipped drums set no midinote, so the event default stands).
// Kick and hat set no amp in the shipped engine, so they got the default event
// amp 0.1, which overrides their SynthDef defaults; the clap set 0.25. Legato
// 0.8 is the event default. All of it is reproduced as it was, never "fixed"
// (D-02).
~ppDrumGrid = (
	kick: (rows: [[60, 1, 0.1, 0.8], [60, 1, 0.1, 0.8], [60, 1, 0.1, 0.8], [60, 1, 0.1, 0.8]], timingOffset: 0),
	hat: (rows: [[60, 1, 0.1, 0.8], [60, 1, 0.1, 0.8], [60, 1, 0.1, 0.8], [60, 1, 0.1, 0.8]], timingOffset: 0.5),  // offbeat 8th: the "and" of each beat
	clap: (rows: [[60, 2, 0.25, 0.8], [60, 2, 0.25, 0.8]], timingOffset: 1)  // beats 2 and 4
);

// role -> library category that supplies its generator.
~ppRoleCategory = (bass: \progressions, pad: \progressions, arp: \melodies, lead: \melodies);

// The one function that maps "what is selected" to a file stem: classic when
// nothing is selected, when the selection is \auto, or when the selected stem
// is not loaded.
~ppResolveStem = { |cat|
	var sel = if (~ppSel.notNil) { ~ppSel[cat] } { nil };
	if (sel.isNil or: { sel == \auto } or: { ~ppLib[cat][sel].isNil }) {
		\classic
	} {
		sel
	}
};

~ppModuleFor = { |cat|
	~ppLib[cat][~ppResolveStem.(cat)]
};

// The voice for a role: the palette's, falling back to classic's. stem is the
// bar's palette from the harmony entry (entry[\palette]); without one (a caller
// that has no entry) the current selection is resolved here, as before Phase 7.
~ppInstrumentFor = { |role, stem|
	var pal, fallback, inst;
	pal = if (stem.notNil) { ~ppLib[\palettes][stem] } { ~ppModuleFor.(\palettes) };
	if (pal.notNil and: { pal[\roles].notNil and: { pal[\roles][role].notNil } }) {
		inst = pal[\roles][role][\instrument];
	};
	if (inst.isNil) {
		fallback = ~ppLib[\palettes][\classic];
		if (fallback.notNil and: { fallback[\roles].notNil and: { fallback[\roles][role].notNil } }) {
			inst = fallback[\roles][role][\instrument];
		};
	};
	inst ? \default
};

// entry is the harmony entry of this bar (core/harmony.scd); without one the plan
// has the four frozen keys only, so a 3-argument caller keeps working.
~ppPlanFor = { |bar, songBar, role, entry|
	var plan = (bar: bar, songBar: songBar, phraseBar: songBar % 8, role: role);
	if (entry.notNil) {
		plan[\progression] = entry[\progression];
		plan[\chord] = entry[\chord];
		plan[\nextChord] = entry[\nextChord];
		plan[\changesNext] = entry[\changesNext];
		plan[\chordBar] = entry[\chordBar];
		plan[\chordBars] = entry[\chordBars];
		plan[\cycleBar] = entry[\cycleBar];
		plan[\cycleLen] = entry[\cycleLen];
		plan[\voicing] = entry[\voicing];
		plan[\scale] = entry[\scale];
	};
	plan
};

// --- Seeding (RESEARCH Pitfall 4) ---
// Every init and generator call is seeded from (song seed, song bar, role) with
// plain integer arithmetic, so restarting the song replays the same values bar
// for bar. Never Array.hash (it differs between processes); a Symbol's hash is
// stable. The shipped generators use no randomness; the formula is fixed here
// before Phase 8 starts logging seeds.
~ppSongSeed = ~ppSongSeed ? 0;
~ppSeedFor = { |songSeed, bar, role|
	((songSeed * 1000003) + (bar * 7919) + role.hash.abs) & 0x7FFFFFFF
};

// Per (category, stem) count of bars that fell back to classic since the file
// was last (re)loaded: category -> (stem -> count). The loader resets an entry
// on every successful load, so a reloaded file starts clean.
~ppRenderErrors = ~ppRenderErrors ? ();

// Run one generator for one bar under try: seed, call, check the rows. Returns
// (rows:, reason:) where reason is nil when the rows are valid.
~ppRunGenerator = { |gen, plan, state, role, songBar|
	var rows = nil, reason = nil;
	try {
		thisThread.randSeed = ~ppSeedFor.(~ppSongSeed, songBar, role);
		rows = gen.value(plan, state);
	} { |err|
		reason = "generator threw: %".format(err.errorString);
	};
	if (reason.isNil) { reason = ~ppRowsValid.(rows) };
	(rows: rows, reason: reason)
};

// Count and log one failed bar of a library file. At the third failure, if the
// file is still the selection, the category goes back to classic (never for
// classic itself).
~ppRenderFail = { |cat, mod, role, bar, reason|
	var stem, path, n;
	stem = mod[\name];
	path = mod[\path];
	~ppRenderErrors[cat] = ~ppRenderErrors[cat] ? ();
	n = (~ppRenderErrors[cat][stem] ? 0) + 1;
	~ppRenderErrors[cat][stem] = n;
	~ppLog.("PedalPulse ERROR: library file % % bar %: % -- playing classic for this bar".format(path, role, bar, reason));
	if ((n >= 3) and: { stem != \classic } and: { ~ppSel.notNil } and: { ~ppSel[cat] == stem }) {
		~ppSel[cat] = \classic;
		~ppLog.("PedalPulse ERROR: library file % failed 3 times -- % back to classic".format(path, cat));
	};
	nil
};

// Render one bar for a role: rows [instrument, note, dur, amp, legato] for a
// pitched role, [instrument, dur, amp, legato] for a drum role.
//
// Containment (LIB-04): init and the generator run under try and their rows are
// checked with ~ppRowsValid. On a throw or invalid rows this bar is rendered
// from the classic module instead (itself try-wrapped and checked; the last
// resort is one silent row), the failure is logged with the file's path and
// counted, and the third failure sends the category back to classic. A module
// that simply has no generator for the role uses classic's silently (that is
// not a failure).
//
// Harmony (Phase 6) and palette (Phase 7): every role pulls the memoized harmony
// entry for its own (bar, songBar) from core/harmony.scd, the drums too: they read
// only the bar's palette from it (drum plans never carry harmony keys). Bass and
// pad read the cycle's captured progression module (a pick never switches them
// mid-cycle), and
// a module with chord data and no generator for the role is played by the core's
// default bass or pad. Arp and lead rows are mapped onto the entry's chord (D-01,
// D-02) unless the entry is classic's (left untouched, byte for byte) or the
// melody's own generator declares ownHarmony: true (it reads plan[\chord] itself;
// rows that came from the classic fallback are always mapped).
//
// entry is optional: the layers call the 4-argument form and the renderer pulls
// it; a caller may pass one.
~ppRenderBar = { |role, songBar, bar, layerState, entry|
	var cat, mod, key, gen, res, inst, plan, out, drum, failure, classicMod, fb, fromOwn, palStem;
	// The entry first, for every role: it carries the bar's palette. A caller that
	// passes none (the layers) gets the memoized one; entries without a palette
	// (the strict chord check's explicit ones, ~ppHarmClassicEntry) fall back to
	// the current selection.
	if (entry.isNil) {
		entry = try {
			~ppHarmonyFor.(bar, songBar)
		} { |err|
			~ppLog.("PedalPulse ERROR: harmony for bar % failed: % -- classic harmony".format(bar, err.errorString));
			~ppHarmClassicEntry.()
		};
	};
	palStem = entry[\palette] ? ~ppResolveStem.(\palettes);
	inst = ~ppInstrumentFor.(role, palStem);
	drum = ~ppDrumGrid[role];
	if (drum.notNil) {
		out = drum[\rows].collect { |r| [inst, r[1], r[2], r[3]] };
		~ppRoleNotes[role] = (~ppRoleNotes[role] ? 0) + out.size;
		out
	} {
		cat = ~ppRoleCategory[role];
		classicMod = ~ppLib[cat][\classic];
		mod = if ((role == \bass) or: { role == \pad }) {
			entry[\mod] ? classicMod
		} {
			~ppModuleFor.(cat)
		};
		key = if (mod.notNil) { [mod[\name], mod[\rev]] } { nil };
		plan = ~ppPlanFor.(bar, songBar, role, entry);
		failure = nil;
		res = nil;
		fromOwn = false;
		// A different module (or a reload of the same one) starts with a fresh state.
		if (key != layerState[\moduleKey]) {
			layerState[\state] = ();
			layerState[\initError] = nil;
			if (mod.notNil and: { mod[\init].isFunction }) {
				try {
					thisThread.randSeed = ~ppSeedFor.(~ppSongSeed, songBar, role);
					mod[\init].value(layerState[\state]);
				} { |err|
					layerState[\initError] = "init threw: %".format(err.errorString);
				};
			};
			layerState[\moduleKey] = key;
		};
		if (layerState[\initError].notNil) {
			failure = layerState[\initError];
		} {
			gen = if (mod.notNil) { mod[role] } { nil };
			if (gen.isFunction.not and: { (role == \bass) or: { role == \pad } } and: { mod.notNil } and: { mod[\chords].notNil }) {
				// Chord data without its own part: the core plays it.
				gen = if (role == \bass) { ~ppDefaultBass } { ~ppDefaultPad };
			};
			if (gen.isFunction) {
				res = ~ppRunGenerator.(gen, plan, layerState[\state], role, songBar);
				if (res[\reason].notNil) { failure = res[\reason] } { fromOwn = true };
			};
		};
		if (failure.notNil) {
			~ppRenderFail.(cat, mod, role, bar, failure);
			res = nil;
			fromOwn = false;
		};
		if (res.isNil) {
			// Either this bar failed, or the module has no generator for the role:
			// play classic's (rests when classic has none either).
			gen = if (classicMod.notNil) { classicMod[role] } { nil };
			if (gen.isFunction) {
				fb = ~ppRunGenerator.(gen, plan, (), role, songBar);
				if (fb[\reason].isNil) { res = fb };
			};
		};
		out = if (res.notNil) { res[\rows] } { [[\rest, 4, 0, 1]] };
		// Arp and lead follow the bar's chord (not under classic's own harmony).
		if (((role == \arp) or: { role == \lead }) and: { entry[\classic] != true } and: { res.notNil }) {
			if ((fromOwn and: { mod[\ownHarmony] == true }).not) {
				out = try {
					~ppFollowRows.(out, entry[\chord])
				} { |err|
					~ppLog.("PedalPulse ERROR: chord following of % bar % failed: % -- silent bar".format(role, bar, err.errorString));
					[[\rest, 4, 0, 1]]
				};
			};
		};
		out = out.collect { |r| [inst] ++ r };
		~ppRoleNotes[role] = (~ppRoleNotes[role] ? 0) + out.count { |r| r[1] != \rest };
		out
	}
};

// (Re)build every layer in ~ppLayers that has a role. Pbindef(name) stays the
// handle main.scd and the tests play, stop and ask isPlaying.
~ppBuildLayers = {
	var env = currentEnvironment;
	~ppLayers.do { |name|
		var role = ~ppLayerRole[name];
		if (role.notNil) {
			var drum, columns, offset, silent;
			// Drum rows carry no note column (the shipped drums set no midinote).
			drum = ~ppDrumGrid[role];
			columns = if (drum.notNil) { [\instrument, \dur, \amp, \legato] } { [\instrument, \midinote, \dur, \amp, \legato] };
			offset = if (drum.notNil) { drum[\timingOffset] } { 0 };
			silent = if (drum.notNil) { [[\default, 4, 0, 1]] } { [[\default, \rest, 4, 0, 1]] };
			// Pbindef merges keys; clearing first drops keys of an older definition.
			Pbindef(name).clear;
			Pbindef(name,
				columns,
				Prout({ |inEvent|
					var songBar = 0, layerState = ();
					loop {
						var bar, rows;
						bar = (thisThread.beats / 4 + 1e-6).floor.asInteger;
						// The thread's environment is not guaranteed to be the
						// interpreter's, so run the renderer inside the captured one.
						rows = try {
							env.use { ~ppRenderBar.(role, songBar, bar, layerState) }
						} { |err|
							env.use { ~ppLog.("PedalPulse ERROR: render of % failed: %".format(role, err.errorString)) };
							silent
						};
						inEvent = Pseq(rows, 1).embedInStream(inEvent);
						songBar = songBar + 1;
					};
				}),
				\timingOffset, offset,
				\out, ~ppMixBus,
				\group, ~ppInstrGroup
			);
			Pbindef(name).quant = 4;
		};
	};
};

\ppRender
