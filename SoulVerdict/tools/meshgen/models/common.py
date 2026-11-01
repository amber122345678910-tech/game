"""Shared sculpting helpers: grooves, carved cracks, depth-based colouring, palettes."""
from __future__ import annotations

import math

import numpy as np

from sdf import clamp, hex_color, length, polyline_dist_2d, polyline_dist_3d, smax, smoothstep, surface_project, vec

# ---- palette (sRGB) ---------------------------------------------------------------------------
BONE = hex_color("#F2EEE4")
BONE_COOL = hex_color("#EEF1F4")
BONE_WARM = hex_color("#ECE4D3")
VOID = hex_color("#07070B")
SOCKET = hex_color("#0B0B12")
GROOVE = hex_color("#17161C")
GOLD = hex_color("#E9B437")
GOLD_HI = hex_color("#FFE08A")
FELL_RED = hex_color("#C21F2B")
FELL_DARK = hex_color("#2A0609")
ECL_VIOLET_DEEP = hex_color("#2B0C63")
ECL_VIOLET = hex_color("#8B3DFF")
ECL_CYAN = hex_color("#7DF9FF")
ECL_HALO = hex_color("#CDB9FF")
ECL_VOID = hex_color("#120822")


def lerp_rgb(a, b, t):
    t = np.asarray(t, dtype=np.float64)
    if t.ndim == 1:
        t = t[:, None]
    return a + (b - a) * t


def solid(n, rgb):
    return np.tile(vec(rgb), (n, 1))


# ---- surface parameterisations ------------------------------------------------------------------
def cyl_uv(p, axis_z: float, radius: float, y_offset: float = 0.0):
    """Cylindrical coordinates around a vertical axis through (0, *, axis_z). u = arc length on a
    cylinder of `radius` measured from the front (-Z), positive toward +X; v = y."""
    ang = np.arctan2(p[:, 0], -(p[:, 2] - axis_z))
    return ang * radius, p[:, 1] - y_offset


def sample_curve(fn_v, u0, u1, n=48):
    u = np.linspace(u0, u1, n)
    return np.stack([u, fn_v(u)], axis=1)


def lines_dist(u, v, polylines):
    d = None
    for pl in polylines:
        di = polyline_dist_2d(u, v, pl)
        d = di if d is None else np.minimum(d, di)
    return d


def carve(d, cutter_dist, half_width, depth, k=0.006, profile="u"):
    """Carve a groove of `half_width` along a centre-line distance field into surface d, at most
    `depth` deep. profile 'v' narrows with depth (V-groove), 'u' keeps the width."""
    below = clamp(-d / depth, 0.0, 1.0)  # 0 at the surface .. 1 at full depth
    if profile == "v":
        w = half_width * (1.0 - 0.85 * below)
    else:
        w = half_width * np.sqrt(np.maximum(1.0 - below**4, 0.0)) + 1e-4
    cut = np.maximum(cutter_dist - w, -(d + depth))
    return smax(d, -cut, k)


# ---- cracks --------------------------------------------------------------------------------------
def sph_dir(az, el):
    """Direction for azimuth az (0 = front/-Z, + toward +X) and elevation el (+ up)."""
    return np.array([math.sin(az) * math.cos(el), math.sin(el), -math.cos(az) * math.cos(el)])


def crack_paths(seed, start, heading, length_rad, steps, jitter, branches, branch_len=0.45):
    """Random-walk crack in (azimuth, elevation) space. Returns a list of (points, width_scale)."""
    rng = np.random.default_rng(seed)
    paths = []

    def walk(a, e, h, n, step, width, depth_level):
        pts = [(a, e)]
        for i in range(n):
            h += rng.normal(0.0, jitter)
            a += math.cos(h) * step
            e += math.sin(h) * step
            pts.append((a, e))
        paths.append((np.array(pts), width))
        return pts

    step = length_rad / steps
    main = walk(start[0], start[1], heading, steps, step, 1.0, 0)
    for b in range(branches):
        i = int(rng.integers(2, max(3, steps - 2)))
        a, e = main[i]
        side = 1 if b % 2 == 0 else -1
        h = heading + side * rng.uniform(0.55, 1.05)
        n = max(3, int(steps * branch_len * rng.uniform(0.7, 1.2)))
        sub = walk(a, e, h, n, step * 0.9, 0.62, 1)
        if rng.random() < 0.6:
            j = int(rng.integers(1, max(2, n - 1)))
            a2, e2 = sub[j]
            walk(a2, e2, h - side * rng.uniform(0.5, 0.9), max(2, n // 2), step * 0.8, 0.4, 2)
    return paths


def project_paths(surface_fn, center, paths, r_out=3.0):
    """Project (azimuth, elevation) polylines onto the surface along rays toward `center`."""
    out = []
    c = vec(center)
    for pts, w in paths:
        dirs = np.array([sph_dir(a, e) for a, e in pts])
        starts = c + dirs * r_out
        hits, ok = surface_project(surface_fn, starts, -dirs, r_out, steps=96)
        hits = hits[ok]
        if len(hits) >= 2:
            out.append((hits, w))
    return out


def crack_field(p, cracks, width, taper=0.75):
    """Distance to the nearest crack centre line minus its tapered half width (in studs).
    Returns (signed distance-to-crack-tube, normalised closeness 0..1)."""
    best = np.full(len(p), np.inf)
    for pts, wscale in cracks:
        d, s = polyline_dist_3d(p, pts)
        r = width * wscale * (1.0 - taper * s)  # thinner toward the tip
        best = np.minimum(best, d - r)
    return best


def crack_dist(p, cracks):
    best = np.full(len(p), np.inf)
    for pts, _ in cracks:
        d, _s = polyline_dist_3d(p, pts)
        best = np.minimum(best, d)
    return best


def carve_cracks(d, p, cracks, width, depth, k=0.004):
    """V-groove cracks (width = half width at the surface)."""
    below = clamp(-d / depth, 0.0, 1.0)
    best = np.full(len(p), np.inf)
    for pts, wscale in cracks:
        dist, s = polyline_dist_3d(p, pts)
        r = width * wscale * (1.0 - 0.7 * s) * (1.0 - 0.9 * below)
        best = np.minimum(best, dist - r)
    cut = np.maximum(best, -(d + depth))
    return smax(d, -cut, k)


def depth_tint(rgb, depth, color, d0, d1):
    """Blend toward `color` as the point gets deeper below the pre-carve surface."""
    t = smoothstep(d0, d1, depth)
    return lerp_rgb(rgb, color, t)
