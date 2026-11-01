#!/usr/bin/env python3
"""contracts.py — cross-module consistency checks for src/** (docs/SPEC.md contracts).

  [require]        `local X = require(<path>)` is resolved through the Rojo tree (default.project.json mounts;
                   script / script.Parent chains, game:GetService / game.X, :WaitForChild / :FindFirstChild,
                   variables holding such paths). A path inside a mounted folder that has no module file is an
                   ERROR (the require would fail at runtime).
  [export]         uses `X.Name` / `X:Name` of a resolved module must be exported by it (`function M.Name`,
                   `M.Name =`, keys of the module table / returned table literal, `export type Name`). One level
                   deeper for table-literal exports (e.g. Config.Round.RoundTime). Modules with dynamic keys,
                   setmetatable or non-table returns are skipped. ERROR.
  [net]            every Net.Server.* / Net.Client.* call uses a remote name declared in Net.luau with the right
                   kind (On/Fire* -> Events/Unreliable, OnInvoke/Invoke -> Functions); Net.Server.* only in server
                   code, Net.Client.* only in client code. ERROR.
  [strings]        Strings.L("key") literals exist in the merged strings files (WARNING); every strings file is listed
                   in Strings/init.luau SOURCES (ERROR, it would never load); entries have en + ru (WARNING);
                   duplicate keys across files (WARNING).
  [clips]          kit data `Clip = "X"` and AnimController.Play/Stop(..., "X") / fx.Anim.Play(..., "X") literals exist
                   in Shared/Anim/Clips (family file + Clips/Kits/<KitId>.luau). WARNING while the clip files do
                   not exist, ERROR once they do. Family clip files must provide every clip SPEC §8 requires (ERROR).
  [icons]          every kit `Icon = "X"` and Kits.IconNames entry exists in src/client/UI/Icons.luau (WARNING).
  [service-shape]  modules in src/server/Services and src/client/Controllers export Init and Start (WARNING).
Usage: python3 tools/checks/contracts.py [--quiet-warnings] [--stats]
"""

from __future__ import annotations

import json
import os
import sys

sys.dont_write_bytecode = True  # keep tools/checks free of __pycache__
sys.path.insert(0, os.path.dirname(__file__))

from report import ROOT, Reporter, load, luau_files, main_wrapper  # noqa: E402
from luau_lex import closes_block, matching, opens_block, skip_type, split_args  # noqa: E402

REQUIRED_FAMILY_CLIPS = [
    "Idle", "Walk", "Run", "Jump", "Fall", "Land", "Dash", "Stunned", "Downed", "Block", "Parry", "Dodge", "Hit",
    "Death", "Victory", "Emote_Wave", "Emote_Shrug", "Emote_Sit", "Emote_Laugh",
    "Cast", "CastUp", "CastForward", "Summon", "Point", "Slam", "Throw", "Spin", "Leap", "Charge",
    "Slash1", "Slash2", "Slash3", "Slash4", "Punch1", "Punch2", "Punch3", "Punch4", "Kick1", "Kick2", "Kick3",
    "Shoot", "Reload", "Heal", "Guard", "Taunt",
]
SCRIPT_SUFFIXES = (".server.luau", ".client.luau", ".server.lua", ".client.lua", ".luau", ".lua")
NET_EVENT_FNS = {"On", "Fire", "FireAll", "FireExcept", "FireList"}
NET_FUNCTION_FNS = {"OnInvoke", "Invoke"}


# ---------------------------------------------------------------------------------------------------
# Rojo tree <-> files
# ---------------------------------------------------------------------------------------------------
class ModuleIndex:
    def __init__(self):
        with open(os.path.join(ROOT, "default.project.json"), encoding="utf-8") as f:
            project = json.load(f)
        self.mounts: list[tuple[tuple, str]] = []

        def walk(node, path):
            if isinstance(node, dict):
                if "$path" in node:
                    self.mounts.append((tuple(path), node["$path"].rstrip("/")))
                for k, v in node.items():
                    if not k.startswith("$"):
                        walk(v, path + [k])

        walk(project.get("tree", {}), [])
        self.by_inst: dict[tuple, str] = {}
        self.inst_of: dict[str, tuple] = {}
        self.folders: set[tuple] = set()
        for inst, d in self.mounts:
            base = os.path.join(ROOT, d)
            if not os.path.isdir(base):
                continue
            self.folders.add(inst)
            for dirpath, dirnames, _ in os.walk(base):
                dirnames[:] = [x for x in dirnames if not x.startswith(".")]
                relp = os.path.relpath(dirpath, base)
                if relp != ".":
                    self.folders.add(inst + tuple(relp.replace(os.sep, "/").split("/")))
            for file in luau_files(d):
                parts = file[len(d) + 1 :].split("/")
                name = parts[-1]
                for suf in SCRIPT_SUFFIXES:
                    if name.endswith(suf):
                        name = name[: -len(suf)]
                        break
                ip = inst + tuple(parts[:-1]) if name == "init" else inst + tuple(parts[:-1]) + (name,)
                self.by_inst[ip] = file
                self.inst_of[file] = ip

    def under_mount(self, ip: tuple) -> bool:
        return any(len(ip) > len(m) and ip[: len(m)] == m for m, _ in self.mounts)

    def file_for(self, ip: tuple):
        return self.by_inst.get(ip)


# ---------------------------------------------------------------------------------------------------
# Token helpers
# ---------------------------------------------------------------------------------------------------
def first_string_arg(toks, open_idx):
    args = split_args(toks, open_idx)
    if args and args[0][1] - args[0][0] == 1 and toks[args[0][0]].kind == "string":
        return toks[args[0][0]].value
    return None


def eval_path(toks, start, end, env, self_path):
    """Instance path (tuple) of a reference expression, or None."""
    if start >= end:
        return None
    t0 = toks[start]
    if t0.kind != "name":
        return None
    if t0.value == "script":
        path = self_path
    elif t0.value == "game":
        path = ()
    elif t0.value == "workspace":
        path = ("Workspace",)
    elif t0.value in env:
        path = env[t0.value]
    else:
        return None
    if path is None:
        return None
    i = start + 1
    while i < end:
        t = toks[i]
        if t.is_op("::"):
            break
        if t.is_op(".") and i + 1 < end and toks[i + 1].kind == "name":
            name = toks[i + 1].value
            if name == "Parent":
                if not path:
                    return None
                path = path[:-1]
            else:
                path = path + (name,)
            i += 2
        elif t.is_op(":") and i + 2 < end and toks[i + 1].kind == "name" and toks[i + 2].is_op("("):
            method = toks[i + 1].value
            arg = first_string_arg(toks, i + 2)
            close = matching(toks, i + 2)
            if method in ("WaitForChild", "FindFirstChild") and arg is not None:
                path = path + (arg,)
            elif method in ("GetService", "FindService") and path == () and arg is not None:
                path = (arg,)
            else:
                return None
            i = close + 1
        elif t.is_op("[") and i + 2 < end and toks[i + 1].kind == "string" and toks[i + 2].is_op("]"):
            path = path + (toks[i + 1].value,)
            i += 3
        else:
            return None
    return path


def expr_end(toks, start):
    """Index just past a simple expression starting at `start` (good enough for initialisers)."""
    n = len(toks)
    k = start
    prev_line = toks[start].line if start < n else 0
    ends_operand = False
    while k < n and toks[k].kind != "eof":
        t = toks[k]
        if t.kind == "op" and t.value in ("(", "[", "{"):
            if ends_operand and t.line != prev_line and t.value == "(":
                break
            k = matching(toks, k) + 1
            prev_line = toks[k - 1].line
            ends_operand = True
            continue
        if t.kind == "keyword":
            if t.value == "function":
                depth = 0
                while k < n:
                    if opens_block(toks[k]):
                        depth += 1
                    elif closes_block(toks[k]):
                        depth -= 1
                        if depth == 0:
                            break
                    k += 1
                k += 1
                ends_operand = True
                continue
            if t.value in ("and", "or", "not"):
                ends_operand = False
                k += 1
                continue
            if t.value in ("nil", "true", "false") and not ends_operand:
                ends_operand = True
                k += 1
                continue
            break
        if t.kind in ("name", "number", "string", "istring"):
            if ends_operand and (t.line != prev_line or t.kind == "name"):
                break
            if t.kind == "istring":
                while k < n and not toks[k].is_op("`end"):
                    k += 1
            ends_operand = True
            prev_line = toks[k].line
            k += 1
            continue
        if t.kind == "op":
            if t.value in (";", ",", ")", "]", "}", "=", "`end"):
                break
            if t.value == "::":
                k = skip_type(toks, k + 1)  # type assertion
                continue
            ends_operand = False
            prev_line = t.line
            k += 1
            continue
        k += 1
    return k


def table_literal_keys(toks, open_idx, depth=0):
    """Keys of a table constructor starting at toks[open_idx] == '{'.
    Returns (keys: dict name -> nested keys dict|None, closed: bool)."""
    close = matching(toks, open_idx)
    keys: dict = {}
    closed = True
    k = open_idx + 1
    while k < close:
        t = toks[k]
        entry_start = k
        # find the end of this entry
        d = 0
        e = k
        while e < close:
            te = toks[e]
            if te.kind == "op" and te.value in ("(", "[", "{"):
                e = matching(toks, e) + 1
                continue
            if te.kind == "keyword" and te.value == "function":
                bd = 0
                while e < close:
                    if opens_block(toks[e]):
                        bd += 1
                    elif closes_block(toks[e]):
                        bd -= 1
                        if bd == 0:
                            break
                    e += 1
                e += 1
                continue
            if te.kind == "op" and te.value in (",", ";") and d == 0:
                break
            e += 1
        # classify
        name = None
        value_idx = None
        if t.kind in ("name",) and entry_start + 1 < e and toks[entry_start + 1].is_op("="):
            name = t.value
            value_idx = entry_start + 2
        elif t.kind == "keyword" and entry_start + 1 < e and toks[entry_start + 1].is_op("="):
            name = t.value  # e.g. { end = 1 } is invalid Luau anyway
            value_idx = entry_start + 2
        elif t.is_op("["):
            kclose = matching(toks, entry_start)
            if kclose == entry_start + 2 and toks[entry_start + 1].kind == "string" and kclose + 1 < e and toks[kclose + 1].is_op("="):
                name = toks[entry_start + 1].value
                value_idx = kclose + 2
            elif kclose + 1 < e and toks[kclose + 1].is_op("="):
                if toks[entry_start + 1].kind != "number":
                    closed = False  # dynamic key
        if name is not None:
            nested = None
            if depth < 3 and value_idx is not None and value_idx < e and toks[value_idx].is_op("{") and matching(toks, value_idx) == e - 1:
                sub, sub_closed = table_literal_keys(toks, value_idx, depth + 1)
                nested = sub if sub_closed else None
            if name in keys and keys[name] is not None and nested is not None:
                keys[name] = {**keys[name], **nested}
            else:
                keys[name] = nested
        k = e + 1
    return keys, closed


class Exports:
    def __init__(self):
        self.open = False
        self.keys: dict = {}
        self.types: set = set()


def block_depths(toks):
    depths = []
    d = 0
    for t in toks:
        if closes_block(t):
            d -= 1
        depths.append(d)
        if opens_block(t):
            d += 1
    return depths


_exports_cache: dict[str, Exports] = {}


def module_exports(path: str) -> Exports:
    if path in _exports_cache:
        return _exports_cache[path]
    ex = Exports()
    _exports_cache[path] = ex
    _, lx = load(path)
    toks = lx.tokens
    n = len(toks)
    for k in range(n - 2):
        if toks[k].kind == "name" and toks[k].value == "export" and toks[k + 1].kind == "name" and toks[k + 1].value == "type":
            ex.types.add(toks[k + 2].value)
    depths = block_depths(toks)
    if depths and (depths[-1] != 0 or min(depths) < 0):
        ex.open = True  # block structure not understood (or invalid code: compile.luau reports it)
        return ex
    ret = None
    for k in range(n):
        if toks[k].is_kw("return") and depths[k] == 0:
            ret = k
    if ret is None:
        ex.open = True
        return ex
    r = ret + 1
    var = None
    if toks[r].is_op("{"):
        keys, closed = table_literal_keys(toks, r)
        ex.keys, ex.open = keys, not closed
        return ex
    if toks[r].kind == "name" and toks[r].value == "table" and toks[r + 1].is_op(".") and toks[r + 2].value == "freeze" and toks[r + 3].is_op("(") and toks[r + 4].kind == "name" and toks[r + 5].is_op(")"):
        var = toks[r + 4].value
    elif toks[r].kind == "name" and (toks[r + 1].kind == "eof" or toks[r + 1].is_op("::", ";") or toks[r + 1].line != toks[r].line):
        var = toks[r].value
    if var is None:
        ex.open = True
        return ex
    # declaration of the module table
    declared = False
    for k in range(n - 3):
        if toks[k].is_kw("local") and toks[k + 1].kind == "name" and toks[k + 1].value == var:
            j = k + 2
            if toks[j].is_op(":"):
                while j < n and not toks[j].is_op("="):
                    j += 1
            if toks[j].is_op("=") and toks[j + 1].is_op("{"):
                keys, closed = table_literal_keys(toks, j + 1)
                ex.keys.update(keys)
                if not closed:
                    ex.open = True
                declared = True
            else:
                ex.open = True
            break
    if not declared:
        ex.open = True
        return ex
    for k in range(n - 3):
        t = toks[k]
        if t.kind == "name" and t.value == "setmetatable" and toks[k + 1].is_op("(") and toks[k + 2].kind == "name" and toks[k + 2].value == var and toks[k + 3].is_op(","):
            ex.open = True
        if t.kind != "name" or t.value != var or (k > 0 and toks[k - 1].is_op(".", ":")):
            continue
        is_fn = k > 0 and toks[k - 1].is_kw("function")
        nxt = toks[k + 1]
        if nxt.is_op(".", ":") and toks[k + 2].kind == "name":
            key = toks[k + 2].value
            after = toks[k + 3] if k + 3 < n else toks[-1]
            if is_fn:
                if after.is_op(".") and toks[k + 4].kind == "name":
                    sub = ex.keys.setdefault(key, {})
                    if isinstance(sub, dict):
                        sub[toks[k + 4].value] = None
                else:
                    ex.keys.setdefault(key, None)
            elif after.is_op("="):
                if k + 4 < n and toks[k + 4].is_op("{") and expr_end(toks, k + 4) == matching(toks, k + 4) + 1:
                    sub, closed = table_literal_keys(toks, k + 4)
                    prev = ex.keys.get(key)
                    if key in ex.keys and prev is None:
                        pass  # already known as non-literal
                    elif closed:
                        ex.keys[key] = {**(prev or {}), **sub}
                    else:
                        ex.keys[key] = None
                else:
                    if key not in ex.keys or ex.keys[key] is not None:
                        ex.keys[key] = None
            elif after.is_op(".") and toks[k + 4].kind == "name" and toks[k + 5].is_op("=") if k + 5 < n else False:
                sub = ex.keys.get(key)
                if isinstance(sub, dict):
                    sub[toks[k + 4].value] = None
            elif after.is_op("[") and key in ex.keys:
                close = matching(toks, k + 3)
                if close + 1 < n and toks[close + 1].is_op("="):
                    ex.keys[key] = None
        elif nxt.is_op("["):
            close = matching(toks, k + 1)
            if close + 1 < n and toks[close + 1].is_op("="):
                if close == k + 3 and toks[k + 2].kind == "string":
                    ex.keys.setdefault(toks[k + 2].value, None)
                else:
                    ex.open = True
    return ex


def returned_string_list(path: str, field_name: str):
    """String items of `X.<field_name> = { "a", "b" }` or `local <field_name> = { ... }` in a file."""
    _, lx = load(path)
    toks = lx.tokens
    for k in range(len(toks) - 3):
        t = toks[k]
        if t.kind == "name" and t.value == field_name and toks[k + 1].is_op("=") and toks[k + 2].is_op("{"):
            close = matching(toks, k + 2)
            return [x.value for x in toks[k + 3 : close] if x.kind == "string"], t.line
    return None, 0


# ---------------------------------------------------------------------------------------------------
# Per-file require bindings
# ---------------------------------------------------------------------------------------------------
class FileInfo:
    def __init__(self, path, index: ModuleIndex):
        self.path = path
        _, self.lx = load(path)
        self.toks = self.lx.tokens
        self.self_path = index.inst_of.get(path)
        self.bindings: dict[str, tuple] = {}  # local name -> (module file, line)
        self.missing: list = []  # (line, instance path)
        self.declared_count: dict[str, int] = {}
        self.assign_count: dict[str, int] = {}
        self.lazy: set = set()
        env: dict[str, tuple] = {}
        toks = self.toks
        n = len(toks)
        brackets = []
        for k in range(n):
            t = toks[k]
            if t.kind == "op" and t.value in ("(", "[", "{"):
                brackets.append(t.value)
            elif t.kind == "op" and t.value in (")", "]", "}") and brackets:
                brackets.pop()
            if (
                t.kind == "name"
                and k + 1 < n
                and toks[k + 1].is_op("=")
                and not (k > 0 and toks[k - 1].is_op(".", ":", ","))
                and not (k > 0 and toks[k - 1].is_kw("local"))
                and (not brackets or brackets[-1] != "{")
            ):
                self.assign_count[t.value] = self.assign_count.get(t.value, 0) + 1
                v = k + 2
                # lazy require into a forward-declared local: `Name = require(path) :: any`
                if v + 1 < n and toks[v].kind == "name" and toks[v].value == "require" and toks[v + 1].is_op("("):
                    close = matching(toks, v + 1)
                    ip = eval_path(toks, v + 2, close, env, self.self_path) if self.self_path is not None else None
                    if ip is not None:
                        file = index.file_for(ip)
                        if file is not None:
                            self.bindings[t.value] = (file, t.line)
                            self.lazy.add(t.value)
                        elif index.under_mount(ip):
                            kind = "a Folder (no init.luau)" if ip in index.folders else "missing"
                            self.missing.append((t.line, ".".join(ip), kind))
            if t.is_kw("local") and toks[k + 1].kind == "name":
                name = toks[k + 1].value
                self.declared_count[name] = self.declared_count.get(name, 0) + 1
                j = k + 2
                if toks[j].is_op(":"):
                    bd = 0
                    while j < n:
                        if toks[j].is_op("(", "{", "[", "<"):
                            bd += 1
                        elif toks[j].is_op(")", "}", "]", ">"):
                            bd -= 1
                        elif bd == 0 and (toks[j].is_op("=", ",") or toks[j].kind == "keyword"):
                            break
                        j += 1
                if not toks[j].is_op("="):
                    continue
                v = j + 1
                if toks[v].kind == "name" and toks[v].value == "require" and toks[v + 1].is_op("("):
                    close = matching(toks, v + 1)
                    ip = eval_path(toks, v + 2, close, env, self.self_path) if self.self_path is not None else None
                    if ip is not None:
                        file = index.file_for(ip)
                        if file is not None:
                            self.bindings[name] = (file, t.line)
                        elif index.under_mount(ip):
                            kind = "a Folder (no init.luau)" if ip in index.folders else "missing"
                            self.missing.append((t.line, ".".join(ip), kind))
                else:
                    end = expr_end(toks, v)
                    ip = eval_path(toks, v, end, env, self.self_path) if self.self_path is not None else None
                    if ip is not None:
                        env[name] = ip
            elif t.is_kw("function"):
                # parameters shadow names
                j = k + 1
                while j < n and not toks[j].is_op("("):
                    j += 1
                close = matching(toks, j) if j < n else j
                for p in range(j + 1, close):
                    if toks[p].kind == "name" and toks[p - 1].is_op("(", ","):
                        self.declared_count[toks[p].value] = self.declared_count.get(toks[p].value, 0) + 1
            elif t.is_kw("for"):
                j = k + 1
                while j < n and not (toks[j].is_op("=") or toks[j].is_kw("in")):
                    if toks[j].kind == "name" and (j == k + 1 or toks[j - 1].is_op(",")):
                        self.declared_count[toks[j].value] = self.declared_count.get(toks[j].value, 0) + 1
                    j += 1

    def stable_bindings(self):
        """Bindings whose local is declared once and assigned only by the require (safe to check)."""
        for name, (file, line) in self.bindings.items():
            expected_assignments = 1 if name in self.lazy else 0
            if self.declared_count.get(name, 0) == 1 and self.assign_count.get(name, 0) == expected_assignments:
                yield name, file, line


# ---------------------------------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------------------------------
def module_label(index: ModuleIndex, file: str) -> str:
    ip = index.inst_of.get(file)
    return ip[-1] if ip else file


STATS = {"requires_resolved": 0, "member_uses_checked": 0}


def check_requires_and_exports(infos, index, rep):
    for info in infos:
        STATS["requires_resolved"] += len(info.bindings)
        for line, ip, kind in info.missing:
            rep.error(info.path, line, f"require target {ip} is {kind} in the Rojo tree", "require")
        toks = info.toks
        for name, file, _ in info.stable_bindings():
            ex = module_exports(file)
            if ex.open:
                continue
            label = module_label(index, file)
            for k in range(len(toks) - 2):
                t = toks[k]
                if t.kind != "name" or t.value != name or (k > 0 and toks[k - 1].is_op(".", ":")):
                    continue
                if not toks[k + 1].is_op(".", ":") or toks[k + 2].kind != "name":
                    continue
                if toks[k + 1].is_op(":") and not (toks[k + 3].is_op("(", "{") or toks[k + 3].kind == "string"):
                    continue  # `Name: type` field in a type/table definition, not a method call
                key = toks[k + 2].value
                STATS["member_uses_checked"] += 1
                if key not in ex.keys and key not in ex.types:
                    rep.error(info.path, toks[k + 2].line, f"{label} has no member '{key}' (not exported by {file})", "export")
                    continue
                nested = ex.keys.get(key)
                if isinstance(nested, dict) and nested and k + 4 < len(toks) and toks[k + 3].is_op(".", ":") and toks[k + 4].kind == "name":
                    sub = toks[k + 4].value
                    is_write = k + 5 < len(toks) and toks[k + 5].is_op("=")
                    if sub not in nested and not is_write:
                        rep.error(info.path, toks[k + 4].line, f"{label}.{key} has no member '{sub}'", "export")


def find_module(index, suffix_parts):
    for ip, file in index.by_inst.items():
        if ip[-len(suffix_parts) :] == tuple(suffix_parts):
            return file
    return None


def check_net(infos, index, rep):
    net_file = find_module(index, ["Shared", "Net"])
    if net_file is None:
        return
    lists = {}
    for field in ("Events", "Functions", "Unreliable"):
        items, _ = returned_string_list(net_file, field)
        lists[field] = set(items or [])
    for info in infos:
        side = "server" if info.path.startswith(("src/server/", "src/StarterCharacterScripts/")) and ".client." not in info.path else None
        if info.path.startswith("src/client/") or ".client." in info.path:
            side = "client"
        toks = info.toks
        for name, file, _ in info.stable_bindings():
            if file != net_file:
                continue
            for k in range(len(toks) - 6):
                t = toks[k]
                if t.kind != "name" or t.value != name or (k > 0 and toks[k - 1].is_op(".", ":")):
                    continue
                if not (toks[k + 1].is_op(".") and toks[k + 2].value in ("Server", "Client") and toks[k + 3].is_op(".") and toks[k + 4].kind == "name" and toks[k + 5].is_op("(")):
                    continue
                which, fn = toks[k + 2].value, toks[k + 4].value
                if which == "Server" and side == "client":
                    rep.error(info.path, t.line, f"Net.Server.{fn} used in client code", "net")
                if which == "Client" and side == "server":
                    rep.error(info.path, t.line, f"Net.Client.{fn} used in server code", "net")
                if fn not in NET_EVENT_FNS and fn not in NET_FUNCTION_FNS:
                    continue
                remote = first_string_arg(toks, k + 5)
                if remote is None:
                    continue
                if fn in NET_FUNCTION_FNS:
                    if remote not in lists["Functions"]:
                        known = remote in lists["Events"] or remote in lists["Unreliable"]
                        rep.error(info.path, t.line, f"Net.{which}.{fn}(\"{remote}\"): " + ("is an event, not a RemoteFunction" if known else "unknown remote (not in Net.Functions)"), "net")
                else:
                    if remote not in lists["Events"] and remote not in lists["Unreliable"]:
                        known = remote in lists["Functions"]
                        rep.error(info.path, t.line, f"Net.{which}.{fn}(\"{remote}\"): " + ("is a RemoteFunction, use Invoke/OnInvoke" if known else "unknown remote (not in Net.Events/Net.Unreliable)"), "net")


def check_strings(infos, index, rep):
    init = find_module(index, ["Shared", "Strings"])
    if init is None:
        return
    folder = os.path.dirname(init)
    sources, sources_line = returned_string_list(init, "SOURCES")
    merged: dict[str, str] = {}
    for file in luau_files(folder):
        if file == init:
            continue
        base = os.path.basename(file)
        mod_name = base[: -len(".luau")] if base.endswith(".luau") else base
        if sources is not None and mod_name not in sources:
            rep.error(file, 1, f"strings file {mod_name} is not listed in Strings/init.luau SOURCES (it will never load)", "strings")
        _, lx = load(file)
        toks = lx.tokens
        depths = block_depths(toks)
        ret = None
        for k, t in enumerate(toks):
            if t.is_kw("return") and depths[k] == 0:
                ret = k
        if ret is None or not toks[ret + 1].is_op("{"):
            continue
        keys, _ = table_literal_keys(toks, ret + 1)
        # entry lines: find ["key"] tokens
        line_of = {}
        for k in range(ret + 1, len(toks) - 2):
            if toks[k].is_op("[") and toks[k + 1].kind == "string" and toks[k + 2].is_op("]"):
                line_of.setdefault(toks[k + 1].value, toks[k + 1].line)
        for key, nested in keys.items():
            line = line_of.get(key, 1)
            if key in merged:
                rep.warn(file, line, f"duplicate strings key \"{key}\" (also in {merged[key]})", "strings")
            merged[key] = file
            if not isinstance(nested, dict) or "en" not in nested or "ru" not in nested:
                rep.warn(file, line, f"strings key \"{key}\" must have both en and ru", "strings")
    for info in infos:
        toks = info.toks
        for name, file, _ in info.stable_bindings():
            if file != init:
                continue
            for k in range(len(toks) - 4):
                t = toks[k]
                if t.kind == "name" and t.value == name and not (k > 0 and toks[k - 1].is_op(".", ":")) and toks[k + 1].is_op(".") and toks[k + 2].value == "L" and toks[k + 3].is_op("("):
                    key = first_string_arg(toks, k + 3)
                    if key is not None and key not in merged:
                        rep.warn(info.path, t.line, f"Strings.L(\"{key}\"): key not found in any strings file", "strings")


def clip_names(file):
    ex = module_exports(file)
    if ex.open:
        return None
    return set(ex.keys.keys())


def check_clips(infos, index, rep):
    clips_dir = os.path.join("src", "shared", "Anim", "Clips")
    have_dir = os.path.isdir(os.path.join(ROOT, clips_dir))
    family: dict[str, set | None] = {}
    kit_clips: dict[str, set | None] = {}
    if have_dir:
        for file in luau_files(clips_dir):
            parts = file.split("/")
            name = parts[-1][: -len(".luau")] if parts[-1].endswith(".luau") else parts[-1]
            names = clip_names(file)
            if len(parts) >= 2 and parts[-2] == "Kits":
                kit_clips[name] = names
            else:
                family[name] = names
                if name in ("Skeleton", "Human") and names is not None:
                    missing = [c for c in REQUIRED_FAMILY_CLIPS if c not in names]
                    if missing:
                        rep.error(file, 1, f"{name} clip set is missing SPEC §8 clips: {', '.join(missing)}", "clips")
    all_clips: set = set()
    unknown_sets = False
    for s in list(family.values()) + list(kit_clips.values()):
        if s is None:
            unknown_sets = True
        else:
            all_clips |= s
    unchecked = 0

    def verify(path, line, clip, valid: set | None, where: str):
        nonlocal unchecked
        if valid is None:
            unchecked += 1
            return
        if clip not in valid:
            rep.error(path, line, f"clip \"{clip}\" not found in {where}", "clips")

    # kit data
    for file in luau_files(os.path.join("src", "shared", "Kits")):
        if file.endswith("/init.luau"):
            continue
        _, lx = load(file)
        toks = lx.tokens
        kit_id = family_name = None
        refs = []
        for k in range(len(toks) - 2):
            t = toks[k]
            if t.kind == "name" and toks[k + 1].is_op("=") and toks[k + 2].kind == "string":
                if t.value == "Id" and kit_id is None:
                    kit_id = toks[k + 2].value
                elif t.value == "Family" and family_name is None:
                    family_name = toks[k + 2].value
                elif t.value == "Clip":
                    refs.append((toks[k + 2].line, toks[k + 2].value))
        fam = family.get(family_name or "")
        valid = None
        if fam is not None:
            valid = set(fam) | set(kit_clips.get(kit_id or "", None) or set())
        for line, clip in refs:
            verify(file, line, clip, valid, f"Anim/Clips/{family_name}.luau or Anim/Clips/Kits/{kit_id}.luau")
    # AnimController.Play / Stop literals
    for info in infos:
        toks = info.toks
        for k in range(2, len(toks) - 2):
            t = toks[k]
            if t.kind == "name" and t.value in ("Play", "Stop") and toks[k - 1].is_op(".") and toks[k - 2].kind == "name" and toks[k - 2].value in ("AnimController", "Anim") and toks[k + 1].is_op("("):
                args = split_args(toks, k + 1)
                if len(args) >= 2 and args[1][1] - args[1][0] == 1 and toks[args[1][0]].kind == "string":
                    clip_tok = toks[args[1][0]]
                    verify(info.path, clip_tok.line, clip_tok.value, None if (unknown_sets or not family) else all_clips, "any Anim/Clips file")
    if unchecked:
        reason = "Anim/Clips does not exist yet" if not family else "the family clip file is missing or not statically readable"
        rep.warn(clips_dir, 1, f"{unchecked} clip references unchecked: {reason}", "clips")


def check_icons(index, rep):
    icons_file = os.path.join("src", "client", "UI", "Icons.luau")
    if not os.path.isfile(os.path.join(ROOT, icons_file)):
        return
    _, lx = load(icons_file)
    toks = lx.tokens
    names = set()
    for k in range(len(toks) - 2):
        t = toks[k]
        if t.kind == "string":
            names.add(t.value)
        if t.is_op(".") and toks[k + 1].kind == "name" and toks[k + 2].is_op("="):
            names.add(toks[k + 1].value)
        if t.kind == "name" and toks[k + 1].is_op("=") and k > 0 and toks[k - 1].is_op("{", ",", ";"):
            names.add(t.value)
    refs = []
    for file in luau_files(os.path.join("src", "shared", "Kits")):
        _, klx = load(file)
        kt = klx.tokens
        for k in range(len(kt) - 2):
            if kt[k].kind == "name" and kt[k].value == "Icon" and kt[k + 1].is_op("=") and kt[k + 2].kind == "string":
                refs.append((file, kt[k + 2].line, kt[k + 2].value))
        if file.endswith("Kits/init.luau"):
            items, _ = returned_string_list(file, "IconNames")
            for k in range(len(kt) - 2):
                if kt[k].kind == "name" and kt[k].value == "IconNames" and kt[k + 1].is_op("=") and kt[k + 2].is_op("{"):
                    close = matching(kt, k + 2)
                    for x in kt[k + 3 : close]:
                        if x.kind == "string":
                            refs.append((file, x.line, x.value))
    for file, line, name in refs:
        if name not in names:
            rep.warn(file, line, f"icon \"{name}\" is not defined in {icons_file}", "icons")


def check_service_shape(rep):
    for folder in (os.path.join("src", "server", "Services"), os.path.join("src", "client", "Controllers")):
        if not os.path.isdir(os.path.join(ROOT, folder)):
            continue
        for file in luau_files(folder):
            if os.path.dirname(file) != folder.replace(os.sep, "/"):
                continue  # only direct children are services/controllers
            ex = module_exports(file)
            if ex.open:
                continue
            for fn in ("Init", "Start"):
                if fn not in ex.keys:
                    rep.warn(file, 1, f"service/controller module should export {fn}() (SPEC §7.1)", "service-shape")


def main() -> int:
    quiet = "--quiet-warnings" in sys.argv
    rep = Reporter("contracts")
    index = ModuleIndex()
    files = luau_files("src")
    infos = [FileInfo(f, index) for f in files]
    check_requires_and_exports(infos, index, rep)
    check_net(infos, index, rep)
    check_strings(infos, index, rep)
    check_clips(infos, index, rep)
    check_icons(index, rep)
    check_service_shape(rep)
    if "--stats" in sys.argv:
        print("contracts stats: " + ", ".join(f"{k}={v}" for k, v in STATS.items()))
    return rep.finish(len(files), quiet)


if __name__ == "__main__":
    main_wrapper(main)
