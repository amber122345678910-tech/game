#!/usr/bin/env bash
# Скачивает инструменты сборки/проверки в .tools/ (Linux x86_64).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .tools && cd .tools
dl() { curl -sSL -o "$1" "$2"; }
[ -x rojo ] || { dl rojo.zip https://github.com/rojo-rbx/rojo/releases/download/v7.7.1/rojo-7.7.1-linux-x86_64.zip && unzip -o -q rojo.zip && rm rojo.zip; }
[ -x lune ] || { dl lune.zip https://github.com/lune-org/lune/releases/download/v0.10.4/lune-0.10.4-linux-x86_64.zip && unzip -o -q lune.zip && rm lune.zip; }
[ -x luau-lsp ] || { dl lsp.zip https://github.com/JohnnyMorganz/luau-lsp/releases/download/1.70.1/luau-lsp-linux-x86_64.zip && unzip -o -q lsp.zip && rm lsp.zip; }
[ -f globalTypes.d.luau ] || dl globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
chmod +x rojo lune luau-lsp
echo "Tools ready in .tools/"
