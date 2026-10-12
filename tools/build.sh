#!/usr/bin/env bash
# Полная сборка: карта -> тесты -> строгий анализ -> проверка UI -> .rbxl -> проверка места
set -euo pipefail
cd "$(dirname "$0")/.."
T=.tools
$T/lune run tools/gen_map.luau
$T/lune run tools/tests/run.luau
tools/analyze.sh
python3 tools/check_ui_props.py
$T/rojo build default.project.json -o AmberAlert.rbxl
$T/lune run tools/verify_place.luau AmberAlert.rbxl
echo "Built AmberAlert.rbxl"
