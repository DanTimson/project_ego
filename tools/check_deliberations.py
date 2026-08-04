#!/usr/bin/env python3
"""Validate Project EGO cross-agent deliberation packages.

The status file intentionally uses a small YAML subset:
- top-level ``key: scalar`` entries
- top-level lists introduced by ``key:`` and indented ``- item`` lines

No third-party packages are required.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, List, Union

ScalarOrList = Union[str, List[str]]

ALLOWED_STATES = {
    "draft",
    "independent_review",
    "cross_review",
    "decision_required",
    "decided",
    "implementing",
    "verified",
    "archived",
}

DECIDED_STATES = {"decided", "implementing", "verified", "archived"}
VERIFIED_STATES = {"verified", "archived"}
REQUIRED_FILES = {
    "brief.md",
    "position_binary.md",
    "position_engine.md",
    "cross_review.md",
    "decision.md",
    "status.yaml",
}
DIR_RE = re.compile(r"^(?P<number>\d{4})-(?P<slug>[a-z0-9][a-z0-9-]*)$")
ID_RE = re.compile(r"^DELIB-(?P<number>\d{4})$")


def parse_small_yaml(path: Path) -> Dict[str, ScalarOrList]:
    data: Dict[str, ScalarOrList] = {}
    active_list: str | None = None

    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue

        if raw.startswith("  - "):
            if active_list is None:
                raise ValueError(f"{path}:{line_no}: list item without a list key")
            value = raw[4:].strip()
            cast = data[active_list]
            assert isinstance(cast, list)
            cast.append(value)
            continue

        if raw.startswith((" ", "\t")):
            raise ValueError(
                f"{path}:{line_no}: unsupported nesting; use top-level scalars/lists"
            )

        if ":" not in raw:
            raise ValueError(f"{path}:{line_no}: expected 'key: value'")

        key, value = raw.split(":", 1)
        key = key.strip()
        value = value.strip()

        if not key:
            raise ValueError(f"{path}:{line_no}: empty key")
        if key in data:
            raise ValueError(f"{path}:{line_no}: duplicate key '{key}'")

        if value:
            data[key] = value
            active_list = None
        else:
            data[key] = []
            active_list = key

    return data


def scalar(data: Dict[str, ScalarOrList], key: str) -> str:
    value = data.get(key, "")
    return value if isinstance(value, str) else ""


def list_value(data: Dict[str, ScalarOrList], key: str) -> List[str]:
    value = data.get(key, [])
    return value if isinstance(value, list) else []


def nonempty_markdown(path: Path, required_heading: str) -> bool:
    text = path.read_text(encoding="utf-8")
    return required_heading in text and len(text.strip()) > len(required_heading)


def validate_package(path: Path) -> List[str]:
    errors: List[str] = []
    match = DIR_RE.match(path.name)
    if not match:
        return [f"{path}: directory name must be NNNN-lowercase-slug"]

    missing = sorted(name for name in REQUIRED_FILES if not (path / name).is_file())
    if missing:
        errors.append(f"{path}: missing required files: {', '.join(missing)}")
        return errors

    try:
        status = parse_small_yaml(path / "status.yaml")
    except ValueError as exc:
        errors.append(str(exc))
        return errors

    required_keys = {"id", "title", "state", "opened", "participants"}
    for key in sorted(required_keys):
        if key not in status:
            errors.append(f"{path}/status.yaml: missing key '{key}'")

    deliberation_id = scalar(status, "id")
    id_match = ID_RE.match(deliberation_id)
    if not id_match:
        errors.append(f"{path}/status.yaml: invalid id '{deliberation_id}'")
    elif id_match.group("number") != match.group("number"):
        errors.append(
            f"{path}/status.yaml: id {deliberation_id} does not match directory"
        )

    state = scalar(status, "state")
    if state not in ALLOWED_STATES:
        errors.append(
            f"{path}/status.yaml: state '{state}' is not one of "
            + ", ".join(sorted(ALLOWED_STATES))
        )

    participants = list_value(status, "participants")
    for required in ("human", "binary", "engine"):
        if required not in participants:
            errors.append(
                f"{path}/status.yaml: participants must include '{required}'"
            )

    if state in DECIDED_STATES:
        decision_name = scalar(status, "decision")
        if not decision_name:
            errors.append(f"{path}/status.yaml: decided state requires 'decision'")
        elif not (path / decision_name).is_file():
            errors.append(
                f"{path}/status.yaml: decision file '{decision_name}' does not exist"
            )
        elif not nonempty_markdown(path / decision_name, "## Decision"):
            errors.append(f"{path}/{decision_name}: missing non-empty '## Decision'")

    if state in VERIFIED_STATES and not list_value(status, "verification"):
        errors.append(
            f"{path}/status.yaml: verified/archived state requires verification targets"
        )

    if state in {"cross_review", "decision_required", *DECIDED_STATES}:
        if not nonempty_markdown(path / "cross_review.md", "# Cross-review"):
            errors.append(f"{path}/cross_review.md: cross-review is empty")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "root",
        nargs="?",
        default="docs/deliberations",
        help="deliberations directory (default: docs/deliberations)",
    )
    args = parser.parse_args()

    root = Path(args.root)
    if not root.is_dir():
        print(f"ERROR: {root} is not a directory", file=sys.stderr)
        return 1

    packages = sorted(
        path
        for path in root.iterdir()
        if path.is_dir() and path.name != "_template" and not path.name.startswith(".")
    )

    errors: List[str] = []
    for package in packages:
        errors.extend(validate_package(package))

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(
            f"FAIL: {len(errors)} error(s) across {len(packages)} package(s)",
            file=sys.stderr,
        )
        return 1

    print(f"PASS: {len(packages)} deliberation package(s) validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
