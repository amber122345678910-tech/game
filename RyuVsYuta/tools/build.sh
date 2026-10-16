#!/usr/bin/env bash
# Полная сборка катсцены: тесты -> строгий анализ типов -> Rojo (скрипты) -> Lune (модели, свет) -> проверка.
# Результат: ../RyuVsYuta.rbxl (в корне репозитория).
set -euo pipefail
cd "$(dirname "$0")/.."
T=../.tools
[ -x $T/lune ] || ../tools/setup.sh
$T/lune run tools/tests/run.luau
tools/analyze.sh
mkdir -p build
$T/rojo build default.project.json -o build/base.rbxl
$T/lune run tools/assemble.luau build/base.rbxl ../RyuVsYuta.rbxl
$T/lune run tools/verify_place.luau ../RyuVsYuta.rbxl
echo "Built RyuVsYuta.rbxl"
