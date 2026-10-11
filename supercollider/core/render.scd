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
~ppLayerRole = (ppArp: \arp);

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

// Render one bar for a role: rows [instrument, note, dur, amp, legato].
~ppRenderBar = { |role, songBar, bar, layerState|
	var cat, mod, key, gen, rows, inst, plan;
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
	inst = ~ppInstrumentFor.(role);
	rows.collect { |r| [inst] ++ r }
};

// (Re)build every layer in ~ppLayers that has a role. Pbindef(name) stays the
// handle main.scd and the tests play, stop and ask isPlaying.
~ppBuildLayers = {
	var env = currentEnvironment;
	~ppLayers.do { |name|
		var role = ~ppLayerRole[name];
		if (role.notNil) {
			// Pbindef merges keys; clearing first drops keys of an older definition.
			Pbindef(name).clear;
			Pbindef(name,
				[\instrument, \midinote, \dur, \amp, \legato],
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
							[[\default, \rest, 4, 0, 1]]
						};
						inEvent = Pseq(rows, 1).embedInStream(inEvent);
						songBar = songBar + 1;
					};
				}),
				\timingOffset, 0,
				\out, ~ppMixBus,
				\group, ~ppInstrGroup
			);
			Pbindef(name).quant = 4;
		};
	};
};

\ppRender
