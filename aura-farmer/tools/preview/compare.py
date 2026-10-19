#!/usr/bin/env python3
"""Склеивает пары [референс | рендер] в один лист: python3 compare.py out.png render1.png render2.png ...
Время берётся из имени файла рендера (..._tX.XXX.png); референс — кадр all_NNNN.jpg из REF_DIR."""
import os, re, sys
from PIL import Image, ImageDraw
REF = os.environ.get("REF_DIR", "/tmp/claude-0/-home-user-game/112adbfb-3fe9-56d6-b349-6b4853bc6dde/scratchpad/ref")
out, files = sys.argv[1], sys.argv[2:]
W, H = 640, 360
rows = []
for f in files:
    m = re.search(r"_t([0-9.]+)\.png$", f)
    t = float(m.group(1)) if m else 0
    n = round(t * 30) + 1
    ref = os.path.join(REF, f"all_{n:04d}.jpg")
    row = Image.new("RGB", (W * 2, H), (0, 0, 0))
    if os.path.exists(ref):
        row.paste(Image.open(ref).convert("RGB").resize((W, H)), (0, 0))
    row.paste(Image.open(f).convert("RGB").resize((W, H)), (W, 0))
    d = ImageDraw.Draw(row)
    d.rectangle([0, 0, 150, 22], fill=(0, 0, 0)); d.text((6, 5), f"REF t={t:.3f}", fill=(255, 255, 0))
    d.rectangle([W, 0, W + 170, 22], fill=(0, 0, 0)); d.text((W + 6, 5), f"ROBLOX t={t:.3f}", fill=(0, 255, 255))
    rows.append(row)
sheet = Image.new("RGB", (W * 2, H * len(rows)), (0, 0, 0))
for i, r in enumerate(rows):
    sheet.paste(r, (0, i * H))
sheet.save(out)
print(out)
