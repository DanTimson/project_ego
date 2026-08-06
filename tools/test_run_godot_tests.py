#!/usr/bin/env python3
"""Focused tests for run_godot_tests.py."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("run_godot_tests.py")
SPEC = importlib.util.spec_from_file_location("run_godot_tests", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
RUNNER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = RUNNER
SPEC.loader.exec_module(RUNNER)


class StandaloneClassificationTests(unittest.TestCase):
    def test_accepts_scene_tree_and_main_loop_declarations(self) -> None:
        self.assertTrue(RUNNER.is_standalone_script("extends SceneTree\n"))
        self.assertTrue(
            RUNNER.is_standalone_script("  extends MainLoop # standalone\n")
        )

    def test_rejects_comments_placeholders_and_non_standalone_scripts(self) -> None:
        self.assertFalse(RUNNER.is_standalone_script("# extends SceneTree\n"))
        self.assertFalse(RUNNER.is_standalone_script(""))
        self.assertFalse(RUNNER.is_standalone_script("extends RefCounted\n"))

    def test_discovery_is_sorted_and_keeps_helpers_compile_only(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            tests = repository / "tests"
            tests.mkdir()
            (tests / "test_zeta.gd").write_text("extends MainLoop\n", encoding="utf-8")
            (tests / "test_helper.gd").write_text("", encoding="utf-8")
            (tests / "test_alpha.gd").write_text("extends SceneTree\n", encoding="utf-8")
            (tests / "other.gd").write_text("extends SceneTree\n", encoding="utf-8")

            runnable, compile_only = RUNNER.discover_standalone_scripts(repository)

            self.assertEqual([path.name for path in runnable], ["test_alpha.gd", "test_zeta.gd"])
            self.assertEqual([path.name for path in compile_only], ["test_helper.gd"])


class MarkerDetectionTests(unittest.TestCase):
    def test_detects_parser_compiler_and_script_errors(self) -> None:
        cases = (
            "SCRIPT ERROR: Parse Error: Could not find type X",
            "Compiler Error: Identifier not found",
            "SCRIPT ERROR: Invalid call. Nonexistent function.",
            'ERROR: Failed to load script "res://tests/test_x.gd" with error "Parse error".',
        )
        for output in cases:
            with self.subTest(output=output):
                self.assertTrue(RUNNER.find_error_markers("", output))

    def test_detects_explicit_failures_without_matching_benign_words(self) -> None:
        self.assertIn(
            "explicit test failure",
            RUNNER.find_error_markers("  FAIL  expected 2, got 3", ""),
        )
        self.assertIn(
            "explicit test failure",
            RUNNER.find_error_markers("2 FAILURES", ""),
        )
        self.assertEqual(RUNNER.find_error_markers("placing here fails cleanly", ""), [])
        self.assertEqual(RUNNER.find_error_markers("0 FAILURES", ""), [])

    def test_recognizes_only_the_existing_requires_pack_clean_skip(self) -> None:
        output = (
            "SKIP requires-pack: packs/genesis/data is absent; "
            "generate it with the extraction tools\n"
        )
        expected = Path("tests/test_scenario_requires_pack.gd")
        other = Path("tests/test_scenario.gd")

        self.assertTrue(RUNNER.is_requires_pack_skip(expected, output, ""))
        self.assertFalse(RUNNER.is_requires_pack_skip(other, output, ""))
        self.assertFalse(RUNNER.is_requires_pack_skip(expected, "SKIP for another reason", ""))


if __name__ == "__main__":
    unittest.main(verbosity=2)
