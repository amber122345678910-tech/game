"""Small vectorised SDF modelling library (numpy).

Every primitive takes `p`, an (N, 3) float array of sample points, and returns an (N,) array of
signed distances (negative inside). Models are written as plain Python functions that combine
these arrays, which keeps intermediate fields (e.g. the "pre-carve" surface) available for
vertex colouring.

Conventions: studs, +Y up, the model faces -Z (Roblox LookVector), right = +X.
"""
from __future__ import annotations

import math

import numpy as np

EPS = 1e-9


def vec(a) -> np.ndarray:
    return np.asarray(a, dtype=np.float64)


def length(v: np.ndarray) -> np.ndarray:
    return np.sqrt(np.einsum("ij,ij->i", v, v))


def clamp(x, lo, hi):
    return np.minimum(np.maximum(x, lo), hi)


def smoothstep(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    return a + (b - a) * t


# --------------------------------------------------------------------------------------------
# Rotations (column-vector convention: world = R @ local). Matches Roblox CFrame.Angles order.
# --------------------------------------------------------------------------------------------
def rot_x(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float64)


def rot_y(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float64)


def euler(rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> np.ndarray:
    """Rx @ Ry @ Rz, like CFrame.Angles(rx, ry, rz)."""
    return rot_x(rx) @ rot_y(ry) @ rot_z(rz)


def to_local(p: np.ndarray, center=(0, 0, 0), R: np.ndarray | None = None) -> np.ndarray:
    """World points -> local frame of a shape placed at `center` with rotation `R`."""
    q = p - vec(center)
    if R is not None:
        q = q @ R  # == (R^T q^T)^T
    return q


def mirror_x(p: np.ndarray) -> np.ndarray:
    """Fold space so that modelling the +X half yields a symmetric shape."""
    q = p.copy()
    q[:, 0] = np.abs(q[:, 0])
    return q


# --------------------------------------------------------------------------------------------
# Boolean operators (iq's polynomial smooth min/max)
# --------------------------------------------------------------------------------------------
def smin(a, b, k: float = 0.0):
    if k <= 0.0:
        return np.minimum(a, b)
    h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return mix(b, a, h) - k * h * (1.0 - h)


def smax(a, b, k: float = 0.0):
    if k <= 0.0:
        return np.maximum(a, b)
    return -smin(-a, -b, k)


def union(*ds, k: float = 0.0):
    out = ds[0]
    for d in ds[1:]:
        out = smin(out, d, k)
    return out


def subtract(a, b, k: float = 0.0):
    """a minus b."""
    return smax(a, -b, k)


def intersect(a, b, k: float = 0.0):
    return smax(a, b, k)


# --------------------------------------------------------------------------------------------
# Primitives (all take world points; position/orientation via center/R)
# --------------------------------------------------------------------------------------------
def sphere(p, c, r):
    return length(p - vec(c)) - r


def ellipsoid(p, c, radii, R=None):
    """iq's improved ellipsoid approximation (good near the surface)."""
    q = to_local(p, c, R)
    r = vec(radii)
    k0 = length(q / r)
    k1 = length(q / (r * r))
    return k0 * (k0 - 1.0) / np.maximum(k1, EPS)


def ellipse_prism(p, c, radii2, z_front, z_floor, R=None, floor_round=0.08):
    """Elliptic hole profile extruded along local Z from z_front (open side, toward -Z) back to
    z_floor, with a rounded floor. radii2 = (rx, ry). Steep walls -> crisp sockets."""
    q = to_local(p, c, R)
    rx, ry = radii2
    k0 = np.sqrt((q[:, 0] / rx) ** 2 + (q[:, 1] / ry) ** 2)
    k1 = np.sqrt((q[:, 0] / (rx * rx)) ** 2 + (q[:, 1] / (ry * ry)) ** 2)
    d2 = k0 * (k0 - 1.0) / np.maximum(k1, EPS)
    dz_back = q[:, 2] - z_floor  # > 0 behind the floor
    dz_front = z_front - q[:, 2]  # > 0 in front of the opening
    d = smax(d2, dz_back, floor_round)
    return np.maximum(d, dz_front)


def round_box(p, c, half, r, R=None):
    """Box with half extents `half` (rounding included) and corner radius r."""
    q = np.abs(to_local(p, c, R)) - (vec(half) - r)
    outside = length(np.maximum(q, 0.0))
    inside = np.minimum(np.max(q, axis=1), 0.0)
    return outside + inside - r


def capsule(p, a, b, r):
    a, b = vec(a), vec(b)
    pa = p - a
    ba = b - a
    h = clamp((pa @ ba) / max(float(ba @ ba), EPS), 0.0, 1.0)
    return length(pa - np.outer(h, ba)) - r


def round_cone(p, a, b, r1, r2):
    """Exact SDF of the convex hull of sphere(a, r1) and sphere(b, r2) (iq)."""
    a, b = vec(a), vec(b)
    ba = b - a
    l2 = float(ba @ ba)
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / max(l2, EPS)
    pa = p - a
    y = pa @ ba
    z = y - l2
    w = pa * l2 - np.outer(y, ba)
    x2 = np.einsum("ij,ij->i", w, w)
    y2 = y * y * l2
    z2 = z * z * l2
    k = math.copysign(1.0, rr) * rr * rr * x2
    d_far = np.sqrt(x2 + z2) * il2 - r2
    d_near = np.sqrt(x2 + y2) * il2 - r1
    d_mid = (np.sqrt(np.maximum(x2 * a2 * il2, 0.0)) + y * rr) * il2 - r1
    return np.where(np.sign(z) * a2 * z2 > k, d_far, np.where(np.sign(y) * a2 * y2 < k, d_near, d_mid))


def tube(p, points, radii):
    """Tapered tube through `points` (M,3) with per-point radii (M,): union of round cones."""
    pts = vec(points)
    rad = vec(radii)
    d = None
    for i in range(len(pts) - 1):
        di = round_cone(p, pts[i], pts[i + 1], float(rad[i]), float(rad[i + 1]))
        d = di if d is None else np.minimum(d, di)
    return d


def cylinder(p, c, r, h, R=None):
    """Capped cylinder along local Y, radius r, half height h."""
    q = to_local(p, c, R)
    dx = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - r
    dy = np.abs(q[:, 1]) - h
    outside = np.sqrt(np.maximum(dx, 0) ** 2 + np.maximum(dy, 0) ** 2)
    return np.minimum(np.maximum(dx, dy), 0.0) + outside


def capped_cone(p, a, b, ra, rb):
    """Exact capped cone between points a (radius ra) and b (radius rb) (iq)."""
    a, b = vec(a), vec(b)
    ba = b - a
    rba = rb - ra
    baba = float(ba @ ba)
    pa = p - a
    papa = np.einsum("ij,ij->i", pa, pa)
    paba = (pa @ ba) / baba
    x = np.sqrt(np.maximum(papa - paba * paba * baba, 0.0))
    cax = np.maximum(0.0, x - np.where(paba < 0.5, ra, rb))
    cay = np.abs(paba - 0.5) - 0.5
    k = rba * rba + baba
    f = clamp((rba * (x - ra) + paba * baba) / k, 0.0, 1.0)
    cbx = x - ra - f * rba
    cby = paba - f
    s = np.where((cbx < 0.0) & (cay < 0.0), -1.0, 1.0)
    return s * np.sqrt(np.minimum(cax * cax + cay * cay * baba, cbx * cbx + cby * cby * baba))


def torus(p, c, R_major, r_minor, R=None):
    """Torus in the local XZ plane."""
    q = to_local(p, c, R)
    qx = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - R_major
    return np.sqrt(qx * qx + q[:, 1] ** 2) - r_minor


def plane(p, normal, offset):
    """Half-space n.p <= offset is inside."""
    n = vec(normal)
    n = n / np.linalg.norm(n)
    return p @ n - offset


def tri_prism(p, c, half_w, half_h, depth, R=None, apex_up=True, round_r=0.0):
    """Isosceles triangular prism along local Z (2D triangle extruded), optional rounding.
    Triangle spans x in [-half_w, half_w], y in [-half_h, half_h]; apex at +y if apex_up."""
    q = to_local(p, c, R)
    x = np.abs(q[:, 0])
    y = q[:, 1] if apex_up else -q[:, 1]
    hw = half_w - round_r
    hh = half_h - round_r
    # 2D distance to triangle with vertices (-hw,-hh), (hw,-hh), (0,hh) using edge planes (approx)
    e_len = math.hypot(hw, 2 * hh)
    nx, ny = (2 * hh) / e_len, hw / e_len  # outward normal of the slanted edge
    d_slant = (x - 0.0) * nx + (y - hh) * ny
    d_base = -y - hh
    d2 = np.maximum(d_slant, d_base) - round_r
    dz = np.abs(q[:, 2]) - depth
    outside = np.sqrt(np.maximum(d2, 0) ** 2 + np.maximum(dz, 0) ** 2)
    return np.minimum(np.maximum(d2, dz), 0.0) + outside


# --------------------------------------------------------------------------------------------
# Curves
# --------------------------------------------------------------------------------------------
def bezier(points, n: int = 16) -> np.ndarray:
    """Sample a cubic (or any-degree) Bezier curve given control points -> (n,3)."""
    P = vec(points)
    t = np.linspace(0.0, 1.0, n)
    m = len(P) - 1
    out = np.zeros((n, P.shape[1]))
    for i in range(m + 1):
        coef = math.comb(m, i) * (t**i) * ((1 - t) ** (m - i))
        out += np.outer(coef, P[i])
    return out


def seg_dist_2d(px, py, ax, ay, bx, by):
    """Distance from points (px,py) to segment a-b in 2D, plus the segment parameter."""
    abx, aby = bx - ax, by - ay
    l2 = abx * abx + aby * aby
    t = clamp(((px - ax) * abx + (py - ay) * aby) / max(l2, EPS), 0.0, 1.0)
    dx = px - (ax + t * abx)
    dy = py - (ay + t * aby)
    return np.sqrt(dx * dx + dy * dy), t


def polyline_dist_2d(px, py, pts):
    """Distance from 2D points to a polyline (M,2)."""
    d = None
    for i in range(len(pts) - 1):
        di, _ = seg_dist_2d(px, py, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1])
        d = di if d is None else np.minimum(d, di)
    return d


def polyline_dist_3d(p, pts):
    """Distance from points to a 3D polyline and the arc-length fraction of the closest point."""
    pts = vec(pts)
    seglen = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    total = max(float(seglen.sum()), EPS)
    cum = np.concatenate([[0.0], np.cumsum(seglen)])
    best = np.full(len(p), np.inf)
    best_s = np.zeros(len(p))
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        ba = b - a
        l2 = max(float(ba @ ba), EPS)
        t = clamp(((p - a) @ ba) / l2, 0.0, 1.0)
        d = length(p - a - np.outer(t, ba))
        better = d < best
        best = np.where(better, d, best)
        best_s = np.where(better, (cum[i] + t * seglen[i]) / total, best_s)
    return best, best_s


# --------------------------------------------------------------------------------------------
# Noise (value noise + fBm), deterministic
# --------------------------------------------------------------------------------------------
def _hash(ix, iy, iz, seed):
    h = (ix.astype(np.uint32) * np.uint32(73856093)) ^ (iy.astype(np.uint32) * np.uint32(19349663))
    h = h ^ (iz.astype(np.uint32) * np.uint32(83492791)) ^ np.uint32(seed * 2654435761 % 4294967296)
    h = (h ^ (h >> np.uint32(13))) * np.uint32(1274126177)
    h = h ^ (h >> np.uint32(16))
    return (h & np.uint32(0xFFFFFF)).astype(np.float64) / float(0xFFFFFF)


def value_noise(p, freq: float = 1.0, seed: int = 1):
    """Smooth 3D value noise in [-1, 1]."""
    q = p * freq
    i = np.floor(q)
    f = q - i
    u = f * f * (3.0 - 2.0 * f)
    ii = i.astype(np.int64)
    out = 0.0
    for dx in (0, 1):
        wx = u[:, 0] if dx else 1.0 - u[:, 0]
        for dy in (0, 1):
            wy = u[:, 1] if dy else 1.0 - u[:, 1]
            for dz in (0, 1):
                wz = u[:, 2] if dz else 1.0 - u[:, 2]
                h = _hash(ii[:, 0] + dx, ii[:, 1] + dy, ii[:, 2] + dz, seed)
                out = out + wx * wy * wz * h
    return out * 2.0 - 1.0


def fbm(p, freq=1.0, octaves=3, seed=1, gain=0.5, lacunarity=2.03):
    total = 0.0
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        total = total + amp * value_noise(p, freq * (lacunarity**o), seed + o * 101)
        norm += amp
        amp *= gain
    return total / norm


# --------------------------------------------------------------------------------------------
# Evaluation helpers
# --------------------------------------------------------------------------------------------
def aabb_dist(p, lo, hi):
    """Distance to an axis-aligned box (0 inside) - a lower bound for anything inside it."""
    lo, hi = vec(lo), vec(hi)
    q = np.maximum(np.maximum(lo - p, p - hi), 0.0)
    return length(q)


def bounded(p, lo, hi, fn, margin: float = 0.1):
    """Evaluate fn only for points inside the AABB [lo, hi] grown by margin; elsewhere return
    the distance to the grown box plus margin (a safe lower bound, positive outside)."""
    lo = vec(lo) - margin
    hi = vec(hi) + margin
    inside = np.all((p >= lo) & (p <= hi), axis=1)
    out = aabb_dist(p, lo, hi) + margin
    if inside.any():
        out[inside] = fn(p[inside])
    return out


def gradient(fn, p, h: float = 1e-3):
    """Central-difference gradient of a scalar field fn at points p."""
    g = np.zeros_like(p)
    for axis in range(3):
        o = np.zeros(3)
        o[axis] = h
        g[:, axis] = (fn(p + o) - fn(p - o)) / (2 * h)
    return g


def surface_project(fn, start, direction, t_max: float, steps: int = 48):
    """For each ray start + t*dir (t in [0, t_max]) find the first sign change of fn by sampling
    and bisection. Returns hit points (rays that miss keep the start point) and a hit mask."""
    start = vec(start).reshape(-1, 3)
    direction = vec(direction).reshape(-1, 3)
    direction = direction / np.linalg.norm(direction, axis=1, keepdims=True)
    ts = np.linspace(0.0, t_max, steps)
    prev_t = np.zeros(len(start))
    prev_d = fn(start)
    hit_lo = np.full(len(start), np.nan)
    hit_hi = np.full(len(start), np.nan)
    for t in ts[1:]:
        d = fn(start + direction * t)
        cross = (prev_d > 0) & (d <= 0) & np.isnan(hit_lo)
        hit_lo[cross] = prev_t[cross]
        hit_hi[cross] = t
        prev_t = np.full(len(start), t)
        prev_d = d
    hit = ~np.isnan(hit_lo)
    lo = np.where(hit, hit_lo, 0.0)
    hi = np.where(hit, hit_hi, 0.0)
    for _ in range(30):
        mid = 0.5 * (lo + hi)
        d = fn(start + direction * mid[:, None])
        outside = d > 0
        lo = np.where(outside, mid, lo)
        hi = np.where(outside, hi, mid)
    t = 0.5 * (lo + hi)
    return start + direction * t[:, None], hit


def hex_color(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float64)
