#!/usr/bin/env bash
# Side-by-side check video: reference (left) and our preview (right), no audio.
#   tools/preview/compare.sh <reference.mp4> <preview.mp4> <out.mp4> [crop]
#   crop: the picture inside the vertical reference video
#         (part 1: 1080:626:0:647, part 2: 720:416:0:432)
set -euo pipefail
REF=$1; OURS=$2; OUT=$3; CROP=${4:-1080:626:0:647}
F=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
ffmpeg -v error -y -i "$REF" -i "$OURS" -filter_complex "\
[0:v]crop=$CROP,scale=621:360,pad=640:360:9:0:black,fps=30,drawtext=fontfile=$F:text='Оригинал':x=10:y=10:fontsize=18:fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=5[a];\
[1:v]scale=640:360,fps=30,drawtext=fontfile=$F:text='Roblox (превью)':x=10:y=10:fontsize=18:fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=5[b];\
[a][b]hstack=inputs=2[v]" -map "[v]" -an -c:v libx264 -pix_fmt yuv420p -crf 20 -preset medium -shortest "$OUT"
echo "$OUT"
