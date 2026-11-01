"""SDF model -> clean, decimated, vertex-coloured triangle mesh.

Pipeline: narrow-band grid evaluation -> marching cubes (skimage) -> keep main components ->
Taubin smoothing -> projection onto the zero set -> quadric decimation (fast_simplification) ->
re-projection -> smooth normals (SDF gradient, mesh fallback) -> region colours (model) ->
SDF ambient occlusion bake -> palette quantisation -> centre at the bounding-box centre.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field

import fast_simplification
import numpy as np
import trimesh
from scipy import ndimage
from scipy.cluster.vq import kmeans2
from skimage.measure import marching_cubes

from sdf import clamp, gradient, length, vec


@dataclass
class ModelSpec:
    """A mesh to build. `field(p)` returns a dict with at least 'd' (signed distance)."""

    name: str
    lo: tuple
    hi: tuple
    field: callable
    colorize: callable  # (P, N, fields) -> (N,3) sRGB 0..1
    budget: int
    description: str = ""
    anchors: dict = field(default_factory=dict)  # design-space points
    hinge: tuple | None = None  # design-space hinge point (jaws)
    ao_strength: float = 0.55
    ao_scale: float = 1.0  # characteristic size used for AO probe distances
    resolution: int = 200
    min_component_frac: float = 0.002
    taubin_iters: int = 6


@dataclass
class MeshResult:
    name: str
    vertices: np.ndarray  # (V,3) centred
    normals: np.ndarray  # (V,3)
    colors: np.ndarray  # (V,3) sRGB 0..1 (after palette quantisation)
    palette: np.ndarray  # (P,4) uint8 RGBA
    color_index: np.ndarray  # (V,) uint8
    faces: np.ndarray  # (T,3) int
    size: np.ndarray  # (3,)
    center: np.ndarray  # design-space bbox centre that was subtracted
    anchors: dict
    hinge: np.ndarray | None
    description: str = ""
    stats: dict = field(default_factory=dict)


def _field_d(spec: ModelSpec):
    return lambda p: spec.field(p)["d"]


def evaluate_grid(fn, lo, hi, res: int, block: int = 8, lipschitz: float = 2.0, chunk: int = 400_000):
    lo = vec(lo)
    hi = vec(hi)
    ext = hi - lo
    h = float(ext.max()) / res
    n = (np.ceil(ext / h).astype(int) + 1).clip(min=4)
    nb = np.ceil((n - 1) / block).astype(int).clip(min=1)
    # block centres
    bi = [(np.arange(nb[a]) * block + block * 0.5) * h + lo[a] for a in range(3)]
    BX, BY, BZ = np.meshgrid(bi[0], bi[1], bi[2], indexing="ij")
    centers = np.stack([BX.ravel(), BY.ravel(), BZ.ravel()], axis=1)
    dc = np.concatenate([fn(centers[i : i + chunk]) for i in range(0, len(centers), chunk)])
    dc = dc.reshape(tuple(nb))
    half_diag = np.sqrt(3.0) * block * h * 0.5
    active = np.abs(dc) <= lipschitz * half_diag + 2 * h
    active = ndimage.binary_dilation(active, iterations=1)
    ix = [np.minimum(np.arange(n[a]) // block, nb[a] - 1) for a in range(3)]
    vol = dc[ix[0][:, None, None], ix[1][None, :, None], ix[2][None, None, :]].astype(np.float32)
    mask = active[ix[0][:, None, None], ix[1][None, :, None], ix[2][None, None, :]]
    idx = np.nonzero(mask)
    total = len(idx[0])
    for s in range(0, total, chunk):
        sl = slice(s, s + chunk)
        pts = np.stack([idx[0][sl] * h + lo[0], idx[1][sl] * h + lo[1], idx[2][sl] * h + lo[2]], axis=1)
        vol[idx[0][sl], idx[1][sl], idx[2][sl]] = fn(pts).astype(np.float32)
    return vol, lo, h, total


def project_to_surface(fn, verts, iters: int = 2, max_step: float = 0.02):
    v = verts.copy()
    for _ in range(iters):
        d = fn(v)
        g = gradient(fn, v, 1e-3)
        g2 = np.maximum(np.einsum("ij,ij->i", g, g), 1e-6)
        step = (d / g2)[:, None] * g
        sl = length(step)
        scale = np.minimum(1.0, max_step / np.maximum(sl, 1e-12))
        v = v - step * scale[:, None]
    return v


def sdf_ao(fn, P, N, scale: float, strength: float):
    """Classic SDF ambient occlusion probe along the normal (iq)."""
    occ = np.zeros(len(P))
    sca = 1.0
    for i in range(5):
        hh = scale * (0.02 + 0.16 * i / 4.0)
        d = fn(P + N * hh)
        occ += (hh - d) * sca
        sca *= 0.75
    ao = clamp(1.0 - strength * occ / scale * 3.0, 0.0, 1.0)
    return ao


def octa_encode(n: np.ndarray) -> np.ndarray:
    """Precise 8-bit octahedral encoding -> (V,2) uint8."""
    n = n / np.maximum(np.abs(n).sum(axis=1, keepdims=True), 1e-12)
    x, y, z = n[:, 0].copy(), n[:, 1].copy(), n[:, 2]
    neg = z < 0
    sx = np.where(x >= 0, 1.0, -1.0)
    sy = np.where(y >= 0, 1.0, -1.0)
    ox = np.where(neg, (1.0 - np.abs(y)) * sx, x)
    oy = np.where(neg, (1.0 - np.abs(x)) * sy, y)
    fx = (ox * 0.5 + 0.5) * 255.0
    fy = (oy * 0.5 + 0.5) * 255.0
    best = None
    best_err = None
    target = n / np.linalg.norm(n, axis=1, keepdims=True)
    for cx in (np.floor(fx), np.ceil(fx)):
        for cy in (np.floor(fy), np.ceil(fy)):
            cx_ = np.clip(cx, 0, 255)
            cy_ = np.clip(cy, 0, 255)
            dec = octa_decode(np.stack([cx_, cy_], axis=1).astype(np.uint8))
            err = 1.0 - np.einsum("ij,ij->i", dec, target)
            cand = np.stack([cx_, cy_], axis=1)
            if best is None:
                best, best_err = cand, err
            else:
                better = err < best_err
                best[better] = cand[better]
                best_err = np.where(better, err, best_err)
    return best.astype(np.uint8)


def octa_decode(e: np.ndarray) -> np.ndarray:
    x = e[:, 0].astype(np.float64) / 255.0 * 2.0 - 1.0
    y = e[:, 1].astype(np.float64) / 255.0 * 2.0 - 1.0
    z = 1.0 - np.abs(x) - np.abs(y)
    neg = z < 0
    sx = np.where(x >= 0, 1.0, -1.0)
    sy = np.where(y >= 0, 1.0, -1.0)
    nx = np.where(neg, (1.0 - np.abs(y)) * sx, x)
    ny = np.where(neg, (1.0 - np.abs(x)) * sy, y)
    v = np.stack([nx, ny, z], axis=1)
    return v / np.linalg.norm(v, axis=1, keepdims=True)


def quantize_palette(colors: np.ndarray, max_colors: int = 255, seed: int = 7):
    """sRGB (V,3) floats -> palette (P,4) uint8 + per-vertex uint8 indices."""
    c8 = np.clip(np.round(colors * 255.0), 0, 255).astype(np.int64)
    keys = c8[:, 0] * 65536 + c8[:, 1] * 256 + c8[:, 2]
    uniq, inv = np.unique(keys, return_inverse=True)
    if len(uniq) <= max_colors:
        pal = np.stack([uniq // 65536, (uniq // 256) % 256, uniq % 256], axis=1)
        idx = inv
    else:
        data = c8.astype(np.float64)
        rng = np.random.default_rng(seed)
        np.random.seed(seed)
        init = data[rng.choice(len(data), size=max_colors, replace=False)]
        centers, labels = kmeans2(data, init, iter=25, minit="matrix")
        # make sure extreme (glow / gold) colours are represented exactly: snap centre to member mean
        pal = np.clip(np.round(centers), 0, 255).astype(np.int64)
        used = np.unique(labels)
        remap = -np.ones(len(pal), dtype=np.int64)
        remap[used] = np.arange(len(used))
        pal = pal[used]
        idx = remap[labels]
    palette = np.concatenate([pal, np.full((len(pal), 1), 255)], axis=1).astype(np.uint8)
    return palette, idx.astype(np.uint8)


def decimate(V, F, target: int):
    """Quadric edge-collapse decimation to <= target faces. Prefers MeshLab (better triangle quality,
    normal-flip protection); falls back to fast_simplification when pymeshlab is unavailable."""
    try:
        import pymeshlab  # needs the system libOpenGL.so.0 (apt: libopengl0)

        ms = pymeshlab.MeshSet()
        ms.add_mesh(pymeshlab.Mesh(vertex_matrix=np.asarray(V, dtype=np.float64), face_matrix=np.asarray(F)))
        goal = int(target)
        for _ in range(6):
            ms.meshing_decimation_quadric_edge_collapse(targetfacenum=goal, qualitythr=0.55, preservenormal=True,
                                                        preservetopology=True, optimalplacement=True,
                                                        planarquadric=True, planarweight=0.0015, autoclean=True)
            if ms.current_mesh().face_number() <= target:
                break
            goal = int(goal * 0.985)
        m = ms.current_mesh()
        return np.asarray(m.vertex_matrix(), dtype=np.float64), np.asarray(m.face_matrix()), "meshlab"
    except Exception as exc:  # pragma: no cover - fallback path
        print("  (pymeshlab unavailable, using fast_simplification:", type(exc).__name__, ")")
        v, f = np.asarray(V), np.asarray(F)
        goal = float(target)
        for _ in range(6):
            v, f = fast_simplification.simplify(np.asarray(V, dtype=np.float32), np.asarray(F), target_count=int(goal),
                                                agg=5.0)
            if len(f) <= target:
                break
            goal *= 0.98
        return np.asarray(v, dtype=np.float64), np.asarray(f), "fast_simplification"


def smooth_vertex_scalar(F, values, iterations=3, alpha=0.5):
    """Laplacian smoothing of a per-vertex scalar over the mesh graph (removes AO blotches)."""
    n = len(values)
    e = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    deg = np.bincount(e[:, 0], minlength=n).astype(np.float64)
    v = values.astype(np.float64).copy()
    for _ in range(iterations):
        acc = np.bincount(e[:, 0], weights=v[e[:, 1]], minlength=n)
        avg = acc / np.maximum(deg, 1)
        v = v * (1 - alpha) + avg * alpha
    return v


def keep_main_components(mesh: trimesh.Trimesh, min_frac: float) -> trimesh.Trimesh:
    parts = mesh.split(only_watertight=False)
    if len(parts) <= 1:
        return mesh
    total = sum(p.area for p in parts)
    keep = [p for p in parts if p.area >= min_frac * total]
    return trimesh.util.concatenate(keep)


def build(spec: ModelSpec, res: int | None = None, verbose: bool = True) -> MeshResult:
    t0 = time.time()
    fn = _field_d(spec)
    res = res or spec.resolution
    vol, lo, h, n_eval = evaluate_grid(fn, spec.lo, spec.hi, res)
    t1 = time.time()
    # the volume must be positive at its border, otherwise the shape is clipped
    border = np.concatenate([vol[0].ravel(), vol[-1].ravel(), vol[:, 0].ravel(), vol[:, -1].ravel(),
                             vol[:, :, 0].ravel(), vol[:, :, -1].ravel()])
    if (border <= 0).any():
        print(f"  WARNING {spec.name}: shape touches the evaluation bounds ({int((border <= 0).sum())} samples)")
    verts, faces, _, _ = marching_cubes(vol, level=0.0, spacing=(h, h, h), gradient_direction="ascent",
                                        allow_degenerate=False)
    verts = verts + lo
    mesh = trimesh.Trimesh(verts, faces, process=True)
    mesh = keep_main_components(mesh, spec.min_component_frac)
    if mesh.volume < 0:
        mesh.invert()
    mc_faces = len(mesh.faces)
    if spec.taubin_iters > 0:
        trimesh.smoothing.filter_taubin(mesh, lamb=0.5, nu=0.53, iterations=spec.taubin_iters)
    mesh.vertices = project_to_surface(fn, np.asarray(mesh.vertices), iters=2, max_step=h)
    t2 = time.time()
    # decimate to budget
    v, f, decimator = decimate(np.asarray(mesh.vertices), np.asarray(mesh.faces), spec.budget)
    dm = trimesh.Trimesh(v, f, process=True)
    dm.remove_unreferenced_vertices()
    nondeg = dm.nondegenerate_faces(height=1e-7)
    dm.update_faces(nondeg)
    dm.remove_unreferenced_vertices()
    trimesh.repair.fix_winding(dm)
    if dm.volume < 0:
        dm.invert()
    # pull vertices back onto the analytic surface (small steps only)
    dm.vertices = project_to_surface(fn, np.asarray(dm.vertices), iters=2, max_step=h * 0.75)
    P = np.asarray(dm.vertices)
    F = np.asarray(dm.faces)
    t3 = time.time()
    # normals: analytic gradient, mesh normal fallback where they disagree
    g = gradient(fn, P, 2e-3)
    gn = g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-12)
    mn = np.asarray(dm.vertex_normals)
    agree = np.einsum("ij,ij->i", gn, mn)
    N = np.where((agree > 0.35)[:, None], gn, mn)
    N = N / np.linalg.norm(N, axis=1, keepdims=True)
    # colours
    fields = spec.field(P)
    rgb = spec.colorize(P, N, fields)
    if spec.ao_strength > 0:
        ao = sdf_ao(fn, P, N, spec.ao_scale, spec.ao_strength)
        ao = smooth_vertex_scalar(F, ao, iterations=4, alpha=0.6)
        rgb = rgb * (0.35 + 0.65 * ao)[:, None]
    rgb = np.clip(rgb, 0.0, 1.0)
    palette, cidx = quantize_palette(rgb)
    qcolors = palette[cidx, :3].astype(np.float64) / 255.0
    # centre on the bounding box
    bmin, bmax = P.min(axis=0), P.max(axis=0)
    center = (bmin + bmax) * 0.5
    Pc = P - center
    anchors = {k: vec(a) - center for k, a in spec.anchors.items()}
    hinge = None if spec.hinge is None else vec(spec.hinge) - center
    t4 = time.time()
    res_ = MeshResult(
        name=spec.name, vertices=Pc, normals=N, colors=qcolors, palette=palette, color_index=cidx, faces=F,
        size=bmax - bmin, center=center, anchors=anchors, hinge=hinge, description=spec.description,
        stats=dict(mc_faces=mc_faces, evals=n_eval, grid_h=h, t_grid=t1 - t0, t_mc=t2 - t1, t_dec=t3 - t2,
                   t_post=t4 - t3, watertight=bool(dm.is_watertight), palette=len(palette), decimator=decimator),
    )
    if verbose:
        s = res_.stats
        print(f"  {spec.name}: {len(F)} tris / {len(P)} verts (mc {mc_faces}), size {np.round(res_.size, 3)}, "
              f"palette {s['palette']}, watertight {s['watertight']}, grid {s['t_grid']:.1f}s mc {s['t_mc']:.1f}s "
              f"dec {s['t_dec']:.1f}s post {s['t_post']:.1f}s")
    return res_
