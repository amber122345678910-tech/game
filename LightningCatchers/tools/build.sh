#!/usr/bin/env bash
# Полная сборка: карта -> тесты -> баланс -> анализ -> локализация -> проверка UI -> .rbxl -> проверка места
set -euo pipefail
cd "$(dirname "$0")/.."
T=.tools
$T/lune run tools/gen_map.luau
$T/lune run tools/tests/run.luau
$T/lune run tools/tests/balance.luau 1 | tail -1
tools/analyze.sh
python3 tools/check_loc.py | tail -1
python3 tools/check_ui_props.py
$T/rojo build default.project.json -o LightningCatchers.rbxl
$T/lune run tools/verify_place.luau LightningCatchers.rbxl
echo "Собрано: LightningCatchers.rbxl"
