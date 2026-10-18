#!/usr/bin/env python3
"""Проверка ключей в таблицах свойств, которые передаются в UIKit.new / UIKit.label /
UIKit.panel / UIKit.button: каждый ключ должен быть реальным свойством класса Roblox
(по .tools/globalTypes.d.luau) или известным служебным ключом. Ловит ошибки вида
"X is not a valid member of TextLabel", которые строгий анализатор не видит из-за `any`."""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
defs = (ROOT / ".tools" / "globalTypes.d.luau").read_text(encoding="utf-8")

classes = {}
cur = None
for line in defs.splitlines():
    m = re.match(r"declare (?:extern type|class) (\w+)(?: extends (\w+))?", line)
    if m:
        cur = m.group(1)
        classes[cur] = {"base": m.group(2), "props": set()}
        continue
    if cur and line.strip() == "end":
        cur = None
        continue
    if cur:
        m = re.match(r"\s+([A-Za-z_]\w*)\s*:\s*(.+)", line)
        if m and not m.group(2).lstrip().startswith("RBXScriptSignal") and "(self" not in m.group(2):
            classes[cur]["props"].add(m.group(1))

def props_of(cls):
    out = set()
    while cls:
        c = classes.get(cls)
        if not c:
            break
        out |= c["props"]
        cls = c["base"]
    return out

def table_keys(src, start):
    """start указывает на '{'. Возвращает (ключи верхнего уровня, конец)."""
    depth, i, keys, entry_start = 0, start, [], True
    n = len(src)
    while i < n:
        ch = src[i]
        if ch in "\"'":
            q = ch; i += 1
            while i < n and src[i] != q:
                i += 2 if src[i] == "\\" else 1
        elif src.startswith("--", i):
            while i < n and src[i] != "\n":
                i += 1
            continue
        elif ch in "{([":
            depth += 1
            if depth == 1:
                entry_start = True
        elif ch in "})]":
            depth -= 1
            if depth == 0:
                return keys, i
        elif ch in ",;" and depth == 1:
            entry_start = True
        elif depth == 1 and entry_start and not ch.isspace():
            m = re.match(r"([A-Za-z_]\w*)\s*=(?!=)", src[i:])
            if m:
                keys.append(m.group(1))
            entry_start = False
        i += 1
    return keys, i

BUTTON_KEYS = {"Text", "Color", "ColorDark", "Size", "Position", "AnchorPoint", "TextSize", "Parent", "LayoutOrder", "Name", "ZIndex"}
errors = []
checked = 0
for path in sorted((ROOT / "src").rglob("*.luau")):
    src = path.read_text(encoding="utf-8")
    for m in re.finditer(r'UIKit\.(new)\("(\w+)",\s*\{|UIKit\.(label|panel|button)\(\{', src):
        brace = m.end() - 1
        keys, _ = table_keys(src, brace)
        if m.group(1):
            cls = m.group(2)
            allowed = props_of(cls) | {"Parent"}
            if cls not in classes:
                errors.append(f"{path.relative_to(ROOT)}: unknown class {cls}")
                continue
        elif m.group(3) == "label":
            cls = "TextLabel"; allowed = props_of(cls) | {"Parent", "MaxTextSize", "NoStroke"}
        elif m.group(3) == "panel":
            cls = "Frame"; allowed = props_of(cls) | {"Parent"}
        else:
            cls = "ButtonOptions"; allowed = BUTTON_KEYS
        line = src.count("\n", 0, m.start()) + 1
        for k in keys:
            checked += 1
            if k not in allowed:
                errors.append(f"{path.relative_to(ROOT)}:{line}: '{k}' is not a property of {cls}")
print(f"UI property check: {checked} keys checked")
for e in errors:
    print("ERROR:", e)
sys.exit(1 if errors else 0)
