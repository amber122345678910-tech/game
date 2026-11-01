#!/usr/bin/env python3
"""selftest.py — regression test for the checkers themselves (run by tools/check.sh).

Runs apicheck.py and conventions.py on tools/checks/fixtures/*.luau. A fixture line ending in
`-- expect: rule[, rule...]` must produce exactly those findings; any other finding is a false positive.
Exit code 1 on any mismatch.
"""

from __future__ import annotations

import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(__file__))

import apicheck  # noqa: E402
import conventions  # noqa: E402
from report import Reporter, load  # noqa: E402

FIXTURES = "tools/checks/fixtures"


EXPECT = re.compile(r"--\s*expect:\s*([a-z][a-z\-]*(?:\s*,\s*[a-z][a-z\-]*)*)\s*$")


def expectations(path: str) -> set:
    _, lx = load(path)
    out = set()
    for cm in lx.comments:
        m = EXPECT.search(cm.text)
        if m:
            for rule in m.group(1).split(","):
                out.add((cm.line, rule.strip()))
    return out


def compare(name: str, path: str, rep: Reporter) -> int:
    expected = expectations(path)
    actual = {(line, rule) for (_, line, _, _, rule) in rep.findings}
    problems = 0
    for line, rule in sorted(expected - actual):
        print(f"selftest[{name}]: MISSED {path}:{line} [{rule}]")
        problems += 1
    for line, rule in sorted(actual - expected):
        msg = next(f[3] for f in rep.findings if f[1] == line and f[4] == rule)
        print(f"selftest[{name}]: FALSE POSITIVE {path}:{line} [{rule}] {msg}")
        problems += 1
    return problems


def main() -> int:
    problems = 0
    api = apicheck.Api(apicheck.DUMP)
    path = f"{FIXTURES}/api_cases.luau"
    rep = Reporter("apicheck")
    apicheck.FileChecker(api, path, rep).run()
    problems += compare("apicheck", path, rep)

    path = f"{FIXTURES}/conv_cases.luau"
    rep = Reporter("conventions")
    conventions.check_file(path, rep, [FIXTURES], set())
    problems += compare("conventions", path, rep)

    n_expected = len(expectations(f"{FIXTURES}/api_cases.luau")) + len(expectations(f"{FIXTURES}/conv_cases.luau"))
    if problems:
        print(f"selftest: 2 files, {problems} errors, 0 warnings  (checker regression!)")
        return 1
    print(f"selftest: 2 files, 0 errors, 0 warnings  ({n_expected} expected findings reproduced)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
