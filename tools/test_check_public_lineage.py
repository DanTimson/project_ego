#!/usr/bin/env python3
"""Synthetic tests for check_public_lineage.py."""

from __future__ import annotations

import csv
import io
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import check_public_lineage as checker


def lineage_row(artifact: str = "core/example.gd") -> list[str]:
    return [
        artifact,
        "Example.scope",
        "public basis",
        "N0_PUBLIC",
        "T0_RETAIN",
        "material",
        "public",
        "none",
        "none",
        "yes",
        "retain",
        "engine",
        "preliminary",
        "synthetic row",
    ]


def test_row(artifact: str = "tests/test_example.gd") -> list[str]:
    return [
        artifact,
        "example",
        "project architecture",
        "N0_PUBLIC",
        "T0_RETAIN",
        "retain",
        "ready_candidate",
        "synthetic row",
    ]


class PublicLineageValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        (self.root / "core").mkdir()
        (self.root / "tests" / "fixtures").mkdir(parents=True)
        (self.root / "core" / "example.gd").touch()
        (self.root / "tests" / "test_example.gd").touch()
        (self.root / "tests" / "fixtures" / "minimal.json").touch()
        self.lineage = self.root / "lineage.csv"
        self.tests = self.root / "tests.csv"

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def write_csv(self, path: Path, header: tuple[str, ...], rows: list[list[str]]) -> None:
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(header)
            writer.writerows(rows)

    def run_validator(self) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = checker.main(
                [
                    "--root",
                    str(self.root),
                    "--lineage",
                    str(self.lineage),
                    "--tests",
                    str(self.tests),
                ]
            )
        return result, stdout.getvalue(), stderr.getvalue()

    def write_valid_registries(self) -> None:
        self.write_csv(self.lineage, checker.LINEAGE_HEADER, [lineage_row()])
        self.write_csv(self.tests, checker.TEST_HEADER, [test_row()])

    def test_accepts_literal_group_glob_and_explicit_aggregate_forms(self) -> None:
        lineage_rows = [
            lineage_row(),
            lineage_row("core/example.gd; tests/test_example.gd"),
            lineage_row("tests/fixtures/**"),
            lineage_row("private evidence exports"),
        ]
        for index, row in enumerate(lineage_rows):
            row[1] = f"scope-{index}"
        self.write_csv(self.lineage, checker.LINEAGE_HEADER, lineage_rows)
        self.write_csv(self.tests, checker.TEST_HEADER, [test_row()])

        result, stdout, stderr = self.run_validator()

        self.assertEqual(result, 0, stderr)
        self.assertIn("literal=1, group=1, glob=1, aggregate=1", stdout)

    def test_unclassified_classes_are_notices_not_errors(self) -> None:
        self.write_valid_registries()
        rows = [test_row("all remaining tests/** and oracle/test_*.py")]
        rows[0][3] = "unclassified"
        rows[0][4] = "unclassified"
        self.write_csv(self.tests, checker.TEST_HEADER, rows)

        result, stdout, stderr = self.run_validator()

        self.assertEqual(result, 0, stderr)
        self.assertEqual(stdout.count("NOTICE:"), 2)
        self.assertIn("2 open classification notice(s)", stdout)

    def test_rejects_header_and_malformed_width(self) -> None:
        self.write_csv(self.lineage, ("wrong",), [["value"]])
        self.write_csv(self.tests, checker.TEST_HEADER, [test_row()[:-1]])

        result, _stdout, stderr = self.run_validator()

        self.assertEqual(result, 1)
        self.assertIn("header mismatch", stderr)
        self.assertIn("expected 8 columns, found 7", stderr)

    def test_rejects_duplicate_exact_artifact_scope_row(self) -> None:
        row = lineage_row()
        self.write_csv(self.lineage, checker.LINEAGE_HEADER, [row, row])
        self.write_csv(self.tests, checker.TEST_HEADER, [test_row()])

        result, _stdout, stderr = self.run_validator()

        self.assertEqual(result, 1)
        self.assertIn("duplicate artifact/scope row", stderr)

    def test_rejects_missing_literal_but_does_not_require_glob_match(self) -> None:
        self.write_csv(
            self.lineage,
            checker.LINEAGE_HEADER,
            [lineage_row("core/missing.gd"), lineage_row("optional/**/*.gd")],
        )
        self.write_csv(self.tests, checker.TEST_HEADER, [test_row()])

        result, _stdout, stderr = self.run_validator()

        self.assertEqual(result, 1)
        self.assertIn("literal path does not exist: core/missing.gd", stderr)
        self.assertNotIn("optional/**/*.gd", stderr)

    def test_rejects_unknown_classes_and_ambiguous_artifact_form(self) -> None:
        row = lineage_row("misspelled aggregate")
        row[3] = "N9_UNKNOWN"
        row[4] = "T0_RETAIN + T9_UNKNOWN"
        self.write_csv(self.lineage, checker.LINEAGE_HEADER, [row])
        self.write_csv(self.tests, checker.TEST_HEADER, [test_row()])

        result, _stdout, stderr = self.run_validator()

        self.assertEqual(result, 1)
        self.assertIn("artifact form is empty or not a recognized", stderr)
        self.assertIn("unknown necessity_class value 'N9_UNKNOWN'", stderr)
        self.assertIn("unknown transfer_class value 'T9_UNKNOWN'", stderr)


if __name__ == "__main__":
    unittest.main()
