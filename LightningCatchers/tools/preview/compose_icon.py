#!/usr/bin/env python3
# Шрифт названия: Russo One (OFL), https://fonts.google.com/specimen/Russo+One
"""Иконка (512x512) и обложка (1920x1080) игры из офлайн-рендеров сцены tools/preview/icon_scene.luau.
python3 compose_icon.py <рендер_квадрат.png> <рендер_широкий.png> <шрифт.ttf> <папка_вывода>"""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageEnhance, ImageFilter

sq_path, wide_path, font_path, out_dir = sys.argv[1:5]
os.makedirs(out_dir, exist_ok=True)

GOLD_TOP = (255, 246, 150)
GOLD_BOTTOM = (255, 160, 20)
OUTLINE = (18, 22, 60)


def grade(img):
    """Сочнее цвета и контраст (как в превью-картинках Roblox)."""
    img = ImageEnhance.Color(img).enhance(1.3)
    img = ImageEnhance.Contrast(img).enhance(1.12)
    return img


def vignette(img, strength=0.45):
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    for i in range(60):
        t = i / 60
        d.ellipse([-w * 0.25 + t * w * 0.2, -h * 0.25 + t * h * 0.2, w * 1.25 - t * w * 0.2, h * 1.25 - t * h * 0.2], fill=int(255 * t))
    mask = mask.filter(ImageFilter.GaussianBlur(w // 20))
    dark = Image.new("RGB", (w, h), (8, 10, 30))
    return Image.composite(img, Image.blend(img, dark, strength), mask)


def gradient_text(size, text, font, top, bottom, stroke, outline, shadow_offset):
    """Текст с вертикальным градиентом, толстой обводкой и тенью. Возвращает RGBA и смещение."""
    tmp = Image.new("L", (10, 10))
    bbox = ImageDraw.Draw(tmp).textbbox((0, 0), text, font=font, stroke_width=stroke)
    w, h = bbox[2] - bbox[0] + shadow_offset * 2 + 8, bbox[3] - bbox[1] + shadow_offset * 2 + 8
    ox, oy = -bbox[0] + 4, -bbox[1] + 4
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # тень
    sh = Image.new("L", (w, h), 0)
    ImageDraw.Draw(sh).text((ox + shadow_offset, oy + shadow_offset), text, font=font, fill=255, stroke_width=stroke, stroke_fill=255)
    sh = sh.filter(ImageFilter.GaussianBlur(max(1, shadow_offset // 2)))
    layer.paste(Image.new("RGBA", (w, h), (0, 0, 0, 170)), (0, 0), sh)
    # обводка
    ol = Image.new("L", (w, h), 0)
    ImageDraw.Draw(ol).text((ox, oy), text, font=font, fill=255, stroke_width=stroke, stroke_fill=255)
    layer.paste(Image.new("RGBA", (w, h), outline + (255,)), (0, 0), ol)
    # заливка градиентом
    fill_mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(fill_mask).text((ox, oy), text, font=font, fill=255)
    grad = Image.new("RGBA", (w, h))
    gd = ImageDraw.Draw(grad)
    t0, t1 = oy + bbox[1], oy + bbox[3]
    for y in range(h):
        t = min(1, max(0, (y - t0) / max(1, (t1 - t0))))
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        gd.line([(0, y), (w, y)], fill=c + (255,))
    layer.paste(grad, (0, 0), fill_mask)
    # блик в верхней трети букв
    shine = Image.new("L", (w, h), 0)
    sd = ImageDraw.Draw(shine)
    sd.rectangle([0, t0, w, t0 + (t1 - t0) * 0.32], fill=70)
    shine = Image.composite(shine, Image.new("L", (w, h), 0), fill_mask)
    layer.paste(Image.new("RGBA", (w, h), (255, 255, 255, 255)), (0, 0), shine)
    return layer


def paste_rotated(base, layer, center, angle):
    rot = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    x = int(center[0] - rot.width / 2)
    y = int(center[1] - rot.height / 2)
    base.alpha_composite(rot, (x, y))


def badge(text, font, fill, outline, pad=18):
    tmp = Image.new("L", (10, 10))
    bbox = ImageDraw.Draw(tmp).textbbox((0, 0), text, font=font)
    w, h = bbox[2] - bbox[0] + pad * 2, bbox[3] - bbox[1] + pad * 2
    img = Image.new("RGBA", (w + 8, h + 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([4, 4, w + 4, h + 4], radius=h // 2, fill=fill, outline=outline, width=6)
    d.text((4 + pad - bbox[0], 4 + pad - bbox[1]), text, font=font, fill=(255, 255, 255), stroke_width=3, stroke_fill=outline)
    return img


# ---------------- иконка ----------------
sq = grade(Image.open(sq_path).convert("RGB"))
sq = vignette(sq, 0.35).convert("RGBA")
S = sq.width  # 1024
f1 = ImageFont.truetype(font_path, int(S * 0.165))
f2 = ImageFont.truetype(font_path, int(S * 0.185))
line1 = gradient_text(S, "ЛОВЦЫ", f1, GOLD_TOP, GOLD_BOTTOM, int(S * 0.016), OUTLINE, int(S * 0.012))
line2 = gradient_text(S, "МОЛНИЙ", f2, GOLD_TOP, GOLD_BOTTOM, int(S * 0.018), OUTLINE, int(S * 0.012))
paste_rotated(sq, line1, (S * 0.5, S * 0.74), 4)
paste_rotated(sq, line2, (S * 0.5, S * 0.885), 4)
icon = sq.convert("RGB").resize((512, 512), Image.LANCZOS)
icon.save(os.path.join(out_dir, "icon_512.png"))
sq.convert("RGB").save(os.path.join(out_dir, "icon_1024.png"))

# ---------------- обложка ----------------
wide = grade(Image.open(wide_path).convert("RGB"))
wide = vignette(wide, 0.3).convert("RGBA")
W, H = wide.size
# затемнение слева под текст
shade = Image.new("L", (W, H), 0)
sd = ImageDraw.Draw(shade)
for x in range(int(W * 0.55)):
    sd.line([(x, 0), (x, H)], fill=int(150 * (1 - x / (W * 0.55)) ** 1.5))
wide.paste(Image.new("RGBA", (W, H), (6, 8, 28, 255)), (0, 0), shade)
ft1 = ImageFont.truetype(font_path, int(H * 0.17))
ft2 = ImageFont.truetype(font_path, int(H * 0.19))
fsub = ImageFont.truetype(font_path, int(H * 0.05))
t1 = gradient_text(W, "ЛОВЦЫ", ft1, GOLD_TOP, GOLD_BOTTOM, int(H * 0.016), OUTLINE, int(H * 0.012))
t2 = gradient_text(W, "МОЛНИЙ", ft2, GOLD_TOP, GOLD_BOTTOM, int(H * 0.018), OUTLINE, int(H * 0.012))
paste_rotated(wide, t1, (W * 0.25, H * 0.26), 3)
paste_rotated(wide, t2, (W * 0.25, H * 0.45), 3)
sub = gradient_text(W, "Лови молнию в нужный момент!", fsub, (210, 240, 255), (120, 200, 255), int(H * 0.007), OUTLINE, int(H * 0.006))
paste_rotated(wide, sub, (W * 0.25, H * 0.6), 2)
fb = ImageFont.truetype(font_path, int(H * 0.055))
b1 = badge("ИДЕАЛЬНО!", fb, (255, 190, 30, 255), OUTLINE)
paste_rotated(wide, b1, (W * 0.8, H * 0.2), -8)
b2 = badge("x25 КОМБО", fb, (150, 90, 255, 255), OUTLINE)
paste_rotated(wide, b2, (W * 0.16, H * 0.82), 6)
b3 = badge("+1.2M ВОЛЬТ", fb, (40, 170, 90, 255), OUTLINE)
paste_rotated(wide, b3, (W * 0.84, H * 0.86), -5)
wide.convert("RGB").save(os.path.join(out_dir, "thumbnail_1920x1080.png"))
print("saved to", out_dir)
