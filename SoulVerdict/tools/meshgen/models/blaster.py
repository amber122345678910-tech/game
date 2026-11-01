"""Gaster Blaster skulls + hinged jaws (Classic / Fell / Eclipse).

Design space: the muzzle points to -Z, +Y up, +X = the skull's right. The skull and the jaw are
modelled in the same space; the jaw rotates about the X axis through HINGE (opening = negative
X rotation, i.e. CFrame.Angles(-angle, 0, 0) about the hinge).
"""
from __future__ import annotations

import math

import numpy as np

from mesher import ModelSpec
from models import common as C
from sdf import (bezier, bounded, clamp, ellipse_prism, ellipsoid, euler, fbm, hex_color, mirror_x, mix,
                 round_box, round_cone, rot_y, smax, smin, smoothstep, tube, vec)

HINGE = (0.0, -0.36, 0.40)


# ---------------------------------------------------------------------------------------------
# Style parameters
# ---------------------------------------------------------------------------------------------
STYLES = {
    "Classic": dict(
        snout_len=1.62, snout_w=(0.84, 0.42), snout_h=(0.56, 0.33), snout_top_drop=0.28, stop=0.0,
        eye_c=(0.52, 0.30, -0.32), eye_r=(0.335, 0.275), eye_yaw=0.34, eye_slant=0.0,
        horn=dict(root=(0.42, 0.60, 0.18), c1=(0.62, 1.10, 0.55), c2=(0.86, 1.10, 1.15), tip=(0.98, 0.78, 1.72),
                  r0=0.22, r1=0.03),
        cheek_spikes=[((0.90, -0.04, 0.32), (1.36, -0.20, 1.10), 0.13), ((0.80, -0.26, 0.24), (1.16, -0.56, 0.92), 0.10)],
        brow_spikes=[], teeth_n=6, tooth_len=0.20, canine=2, canine_len=0.30, tooth_jag=0.0,
        bone="#EEF1F5", socket="#07080D", inner="#14121A", crack=None, seed=1,
    ),
    "Fell": dict(
        snout_len=1.66, snout_w=(0.86, 0.40), snout_h=(0.56, 0.32), snout_top_drop=0.30, stop=0.0,
        eye_c=(0.52, 0.29, -0.32), eye_r=(0.34, 0.27), eye_yaw=0.34, eye_slant=0.40,
        horn=dict(root=(0.42, 0.60, 0.18), c1=(0.66, 1.18, 0.50), c2=(0.95, 1.22, 1.10), tip=(1.12, 0.92, 1.78),
                  r0=0.23, r1=0.025, prong=True),
        cheek_spikes=[((0.90, -0.04, 0.32), (1.42, -0.18, 1.12), 0.13), ((0.80, -0.26, 0.24), (1.22, -0.62, 0.92), 0.10),
                      ((0.86, 0.12, 0.18), (1.30, 0.30, 0.78), 0.085)],
        brow_spikes=[((0.62, 0.62, -0.18), (0.82, 0.98, 0.10), 0.075), ((0.40, 0.66, -0.02), (0.52, 1.00, 0.30), 0.06)],
        teeth_n=8, tooth_len=0.22, canine=2, canine_len=0.34, tooth_jag=0.35,
        bone="#E9E2D6", socket="#16030A", inner="#1E0608", crack="fell", seed=7,
    ),
    "Eclipse": dict(
        snout_len=2.05, snout_w=(0.74, 0.27), snout_h=(0.52, 0.24), snout_top_drop=0.46, stop=0.12,
        eye_c=(0.50, 0.33, -0.30), eye_r=(0.31, 0.235), eye_yaw=0.30, eye_slant=0.24,
        horn=dict(root=(0.44, 0.58, 0.26), c1=(0.56, 1.02, 0.42), c2=(0.70, 1.22, 0.78), tip=(0.78, 1.20, 1.22),
                  r0=0.24, r1=0.02, blade=True),
        cheek_spikes=[((0.86, -0.04, 0.30), (1.30, -0.26, 1.02), 0.12), ((0.62, 0.70, 0.40), (0.86, 0.96, 1.14), 0.09),
                      ((0.20, 0.82, 0.42), (0.26, 1.02, 1.12), 0.075)],
        brow_spikes=[], teeth_n=7, tooth_len=0.17, canine=1, canine_len=0.48, tooth_jag=0.1,
        bone="#ECEBF4", socket="#0C0618", inner="#120A22", crack="eclipse", seed=3,
    ),
}


def snout_profile(st, z):
    """Lofted snout: returns (rx, ry, cy, top) at depth z (z from 0.15 at the back to -L at the tip)."""
    L = st["snout_len"]
    t = clamp((0.15 - z) / (L + 0.15), 0.0, 1.0)
    rx = mix(st["snout_w"][0], st["snout_w"][1], t**0.85)
    ry = mix(st["snout_h"][0], st["snout_h"][1], t)
    cy = mix(0.06, 0.06 - st["snout_top_drop"] * 0.55, t)
    return rx, ry, cy, t


def snout_sdf(p, st):
    L = st["snout_len"]
    rx, ry, cy, t = snout_profile(st, p[:, 2])
    x = p[:, 0]
    y = p[:, 1] - cy
    k0 = np.sqrt((x / rx) ** 2 + (y / ry) ** 2)
    k1 = np.sqrt((x / (rx * rx)) ** 2 + (y / (ry * ry)) ** 2)
    d2 = k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
    # flatten the palate a little (teeth hang from a flatter underside)
    d2 = smax(d2, -(p[:, 1] - (cy - ry * 0.80)), 0.10)
    dz = np.maximum(p[:, 2] - 0.45, -L - p[:, 2])
    return smax(d2, dz, 0.30)


def horn_points(h, side=1.0, n=14):
    pts = bezier([h["root"], h["c1"], h["c2"], h["tip"]], n)
    pts[:, 0] *= side
    return pts


def horn_sdf(q, h):
    pts = horn_points(h)
    t = np.linspace(0.0, 1.0, len(pts))
    radii = h["r0"] * (1 - t) ** 1.15 + h["r1"]
    lo = pts.min(axis=0) - h["r0"]
    hi = pts.max(axis=0) + h["r0"]
    d = bounded(q, lo, hi, lambda x: tube(x, pts, radii), 0.12)
    if h.get("blade"):
        # flattened "ear blade": a second tube offset downward/back, merged into a wide fin
        pts2 = pts + np.array([0.04, -0.16, 0.10]) * np.sin(np.pi * t)[:, None]
        d2 = bounded(q, pts2.min(axis=0) - 0.25, pts2.max(axis=0) + 0.25,
                     lambda x: tube(x, pts2, radii * 0.8), 0.12)
        d = smin(d, d2, 0.10)
    if h.get("prong"):
        mid = pts[5]
        tip = mid + np.array([0.18, 0.34, -0.04])
        dp = bounded(q, np.minimum(mid, tip) - 0.12, np.maximum(mid, tip) + 0.12,
                     lambda x: round_cone(x, mid, tip, 0.085, 0.015), 0.1)
        d = smin(d, dp, 0.05)
    return d


def tooth_line(st, n, y_off=0.0, inset=0.10, z_back=-0.05):
    """Points along the snout's lower outline (one side, +X), front to back."""
    L = st["snout_len"]
    zs = np.linspace(-L + 0.10, z_back, n)
    out = []
    for i, z in enumerate(zs):
        rx, ry, cy, t = snout_profile(st, np.array([z]))
        rx, ry, cy = float(rx[0]), float(ry[0]), float(cy[0])
        x = max(rx - inset, 0.05)
        # the front-most tooth sits nearer the centre line
        if i == 0:
            x = max(0.07, x * 0.55)
        y = cy - ry * 0.80 + y_off
        out.append((x, y, z))
    return np.array(out)


def teeth_specs(st, upper=True):
    """List of (base, tip, r_base, r_tip) for one side (+X)."""
    rng = np.random.default_rng(st["seed"] + (0 if upper else 50))
    n = st["teeth_n"]
    line = tooth_line(st, n, y_off=0.04 if upper else -0.0)
    specs = []
    for i, base in enumerate(line):
        if not upper:
            # lower teeth sit between the upper ones
            if i == len(line) - 1:
                continue
            base = (line[i] + line[i + 1]) * 0.5
        length = st["tooth_len"] * (0.75 + 0.25 * (1 - i / max(n - 1, 1)))
        r = 0.075 + 0.02 * (1 - i / max(n - 1, 1))
        if upper and i == st["canine"]:
            length = st["canine_len"]
            r *= 1.25
        if (not upper) and i == st["canine"] - 1:
            length = st["canine_len"] * (0.62 if st["canine_len"] > 0.45 else 0.85)
            r *= 1.15
        if st["tooth_jag"] > 0:
            length *= 1.0 + st["tooth_jag"] * rng.uniform(-0.6, 0.5)
        sign = -1.0 if upper else 1.0
        lean = np.array([rng.uniform(-0.03, 0.03) * st["tooth_jag"] * 3, 0.0, 0.05])
        tip = base + np.array([0.0, sign * length, 0.0]) + lean * length
        b = base - np.array([0.0, sign * 0.06, 0.0])
        specs.append((b, tip, r, 0.010 if st["tooth_jag"] == 0 else 0.006))
    return specs


def teeth_sdf(q, specs):
    d = None
    for b, tip, rb, rt in specs:
        lo = np.minimum(b, tip) - rb
        hi = np.maximum(b, tip) + rb
        di = bounded(q, lo, hi, lambda x, b=b, tip=tip, rb=rb, rt=rt: round_cone(x, b, tip, rb, rt), 0.08)
        d = di if d is None else np.minimum(d, di)
    return d


def spikes_sdf(q, spikes):
    d = None
    for a, b, r in spikes:
        a, b = vec(a), vec(b)
        di = bounded(q, np.minimum(a, b) - r, np.maximum(a, b) + r,
                     lambda x, a=a, b=b, r=r: round_cone(x, a, b, r, 0.012), 0.1)
        d = di if d is None else np.minimum(d, di)
    return d


# ---------------------------------------------------------------------------------------------
# Skull
# ---------------------------------------------------------------------------------------------
def skull_field(style, cracks=None):
    st = STYLES[style]

    def field(p):
        q = mirror_x(p)
        cran = ellipsoid(p, (0, 0.17, 0.42), (0.90, 0.70, 0.82))
        crb = round_box(p, (0, 0.12, 0.42), (0.86, 0.66, 0.80), 0.48)
        d = mix(cran, crb, 0.35)
        snout = snout_sdf(p, st)
        d = smin(d, snout, 0.34)
        if st["stop"] > 0:
            # lupine forehead step: raise the brow area above the eyes
            fh = ellipsoid(p, (0, 0.50, -0.05), (0.62, 0.30, 0.55))
            d = smin(d, fh, 0.20)
        # brow ridges arching over the sockets
        ex, ey, ez = st["eye_c"]
        brow = ellipsoid(q, (ex + 0.02, ey + 0.27, ez + 0.06), (0.42, 0.13, 0.30),
                         euler(0.0, -st["eye_yaw"], -0.18 - st["eye_slant"] * 0.6))
        d = smin(d, brow, 0.14)
        # zygomatic arches toward the hinge
        arch = round_cone(q, (0.70, -0.06, -0.40), (0.86, -0.16, 0.40), 0.13, 0.15)
        d = smin(d, arch, 0.16)
        # hinge bosses
        boss = ellipsoid(q, (0.78, HINGE[1] + 0.05, HINGE[2]), (0.16, 0.20, 0.20))
        d = smin(d, boss, 0.12)
        # horns & spikes
        d = smin(d, horn_sdf(q, st["horn"]), 0.10)
        d = smin(d, spikes_sdf(q, st["cheek_spikes"]), 0.08)
        if st["brow_spikes"]:
            d = smin(d, spikes_sdf(q, st["brow_spikes"]), 0.06)
        # occipital crest between the horns
        crest = round_cone(p, (0, 0.80, 0.10), (0, 0.55, 1.08), 0.07, 0.05)
        d = smin(d, crest, 0.16)
        head = d
        # ---- carving
        # eye sockets: steep elliptic tunnels angled outward
        R = euler(0.0, -st["eye_yaw"], 0.0)
        e = ellipse_prism(q, st["eye_c"], st["eye_r"], -0.8, 0.20, R, floor_round=0.10)
        if st["eye_slant"] > 0:
            ql = (q - vec(st["eye_c"])) @ R
            slant = (ql[:, 1] - st["eye_r"][1] * 0.55) * math.cos(st["eye_slant"]) - ql[:, 0] * math.sin(st["eye_slant"])
            e = smax(e, slant, 0.05)
        d = smax(d, -e, 0.03)
        # nasal cavity at the snout tip
        L = st["snout_len"]
        rx, ry, cy, _ = snout_profile(st, np.array([-L]))
        ntop = float(cy[0] + ry[0] * 0.15)
        nose = ellipsoid(q, (0.075, ntop, -L - 0.05), (0.085, 0.10, 0.30), euler(0.0, 0.0, -0.35))
        d = smax(d, -nose, 0.03)
        # mouth roof: shallow palate hollow inside the tooth line
        rxb, ryb, cyb, _ = snout_profile(st, np.array([-0.6]))
        palate = ellipsoid(p, (0, float(cyb[0] - ryb[0] * 0.80) - 0.06, -0.75), (float(rxb[0]) * 0.62, 0.12, L * 0.42))
        d = smax(d, -palate, 0.05)
        # dragon-skull openings: antorbital fossa on the snout side, temporal fossa behind the eye
        zA = -0.52 - 0.30 * (L / 1.62)
        rxa, rya, cya, _ = snout_profile(st, np.array([zA]))
        ant = ellipse_prism(q, (float(rxa[0]) * 0.92, float(cya[0]) - 0.02, zA), (0.24 * L / 1.62, 0.10), -0.5, 0.11,
                            euler(0.0, -1.30, -0.12), floor_round=0.06)
        temp = ellipse_prism(q, (0.80, 0.30, 0.22), (0.17, 0.12), -0.5, 0.12, euler(-0.35, -1.25, 0.25),
                             floor_round=0.06)
        fen = np.minimum(ant, temp)
        d = smax(d, -fen, 0.025)
        pre_groove = d
        # centre seam (the blaster's iconic centre line) from the crest down to the nose
        seam_pts = np.array([[0, ntop + 0.12, -L - 0.10], [0, ntop + 0.32, -L + 0.45], [0, 0.42, -0.70],
                             [0, 0.62, -0.20], [0, 0.82, 0.25]])
        from sdf import polyline_dist_3d

        ds, _ = polyline_dist_3d(p, seam_pts)
        d = C.carve(d, ds, 0.026, 0.055, k=0.006)
        # upper teeth (added after carving so the palate does not eat them)
        tsd = teeth_sdf(q, teeth_specs(st, upper=True))
        d = smin(d, tsd, 0.025)
        out = {"head": head, "eye": e, "nose": nose, "palate": palate, "seam": ds, "pre_groove": pre_groove,
               "teeth": tsd, "fen": fen}
        pre_cracks = d
        if cracks is not None:
            d = C.carve_cracks(d, p, cracks["paths"], cracks["width"], cracks["depth"])
        out["pre_cracks"] = pre_cracks
        out["d"] = d
        return out

    return field


def skull_colorize(style, cracks=None):
    st = STYLES[style]
    bone = hex_color(st["bone"])
    socket = hex_color(st["socket"])
    inner = hex_color(st["inner"])

    def colorize(P, N, f):
        n = len(P)
        rgb = C.solid(n, bone)
        rgb = rgb * (0.97 + 0.03 * np.clip(N[:, 1], -1, 1))[:, None]
        depth = np.maximum(-f["head"], 0.0)
        in_eye = f["eye"] < 0.03
        rgb = np.where(in_eye[:, None], C.depth_tint(rgb, depth, socket, 0.004, 0.07), rgb)
        in_nose = f["nose"] < 0.03
        rgb = np.where(in_nose[:, None], C.depth_tint(rgb, depth, socket, 0.004, 0.06), rgb)
        in_fen = f["fen"] < 0.025
        rgb = np.where(in_fen[:, None], C.depth_tint(rgb, depth, socket, 0.003, 0.05), rgb)
        in_pal = (f["palate"] < 0.03) & (f["teeth"] > 0.004)
        rgb = np.where(in_pal[:, None], C.depth_tint(rgb, depth, inner, 0.004, 0.05), rgb)
        gdepth = np.maximum(-f["pre_groove"], 0.0)
        seam = f["seam"] < 0.05
        rgb = np.where(seam[:, None], C.depth_tint(rgb, gdepth, C.GROOVE, 0.003, 0.03), rgb)
        # teeth: very slightly warmer ivory with darker roots
        teeth = f["teeth"] < 0.003
        rgb = np.where(teeth[:, None], rgb * hex_color("#FFF8EA")[None, :], rgb)
        if style == "Fell":
            # red stain toward horn tips and spikes
            tipness = smoothstep(1.15, 1.8, P[:, 2]) + smoothstep(1.15, 1.45, np.abs(P[:, 0])) + \
                smoothstep(0.85, 1.05, P[:, 1])
            rgb = C.lerp_rgb(rgb, C.FELL_RED * 0.85, np.clip(tipness, 0, 1) * 0.55)
        if style == "Eclipse":
            # void tint creeping up the ear spikes and into the sockets
            tipness = smoothstep(0.55, 1.15, P[:, 1]) * smoothstep(0.55, 1.0, P[:, 2])
            rgb = C.lerp_rgb(rgb, C.ECL_VIOLET * 0.7, np.clip(tipness, 0, 1) * 0.75)
        if cracks is not None:
            rgb = crack_colors(rgb, P, f, cracks, in_eye)
        return rgb

    return colorize


def crack_colors(rgb, P, f, cracks, in_eye):
    dist = C.crack_dist(P, cracks["paths"])
    cdepth = np.maximum(-f["pre_cracks"], 0.0)
    w = cracks["width"]
    t = np.maximum(smoothstep(0.0, cracks["depth"] * 0.6, cdepth), smoothstep(w * 1.1, w * 0.25, dist))
    inside = (((cdepth > 0.003) | (dist < w * 0.6)) & ~in_eye)[:, None]
    if cracks["kind"] == "eclipse":
        halo = smoothstep(0.09, 0.0, dist) * (~in_eye)
        rgb = C.lerp_rgb(rgb, C.ECL_HALO, halo * 0.6)
        core = C.lerp_rgb(C.lerp_rgb(C.ECL_VIOLET_DEEP, C.ECL_VIOLET, smoothstep(0.0, 0.4, t)), C.ECL_CYAN,
                          smoothstep(0.55, 0.95, t))
    else:
        rim = smoothstep(0.08, 0.0, dist) * (~in_eye)
        rgb = C.lerp_rgb(rgb, C.FELL_RED * 0.9, rim * 0.45)
        core = C.lerp_rgb(C.FELL_RED * 0.75, C.FELL_DARK * 0.5, t)
    return np.where(inside, core, rgb)


def _crack_set(style, surface, center, which):
    st = STYLES[style]
    if st["crack"] is None:
        return None
    if which == "skull":
        if style == "Fell":
            paths = [
                (np.array([(-0.10, 0.95), (-0.22, 0.80), (-0.18, 0.66), (-0.32, 0.52), (-0.30, 0.40)]), 1.0),
                (np.array([(-0.22, 0.80), (-0.40, 0.84), (-0.52, 0.76)]), 0.6),
                (np.array([(0.10, 0.30), (0.05, 0.18), (0.12, 0.06), (0.06, -0.04)]), 0.7),
            ]
            width, depth = 0.04, 0.07
        else:
            paths = [
                (np.array([(0.02, 1.25), (0.10, 1.10), (0.06, 0.96), (0.18, 0.84), (0.14, 0.70), (0.28, 0.58),
                           (0.26, 0.48), (0.36, 0.40)]), 1.0),
                (np.array([(0.10, 1.10), (0.30, 1.16), (0.46, 1.06), (0.66, 1.10), (0.82, 1.00)]), 0.7),
                (np.array([(0.18, 0.84), (0.36, 0.86), (0.48, 0.76)]), 0.5),
                # down the snout toward the nose
                (np.array([(-0.06, 0.40), (-0.12, 0.30), (-0.06, 0.22), (-0.14, 0.14), (-0.08, 0.08)]), 0.75),
                (np.array([(-0.12, 0.30), (-0.24, 0.26), (-0.30, 0.18)]), 0.45),
            ]
            width, depth = 0.05, 0.085
    else:
        if style == "Fell":
            paths = [(np.array([(0.10, -0.55), (0.20, -0.60), (0.28, -0.52), (0.38, -0.58)]), 1.0)]
            width, depth = 0.035, 0.05
        else:
            paths = [(np.array([(-0.08, -0.50), (-0.18, -0.58), (-0.26, -0.50), (-0.36, -0.56), (-0.46, -0.50)]), 1.0),
                     (np.array([(-0.26, -0.50), (-0.30, -0.40)]), 0.5)]
            width, depth = 0.04, 0.05
    cr = C.project_paths(surface, center, paths, r_out=3.5)
    return {"paths": cr, "width": width, "depth": depth, "kind": st["crack"]}


def skull_anchors(style):
    st = STYLES[style]
    ex, ey, ez = st["eye_c"]
    yaw = st["eye_yaw"]
    # socket floor along the socket axis
    fl = np.array([ex, ey, ez]) + rot_y(-yaw) @ np.array([0.0, 0.0, 0.20 - 0.05])
    L = st["snout_len"]
    return {
        "RightEye": tuple(fl),
        "LeftEye": (-fl[0], fl[1], fl[2]),
        "Muzzle": (0.0, -0.50, -L - 0.05),
        "JawHinge": HINGE,
        "HornTipRight": tuple(st["horn"]["tip"]),
        "HornTipLeft": (-st["horn"]["tip"][0], st["horn"]["tip"][1], st["horn"]["tip"][2]),
    }


def skull_bounds(style):
    st = STYLES[style]
    L = st["snout_len"]
    hx = max(st["horn"]["tip"][0], max(a[0] for _, a, _ in [(None, s[1], None) for s in st["cheek_spikes"]])) + 0.25
    return (-hx, -1.05, -L - 0.30), (hx, 1.62, 1.95)


def skull(style) -> ModelSpec:
    base = skull_field(style)
    surf = lambda p: base(p)["d"]  # noqa: E731
    cracks = _crack_set(style, surf, (0.0, 0.2, 0.0), "skull")
    lo, hi = skull_bounds(style)
    return ModelSpec(
        name=f"BlasterSkull{style}", lo=lo, hi=hi, field=skull_field(style, cracks), colorize=skull_colorize(style, cracks),
        budget=8000, anchors=skull_anchors(style), resolution=220,
        description=f"Gaster Blaster skull ({style}); the jaw is BlasterJaw{style}, hinged at Anchors.JawHinge.",
        ao_strength=0.55, ao_scale=1.2,
    )


# ---------------------------------------------------------------------------------------------
# Jaw
# ---------------------------------------------------------------------------------------------
def jaw_profile(st, z):
    L = st["snout_len"]
    t = clamp((0.40 - z) / (L + 0.40 - 0.12), 0.0, 1.0)
    rx = mix(st["snout_w"][0] * 0.98, st["snout_w"][1] * 0.95, t**0.9)
    top = mix(-0.40, -0.40 - st["snout_top_drop"] * 0.10, t)
    bot = mix(-0.90, -0.70, t)
    return rx, top, bot, t


def jaw_field(style, cracks=None):
    st = STYLES[style]
    L = st["snout_len"]

    def field(p):
        q = mirror_x(p)
        rx, top, bot, t = jaw_profile(st, p[:, 2])
        cy = (top + bot) * 0.5
        ry = (top - bot) * 0.5
        x = p[:, 0]
        y = p[:, 1] - cy
        # outer body: elliptical bottom, flat-ish top
        k0 = np.sqrt((x / rx) ** 2 + (y / (ry * 1.6)) ** 2)
        k1 = np.sqrt((x / (rx * rx)) ** 2 + (y / ((ry * 1.6) ** 2)) ** 2)
        body = k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
        body = smax(body, p[:, 1] - top, 0.06)
        dz = np.maximum(p[:, 2] - 0.30, -(L - 0.05) - p[:, 2])
        body = smax(body, dz, 0.22)
        # hollow trough (inside of the mouth)
        inner_rx = np.maximum(rx - 0.15, 0.04)
        k0i = np.sqrt((x / inner_rx) ** 2 + ((p[:, 1] - top) / (ry * 1.25)) ** 2)
        k1i = np.sqrt((x / (inner_rx**2)) ** 2 + ((p[:, 1] - top) / ((ry * 1.25) ** 2)) ** 2)
        trough = k0i * (k0i - 1.0) / np.maximum(k1i, 1e-9)
        trough = smax(trough, np.maximum(p[:, 2] - 0.05, -(L - 0.30) - p[:, 2]), 0.15)
        d = smax(body, -trough, 0.05)
        # rami rising to the hinge + condyles
        ramus = round_cone(q, (0.74, -0.62, 0.18), (0.76, HINGE[1], HINGE[2]), 0.13, 0.10)
        d = smin(d, ramus, 0.12)
        cond = ellipsoid(q, (0.74, HINGE[1], HINGE[2]), (0.12, 0.11, 0.12))
        d = smin(d, cond, 0.06)
        # lower edge ridge
        rl = round_cone(q, (0.70, -0.86, 0.10), (0.20, -0.72, -L + 0.30), 0.06, 0.05)
        d = smin(d, rl, 0.08)
        # chin
        chin = ellipsoid(p, (0, -0.70, -L + 0.18), (0.22, 0.12, 0.18))
        d = smin(d, chin, 0.10)
        if style == "Fell":
            d = smin(d, spikes_sdf(q, [((0.10, -0.74, -L + 0.30), (0.16, -1.02, -L + 0.12), 0.07),
                                       ((0.62, -0.78, -0.20), (0.82, -1.00, 0.18), 0.07)]), 0.05)
        if style == "Eclipse":
            # wolf: slight downward hook at the chin
            d = smin(d, ellipsoid(p, (0, -0.74, -L + 0.40), (0.16, 0.10, 0.30)), 0.08)
        body_d = d
        lt = teeth_sdf(q, teeth_specs(st, upper=False))
        d = smin(d, lt, 0.02)
        out = {"body": body_d, "trough": trough, "teeth": lt}
        pre_cracks = d
        if cracks is not None:
            d = C.carve_cracks(d, p, cracks["paths"], cracks["width"], cracks["depth"])
        out["pre_cracks"] = pre_cracks
        out["d"] = d
        return out

    return field


def jaw_colorize(style, cracks=None):
    st = STYLES[style]
    bone = hex_color(st["bone"])
    inner = hex_color(st["inner"])

    def colorize(P, N, f):
        n = len(P)
        rgb = C.solid(n, bone)
        rgb = rgb * (0.97 + 0.03 * np.clip(N[:, 1], -1, 1))[:, None]
        inside = (f["trough"] < 0.02) & (f["teeth"] > 0.004)
        depth = np.maximum(-(P[:, 1] - jaw_profile(st, P[:, 2])[1]), 0.0)
        rgb = np.where(inside[:, None], C.depth_tint(rgb, depth, inner, 0.01, 0.10), rgb)
        teeth = f["teeth"] < 0.003
        rgb = np.where(teeth[:, None], rgb * hex_color("#FFF8EA")[None, :], rgb)
        if cracks is not None:
            rgb = crack_colors(rgb, P, f, cracks, np.zeros(n, dtype=bool))
        return rgb

    return colorize


def jaw(style) -> ModelSpec:
    st = STYLES[style]
    L = st["snout_len"]
    base = jaw_field(style)
    surf = lambda p: base(p)["d"]  # noqa: E731
    cracks = _crack_set(style, surf, (0.0, -0.45, -0.6), "jaw")
    lo, hi = (-1.15, -1.15, -L - 0.25), (1.15, 0.05, 0.75)
    return ModelSpec(
        name=f"BlasterJaw{style}", lo=lo, hi=hi, field=jaw_field(style, cracks), colorize=jaw_colorize(style, cracks),
        budget=3000, hinge=HINGE, anchors={"Hinge": HINGE}, resolution=200,
        description=f"Gaster Blaster lower jaw ({style}); rotate about Hinge (X axis) to open.",
        ao_strength=0.5, ao_scale=0.9,
    )
