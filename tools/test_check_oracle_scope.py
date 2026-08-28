#!/usr/bin/env python3
"""Focused synthetic tests for check_oracle_scope.py."""

from __future__ import annotations

import csv
import io
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import check_oracle_scope as checker


NOT_REQUIRED = """# CX-019 — synthetic

PYTHON_ORACLE: NOT_REQUIRED
Reason: synthetic governance work has no oracle implementation.
"""
EXISTING = """# CX-019 — synthetic

PYTHON_ORACLE: EXISTING_HARNESS_ONLY
PYTHON_ORACLE_HARNESS: Existing O2 coverage must stay green; no broadening is authorized.
"""
REQUIRED = """# CX-019 — synthetic

PYTHON_ORACLE: REQUIRED
PYTHON_ORACLE_RETENTION_CRITERION: recovered exact arithmetic and ordering
PYTHON_ORACLE_SCOPE: oracle/kernel.py
PYTHON_ORACLE_INDEPENDENT_VALUE: independently checks evidence-grounded boundary vectors
"""


class OracleScopeValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        (self.root / "oracle").mkdir()
        (self.root / "docs" / "codex" / "tasks").mkdir(parents=True)
        (self.root / "oracle" / "kernel.py").write_text("VALUE = 1\n", encoding="utf-8")
        (self.root / "oracle" / "harness.py").write_text("VALUE = 1\n", encoding="utf-8")
        self.inventory = self.root / "docs" / "ORACLE_SCOPE.csv"
        self.task = self.root / "docs" / "codex" / "tasks" / "CX-019.md"
        self.task.write_text(NOT_REQUIRED, encoding="utf-8")
        self.write_inventory()

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def row(self, path: str, oracle_class: str) -> list[str]:
        return [
            path,
            oracle_class,
            "synthetic current role",
            "synthetic retained criterion",
            "no",
            "synthetic provenance note",
        ]

    def write_inventory(self, rows: list[list[str]] | None = None) -> None:
        if rows is None:
            rows = [self.row("oracle/kernel.py", "O1"), self.row("oracle/harness.py", "O2")]
        with self.inventory.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(checker.INVENTORY_HEADER)
            writer.writerows(rows)

    def run_validator(self, *extra: str) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        args = ["--root", str(self.root), "--inventory", str(self.inventory), *extra]
        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = checker.main(args)
        return result, stdout.getvalue(), stderr.getvalue()

    def init_git(self) -> str:
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "user.name", "Oracle Scope Test"], cwd=self.root, check=True)
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "base"], cwd=self.root, check=True)
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=self.root, check=True,
            text=True, capture_output=True
        ).stdout.strip()

    def test_valid_complete_inventory(self) -> None:
        result, stdout, stderr = self.run_validator()
        self.assertEqual(result, 0, stderr)
        self.assertIn("2 standing oracle module(s) classified", stdout)

    def test_missing_module_classification(self) -> None:
        self.write_inventory([self.row("oracle/kernel.py", "O1")])
        result, _stdout, stderr = self.run_validator()
        self.assertEqual(result, 1)
        self.assertIn("missing module classification: oracle/harness.py", stderr)

    def test_duplicate_inventory_row(self) -> None:
        row = self.row("oracle/kernel.py", "O1")
        self.write_inventory([row, row, self.row("oracle/harness.py", "O2")])
        result, _stdout, stderr = self.run_validator()
        self.assertEqual(result, 1)
        self.assertIn("duplicate path: oracle/kernel.py", stderr)

    def test_invalid_o_class(self) -> None:
        self.write_inventory([self.row("oracle/kernel.py", "O9"), self.row("oracle/harness.py", "O2")])
        result, _stdout, stderr = self.run_validator()
        self.assertEqual(result, 1)
        self.assertIn("invalid oracle_class 'O9'", stderr)

    def test_stale_path(self) -> None:
        self.write_inventory([
            self.row("oracle/kernel.py", "O1"), self.row("oracle/harness.py", "O2"),
            self.row("oracle/missing.py", "O3")
        ])
        result, _stdout, stderr = self.run_validator()
        self.assertEqual(result, 1)
        self.assertIn("stale or missing path: oracle/missing.py", stderr)

    def test_cx019_task_missing_declaration(self) -> None:
        self.task.write_text("# CX-019 — no declaration\n", encoding="utf-8")
        result, _stdout, stderr = self.run_validator()
        self.assertEqual(result, 1)
        self.assertIn("expected exactly one PYTHON_ORACLE declaration, found 0", stderr)

    def test_invalid_declaration_value(self) -> None:
        self.task.write_text("PYTHON_ORACLE: MAYBE\n", encoding="utf-8")
        result, _stdout, stderr = self.run_validator()
        self.assertEqual(result, 1)
        self.assertIn("invalid PYTHON_ORACLE value 'MAYBE'", stderr)

    def test_valid_not_required(self) -> None:
        self.task.write_text(NOT_REQUIRED, encoding="utf-8")
        result, _stdout, stderr = self.run_validator()
        self.assertEqual(result, 0, stderr)

    def test_valid_existing_harness_only(self) -> None:
        self.task.write_text(EXISTING, encoding="utf-8")
        result, _stdout, stderr = self.run_validator()
        self.assertEqual(result, 0, stderr)

    def test_valid_required_with_explicit_fields(self) -> None:
        self.task.write_text(REQUIRED, encoding="utf-8")
        result, _stdout, stderr = self.run_validator()
        self.assertEqual(result, 0, stderr)

    def test_diff_not_required_rejects_production_oracle_modification(self) -> None:
        base = self.init_git()
        (self.root / "oracle" / "kernel.py").write_text("VALUE = 2\n", encoding="utf-8")
        result, _stdout, stderr = self.run_validator("--base", base, "--task", str(self.task))
        self.assertEqual(result, 1)
        self.assertIn("NOT_REQUIRED forbids production oracle change: oracle/kernel.py", stderr)

    def test_diff_existing_harness_rejects_new_production_module(self) -> None:
        base = self.init_git()
        self.task.write_text(EXISTING, encoding="utf-8")
        (self.root / "oracle" / "new_module.py").write_text("VALUE = 1\n", encoding="utf-8")
        self.write_inventory([
            self.row("oracle/kernel.py", "O1"), self.row("oracle/harness.py", "O2"),
            self.row("oracle/new_module.py", "O2")
        ])
        result, _stdout, stderr = self.run_validator("--base", base, "--task", str(self.task))
        self.assertEqual(result, 1)
        self.assertIn("EXISTING_HARNESS_ONLY forbids new oracle module", stderr)

    def test_diff_existing_harness_allows_changed_existing_o2(self) -> None:
        base = self.init_git()
        self.task.write_text(EXISTING, encoding="utf-8")
        (self.root / "oracle" / "harness.py").write_text("VALUE = 2\n", encoding="utf-8")
        result, _stdout, stderr = self.run_validator("--base", base, "--task", str(self.task))
        self.assertEqual(result, 0, stderr)

    def test_diff_required_rejects_undeclared_expansion(self) -> None:
        base = self.init_git()
        self.task.write_text(REQUIRED, encoding="utf-8")
        (self.root / "oracle" / "harness.py").write_text("VALUE = 2\n", encoding="utf-8")
        result, _stdout, stderr = self.run_validator("--base", base, "--task", str(self.task))
        self.assertEqual(result, 1)
        self.assertIn("REQUIRED scope does not declare changed module: oracle/harness.py", stderr)

    def test_diff_required_allows_only_declared_scope(self) -> None:
        base = self.init_git()
        self.task.write_text(REQUIRED, encoding="utf-8")
        (self.root / "oracle" / "kernel.py").write_text("VALUE = 2\n", encoding="utf-8")
        result, _stdout, stderr = self.run_validator("--base", base, "--task", str(self.task))
        self.assertEqual(result, 0, stderr)

    def test_diff_oracle_test_only_change_is_not_expansion(self) -> None:
        (self.root / "oracle" / "test_kernel.py").write_text("def test_one(): pass\n", encoding="utf-8")
        base = self.init_git()
        (self.root / "oracle" / "test_kernel.py").write_text("def test_two(): pass\n", encoding="utf-8")
        result, _stdout, stderr = self.run_validator("--base", base, "--task", str(self.task))
        self.assertEqual(result, 0, stderr)


    def test_diff_existing_harness_rejects_same_diff_reclassification(self) -> None:
        (self.root / "oracle" / "identity.py").write_text("VALUE = 1\n", encoding="utf-8")
        self.write_inventory([
            self.row("oracle/kernel.py", "O1"),
            self.row("oracle/harness.py", "O2"),
            self.row("oracle/identity.py", "O3"),
        ])
        base = self.init_git()
        self.task.write_text(EXISTING, encoding="utf-8")
        (self.root / "oracle" / "identity.py").write_text("VALUE = 2\n", encoding="utf-8")
        self.write_inventory([
            self.row("oracle/kernel.py", "O1"),
            self.row("oracle/harness.py", "O2"),
            self.row("oracle/identity.py", "O2"),
        ])
        result, _stdout, stderr = self.run_validator("--base", base, "--task", str(self.task))
        self.assertEqual(result, 1)
        self.assertIn("EXISTING_HARNESS_ONLY forbids oracle inventory changes", stderr)

    def test_wrapped_reason_is_parsed_in_full(self) -> None:
        text = """# CX-019 — synthetic

PYTHON_ORACLE: NOT_REQUIRED
Reason: governance-only work must not add or broaden
oracle implementation behavior.
"""
        fields = checker._structured_fields(checker._without_fenced_blocks(text))
        self.assertEqual(
            fields["Reason"],
            ["governance-only work must not add or broaden oracle implementation behavior."],
        )
        self.task.write_text(text, encoding="utf-8")
        result, _stdout, stderr = self.run_validator()
        self.assertEqual(result, 0, stderr)

    def test_wrapped_required_scope_preserves_all_modules(self) -> None:
        base = self.init_git()
        text = """# CX-019 — synthetic

PYTHON_ORACLE: REQUIRED
PYTHON_ORACLE_RETENTION_CRITERION: recovered exact arithmetic and ordering
PYTHON_ORACLE_SCOPE: oracle/kernel.py,
oracle/harness.py
PYTHON_ORACLE_INDEPENDENT_VALUE: independently checks evidence-grounded boundary vectors
"""
        self.task.write_text(text, encoding="utf-8")
        (self.root / "oracle" / "kernel.py").write_text("VALUE = 2\n", encoding="utf-8")
        (self.root / "oracle" / "harness.py").write_text("VALUE = 2\n", encoding="utf-8")
        declaration, errors = checker.validate_task(self.task)
        self.assertEqual(errors, [])
        self.assertIsNotNone(declaration)
        assert declaration is not None
        self.assertEqual(
            declaration.scope,
            frozenset({"oracle/kernel.py", "oracle/harness.py"}),
        )
        result, _stdout, stderr = self.run_validator("--base", base, "--task", str(self.task))
        self.assertEqual(result, 0, stderr)

    def test_diff_ignores_file_mode_only_changes(self) -> None:
        base = self.init_git()
        self.task.write_text(NOT_REQUIRED, encoding="utf-8")
        target = self.root / "oracle" / "kernel.py"
        target.chmod(0o755)
        result, _stdout, stderr = self.run_validator("--base", base, "--task", str(self.task))
        self.assertEqual(result, 0, stderr)

if __name__ == "__main__":
    unittest.main()
