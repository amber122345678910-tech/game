#!/usr/bin/env bash
# Exports every style, renders preview frames and encodes MP4 files.
#   tools/preview/make.sh [width] [height] [styles...]
set -euo pipefail
cd "$(dirname "$0")/../.."
W=${1:-1280}; H=${2:-720}; shift 2 || true
STYLES=${*:-anime cinema classic}
mkdir -p build/preview
for s in $STYLES; do
  ../.tools/lune run tools/export.luau "$s" "build/$s.json" 30
  rm -rf "build/frames_$s"
  node tools/preview/render.cjs "build/$s.json" "build/frames_$s" "$W" "$H"
  ffmpeg -v error -y -framerate 30 -i "build/frames_$s/f_%04d.png" -c:v libx264 -pix_fmt yuv420p -crf 16 -preset slow "build/preview/$s.mp4"
  echo "build/preview/$s.mp4"
done
