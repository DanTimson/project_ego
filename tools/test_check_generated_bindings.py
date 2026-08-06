#!/usr/bin/env python3
"""Synthetic tests for check_generated_bindings.py."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("check_generated_bindings.py")
NOTE_TEMPLATE = (
    "Skeleton. Regenerate locally with tools/extract/make_bindings.py <var-dir> "
    "{pack_id}, then hand-edit the empty handlers. An empty 'abilities' map is "
    "a valid pack: every ability resolves as unbound and the load report counts "
    "it honestly."
)


def empty_skeleton(pack_id: str) -> dict[str, object]:
    return {
        "pack": pack_id,
        "note": NOTE_TEMPLATE.format(pack_id=pack_id),
        "summary": {"opcodes": 0, "bound": 0, "unbound": 0},
        "abilities": {},
    }


class GuardTests(unittest.TestCase):
    def make_repository(self, *pack_ids: str) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        repository = Path(temporary.name)
        for pack_id in pack_ids:
            (repository / "packs" / pack_id).mkdir(parents=True)
        return repository

    def write_json(self, repository: Path, pack_id: str, value: object) -> Path:
        path = repository / "packs" / pack_id / "bindings.json"
        path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
        return path

    def run_guard(self, repository: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(repository), *arguments],
            text=True,
            capture_output=True,
            check=False,
        )

    def test_accepts_exact_empty_skeleton(self) -> None:
        repository = self.make_repository("demo")
        self.write_json(repository, "demo", empty_skeleton("demo"))

        result = self.run_guard(repository)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("CHECK packs/demo/bindings.json: EMPTY", result.stdout)
        self.assertIn("RESULT: OK", result.stdout)

    def test_absent_binding_is_a_finding(self) -> None:
        repository = self.make_repository("demo")

        result = self.run_guard(repository)

        self.assertEqual(result.returncode, 1)
        self.assertIn("CHECK packs/demo/bindings.json: ABSENT", result.stdout)
        self.assertIn("RESULT: FINDINGS", result.stdout)

    def test_malformed_json_is_a_finding_and_is_not_overridden(self) -> None:
        repository = self.make_repository("demo")
        path = repository / "packs" / "demo" / "bindings.json"
        malformed = '{"abilities": '
        path.write_text(malformed, encoding="utf-8")

        regular = self.run_guard(repository)
        overridden = self.run_guard(repository, "--allow-populated")

        self.assertEqual(regular.returncode, 1)
        self.assertEqual(overridden.returncode, 1)
        self.assertIn("CHECK packs/demo/bindings.json: MALFORMED", regular.stdout)
        self.assertIn("CHECK packs/demo/bindings.json: MALFORMED", overridden.stdout)
        self.assertEqual(path.read_text(encoding="utf-8"), malformed)

    def test_populated_binding_fails_and_is_not_modified(self) -> None:
        repository = self.make_repository("demo")
        populated = empty_skeleton("demo")
        populated["summary"] = {"opcodes": 1, "bound": 1, "unbound": 0}
        populated["abilities"] = {"7": {"handler": "synthetic", "params": {}}}
        path = self.write_json(repository, "demo", populated)
        before = path.read_bytes()

        result = self.run_guard(repository)

        self.assertEqual(result.returncode, 1)
        self.assertIn("CHECK packs/demo/bindings.json: POPULATED", result.stdout)
        self.assertIn("RESULT: FINDINGS", result.stdout)
        self.assertEqual(path.read_bytes(), before)

    def test_override_allows_only_populated_and_still_reports_it(self) -> None:
        repository = self.make_repository("demo")
        populated = empty_skeleton("demo")
        populated["summary"] = {"opcodes": 1, "bound": 0, "unbound": 1}
        self.write_json(repository, "demo", populated)

        result = self.run_guard(repository, "--allow-populated")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("CHECK packs/demo/bindings.json: POPULATED", result.stdout)
        self.assertIn("RESULT: OK_WITH_POPULATED_OVERRIDE", result.stdout)

    def test_valid_json_with_wrong_shape_is_not_overridden(self) -> None:
        repository = self.make_repository("demo")
        self.write_json(repository, "demo", {"abilities": {}})

        result = self.run_guard(repository, "--allow-populated")

        self.assertEqual(result.returncode, 1)
        self.assertIn("CHECK packs/demo/bindings.json: INVALID_STRUCTURE", result.stdout)

    def test_all_pack_paths_are_reported_in_deterministic_order(self) -> None:
        repository = self.make_repository("zeta", "alpha")
        self.write_json(repository, "zeta", empty_skeleton("zeta"))
        self.write_json(repository, "alpha", empty_skeleton("alpha"))

        result = self.run_guard(repository)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        checks = [line for line in result.stdout.splitlines() if line.startswith("CHECK ")]
        self.assertEqual(
            checks,
            [
                "CHECK packs/alpha/bindings.json: EMPTY - accepted intentional empty skeleton",
                "CHECK packs/zeta/bindings.json: EMPTY - accepted intentional empty skeleton",
            ],
        )

    def test_missing_packs_directory_is_an_operational_error(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)

        regular = self.run_guard(Path(temporary.name))
        overridden = self.run_guard(Path(temporary.name), "--allow-populated")

        for result in (regular, overridden):
            self.assertEqual(result.returncode, 2)
            self.assertIn("ERROR: packs directory is absent", result.stdout)
            self.assertIn("RESULT: OPERATIONAL_ERROR", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
