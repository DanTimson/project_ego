#!/usr/bin/env python3
"""Scan registered transfer candidates for research-only provenance tokens.

Findings are review input, not transfer decisions.  By default findings do not
make the command fail; malformed configuration, registries, or candidate files
do.  Use --fail-on-findings when a clean surface is required by a later gate.
"""

from __future__ import annotations

import argparse
import csv
import fnmatch
import glob
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Pattern, Sequence


DEFAULT_PATTERNS = (
    {
        "name": "executable_address",
        # Deliberately narrow: eight-digit, zero-prefixed executable-style
        # addresses, not every hexadecimal literal or claim number.
        "regex": r"(?<![0-9A-Za-z_])(?:0x)?00[0-9A-Fa-f]{6}(?![0-9A-Za-z_])",
        "flags": [],
    },
    {
        "name": "ghidra_symbol",
        "regex": r"\b(?:FUN|LAB|DAT|PTR)_[A-Za-z0-9_]+",
        "flags": [],
    },
    {
        "name": "ghidra_terminology",
        "regex": r"\b(?:Ghidra|decompiler(?:-shaped)?)\b",
        "flags": ["IGNORECASE"],
    },
    {
        "name": "decompiler_identifier",
        "regex": (
            r"\b(?:undefined(?:1|2|4|8)|[a-z]{1,3}Var[0-9]+|"
            r"local_[A-Za-z0-9_]+|[a-z]{1,3}Stack_[0-9A-Fa-f]+|"
            r"param_[0-9]+|extraout_[A-Za-z0-9_]+|unaff_[A-Za-z0-9_]+)\b"
        ),
        "flags": [],
    },
)

FLAG_VALUES = {
    "ASCII": re.ASCII,
    "IGNORECASE": re.IGNORECASE,
    "MULTILINE": re.MULTILINE,
}


@dataclass(frozen=True)
class ScanPattern:
    name: str
    expression: str
    regex: Pattern[str]


@dataclass(frozen=True)
class AllowRule:
    path: str
    pattern: str
    line_expression: str | None
    line_regex: Pattern[str] | None
    reason: str


@dataclass(frozen=True, order=True)
class Finding:
    path: str
    line: int
    column: int
    pattern: str
    match: str
    text: str


@dataclass(frozen=True)
class ScanConfig:
    patterns: tuple[ScanPattern, ...]
    allowlist: tuple[AllowRule, ...]


def _compile_pattern(raw: object, location: str) -> tuple[ScanPattern | None, list[str]]:
    errors: list[str] = []
    if not isinstance(raw, dict):
        return None, [f"{location}: pattern must be an object"]
    name = raw.get("name")
    expression = raw.get("regex")
    flags_raw = raw.get("flags", [])
    if not isinstance(name, str) or not name.strip():
        errors.append(f"{location}: pattern name must be a non-empty string")
    if not isinstance(expression, str) or not expression:
        errors.append(f"{location}: regex must be a non-empty string")
    if not isinstance(flags_raw, list) or not all(isinstance(item, str) for item in flags_raw):
        errors.append(f"{location}: flags must be a list of strings")
        flags_raw = []
    flags = 0
    for flag_name in flags_raw:
        if flag_name not in FLAG_VALUES:
            errors.append(f"{location}: unknown regex flag '{flag_name}'")
        else:
            flags |= FLAG_VALUES[flag_name]
    if errors:
        return None, errors
    assert isinstance(name, str) and isinstance(expression, str)
    try:
        compiled = re.compile(expression, flags)
    except re.error as exc:
        return None, [f"{location}: invalid regex: {exc}"]
    return ScanPattern(name.strip(), expression, compiled), []


def _compile_allow_rule(raw: object, location: str) -> tuple[AllowRule | None, list[str]]:
    errors: list[str] = []
    if not isinstance(raw, dict):
        return None, [f"{location}: allowlist entry must be an object"]
    path = raw.get("path")
    pattern = raw.get("pattern")
    reason = raw.get("reason")
    line_expression = raw.get("line_regex")
    if not isinstance(path, str) or not path.strip():
        errors.append(f"{location}: path must be a non-empty glob string")
    if not isinstance(pattern, str) or not pattern.strip():
        errors.append(f"{location}: pattern must be a non-empty name or '*'")
    if not isinstance(reason, str) or not reason.strip():
        errors.append(f"{location}: reason must be a non-empty string")
    if line_expression is not None and not isinstance(line_expression, str):
        errors.append(f"{location}: line_regex must be a string when present")
    line_regex = None
    if isinstance(line_expression, str):
        try:
            line_regex = re.compile(line_expression)
        except re.error as exc:
            errors.append(f"{location}: invalid line_regex: {exc}")
    if errors:
        return None, errors
    assert isinstance(path, str) and isinstance(pattern, str) and isinstance(reason, str)
    return AllowRule(
        path=path.strip(),
        pattern=pattern.strip(),
        line_expression=line_expression,
        line_regex=line_regex,
        reason=reason.strip(),
    ), []


def load_config(path: Path | None) -> tuple[ScanConfig | None, list[str]]:
    raw: object = {}
    if path is not None:
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            return None, [f"{path}: cannot read configuration: {exc}"]
    if not isinstance(raw, dict):
        return None, [f"{path or '<default>'}: configuration must be an object"]

    raw_patterns = raw.get("patterns", list(DEFAULT_PATTERNS))
    raw_allowlist = raw.get("allowlist", [])
    errors: list[str] = []
    if not isinstance(raw_patterns, list):
        errors.append(f"{path or '<default>'}: patterns must be a list")
        raw_patterns = []
    if not isinstance(raw_allowlist, list):
        errors.append(f"{path or '<default>'}: allowlist must be a list")
        raw_allowlist = []

    patterns: list[ScanPattern] = []
    for index, value in enumerate(raw_patterns):
        pattern, item_errors = _compile_pattern(value, f"patterns[{index}]")
        errors.extend(item_errors)
        if pattern is not None:
            patterns.append(pattern)
    names = [pattern.name for pattern in patterns]
    for name in sorted(set(names)):
        if names.count(name) > 1:
            errors.append(f"duplicate pattern name '{name}'")

    allowlist: list[AllowRule] = []
    for index, value in enumerate(raw_allowlist):
        rule, item_errors = _compile_allow_rule(value, f"allowlist[{index}]")
        errors.extend(item_errors)
        if rule is not None:
            allowlist.append(rule)

    if errors:
        return None, errors
    return ScanConfig(tuple(patterns), tuple(allowlist)), []


def _looks_like_explicit_path(value: str) -> bool:
    return "/" in value or Path(value).suffix != "" or glob.has_magic(value)


def _safe_registry_path(root: Path, value: str) -> tuple[Path | None, str | None]:
    candidate = Path(value)
    if candidate.is_absolute():
        return None, f"absolute artifact path is not allowed: {value}"
    root_resolved = root.resolve()
    resolved = (root / candidate).resolve()
    try:
        resolved.relative_to(root_resolved)
    except ValueError:
        return None, f"artifact path escapes repository root: {value}"
    return resolved, None


def _expand_artifact_form(
    root: Path, registry: Path, line_no: int, form: str
) -> tuple[list[Path], list[str], list[str]]:
    """Expand one registry form to concrete files without guessing aggregates."""
    notices: list[str] = []
    errors: list[str] = []
    checked, path_error = _safe_registry_path(root, form)
    if path_error:
        return [], notices, [f"{registry}:{line_no}: {path_error}"]
    assert checked is not None

    if glob.has_magic(form):
        matches = sorted(Path(match).resolve() for match in glob.glob(str(root / form), recursive=True))
        if not matches:
            notices.append(f"{registry}:{line_no}: artifact glob matched no files: {form}")
            return [], notices, errors
    elif checked.exists():
        matches = [checked]
    elif _looks_like_explicit_path(form):
        errors.append(f"{registry}:{line_no}: artifact path does not exist: {form}")
        return [], notices, errors
    else:
        notices.append(
            f"{registry}:{line_no}: skipped non-resolving descriptive aggregate '{form}'"
        )
        return [], notices, errors

    files: set[Path] = set()
    root_resolved = root.resolve()
    for match in matches:
        try:
            match.relative_to(root_resolved)
        except ValueError:
            errors.append(f"{registry}:{line_no}: artifact match escapes repository root: {form}")
            continue
        if match.is_file():
            files.add(match)
        elif match.is_dir():
            files.update(path.resolve() for path in match.rglob("*") if path.is_file())
    return sorted(files), notices, errors


def registry_paths(
    registry: Path, root: Path
) -> tuple[list[Path], list[str], list[str], list[str]]:
    """Resolve registry rows, then classify each concrete file by all its rows."""
    try:
        with registry.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle, strict=True)
            if reader.fieldnames is None:
                return [], [], [], [f"{registry}: empty CSV"]
            required = {"artifact", "transfer_class"}
            missing = sorted(required - set(reader.fieldnames))
            if missing:
                return [], [], [], [
                    f"{registry}: missing required column(s): {', '.join(missing)}"
                ]
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as exc:
        return [], [], [], [f"{registry}: cannot read CSV: {exc}"]

    classifications: dict[Path, set[bool]] = {}
    notices: list[str] = []
    errors: list[str] = []
    for line_no, row in enumerate(rows, 2):
        artifact = (row.get("artifact") or "").strip()
        classes = [part.strip() for part in (row.get("transfer_class") or "").split("+")]
        parts = [part.strip() for part in artifact.split(";")]
        if not artifact or any(not part for part in parts):
            errors.append(f"{registry}:{line_no}: empty artifact path")
            continue
        if not classes or any(not item for item in classes):
            errors.append(f"{registry}:{line_no}: empty transfer class")
            continue
        row_contains_t3 = "T3_RESEARCH_ONLY" in classes
        for part in parts:
            files, part_notices, part_errors = _expand_artifact_form(
                root, registry, line_no, part
            )
            notices.extend(part_notices)
            errors.extend(part_errors)
            for path in files:
                classifications.setdefault(path, set()).add(row_contains_t3)

    candidates: list[Path] = []
    research_paths: list[str] = []
    root_resolved = root.resolve()
    for path in sorted(classifications):
        row_kinds = classifications[path]
        relative = path.relative_to(root_resolved).as_posix()
        if row_kinds == {True}:
            research_paths.append(relative)
        else:
            candidates.append(path)
            if row_kinds == {False, True}:
                notices.append(
                    f"{registry}: mixed T3/non-T3 scopes in {relative}; "
                    "findings are file-level review input"
                )

    return candidates, sorted(research_paths), sorted(set(notices)), errors


def _allow_reason(finding: Finding, rules: Sequence[AllowRule]) -> str | None:
    for rule in rules:
        if not fnmatch.fnmatchcase(finding.path, rule.path):
            continue
        if rule.pattern != "*" and rule.pattern != finding.pattern:
            continue
        if rule.line_regex is not None and rule.line_regex.search(finding.text) is None:
            continue
        return rule.reason
    return None


def _research_reference_patterns(
    candidate_path: str, research_paths: Sequence[str]
) -> list[tuple[str, Pattern[str]]]:
    """Build bounded root-relative and explicit relative reference patterns."""
    parent = Path(candidate_path).parent.as_posix()
    start = parent if parent != "." else "."
    spellings: set[str] = set()
    for target in research_paths:
        spellings.add(target)
        relative = os.path.relpath(target, start=start).replace(os.sep, "/")
        spellings.add(relative if relative.startswith("../") else f"./{relative}")

    boundary = r"0-9A-Za-z_./-"
    return [
        (
            spelling,
            re.compile(
                rf"(?<![{boundary}]){re.escape(spelling)}(?![{boundary}])"
            ),
        )
        for spelling in sorted(spellings)
    ]


def scan_files(
    root: Path,
    candidates: Sequence[Path],
    research_paths: Sequence[str],
    config: ScanConfig,
) -> tuple[list[Finding], list[tuple[Finding, str]], list[str]]:
    findings: list[Finding] = []
    allowed: list[tuple[Finding, str]] = []
    errors: list[str] = []
    root_resolved = root.resolve()

    for path in sorted(set(candidate.resolve() for candidate in candidates)):
        try:
            relative = path.relative_to(root_resolved).as_posix()
        except ValueError:
            errors.append(f"candidate path is outside repository root: {path}")
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeError) as exc:
            errors.append(f"{relative}: cannot read UTF-8 text: {exc}")
            continue

        reference_patterns = _research_reference_patterns(relative, research_paths)
        for line_no, text in enumerate(lines, 1):
            line_findings: list[Finding] = []
            for pattern in config.patterns:
                for match in pattern.regex.finditer(text):
                    line_findings.append(
                        Finding(relative, line_no, match.start() + 1, pattern.name, match.group(), text)
                    )
            for _spelling, reference_regex in reference_patterns:
                for match in reference_regex.finditer(text):
                    line_findings.append(
                        Finding(
                            relative,
                            line_no,
                            match.start() + 1,
                            "research_only_reference",
                            match.group(),
                            text,
                        )
                    )

            for finding in sorted(set(line_findings)):
                reason = _allow_reason(finding, config.allowlist)
                if reason is None:
                    findings.append(finding)
                else:
                    allowed.append((finding, reason))

    return sorted(set(findings)), sorted(set(allowed), key=lambda item: item[0]), errors


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."), help="repository root")
    parser.add_argument(
        "--registry",
        type=Path,
        help=(
            "transfer registry used to select candidate paths "
            "(default: docs/PUBLIC_LINEAGE_TRANSFER.csv under --root)"
        ),
    )
    parser.add_argument("--config", type=Path, help="optional JSON pattern/allowlist configuration")
    parser.add_argument("--fail-on-findings", action="store_true")
    parser.add_argument("--show-allowlisted", action="store_true")
    args = parser.parse_args(list(argv) if argv is not None else None)

    config, config_errors = load_config(args.config)
    if config_errors:
        for error in config_errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"ERROR SUMMARY: {len(config_errors)} configuration error(s)", file=sys.stderr)
        return 2
    assert config is not None

    registry = (
        args.registry
        if args.registry is not None
        else args.root / "docs" / "PUBLIC_LINEAGE_TRANSFER.csv"
    )
    candidates, research_paths, notices, registry_errors = registry_paths(
        registry, args.root
    )
    for notice in notices:
        print(f"NOTICE: {notice}")
    if registry_errors:
        for error in registry_errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"ERROR SUMMARY: {len(registry_errors)} registry error(s)", file=sys.stderr)
        return 2

    findings, allowed, scan_errors = scan_files(
        args.root, candidates, research_paths, config
    )
    if scan_errors:
        for error in scan_errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"ERROR SUMMARY: {len(scan_errors)} scan error(s)", file=sys.stderr)
        return 2

    for finding in findings:
        print(
            f"FINDING: {finding.path}:{finding.line}:{finding.column}: "
            f"{finding.pattern}: {finding.match}"
        )
    if args.show_allowlisted:
        for finding, reason in allowed:
            print(
                f"ALLOWLISTED: {finding.path}:{finding.line}:{finding.column}: "
                f"{finding.pattern}: {finding.match} ({reason})"
            )
    print(
        f"SUMMARY: {len(candidates)} file(s); {len(findings)} finding(s); "
        f"{len(allowed)} allowlisted exception(s); 0 error(s)"
    )
    if findings and args.fail_on_findings:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
