#!/usr/bin/env python3
"""Validate the public-lineage artifact and test transfer registries."""

from __future__ import annotations

import argparse
import csv
import glob
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence


NECESSITY_CLASSES = {
    "N0_PUBLIC",
    "N1_BLACKBOX",
    "N2_EXACT_EDGE",
    "N3_INTERNAL",
    "N4_PROFILE",
}
TRANSFER_CLASSES = {
    "T0_RETAIN",
    "T1_SANITIZE",
    "T2_REIMPLEMENT",
    "T3_RESEARCH_ONLY",
    "T4_DELIBERATE",
}

LINEAGE_HEADER = (
    "artifact",
    "symbol_or_scope",
    "current_basis",
    "necessity_class",
    "transfer_class",
    "materiality",
    "public_basis",
    "binary_basis",
    "binary_basis_surface",
    "public_basis_sufficient",
    "required_action",
    "owner",
    "status",
    "notes",
)
TEST_HEADER = (
    "artifact_or_pattern",
    "area",
    "basis",
    "necessity_class",
    "transfer_class",
    "required_action",
    "status",
    "notes",
)

# These are registry concepts, not filesystem paths. Keeping the list explicit
# prevents a misspelled path from silently becoming a descriptive aggregate.
LINEAGE_AGGREGATES = {
    "private evidence exports",
    "packs and content parsers",
    "tests using public formulas and synthetic fixtures",
    "tests tied to raw addresses or decompiler-shaped provider cuts",
}
TEST_AGGREGATES = {
    "all remaining tests/** and oracle/test_*.py",
}


@dataclass(frozen=True)
class RegistrySpec:
    name: str
    header: tuple[str, ...]
    artifact_column: str
    scope_column: str
    aggregates: frozenset[str]


LINEAGE_SPEC = RegistrySpec(
    name="lineage",
    header=LINEAGE_HEADER,
    artifact_column="artifact",
    scope_column="symbol_or_scope",
    aggregates=frozenset(LINEAGE_AGGREGATES),
)
TEST_SPEC = RegistrySpec(
    name="test",
    header=TEST_HEADER,
    artifact_column="artifact_or_pattern",
    scope_column="area",
    aggregates=frozenset(TEST_AGGREGATES),
)


def split_classes(value: str) -> list[str]:
    return [part.strip() for part in value.split("+")]


def has_glob_magic(value: str) -> bool:
    return glob.has_magic(value)


def looks_like_path(value: str) -> bool:
    return "/" in value or Path(value).suffix != ""


def classify_part(value: str, aggregates: frozenset[str]) -> str | None:
    if value in aggregates:
        return "aggregate"
    if has_glob_magic(value):
        return "glob"
    if looks_like_path(value):
        return "literal"
    return None


def classify_artifact(
    value: str, aggregates: frozenset[str]
) -> tuple[str | None, list[tuple[str, str]]]:
    parts = [part.strip() for part in value.split(";")]
    if any(not part for part in parts):
        return None, []

    classified: list[tuple[str, str]] = []
    for part in parts:
        kind = classify_part(part, aggregates)
        if kind is None:
            return None, []
        classified.append((part, kind))

    if len(parts) > 1:
        return "group", classified
    return classified[0][1], classified


def read_rows(path: Path, expected_header: Sequence[str]) -> tuple[list[dict[str, str]], list[str]]:
    errors: list[str] = []
    try:
        with path.open("r", encoding="utf-8", newline="") as handle:
            raw_rows = list(csv.reader(handle, strict=True))
    except (OSError, UnicodeError, csv.Error) as exc:
        return [], [f"{path}: cannot read CSV: {exc}"]

    if not raw_rows:
        return [], [f"{path}: empty CSV"]

    header = tuple(raw_rows[0])
    if header != tuple(expected_header):
        errors.append(
            f"{path}:1: header mismatch; expected {','.join(expected_header)}"
        )

    rows: list[dict[str, str]] = []
    for line_no, values in enumerate(raw_rows[1:], 2):
        if len(values) != len(expected_header):
            errors.append(
                f"{path}:{line_no}: expected {len(expected_header)} columns, "
                f"found {len(values)}"
            )
            continue
        rows.append({key: value for key, value in zip(expected_header, values)})
        rows[-1]["__line__"] = str(line_no)
    return rows, errors


def validate_classes(
    path: Path,
    line_no: str,
    column: str,
    value: str,
    recognized: set[str],
) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    notices: list[str] = []
    tokens = split_classes(value)
    if not tokens or any(not token for token in tokens):
        return [f"{path}:{line_no}: empty class in {column}"], notices

    for token in tokens:
        if token == "unclassified":
            notices.append(f"{path}:{line_no}: {column} remains unclassified")
        elif token not in recognized:
            errors.append(f"{path}:{line_no}: unknown {column} value '{token}'")
    return errors, notices


def validate_registry(
    path: Path, root: Path, spec: RegistrySpec
) -> tuple[list[str], list[str], Counter[str], int]:
    rows, errors = read_rows(path, spec.header)
    notices: list[str] = []
    forms: Counter[str] = Counter()
    seen: dict[tuple[str, str], str] = {}

    for row in rows:
        line_no = row["__line__"]
        artifact = row[spec.artifact_column].strip()
        scope = row[spec.scope_column].strip()
        key = (artifact, scope)
        if key in seen:
            errors.append(
                f"{path}:{line_no}: duplicate artifact/scope row; "
                f"first seen on line {seen[key]}"
            )
        else:
            seen[key] = line_no

        form, parts = classify_artifact(artifact, spec.aggregates)
        if form is None:
            errors.append(
                f"{path}:{line_no}: artifact form is empty or not a recognized "
                "literal, semicolon group, glob, or descriptive aggregate"
            )
        else:
            forms[form] += 1
            for part, kind in parts:
                if kind == "literal" and not (root / part).exists():
                    errors.append(f"{path}:{line_no}: literal path does not exist: {part}")

        class_errors, class_notices = validate_classes(
            path,
            line_no,
            "necessity_class",
            row["necessity_class"].strip(),
            NECESSITY_CLASSES,
        )
        errors.extend(class_errors)
        notices.extend(class_notices)
        class_errors, class_notices = validate_classes(
            path,
            line_no,
            "transfer_class",
            row["transfer_class"].strip(),
            TRANSFER_CLASSES,
        )
        errors.extend(class_errors)
        notices.extend(class_notices)

    return errors, notices, forms, len(rows)


def format_forms(forms: Counter[str]) -> str:
    order = ("literal", "group", "glob", "aggregate")
    return ", ".join(f"{name}={forms[name]}" for name in order)


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=Path("."),
        help="repository root used to resolve literal paths (default: current directory)",
    )
    parser.add_argument(
        "--lineage",
        type=Path,
        default=Path("docs/PUBLIC_LINEAGE_TRANSFER.csv"),
    )
    parser.add_argument(
        "--tests",
        type=Path,
        default=Path("docs/PUBLIC_TEST_TRANSFER.csv"),
    )
    args = parser.parse_args(list(argv) if argv is not None else None)

    all_errors: list[str] = []
    all_notices: list[str] = []
    summaries: list[str] = []
    for path, spec in ((args.lineage, LINEAGE_SPEC), (args.tests, TEST_SPEC)):
        errors, notices, forms, row_count = validate_registry(path, args.root, spec)
        all_errors.extend(errors)
        all_notices.extend(notices)
        summaries.append(
            f"{spec.name}: {row_count} row(s); forms: {format_forms(forms)}"
        )

    for notice in all_notices:
        print(f"NOTICE: {notice}")
    for error in all_errors:
        print(f"ERROR: {error}", file=sys.stderr)

    if all_errors:
        print(
            f"FAIL: {len(all_errors)} structural error(s); "
            f"{len(all_notices)} open classification notice(s)",
            file=sys.stderr,
        )
        return 1

    for summary in summaries:
        print(summary)
    print(
        f"PASS: public-lineage registries validated; "
        f"{len(all_notices)} open classification notice(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
