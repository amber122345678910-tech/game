#!/usr/bin/env python3
"""Generate the selene Roblox standard library (roblox.yml at the project root) OFFLINE.

Why: `selene generate-roblox-std` downloads the API dump with its own bundled TLS roots, which the
sandbox egress proxy rejects ("invalid peer certificate: UnknownIssuer"). This script is a faithful
Python port of selene 0.31.0 `src/roblox/generate_std.rs`, fed with the pinned local dump
(`.tools/API-Dump.json`, Roblox 0.745 — the same file the rest of our tooling uses), so the result is
what `selene generate-roblox-std` would have produced for that API version.

Inputs:
  tools/checks/selene/roblox_base.yml   vendored verbatim from selene-lib 0.31.0 (MPL-2.0)
  .tools/API-Dump.json                  (or --dump PATH; the Full dump also works but adds internal members)
Output:
  roblox.yml (project root)             `base: luau`; selene.toml uses std = "sv" whose sv.yml has `base: roblox`

Usage (from the project root):  python3 tools/checks/gen_selene_std.py [--dump PATH] [--out PATH]
Re-run only when the API dump is updated. Requires PyYAML (python3 -c "import yaml").
"""

from __future__ import annotations

import argparse
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SELENE_VERSION = "0.31.0"
CUSTOM_METHOD_DATATYPES = {"CFrame", "UDim", "UDim2", "Vector2", "Vector3"}  # see selene api.rs has_custom_methods


def str_tags(tags) -> list[str]:
    """API dump tags may contain dicts (e.g. PreferredDescriptorName) — keep only plain string tags."""
    return [t for t in (tags or []) if isinstance(t, str)]


def is_default_security(security) -> bool:
    if not isinstance(security, dict):
        return security in (None, "None")
    return security.get("Read", "None") == "None" and security.get("Write", "None") == "None"


class Generator:
    def __init__(self, base: dict, api: dict):
        self.std = base
        self.std.setdefault("globals", {})
        self.std.setdefault("structs", {})
        self.api = api
        self.classes = {c["Name"]: c for c in api["Classes"]}

    # -- port of RobloxGenerator::write_class / write_class_struct / write_class_members ------------
    def write_class(self, global_name: str, class_name: str) -> None:
        self.write_class_struct(class_name)
        self.std["globals"][global_name] = {"struct": class_name}

    def write_class_struct(self, class_name: str) -> None:
        structs = self.std["structs"]
        if class_name in structs:
            return
        structs[class_name] = {}  # recursion guard (same as the Rust code)
        table = {"*": {"struct": "Instance"}}
        self.write_class_members(table, class_name)
        structs[class_name] = table

    def write_class_members(self, table: dict, class_name: str) -> None:
        cls = self.classes[class_name]
        for member in cls.get("Members", []):
            kind = member.get("MemberType")
            name = member.get("Name")
            tags = str_tags(member.get("Tags"))
            field = None
            if kind == "Callback":
                field = {"property": "override-fields"}
            elif kind == "Event":
                field = {"struct": "Event"}
            elif kind == "Function":
                field = {
                    "args": [{"required": False, "type": "any"} for _ in member.get("Parameters", [])],
                    "method": True,
                }
            elif kind == "Property":
                if is_default_security(member.get("Security")):
                    default_field = {"property": "read-only" if "ReadOnly" in tags else "override-fields"}
                    value_type = member.get("ValueType") or {}
                    category = value_type.get("Category")
                    if category == "Class":
                        self.write_class_struct(value_type["Name"])
                        field = {"struct": value_type["Name"]}
                    elif category == "DataType" and value_type.get("Name") in CUSTOM_METHOD_DATATYPES:
                        field = {"any": True}
                    else:
                        field = default_field
            else:
                continue
            if field is not None:
                if "Deprecated" in tags:
                    field["deprecated"] = {"message": "this property is deprecated.", "replace": []}
                table[name] = field
        superclass = cls.get("Superclass")
        if superclass and superclass != "<<<ROOT>>>":
            self.write_class_members(table, superclass)

    # -- write_enums ----------------------------------------------------------------------------------
    def write_enums(self) -> None:
        g = self.std["globals"]
        for enum in self.api["Enums"]:
            ename = enum["Name"]
            g[f"Enum.{ename}.GetEnumItems"] = {"args": [], "method": True, "must_use": True}
            g[f"Enum.{ename}.FromName"] = {
                "args": [{"required": False, "type": "string"}],
                "method": True,
                "must_use": True,
            }
            g[f"Enum.{ename}.FromValue"] = {
                "args": [{"required": False, "type": "number"}],
                "method": True,
                "must_use": True,
            }
            for item in enum["Items"]:
                g[f"Enum.{ename}.{item['Name']}"] = {"struct": "EnumItem"}
                for legacy in item.get("LegacyNames", []) or []:
                    g[f"Enum.{ename}.{legacy}"] = {
                        "struct": "EnumItem",
                        "deprecated": {
                            "message": f"Enum.{ename}.{legacy} was replaced with Enum.{ename}.{item['Name']}",
                            "replace": [f"Enum.{ename}.{item['Name']}"],
                        },
                    }

    # -- write_instance_new ---------------------------------------------------------------------------
    def write_instance_new(self) -> None:
        names = [c["Name"] for c in self.api["Classes"] if "NotCreatable" not in str_tags(c.get("Tags"))]
        self.std["globals"]["Instance.new"] = {
            "args": [
                {"type": names},
                {
                    "required": False,
                    "type": {"display": "Instance"},
                    "deprecated": {"message": "set the instance's parent separately", "replace": []},
                },
            ],
            "must_use": True,
        }

    # -- write_get_service ----------------------------------------------------------------------------
    def write_get_service(self) -> None:
        services = [c["Name"] for c in self.api["Classes"] if "Service" in str_tags(c.get("Tags"))]
        self.std["structs"]["DataModel"]["GetService"] = {
            "args": [{"type": services}],
            "method": True,
            "must_use": True,
        }

    # -- write_roblox_classes -------------------------------------------------------------------------
    def write_roblox_classes(self) -> None:
        out = {}
        for cls in self.api["Classes"]:
            events, props = [], []
            for m in cls.get("Members", []):
                if m.get("MemberType") == "Event":
                    events.append(m["Name"])
                elif m.get("MemberType") == "Property":
                    props.append(m["Name"])
            out[cls["Name"]] = {"superclass": cls["Superclass"], "events": events, "properties": props}
        self.std["roblox_classes"] = out

    def generate(self) -> dict:
        self.write_class("game", "DataModel")
        self.write_class("plugin", "Plugin")
        self.write_class("script", "Script")
        self.write_class("workspace", "Workspace")
        self.write_enums()
        self.write_instance_new()
        self.write_get_service()
        self.write_roblox_classes()
        self.std["last_selene_version"] = SELENE_VERSION
        return self.std


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dump", default=os.path.join(ROOT, ".tools", "API-Dump.json"))
    ap.add_argument("--base", default=os.path.join(ROOT, "tools", "checks", "selene", "roblox_base.yml"))
    ap.add_argument("--out", default=os.path.join(ROOT, "roblox.yml"))
    args = ap.parse_args()
    try:
        import yaml  # type: ignore
    except ImportError:
        print("gen_selene_std: PyYAML is required (pip install pyyaml)", file=sys.stderr)
        return 2
    if not os.path.isfile(args.dump):
        print(f"gen_selene_std: API dump not found: {args.dump}", file=sys.stderr)
        return 2
    with open(args.base, encoding="utf-8") as f:
        base = yaml.safe_load(f)
    with open(args.dump, encoding="utf-8") as f:
        api = json.load(f)
    std = Generator(base, api).generate()
    header = (
        "# @generated by tools/checks/gen_selene_std.py from "
        + os.path.relpath(args.dump, ROOT).replace(os.sep, "/")
        + " (port of `selene generate-roblox-std`, selene "
        + SELENE_VERSION
        + "). DO NOT EDIT — re-run the script.\n"
        "# Project-specific overrides (deprecated wait/spawn/delay, ...) live in sv.yml.\n"
    )
    text = yaml.safe_dump(std, sort_keys=True, default_flow_style=False, width=4096, allow_unicode=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(header)
        f.write("---\n")
        f.write(text)
    n_enums = len(api["Enums"])
    print(f"gen_selene_std: wrote {os.path.relpath(args.out, ROOT)} ({len(std['globals'])} globals, "
          f"{len(std['structs'])} structs, {n_enums} enums)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
