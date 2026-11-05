#!/usr/bin/env bash
# Сборка CORE ROULETTE: строгий анализ типов -> тесты Lune -> CoreRoulette.rbxl
# Инструменты: ../tools/setup.sh (rojo, lune, luau-lsp в ../.tools)
set -euo pipefail
cd "$(dirname "$0")"
T=../.tools
$T/rojo sourcemap default.project.json -o sourcemap.json --include-non-scripts >/dev/null
$T/luau-lsp analyze --flag:LuauSolverV2=true --sourcemap sourcemap.json \
  --definitions $T/globalTypes.d.luau --platform roblox src/ 2>&1 \
  | grep -v "^\[INFO\]" | grep -v "client does not allow" || true
$T/lune run tests/run.luau
$T/rojo build default.project.json -o CoreRoulette.rbxl
echo "Built CoreRoulette.rbxl"
