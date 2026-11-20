#!/bin/sh
# xfd-native self-tests.
#
#   sh tests/run.sh build/xfdnative
#
# Optional corpus check: point XFD_TEST_CORPUS at a directory of crunched
# files, each with a reference result made by xfdDecrunch on an Amiga:
#   NAME            the crunched file
#   NAME.expected   xfdDecrunch NAME NAME.expected FORCE LP
# Files without a .expected must come back "Not crunched". Crunched Amiga
# productions are usually copyrighted, so no corpus is included here.
# XFD_SLAVES (or a slaves/ directory) adds the external slaves.
#
# SPDX-License-Identifier: LGPL-2.1-or-later

set -u
BIN=${1:-build/xfdnative}
[ -x "$BIN" ] || BIN="$BIN.exe"
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t xfdtest)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; }

# write big-endian 32-bit words given as hex
words() { for w in "$@"; do printf "$(printf '\\%03o\\%03o\\%03o\\%03o' \
	$((0x$w >> 24 & 255)) $((0x$w >> 16 & 255)) $((0x$w >> 8 & 255)) $((0x$w & 255)))"; done; }

# 1. version
"$BIN" --version >/dev/null 2>&1 && ok "version" || bad "version"

# 2. internal slave list
n=$("$BIN" --noextern --list | tail -n 1)
[ "$n" = "139 slaves" ] && ok "139 internal slaves" || bad "internal slaves: got '$n'"

# Tests 3-5 use only the built-in slaves (-n), so results do not depend on
# which external slaves happen to be installed.

# 3. a tiny uncrunched executable (one code hunk: rts rts)
words 000003f3 00000000 00000001 00000000 00000000 00000001 \
	000003e9 00000001 4e754e75 000003f2 >"$TMP/plain"
out=$("$BIN" -n -f "$TMP/plain" "$TMP/plain.out" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q "^Not crunched" && [ ! -e "$TMP/plain.out" ]; then
	ok "uncrunched file is left alone"
else
	bad "uncrunched file (rc=$rc): $out"
fi

# 4. --copyall writes it unchanged
"$BIN" -n -f -c "$TMP/plain" "$TMP/plain.copy" >/dev/null 2>&1
cmp -s "$TMP/plain" "$TMP/plain.copy" && ok "--copyall copies" || bad "--copyall"

# 5. garbage and empty input must not crash
printf 'not an amiga file at all' >"$TMP/text"
"$BIN" -n "$TMP/text" >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && ok "text file" || bad "text file rc=$rc"
: >"$TMP/empty"
"$BIN" -n "$TMP/empty" >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && ok "empty file" || bad "empty file rc=$rc"

# 6. end-to-end through a real 68k slave: the public-domain OBJT external
#    slave (m68k/extra/OBJT) converts an OBJT object into a hunk executable
if [ -f m68k/extra/OBJT ]; then
	printf 'OBJT\000\000\000\001\160\000\116\165\000\000' >"$TMP/objt"
	words 000003f3 00000000 00000001 00000000 00000000 00000001 \
		000003e9 00000001 70004e75 000003f2 >"$TMP/objt.expected"
	"$BIN" -f -n -x m68k/extra "$TMP/objt" "$TMP/objt.out" >"$TMP/log" 2>&1
	grep -q "^Not crunched" "$TMP/log" && ok "--noextern ignores external slaves" ||
		bad "--noextern: $(cat "$TMP/log")"
	"$BIN" -f -x m68k/extra "$TMP/objt" "$TMP/objt.out" >"$TMP/log" 2>&1
	cmp -s "$TMP/objt.out" "$TMP/objt.expected" && ok "OBJT slave decrunch (68k)" ||
		bad "OBJT slave decrunch: $(cat "$TMP/log")"
fi

# 7. optional corpus
if [ -n "${XFD_TEST_CORPUS:-}" ] && [ -d "$XFD_TEST_CORPUS" ]; then
	for f in "$XFD_TEST_CORPUS"/*; do
		case "$f" in *.expected) continue ;; esac
		[ -f "$f" ] || continue
		name=$(basename "$f")
		rm -f "$TMP/out"
		"$BIN" -f -p "$f" "$TMP/out" >"$TMP/log" 2>&1
		if [ -f "$f.expected" ]; then
			cmp -s "$TMP/out" "$f.expected" && ok "corpus $name" || bad "corpus $name: $(tail -n 1 "$TMP/log")"
		else
			grep -q "^Not crunched" "$TMP/log" && ok "corpus $name (not crunched)" || bad "corpus $name: expected not crunched"
		fi
	done
fi

echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
