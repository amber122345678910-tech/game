# Рисует PNG-иконки (для Android 7 и для превью) по тем же координатам, что и векторная иконка.
import sys
from PIL import Image, ImageDraw

RECTS = [  # (цвет, x, y, w, h) в единицах 108
    ('#FFD23F', 0, 0, 108, 108), ('#FFC20E', 0, 78, 108, 30),
    ('#111111', 22, 78, 64, 16), ('#F2C9A0', 32, 34, 44, 44), ('#D9A97C', 70, 34, 6, 44),
    ('#2B1D10', 30, 28, 48, 10), ('#2B1D10', 30, 38, 6, 6),
    ('#111111', 30, 48, 48, 4), ('#111111', 35, 50, 16, 9), ('#111111', 57, 50, 16, 9),
    ('#FFFFFF', 38, 52, 5, 2), ('#FFFFFF', 60, 52, 5, 2),
    ('#111111', 44, 67, 22, 3), ('#111111', 63, 63, 3, 4),
]

def render(size, crop=(14, 14, 94, 94), round_=True):
    big = size * 4
    x0, y0, x1, y1 = crop
    k = big / (x1 - x0)
    im = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for c, x, y, w, h in RECTS:
        d.rectangle([(x - x0) * k, (y - y0) * k, (x + w - x0) * k - 1, (y + h - y0) * k - 1], fill=c)
    if round_:
        mask = Image.new('L', (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=big * 0.22, fill=255)
        im.putalpha(mask)
    return im.resize((size, size), Image.LANCZOS)

res = sys.argv[1]
for name, s in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    import os
    os.makedirs(f'{res}/mipmap-{name}', exist_ok=True)
    render(s).save(f'{res}/mipmap-{name}/ic_launcher.png')
render(512).save(sys.argv[2])
