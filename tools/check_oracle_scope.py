#!/usr/bin/env python3
"""Validate the O1-O4 oracle inventory and future task oracle scope."""

from __future__ import annotations

import argparse
import ast
import csv
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

INVENTORY_HEADER = (
    "path",
    "oracle_class",
    "current_role",
    "retention_criterion",
    "expansion_allowed_by_default",
    "notes",
)
ORACLE_CLASSES = {"O1", "O2", "O3", "O4"}
DECLARATIONS = {"REQUIRED", "EXISTING_HARNESS_ONLY", "NOT_REQUIRED"}
TASK_NAME_RE = re.compile(r"^CX-(?P<number>\d+)\.md$")
DECLARATION_RE = re.compile(
    r"^\s*PYTHON_ORACLE:\s*(?P<value>\S+)\s*$", re.MULTILINE
)
STRUCTURED_KEY_RE = re.compile(r"^\s*(?P<key>[A-Z_]+|Reason):\s*(?P<value>.*)\s*$")


@dataclass(frozen=True)
class InventoryRow:
    path: str
    oracle_class: str
    current_role: str
    retention_criterion: str
    expansion_allowed_by_default: str
    notes: str


@dataclass(frozen=True)
class TaskDeclaration:
    value: str
    scope: frozenset[str]


def _relative_display(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return str(path)


def _is_empty_package_marker(path: Path) -> bool:
    if path.name != "__init__.py":
        return False
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, SyntaxError):
        return False
    nodes = list(tree.body)
    if nodes and isinstance(nodes[0], ast.Expr) and isinstance(
        nodes[0].value, ast.Constant
    ) and isinstance(nodes[0].value.value, str):
        nodes.pop(0)
    return not nodes


def is_standing_oracle_path(relative: str, root: Path) -> bool:
    path = Path(relative)
    if not path.parts or path.parts[0] != "oracle" or path.suffix != ".py":
        return False
    if "__pycache__" in path.parts or path.name == "conftest.py":
        return False
    if path.name.startswith("test_"):
        return False
    absolute = root / path
    if absolute.exists() and _is_empty_package_marker(absolute):
        return False
    return True


def standing_oracle_modules(root: Path) -> set[str]:
    oracle = root / "oracle"
    if not oracle.is_dir():
        return set()
    return {
        path.relative_to(root).as_posix()
        for path in oracle.rglob("*.py")
        if is_standing_oracle_path(path.relative_to(root).as_posix(), root)
    }


def read_inventory(path: Path) -> tuple[list[InventoryRow], list[str]]:
    errors: list[str] = []
    try:
        with path.open("r", encoding="utf-8", newline="") as handle:
            raw = list(csv.reader(handle, strict=True))
    except (OSError, UnicodeError, csv.Error) as exc:
        return [], [f"{path}: cannot read inventory: {exc}"]
    if not raw:
        return [], [f"{path}: inventory is empty"]
    if tuple(raw[0]) != INVENTORY_HEADER:
        errors.append(
            f"{path}:1: header mismatch; expected {','.join(INVENTORY_HEADER)}"
        )
    rows: list[InventoryRow] = []
    for line_no, values in enumerate(raw[1:], 2):
        if len(values) != len(INVENTORY_HEADER):
            errors.append(
                f"{path}:{line_no}: expected {len(INVENTORY_HEADER)} columns, "
                f"found {len(values)}"
            )
            continue
        if any(not value.strip() for value in values):
            errors.append(f"{path}:{line_no}: every inventory field must be populated")
        rows.append(InventoryRow(*(value.strip() for value in values)))
    return rows, errors


def validate_inventory(path: Path, root: Path) -> tuple[dict[str, InventoryRow], list[str]]:
    rows, errors = read_inventory(path)
    indexed: dict[str, InventoryRow] = {}
    for line_no, row in enumerate(rows, 2):
        if row.path in indexed:
            errors.append(f"{path}:{line_no}: duplicate path: {row.path}")
        else:
            indexed[row.path] = row
        if row.oracle_class not in ORACLE_CLASSES:
            errors.append(
                f"{path}:{line_no}: invalid oracle_class '{row.oracle_class}'"
            )
        if row.expansion_allowed_by_default != "no":
            errors.append(
                f"{path}:{line_no}: expansion_allowed_by_default must be 'no'; "
                "all O1-O4 expansion is opt-in under DELIB-0008"
            )
        candidate = root / row.path
        if not candidate.is_file():
            errors.append(f"{path}:{line_no}: stale or missing path: {row.path}")
        elif not is_standing_oracle_path(row.path, root):
            errors.append(
                f"{path}:{line_no}: path is outside the standing-module scope: {row.path}"
            )

    standing = standing_oracle_modules(root)
    for missing in sorted(standing - set(indexed)):
        errors.append(f"{path}: missing module classification: {missing}")
    for extra in sorted(set(indexed) - standing):
        if (root / extra).is_file():
            errors.append(f"{path}: row is not a standing oracle module: {extra}")
    return indexed, errors


def _without_fenced_blocks(text: str) -> str:
    kept: list[str] = []
    in_fence = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence:
            kept.append(line)
    return "\n".join(kept)


def _structured_fields(text: str) -> dict[str, list[str]]:
    """Parse structured task fields, including wrapped Markdown continuation lines.

    A field continues across immediately following non-empty lines until another
    structured field, a Markdown heading, or a blank line begins. This keeps task
    contracts readable without silently truncating wrapped values.
    """
    fields: dict[str, list[str]] = {}
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        match = STRUCTURED_KEY_RE.match(lines[index])
        if match is None:
            index += 1
            continue

        key = match.group("key")
        parts = [match.group("value").strip()]
        next_index = index + 1
        while next_index < len(lines):
            continuation = lines[next_index]
            if not continuation.strip():
                break
            if STRUCTURED_KEY_RE.match(continuation):
                break
            if continuation.lstrip().startswith("#"):
                break
            parts.append(continuation.strip())
            next_index += 1

        value = " ".join(part for part in parts if part).strip()
        fields.setdefault(key, []).append(value)
        index = next_index
    return fields


def _single_field(fields: dict[str, list[str]], name: str, errors: list[str], task: Path) -> str:
    values = fields.get(name, [])
    if len(values) != 1 or not values[0]:
        errors.append(f"{task}: {name}: must appear exactly once with non-empty text")
        return ""
    return values[0]


def validate_task(task: Path) -> tuple[TaskDeclaration | None, list[str]]:
    errors: list[str] = []
    try:
        text = task.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        return None, [f"{task}: cannot read task: {exc}"]
    text = _without_fenced_blocks(text)
    matches = list(DECLARATION_RE.finditer(text))
    if len(matches) != 1:
        return None, [
            f"{task}: expected exactly one PYTHON_ORACLE declaration, found {len(matches)}"
        ]
    raw_value = matches[0].group("value")
    value = raw_value[1:-1] if raw_value.startswith("`") and raw_value.endswith("`") else raw_value
    if value not in DECLARATIONS:
        return None, [
            f"{task}: invalid PYTHON_ORACLE value '{value}'; expected "
            + ", ".join(sorted(DECLARATIONS))
        ]
    fields = _structured_fields(text)
    scope: set[str] = set()
    if value == "NOT_REQUIRED":
        reasons = fields.get("PYTHON_ORACLE_REASON", []) + fields.get("Reason", [])
        if len(reasons) != 1 or not reasons[0]:
            errors.append(
                f"{task}: NOT_REQUIRED requires exactly one short Reason: or "
                "PYTHON_ORACLE_REASON:"
            )
    elif value == "EXISTING_HARNESS_ONLY":
        statement = _single_field(fields, "PYTHON_ORACLE_HARNESS", errors, task)
        normalized = statement.lower()
        if statement and not (
            ("o2" in normalized or "existing" in normalized)
            and ("green" in normalized or "remain valid" in normalized)
            and ("no broad" in normalized or "not authoriz" in normalized)
        ):
            errors.append(
                f"{task}: PYTHON_ORACLE_HARNESS must say existing O2 coverage stays "
                "green/valid and that broadening is not authorized"
            )
    else:
        _single_field(fields, "PYTHON_ORACLE_RETENTION_CRITERION", errors, task)
        raw_scope = _single_field(fields, "PYTHON_ORACLE_SCOPE", errors, task)
        _single_field(fields, "PYTHON_ORACLE_INDEPENDENT_VALUE", errors, task)
        if raw_scope:
            for item in raw_scope.split(","):
                item = item.strip()
                module = item.split("::", 1)[0]
                if not item or not module.startswith("oracle/") or not module.endswith(".py"):
                    errors.append(
                        f"{task}: invalid PYTHON_ORACLE_SCOPE item '{item}'; "
                        "use exact oracle/*.py paths, optionally followed by ::kernel"
                    )
                else:
                    scope.add(module)
            if not scope:
                errors.append(f"{task}: PYTHON_ORACLE_SCOPE names no exact Python surface")
    return TaskDeclaration(value, frozenset(scope)), errors


def future_tasks(root: Path) -> list[Path]:
    tasks = root / "docs" / "codex" / "tasks"
    if not tasks.is_dir():
        return []
    result: list[Path] = []
    for path in sorted(tasks.glob("CX-*.md")):
        match = TASK_NAME_RE.match(path.name)
        if match and int(match.group("number")) >= 19:
            result.append(path)
    return result


def _git(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    # /mnt/d worktrees can report synthetic executable-bit changes unless Git is
    # forced to ignore file-mode metadata. Keep the validator independent of the
    # caller's shell environment.
    return subprocess.run(
        ["git", "-c", "core.fileMode=false", *args],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )


def path_changed_since_base(root: Path, base: str, relative: str) -> tuple[bool, list[str]]:
    """Return whether a path differs from the frozen base, including untracked adds."""
    diff = _git(root, "diff", "--name-only", base, "--", relative)
    if diff.returncode:
        return False, [f"git diff failed for {relative}: {diff.stderr.strip()}"]
    if diff.stdout.strip():
        return True, []

    untracked = _git(root, "ls-files", "--others", "--exclude-standard", "--", relative)
    if untracked.returncode:
        return False, [f"git ls-files failed for {relative}: {untracked.stderr.strip()}"]
    return bool(untracked.stdout.strip()), []


def changed_oracle_modules(root: Path, base: str) -> tuple[dict[str, str], list[str]]:
    verify = _git(root, "cat-file", "-e", f"{base}^{{commit}}")
    if verify.returncode:
        return {}, [f"git base '{base}' is not a commit in {root}"]
    diff = _git(root, "diff", "--name-status", "--find-renames", base, "--", "oracle")
    if diff.returncode:
        return {}, [f"git diff failed: {diff.stderr.strip()}"]
    changed: dict[str, str] = {}
    for line in diff.stdout.splitlines():
        parts = line.split("\t")
        status = parts[0]
        if status.startswith(("R", "C")) and len(parts) == 3:
            relative = parts[2]
            effective = "A" if status.startswith("R") else "M"
        elif len(parts) == 2:
            relative = parts[1]
            effective = status[0]
        else:
            continue
        if effective in {"A", "M"} and is_standing_oracle_path(relative, root):
            changed[relative] = effective
    untracked = _git(root, "ls-files", "--others", "--exclude-standard", "--", "oracle")
    if untracked.returncode:
        return changed, [f"git ls-files failed: {untracked.stderr.strip()}"]
    for relative in untracked.stdout.splitlines():
        if is_standing_oracle_path(relative, root):
            changed[relative] = "A"
    return changed, []


def validate_diff(
    root: Path,
    base: str,
    declaration: TaskDeclaration,
    inventory: dict[str, InventoryRow],
) -> list[str]:
    changed, errors = changed_oracle_modules(root, base)
    if errors:
        return errors
    if declaration.value == "NOT_REQUIRED":
        for path in sorted(changed):
            errors.append(f"NOT_REQUIRED forbids production oracle change: {path}")
    elif declaration.value == "EXISTING_HARNESS_ONLY":
        inventory_changed, inventory_change_errors = path_changed_since_base(
            root, base, "docs/ORACLE_SCOPE.csv"
        )
        errors.extend(inventory_change_errors)
        if inventory_changed:
            errors.append(
                "EXISTING_HARNESS_ONLY forbids oracle inventory changes; "
                "use REQUIRED or a dedicated governance/reclassification task"
            )
        for path, status in sorted(changed.items()):
            if status == "A":
                errors.append(f"EXISTING_HARNESS_ONLY forbids new oracle module: {path}")
            elif path not in inventory or inventory[path].oracle_class != "O2":
                errors.append(
                    f"EXISTING_HARNESS_ONLY permits changes only to classified O2 modules: {path}"
                )
    else:
        for path in sorted(changed):
            if path not in declaration.scope:
                errors.append(f"REQUIRED scope does not declare changed module: {path}")
            if changed[path] == "A" and path not in inventory:
                errors.append(f"new oracle module is missing from inventory: {path}")
    return errors


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--inventory", type=Path, default=Path("docs/ORACLE_SCOPE.csv"))
    parser.add_argument("--base", help="frozen git base for diff-aware validation")
    parser.add_argument("--task", type=Path, help="task contract used with --base")
    args = parser.parse_args(list(argv) if argv is not None else None)
    root = args.root.resolve()
    inventory_path = args.inventory
    if not inventory_path.is_absolute():
        inventory_path = root / inventory_path
    errors: list[str] = []
    inventory, inventory_errors = validate_inventory(inventory_path, root)
    errors.extend(inventory_errors)

    selected_task: Path | None = None
    if args.task is not None:
        selected_task = args.task if args.task.is_absolute() else root / args.task
        _declaration, task_errors = validate_task(selected_task)
        errors.extend(task_errors)
    else:
        for task in future_tasks(root):
            _declaration, task_errors = validate_task(task)
            errors.extend(task_errors)

    if bool(args.base) != bool(args.task):
        errors.append("--base and --task must be supplied together")
    elif args.base and selected_task:
        declaration, task_errors = validate_task(selected_task)
        # Avoid duplicate diagnostics from the selected-task validation above.
        if not task_errors and declaration is not None:
            errors.extend(validate_diff(root, args.base, declaration, inventory))

    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    if errors:
        print(f"FAIL: {len(errors)} oracle-scope error(s)", file=sys.stderr)
        return 1
    print(
        f"PASS: {len(inventory)} standing oracle module(s) classified; "
        f"{len(future_tasks(root)) if args.task is None else 1} task declaration(s) checked"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
