#!/usr/bin/env bash
# Строгий статический анализ Luau-кода катсцены с типами Roblox API (luau-lsp).
set -uo pipefail
cd "$(dirname "$0")/.."
T=../.tools
$T/rojo sourcemap default.project.json -o sourcemap.json --include-non-scripts >/dev/null
OUT=$($T/luau-lsp analyze --flag:LuauSolverV2=true --sourcemap sourcemap.json \
  --definitions $T/globalTypes.d.luau --platform roblox \
  --ignore "tools/**" src/ 2>&1)
CODE=$?
echo "$OUT" | grep -v "^\[INFO\]" | grep -v "^\[WARN\] client does not allow" | awk '!seen[$0]++'
exit $CODE
