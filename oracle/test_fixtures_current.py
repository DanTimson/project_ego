#!/usr/bin/env python3
"""Committed fixtures must match what the generator produces right now.

The GDScript differential tests read `tests/fixtures/*.json`, which are generated
from the oracle. Nothing in `pytest oracle/` reads them, so an oracle change that
alters a fixture leaves the committed copy stale and the Python suite green — the
divergence only surfaces later, in Godot, as a port failure that is really an
out-of-date fixture.

That is not hypothetical: implementing R7's automatic side transition changed one
line of the skirmish log, and the full Python suite still passed.

This test closes the gap. It regenerates every fixture into a temporary directory
and compares byte for byte.

Run:  python3 oracle/test_fixtures_current.py
"""

from __future__ import annotations

import filecmp
import os
import shutil
import subprocess
import sys
import tempfile

FAILS: list = []

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMMITTED = os.path.join(ROOT, "tests", "fixtures")
GENERATOR = os.path.join(ROOT, "oracle", "make_fixtures.py")


def check(ok: bool, label: str, detail: str = "") -> None:
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label,
                          "  - %s" % detail if detail else ""))
    if not ok:
        FAILS.append(label)
        # Under pytest, raise: check() otherwise only RECORDS a failure, so
        # `pytest oracle/` would report green while assertions fail. The
        # standalone runner still collects every failure before exiting.
        if "PYTEST_CURRENT_TEST" in os.environ:
            raise AssertionError(label)


def test_fixtures_are_current() -> None:
    print("\n[1] committed fixtures match a fresh generation")
    tmp = tempfile.mkdtemp(prefix="ego_fixtures_")
    try:
        proc = subprocess.run([sys.executable, GENERATOR, tmp],
                              cwd=ROOT, capture_output=True, text=True)
        check(proc.returncode == 0, "the generator runs cleanly",
              (proc.stderr or "").strip().splitlines()[-1:] and
              (proc.stderr or "").strip().splitlines()[-1] or "")
        if proc.returncode != 0:
            return

        generated = sorted(f for f in os.listdir(tmp) if f.endswith(".json"))
        check(bool(generated), "the generator produced fixtures",
              "%d files" % len(generated))

        missing, stale = [], []
        for name in generated:
            committed = os.path.join(COMMITTED, name)
            if not os.path.exists(committed):
                missing.append(name)
            elif not filecmp.cmp(committed, os.path.join(tmp, name), shallow=False):
                stale.append(name)

        check(not missing,
              "every generated fixture is committed",
              "missing: %s — run `python3 oracle/make_fixtures.py tests/fixtures/` "
              "and `git add` them" % ", ".join(missing))
        check(not stale,
              "no committed fixture is stale",
              "stale: %s — regenerate with "
              "`python3 oracle/make_fixtures.py tests/fixtures/`" % ", ".join(stale))

        # An orphan is committed but no longer generated: usually a renamed
        # fixture whose old copy a GDScript test may still be reading.
        orphans = [f for f in sorted(os.listdir(COMMITTED))
                   if f.endswith(".json") and f not in generated]
        check(not orphans,
              "no committed fixture is orphaned by the generator",
              "orphans: %s" % ", ".join(orphans))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main() -> None:
    test_fixtures_are_current()
    print("\n%s" % ("ALL PASS" if not FAILS
                    else "%d FAILURES: %s" % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()
