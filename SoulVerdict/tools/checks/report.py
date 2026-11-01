"""Shared helpers for the SoulVerdict python checks: file discovery, findings, summary, exit code.

Output format (one finding per line, sorted by file then line):
    path:line: error: message [rule]
    path:line: warning: message [rule]
Any finding can be silenced in the source with a comment on the same line (or alone on the line above):
    -- check:ignore            (all rules)
    -- check:ignore(rule-id)   (one or more comma-separated rule ids)
"""

from __future__ import annotations

import json
import os
import sys

from luau_lex import Lexed, lex, suppressed

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def rel(path: str) -> str:
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def luau_files(*roots: str) -> list[str]:
    """All .luau/.lua files under the given project-relative roots, sorted, project-relative paths."""
    out = []
    for root in roots:
        base = os.path.join(ROOT, root)
        if os.path.isfile(base):
            out.append(rel(base))
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
            for f in sorted(filenames):
                if f.endswith(".luau") or f.endswith(".lua"):
                    out.append(rel(os.path.join(dirpath, f)))
    return sorted(set(out))


_cache: dict[str, tuple[str, Lexed]] = {}


def load(path: str) -> tuple[str, Lexed]:
    """(source, lexed) for a project-relative path (cached)."""
    if path not in _cache:
        with open(os.path.join(ROOT, path), encoding="utf-8") as f:
            src = f.read()
        _cache[path] = (src, lex(src))
    return _cache[path]


def load_json(path: str):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return json.load(f)


class Reporter:
    def __init__(self, tool: str):
        self.tool = tool
        self.findings: list[tuple[str, int, str, str, str]] = []
        self._seen: set = set()

    def add(self, path: str, line: int, severity: str, message: str, rule: str) -> None:
        if path.endswith((".luau", ".lua")) and os.path.isfile(os.path.join(ROOT, path)):
            _, lexed = load(path)
            if suppressed(lexed, line, rule):
                return
        key = (path, line, severity, message, rule)
        if key in self._seen:
            return
        self._seen.add(key)
        self.findings.append(key)

    def error(self, path: str, line: int, message: str, rule: str) -> None:
        self.add(path, line, "error", message, rule)

    def warn(self, path: str, line: int, message: str, rule: str) -> None:
        self.add(path, line, "warning", message, rule)

    @property
    def errors(self) -> int:
        return sum(1 for f in self.findings if f[2] == "error")

    @property
    def warnings(self) -> int:
        return sum(1 for f in self.findings if f[2] == "warning")

    def finish(self, files_checked: int, quiet_warnings: bool = False) -> int:
        """Prints findings (errors first) + a summary line; returns the process exit code."""
        order = {"error": 0, "warning": 1}
        for path, line, sev, msg, rule in sorted(self.findings, key=lambda f: (order[f[2]], f[0], f[1])):
            if sev == "warning" and quiet_warnings:
                continue
            print(f"{path}:{line}: {sev}: {msg} [{rule}]")
        print(f"{self.tool}: {files_checked} files, {self.errors} errors, {self.warnings} warnings")
        return 1 if self.errors else 0


def main_wrapper(fn) -> None:
    try:
        sys.exit(fn())
    except BrokenPipeError:  # e.g. piped into head
        sys.exit(1)
