#!/usr/bin/env python3
"""Repository hygiene — governance rules that must be mechanically enforced.

DELIB-0002 accepted several rules about what may be committed. A rule recorded
only in a document is a rule that gets broken by an ordinary `git add -A`, and
this repository has already had exactly that happen: 59 raw `.var` files were
committed while `README.md` stated the project does not redistribute `.var`
content.

These checks turn the accepted rules into failures. They are deliberately about
the INDEX rather than the working tree — a locally generated pack or populated
bindings file is expected and fine; committing one is not.

Skips cleanly when git is unavailable or the checkout is not a repository.

Run:  python3 oracle/test_repository_hygiene.py
"""

from __future__ import annotations

import json
import os
import subprocess
import sys

FAILS: list = []

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


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


def tracked_files() -> list | None:
    """Paths in the git index, or None when git is unavailable."""
    try:
        proc = subprocess.run(["git", "ls-files"], cwd=ROOT,
                              capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    return [line for line in proc.stdout.splitlines() if line]


def test_no_populated_bindings_are_committed() -> None:
    """DELIB-0002: populated generated bindings are `T4_DELIBERATE`.

    A generated `bindings.json` embeds opcode-to-name mappings drawn from
    `ability_num.var`, so committing one is a redistribution question that has
    not been decided. `make_bindings.py` writes to stdout and the documented
    usage redirects into a TRACKED path, which is precisely how a populated file
    reaches the index by accident.
    """
    print("\n[1] committed bindings are unpopulated")
    files = tracked_files()
    if files is None:
        print("  SKIP  git is unavailable")
        return
    bindings = [f for f in files if f.endswith("bindings.json")]
    check(bindings, "bindings files are tracked at all", "%d found" % len(bindings))
    for rel in bindings:
        path = os.path.join(ROOT, rel)
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError) as exc:
            check(False, "%s parses as JSON" % rel, str(exc)[:60])
            continue
        bound = len(data.get("abilities", {}) or {})
        check(bound == 0,
              "%s is an unpopulated skeleton" % rel,
              "%d opcodes bound — regenerate locally, do not commit" % bound)


def test_no_original_var_content_is_committed() -> None:
    """`README.md` states the project does not redistribute `.var` content.

    The one permitted exception is `tests/fixtures/var/`, which holds
    hand-authored synthetic samples with invented names that exist to test the
    parser's dialect handling.
    """
    print("\n[2] no original .var content is committed")
    files = tracked_files()
    if files is None:
        print("  SKIP  git is unavailable")
        return
    allowed_prefix = "tests/fixtures/var/"
    offenders = [f for f in files
                 if f.endswith(".var") and not f.startswith(allowed_prefix)]
    check(not offenders,
          "the only committed .var files are the synthetic dialect fixtures",
          "offenders: %s" % ", ".join(offenders[:5]))

    synthetic = [f for f in files if f.startswith(allowed_prefix)
                 and f.endswith(".var")]
    check(synthetic, "and those fixtures are present",
          "%d files" % len(synthetic))


def test_no_extracted_pack_data_is_committed() -> None:
    """Pack data is generated from a local installation and is gitignored.

    Committing it would redistribute extracted tables wholesale, which is the
    systematic-reproduction edge the provenance policy exists to avoid.
    """
    print("\n[3] no extracted pack data is committed")
    files = tracked_files()
    if files is None:
        print("  SKIP  git is unavailable")
        return
    offenders = [f for f in files
                 if f.startswith("packs/") and "/data/" in f]
    check(not offenders, "packs/*/data is not tracked",
          "offenders: %s" % ", ".join(offenders[:5]))


def main() -> None:
    test_no_populated_bindings_are_committed()
    test_no_original_var_content_is_committed()
    test_no_extracted_pack_data_is_committed()
    print("\n%s" % ("ALL PASS" if not FAILS
                    else "%d FAILURES: %s" % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()
