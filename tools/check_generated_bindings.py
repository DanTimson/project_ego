#!/usr/bin/env python3
"""Read-only guard for generated pack binding files."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any, Sequence


NOTE_TEMPLATE = (
    "Skeleton. Regenerate locally with tools/extract/make_bindings.py <var-dir> "
    "{pack_id}, then hand-edit the empty handlers. An empty 'abilities' map is "
    "a valid pack: every ability resolves as unbound and the load report counts "
    "it honestly."
)
EMPTY_SUMMARY = {"opcodes": 0, "bound": 0, "unbound": 0}
TOP_LEVEL_KEYS = {"pack", "note", "summary", "abilities"}
SUMMARY_KEYS = set(EMPTY_SUMMARY)


class Status(Enum):
    ABSENT = "ABSENT"
    EMPTY = "EMPTY"
    MALFORMED = "MALFORMED"
    POPULATED = "POPULATED"
    INVALID_STRUCTURE = "INVALID_STRUCTURE"
    ERROR = "ERROR"


@dataclass(frozen=True)
class CheckResult:
    path: Path
    status: Status
    detail: str


def expected_empty_skeleton(pack_id: str) -> dict[str, Any]:
    """Return the intentional committed empty structure for one pack."""
    return {
        "pack": pack_id,
        "note": NOTE_TEMPLATE.format(pack_id=pack_id),
        "summary": dict(EMPTY_SUMMARY),
        "abilities": {},
    }


def _is_count(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _has_populated_structure(value: object, pack_id: str) -> bool:
    """Recognize the binding schema with at least one content indicator set."""
    if not isinstance(value, dict) or set(value) != TOP_LEVEL_KEYS:
        return False
    if value["pack"] != pack_id or not isinstance(value["note"], str):
        return False
    summary = value["summary"]
    abilities = value["abilities"]
    if not isinstance(summary, dict) or set(summary) != SUMMARY_KEYS:
        return False
    if not all(_is_count(summary[key]) for key in SUMMARY_KEYS):
        return False
    if not isinstance(abilities, dict):
        return False
    return bool(abilities) or any(summary[key] != 0 for key in SUMMARY_KEYS)


def check_binding(path: Path, pack_id: str) -> CheckResult:
    if not path.exists():
        return CheckResult(path, Status.ABSENT, "expected binding file is absent")
    if not path.is_file():
        return CheckResult(path, Status.ERROR, "binding path is not a regular file")

    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        return CheckResult(path, Status.ERROR, f"cannot read binding file: {exc}")

    try:
        value = json.loads(text)
    except json.JSONDecodeError as exc:
        return CheckResult(
            path,
            Status.MALFORMED,
            f"malformed JSON at line {exc.lineno}, column {exc.colno}",
        )

    if value == expected_empty_skeleton(pack_id):
        return CheckResult(path, Status.EMPTY, "accepted intentional empty skeleton")
    if _has_populated_structure(value, pack_id):
        return CheckResult(
            path,
            Status.POPULATED,
            "structurally valid binding content is populated",
        )
    return CheckResult(
        path,
        Status.INVALID_STRUCTURE,
        "valid JSON does not match the intentional empty skeleton or populated schema",
    )


def check_repository(repository: Path) -> tuple[list[CheckResult], str | None]:
    """Check one expected bindings.json path for each immediate pack directory."""
    try:
        repository = repository.resolve(strict=True)
    except OSError as exc:
        return [], f"cannot resolve repository path: {exc}"
    if not repository.is_dir():
        return [], f"repository path is not a directory: {repository}"

    packs_dir = repository / "packs"
    if not packs_dir.is_dir():
        return [], f"packs directory is absent or not a directory: {packs_dir}"

    try:
        pack_dirs = sorted(
            (entry for entry in packs_dir.iterdir() if entry.is_dir()),
            key=lambda entry: entry.name,
        )
    except OSError as exc:
        return [], f"cannot enumerate packs directory: {exc}"
    if not pack_dirs:
        return [], f"no pack directories found in: {packs_dir}"

    return [check_binding(pack / "bindings.json", pack.name) for pack in pack_dirs], None


def _display_path(path: Path, repository: Path) -> str:
    try:
        return path.relative_to(repository).as_posix()
    except ValueError:
        return path.as_posix()


def run(repository: Path, allow_populated: bool = False) -> int:
    resolved_repository = repository.resolve()
    results, operational_error = check_repository(repository)
    if operational_error is not None:
        print(f"ERROR: {operational_error}")
        print("RESULT: OPERATIONAL_ERROR")
        return 2

    for result in results:
        display_path = _display_path(result.path, resolved_repository)
        print(f"CHECK {display_path}: {result.status.value} - {result.detail}")

    errors = [result for result in results if result.status is Status.ERROR]
    findings = [
        result
        for result in results
        if result.status
        in {
            Status.ABSENT,
            Status.MALFORMED,
            Status.POPULATED,
            Status.INVALID_STRUCTURE,
        }
    ]
    unoverridden = [
        result
        for result in findings
        if not (allow_populated and result.status is Status.POPULATED)
    ]

    if errors:
        print(f"RESULT: OPERATIONAL_ERROR ({len(errors)} file error(s))")
        return 2
    if unoverridden:
        print(f"RESULT: FINDINGS ({len(unoverridden)} blocking finding(s))")
        return 1
    populated = sum(result.status is Status.POPULATED for result in results)
    if allow_populated and populated:
        print(
            "RESULT: OK_WITH_POPULATED_OVERRIDE "
            f"({populated} populated finding(s) explicitly allowed)"
        )
    else:
        print(f"RESULT: OK ({len(results)} empty binding file(s))")
    return 0


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check packs/*/bindings.json without modifying binding files."
    )
    parser.add_argument(
        "repository",
        nargs="?",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="repository root (default: the parent of tools/)",
    )
    parser.add_argument(
        "--allow-populated",
        action="store_true",
        help=(
            "allow only structurally valid populated bindings to exit successfully; "
            "the populated finding is still reported"
        ),
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    return run(args.repository, allow_populated=args.allow_populated)


if __name__ == "__main__":
    sys.exit(main())
