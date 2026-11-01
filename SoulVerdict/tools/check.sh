#!/usr/bin/env bash
# tools/check.sh — the project's static-analysis gate (we cannot run Studio / luau-lsp here).
# Steps (in order):
#   compile      tools/checks/compile.luau       Luau compiler over every .luau in src/ and tools/ (syntax)
#   selene       selene src                      lints with the Roblox std (selene.toml -> sv.yml -> roblox.yml)
#   apicheck     tools/checks/apicheck.py        Roblox API usage vs .tools/API-Dump.json
#   conventions  tools/checks/conventions.py     --!strict, banned APIs, Lune-safety, file size
#   contracts    tools/checks/contracts.py       requires/exports, Net remotes, Strings keys, clips, icons
#   selftest     tools/checks/selftest.py        the checkers reproduce tools/checks/fixtures (no regressions)
#   tests        tools/lune/run_tests.luau       Lune unit tests (incl. require-all of Lune-safe modules)
#   place        rojo build (temp file) + tools/lune/verify_place.luau   (SPEC §15; SoulVerdict.rbxl untouched)
#   format       stylua --check src              informational only (never fails; format only YOUR files)
# Prints every finding, then a summary table. Exit code 1 if any step reports an ERROR (warnings are OK).
# Usage: tools/check.sh [-q|--quiet]   (quiet = hide warnings, show errors + table)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
export PATH="$ROOT/.tools/cargo/bin:$PATH"
QUIET=0
for arg in "$@"; do
	case "$arg" in
		-q | --quiet) QUIET=1 ;;
		-h | --help)
			sed -n '2,15p' "$0"
			exit 0
			;;
	esac
done

LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/sv-check.XXXXXX")"
trap 'rm -rf "$LOGDIR"' EXIT

NAMES=()
STATUS=()
ERRS=()
WARNS=()
TIMES=()
ANY_ERROR=0

now_ms() { date +%s%3N; }

# record NAME STATUS ERRORS WARNINGS MS
record() {
	NAMES+=("$1")
	STATUS+=("$2")
	ERRS+=("$3")
	WARNS+=("$4")
	TIMES+=("$5")
	if [ "$2" = "FAIL" ]; then ANY_ERROR=1; fi
}

show() { # show LOGFILE: print findings (errors always, warnings unless quiet)
	if [ "$QUIET" = 1 ]; then
		grep -E 'error|FAIL|ERROR' "$1" | grep -v -E '^(Results:|[0-9]+ (errors|warnings|parse errors))' || true
	else
		cat "$1"
	fi
}

have() { command -v "$1" > /dev/null 2>&1; }

# Generic runner for tools that print `path:line: error: ...` / `path:line: warning: ...`
run_findings() {
	local name="$1"
	shift
	local log="$LOGDIR/$name.log"
	local t0 code e w
	t0=$(now_ms)
	"$@" > "$log" 2>&1
	code=$?
	e=$(grep -c ': error: ' "$log")
	w=$(grep -c ': warning: ' "$log")
	if [ "$code" -ne 0 ] && [ "$e" -eq 0 ]; then e=1; fi # crashed / tool failure
	echo "== $name"
	show "$log"
	if [ "$e" -gt 0 ]; then
		record "$name" FAIL "$e" "$w" $(($(now_ms) - t0))
	else
		record "$name" ok "$e" "$w" $(($(now_ms) - t0))
	fi
}

# --- compile -------------------------------------------------------------------------------------
if have lune; then
	run_findings compile lune run tools/checks/compile.luau src tools
else
	echo "== compile: lune not found (expected in .tools/cargo/bin)"
	record compile FAIL 1 0 0
fi

# --- selene --------------------------------------------------------------------------------------
if have selene; then
	log="$LOGDIR/selene.log"
	t0=$(now_ms)
	selene --display-style=quiet --allow-warnings src > "$log" 2>&1
	code=$?
	echo "== selene"
	if grep -q "feature for it is not enabled" "$log"; then
		echo "selene was built WITHOUT Luau support. Rebuild it with:"
		echo "  cargo install selene --version 0.31.0 --locked --root .tools/cargo   (default features)"
		record selene FAIL 1 0 $(($(now_ms) - t0))
	else
		grep -v -E '^(Results:|[0-9]+ (errors|warnings|parse errors))$' "$log" > "$log.f"
		show "$log.f"
		e=$(grep -c -E ': error\[' "$log")
		w=$(grep -c -E ': warning\[' "$log")
		if [ "$code" -ne 0 ] && [ "$e" -eq 0 ]; then
			cat "$log"
			e=1
		fi
		if [ "$e" -gt 0 ]; then st=FAIL; else st=ok; fi
		record selene "$st" "$e" "$w" $(($(now_ms) - t0))
	fi
else
	echo "== selene: not found (expected in .tools/cargo/bin)"
	record selene FAIL 1 0 0
fi

# --- python checks -------------------------------------------------------------------------------
if have python3; then
	run_findings apicheck python3 tools/checks/apicheck.py
	run_findings conventions python3 tools/checks/conventions.py
	run_findings contracts python3 tools/checks/contracts.py
	run_findings selftest python3 tools/checks/selftest.py
else
	echo "== python3 not found: apicheck/conventions/contracts skipped"
	record python3 FAIL 1 0 0
fi

# --- Lune tests ----------------------------------------------------------------------------------
if have lune; then
	log="$LOGDIR/tests.log"
	t0=$(now_ms)
	lune run tools/lune/run_tests.luau > "$log" 2>&1
	code=$?
	echo "== tests"
	if [ "$QUIET" = 1 ]; then grep -E 'FAILED|  - |ERROR|Ran ' "$log" || true; else cat "$log"; fi
	failed=$(sed -n 's/^FAILED: \([0-9]*\).*/\1/p' "$log" | head -1)
	failed=${failed:-0}
	if [ "$code" -ne 0 ] && [ "$failed" -eq 0 ]; then failed=1; fi
	if [ "$failed" -gt 0 ]; then st=FAIL; else st=ok; fi
	record tests "$st" "$failed" 0 $(($(now_ms) - t0))
fi

# --- place build + verification (into the temp dir; tools/build.sh writes SoulVerdict.rbxl) ---------
if have rojo && have lune; then
	log="$LOGDIR/place.log"
	t0=$(now_ms)
	{ rojo build default.project.json -o "$LOGDIR/check.rbxl" && lune run tools/lune/verify_place.luau "$LOGDIR/check.rbxl"; } > "$log" 2>&1
	code=$?
	echo "== place"
	if [ "$QUIET" = 1 ] && [ "$code" -eq 0 ]; then grep -E 'scripts:|OK' "$log" || true; else cat "$log"; fi
	w=$(grep -c 'WARNING:' "$log")
	if [ "$code" -ne 0 ]; then
		e=$(grep -c 'FAIL:' "$log")
		[ "$e" -eq 0 ] && e=1
		record place FAIL "$e" "$w" $(($(now_ms) - t0))
	else
		record place ok 0 "$w" $(($(now_ms) - t0))
	fi
else
	echo "== place: rojo/lune not found"
	record place FAIL 1 0 0
fi

# --- formatting (informational) --------------------------------------------------------------------
if have stylua; then
	log="$LOGDIR/format.log"
	t0=$(now_ms)
	stylua --check src > "$log" 2>&1
	n=$(grep -c '^Diff in' "$log")
	echo "== format (info): $n files differ from stylua.toml style — format only files you own: stylua <file>"
	record "format(info)" info 0 "$n" $(($(now_ms) - t0))
fi

# --- summary -------------------------------------------------------------------------------------
echo
printf '%-14s %-6s %7s %9s %8s\n' STEP STATUS ERRORS WARNINGS TIME
printf '%-14s %-6s %7s %9s %8s\n' -------------- ------ ------- --------- --------
total_e=0
total_w=0
for i in "${!NAMES[@]}"; do
	printf '%-14s %-6s %7s %9s %7ss\n' "${NAMES[$i]}" "${STATUS[$i]}" "${ERRS[$i]}" "${WARNS[$i]}" \
		"$(awk -v ms="${TIMES[$i]}" 'BEGIN { printf "%.1f", ms / 1000 }')"
	total_e=$((total_e + ${ERRS[$i]}))
	if [ "${STATUS[$i]}" != "info" ]; then total_w=$((total_w + ${WARNS[$i]})); fi
done
printf '%-14s %-6s %7s %9s\n' -------------- ------ ------- ---------
if [ "$ANY_ERROR" = 1 ]; then
	printf '%-14s %-6s %7s %9s\n' TOTAL FAIL "$total_e" "$total_w"
	exit 1
fi
printf '%-14s %-6s %7s %9s\n' TOTAL ok "$total_e" "$total_w"
exit 0
