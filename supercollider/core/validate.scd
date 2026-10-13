// PedalPulse core: library file validation (Phase 4, LIB-04 / LIB-06).
//
// Loaded by main.scd (~ppLoadCore) first, before loader.scd and render.scd.
// Pure and server-free: it only defines ~ variables and plays nothing. The
// loader calls these functions on every file it reads, the renderer calls
// ~ppRowsValid on every bar a generator returns, and the library check calls the
// same functions, so there is one definition of "valid".
//
// Contract-freeze rule: unknown keys and unknown role names are ignored, never
// errors. Later phases add optional fields to modules and committed files never
// need an edit. (Phase 6 adds the optional progression keys chords and
// barsPerChord; a file that has them is checked by ~ppChordDataReasons.)
//
// Events are always accessed with [\key], never dot syntax.

~ppDrumRoles = [\kick, \hat, \clap];
~ppPitchedRoles = [\bass, \pad, \arp, \lead];

// Chord qualities a progression file may name (Phase 6). Intervals are semitones
// above the chord root. core/harmony.scd reads this table, so it lives here,
// next to the validator that checks a file's chord data against it.
~ppChordTypes = (maj: [0, 4, 7], min: [0, 3, 7]);

// module -> Array of reason Strings for a progression's chord data (empty means
// valid). Never throws on hostile values: every value's class is checked before
// it is used, and the chord count is checked before any chord is looked at, so a
// huge Array is refused without a loop over it. N in a reason is the 1-based
// chord number.
~ppChordDataReasons = { |module|
	var reasons = List.new, chords, cycle = 0, bpc, isInt, intervalsOk, qualityKeys;
	isInt = { |x, lo, hi| x.isKindOf(Integer) and: { (x >= lo) and: { x <= hi } } };
	intervalsOk = { |iv|
		var ok = iv.isKindOf(Array) and: { (iv.size == 3) or: { iv.size == 4 } };
		if (ok) {
			ok = iv.every { |x| isInt.(x, 0, 11) };
		};
		if (ok) {
			ok = (iv[0] == 0);
		};
		if (ok) {
			(iv.size - 1).do { |i| if (iv[i + 1] <= iv[i]) { ok = false } };
		};
		ok
	};
	qualityKeys = ~ppChordTypes.keys.asArray.sort.join(", ");
	chords = module[\chords];
	bpc = module[\barsPerChord];
	if (bpc.notNil and: { isInt.(bpc, 1, 8).not }) {
		reasons.add("barsPerChord is not an Integer from 1 to 8");
	};
	if (chords.isKindOf(Array).not) {
		reasons.add("chords is not an Array");
	} {
		if (chords.size < 1) {
			reasons.add("chords is empty");
		} {
			if (chords.size > 16) {
				reasons.add("chords has % entries, more than 16".format(chords.size));
			} {
				chords.do { |c, i|
					var n = i + 1, bars;
					if (c.isKindOf(Event).not) {
						reasons.add("chord % is not an Event".format(n));
						cycle = cycle + 1;
					} {
						if (isInt.(c[\root], 0, 11).not) {
							reasons.add("chord % root is not an Integer from 0 to 11".format(n));
						};
						if (c[\quality].notNil and: { ~ppChordTypes[c[\quality]].isNil }) {
							reasons.add("chord % quality is not one of: %".format(n, qualityKeys));
						};
						if (c[\intervals].notNil and: { intervalsOk.(c[\intervals]).not }) {
							reasons.add("chord % intervals are not 3 or 4 rising Integers from 0 to 11 starting at 0".format(n));
						};
						if (c[\quality].isNil and: { c[\intervals].isNil }) {
							reasons.add("chord % has neither quality nor intervals".format(n));
						};
						bars = c[\bars];
						if (bars.notNil and: { isInt.(bars, 1, 8).not }) {
							reasons.add("chord % bars is not an Integer from 1 to 8".format(n));
						};
						// The cycle length counts valid numbers only; a bad value was
						// already refused above.
						cycle = cycle + if (isInt.(bars, 1, 8)) { bars } { if (isInt.(bpc, 1, 8)) { bpc } { 1 } };
					};
				};
				if (cycle > 16) {
					reasons.add("the cycle is % bars, more than 16".format(cycle));
				};
			};
		};
	};
	reasons.asArray
};

// rows -> nil when valid, otherwise one reason String.
// A bar is a non-empty Array of [note, dur, amp, legato] rows whose durs sum
// to 4.0 within 1e-6. note is \rest, a finite Number, or a non-empty Array of
// finite Numbers; dur and legato are finite and > 0; amp is finite, 0 to 1.
//
// Upper bounds (Phase 7, WR-01 of the Phase 4 review): without them a file could
// return a "valid" bar of hundreds of thousands of rows, a legato of 100 or a
// note of 500 and choke the engine. A bar has at most 64 rows (checked before any
// row is looked at, so a huge Array is refused without a loop), every dur is at
// least 1/32 beat, a legato is at most 8, a Number note and every chord note is
// in -12..127, and a chord has at most 8 notes. The durs of a valid bar sum to 4,
// so these caps bound one layer's overlap to 4 x 8 x 8 = 256 voice-beats per bar.
// Legato 8, not the 4 the review suggested: the core's default pad on an 8-bar
// chord has legato 7.2, and a cap of 4 would send a legal progression back to
// classic's pad.
~ppRowsValid = { |rows|
	var reason = nil, sum = 0, finite, noteOk;
	finite = { |x| x.isNumber and: { x.isNaN.not and: { x.abs < inf } } };
	noteOk = { |x| (x >= -12) and: { x <= 127 } };
	if (rows.isKindOf(Array).not or: { rows.size < 1 }) {
		reason = "bar is not a non-empty Array of rows";
	} {
		if (rows.size > 64) {
			reason = "bar has % rows, more than 64".format(rows.size);
		};
	};
	if (reason.isNil) {
		rows.do { |r, i|
			var n = i + 1, note;
			if (reason.isNil) {
				if (r.isKindOf(Array).not or: { r.size != 4 }) {
					reason = "row % is not [note, dur, amp, legato]".format(n);
				} {
					note = r[0];
					if ((note === \rest).not) {
						if (note.isKindOf(Array)) {
							if ((note.size < 1) or: { note.every(finite).not }) {
								reason = "row %: note is an empty or non-numeric chord".format(n);
							};
						} {
							if (finite.(note).not) {
								reason = "row %: note is not \\rest, a number or a chord".format(n);
							};
						};
					};
					if (reason.isNil and: { finite.(r[1]).not or: { r[1] <= 0 } }) {
						reason = "row %: dur is not a number above 0".format(n);
					};
					if (reason.isNil and: { finite.(r[2]).not or: { (r[2] < 0) or: { r[2] > 1 } } }) {
						reason = "row %: amp is not a number from 0 to 1".format(n);
					};
					if (reason.isNil and: { finite.(r[3]).not or: { r[3] <= 0 } }) {
						reason = "row %: legato is not a number above 0".format(n);
					};
					// Upper bounds (WR-01); every value is known finite here.
					if (reason.isNil and: { note.isKindOf(Array) }) {
						if (note.size > 8) {
							reason = "row %: chord has % notes, more than 8".format(n, note.size);
						} {
							note.do { |cn|
								if (reason.isNil and: { noteOk.(cn).not }) {
									reason = "row %: chord note % is outside -12 to 127".format(n, cn);
								};
							};
						};
					};
					if (reason.isNil and: { (note === \rest).not and: { note.isKindOf(Array).not } and: { noteOk.(note).not } }) {
						reason = "row %: note % is outside -12 to 127".format(n, note);
					};
					if (reason.isNil and: { r[1] < (1/32) }) {
						reason = "row %: dur % is shorter than 1/32 beat".format(n, r[1]);
					};
					if (reason.isNil and: { r[3] > 8 }) {
						reason = "row %: legato % is more than 8".format(n, r[3]);
					};
					if (reason.isNil) { sum = sum + r[1] };
				};
			};
		};
		if (reason.isNil and: { (sum - 4.0).abs > 1e-6 }) {
			reason = "bar fills % beats, not 4".format(sum);
		};
	};
	reason
};

// cat, module -> Array of reason Strings (empty means valid).
~ppValidate = { |cat, module|
	var reasons = List.new, isFn, checkFn, anyOf;
	isFn = { |x| x.isFunction };
	// checkFn adds a reason when module[key] is present and not a Function.
	checkFn = { |key|
		if (module[key].notNil and: { isFn.(module[key]).not }) {
			reasons.add("% is not a Function".format(key));
		};
	};
	anyOf = { |keys|
		if (keys.every { |k| module[k].isNil }) {
			reasons.add("defines none of: %".format(keys.join(", ")));
		};
	};
	if (module.isKindOf(Event).not) {
		reasons.add("is not an Event");
	} {
		if (module[\desc].isKindOf(String).not or: { module[\desc].size < 1 }) {
			reasons.add("desc is missing or not a non-empty String");
		};
		if (cat == \progressions) {
			// A progression is chord data (chords) and/or its own bass and pad
			// generators. Classic is generators only; it has no chords.
			anyOf.([\bass, \pad, \chords]);
			checkFn.(\bass);
			checkFn.(\pad);
			if (module[\chords].notNil or: { module[\barsPerChord].notNil }) {
				~ppChordDataReasons.(module).do { |r| reasons.add(r) };
			};
		};
		if (cat == \melodies) {
			anyOf.([\arp, \lead]);
			checkFn.(\arp);
			checkFn.(\lead);
			checkFn.(\init);
		};
		if (cat == \palettes) {
			if (module[\roles].isKindOf(Event).not) {
				reasons.add("roles is missing or not an Event");
			} {
				var known = 0;
				(~ppDrumRoles ++ ~ppPitchedRoles).do { |role|
					var entry = module[\roles][role];
					if (entry.notNil) {
						known = known + 1;
						if (entry.isKindOf(Event).not or: { entry[\instrument].isKindOf(Symbol).not }) {
							reasons.add("role % has no instrument Symbol".format(role));
						};
					};
				};
				if (known == 0) {
					reasons.add("roles names no known role (%)".format((~ppDrumRoles ++ ~ppPitchedRoles).join(", ")));
				};
			};
			checkFn.(\defs);
		};
		if ([\progressions, \melodies, \palettes].includes(cat).not) {
			reasons.add("unknown category %".format(cat));
		};
	};
	reasons.asArray
};

// module -> Array of reason Strings for a palette's voices. Only meaningful
// after the palette's defs ran (client-side: SynthDef.add registers the
// SynthDesc at once, no server needed). Every known role's instrument must be a
// known SynthDef with out and amp controls, plus freq and gate for pitched roles.
~ppValidateVoices = { |module|
	var reasons = List.new;
	if (module.isKindOf(Event) and: { module[\roles].isKindOf(Event) }) {
		(~ppDrumRoles ++ ~ppPitchedRoles).do { |role|
			var entry = module[\roles][role], inst, desc, need;
			if (entry.notNil and: { entry.isKindOf(Event) }) {
				inst = entry[\instrument];
				if (inst.isKindOf(Symbol)) {
					desc = SynthDescLib.global.at(inst);
					if (desc.isNil) {
						reasons.add("voice % for role % is not a known SynthDef".format(inst, role));
					} {
						need = [\out, \amp];
						if (~ppPitchedRoles.includes(role)) { need = need ++ [\freq, \gate] };
						need.do { |c|
							if (desc.controlDict[c].isNil) {
								reasons.add("voice % for role % has no % control".format(inst, role, c));
							};
						};
					};
				};
			};
		};
	};
	reasons.asArray
};

\ppValidate
