#!/usr/bin/env python3
"""Build the SoulVerdict HD meshes (docs/HD_MESHES.md).

Usage (from the project root):
    python3 tools/meshgen/build.py                      # build + export all meshes, render previews
    python3 tools/meshgen/build.py SansSkullClassic     # just one (or several) mesh(es)
    python3 tools/meshgen/build.py --res 140 --no-export --preview-dir /tmp/x   # quick iteration
Options:
    --res N            grid resolution along the longest axis (default: per model, ~200)
    --no-export        skip src/shared/Meshes + assets/meshes outputs (JSON for previews is still written)
    --no-preview       skip PNG previews
    --preview-dir DIR  where previews go (default previews/dev)
    --views a,b,c      preview views (front, threequarter, side, back, top, low)
Outputs: src/shared/Meshes/<Name>.luau + init.luau, assets/meshes/<Name>.obj/.glb,
         tools/meshgen/out/<Name>.json, previews/dev/hd_*.png + hd_sheet.png
"""
from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import export  # noqa: E402
import mesher  # noqa: E402
from models import ORDER, registry  # noqa: E402

OUT_JSON = os.path.join(HERE, "out")
MESH_SRC = os.path.join(ROOT, "src", "shared", "Meshes")
ASSETS = os.path.join(ROOT, "assets", "meshes")
PREVIEW_DEFAULT = os.path.join(ROOT, "previews", "dev")
JAW_PREVIEW_OPEN = math.radians(28)


def jaw_matrix(skull_meta, jaw_meta, angle):
    """Row-major 4x4 placing the jaw (mesh-local) in skull-local space, opened by `angle` rad."""
    sh = np.array(skull_meta["anchors"]["JawHinge"])
    jh = np.array(jaw_meta["hinge"])
    c, s = math.cos(-angle), math.sin(-angle)
    R = np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    t = sh - R @ jh
    M = np.eye(4)
    M[:3, :3] = R
    M[:3, 3] = t
    return M.ravel().tolist()


def load_meta(name):
    with open(os.path.join(OUT_JSON, name + ".json")) as fh:
        j = json.load(fh)
    return {"anchors": j["anchors"], "hinge": j["hinge"], "size": j["size"], "tris": len(j["indices"]) // 3}


def preview_jobs(names, outdir, views):
    jobs = []
    have = {n for n in ORDER if os.path.exists(os.path.join(OUT_JSON, n + ".json"))}
    for n in names:
        meta = load_meta(n)
        if n.startswith("SansSkull"):
            for v in views:
                jobs.append({"out": os.path.join(outdir, f"hd_{n}_{v}.png"), "view": v, "label": n,
                             "meshes": [{"json": os.path.join(OUT_JSON, n + ".json")}]})
        elif n.startswith("BlasterSkull"):
            style = n[len("BlasterSkull"):]
            jn = "BlasterJaw" + style
            meshes = [{"json": os.path.join(OUT_JSON, n + ".json")}]
            sub = f"{meta['tris']} tris"
            if jn in have:
                jm = load_meta(jn)
                meshes.append({"json": os.path.join(OUT_JSON, jn + ".json"),
                               "matrix": jaw_matrix(meta, jm, JAW_PREVIEW_OPEN)})
                sub = f"skull {meta['tris']} + jaw {jm['tris']} tris (jaw open 28°)"
            for v in views:
                jobs.append({"out": os.path.join(outdir, f"hd_{n}_{v}.png"), "view": v, "label": n, "sub": sub,
                             "meshes": meshes})
        elif n.startswith("BlasterJaw"):
            jobs.append({"out": os.path.join(outdir, f"hd_{n}_threequarter.png"), "view": "threequarter",
                         "label": n, "meshes": [{"json": os.path.join(OUT_JSON, n + ".json")}]})
    return jobs


def run_previews(jobs, size=560):
    if not jobs:
        return
    spec = {"width": size, "height": size, "jobs": jobs}
    path = os.path.join(OUT_JSON, "_jobs.json")
    with open(path, "w") as fh:
        json.dump(spec, fh)
    subprocess.run(["node", os.path.join(HERE, "preview", "render.mjs"), path], check=True,
                   cwd=os.path.join(HERE, "preview"))


def contact_sheet(outdir, names, views):
    from PIL import Image, ImageDraw

    rows = []
    for n in names:
        if n.startswith("BlasterJaw"):
            continue
        row = [os.path.join(outdir, f"hd_{n}_{v}.png") for v in views]
        rows.append([p for p in row if os.path.exists(p)])
    jaws = [os.path.join(outdir, f"hd_{n}_threequarter.png") for n in names if n.startswith("BlasterJaw")]
    jaws = [p for p in jaws if os.path.exists(p)]
    if jaws:
        rows.append(jaws)
    rows = [r for r in rows if r]
    if not rows:
        return None
    tile = 300
    cols = max(len(r) for r in rows)
    sheet = Image.new("RGB", (cols * tile, len(rows) * tile + 34), (13, 15, 22))
    d = ImageDraw.Draw(sheet)
    d.text((10, 10), "UNDERTALE: SOUL VERDICT - HD mesh tier (tools/meshgen)", fill=(205, 214, 234))
    for r, row in enumerate(rows):
        for c, p in enumerate(row):
            im = Image.open(p).convert("RGB").resize((tile, tile), Image.LANCZOS)
            sheet.paste(im, (c * tile, 34 + r * tile))
    out = os.path.join(outdir, "hd_sheet.png")
    sheet.save(out, optimize=True)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--res", type=int, default=None)
    ap.add_argument("--no-export", action="store_true")
    ap.add_argument("--no-preview", action="store_true")
    ap.add_argument("--preview-dir", default=PREVIEW_DEFAULT)
    ap.add_argument("--views", default="front,threequarter,side")
    ap.add_argument("--size", type=int, default=560)
    args = ap.parse_args()

    reg = registry()
    names = args.names or list(ORDER)
    for n in names:
        if n not in reg:
            sys.exit(f"unknown mesh {n}; known: {', '.join(ORDER)}")
    for d in (OUT_JSON, args.preview_dir):
        export.ensure_dir(d)
    if not args.no_export:
        export.ensure_dir(MESH_SRC)
        export.ensure_dir(ASSETS)
    report = []
    t0 = time.time()
    for n in names:
        spec = reg[n]()
        m = mesher.build(spec, res=args.res)
        export.write_json(m, os.path.join(OUT_JSON, n + ".json"))
        if not args.no_export:
            src_bytes = export.write_luau(m, os.path.join(MESH_SRC, n + ".luau"))
            export.write_obj(m, os.path.join(ASSETS, n + ".obj"))
            export.write_glb(m, os.path.join(ASSETS, n + ".glb"))
            report.append((n, len(m.faces), len(m.vertices), src_bytes, np.round(m.size, 3).tolist()))
    if not args.no_export:
        export.write_index(list(ORDER), os.path.join(MESH_SRC, "init.luau"))
    print(f"built {len(names)} mesh(es) in {time.time() - t0:.1f}s")
    for n, t, v, b, s in report:
        print(f"  {n:22s} {t:6d} tris {v:6d} verts  {b / 1024:7.1f} KB luau  size {s}")
    if not args.no_preview:
        views = [v for v in args.views.split(",") if v]
        run_previews(preview_jobs(names, args.preview_dir, views), args.size)
        if args.preview_dir == PREVIEW_DEFAULT and set(names) == set(ORDER):
            print("sheet:", contact_sheet(args.preview_dir, list(ORDER), views))


if __name__ == "__main__":
    main()
