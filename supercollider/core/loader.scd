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
// Total lines ever logged: ~ppLogLines is capped, so tests count new lines
// with this, never with the list size.
~ppLogCount = ~ppLogCount ? 0;
~ppLog = { |line|
	line.postln;
	~ppLogCount = ~ppLogCount + 1;
	~ppLogLines.add(line);
	while { ~ppLogLines.size > 100 } { ~ppLogLines.removeAt(0) };
	line
};

// category -> (stem -> module Event)
~ppLib = ~ppLib ? (progressions: (), melodies: (), palettes: ());

~ppLibPath = { |cat, stem|
	~ppLibRoot +/+ cat.asString +/+ (stem.asString ++ ".scd")
};

// A selectable name: 1-64 characters, each a-z, 0-9 or _; not starting with _
// (those are templates) and not "auto", "parent" or "proto" (reserved: Event:put
// treats \parent and \proto as prototype slots, not as keys, so a registry entry
// under either stem would leak its keys into every lookup). Takes a String or a
// Symbol.
// A character loop on ascii codes, never a regex: a regex $ anchor accepts a
// trailing newline, so "classic\n" would pass (RESEARCH Pitfall 5). Names are
// compared byte for byte, so Classic, clássico and "my lead" are all refused.
~ppStemValid = { |str|
	var ok;
	str = str.asString;
	ok = (str.size >= 1) and: { str.size <= 64 };
	if (ok) {
		str.do { |ch|
			var a = ch.ascii;
			var good = ((a >= 97) and: { a <= 122 }) or: { ((a >= 48) and: { a <= 57 }) or: { a == 95 } };
			if (good.not) { ok = false };
		};
	};
	if (ok) {
		ok = (str[0].ascii != 95) and: { ["auto", "parent", "proto"].includesEqual(str).not };
	};
	ok
};

// True only when the file really sits inside its category folder: both paths
// are resolved through symlinks and the file must start with the folder plus a
// "/". A symlink pointing outside the library fails.
~ppLibContained = { |cat, path|
	var real, base;
	real = File.realpath(path);
	base = File.realpath(~ppLibRoot +/+ cat.asString);
	real.notNil and: { base.notNil and: { real.beginsWith(base ++ "/") } }
};

// Load one library file from disk. Returns the module Event, or nil after
// logging one "PedalPulse ERROR: library file <path> <reason>" line.
// String:load compile errors do not name the file, so the loader always does.
~ppLibLoad = { |cat, stem|
	var path, mod, failed = false, reasons;
	path = ~ppLibPath.(cat, stem);
	~ppLog.("PedalPulse: loading %".format(path));
	if (File.exists(path).not) {
		~ppLog.("PedalPulse ERROR: library file % does not exist".format(path));
		failed = true;
	};
	if (failed.not and: { ~ppLibContained.(cat, path).not }) {
		~ppLog.("PedalPulse ERROR: library file % resolves outside %".format(path, ~ppLibRoot +/+ cat.asString));
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
	// The same pure functions the library check uses (core/validate.scd). A
	// validator that itself throws on a hostile value counts as a refusal.
	if (failed.not) {
		reasons = try {
			~ppValidate.(cat, mod)
		} { |err|
			["validation threw: %".format(err.errorString)]
		};
		if (reasons.size > 0) {
			~ppLog.("PedalPulse ERROR: library file % is invalid: %".format(path, reasons.join("; ")));
			failed = true;
		};
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
// Loads on every call, so selecting a name again reloads it. On any failure
// (load, validation, defs, voices) the registry is left untouched, so the last
// good copy keeps playing, and false is returned after an ERROR line naming the
// file. Success is the single registry put at the end.
~ppLibEnsure = { |cat, stem|
	var mod, prev, ok = true, reasons;
	mod = ~ppLibLoad.(cat, stem);
	if (mod.isNil) {
		ok = false;
	} {
		if (cat == \palettes) {
			// defs is optional: a palette may only re-map voices that already exist.
			if (mod[\defs].isFunction) {
				try {
					mod[\defs].value;
					s.sync;
				} { |err|
					~ppLog.("PedalPulse ERROR: library file % defs failed: %".format(mod[\path], err.errorString));
					ok = false;
				};
			};
			if (ok) {
				reasons = try {
					~ppValidateVoices.(mod)
				} { |err|
					["voice validation threw: %".format(err.errorString)]
				};
				if (reasons.size > 0) {
					~ppLog.("PedalPulse ERROR: library file % has invalid voices: %".format(mod[\path], reasons.join("; ")));
					ok = false;
				};
			};
		};
	};
	if (ok) {
		prev = ~ppLib[cat][stem.asSymbol];
		mod[\rev] = if (prev.notNil) { (prev[\rev] ? 0) + 1 } { 1 };
		~ppLib[cat].put(stem.asSymbol, mod);
		// A (re)loaded file starts with a clean render error count.
		if (~ppRenderErrors.notNil and: { ~ppRenderErrors[cat].notNil }) {
			~ppRenderErrors[cat][stem.asSymbol] = 0;
		};
	};
	ok
};

// --- Auto prefetch (D-10, LIB-05) ---
// Auto may choose any progression file on disk, including one added while the
// engine runs. The layer that decides a cycle never waits for disk, so each Auto
// pick starts ONE background scan of the progressions folder on SystemClock; a
// file it registers is a candidate from the next pick. Every scanned name passes
// ~ppStemValid before a path is built and loads only through ~ppLibEnsure
// (containment, validation, one registry put). A file that failed to load is
// remembered with its modification time (path -> mtime), so a broken file is
// read and reported once per change of the file, not at every pick. The scan
// never sets ~ppSel and never reloads a stem that is already registered (an
// explicit pick does that). It is capped at 256 files and runs one at a time.
~ppAutoFailed = ~ppAutoFailed ? Dictionary.new;
~ppAutoPrefetching = ~ppAutoPrefetching ? false;
~ppAutoPrefetch = {
	var env;
	if (~ppAutoPrefetching != true) {
		~ppAutoPrefetching = true;
		env = currentEnvironment;
		Routine({
			env.use {
				try {
					var paths;
					paths = (~ppLibRoot +/+ "progressions" +/+ "*.scd").pathMatch;
					paths.keep(256).do { |path|
						var stem, mtime, ok;
						stem = PathName(path).fileNameWithoutExtension;
						if (~ppStemValid.(stem) and: { ~ppLib[\progressions][stem.asSymbol].isNil }) {
							mtime = File.mtime(path);
							if (~ppAutoFailed[path] != mtime) {
								ok = try {
									~ppLibEnsure.(\progressions, stem.asSymbol)
								} { |err|
									~ppLog.("PedalPulse ERROR: progression % failed to load: %".format(path, err.errorString));
									false
								};
								if (ok == true) {
									~ppAutoFailed.removeAt(path);
								} {
									~ppAutoFailed[path] = mtime;
								};
							};
						};
					};
				} { |err|
					~ppLog.("PedalPulse ERROR: progression scan failed: %".format(err.errorString));
				};
				~ppAutoPrefetching = false;
			};
		}).play(SystemClock);
	};
};

// --- Selection by name (LIB-02, LIB-05) ---
// Latest wins: a request number per category. A request that finishes loading
// after a newer one was made (or after `auto`) does not become the selection.
~ppSelReq = ~ppSelReq ? (progressions: 0, melodies: 0, palettes: 0);

// Called by the three OSC handlers. cat is \progressions, \melodies or
// \palettes; raw is whatever the message carried (OSC strings arrive as
// Symbols); address is only used in log lines. It validates, then loads in a
// background Routine on SystemClock: the OSC responder never waits and never
// calls s.sync. ~ppSel[cat] is set only after a successful load. Palettes and
// melodies are read by the per-bar renderer at the start of each bar, so the
// music switches on the next bar line. Progressions are read at the next cycle
// decision (core/harmony.scd), so a progression pick switches at the end of the
// current progression cycle, never mid-cycle. Nothing is ever sent back.
~ppSelect = { |cat, raw, address|
	var str, token, env;
	if (raw.isKindOf(Symbol).not and: { raw.isKindOf(String).not }) {
		~ppLog.("PedalPulse WARNING: ignoring % with invalid argument %".format(address, raw));
	} {
		str = raw.asString;
		if (str == "auto") {
			// Supersedes any load still in flight for this category.
			~ppSelReq[cat] = ~ppSelReq[cat] + 1;
			~ppSel[cat] = \auto;
			if (cat == \progressions) {
					~ppLog.("PedalPulse: % auto -> auto (rotates progressions at cycle ends; a Start begins on classic)".format(address));
					~ppAutoPrefetch.value;
				} {
					~ppLog.("PedalPulse: % auto -> auto (resolves to classic)".format(address));
				};
		} {
			if (~ppStemValid.(str).not) {
				// No path is ever built from an invalid name.
				~ppLog.("PedalPulse WARNING: ignoring % \"%\": a name is 1-64 characters from a-z, 0-9 and _, not starting with _, and not auto".format(address, str));
			} {
				token = ~ppSelReq[cat] + 1;
				~ppSelReq[cat] = token;
				env = currentEnvironment;
				Routine({
					env.use {
						var ok, mod;
						ok = try {
							~ppLibEnsure.(cat, str.asSymbol)
						} { |err|
							~ppLog.("PedalPulse ERROR: % % failed: %".format(address, str, err.errorString));
							false
						};
						if (ok) {
							if (token == ~ppSelReq[cat]) {
								~ppSel[cat] = str.asSymbol;
								mod = ~ppLib[cat][str.asSymbol];
								if (cat == \progressions) {
									~ppLog.("PedalPulse: % % -> selected (rev %), switches at the end of the current progression cycle".format(address, str, mod[\rev]));
								} {
									~ppLog.("PedalPulse: % % -> selected (rev %), plays from the next bar".format(address, str, mod[\rev]));
								};
							} {
								~ppLog.("PedalPulse: % % loaded but superseded by a newer selection".format(address, str));
							};
						} {
							~ppLog.("PedalPulse: % % refused -- still playing %".format(address, str, ~ppSel[cat]));
						};
					};
				}).play(SystemClock);
			};
		};
	};
};

\ppLoader
