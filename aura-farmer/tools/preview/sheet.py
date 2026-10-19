#!/usr/bin/env python3
"""Тайлы картинок в один лист (по 2 в ряд): python3 sheet.py out.png a.png b.png ..."""
import sys, math
from PIL import Image, ImageDraw
out, files = sys.argv[1], sorted(sys.argv[2:], key=lambda f: float(f.rsplit('_t', 1)[-1][:-4]) if '_t' in f else 0)
W, H = 640, 360
cols = 2 if len(files) > 1 else 1
rows = math.ceil(len(files) / cols)
sheet = Image.new("RGB", (W * cols, H * rows), (0, 0, 0))
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB").resize((W, H))
    sheet.paste(im, ((i % cols) * W, (i // cols) * H))
sheet.save(out)
print(out)
