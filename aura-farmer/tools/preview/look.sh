#!/usr/bin/env bash
# Осмотр персонажа/декорации: лист с видами в одной картинке.
#   tools/preview/look.sh char Horse [views] [outdir]          (views: front,three,side,back,head,headside,hands,hand,feet,torso)
#   tools/preview/look.sh set Beach "0,6,-30>0,4,0@50;..." [outdir]
#   EXTRA="--keys tools/anims/test_pose.luau --t 0" tools/preview/look.sh char Horse hands
set -euo pipefail
cd "$(dirname "$0")/../.."
KIND=${1:?char|set}
NAME=${2:?name}
ARG=${3:-}
OUT=${4:-build/look/${KIND}_${NAME}}
mkdir -p "$OUT"
rm -f "$OUT"/LOOK_*.png
if [ "$KIND" = char ]; then
  ../.tools/lune run tools/preview/look.luau "$OUT/frames.json" --char "$NAME" --views "${ARG:-front,three,side,head}" ${EXTRA:-}
else
  ../.tools/lune run tools/preview/look.luau "$OUT/frames.json" --set "$NAME" --cams "${ARG:-0,6,-30>0,4,0@50}" ${EXTRA:-}
fi
node tools/preview/render.mjs "$OUT/frames.json" "$OUT" ${W:-960} ${H:-540} >/dev/null
python3 tools/preview/sheet.py "$OUT/sheet.png" "$OUT"/LOOK_*.png
