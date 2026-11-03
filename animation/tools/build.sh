#!/usr/bin/env bash
# Full build: static analysis -> realizer check -> place -> place verification.
# Tools come from the repository root: ../tools/setup.sh downloads them to ../.tools/
set -euo pipefail
cd "$(dirname "$0")/.."
T=../.tools
tools/analyze.sh
$T/lune run tools/check_realizer.luau
$T/rojo build default.project.json -o YutaVsRyu_StyleTest.rbxl
$T/lune run tools/verify_place.luau YutaVsRyu_StyleTest.rbxl | tail -1
echo "Built YutaVsRyu_StyleTest.rbxl"
