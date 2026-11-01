#!/usr/bin/env python3
"""conventions.py — project coding rules (docs/AGENT_GUIDE.md "Coding rules", SPEC §0) for src/**.

Errors (exit 1):
  strict          first line of every .luau must be exactly `--!strict`
  banned-api      legacy / deprecated APIs: wait() spawn() delay() (+ Wait/Spawn/Delay), RenderStepped,
                  FindPartOnRay*, FindPartsInRegion3*, LoadAnimation, TweenPosition/TweenSize*,
                  Body* movers (BodyVelocity, BodyGyro, BodyPosition, BodyAngularVelocity, BodyForce,
                  BodyThrust), RocketPropulsion
  instance-parent Instance.new(class, parent) 2-argument form
  lune-safe       in Lune-safe roots: any use of game / workspace / plugin / RunService / TweenService /
                  UserInputService / ContextActionService
  lune-require    in Lune-safe roots: require(game...), require(workspace...), require("path"), require(assetId)
  max-lines       file longer than MAX_LINES
Warnings:
  header          line 2 should be a `--` comment describing the module
  determinism     Random.new / math.random in Lune-safe roots (use Shared/Util/Rng)
  tabs            indentation with spaces (first offending line per file)
  server-localplayer  Players.LocalPlayer used in src/server (always nil on the server)
Comments and string contents never match (a real Luau lexer is used). Silence a justified hit with
`-- check:ignore(rule)` on the line (or alone on the line above).
Usage: python3 tools/checks/conventions.py [--quiet-warnings] [paths...]
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from report import Reporter, load, load_json, luau_files, main_wrapper  # noqa: E402
from luau_lex import split_args  # noqa: E402

# ---------------------------------------------------------------------------------------------------
# CONFIG — edit here
# ---------------------------------------------------------------------------------------------------
SRC_ROOTS = ["src"]
MAX_LINES = 3000
# Lune-safe roots + runtime-only exceptions live in tools/checks/lune_safe.json (shared with the Lune
# require-all test). Today: everything under src/shared except Net.luau (SPEC §2.1).
LUNE_SAFE_CONFIG = "tools/checks/lune_safe.json"

# global functions that must be called through `task` (only when called as a bare global)
BANNED_GLOBAL_CALLS = {
    "wait": "use task.wait",
    "spawn": "use task.spawn",
    "delay": "use task.delay",
    "Wait": "use task.wait",
    "Spawn": "use task.spawn",
    "Delay": "use task.delay",
    "ypcall": "use pcall",
}
# member / identifier names that must not appear at all (as code tokens)
BANNED_NAMES = {
    "RenderStepped": "use RunService.PreRender or :BindToRenderStep",
    "FindPartOnRay": "use workspace:Raycast",
    "FindPartOnRayWithIgnoreList": "use workspace:Raycast with RaycastParams",
    "FindPartOnRayWithWhitelist": "use workspace:Raycast with RaycastParams",
    "FindPartsInRegion3": "use workspace:GetPartBoundsInBox",
    "FindPartsInRegion3WithIgnoreList": "use workspace:GetPartBoundsInBox",
    "FindPartsInRegion3WithWhiteList": "use workspace:GetPartBoundsInBox",
    "LoadAnimation": "animations are procedural (SPEC §8): no Animator/LoadAnimation",
    "TweenPosition": "use TweenService",
    "TweenSize": "use TweenService",
    "TweenSizeAndPosition": "use TweenService",
}
# legacy classes, flagged as identifiers or as string literals ("BodyVelocity")
BANNED_CLASSES = {
    "BodyVelocity": "use LinearVelocity",
    "BodyGyro": "use AlignOrientation",
    "BodyPosition": "use AlignPosition",
    "BodyAngularVelocity": "use AngularVelocity",
    "BodyForce": "use VectorForce",
    "BodyThrust": "use VectorForce",
    "RocketPropulsion": "use AlignPosition/LinearVelocity",
}
# identifiers that must not be used in Lune-safe modules (as bare names, not fields)
LUNE_UNSAFE_NAMES = {
    "game": "game / services are not available offline",
    "workspace": "no workspace in Lune-safe modules",
    "plugin": "plugin global is not available",
    "RunService": "no RunService in Lune-safe modules",
    "TweenService": "no TweenService in Lune-safe modules",
    "UserInputService": "no UserInputService in Lune-safe modules",
    "ContextActionService": "no ContextActionService in Lune-safe modules",
}
# per-file rule exemptions: { "src/path.luau": ["rule-id", ...] }
PER_FILE_ALLOW: dict[str, list[str]] = {}
# ---------------------------------------------------------------------------------------------------


def lune_safe_config():
    cfg = load_json(LUNE_SAFE_CONFIG)
    roots = [r.rstrip("/") for r in cfg.get("lune_safe_roots", [])]
    runtime_only = set(cfg.get("runtime_only", {}).keys())
    return roots, runtime_only


def is_lune_safe(path: str, roots, runtime_only) -> bool:
    if path in runtime_only:
        return False
    return any(path == r or path.startswith(r + "/") for r in roots)


def check_file(path: str, rep: Reporter, roots, runtime_only) -> None:
    allowed = set(PER_FILE_ALLOW.get(path, []))

    def err(line, msg, rule):
        if rule not in allowed:
            rep.error(path, line, msg, rule)

    def warn(line, msg, rule):
        if rule not in allowed:
            rep.warn(path, line, msg, rule)

    src, lx = load(path)
    lines = src.split("\n")
    first = lines[0].lstrip("﻿").rstrip() if lines else ""
    if first != "--!strict":
        err(1, f"first line must be `--!strict` (found {first[:40]!r})", "strict")
    # header comment (line 2, or line 3 after a blank line)
    rest = [ln.strip() for ln in lines[1:4] if ln.strip()]
    if not rest or not rest[0].startswith("--"):
        warn(2, "missing header comment (module purpose / public API) after --!strict", "header")
    if len(lines) > MAX_LINES:
        err(MAX_LINES + 1, f"file has {len(lines)} lines (max {MAX_LINES}); split it", "max-lines")

    # indentation with spaces (outside long strings/comments: use the stripped text)
    for i, ln in enumerate(lx.stripped_lines(), start=1):
        if ln.startswith(" ") and ln.strip() and not lx.ignore_lines.get(i):
            # skip continuation lines inside multi-line strings (blanked to '_') and comments (blank)
            warn(i, "indentation uses spaces; the project uses tabs", "tabs")
            break

    toks = lx.tokens
    local_names = set()
    for k, t in enumerate(toks):
        if t.is_kw("local") and k + 1 < len(toks):
            nxt = toks[k + 1]
            if nxt.is_kw("function") and k + 2 < len(toks):
                local_names.add(toks[k + 2].value)
            elif nxt.kind == "name":
                local_names.add(nxt.value)

    lune_safe = is_lune_safe(path, roots, runtime_only)
    is_server = path.startswith("src/server/")

    for k, t in enumerate(toks):
        prev = toks[k - 1] if k > 0 else None
        nxt = toks[k + 1] if k + 1 < len(toks) else None
        is_field = prev is not None and prev.is_op(".", ":")
        if t.kind == "name":
            v = t.value
            if v in BANNED_GLOBAL_CALLS and not is_field and nxt is not None and nxt.is_op("(") and v not in local_names:
                err(t.line, f"`{v}()` is banned: {BANNED_GLOBAL_CALLS[v]}", "banned-api")
            if v in BANNED_NAMES:
                err(t.line, f"`{v}` is banned: {BANNED_NAMES[v]}", "banned-api")
            if v in BANNED_CLASSES and not is_field:
                err(t.line, f"`{v}` is deprecated: {BANNED_CLASSES[v]}", "banned-api")
            if v == "Instance" and nxt is not None and nxt.is_op(".") and k + 3 < len(toks):
                if toks[k + 2].value == "new" and toks[k + 3].is_op("("):
                    args = split_args(toks, k + 3)
                    if len(args) >= 2:
                        err(t.line, "Instance.new(class, parent) is banned: configure the instance, set .Parent last", "instance-parent")
            if lune_safe and not is_field and v in LUNE_UNSAFE_NAMES:
                # allow `Types.X` style type names? these are values; field access is excluded above
                err(t.line, f"`{v}` in a Lune-safe module: {LUNE_UNSAFE_NAMES[v]} (SPEC §0.4)", "lune-safe")
            if lune_safe and v == "require" and not is_field and nxt is not None and nxt.is_op("("):
                # script.Parent... (or a variable holding such a reference) is fine; absolute paths,
                # string paths and asset ids are not.
                arg = toks[k + 2] if k + 2 < len(toks) else None
                if arg is not None and (arg.kind in ("string", "number") or (arg.kind == "name" and arg.value in ("game", "workspace"))):
                    err(t.line, "Lune-safe modules must require siblings via script.Parent... (SPEC §0.4)", "lune-require")
            if lune_safe and not is_field:
                if v == "Random" and nxt is not None and nxt.is_op(".") and k + 2 < len(toks) and toks[k + 2].value == "new":
                    warn(t.line, "Random.new in a Lune-safe module: use Shared/Util/Rng for cross-runtime determinism", "determinism")
                if v == "math" and nxt is not None and nxt.is_op(".") and k + 2 < len(toks) and toks[k + 2].value == "random":
                    warn(t.line, "math.random in a Lune-safe module: use Shared/Util/Rng for determinism", "determinism")
            if is_server and v == "LocalPlayer" and is_field:
                warn(t.line, "Players.LocalPlayer is nil on the server", "server-localplayer")
        elif t.kind == "string" and t.value in BANNED_CLASSES:
            err(t.line, f"\"{t.value}\" is deprecated: {BANNED_CLASSES[t.value]}", "banned-api")

    for line, msg in lx.errors:
        err(line, f"lexer: {msg}", "syntax")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    quiet = "--quiet-warnings" in sys.argv
    rep = Reporter("conventions")
    roots, runtime_only = lune_safe_config()
    for missing in sorted(p for p in runtime_only if not os.path.exists(os.path.join(os.path.dirname(__file__), "..", "..", p))):
        rep.warn(LUNE_SAFE_CONFIG, 1, f"runtime_only entry does not exist: {missing}", "config")
    files = luau_files(*(args or SRC_ROOTS))
    for path in files:
        check_file(path, rep, roots, runtime_only)
    return rep.finish(len(files), quiet)


if __name__ == "__main__":
    main_wrapper(main)
