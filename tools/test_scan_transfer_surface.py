#!/usr/bin/env python3
"""Synthetic contract tests for scan_transfer_surface.py."""

from __future__ import annotations

import csv
import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import scan_transfer_surface as scanner


class TransferSurfaceScannerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.registry = self.root / "transfer.csv"

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def write_file(self, relative: str, text: str) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def write_registry(self, rows: list[tuple[str, str]]) -> None:
        with self.registry.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(("artifact", "transfer_class"))
            writer.writerows(rows)

    def write_config(self, value: object) -> Path:
        path = self.root / "scanner.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def run_scanner(self, *extra: str) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        argv = [
            "--root",
            str(self.root),
            "--registry",
            str(self.registry),
            *extra,
        ]
        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = scanner.main(argv)
        return result, stdout.getvalue(), stderr.getvalue()

    def test_detects_every_required_pattern_family_with_location(self) -> None:
        self.write_file(
            "core/candidate.gd",
            "ordinary 0x12 and deadbeef\n"
            "jump 004D0AC0 or 0x004D0AC1\n"
            "FUN_00401000 LAB_1 DAT_00402000 PTR_table\n"
            "FUN_ LAB_ DAT_ PTR_\n"
            "Ghidra decompiler-shaped\n"
            "undefined4 iVar1 puVar2 local_10 local_res8 auStack_20 "
            "param_1 extraout_EAX unaff_EBX\n",
        )
        self.write_registry([("core/candidate.gd", "T1_SANITIZE")])

        result, stdout, stderr = self.run_scanner()

        self.assertEqual(result, 0, stderr)
        self.assertEqual(stderr, "")
        self.assertIn("core/candidate.gd:2:", stdout)
        self.assertIn("executable_address: 004D0AC0", stdout)
        self.assertIn("executable_address: 0x004D0AC1", stdout)
        self.assertIn("ghidra_symbol: FUN_00401000", stdout)
        self.assertIn("ghidra_symbol: LAB_1", stdout)
        self.assertIn("ghidra_symbol: DAT_00402000", stdout)
        self.assertIn("ghidra_symbol: PTR_table", stdout)
        self.assertIn("ghidra_terminology: Ghidra", stdout)
        self.assertIn("ghidra_terminology: decompiler-shaped", stdout)
        self.assertIn("decompiler_identifier: undefined4", stdout)
        self.assertIn("decompiler_identifier: iVar1", stdout)
        self.assertIn("decompiler_identifier: local_res8", stdout)
        self.assertIn("decompiler_identifier: auStack_20", stdout)
        self.assertNotIn("core/candidate.gd:4:", stdout)
        self.assertNotIn("executable_address: 0x12", stdout)
        self.assertNotIn("executable_address: deadbeef", stdout)
        self.assertRegex(stdout, r"SUMMARY: 1 file\(s\); [1-9][0-9]* finding\(s\);")

    def test_skips_t3_paths_and_matches_bounded_root_and_relative_references(self) -> None:
        private_text = "004D0AC0 must not be scanned\n"
        private = self.write_file("docs/private.md", private_text)
        self.write_file(
            "core/candidate.gd",
            "root docs/private.md; relative ../docs/private.md\n"
            "not docs/private.md.bak and not xdocs/private.md and not private.md\n",
        )
        self.write_file(
            "docs/reader.md",
            "same directory ./private.md but basename private.md is not enough\n",
        )
        self.write_registry(
            [
                ("docs/private.md", "T3_RESEARCH_ONLY"),
                ("core/candidate.gd", "T0_RETAIN"),
                ("docs/reader.md", "T0_RETAIN"),
            ]
        )

        result, stdout, stderr = self.run_scanner()

        self.assertEqual(result, 0, stderr)
        self.assertIn("research_only_reference: docs/private.md", stdout)
        self.assertIn("research_only_reference: ../docs/private.md", stdout)
        self.assertIn("research_only_reference: ./private.md", stdout)
        self.assertEqual(stdout.count("research_only_reference"), 3)
        self.assertNotIn("docs/private.md.bak", stdout)
        self.assertNotIn("xdocs/private.md", stdout)
        self.assertNotIn("executable_address", stdout)
        self.assertEqual(private.read_text(encoding="utf-8"), private_text)

    def test_mixed_t3_path_is_scanned_with_file_level_notice(self) -> None:
        self.write_file("core/mixed.gd", "004D0AC0\n")
        self.write_file("core/ref.gd", "core/mixed.gd\n")
        self.write_registry(
            [
                ("core/mixed.gd", "T1_SANITIZE"),
                ("core/mixed.gd", "T3_RESEARCH_ONLY"),
                ("core/ref.gd", "T0_RETAIN"),
            ]
        )

        result, stdout, stderr = self.run_scanner()

        self.assertEqual(result, 0, stderr)
        self.assertIn(
            "mixed T3/non-T3 scopes in core/mixed.gd; "
            "findings are file-level review input",
            stdout,
        )
        self.assertIn("FINDING: core/mixed.gd:1:1: executable_address: 004D0AC0", stdout)
        self.assertNotIn("research_only_reference", stdout)
        self.assertIn("SUMMARY: 2 file(s); 1 finding(s)", stdout)

    def test_allowlist_requires_reason_and_can_report_suppressed_finding(self) -> None:
        self.write_file("core/candidate.gd", "synthetic vector 004D0AC0\n")
        self.write_registry([("core/candidate.gd", "T2_REIMPLEMENT")])
        config = self.write_config(
            {
                "allowlist": [
                    {
                        "path": "core/*.gd",
                        "pattern": "executable_address",
                        "line_regex": "synthetic vector",
                        "reason": "contract-owned synthetic scanner fixture",
                    }
                ]
            }
        )

        result, stdout, stderr = self.run_scanner(
            "--config", str(config), "--show-allowlisted"
        )

        self.assertEqual(result, 0, stderr)
        self.assertNotIn("FINDING:", stdout)
        self.assertIn("ALLOWLISTED:", stdout)
        self.assertIn("contract-owned synthetic scanner fixture", stdout)
        self.assertIn("0 finding(s); 1 allowlisted exception(s)", stdout)

        config.write_text(
            json.dumps(
                {
                    "allowlist": [
                        {
                            "path": "core/*.gd",
                            "pattern": "executable_address",
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        result, _stdout, stderr = self.run_scanner("--config", str(config))
        self.assertEqual(result, 2)
        self.assertIn("ERROR: allowlist[0]: reason must be a non-empty string", stderr)
        self.assertIn("configuration error(s)", stderr)

    def test_patterns_are_configurable_and_fail_on_findings_is_optional(self) -> None:
        self.write_file("core/z.gd", "CUSTOM-42\n")
        self.write_registry([("core/z.gd", "T0_RETAIN")])
        config = self.write_config(
            {
                "patterns": [
                    {"name": "custom_token", "regex": "CUSTOM-[0-9]+", "flags": []}
                ]
            }
        )

        result, stdout, stderr = self.run_scanner("--config", str(config))
        self.assertEqual(result, 0, stderr)
        self.assertIn("custom_token: CUSTOM-42", stdout)
        self.assertNotIn("executable_address", stdout)

        result, _stdout, stderr = self.run_scanner(
            "--config", str(config), "--fail-on-findings"
        )
        self.assertEqual(result, 1, stderr)

    def test_findings_are_deterministic_by_path_line_column_and_pattern(self) -> None:
        self.write_file("z.gd", "004D0AC2\n")
        self.write_file("a.gd", "004D0AC1 FUN_00401000\n")
        self.write_registry(
            [("z.gd", "T0_RETAIN"), ("a.gd", "T0_RETAIN")]
        )

        first = self.run_scanner()
        second = self.run_scanner()

        self.assertEqual(first, second)
        result, stdout, stderr = first
        self.assertEqual(result, 0, stderr)
        finding_lines = [line for line in stdout.splitlines() if line.startswith("FINDING:")]
        self.assertTrue(finding_lines[0].startswith("FINDING: a.gd:1:"))
        self.assertTrue(finding_lines[-1].startswith("FINDING: z.gd:1:"))

    def test_registry_and_scan_errors_are_not_findings(self) -> None:
        self.write_registry([("missing.gd", "T0_RETAIN")])

        result, stdout, stderr = self.run_scanner()

        self.assertEqual(result, 2)
        self.assertNotIn("FINDING:", stdout)
        self.assertIn("ERROR: ", stderr)
        self.assertIn("artifact path does not exist", stderr)
        self.assertIn("registry error(s)", stderr)

    def test_groups_paths_directories_globs_and_extensionless_files_expand(self) -> None:
        self.write_file("core/a.gd", "clean\n")
        self.write_file("core/b.gd", "clean\n")
        self.write_file("assets/data.txt", "clean\n")
        self.write_file("Makefile", "clean\n")
        self.write_registry(
            [
                ("core/*.gd", "T0_RETAIN"),
                ("core/a.gd; core/b.gd", "T1_SANITIZE"),
                ("assets", "T0_RETAIN"),
                ("Makefile", "T0_RETAIN"),
                ("descriptive aggregate", "T0_RETAIN"),
            ]
        )

        result, stdout, stderr = self.run_scanner()

        self.assertEqual(result, 0, stderr)
        self.assertIn("skipped non-resolving descriptive aggregate", stdout)
        self.assertIn("SUMMARY: 4 file(s); 0 finding(s)", stdout)

    def test_t3_glob_expands_to_concrete_reference_targets(self) -> None:
        self.write_file("private/a.md", "004D0AC0 is excluded\n")
        self.write_file("private/b.md", "004D0AC1 is excluded\n")
        self.write_file(
            "core/candidate.gd",
            "private/a.md and ../private/b.md but private/*.md is not a target\n",
        )
        self.write_registry(
            [
                ("private/*.md", "T3_RESEARCH_ONLY"),
                ("core/candidate.gd", "T0_RETAIN"),
            ]
        )

        result, stdout, stderr = self.run_scanner()

        self.assertEqual(result, 0, stderr)
        self.assertIn("research_only_reference: private/a.md", stdout)
        self.assertIn("research_only_reference: ../private/b.md", stdout)
        self.assertNotIn("research_only_reference: private/*.md", stdout)
        self.assertNotIn("executable_address", stdout)
        self.assertIn("SUMMARY: 1 file(s); 2 finding(s)", stdout)

    def test_default_registry_is_resolved_under_root(self) -> None:
        self.registry = self.root / "docs" / "PUBLIC_LINEAGE_TRANSFER.csv"
        self.registry.parent.mkdir(parents=True)
        self.write_file("candidate.gd", "004D0AC0\n")
        self.write_registry([("candidate.gd", "T0_RETAIN")])
        stdout = io.StringIO()
        stderr = io.StringIO()

        with redirect_stdout(stdout), redirect_stderr(stderr):
            result = scanner.main(["--root", str(self.root)])

        self.assertEqual(result, 0, stderr.getvalue())
        self.assertIn("FINDING: candidate.gd:1:1: executable_address", stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
