#!/usr/bin/env bash
# Полная сборка AuraFarmer.rbxl: тесты -> анализ типов -> Rojo (скрипты) -> Lune (мир, риги, анимации) -> проверка.
set -euo pipefail
cd "$(dirname "$0")/.."
T=../.tools
mkdir -p build
$T/lune run tools/tests/run.luau
tools/analyze.sh
$T/rojo build default.project.json -o build/base.rbxl
$T/lune run tools/build.luau build/base.rbxl AuraFarmer.rbxl
$T/lune run tools/verify.luau AuraFarmer.rbxl
$T/lune run tools/tests/runtime_sim.luau AuraFarmer.rbxl
echo "Built AuraFarmer.rbxl"
