#!/usr/bin/env python3
"""Tests for the CX-002 public-test inventory tool."""

from __future__ import annotations

import csv
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
REPOSITORY_ROOT = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))

import inventory_public_tests as inventory  # noqa: E402


class InventoryPublicTestsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.registry = self.root / "docs" / "PUBLIC_TEST_TRANSFER.csv"
        self._write_candidates()
        self._write_registry()
        self.registry_before = self.registry.read_bytes()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def _write_file(self, relative_path: str, content: str = "synthetic\n") -> None:
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def _write_candidates(self) -> None:
        for path in (
            "tests/test_alpha.gd",
            "tests/test_group.gd",
            "tests/test_multi.gd",
            "tests/test_unclassified.gd",
            "tests/fixtures/direct.json",
            "tests/fixtures/nested/deep.json",
            "oracle/test_group.py",
            "oracle/test_unclassified.py",
            "scenarios/open.json",
        ):
            self._write_file(path)

        # These are outside the candidate path rules.
        self._write_file("oracle/helper.py")
        self._write_file("other/test_ignored.py")

    def _write_registry(self) -> None:
        self.registry.parent.mkdir(parents=True, exist_ok=True)
        rows = (
            ("tests/test_alpha.gd", "classified"),
            ("tests/test_group.gd; oracle/test_group.py", "classified"),
            ("tests/fixtures/**", "classified"),
            ("tests/test_multi.gd", "classified"),
            ("tests/test_multi.gd", "classified"),
            ("all remaining tests/** and oracle/test_*.py", "unclassified"),
        )
        with self.registry.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.writer(stream)
            writer.writerow(("artifact_or_pattern", "transfer_class"))
            writer.writerows(rows)

    def test_inventory_categories_and_expansion(self) -> None:
        report = inventory.build_inventory(self.root, self.registry)

        self.assertEqual(
            report["summary"],
            {
                "candidate_files": 9,
                "specifically_classified_files": 6,
                "unclassified_files": 3,
                "catch_all_only_files": 2,
                "outside_catch_all_files": 1,
                "multiply_matched_files": 1,
            },
        )
        self.assertEqual(
            report["unclassified_files"],
            [
                "oracle/test_unclassified.py",
                "scenarios/open.json",
                "tests/test_unclassified.gd",
            ],
        )
        self.assertEqual(
            report["catch_all_only_files"],
            ["oracle/test_unclassified.py", "tests/test_unclassified.gd"],
        )
        self.assertEqual(report["outside_catch_all_files"], ["scenarios/open.json"])
        alpha_entry = next(entry for entry in report["entries"] if entry["path"] == "tests/test_alpha.gd")
        self.assertEqual(alpha_entry["catch_all_matches"], [])
        self.assertEqual(
            [entry["path"] for entry in report["multiply_matched_files"]],
            ["tests/test_multi.gd"],
        )
        self.assertEqual(
            [match["row_number"] for match in report["multiply_matched_files"][0]["specific_matches"]],
            [5, 6],
        )

        fixture_row = next(
            row for row in report["specific_rows"] if row["artifact_or_pattern"] == "tests/fixtures/**"
        )
        self.assertEqual(
            fixture_row["expanded_files"],
            ["tests/fixtures/direct.json", "tests/fixtures/nested/deep.json"],
        )
        group_row = next(
            row
            for row in report["specific_rows"]
            if row["artifact_or_pattern"] == "tests/test_group.gd; oracle/test_group.py"
        )
        self.assertEqual(
            group_row["patterns"],
            ["tests/test_group.gd", "oracle/test_group.py"],
        )
        self.assertEqual(
            group_row["expanded_files"],
            ["oracle/test_group.py", "tests/test_group.gd"],
        )

        # Building and rendering are deterministic and never alter the registry.
        self.assertEqual(report, inventory.build_inventory(self.root, self.registry))
        self.assertEqual(self.registry.read_bytes(), self.registry_before)
        text = inventory.render_text(report)
        self.assertEqual(text, inventory.render_text(report))
        self.assertIn("Unclassified files (no specific row): 3", text)
        self.assertIn("scenarios/open.json [outside catch-all]", text)
        self.assertIn("tests/test_multi.gd [row 5, row 6]", text)

    def test_cli_json_and_text_modes(self) -> None:
        command = [
            sys.executable,
            str(TOOLS_DIR / "inventory_public_tests.py"),
            "--root",
            str(self.root),
            "--registry",
            str(self.registry),
        ]
        json_result = subprocess.run(
            command + ["--format", "json"],
            check=True,
            capture_output=True,
            text=True,
        )
        parsed = json.loads(json_result.stdout)
        self.assertEqual(parsed["summary"]["candidate_files"], 9)
        self.assertEqual(parsed["unclassified_files"], inventory.build_inventory(self.root, self.registry)["unclassified_files"])

        text_result = subprocess.run(
            command + ["--format", "text"],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertTrue(text_result.stdout.startswith("Public test transfer inventory\n"))
        self.assertIn("Multiply matched files: 1", text_result.stdout)
        self.assertEqual(self.registry.read_bytes(), self.registry_before)

    def test_rejects_patterns_that_escape_repository(self) -> None:
        with self.registry.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.writer(stream)
            writer.writerow(("artifact_or_pattern", "transfer_class"))
            writer.writerow(("../outside/**", "classified"))
        with self.assertRaisesRegex(inventory.InventoryError, "must stay within"):
            inventory.build_inventory(self.root, self.registry)


if __name__ == "__main__":
    unittest.main()
