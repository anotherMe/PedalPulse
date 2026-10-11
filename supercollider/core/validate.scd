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
// need an edit.
//
// Events are always accessed with [\key], never dot syntax.

~ppDrumRoles = [\kick, \hat, \clap];
~ppPitchedRoles = [\bass, \pad, \arp, \lead];

// rows -> nil when valid, otherwise one reason String.
// A bar is a non-empty Array of [note, dur, amp, legato] rows whose durs sum
// to 4.0 within 1e-6. note is \rest, a finite Number, or a non-empty Array of
// finite Numbers; dur and legato are finite and > 0; amp is finite, 0 to 1.
~ppRowsValid = { |rows|
	var reason = nil, sum = 0, finite;
	finite = { |x| x.isNumber and: { x.isNaN.not and: { x.abs < inf } } };
	if (rows.isKindOf(Array).not or: { rows.size < 1 }) {
		reason = "bar is not a non-empty Array of rows";
	} {
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
			anyOf.([\bass, \pad]);
			checkFn.(\bass);
			checkFn.(\pad);
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
