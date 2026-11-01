#!/usr/bin/env bash
# tools/build.sh — gate + build + verify the place file.
#   1. tools/check.sh                       (aborts the build on any ERROR unless --force)
#   2. rojo build default.project.json -o SoulVerdict.rbxl
#   3. lune run tools/lune/verify_place.luau SoulVerdict.rbxl
# Usage: tools/build.sh [--force] [--skip-check] [-o OUTPUT.rbxl]
#   --force       build even if check.sh reports errors (the check still runs and is reported)
#   --skip-check  do not run check.sh at all
#   -o PATH       output place file (default: SoulVerdict.rbxl in the project root)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
export PATH="$ROOT/.tools/cargo/bin:$PATH"

FORCE=0
SKIP=0
OUT="SoulVerdict.rbxl"
while [ $# -gt 0 ]; do
	case "$1" in
		--force) FORCE=1 ;;
		--skip-check) SKIP=1 ;;
		-o)
			shift
			OUT="${1:?-o needs a path}"
			;;
		-h | --help)
			sed -n '2,10p' "$0"
			exit 0
			;;
		*)
			echo "build.sh: unknown argument $1"
			exit 2
			;;
	esac
	shift
done

CHECK_STATUS=0
if [ "$SKIP" = 0 ]; then
	tools/check.sh -q
	CHECK_STATUS=$?
	if [ "$CHECK_STATUS" -ne 0 ] && [ "$FORCE" = 0 ]; then
		echo "build.sh: check.sh failed — not building (use --force to build anyway)"
		exit 1
	fi
fi

echo "== rojo build -> $OUT"
if ! rojo build default.project.json -o "$OUT"; then
	echo "build.sh: rojo build failed"
	exit 1
fi

echo "== verify_place"
if ! lune run tools/lune/verify_place.luau "$OUT"; then
	echo "build.sh: place verification failed"
	exit 1
fi

if [ "$CHECK_STATUS" -ne 0 ]; then
	echo "build.sh: built $OUT, but check.sh reported errors (--force)"
	exit 1
fi
echo "build.sh: OK -> $OUT"
