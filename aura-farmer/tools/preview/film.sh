#!/usr/bin/env bash
# Обзор всего ролика: по K кадров на план, «референс | рендер».
#   tools/preview/film.sh [K=2] [папка=build/preview/film]
set -euo pipefail
cd "$(dirname "$0")/../.."
K=${1:-2}
OUT=${2:-build/preview/film}
mkdir -p "$OUT"
TIMES=$(python3 - "$K" <<'PY'
import sys
k=int(sys.argv[1])
cuts=[0,1.4333,2.7,3.8667,4.9667,5.9,6.6,7.8667,9.5333,11.1333,13.1333,15.6333]
ts=[]
for a,b in zip(cuts,cuts[1:]):
    for i in range(k):
        ts.append(round(a+(i+0.5)/k*(b-a),3))
print(",".join(map(str,ts)))
PY
)
rm -f "$OUT"/S*_t*.png
../.tools/lune run tools/preview/dump.luau "$OUT/frames.json" --times "$TIMES"
node tools/preview/render.mjs "$OUT/frames.json" "$OUT" ${W:-960} ${H:-540} >/dev/null
python3 tools/preview/compare.py "$OUT/compare.png" $(ls "$OUT"/S*_t*.png | sort -t_ -k2)
