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

// The voice for a role: the resolved palette's, falling back to classic's.
~ppInstrumentFor = { |role|
	var pal, fallback, inst;
	pal = ~ppModuleFor.(\palettes);
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

~ppPlanFor = { |bar, songBar, role|
	(bar: bar, songBar: songBar, phraseBar: songBar % 8, role: role)
};

// Render one bar for a role: rows [instrument, note, dur, amp, legato] for a
// pitched role, [instrument, dur, amp, legato] for a drum role.
~ppRenderBar = { |role, songBar, bar, layerState|
	var cat, mod, key, gen, rows, inst, plan, out;
	inst = ~ppInstrumentFor.(role);
	if (~ppDrumGrid[role].notNil) {
		out = ~ppDrumGrid[role][\rows].collect { |r| [inst, r[1], r[2], r[3]] };
		~ppRoleNotes[role] = (~ppRoleNotes[role] ? 0) + out.size;
		out
	} {
		cat = ~ppRoleCategory[role];
		mod = ~ppModuleFor.(cat);
		key = if (mod.notNil) { [mod[\name], mod[\rev]] } { nil };
		plan = ~ppPlanFor.(bar, songBar, role);
		// A different module (or a reload of the same one) starts with a fresh state.
		if (key != layerState[\moduleKey]) {
			layerState[\state] = ();
			if (mod.notNil and: { mod[\init].isFunction }) {
				mod[\init].value(layerState[\state]);
			};
			layerState[\moduleKey] = key;
		};
		gen = if (mod.notNil) { mod[role] } { nil };
		if (gen.isNil) {
			gen = ~ppLib[cat][\classic] !? { |c| c[role] };
		};
		rows = if (gen.isFunction) { gen.value(plan, layerState[\state]) } { [[\rest, 4, 0, 1]] };
		out = rows.collect { |r| [inst] ++ r };
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
