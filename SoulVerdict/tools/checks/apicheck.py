#!/usr/bin/env python3
"""apicheck.py — Roblox API usage checker for src/** against the pinned API dump (.tools/API-Dump.json).

What it catches (rule ids in brackets):
  [instance-new]   Instance.new("X") with an unknown class, an abstract/NotCreatable class or a service;
                   deprecated classes are warnings
  [enum]           Enum.A.B with unknown enum A or item B; legacy item names / deprecated items (warning)
  [service]        game:GetService("X") / game:FindService("X") with a non-service; game.X that is neither a
                   DataModel member nor a service name (warning)
  [class-name]     :IsA / :FindFirstChildOfClass / :FindFirstChildWhichIsA / :FindFirstAncestorOfClass /
                   :FindFirstAncestorWhichIsA("X") with an unknown class name
  [member]         for variables whose class is known in the current scope
                     local p = Instance.new("Part") | game:GetService("Lighting") | x:FindFirstChildOfClass("C")
                     | x:Clone() of a known variable | workspace | workspace.CurrentCamera
                   - `p.Prop = v` where Prop is not a property/callback of the class (superclasses walked)
                   - `p:Method(` where Method is not a function of the class
                   - `p:GetPropertyChangedSignal("Prop")` with an unknown property
  [readonly]       writes to ReadOnly / NotScriptable properties, properties whose write security is not
                   None (e.g. Lighting.Technology) or that need a capability game scripts lack
                   (PluginOrOpenCloud / InternalTest, e.g. Lighting.LightingStyle, Model.LevelOfDetail);
                   calls of methods with non-None security (PluginSecurity, RobloxScriptSecurity...)
  [deprecated]     use of deprecated members on known classes (warning)
  [value-type]     `p.Prop = <literal>` whose literal type cannot fit the property (bool/number/string vs
                   Vector3/Color3/... ), an Enum item of the wrong enum, or a string that is not an item of
                   the property's enum
  [mistake]        common mistakes anywhere: .Colour, .BrickColour, .Visibility, .Transparancy, .Postion ...
                   lowercase deprecated methods (:remove() :clone() :destroy() :connect( :findFirstChild( ...)
                   Color3.new(255, ...) (needs 0..1), UDim2.new(a, b) with two numbers (warning),
                   CFrame.Angles(90, ...) with degree-looking literals (warning), Vector3.new with > 3 args
Unknown variable types are skipped (no type inference) to keep false positives low; reads like `x.Foo` are not
checked because they may be children. Silence a justified hit with `-- check:ignore(rule)`.
Usage: python3 tools/checks/apicheck.py [--quiet-warnings] [--stats] [paths...]      (default: src)
"""

from __future__ import annotations

import json
import os
import sys

sys.dont_write_bytecode = True  # keep tools/checks free of __pycache__
sys.path.insert(0, os.path.dirname(__file__))

from report import ROOT, Reporter, load, luau_files, main_wrapper  # noqa: E402
from luau_lex import closes_block, matching, opens_block, skip_type, split_args  # noqa: E402

DUMP = os.path.join(ROOT, ".tools", "API-Dump.json")
UNAVAILABLE_CAPABILITIES = {"PluginOrOpenCloud", "InternalTest"}
TYPED_DATATYPES = {
    "Vector3", "Vector2", "CFrame", "Color3", "UDim", "UDim2", "NumberRange", "NumberSequence",
    "ColorSequence", "Rect", "BrickColor", "Font", "PhysicalProperties", "Faces", "Axes", "Ray",
}
NUMBER_PRIMITIVES = {"float", "double", "int", "int64"}
CLASS_NAME_METHODS = {
    "IsA", "FindFirstChildOfClass", "FindFirstChildWhichIsA", "FindFirstAncestorOfClass",
    "FindFirstAncestorWhichIsA", "FindFirstDescendantOfClass",
}
TYPED_LOOKUP_METHODS = {"FindFirstChildOfClass", "FindFirstChildWhichIsA", "FindFirstAncestorOfClass", "FindFirstAncestorWhichIsA"}
TYPO_MEMBERS = {
    "Colour": "Color", "BrickColour": "BrickColor", "Visibility": "Visible", "Transparancy": "Transparency",
    "Transparecy": "Transparency", "Transparency_": "Transparency", "Postion": "Position", "Positon": "Position",
    "Posiiton": "Position", "Orientaion": "Orientation", "Rotaton": "Rotation", "Anchor": "Anchored",
    "CanCollision": "CanCollide", "Collidable": "CanCollide", "TextColor": "TextColor3",
    "BackgroundColor": "BackgroundColor3", "BorderColor": "BorderColor3", "ImageColor": "ImageColor3",
    "TextColour3": "TextColor3", "BackgroundColour3": "BackgroundColor3", "Lenght": "Length",
}
LOWERCASE_METHODS = {
    "remove": "Destroy", "clone": "Clone", "destroy": "Destroy", "connect": "Connect", "disconnect": "Disconnect",
    "findFirstChild": "FindFirstChild", "getChildren": "GetChildren", "children": "GetChildren", "isA": "IsA",
    "IsDescendantOf_": "IsDescendantOf", "waitForChild": "WaitForChild", "kick": "Kick", "getService": "GetService",
    "service": "GetService", "isDescendantOf": "IsDescendantOf", "getPlayers": "GetPlayers",
}
ANGLE_CONSTRUCTORS = {"Angles", "fromEulerAnglesXYZ", "fromEulerAnglesYXZ", "fromOrientation", "fromEulerAngles"}


def str_tags(tags) -> set:
    return {t for t in (tags or []) if isinstance(t, str)}


class Api:
    def __init__(self, path: str):
        with open(path, encoding="utf-8") as f:
            dump = json.load(f)
        self.classes = {}
        for c in dump["Classes"]:
            members = {}
            for m in c.get("Members", []):
                members.setdefault(m["Name"], m)
            self.classes[c["Name"]] = {
                "super": c.get("Superclass"),
                "tags": str_tags(c.get("Tags")),
                "members": members,
            }
        self.enums = {}
        for e in dump["Enums"]:
            items, legacy, deprecated = set(), {}, set()
            for it in e["Items"]:
                items.add(it["Name"])
                for ln in it.get("LegacyNames", []) or []:
                    legacy[ln] = it["Name"]
                if "Deprecated" in str_tags(it.get("Tags")):
                    deprecated.add(it["Name"])
            self.enums[e["Name"]] = {"items": items, "legacy": legacy, "deprecated": deprecated, "tags": str_tags(e.get("Tags"))}
        self.services = {n for n, c in self.classes.items() if "Service" in c["tags"]}
        self.all_member_names = {m for c in self.classes.values() for m in c["members"]}
        self._children: dict[str, list] = {}
        for name, c in self.classes.items():
            self._children.setdefault(c["super"], []).append(name)
        self._desc_members: dict[str, set] = {}

    def subclass_member_names(self, cls: str) -> set:
        """Member names defined by any class deriving from cls (cls itself included)."""
        if cls not in self._desc_members:
            out: set = set()
            stack = [cls]
            while stack:
                c = stack.pop()
                out |= set(self.classes.get(c, {}).get("members", {}))
                stack.extend(self._children.get(c, []))
            self._desc_members[cls] = out
        return self._desc_members[cls]

    def member(self, cls: str, name: str):
        seen = 0
        while cls and cls in self.classes and seen < 64:
            m = self.classes[cls]["members"].get(name)
            if m is not None:
                return m, cls
            cls = self.classes[cls]["super"]
            seen += 1
        return None, None

    def is_a(self, cls: str, base: str) -> bool:
        seen = 0
        while cls and cls in self.classes and seen < 64:
            if cls == base:
                return True
            cls = self.classes[cls]["super"]
            seen += 1
        return False


def write_problem(member) -> str | None:
    """Why a property cannot be written by a game script (None if it can)."""
    tags = str_tags(member.get("Tags"))
    if "ReadOnly" in tags:
        return "is read-only"
    if "NotScriptable" in tags:
        return "is NotScriptable (Studio/place-file only)"
    sec = member.get("Security")
    write_sec = sec.get("Write", "None") if isinstance(sec, dict) else (sec or "None")
    if write_sec != "None":
        return f"needs {write_sec} to write (not available to game scripts)"
    caps = member.get("Capabilities")
    if isinstance(caps, dict):
        missing = [c for c in caps.get("Write", []) or [] if c in UNAVAILABLE_CAPABILITIES]
        if missing:
            return f"needs capability {missing[0]} to write (plugins / Open Cloud only)"
    return None


class Scope:
    """Name -> stack of (depth, ClassInfo or None). ClassInfo = (class name, exact: bool):
    exact = the runtime class is exactly that (Instance.new, GetService...); otherwise it is a declared /
    base class (type annotation, cast, IsA refinement, Class-typed property) and may be a subclass."""

    def __init__(self):
        self.vars: dict[str, list] = {"workspace": [(0, ("Workspace", True))], "game": [(0, ("DataModel", True))]}

    def bind(self, name: str, depth: int, cls):
        self.vars.setdefault(name, []).append((depth, cls))

    def get(self, name: str):
        stack = self.vars.get(name)
        return stack[-1][1] if stack else None

    def assign(self, name: str, depth: int, cls):
        stack = self.vars.get(name)
        if not stack:
            return
        bdepth, _ = stack[-1]
        # reassignment from a nested block: after the block the class is ambiguous -> unknown
        stack[-1] = (bdepth, cls if depth == bdepth else None)

    def pop_to(self, depth: int):
        for name, stack in self.vars.items():
            while stack and stack[-1][0] > depth:
                stack.pop()

    def pop_at(self, depth: int):
        for stack in self.vars.values():
            while stack and stack[-1][0] >= depth and depth > 0:
                stack.pop()


def number_value(tok):
    try:
        return float(tok.value.replace("_", ""), ) if not tok.value.lower().startswith(("0x", "0b")) else float(int(tok.value.replace("_", ""), 0))
    except ValueError:
        return None


STATS = {"tracked": 0, "writes": 0, "calls": 0, "enums": 0, "instance_new": 0}


class FileChecker:
    def __init__(self, api: Api, path: str, rep: Reporter):
        self.api, self.path, self.rep = api, path, rep
        _, self.lx = load(path)
        self.toks = self.lx.tokens
        # names declared as Luau types in this file shadow Roblox class names in annotations
        self.local_types = {
            self.toks[k + 1].value
            for k in range(len(self.toks) - 1)
            if self.toks[k].kind == "name" and self.toks[k].value == "type" and self.toks[k + 1].kind == "name"
        }

    def annotation_class(self, start: int, end: int):
        """Roblox class named by a simple type annotation toks[start:end] (`Part`, `Part?`), else None."""
        t = self.toks
        if end - start == 2 and t[start + 1].is_op("?"):
            end -= 1
        if end - start == 1 and t[start].kind == "name":
            name = t[start].value
            if name in self.api.classes and name not in self.local_types:
                return (name, False)
        return None

    def err(self, tok, msg, rule):
        self.rep.error(self.path, tok.line, msg, rule)

    def warn(self, tok, msg, rule):
        self.rep.warn(self.path, tok.line, msg, rule)

    # -- helpers -----------------------------------------------------------------------------------
    def tok(self, i):
        return self.toks[i] if 0 <= i < len(self.toks) else self.toks[-1]

    def is_field(self, i) -> bool:
        return i > 0 and self.toks[i - 1].is_op(".", ":")

    def string_arg(self, open_idx):
        """First argument of a call if it is a single string literal."""
        args = split_args(self.toks, open_idx)
        if args and args[0][1] - args[0][0] == 1 and self.toks[args[0][0]].kind == "string":
            return self.toks[args[0][0]].value, self.toks[args[0][0]]
        return None, None

    def check_class_name(self, name, tok, rule, creatable=False):
        api = self.api
        if name not in api.classes:
            self.err(tok, f"unknown class \"{name}\"", rule)
            return False
        tags = api.classes[name]["tags"]
        if creatable:
            if "Service" in tags:
                self.err(tok, f"\"{name}\" is a service: use game:GetService(\"{name}\")", rule)
                return False
            if "NotCreatable" in tags:
                self.err(tok, f"\"{name}\" is not creatable with Instance.new (abstract or engine-only)", rule)
                return False
        if "Deprecated" in tags:
            self.warn(tok, f"class \"{name}\" is deprecated", "deprecated")
        return True

    # -- expression class inference (for `local x = <expr>`) -------------------------------------------
    def expr_class(self, start, end, scope: Scope):
        """Class of the expression toks[start:end] if it is a recognised constructor/lookup, else None."""
        t = self.toks
        end = min(end, len(t) - 1)
        if end - start <= 0:
            return None
        # strip a trailing type assertion `:: T` (remember T if it is a Roblox class)
        cast = None
        for k in range(start, end):
            if t[k].is_op("::"):
                cast = self.annotation_class(k + 1, end)
                end = k
                break
        inner = self._expr_class(start, end, scope)
        if inner is not None and (inner[1] or cast is None):
            return inner  # an exact class beats a cast
        return cast if cast is not None else inner

    def _expr_class(self, start, end, scope: Scope):
        t = self.toks
        if end - start <= 0:
            return None
        a = t[start]
        # Instance.new("C")
        if a.kind == "name" and a.value == "Instance" and end - start >= 4 and t[start + 1].is_op(".") and t[start + 2].value == "new" and t[start + 3].is_op("("):
            close = matching(t, start + 3)
            if close == end - 1:
                name, _ = self.string_arg(start + 3)
                if name in self.api.classes:
                    return (name, True)
            return None
        if a.kind == "name" and not self.is_field(start):
            info = scope.get(a.value)
            k = start + 1
            # chain of `.Prop` / `:Method(...)`
            while k < end and info is not None:
                cls, exact = info
                if t[k].is_op(".") and k + 1 < end and t[k + 1].kind == "name":
                    member, _ = self.api.member(cls, t[k + 1].value)
                    if cls == "DataModel" and member is None and t[k + 1].value in self.api.services:
                        info = (t[k + 1].value, True)
                    elif member is not None and member.get("MemberType") == "Property" and (member.get("ValueType") or {}).get("Category") == "Class":
                        info = (member["ValueType"]["Name"], False)
                    else:
                        return None
                    k += 2
                elif t[k].is_op(":") and k + 2 < end and t[k + 1].kind == "name" and t[k + 2].is_op("("):
                    method = t[k + 1].value
                    close = matching(t, k + 2)
                    if method in ("GetService", "FindService") and cls == "DataModel":
                        name, _ = self.string_arg(k + 2)
                        info = (name, True) if name in self.api.services else None
                    elif method in TYPED_LOOKUP_METHODS:
                        name, _ = self.string_arg(k + 2)
                        # ...OfClass returns exactly that class, ...WhichIsA a subclass of it
                        info = (name, method.endswith("OfClass")) if name in self.api.classes else None
                    elif method == "Clone":
                        pass
                    else:
                        return None
                    k = close + 1
                else:
                    return None
            return info if k == end else None
        return None

    def missing_member_is_error(self, info, name: str) -> bool:
        """A member missing on a DECLARED class may exist on a refined subclass (IsA guards Luau understands)."""
        cls, exact = info
        return exact or name not in self.api.subclass_member_names(cls)

    def refine_condition(self, if_idx: int, depth: int, scope: Scope) -> None:
        """`if x:IsA("C") [and ...] then` -> x is a C inside the branch (unknown if the test uses or/not)."""
        t = self.toks
        k = if_idx + 1
        while k < len(t) and not (t[k].is_kw("then") and not t[k].expr):
            k += 1
        cond = range(if_idx + 1, k)
        negated = any(t[c].is_kw("or", "not") for c in cond)
        for c in cond:
            if t[c].kind == "name" and not self.is_field(c) and t[c + 1].is_op(":") and t[c + 2].value == "IsA" and t[c + 3].is_op("("):
                name, _ = self.string_arg(c + 3)
                if name in self.api.classes and scope.get(t[c].value) is not None:
                    scope.bind(t[c].value, depth, None if negated else (name, False))

    # -- main pass ---------------------------------------------------------------------------------------
    def run(self):
        t = self.toks
        api = self.api
        scope = Scope()
        depth = 0
        brackets: list[str] = []  # stack of '(' '[' '{'
        pending_params: list[str] = []
        n = len(t)
        i = 0
        while i < n:
            tk = t[i]
            if tk.kind == "op":
                if tk.value in ("(", "[", "{"):
                    brackets.append(tk.value)
                elif tk.value in (")", "]", "}"):
                    if brackets:
                        brackets.pop()
            elif tk.kind == "keyword":
                v = tk.value
                if v == "function":
                    # params: function name.chain:method ( a, b, ... )
                    k = i + 1
                    while k < n and not t[k].is_op("("):
                        k += 1
                    close = matching(t, k) if k < n else k
                    depth += 1
                    for a, b in split_args(t, k) if k < n else []:
                        if t[a].kind != "name":
                            continue
                        pcls = None
                        if b - a >= 3 and t[a + 1].is_op(":"):
                            pcls = self.annotation_class(a + 2, b)
                        scope.bind(t[a].value, depth, pcls)
                    i = close + 1
                    continue
                if tk.expr:
                    pass  # if-expression keywords do not open/close blocks
                elif v in ("if", "do", "repeat"):
                    depth += 1
                    for p in pending_params:
                        scope.bind(p, depth, None)
                    pending_params = []
                    if v == "if":
                        self.refine_condition(i, depth, scope)
                elif v in ("end", "until"):
                    depth = max(depth - 1, 0)
                    scope.pop_to(depth)
                elif v in ("elseif", "else"):
                    scope.pop_at(depth)  # bindings made in the previous branch end here
                    if v == "elseif":
                        self.refine_condition(i, depth, scope)
                elif v == "for":
                    k = i + 1
                    while k < n and not (t[k].is_op("=") or t[k].is_kw("in")):
                        if t[k].kind == "name" and t[k - 1].is_op(",") or k == i + 1:
                            if t[k].kind == "name":
                                pending_params.append(t[k].value)
                        k += 1
                elif v == "local":
                    self.handle_local(i, depth, scope)
            elif tk.kind == "name":
                self.handle_name(i, depth, scope, brackets)
            elif tk.kind == "string":
                pass
            i += 1
        self.check_globals()

    def statement_end(self, start: int) -> int:
        """Index just past the expression starting at `start` (stops at a statement boundary)."""
        t = self.toks
        k = start
        n = len(t)
        last_line = t[start].line if start < n else 0
        expect_operand = True
        while k < n and t[k].kind != "eof":
            tk = t[k]
            if tk.kind == "op" and tk.value in ("(", "[", "{"):
                if not expect_operand and tk.line != last_line and tk.value == "(":
                    break  # ambiguous call across lines -> treat as a new statement
                close = matching(t, k)
                last_line = t[close].line
                k = close + 1
                expect_operand = False
                continue
            if tk.kind == "keyword" and tk.value == "function":
                # skip a function literal
                d, k2 = 0, k
                while k2 < n:
                    if opens_block(t[k2]):
                        d += 1
                    elif closes_block(t[k2]):
                        d -= 1
                        if d == 0:
                            break
                    k2 += 1
                k = k2 + 1
                expect_operand = False
                continue
            if expect_operand:
                if tk.kind in ("name", "number", "string") or tk.is_kw("nil", "true", "false", "not") or tk.kind == "istring" or tk.is_op("-", "#", "..."):
                    if tk.kind == "istring":
                        # skip to `end
                        while k < n and not t[k].is_op("`end"):
                            k += 1
                    expect_operand = tk.is_kw("not") or tk.is_op("-", "#")
                    last_line = t[k].line
                    k += 1
                    continue
                break
            # expecting an operator
            if tk.kind == "op" and tk.value in (".", ":", "..", "+", "-", "*", "/", "//", "%", "^", "==", "~=", "<", ">", "<=", ">=", "::"):
                if tk.value == "::":
                    k = skip_type(t, k + 1)  # type assertion
                    continue
                expect_operand = True
                last_line = tk.line
                k += 1
                continue
            if tk.is_kw("and", "or"):
                expect_operand = True
                k += 1
                continue
            break
        return min(k, n - 1)

    def handle_local(self, i, depth, scope: Scope):
        t = self.toks
        k = i + 1
        if t[k].is_kw("function"):
            if t[k + 1].kind == "name":
                scope.bind(t[k + 1].value, depth, None)
            return
        names = []
        ann_class = None
        while k < len(t) and t[k].kind == "name":
            names.append(t[k].value)
            k += 1
            if t[k].is_op(":"):  # type annotation
                k += 1
                ann_start = k
                bd = 0
                while k < len(t):
                    if t[k].is_op("(", "{", "[", "<"):
                        bd += 1
                    elif t[k].is_op(")", "}", "]", ">"):
                        bd -= 1
                    elif bd == 0 and (t[k].is_op(",", "=") or t[k].kind == "keyword"):
                        break
                    k += 1
                ann_class = self.annotation_class(ann_start, k)
            if t[k].is_op(","):
                k += 1
                continue
            break
        cls = None
        if len(names) == 1 and t[k].is_op("="):
            end = self.statement_end(k + 1)
            cls = self.expr_class(k + 1, end, scope) or ann_class
        if cls is not None and len(names) == 1:
            STATS["tracked"] += 1
        for nm in names:
            scope.bind(nm, depth, cls if len(names) == 1 else None)

    def handle_name(self, i, depth, scope: Scope, brackets):
        t = self.toks
        api = self.api
        tk = t[i]
        nxt = self.tok(i + 1)
        field = self.is_field(i)

        # --- global constructs (independent of scope) ---------------------------------------------
        if not field and tk.value == "Instance" and nxt.is_op(".") and self.tok(i + 2).value == "new" and self.tok(i + 3).is_op("("):
            name, stok = self.string_arg(i + 3)
            if name is not None:
                STATS["instance_new"] += 1
                self.check_class_name(name, stok, "instance-new", creatable=True)
        if not field and tk.value == "Enum" and nxt.is_op("."):
            self.check_enum(i)
        if field and t[i - 1].is_op(":") and nxt.is_op("(") and tk.value in CLASS_NAME_METHODS:
            name, stok = self.string_arg(i + 1)
            if name is not None:
                self.check_class_name(name, stok, "class-name")
        receiver_known = field and i >= 2 and t[i - 2].kind == "name" and not self.is_field(i - 2) and scope.get(t[i - 2].value) is not None
        if field and t[i - 1].is_op(".") and tk.value in TYPO_MEMBERS and tk.value not in api.all_member_names:
            self.err(tk, f".{tk.value} is not a Roblox member — did you mean .{TYPO_MEMBERS[tk.value]}?", "mistake")
        if not receiver_known:  # known receivers get the precise member/deprecation check below
            if field and t[i - 1].is_op(":") and tk.value in LOWERCASE_METHODS and nxt.is_op("("):
                self.warn(tk, f":{tk.value}() is a deprecated lowercase alias — use :{LOWERCASE_METHODS[tk.value]}()", "mistake")
            if field and t[i - 1].is_op(":") and tk.value == "Remove" and nxt.is_op("(") and self.tok(i + 2).is_op(")"):
                self.warn(tk, ":Remove() is deprecated — use :Destroy()", "deprecated")
        if not field and tk.value in ("Color3", "UDim2", "CFrame", "Vector3") and nxt.is_op(".") and self.tok(i + 3).is_op("("):
            self.check_constructor(i)

        # --- scope-aware member checks ------------------------------------------------------------
        if field:
            return
        name = tk.value
        cls = scope.get(name)
        # plain assignment `name = expr` (not inside a table constructor)
        if nxt.is_op("=") and (not brackets or brackets[-1] != "{"):
            prev = self.tok(i - 1)
            if not prev.is_op(",") and name in scope.vars:
                end = self.statement_end(i + 2)
                scope.assign(name, depth, self.expr_class(i + 2, end, scope))
            return
        if cls is None:
            return
        info = cls
        cls = info[0]
        if nxt.is_op(".") and self.tok(i + 2).kind == "name":
            prop_tok = self.tok(i + 2)
            after = self.tok(i + 3)
            member, owner = api.member(cls, prop_tok.value)
            is_write = after.is_op("=", "+=", "-=", "*=", "/=", "//=", "%=", "^=", "..=") and (not brackets or brackets[-1] != "{")
            if is_write:
                STATS["writes"] += 1
                if member is None and not self.missing_member_is_error(info, prop_tok.value):
                    return
                self.check_write(cls, prop_tok, member, owner, i + 4)
            elif member is not None and "Deprecated" in str_tags(member.get("Tags")):
                self.warn(prop_tok, f"{owner}.{prop_tok.value} is deprecated", "deprecated")
        elif nxt.is_op(":") and self.tok(i + 2).kind == "name" and self.tok(i + 3).is_op("(", "{") or (nxt.is_op(":") and self.tok(i + 3).kind == "string"):
            mtok = self.tok(i + 2)
            STATS["calls"] += 1
            member, owner = api.member(cls, mtok.value)
            if member is None:
                if self.missing_member_is_error(info, mtok.value):
                    self.err(mtok, f"{mtok.value} is not a valid method of {cls}", "member")
            elif member.get("MemberType") != "Function":
                kind = member.get("MemberType")
                self.err(mtok, f"{cls}.{mtok.value} is {'an' if kind == 'Event' else 'a'} {kind}, not a method (use '.')", "member")
            else:
                sec = member.get("Security") or "None"
                if isinstance(sec, dict):
                    sec = sec.get("Read", "None")
                if sec != "None":
                    self.err(mtok, f"{owner}:{mtok.value}() needs {sec} (not callable from game scripts)", "readonly")
                if "Deprecated" in str_tags(member.get("Tags")):
                    self.warn(mtok, f"{owner}:{mtok.value}() is deprecated", "deprecated")
                if mtok.value == "GetPropertyChangedSignal" and self.tok(i + 3).is_op("("):
                    pname, ptok = self.string_arg(i + 3)
                    if pname is not None:
                        pm, _ = api.member(cls, pname)
                        if (pm is None and self.missing_member_is_error(info, pname)) or (pm is not None and pm.get("MemberType") != "Property"):
                            self.err(ptok, f"GetPropertyChangedSignal: {cls} has no property \"{pname}\"", "member")

    def check_write(self, cls, prop_tok, member, owner, value_idx):
        api = self.api
        if member is None:
            self.err(prop_tok, f"{prop_tok.value} is not a valid member of {cls}", "member")
            return
        mt = member.get("MemberType")
        if mt == "Callback":
            return
        if mt != "Property":
            self.err(prop_tok, f"cannot assign to {owner}.{prop_tok.value} ({'an' if mt == 'Event' else 'a'} {mt})", "member")
            return
        problem = write_problem(member)
        if problem:
            self.err(prop_tok, f"{owner}.{prop_tok.value} {problem}", "readonly")
            return
        if "Deprecated" in str_tags(member.get("Tags")):
            self.warn(prop_tok, f"{owner}.{prop_tok.value} is deprecated", "deprecated")
        self.check_value(cls, prop_tok, member, value_idx)

    def check_value(self, cls, prop_tok, member, k):
        t = self.toks
        vt = member.get("ValueType") or {}
        cat, vname = vt.get("Category"), vt.get("Name")
        end = self.statement_end(k)
        span = end - k
        prop = f"{cls}.{prop_tok.value}"
        if span == 1:
            lit = t[k]
            kind = None
            if lit.kind == "number":
                kind = "number"
            elif lit.kind == "string":
                kind = "string"
            elif lit.is_kw("true", "false"):
                kind = "boolean"
            if kind is None:
                return
            ok = True
            if cat == "Primitive":
                if vname == "bool":
                    ok = kind == "boolean"
                elif vname in NUMBER_PRIMITIVES:
                    ok = kind == "number"
                elif vname == "string":
                    ok = kind in ("string", "number")
            elif cat == "Enum":
                if kind == "string":
                    enum = self.api.enums.get(vname)
                    if enum and lit.value not in enum["items"] and lit.value not in enum["legacy"]:
                        self.err(lit, f"{prop} expects Enum.{vname}: \"{lit.value}\" is not an item of it", "value-type")
                    return
                ok = kind == "number"
            elif cat == "DataType" and vname in TYPED_DATATYPES:
                ok = False
            elif cat == "Class":
                ok = False
            if not ok:
                expect = f"Enum.{vname}" if cat == "Enum" else vname
                self.err(lit, f"{prop} expects {expect}, got a {kind} literal", "value-type")
        elif span == 5 and t[k].value == "Enum" and t[k + 1].is_op(".") and t[k + 3].is_op("."):
            used = t[k + 2].value
            if cat == "Enum" and used != vname and used in self.api.enums:
                self.err(t[k + 2], f"{prop} expects Enum.{vname}, got Enum.{used}", "value-type")
            elif cat != "Enum" and cat is not None and used in self.api.enums:
                self.err(t[k + 2], f"{prop} expects {vname}, got an Enum.{used} item", "value-type")

    def check_enum(self, i):
        t = self.toks
        a = self.tok(i + 2)
        if a.kind != "name":
            return
        STATS["enums"] += 1
        enum = self.api.enums.get(a.value)
        if enum is None:
            if a.value not in ("GetEnums",):
                self.err(a, f"unknown enum Enum.{a.value}", "enum")
            return
        if "Deprecated" in enum["tags"]:
            self.warn(a, f"Enum.{a.value} is deprecated", "deprecated")
        if self.tok(i + 3).is_op(".") and self.tok(i + 4).kind == "name":
            b = self.tok(i + 4)
            if b.value in ("GetEnumItems", "FromName", "FromValue"):
                return
            if b.value in enum["items"]:
                if b.value in enum["deprecated"]:
                    self.warn(b, f"Enum.{a.value}.{b.value} is deprecated", "deprecated")
            elif b.value in enum["legacy"]:
                self.warn(b, f"Enum.{a.value}.{b.value} is a legacy name of Enum.{a.value}.{enum['legacy'][b.value]}", "deprecated")
            else:
                self.err(b, f"Enum.{a.value} has no item \"{b.value}\"", "enum")

    def check_constructor(self, i):
        t = self.toks
        ctor = self.tok(i + 2).value
        open_idx = i + 3
        args = split_args(t, open_idx)
        lits = []
        for a, b in args:
            if b - a == 1 and t[a].kind == "number":
                lits.append(number_value(t[a]))
            elif b - a == 2 and t[a].is_op("-") and t[a + 1].kind == "number":
                v = number_value(t[a + 1])
                lits.append(-v if v is not None else None)
            else:
                lits.append(None)
        head = t[i].value
        if head == "Color3" and ctor == "new":
            if any(v is not None and v > 1 for v in lits):
                self.err(t[i], "Color3.new takes components in 0..1 — use Color3.fromRGB for 0..255", "mistake")
        elif head == "UDim2" and ctor == "new" and len(args) == 2 and all(v is not None for v in lits):
            self.warn(t[i], "UDim2.new with two numbers is UDim2.new(xScale, xOffset, 0, 0)?? — use UDim2.fromScale / fromOffset", "mistake")
        elif head == "CFrame" and ctor in ANGLE_CONSTRUCTORS:
            if any(v is not None and abs(v) > 6.3 for v in lits):
                self.warn(t[i], f"CFrame.{ctor} takes RADIANS — wrap degrees in math.rad()", "mistake")
        elif head == "Vector3" and ctor == "new" and len(args) > 3:
            self.err(t[i], f"Vector3.new takes at most 3 arguments ({len(args)} given)", "mistake")

    def check_globals(self):
        """game:GetService("X") / game.X / workspace member reads."""
        t = self.toks
        api = self.api
        for i, tk in enumerate(t):
            if tk.kind != "name" or tk.value != "game" or self.is_field(i):
                continue
            nxt = self.tok(i + 1)
            if nxt.is_op(":") and self.tok(i + 2).value in ("GetService", "FindService") and self.tok(i + 3).is_op("("):
                name, stok = self.string_arg(i + 3)
                if name is not None and name not in api.services:
                    hint = " (it is a class, not a service)" if name in api.classes else ""
                    self.err(stok, f"\"{name}\" is not a service{hint}", "service")
            elif nxt.is_op(".") and self.tok(i + 2).kind == "name":
                member_name = self.tok(i + 2).value
                member, _ = api.member("DataModel", member_name)
                if member is None and member_name not in api.services:
                    self.warn(self.tok(i + 2), f"game.{member_name} is neither a DataModel member nor a service", "service")
                elif member is not None and "Deprecated" in str_tags(member.get("Tags")):
                    self.warn(self.tok(i + 2), f"game.{member_name} is deprecated", "deprecated")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    quiet = "--quiet-warnings" in sys.argv
    if not os.path.isfile(DUMP):
        print(f"apicheck: API dump not found at {DUMP}")
        return 2
    api = Api(DUMP)
    rep = Reporter("apicheck")
    files = luau_files(*(args or ["src"]))
    for path in files:
        FileChecker(api, path, rep).run()
    if "--stats" in sys.argv:
        print("apicheck stats: " + ", ".join(f"{k}={v}" for k, v in STATS.items()))
    return rep.finish(len(files), quiet)


if __name__ == "__main__":
    main_wrapper(main)
