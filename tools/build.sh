#!/usr/bin/env bash
# Полная сборка: карта -> тесты -> анализ -> .rbxl
set -euo pipefail
cd "$(dirname "$0")/.."
T=.tools
$T/lune run tools/gen_map.luau
$T/lune run tools/tests/run.luau
tools/analyze.sh
$T/rojo build default.project.json -o BunkerSimulator.rbxl
$T/lune run tools/verify_place.luau BunkerSimulator.rbxl
echo "Built BunkerSimulator.rbxl"
