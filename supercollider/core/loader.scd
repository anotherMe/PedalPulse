// PedalPulse core: variation library loader (Phase 4, LIB-02).
//
// Loaded by main.scd (~ppLoadCore) at top level, before s.waitForBoot. At load
// this file only defines ~ variables: no server access, no Pbindef, nothing is
// played. Re-evaluating it alone never drops already loaded modules.
//
// A library file is a single parenthesized Event (see library/*/classic.scd).
// The loader sets \name (the file stem), \path, \category and \rev itself and
// ignores any name written inside the file. Events are always accessed with
// [\key], never dot syntax: dot syntax collides with Object methods such as
// name and size.

~ppLibCategories = [\progressions, \melodies, \palettes];

// One post window line that is also kept for the app-facing log (last 100).
~ppLogLines = ~ppLogLines ? List.new;
~ppLog = { |line|
	line.postln;
	~ppLogLines.add(line);
	while { ~ppLogLines.size > 100 } { ~ppLogLines.removeAt(0) };
	line
};

// category -> (stem -> module Event)
~ppLib = ~ppLib ? (progressions: (), melodies: (), palettes: ());

~ppLibPath = { |cat, stem|
	~ppLibRoot +/+ cat.asString +/+ (stem.asString ++ ".scd")
};

// Load one library file from disk. Returns the module Event, or nil after
// logging one "PedalPulse ERROR: library file <path> <reason>" line.
// String:load compile errors do not name the file, so the loader always does.
~ppLibLoad = { |cat, stem|
	var path, mod, failed = false;
	path = ~ppLibPath.(cat, stem);
	~ppLog.("PedalPulse: loading %".format(path));
	if (File.exists(path).not) {
		~ppLog.("PedalPulse ERROR: library file % does not exist".format(path));
		failed = true;
	};
	if (failed.not) {
		try {
			mod = path.load;
		} { |err|
			~ppLog.("PedalPulse ERROR: library file % threw: %".format(path, err.errorString));
			failed = true;
		};
	};
	if (failed.not and: { mod.isNil }) {
		~ppLog.("PedalPulse ERROR: library file % evaluated to nil (syntax error, empty or comment-only file)".format(path));
		failed = true;
	};
	if (failed.not and: { mod.isKindOf(Event).not }) {
		~ppLog.("PedalPulse ERROR: library file % did not evaluate to an Event (got %)".format(path, mod.class));
		failed = true;
	};
	if (failed) {
		nil
	} {
		mod[\name] = stem.asSymbol;
		mod[\path] = path;
		mod[\category] = cat;
		mod
	}
};

// Load from disk and register. Runs only inside a Routine (palettes call s.sync).
// Loads on every call, so selecting a name again reloads it. On any failure the
// registry is left untouched and false is returned.
~ppLibEnsure = { |cat, stem|
	var mod, prev, ok = true;
	mod = ~ppLibLoad.(cat, stem);
	if (mod.isNil) {
		ok = false;
	} {
		if (cat == \palettes) {
			if (mod[\defs].isFunction.not) {
				~ppLog.("PedalPulse ERROR: library file % has no defs function".format(mod[\path]));
				ok = false;
			} {
				try {
					mod[\defs].value;
					s.sync;
				} { |err|
					~ppLog.("PedalPulse ERROR: library file % defs failed: %".format(mod[\path], err.errorString));
					ok = false;
				};
			};
		};
	};
	if (ok) {
		prev = ~ppLib[cat][stem.asSymbol];
		mod[\rev] = if (prev.notNil) { (prev[\rev] ? 0) + 1 } { 1 };
		~ppLib[cat].put(stem.asSymbol, mod);
	};
	ok
};

\ppLoader
