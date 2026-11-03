#!/usr/bin/env bash
# Full build: static analysis -> realizer check (both parts) -> places -> place verification.
# Tools come from the repository root: ../tools/setup.sh downloads them to ../.tools/
set -euo pipefail
cd "$(dirname "$0")/.."
T=../.tools
tools/analyze.sh
$T/lune run tools/check_realizer.luau
$T/rojo build default.project.json -o YutaVsRyu_Part1.rbxl
$T/rojo build part2.project.json -o YutaVsRyu_Part2.rbxl
$T/lune run tools/verify_place.luau YutaVsRyu_Part1.rbxl 1 | tail -1
$T/lune run tools/verify_place.luau YutaVsRyu_Part2.rbxl 2 | tail -1
echo "Built YutaVsRyu_Part1.rbxl and YutaVsRyu_Part2.rbxl"
