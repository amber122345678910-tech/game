#!/usr/bin/env python3
"""Превиз-рендер сцены вне Roblox (грубая трассировка лучей на numpy).

Не претендует на картинку Roblox: нужен, чтобы проверить пропорции моделей, позы и
кадрирование камеры без Studio. Вход — JSON от tools/previz_dump.luau:
{
  "frames": [ {
     "name": "...", "camera": {"pos": [x,y,z], "rot": [9 чисел, строки матрицы], "fov": 70},
     "fog": {"density": 0.0..1, "color": [r,g,b]}, "sky": [[r,g,b] низ, [r,g,b] верх],
     "sun": [x,y,z], "ambient": [r,g,b],
     "parts": [ {"shape": "Block|Ball|Cylinder|Wedge|Ellipsoid", "pos": [...], "rot": [...], "size": [...],
                 "color": [...], "transparency": 0, "neon": false, "group": 0} ],
     "beams": [ {"pts": [[x,y,z]...], "w": [..], "color": [[r,g,b]...], "transparency": 0, "z": 0} ],
     "lights": [ {"pos": [...], "color": [...], "brightness": 1, "range": 10} ],
     "outlines": {"<group>": alpha}
  } ]
}
Запуск: python3 tools/previz_render.py in.json out_dir [--w 640 --h 360]
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

EPS = 1e-6


def rot_matrix(r):
    # Roblox GetComponents: R00 R01 R02 / R10 R11 R12 / R20 R21 R22 (строки), столбцы = оси X, Y, Z
    return np.array(r, dtype=np.float64).reshape(3, 3)


class Camera:
    def __init__(self, cam, w, h):
        self.pos = np.array(cam["pos"], dtype=np.float64)
        self.R = rot_matrix(cam["rot"])
        self.fov = math.radians(cam.get("fov", 70))
        self.w, self.h = w, h
        self.tan = math.tan(self.fov / 2)
        self.aspect = w / h

    def rays(self):
        ys, xs = np.mgrid[0:self.h, 0:self.w]
        nx = ((xs + 0.5) / self.w * 2 - 1) * self.tan * self.aspect
        ny = (1 - (ys + 0.5) / self.h * 2) * self.tan
        d = np.stack([nx, ny, -np.ones_like(nx)], axis=-1)
        d /= np.linalg.norm(d, axis=-1, keepdims=True)
        dw = d @ self.R.T  # в мир
        return dw

    def project(self, pts):
        """мировые точки (N,3) -> экранные x,y (N,) и глубина вдоль -Z камеры"""
        local = (pts - self.pos) @ self.R  # R^T (p - c)
        z = -local[:, 2]
        with np.errstate(divide="ignore", invalid="ignore"):
            sx = (local[:, 0] / (z * self.tan * self.aspect) + 1) / 2 * self.w
            sy = (1 - local[:, 1] / (z * self.tan)) / 2 * self.h
        return sx, sy, z


def box_corners(pos, R, half):
    signs = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], dtype=np.float64)
    return pos + (signs * half) @ R.T


def intersect(shape, o, d, half):
    """o, d — (N,3) в локальных осях детали. Возвращает t (N,), нормаль (N,3) в локальных осях; t=inf если мимо."""
    n = o.shape[0]
    t_out = np.full(n, np.inf)
    nrm = np.zeros((n, 3))
    if shape in ("Ellipsoid", "Ball"):
        if shape == "Ball":
            r = float(np.min(half))
            half = np.array([r, r, r])
        oo = o / half
        dd = d / half
        a = np.sum(dd * dd, axis=1)
        b = 2 * np.sum(oo * dd, axis=1)
        c = np.sum(oo * oo, axis=1) - 1
        disc = b * b - 4 * a * c
        ok = disc >= 0
        sq = np.sqrt(np.where(ok, disc, 0))
        t0 = (-b - sq) / (2 * a)
        t1 = (-b + sq) / (2 * a)
        t = np.where(t0 > EPS, t0, t1)
        ok &= t > EPS
        t_out = np.where(ok, t, np.inf)
        p = o + d * t[:, None]
        nn = p / (half * half)
        nrm = nn / (np.linalg.norm(nn, axis=1, keepdims=True) + EPS)
        return t_out, nrm
    if shape == "Cylinder":
        r = float(min(half[1], half[2]))
        hl = float(half[0])
        # боковая поверхность y^2+z^2=r^2
        a = d[:, 1] ** 2 + d[:, 2] ** 2
        b = 2 * (o[:, 1] * d[:, 1] + o[:, 2] * d[:, 2])
        c = o[:, 1] ** 2 + o[:, 2] ** 2 - r * r
        disc = b * b - 4 * a * c
        ok = (disc >= 0) & (a > EPS)
        sq = np.sqrt(np.where(ok, disc, 0))
        aa = np.where(a > EPS, a, 1)
        t0 = (-b - sq) / (2 * aa)
        x0 = o[:, 0] + d[:, 0] * t0
        side_ok = ok & (t0 > EPS) & (np.abs(x0) <= hl)
        t_side = np.where(side_ok, t0, np.inf)
        # торцы x = +-hl
        t_cap = np.full(n, np.inf)
        cap_n = np.zeros(n)
        for s in (-1, 1):
            with np.errstate(divide="ignore", invalid="ignore"):
                tc = (s * hl - o[:, 0]) / d[:, 0]
            pc = o + d * tc[:, None]
            okc = (tc > EPS) & (pc[:, 1] ** 2 + pc[:, 2] ** 2 <= r * r) & np.isfinite(tc)
            better = okc & (tc < t_cap)
            t_cap = np.where(better, tc, t_cap)
            cap_n = np.where(better, s, cap_n)
        use_cap = t_cap < t_side
        t_out = np.minimum(t_side, t_cap)
        p = o + d * t_out[:, None]
        side_nrm = np.stack([np.zeros(n), p[:, 1], p[:, 2]], axis=1)
        side_nrm /= np.linalg.norm(side_nrm, axis=1, keepdims=True) + EPS
        cap_nrm = np.stack([cap_n, np.zeros(n), np.zeros(n)], axis=1)
        nrm = np.where(use_cap[:, None], cap_nrm, side_nrm)
        return t_out, nrm
    # Выпуклые многогранники: Block, Wedge — пересечение полупространств (n·x <= k)
    planes = [
        (np.array([1.0, 0, 0]), half[0]), (np.array([-1.0, 0, 0]), half[0]),
        (np.array([0, 1.0, 0]), half[1]), (np.array([0, -1.0, 0]), half[1]),
        (np.array([0, 0, 1.0]), half[2]), (np.array([0, 0, -1.0]), half[2]),
    ]
    if shape == "Wedge":
        # скат: y/hy <= z/hz  ->  y*hz - z*hy <= 0
        pn = np.array([0.0, half[2], -half[1]])
        ln = np.linalg.norm(pn)
        planes.append((pn / ln, 0.0))
    t_enter = np.full(n, -np.inf)
    t_exit = np.full(n, np.inf)
    enter_n = np.zeros((n, 3))
    for pn, k in planes:
        denom = d @ pn
        num = k - o @ pn
        with np.errstate(divide="ignore", invalid="ignore"):
            tt = num / denom
        parallel = np.abs(denom) < EPS
        outside_parallel = parallel & (num < 0)
        entering = (~parallel) & (denom < 0)
        exiting = (~parallel) & (denom > 0)
        upd = entering & (tt > t_enter)
        t_enter = np.where(upd, tt, t_enter)
        enter_n = np.where(upd[:, None], pn[None, :], enter_n)
        t_exit = np.where(exiting & (tt < t_exit), tt, t_exit)
        t_exit = np.where(outside_parallel, -np.inf, t_exit)
    hit = (t_enter <= t_exit) & (t_enter > EPS)
    t_out = np.where(hit, t_enter, np.inf)
    return t_out, enter_n


def sky_color(dw, sky):
    lo = np.array(sky[0]); hi = np.array(sky[1])
    k = np.clip(dw[..., 1] * 1.5 + 0.2, 0, 1)[..., None]
    return lo * (1 - k) + hi * k


def render_frame(fr, w, h):
    cam = Camera(fr["camera"], w, h)
    dw = cam.rays()
    flat_d = dw.reshape(-1, 3)
    npx = w * h
    color = sky_color(dw, fr.get("sky", [[0.82, 0.85, 0.93], [0.45, 0.58, 0.82]])).reshape(-1, 3)
    depth = np.full(npx, np.inf)
    group = np.full(npx, -1, dtype=np.int32)
    sun = np.array(fr.get("sun", [0.3, 0.8, 0.5]), dtype=np.float64)
    sun /= np.linalg.norm(sun)
    amb = np.array(fr.get("ambient", [0.45, 0.47, 0.55]))
    lights = fr.get("lights", [])
    parts = fr.get("parts", [])
    opaque = [p for p in parts if p.get("transparency", 0) < 0.02]
    trans = [p for p in parts if 0.02 <= p.get("transparency", 0) < 0.98]
    surf_color = np.zeros((npx, 3))
    surf_alpha_layers = []

    def shade(p, pts_world, nrm_world):
        base = np.array(p["color"], dtype=np.float64)
        if p.get("neon"):
            return np.tile(np.minimum(base * 1.6, 1.0), (pts_world.shape[0], 1))
        ndl = np.clip(nrm_world @ sun, 0, 1)
        # мягкая "аниме" ступенька света
        cel = 0.35 + 0.65 * np.clip((ndl - 0.15) * 3, 0, 1)
        lit = base * (amb[None, :] + (1 - amb[None, :]) * cel[:, None] * 0.9)
        for L in lights:
            lp = np.array(L["pos"]); lc = np.array(L["color"]) * L.get("brightness", 1)
            v = lp - pts_world
            dist = np.linalg.norm(v, axis=1)
            att = np.clip(1 - dist / L.get("range", 10), 0, 1) ** 2
            nl = np.clip(np.sum(nrm_world * v / (dist[:, None] + EPS), axis=1), 0, 1)
            lit = lit + base * lc[None, :] * (att * nl)[:, None] * 0.8
        return np.clip(lit, 0, 1)

    def trace_part(p, mask_idx):
        R = rot_matrix(p["rot"])
        pos = np.array(p["pos"], dtype=np.float64)
        half = np.array(p["size"], dtype=np.float64) / 2
        o_loc = np.tile((cam.pos - pos) @ R, (mask_idx.size, 1))
        d_loc = flat_d[mask_idx] @ R
        t, nloc = intersect(p["shape"], o_loc, d_loc, half)
        return t, nloc @ R.T, R

    def screen_bbox(p):
        R = rot_matrix(p["rot"])
        pos = np.array(p["pos"], dtype=np.float64)
        half = np.array(p["size"], dtype=np.float64) / 2
        corners = box_corners(pos, R, half)
        sx, sy, z = cam.project(corners)
        if np.any(z <= 0.05):
            if np.all(z <= 0.05):
                return None
            return 0, w - 1, 0, h - 1
        x0 = int(max(0, math.floor(np.min(sx)))); x1 = int(min(w - 1, math.ceil(np.max(sx))))
        y0 = int(max(0, math.floor(np.min(sy)))); y1 = int(min(h - 1, math.ceil(np.max(sy))))
        if x0 > x1 or y0 > y1:
            return None
        return x0, x1, y0, y1

    def idx_of(bb):
        x0, x1, y0, y1 = bb
        ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
        return (ys * w + xs).ravel()

    for p in opaque:
        bb = screen_bbox(p)
        if bb is None:
            continue
        idx = idx_of(bb)
        t, nw, _ = trace_part(p, idx)
        closer = t < depth[idx]
        if not np.any(closer):
            continue
        ii = idx[closer]
        tt = t[closer]
        pts = cam.pos + flat_d[ii] * tt[:, None]
        depth[ii] = tt
        surf_color[ii] = shade(p, pts, nw[closer])
        group[ii] = p.get("group", 0)

    hitmask = np.isfinite(depth)
    color[hitmask] = surf_color[hitmask]

    # прозрачные детали — от дальних к ближним
    def dist_of(p):
        return np.linalg.norm(np.array(p["pos"]) - cam.pos)
    for p in sorted(trans, key=dist_of, reverse=True):
        bb = screen_bbox(p)
        if bb is None:
            continue
        idx = idx_of(bb)
        t, nw, _ = trace_part(p, idx)
        vis = t < depth[idx]
        if not np.any(vis):
            continue
        ii = idx[vis]
        pts = cam.pos + flat_d[ii] * t[vis][:, None]
        c = shade(p, pts, nw[vis])
        a = 1 - p.get("transparency", 0)
        color[ii] = color[ii] * (1 - a) + c * a

    # лучи (Beam): полоса вдоль кривой, ширина в мировых единицах -> экранные
    beams = sorted(fr.get("beams", []), key=lambda b: -np.linalg.norm(np.mean(np.array(b["pts"]), axis=0) - cam.pos))
    for b in beams:
        pts = np.array(b["pts"], dtype=np.float64)
        if len(pts) < 2:
            continue
        sx, sy, z = cam.project(pts)
        if np.any(z <= 0.05):
            continue
        widths = np.array(b["w"], dtype=np.float64)
        cols = np.array(b["color"], dtype=np.float64)
        alpha = 1 - b.get("transparency", 0)
        pxw = widths / (z * cam.tan * 2) * h  # ширина в пикселях
        for i in range(len(pts) - 1):
            ax, ay, bx, by = sx[i], sy[i], sx[i + 1], sy[i + 1]
            ra, rb = max(pxw[i] / 2, 0.35), max(pxw[i + 1] / 2, 0.35)
            x0 = int(max(0, math.floor(min(ax, bx) - max(ra, rb)))); x1 = int(min(w - 1, math.ceil(max(ax, bx) + max(ra, rb))))
            y0 = int(max(0, math.floor(min(ay, by) - max(ra, rb)))); y1 = int(min(h - 1, math.ceil(max(ay, by) + max(ra, rb))))
            if x0 > x1 or y0 > y1:
                continue
            ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
            px = xs + 0.5; py = ys + 0.5
            vx, vy = bx - ax, by - ay
            l2 = vx * vx + vy * vy + EPS
            s = np.clip(((px - ax) * vx + (py - ay) * vy) / l2, 0, 1)
            dx = px - (ax + vx * s); dy = py - (ay + vy * s)
            dist = np.sqrt(dx * dx + dy * dy)
            rad = ra + (rb - ra) * s
            zz = z[i] + (z[i + 1] - z[i]) * s
            inside = dist <= rad
            idx = (ys * w + xs)[inside]
            # глубина вдоль луча ~ zz / cos — достаточно для сравнения
            zt = zz[inside]
            vis = zt < depth[idx] + 0.02 + b.get("z", 0)
            idx = idx[vis]
            if idx.size == 0:
                continue
            cc = cols[i] + (cols[min(i + 1, len(cols) - 1)] - cols[i]) * s[inside][vis][:, None]
            color[idx] = color[idx] * (1 - alpha) + cc * alpha
            if b.get("group") is not None:
                group[idx] = b["group"]

    # мягкие спрайты (карточки тумана): эллипс с плавным краем, проверка глубины по центру
    sprites = sorted(fr.get("sprites", []), key=lambda sp: -np.linalg.norm(np.array(sp["center"]) - cam.pos))
    for sp in sprites:
        c = np.array(sp["center"], dtype=np.float64)
        sx, sy, z = cam.project(c[None, :])
        if z[0] <= 0.3:
            continue
        rx = sp["w"] / 2 / (z[0] * cam.tan * 2) * h
        ry = sp["h"] / 2 / (z[0] * cam.tan * 2) * h
        r = math.radians(sp.get("roll", 0))
        R = max(rx, ry)
        x0 = int(max(0, math.floor(sx[0] - R))); x1 = int(min(w - 1, math.ceil(sx[0] + R)))
        y0 = int(max(0, math.floor(sy[0] - R))); y1 = int(min(h - 1, math.ceil(sy[0] + R)))
        if x0 > x1 or y0 > y1:
            continue
        ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
        dx = xs + 0.5 - sx[0]; dy = ys + 0.5 - sy[0]
        u = (dx * math.cos(r) - dy * math.sin(r)) / max(rx, 1e-3)
        v = (dx * math.sin(r) + dy * math.cos(r)) / max(ry, 1e-3)
        d2 = u * u + v * v
        a = sp["alpha"] * np.clip(1 - d2, 0, 1) ** 1.6
        idx = (ys * w + xs).ravel()
        a = a.ravel()
        vis = (z[0] < depth[idx]) & (a > 0.003)
        idx = idx[vis]; a = a[vis]
        col = np.array(sp["color"])
        color[idx] = color[idx] * (1 - a[:, None]) + col[None, :] * a[:, None]

    # туман (как Atmosphere: экспонента по расстоянию)
    fog = fr.get("fog")
    if fog and fog.get("density", 0) > 0:
        dens = fog["density"]
        fc = np.array(fog["color"])
        dd = np.where(np.isfinite(depth), depth, 1e9)
        k = 1 - np.exp(-dd * dens * 0.02)
        k = np.where(np.isfinite(depth), k, fog.get("skyMix", 0.85))
        color = color * (1 - k[:, None]) + fc[None, :] * k[:, None]

    # заливка Highlight (силуэт цвета тумана)
    fills = fr.get("fills", {})
    for gid_s, f in fills.items():
        m = (group == int(gid_s))
        a = f["alpha"]
        color[m] = color[m] * (1 - a) + np.array(f["color"])[None, :] * a

    # контур (Highlight): граница группы с другим содержимым
    outl = fr.get("outlines", {})
    if outl:
        g = group.reshape(h, w)
        img = color.reshape(h, w, 3)
        for gid_s, a in outl.items():
            gid = int(gid_s)
            if a <= 0:
                continue
            m = g == gid
            edge = np.zeros_like(m)
            for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                sh = np.roll(np.roll(m, dy, axis=0), dx, axis=1)
                edge |= m & ~sh
            img[edge] = img[edge] * (1 - a) + np.array([0.06, 0.05, 0.08]) * a
        color = img.reshape(-1, 3)

    img = (np.clip(color.reshape(h, w, 3), 0, 1) * 255).astype(np.uint8)
    return Image.fromarray(img)


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    src, out_dir = args[0], args[1]
    w, h = 640, 360
    if "--w" in args:
        w = int(args[args.index("--w") + 1])
    if "--h" in args:
        h = int(args[args.index("--h") + 1])
    os.makedirs(out_dir, exist_ok=True)
    data = json.load(open(src))
    names = []
    for i, fr in enumerate(data["frames"]):
        img = render_frame(fr, w, h)
        name = fr.get("name", "frame_%03d" % i).replace("/", "_")
        path = os.path.join(out_dir, name + ".png")
        img.save(path)
        names.append(path)
        print(path)
    if "--sheet" in args:
        cols = int(args[args.index("--sheet") + 1])
        ims = [Image.open(p) for p in names]
        rows = (len(ims) + cols - 1) // cols
        sheet = Image.new("RGB", (w * cols, h * rows))
        for i, im in enumerate(ims):
            sheet.paste(im, ((i % cols) * w, (i // cols) * h))
        sp = os.path.join(out_dir, "_sheet.png")
        sheet.save(sp)
        print(sp)


if __name__ == "__main__":
    main()
