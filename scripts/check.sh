#!/usr/bin/env bash
# One command for the whole engine gate (Phase 4, success criterion 4).
#
# Usage:
#   scripts/check.sh                 library guard (+ its self-test), then
#                                    supercollider/library_test.scd, then
#                                    scripts/smoke_test.sh
#   scripts/check.sh --library-only  library guard and library_test.scd only
#                                    (the fast loop while adding a variation)
#
# Override the sclang binary with: SCLANG=/path/to/sclang scripts/check.sh
#
# The library guard (LIB-03) fails when a committed library file or the golden
# is modified, deleted or renamed (a rename shows up as a delete plus an add).
# A brand-new file, or a byte-identical re-save, passes. Every variation is a
# new file, so every earlier one stays selectable. The guard only reads git
# state; its self-test runs in its own temporary repository.
#
# Changes are measured against a stable base, so a change that was already
# committed is still caught: LIBRARY_GUARD_BASE=<git ref> if set, otherwise the
# merge-base of HEAD with origin/main when that ref exists, otherwise HEAD
# (uncommitted changes only).

set -euo pipefail
cd "$(dirname "$0")/.."

LIBRARY_ONLY=0
case "${1:-}" in
	"") ;;
	--library-only) LIBRARY_ONLY=1 ;;
	*)
		echo "usage: scripts/check.sh [--library-only]" >&2
		exit 2
		;;
esac
if [ "$#" -gt 1 ]; then
	echo "usage: scripts/check.sh [--library-only]" >&2
	exit 2
fi

SCLANG="${SCLANG:-/Applications/SuperCollider.app/Contents/MacOS/sclang}"
if [ ! -x "$SCLANG" ]; then
	echo "check FAILED: sclang not found or not executable at $SCLANG (set SCLANG=... to override)" >&2
	exit 1
fi

if [ ! -x .venv/bin/python ]; then
	echo "check FAILED: .venv/bin/python is missing." >&2
	echo "Fix: ./run.sh --setup, or python3.13 -m venv .venv && .venv/bin/pip install -r python_app/requirements.txt" >&2
	exit 1
fi

# The offscreen Qt plugin is absent from the macOS SuperCollider 3.14.1
# bundle and aborts sclang with exit 134 -- plain `sclang -D` already runs
# headless on its own, so make sure nothing upstream left this set.
unset QT_QPA_PLATFORM

# library_guard <repo_dir> [base_ref]: 0 = pass (or skipped), 1 = a committed
# library file or golden was modified, deleted or renamed since base_ref (default
# HEAD). Prints every offending file.
library_guard() {
	local repo="$1" base="${2:-HEAD}" bad
	if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		echo "CHECK SKIP: library guard (not a git work tree)"
		return 0
	fi
	if ! git -C "$repo" rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1; then
		if [ "$base" = "HEAD" ]; then
			echo "CHECK SKIP: library guard (no commits yet)"
			return 0
		fi
		echo "LIBRARY GUARD FAIL: base ref '$base' does not resolve to a commit" >&2
		return 1
	fi
	# Status letters: A added (passes), M modified, D deleted, T type change
	# (all fail). --no-renames turns a rename into D + A, so it fails on the D.
	# Untracked files never appear in git diff, so they pass.
	bad=$(git -C "$repo" diff --name-status --no-renames "$base" -- \
		'supercollider/library/*/[a-z0-9]*.scd' 'supercollider/golden/*.scd') || {
		echo "LIBRARY GUARD FAIL: git diff against '$base' failed" >&2
		return 1
	}
	bad=$(printf '%s\n' "$bad" | grep -v '^A' | grep -v '^$' || true)
	if [ -n "$bad" ]; then
		echo "LIBRARY GUARD FAIL: committed library files and the golden must never be edited, renamed or deleted -- add a new file instead:"
		echo "$bad"
		return 1
	fi
	return 0
}

# Self-test: prove the guard can fail, in a throwaway repository.
library_guard_selftest() {
	local tmp
	tmp=$(mktemp -d)
	# Expands now on purpose: the path is fixed for the life of this function.
	trap "rm -rf '$tmp'" EXIT
	local g="git -C $tmp -c user.name=check -c user.email=check@localhost -c commit.gpgsign=false"
	local keep="supercollider/library/melodies/keep.scd"
	local tmpl="supercollider/library/melodies/_template.scd"
	local gold="supercollider/golden/g.scd"

	git init -q "$tmp"
	mkdir -p "$tmp/supercollider/library/melodies" "$tmp/supercollider/golden"
	echo "keep" > "$tmp/$keep"
	echo "template" > "$tmp/$tmpl"
	echo "golden" > "$tmp/$gold"
	$g add -A
	$g commit -q -m "self-test base"

	local rc
	expect() { # expect <case name> <wanted rc>
		rc=0
		library_guard "$tmp" >/dev/null 2>&1 || rc=$?
		if [ "$rc" -ne "$2" ]; then
			echo "LIBRARY GUARD SELF-TEST FAIL: $1 (got $rc, wanted $2)" >&2
			exit 1
		fi
	}

	expect "clean" 0

	echo "new" > "$tmp/supercollider/library/melodies/new.scd"
	expect "new untracked file" 0
	$g add supercollider/library/melodies/new.scd
	expect "new file staged" 0
	$g reset -q
	rm -f "$tmp/supercollider/library/melodies/new.scd"

	echo "keep" > "$tmp/$keep"
	expect "byte-identical re-save" 0

	echo "changed" >> "$tmp/$keep"
	expect "committed file modified" 1
	$g checkout -q -- "$keep"

	rm "$tmp/$keep"
	expect "committed file deleted" 1
	$g checkout -q -- "$keep"

	$g mv "$keep" supercollider/library/melodies/other.scd
	expect "committed file renamed" 1
	$g mv supercollider/library/melodies/other.scd "$keep"
	$g reset -q
	$g checkout -q -- "$keep"

	echo "changed" >> "$tmp/$gold"
	expect "golden modified" 1
	$g checkout -q -- "$gold"

	echo "changed" >> "$tmp/$tmpl"
	expect "template modified (outside the guard)" 0
	$g checkout -q -- "$tmpl"

	expect "clean again" 0

	# A change that was already committed is caught against the older base, and
	# a base that does not resolve fails instead of passing.
	local base_ref
	base_ref=$($g rev-parse HEAD)
	echo "changed" >> "$tmp/$keep"
	$g commit -q -am "self-test committed edit"
	rc=0
	library_guard "$tmp" "$base_ref" >/dev/null 2>&1 || rc=$?
	if [ "$rc" -ne 1 ]; then
		echo "LIBRARY GUARD SELF-TEST FAIL: committed edit against an older base (got $rc, wanted 1)" >&2
		exit 1
	fi
	rc=0
	library_guard "$tmp" "no-such-ref" >/dev/null 2>&1 || rc=$?
	if [ "$rc" -ne 1 ]; then
		echo "LIBRARY GUARD SELF-TEST FAIL: unresolvable base (got $rc, wanted 1)" >&2
		exit 1
	fi

	# Outside any work tree the guard must say so, not pass silently.
	local plain
	plain=$(mktemp -d)
	if ! library_guard "$plain" | grep -qx 'CHECK SKIP: library guard (not a git work tree)'; then
		rmdir "$plain"
		echo "LIBRARY GUARD SELF-TEST FAIL: not a git work tree (no CHECK SKIP line)" >&2
		exit 1
	fi
	rmdir "$plain"

	# A repository with no commit yet says so, not a silent pass.
	local fresh
	fresh=$(mktemp -d)
	git init -q "$fresh"
	if ! library_guard "$fresh" | grep -qx 'CHECK SKIP: library guard (no commits yet)'; then
		rm -rf "$fresh"
		echo "LIBRARY GUARD SELF-TEST FAIL: no commits (no CHECK SKIP line)" >&2
		exit 1
	fi
	rm -rf "$fresh"
	echo "CHECK OK: library guard self-test"
}

# Run in a subshell so the self-test's trap and exit never touch this shell.
( library_guard_selftest )

GUARD_BASE="${LIBRARY_GUARD_BASE:-}"
if [ -z "$GUARD_BASE" ] && git rev-parse --verify --quiet 'origin/main^{commit}' >/dev/null 2>&1; then
	GUARD_BASE=$(git merge-base HEAD origin/main 2>/dev/null || true)
fi
if library_guard . "${GUARD_BASE:-HEAD}"; then
	echo "CHECK OK: library guard"
else
	exit 1
fi

# Library check: static tier (every library file), golden self-check, parity,
# selection, fallback and containment tiers.
LIB_LOG="${TMPDIR:-/tmp}/pedalpulse-library.log"

TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
	TIMEOUT_CMD="timeout 330"
elif command -v gtimeout >/dev/null 2>&1; then
	TIMEOUT_CMD="gtimeout 330"
fi

rc=0
$TIMEOUT_CMD "$SCLANG" -D supercollider/library_test.scd > "$LIB_LOG" 2>&1 || rc=$?

cat "$LIB_LOG"

if [ "$rc" -ne 0 ] || ! grep -qx 'LIBRARY PASS' "$LIB_LOG"; then
	echo "CHECK FAILED: library check (log: $LIB_LOG)" >&2
	exit 1
fi

# A library file the check never looked at is a hole in the check: the number of
# "LIBCHECK OK: <category>/<stem>" lines must equal the number of .scd files on
# disk (the _template.scd files included).
want=$(find supercollider/library -name '*.scd' ! -name '.*' | wc -l | tr -d ' ')
got=$(grep -c '^LIBCHECK OK: ' "$LIB_LOG" || true)
if [ "$want" -eq 0 ] || [ "$got" -ne "$want" ]; then
	echo "CHECK FAILED: library file count (LIBCHECK OK lines: $got, .scd files on disk: $want)" >&2
	exit 1
fi
echo "CHECK OK: library file count ($want files)"

if [ "$LIBRARY_ONLY" -eq 1 ]; then
	echo "CHECK PASS (library only)"
	exit 0
fi

if ! bash scripts/smoke_test.sh; then
	echo "CHECK FAILED: smoke suite (log: ${TMPDIR:-/tmp}/pedalpulse-smoke.log)" >&2
	exit 1
fi

echo "CHECK PASS"
