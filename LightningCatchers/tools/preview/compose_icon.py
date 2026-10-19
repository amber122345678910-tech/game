#!/usr/bin/env python3
# Шрифты: Montserrat Black Italic (логотип, теги) и Nunito ExtraBold (подзаголовок) — Google Fonts, лицензия OFL.
"""Иконка (512x512) и обложка (1920x1080) игры из офлайн-рендеров сцены tools/preview/icon_scene.luau.
Логотип по docs/STYLE.md §10: две строки, «МОЛНИЙ» на 15% крупнее, наклон, градиент 3 цвета,
двойная обводка, жёсткая тень, голубое свечение, зигзаг-молния за буквами.
python3 compose_icon.py <квадрат.png> <широкий.png> <MontserratBlackItalic.ttf> <NunitoExtraBold.ttf> <папка>"""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageEnhance, ImageFilter

sq_path, wide_path, display_path, body_path, out_dir = sys.argv[1:6]
os.makedirs(out_dir, exist_ok=True)

FILL = [(255, 248, 190), (255, 212, 60), (242, 146, 22)]
INNER = (58, 26, 110)
INK = (14, 10, 32)
SPARK = (80, 210, 255)
CREAM = (255, 248, 232)


def grade(img):
    img = ImageEnhance.Color(img).enhance(1.25)
    return ImageEnhance.Contrast(img).enhance(1.1)


def vignette(img, strength=0.4):
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    for i in range(60):
        t = i / 60
        d.ellipse([-w * 0.25 + t * w * 0.2, -h * 0.25 + t * h * 0.2, w * 1.25 - t * w * 0.2, h * 1.25 - t * h * 0.2], fill=int(255 * t))
    mask = mask.filter(ImageFilter.GaussianBlur(w // 20))
    dark = Image.new("RGB", (w, h), (10, 8, 28))
    return Image.composite(img, Image.blend(img, dark, strength), mask)


def text_mask(size, text, font, offset, stroke=0):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).text(offset, text, font=font, fill=255, stroke_width=stroke, stroke_fill=255)
    return m


def gradient(size, top, bottom, stops):
    w, h = size
    g = Image.new("RGBA", size)
    d = ImageDraw.Draw(g)
    for y in range(h):
        t = min(1, max(0, (y - top) / max(1, bottom - top)))
        if t < 0.5:
            a, b, k = stops[0], stops[1], t / 0.5
        else:
            a, b, k = stops[1], stops[2], (t - 0.5) / 0.5
        c = tuple(int(a[i] + (b[i] - a[i]) * k) for i in range(3))
        d.line([(0, y), (w, y)], fill=c + (255,))
    return g


def logo_word(text, font, cap_h):
    """Одно слово логотипа на прозрачном фоне."""
    outer = max(2, int(cap_h * 0.07))
    inner = max(1, int(cap_h * 0.035))
    shadow = max(2, int(cap_h * 0.06))
    glow = max(2, int(cap_h * 0.15))
    tmp = ImageDraw.Draw(Image.new("L", (4, 4)))
    bb = tmp.textbbox((0, 0), text, font=font, stroke_width=outer)
    pad = glow * 2 + shadow
    w, h = bb[2] - bb[0] + pad * 2, bb[3] - bb[1] + pad * 2
    off = (pad - bb[0], pad - bb[1])
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # свечение
    gm = text_mask((w, h), text, font, off, outer).filter(ImageFilter.GaussianBlur(glow))
    layer.paste(Image.new("RGBA", (w, h), SPARK + (255,)), (0, 0), gm.point(lambda v: int(v * 0.4)))
    # жёсткая тень
    sm = text_mask((w, h), text, font, (off[0], off[1] + shadow), outer)
    layer.paste(Image.new("RGBA", (w, h), INK + (255,)), (0, 0), sm)
    # внешняя обводка
    layer.paste(Image.new("RGBA", (w, h), INK + (255,)), (0, 0), text_mask((w, h), text, font, off, outer))
    # внутренняя обводка
    layer.paste(Image.new("RGBA", (w, h), INNER + (255,)), (0, 0), text_mask((w, h), text, font, off, inner))
    # заливка градиентом
    fill_mask = text_mask((w, h), text, font, off)
    tb = tmp.textbbox(off, text, font=font)
    layer.paste(gradient((w, h), tb[1], tb[3], FILL), (0, 0), fill_mask)
    # блик по верхней трети
    shine = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shine).rectangle([0, tb[1], w, tb[1] + (tb[3] - tb[1]) * 0.3], fill=60)
    layer.paste(Image.new("RGBA", (w, h), (255, 255, 255, 255)), (0, 0), Image.composite(shine, Image.new("L", (w, h), 0), fill_mask))
    return layer


BOLT = [(0.62, 0.0), (0.18, 0.56), (0.44, 0.56), (0.30, 1.0), (0.86, 0.38), (0.58, 0.38), (0.80, 0.0)]


def bolt(size, box, outline):
    """Силуэт молнии (заливка Cream→Volt, обводка Ink) в прямоугольнике box = (x, y, w, h)."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    x, y, w, h = box
    pts = [(x + px * w, y + py * h) for px, py in BOLT]
    d = ImageDraw.Draw(layer)
    d.polygon(pts, fill=INK + (255,))
    d.line(pts + [pts[0]], fill=INK + (255,), width=int(outline * 2), joint="curve")
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    m = m.filter(ImageFilter.MinFilter(max(3, int(outline) | 1)))
    layer.paste(gradient(size, y, y + h, [CREAM, (255, 236, 120), (255, 196, 40)]), (0, 0), m)
    return layer


def logo(width, display_path, cap_frac=0.13):
    """Двухстрочный логотип «ЛОВЦЫ / МОЛНИЙ» шириной примерно width."""
    size1 = int(width * cap_frac * 1.32)
    f1 = ImageFont.truetype(display_path, size1)
    f2 = ImageFont.truetype(display_path, int(size1 * 1.15))
    cap = f1.getbbox("Л")[3] - f1.getbbox("Л")[1]
    w1 = logo_word("ЛОВЦЫ", f1, cap)
    w2 = logo_word("МОЛНИЙ", f2, int(cap * 1.15))
    W = max(w1.width, w2.width) + cap * 2
    H = int(w1.height * 0.78 + w2.height)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # молния за буквами: справа, между строками
    canvas.alpha_composite(bolt((W, H), (W - cap * 2.5, H * 0.0, cap * 2.3, H * 0.98), cap * 0.08))
    canvas.alpha_composite(w1, (int((W - w1.width) / 2 - cap * 0.25), 0))
    canvas.alpha_composite(w2, (int((W - w2.width) / 2 + cap * 0.2), int(w1.height * 0.78)))
    return canvas.rotate(4, resample=Image.BICUBIC, expand=True)


def tag(text, font_path, height):
    """Стикер-тег: лента Ink, наклон, FontDisplay."""
    f = ImageFont.truetype(font_path, int(height * 0.62))
    bb = ImageDraw.Draw(Image.new("L", (4, 4))).textbbox((0, 0), text, font=f)
    w = bb[2] - bb[0] + int(height * 0.9)
    img = Image.new("RGBA", (w + 16, height + 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon([(8 + height * 0.25, 8), (8 + w, 8), (8 + w - height * 0.25, 8 + height), (8, 8 + height)], fill=INK + (255,))
    d.polygon([(8 + height * 0.25, 8), (8 + w, 8), (8 + w - height * 0.12, 8 + height * 0.18), (8 + height * 0.15, 8 + height * 0.18)], fill=(255, 210, 60, 255))
    d.text((8 + height * 0.45 - bb[0], 8 + height * 0.5 - (bb[1] + bb[3]) / 2), text, font=f, fill=CREAM)
    return img.rotate(4, resample=Image.BICUBIC, expand=True)


# ---------------- иконка ----------------
sq = vignette(grade(Image.open(sq_path).convert("RGB")), 0.32).convert("RGBA")
S = sq.width
lg = logo(int(S * 0.92), display_path)
scale = min(S * 0.96 / lg.width, S * 0.40 / lg.height)
lg = lg.resize((int(lg.width * scale), int(lg.height * scale)), Image.LANCZOS)
sq.alpha_composite(lg, (int((S - lg.width) / 2), int(S - lg.height - S * 0.015)))
sq.convert("RGB").resize((512, 512), Image.LANCZOS).save(os.path.join(out_dir, "icon_512.png"))
sq.convert("RGB").save(os.path.join(out_dir, "icon_1024.png"))

# ---------------- обложка ----------------
wide = vignette(grade(Image.open(wide_path).convert("RGB")), 0.28).convert("RGBA")
W, H = wide.size
shade = Image.new("L", (W, H), 0)
sd = ImageDraw.Draw(shade)
for x in range(int(W * 0.55)):
    sd.line([(x, 0), (x, H)], fill=int(140 * (1 - x / (W * 0.55)) ** 1.6))
wide.paste(Image.new("RGBA", (W, H), (8, 6, 26, 255)), (0, 0), shade)
lg = logo(int(W * 0.5), display_path)
scale = min(W * 0.48 / lg.width, H * 0.62 / lg.height)
lg = lg.resize((int(lg.width * scale), int(lg.height * scale)), Image.LANCZOS)
wide.alpha_composite(lg, (int(W * 0.02), int(H * 0.08)))
fsub = ImageFont.truetype(body_path, int(H * 0.05))
sub = Image.new("RGBA", (W, int(H * 0.1)), (0, 0, 0, 0))
ImageDraw.Draw(sub).text((0, 0), "Лови молнию в нужный момент!", font=fsub, fill=CREAM, stroke_width=int(H * 0.006), stroke_fill=INK)
sub = sub.crop(sub.getbbox())
wide.alpha_composite(sub.rotate(4, resample=Image.BICUBIC, expand=True), (int(W * 0.06), int(H * 0.08 + lg.height + H * 0.02)))
t = tag("ИДЕАЛЬНО!", display_path, int(H * 0.08))
wide.alpha_composite(t, (int(W * 0.72), int(H * 0.1)))
wide.convert("RGB").save(os.path.join(out_dir, "thumbnail_1920x1080.png"))
print("saved to", out_dir)
