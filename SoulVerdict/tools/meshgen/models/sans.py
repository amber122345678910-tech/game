"""Sans skulls (Classic / Fell / Eclipse). Face looks toward -Z; +X is the skull's right side
(the viewer's LEFT when looking at the face)."""
from __future__ import annotations

import math

import numpy as np

from mesher import ModelSpec
from models import common as C
from sdf import (bounded, clamp, ellipse_prism, ellipsoid, euler, mirror_x, mix, polyline_dist_3d, round_box, rot_z, smax,
                 smin, smoothstep, tri_prism, vec)

# Mouth layout in cylindrical (u, v) face coordinates
AXIS_Z = 0.22
CYL_R = 1.16
GRIN_Y0 = -0.47  # upper lip line height at the centre
GRIN_A = 0.26  # upper line curvature
GRIN_DROP = 0.215  # teeth height at the centre
GRIN_C = 0.62  # lower line curvature
EYE_C = (0.45, 0.10, -0.99)
EYE_R = (0.325, 0.225, 0.42)
EYE_FLOOR_Z = -0.66


def upper_v(u):
    return GRIN_Y0 + GRIN_A * u * u


def lower_v(u):
    return GRIN_Y0 - GRIN_DROP + GRIN_C * u * u


def corner_u():
    # where the two parabolas meet
    return math.sqrt(GRIN_DROP / (GRIN_C - GRIN_A))


def head_shape(p, fell=False):
    """Uncarved head volume."""
    cran = ellipsoid(p, (0, 0.11, 0.10), (1.04, 0.87, 0.90))
    boxy = round_box(p, (0, 0.08, 0.09), (1.0, 0.85, 0.90), 0.66)
    d = mix(cran, boxy, 0.42)
    jaw = round_box(p, (0, -0.40, -0.20), (0.82, 0.44, 0.70), 0.40)
    d = smin(d, jaw, 0.32)
    q = mirror_x(p)
    # subtle cheekbones (trimmed by the face plane below)
    cheek = ellipsoid(q, (0.66, -0.13, -0.70), (0.25, 0.13, 0.22), euler(0, -0.35, 0.25))
    d = smin(d, cheek, 0.14)
    # flat face plane; the lower face sits slightly proud (jaw line), flattened skull base
    zf = -0.975 - 0.035 * smoothstep(-0.12, -0.67, p[:, 1])
    d = smax(d, zf - p[:, 2], 0.22)
    d = smax(d, -(p[:, 1] + 0.86), 0.22)
    if fell:
        # heavy brow ridge along the top of each socket, slanting down toward the nose (angry)
        brow = ellipsoid(q, (0.44, 0.40, -0.80), (0.44, 0.19, 0.23), rot_z(0.30))
        d = smin(d, brow, 0.16)
        glabella = ellipsoid(p, (0.0, 0.26, -0.84), (0.16, 0.14, 0.16))
        d = smin(d, glabella, 0.12)
    return d


def eye_cutter(p, fell=False):
    q = mirror_x(p)
    e = ellipse_prism(q, (EYE_C[0], EYE_C[1], 0.0), (EYE_R[0], EYE_R[1]), -1.6, EYE_FLOOR_Z, rot_z(0.02),
                      floor_round=0.12)
    if fell:
        # angry: flat top edge slanting down toward the nose
        slant = (q[:, 1] - 0.235) * math.cos(0.34) - (q[:, 0] - 0.43) * math.sin(0.34)
        e = smax(e, slant, 0.06)
    return e


def nose_cutter(p):
    return tri_prism(p, (0, -0.215, -0.99), 0.112, 0.118, 0.30, apex_up=True, round_r=0.03)


def mouth_lines(fell=False):
    uc = corner_u()
    up = C.sample_curve(upper_v, -uc, uc, 56)
    lo = C.sample_curve(lower_v, -uc, uc, 56)
    lines = [up, lo]
    # corner curls (continue the upper line upward) and crossing dashes (the "stitch")
    for s in (-1.0, 1.0):
        cu, cv = s * uc, upper_v(uc)
        curl = np.array([[cu, cv], [cu + s * 0.035, cv + 0.05], [cu + s * 0.045, cv + 0.085]])
        dash = np.array([[cu - s * 0.055, cv + 0.035], [cu + s * 0.11, cv + 0.05]])
        lines += [curl, dash]
    teeth = []
    if fell:
        # zig-zag between upper and lower teeth: sharp interlocking fangs
        n = 11
        us = np.linspace(-uc * 0.93, uc * 0.93, n)
        zz = []
        for i, u in enumerate(us):
            top, bot = upper_v(u), lower_v(u)
            t = 0.18 if i % 2 == 0 else 0.86
            zz.append([u, top + (bot - top) * t])
        teeth.append(np.array(zz))
    else:
        for u in (-0.525, -0.315, -0.105, 0.105, 0.315, 0.525):
            teeth.append(np.array([[u, upper_v(u) + 0.01], [u, lower_v(u) - 0.01]]))
    return lines, teeth


def sans_field(variant: str, cracks=None, chip=None):
    fell = variant == "Fell"

    def field(p):
        head = head_shape(p, fell)
        # --- eye sockets & nose
        eye = bounded(p, (-0.80, -0.25, -1.30), (0.80, 0.42, -0.45), lambda x: eye_cutter(x, fell), 0.08)
        nose = bounded(p, (-0.16, -0.36, -1.30), (0.16, -0.08, -0.65), nose_cutter, 0.06)
        d = smax(head, -eye, 0.034)
        d = smax(d, -nose, 0.03)
        pre_mouth = d
        # --- grin (cylindrical projection onto the face)
        lines, teeth = mouth_lines(fell)

        def mouth_cut(x):
            u, v = C.cyl_uv(x, AXIS_Z, CYL_R)
            dl = C.lines_dist(u, v, lines)
            dt = C.lines_dist(u, v, teeth)
            return dl, dt

        mbox_lo, mbox_hi = (-1.0, -0.86, -1.30), (1.0, -0.20, -0.30)
        inside = np.all((p >= vec(mbox_lo)) & (p <= vec(mbox_hi)), axis=1)
        dl = np.full(len(p), 9.0)
        dt = np.full(len(p), 9.0)
        if inside.any():
            a, b = mouth_cut(p[inside])
            dl[inside] = a
            dt[inside] = b
        d = C.carve(d, dl, 0.024, 0.075, k=0.006)
        d = C.carve(d, dt, 0.0145 if not fell else 0.016, 0.06, k=0.005, profile="v" if fell else "u")
        pre_cracks = d
        out = {"head": head, "eye": eye, "nose": nose, "pre_mouth": pre_mouth, "line": dl, "teeth": dt}
        if cracks is not None:
            d = C.carve_cracks(d, p, cracks["paths"], cracks["width"], cracks["depth"])
        if chip is not None:
            cd = ellipsoid(p, chip["center"], chip["radii"], chip.get("R"))
            from sdf import fbm

            cd = cd + 0.018 * fbm(p, 9.0, 2, seed=chip.get("seed", 3))
            d = smax(d, -cd, 0.02)
            out["chip"] = cd
        out["pre_cracks"] = pre_cracks
        out["d"] = d
        return out

    return field


def sans_colorize(variant: str, cracks=None, gold=None):
    fell = variant == "Fell"
    bone = C.BONE_WARM * 0.25 + C.BONE * 0.75 if fell else C.BONE

    def colorize(P, N, f):
        n = len(P)
        rgb = C.solid(n, bone)
        # subtle top-lit gradient on the bone (cartoon "cel" bias)
        rgb = rgb * (0.965 + 0.035 * np.clip(N[:, 1], -1, 1))[:, None]
        # eye sockets & nose: dark by depth below the head surface
        depth = np.maximum(-f["head"], 0.0)
        in_eye = f["eye"] < 0.012
        in_nose = f["nose"] < 0.012
        socket_col = C.FELL_DARK * 0.35 + C.SOCKET * 0.65 if fell else C.SOCKET
        rgb = np.where((in_eye | in_nose)[:, None], C.depth_tint(rgb, depth, socket_col, 0.02, 0.075), rgb)
        # grin grooves
        gdepth = np.maximum(-f["pre_mouth"], 0.0)
        groove = (f["line"] < 0.06) | (f["teeth"] < 0.05)
        rgb = np.where(groove[:, None], C.depth_tint(rgb, gdepth, C.GROOVE, 0.006, 0.035), rgb)
        if gold is not None:
            u, v = C.cyl_uv(P, AXIS_Z, CYL_R)
            g = gold(u, v) & (gdepth < 0.012) & (P[:, 2] < -0.4)
            sheen = np.clip(0.5 + 0.5 * N[:, 1] - 0.3 * N[:, 0], 0, 1)
            gold_rgb = C.lerp_rgb(C.GOLD, C.GOLD_HI, sheen * 0.6)
            rgb = np.where(g[:, None], gold_rgb, rgb)
        if cracks is not None:
            dist = C.crack_dist(P, cracks["paths"])
            cdepth = np.maximum(-f["pre_cracks"], 0.0)
            kind = cracks["kind"]
            if kind == "eclipse":
                halo = smoothstep(0.085, 0.0, dist) * (~in_eye)
                rgb = C.lerp_rgb(rgb, C.ECL_HALO, halo * 0.6)
                w = cracks["width"]
                t = np.maximum(smoothstep(0.0, cracks["depth"] * 0.6, cdepth), smoothstep(w * 1.1, w * 0.25, dist))
                core = C.lerp_rgb(C.lerp_rgb(C.ECL_VIOLET_DEEP, C.ECL_VIOLET, smoothstep(0.0, 0.4, t)), C.ECL_CYAN,
                                  smoothstep(0.55, 0.95, t))
                inside = (((cdepth > 0.003) | (dist < w * 0.6)) & ~in_eye)[:, None]
                rgb = np.where(inside, core, rgb)
            else:  # fell scar
                w = cracks["width"]
                t = np.maximum(smoothstep(0.0, cracks["depth"] * 0.6, cdepth), smoothstep(w, w * 0.2, dist))
                rim = smoothstep(0.07, 0.0, dist)
                rgb = C.lerp_rgb(rgb, C.BONE_WARM * 0.78, rim * 0.6)
                scar = C.lerp_rgb(C.FELL_RED * 0.6, C.FELL_DARK * 0.6, t)
                rgb = np.where(((cdepth > 0.003) | (dist < w * 0.55))[:, None], scar, rgb)
        if "chip" in f:
            cdepth = np.maximum(-f["pre_cracks"], 0.0)
            chip = (f["chip"] < 0.01) & (cdepth > 0.004)
            t = smoothstep(0.004, 0.06, cdepth)
            rgb = np.where(chip[:, None], C.lerp_rgb(C.ECL_VIOLET * 0.8, C.ECL_VOID, t), rgb)
        return rgb

    return colorize


def _anchors():
    # Roblox: the skull faces -Z, so the character's RIGHT is +X and its LEFT is -X.
    ex, ey, ez = EYE_C
    floor_z = EYE_FLOOR_Z - 0.04
    return {
        "RightEye": (ex, ey, floor_z),
        "LeftEye": (-ex, ey, floor_z),
        "Mouth": (0.0, GRIN_Y0 - GRIN_DROP * 0.5, -0.99),
        "Top": (0.0, 0.96, 0.10),
    }


BOUNDS = ((-1.16, -1.02, -1.14), (1.16, 1.08, 1.12))
SANS_RES = 160  # grid cells along the longest axis (finer grids decimate into noisier 6k meshes)


def classic() -> ModelSpec:
    return ModelSpec(
        name="SansSkullClassic", lo=BOUNDS[0], hi=BOUNDS[1], field=sans_field("Classic"),
        colorize=sans_colorize("Classic"), budget=6000, anchors=_anchors(),
        description="Classic Sans skull: wide round cranium, deep eye sockets, nasal cavity, permanent grin.",
        ao_strength=0.5, ao_scale=0.9, resolution=SANS_RES,
    )


def _surface_for_cracks(variant):
    f = sans_field(variant)
    return lambda p: f(p)["d"]


def fell() -> ModelSpec:
    surf = _surface_for_cracks("Fell")
    # vertical scar through the skull's right eye (+X, viewer's left): forehead -> socket -> cheek
    pts = [(0.40, 0.64), (0.435, 0.55), (0.395, 0.47), (0.43, 0.38), (0.40, 0.28), (0.42, 0.16), (0.40, 0.02),
           (0.415, -0.10), (0.385, -0.20), (0.425, -0.30), (0.395, -0.40)]
    paths = [(np.array(pts), 1.0)]
    # two short side splinters near the brow
    paths.append((np.array([(0.405, 0.42), (0.47, 0.50), (0.52, 0.53)]), 0.5))
    paths.append((np.array([(0.40, -0.18), (0.33, -0.26), (0.30, -0.31)]), 0.45))
    cr = C.project_paths(surf, (0.0, 0.05, 0.10), paths, r_out=2.5)
    cracks = {"paths": cr, "width": 0.042, "depth": 0.085, "kind": "fell"}
    uc = corner_u()

    def gold(u, v):
        # one upper fang on the skull's left side (-X, viewer's right): the zig-zag triangle whose tip
        # points down at us[3]; only the part above the zig-zag (upper teeth) is gold
        us = np.linspace(-uc * 0.93, uc * 0.93, 11)
        zz = np.array([upper_v(x) + (lower_v(x) - upper_v(x)) * (0.18 if i % 2 == 0 else 0.86)
                       for i, x in enumerate(us)])
        line = np.interp(u, us, zz)
        return (u > us[2] + 0.01) & (u < us[4] - 0.01) & (v < upper_v(u) - 0.012) & (v > line + 0.016)

    return ModelSpec(
        name="SansSkullFell", lo=BOUNDS[0], hi=BOUNDS[1], field=sans_field("Fell", cracks=cracks),
        colorize=sans_colorize("Fell", cracks=cracks, gold=gold), budget=6000, anchors=_anchors(),
        description="Fell Sans skull: heavy angry brow, cracked right eye socket, jagged grin with one gold tooth.",
        ao_strength=0.6, ao_scale=0.9, resolution=SANS_RES,
    )


def eclipse() -> ModelSpec:
    surf = _surface_for_cracks("Classic")
    # branching cracks across the top-left of the cranium (viewer's left = skull's right = +X)
    # (azimuth, elevation) polylines; azimuth + = skull's right (+X, viewer's left)
    main = [(0.02, 1.30), (0.08, 1.12), (0.20, 1.02), (0.17, 0.88), (0.30, 0.74), (0.27, 0.60), (0.38, 0.48),
            (0.40, 0.36)]
    paths = [
        (np.array(main), 1.0),
        (np.array([(0.20, 1.02), (0.38, 1.06), (0.52, 0.98), (0.70, 1.02), (0.86, 0.92)]), 0.72),
        (np.array([(0.30, 0.74), (0.46, 0.70), (0.58, 0.58), (0.74, 0.56)]), 0.6),
        (np.array([(0.52, 0.98), (0.60, 1.14), (0.78, 1.22)]), 0.45),
        (np.array([(0.08, 1.12), (-0.06, 1.02), (-0.12, 0.92)]), 0.4),
    ]
    cr = C.project_paths(surf, (0.0, 0.05, 0.12), paths, r_out=2.5)
    cracks = {"paths": cr, "width": 0.046, "depth": 0.10, "kind": "eclipse"}
    # missing chip near the crack
    chip_dir = C.sph_dir(0.60, 0.80)
    chip_c = vec((0.0, 0.05, 0.12)) + chip_dir * 1.0
    hit, _ = __import__("sdf").surface_project(surf, (vec((0.0, 0.05, 0.12)) + chip_dir * 2.5)[None, :],
                                               -chip_dir[None, :], 2.5)
    chip = {"center": tuple(hit[0] + chip_dir * 0.035), "radii": (0.15, 0.11, 0.13), "seed": 4}
    return ModelSpec(
        name="SansSkullEclipse", lo=BOUNDS[0], hi=BOUNDS[1], field=sans_field("Classic", cracks=cracks, chip=chip),
        colorize=sans_colorize("Classic", cracks=cracks), budget=6000, anchors=_anchors(),
        description="Eclipse Sans skull (original AU): Classic base with glowing violet/cyan branching cracks and a chipped crown.",
        ao_strength=0.5, ao_scale=0.9, resolution=SANS_RES,
    )
