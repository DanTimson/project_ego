#!/usr/bin/env python3
"""Inventory public-test transfer coverage without modifying the registry."""

from __future__ import annotations

import argparse
import csv
import glob
import json
import re
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

CATCH_ALL_PREFIX = "all remaining "


class InventoryError(ValueError):
    """Raised when the registry cannot be interpreted as a path inventory."""


def _relative_file_paths(base: Path, paths: Iterable[Path]) -> list[str]:
    return sorted(
        {
            path.relative_to(base).as_posix()
            for path in paths
            if path.is_file()
        }
    )


def discover_candidates(root: Path) -> list[str]:
    """Return test, oracle-test, scenario, and fixture candidate files."""
    paths: list[Path] = []
    tests = root / "tests"
    oracle = root / "oracle"
    scenarios = root / "scenarios"

    if tests.is_dir():
        paths.extend(tests.rglob("*"))
    if oracle.is_dir():
        paths.extend(oracle.glob("test_*.py"))
    if scenarios.is_dir():
        paths.extend(scenarios.rglob("*"))

    return _relative_file_paths(root, paths)


def _is_catch_all(artifact: str) -> bool:
    return artifact.casefold().startswith(CATCH_ALL_PREFIX)


def _patterns_for_artifact(artifact: str, catch_all: bool) -> list[str]:
    if catch_all:
        remainder = artifact[len(CATCH_ALL_PREFIX) :]
        patterns = re.split(r"\s+and\s+", remainder, flags=re.IGNORECASE)
    else:
        patterns = artifact.split(";")

    result = [pattern.strip() for pattern in patterns if pattern.strip()]
    if not result:
        raise InventoryError(f"artifact has no usable path patterns: {artifact!r}")
    return result


def _validate_relative_pattern(pattern: str) -> None:
    pure = PurePosixPath(pattern)
    if pure.is_absolute() or ".." in pure.parts:
        raise InventoryError(f"path pattern must stay within the repository: {pattern!r}")


def _expand_pattern(root: Path, pattern: str) -> list[str]:
    _validate_relative_pattern(pattern)
    if glob.has_magic(pattern):
        matches = (Path(match) for match in glob.glob(str(root / pattern), recursive=True))
    else:
        matches = iter((root / pattern,))
    return _relative_file_paths(root, matches)


def read_registry_rows(root: Path, registry: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Expand registry rows into specific rows and catch-all rows."""
    specific_rows: list[dict[str, Any]] = []
    catch_all_rows: list[dict[str, Any]] = []

    with registry.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames or "artifact_or_pattern" not in reader.fieldnames:
            raise InventoryError("registry is missing the artifact_or_pattern column")

        for row_number, row in enumerate(reader, start=2):
            artifact = (row.get("artifact_or_pattern") or "").strip()
            catch_all = _is_catch_all(artifact)
            patterns = _patterns_for_artifact(artifact, catch_all)
            expanded = sorted(
                {
                    path
                    for pattern in patterns
                    for path in _expand_pattern(root, pattern)
                }
            )
            expanded_row = {
                "row_number": row_number,
                "artifact_or_pattern": artifact,
                "patterns": patterns,
                "expanded_files": expanded,
            }
            if catch_all:
                catch_all_rows.append(expanded_row)
            else:
                specific_rows.append(expanded_row)

    return specific_rows, catch_all_rows


def _row_reference(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "row_number": row["row_number"],
        "artifact_or_pattern": row["artifact_or_pattern"],
    }


def build_inventory(root: Path, registry: Path) -> dict[str, Any]:
    """Build the deterministic inventory report."""
    root = root.resolve()
    registry = registry.resolve()
    candidates = discover_candidates(root)
    specific_rows, catch_all_rows = read_registry_rows(root, registry)

    entries: list[dict[str, Any]] = []
    for path in candidates:
        specific_matches = [
            _row_reference(row) for row in specific_rows if path in row["expanded_files"]
        ]
        # The catch-all applies only after specific rows have been considered.
        catch_all_matches = (
            []
            if specific_matches
            else [
                _row_reference(row)
                for row in catch_all_rows
                if path in row["expanded_files"]
            ]
        )
        if len(specific_matches) > 1:
            coverage = "multiple_specific"
        elif specific_matches:
            coverage = "specific"
        elif catch_all_matches:
            coverage = "catch_all_only"
        else:
            coverage = "unclassified"
        entries.append(
            {
                "path": path,
                "coverage": coverage,
                "specific_matches": specific_matches,
                "catch_all_matches": catch_all_matches,
            }
        )

    specifically_classified = [entry for entry in entries if entry["specific_matches"]]
    unclassified = [entry for entry in entries if not entry["specific_matches"]]
    catch_all_only = [entry for entry in unclassified if entry["catch_all_matches"]]
    outside_catch_all = [entry for entry in unclassified if not entry["catch_all_matches"]]
    multiply_matched = [entry for entry in entries if len(entry["specific_matches"]) > 1]

    return {
        "summary": {
            "candidate_files": len(entries),
            "specifically_classified_files": len(specifically_classified),
            "unclassified_files": len(unclassified),
            "catch_all_only_files": len(catch_all_only),
            "outside_catch_all_files": len(outside_catch_all),
            "multiply_matched_files": len(multiply_matched),
        },
        "specifically_classified_files": [entry["path"] for entry in specifically_classified],
        "unclassified_files": [entry["path"] for entry in unclassified],
        "catch_all_only_files": [entry["path"] for entry in catch_all_only],
        "outside_catch_all_files": [entry["path"] for entry in outside_catch_all],
        "multiply_matched_files": multiply_matched,
        "entries": entries,
        "specific_rows": specific_rows,
        "catch_all_rows": catch_all_rows,
    }


def render_text(report: dict[str, Any]) -> str:
    """Render a deterministic human-readable report."""
    summary = report["summary"]
    lines = [
        "Public test transfer inventory",
        "==============================",
        f"Candidate files: {summary['candidate_files']}",
        f"Specifically classified files: {summary['specifically_classified_files']}",
        f"Unclassified files (no specific row): {summary['unclassified_files']}",
        f"  Catch-all only: {summary['catch_all_only_files']}",
        f"  Outside catch-all: {summary['outside_catch_all_files']}",
        f"Multiply matched files: {summary['multiply_matched_files']}",
        "",
        "Specifically classified files:",
    ]

    entries_by_path = {entry["path"]: entry for entry in report["entries"]}
    if report["specifically_classified_files"]:
        for path in report["specifically_classified_files"]:
            matches = entries_by_path[path]["specific_matches"]
            row_labels = ", ".join(f"row {match['row_number']}" for match in matches)
            lines.append(f"  {path} [{row_labels}]")
    else:
        lines.append("  (none)")

    lines.extend(("", "Unclassified files:"))
    if report["unclassified_files"]:
        catch_all = set(report["catch_all_only_files"])
        for path in report["unclassified_files"]:
            label = "catch-all only" if path in catch_all else "outside catch-all"
            lines.append(f"  {path} [{label}]")
    else:
        lines.append("  (none)")

    lines.extend(("", "Multiply matched files:"))
    if report["multiply_matched_files"]:
        for entry in report["multiply_matched_files"]:
            row_labels = ", ".join(
                f"row {match['row_number']}" for match in entry["specific_matches"]
            )
            lines.append(f"  {entry['path']} [{row_labels}]")
    else:
        lines.append("  (none)")

    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Inventory test and fixture files not covered by specific transfer rows."
    )
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="repository root (defaults to the parent of tools/)",
    )
    parser.add_argument(
        "--registry",
        type=Path,
        help="registry path (defaults to docs/PUBLIC_TEST_TRANSFER.csv under --root)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    registry = args.registry or root / "docs" / "PUBLIC_TEST_TRANSFER.csv"
    if not registry.is_absolute():
        registry = root / registry
    report = build_inventory(root, registry)
    if args.format == "json":
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(render_text(report), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
