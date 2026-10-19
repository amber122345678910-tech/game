#!/usr/bin/env python3
"""Проверка локализации (src/shared/Loc.luau, словари src/shared/Strings/*.luau).

Ошибки (код возврата 1):
  * ключ из Loc.t / Loc.tl / Loc.msg / Loc.plural / Loc.pmsg / Loc.setWorldText без перевода;
  * перевод с другими плейсхолдерами string.format (%d, %s, %.1f, %%), чем у исходника;
  * формы множественного числа: у исходника 3 через «|», у перевода 2;
  * один ключ в двух словарях с разным переводом;
  * имена и описания в данных src/shared (Name/Desc/Title/Text = "…" по-русски) без перевода;
  * таблички карты (Text = "…" в tools/map) без перевода;
  * русская строка в коде, не обёрнутая в Loc.* (кроме warn/print/error, комментариев и строк с пометкой `-- noloc`).
  * в переводе остались русские буквы.
Запуск из LightningCatchers/: python3 tools/check_loc.py [--verbose]
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CYR = re.compile(r"[А-Яа-яЁё]")
STR = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
ENTRY = re.compile(r'^\s*\[\s*"((?:[^"\\]|\\.)*)"\s*\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*,?\s*(--.*)?$')
PH = re.compile(r"%[-+ #0]*\d*(?:\.\d+)?[sdifgxXqc%]")
LOC_CALL = re.compile(r"Loc\.(t|tl|msg|plural|pmsg|setWorldText|has|tc)\(")
# позиция строки внутри вызова Loc.*: до неё не больше двух простых аргументов
WRAPPED = re.compile(r"Loc\.(?:t|tl|msg|plural|pmsg|setWorldText|has)\(\s*(?:[^,()\"]*(?:\([^()]*\))?[^,()\"]*,\s*){0,2}$")
DATA_FIELD = re.compile(r'\b(Name|Desc|Title|Text|Hint|Label)\s*=\s*"((?:[^"\\\n]|\\.)*)"')

verbose = "--verbose" in sys.argv
errors = []
warnings = []


def unescape(s):
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def plain(key):
    i = key.find("::")
    return key[i + 2:] if i >= 0 else key


# ---------------------------------------------------------------- словари
strings_dir = os.path.join(ROOT, "src/shared/Strings")
EN = {}
where = {}
for fn in sorted(os.listdir(strings_dir)):
    if not fn.endswith(".luau"):
        continue
    path = os.path.join(strings_dir, fn)
    for ln, line in enumerate(open(path, encoding="utf-8"), 1):
        m = ENTRY.match(line)
        if not m:
            if '"] =' in line or '" ] =' in line:
                errors.append(f"{fn}:{ln}: не разобрана строка словаря: {line.strip()[:100]}")
            continue
        k, v = unescape(m.group(1)), unescape(m.group(2))
        if k in EN and EN[k] != v:
            errors.append(f"{fn}:{ln}: ключ «{k}» уже переведён иначе в {where[k]}: «{EN[k]}» ≠ «{v}»")
            continue
        EN[k] = v
        where[k] = f"{fn}:{ln}"
        if CYR.search(v):
            errors.append(f"{fn}:{ln}: в переводе русские буквы: «{v}»")
        if PH.findall(plain(k)) != PH.findall(v):
            errors.append(f"{fn}:{ln}: плейсхолдеры не совпадают: «{k}» {PH.findall(plain(k))} → «{v}» {PH.findall(v)}")
        if "|" in k:
            nk, nv = len(plain(k).split("|")), len(v.split("|"))
            if nk == 3 and nv != 2:
                errors.append(f"{fn}:{ln}: множественное число: у «{k}» 3 формы, у перевода «{v}» должно быть 2")

used = set()


def need(key, loc):
    used.add(key)
    if key in EN:
        return
    if "::" in key and plain(key) in EN:
        return
    errors.append(f"{loc}: нет перевода для «{key}»")


# ---------------------------------------------------------------- код
def strip_comment(line):
    # убрать комментарий, не трогая «--» внутри строк
    out, i, q = [], 0, None
    while i < len(line):
        c = line[i]
        if q:
            out.append(c)
            if c == "\\" and i + 1 < len(line):
                out.append(line[i + 1])
                i += 2
                continue
            if c == q:
                q = None
        else:
            if c in "\"'":
                q = c
            elif line.startswith("--", i):
                break
            out.append(c)
        i += 1
    return "".join(out)


def scan(path, rel, is_map):
    text = open(path, encoding="utf-8").read()
    in_block = False
    for ln, raw in enumerate(text.split("\n"), 1):
        line = raw
        if in_block:
            if "]]" in line:
                in_block = False
                line = line.split("]]", 1)[1]
            else:
                continue
        if re.match(r"^\s*--\[(=*)\[", line):
            if "]]" not in line:
                in_block = True
            continue
        noloc = "noloc" in raw
        code = strip_comment(line)
        if not CYR.search(code):
            continue
        loc = f"{rel}:{ln}"
        logline = re.search(r"\b(warn|print|error|assert)\s*\(", code) is not None
        for m in STR.finditer(code):
            s = unescape(m.group(1))
            if not CYR.search(s):
                continue
            before = code[: m.start()]
            if WRAPPED.search(before):
                need(s, loc)
                continue
            if is_map and re.search(r"\bText\s*=\s*$", before):
                need(s, loc)
                continue
            if rel.startswith("src/shared/") and DATA_FIELD.search(code[max(0, m.start() - 12): m.end() + 1]):
                # данные (Config, Pets, …): показываются через Loc.t(def.Name) — перевод обязателен
                need(s, loc)
                continue
            if logline or noloc:
                continue
            if s in EN or (("::" in s) and plain(s) in EN):
                # исходник, который где-то переводится (аргумент Loc.msg, имя в таблице) — допустим
                used.add(s)
                continue
            errors.append(f"{loc}: русская строка без Loc.*: «{s[:80]}» (оберни в Loc.t/Loc.msg или пометь `-- noloc`)")


scan_dirs = [("src", False), ("tools/map", True), ("tools/lib", True)]
for d, is_map in scan_dirs:
    base = os.path.join(ROOT, d)
    for dp, _, files in os.walk(base):
        if os.path.join("src", "shared", "Strings") in dp:
            continue
        for fn in files:
            if fn.endswith(".luau"):
                path = os.path.join(dp, fn)
                rel = os.path.relpath(path, ROOT)
                scan(path, rel, is_map)

unused = [k for k in EN if k not in used]
if verbose:
    for k in unused:
        warnings.append(f"не используется (может, ключ динамический): «{k}» ({where[k]})")

for w in warnings:
    print("  [warn]", w)
for e in errors:
    print("  [ERR]", e)
print(f"Локализация: {len(EN)} переводов, {len(used)} ключей в коде, ошибок: {len(errors)}")
sys.exit(1 if errors else 0)
