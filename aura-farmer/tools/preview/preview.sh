#!/usr/bin/env bash
# Превью плана: сборка в памяти -> JSON -> рендер three.js -> лист «референс | рендер».
#   tools/preview/preview.sh S04 [кадров=4] [папка=build/preview/S04]
#   TIMES=4.0,4.5 tools/preview/preview.sh S04
set -euo pipefail
cd "$(dirname "$0")/../.."
SHOT=${1:?shot id}
N=${2:-4}
OUT=${3:-build/preview/$SHOT}
mkdir -p "$OUT"
LUNE=../.tools/lune
if [ -n "${TIMES:-}" ]; then
  $LUNE run tools/preview/dump.luau "$OUT/frames.json" --shot "$SHOT" --times "$TIMES"
else
  $LUNE run tools/preview/dump.luau "$OUT/frames.json" --shot "$SHOT" --n "$N"
fi
rm -f "$OUT"/${SHOT}_t*.png
node tools/preview/render.mjs "$OUT/frames.json" "$OUT" ${W:-1280} ${H:-720} >/dev/null
python3 tools/preview/compare.py "$OUT/compare.png" $(ls "$OUT"/${SHOT}_t*.png | sort)
