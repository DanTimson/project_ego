#!/usr/bin/env python3
"""Prepare ignored tactical assets from EGOgrabber exports.

This tool deliberately does not parse DAT.  It validates EGOgrabber version-1
manifests, optionally invokes an explicitly supplied EGOgrabber executable, and
writes a deterministic Project EGO local index.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
import os
from pathlib import Path, PurePosixPath
import re
import struct
import subprocess
import sys
from typing import Any, Iterable


DEFAULT_OUTPUT = Path(".local/eador_assets/index.json")
ARCHIVE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
WINDOWS_ABSOLUTE_RE = re.compile(r"^[A-Za-z]:/")


class AssetPreparationError(ValueError):
    """An external manifest or requested layout is unsafe or malformed."""


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise AssetPreparationError(f"duplicate JSON key: {key!r}")
        result[key] = value
    return result


def load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as stream:
            value = json.load(stream, object_pairs_hook=_unique_object)
    except AssetPreparationError:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise AssetPreparationError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise AssetPreparationError(f"JSON root must be an object: {path}")
    return value


def normalize_relative_path(raw: Any, label: str = "path") -> str:
    if not isinstance(raw, str) or not raw or "\x00" in raw:
        raise AssetPreparationError(f"{label} must be a non-empty string")
    normalized = raw.replace("\\", "/")
    if normalized.startswith("/") or WINDOWS_ABSOLUTE_RE.match(normalized):
        raise AssetPreparationError(f"{label} must be relative: {raw!r}")
    parts = PurePosixPath(normalized).parts
    if not parts or any(part in ("", ".", "..") for part in parts):
        raise AssetPreparationError(f"{label} contains traversal: {raw!r}")
    return "/".join(parts)


def validate_archive_name(archive: str) -> str:
    if not ARCHIVE_RE.fullmatch(archive):
        raise AssetPreparationError(f"invalid archive namespace: {archive!r}")
    return archive


def _inside(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def read_export(archive: str, export_dir: Path, index_root: Path) -> list[tuple[str, dict[str, str]]]:
    archive = validate_archive_name(archive)
    export_dir = export_dir.resolve()
    index_root = index_root.resolve()
    if not export_dir.is_dir():
        raise AssetPreparationError(f"export directory is missing: {export_dir}")
    if not _inside(export_dir, index_root):
        raise AssetPreparationError(
            f"export {export_dir} is outside index root {index_root}; "
            "use an explicit index beside/above the exports"
        )
    manifest_path = export_dir / "manifest.json"
    manifest = load_json(manifest_path)
    if manifest.get("version") != 1:
        raise AssetPreparationError(f"unsupported manifest version in {manifest_path}")
    if "root" not in manifest or not isinstance(manifest["root"], str) or not manifest["root"]:
        raise AssetPreparationError(f"manifest root is missing or malformed: {manifest_path}")
    assets = manifest.get("assets")
    if not isinstance(assets, list):
        raise AssetPreparationError(f"manifest assets must be an array: {manifest_path}")

    seen_ids: set[str] = set()
    prepared: list[tuple[str, dict[str, str]]] = []
    for position, entry in enumerate(assets):
        if not isinstance(entry, dict):
            raise AssetPreparationError(f"asset {position} in {manifest_path} must be an object")
        source_id = entry.get("id")
        asset_type = entry.get("type")
        if not isinstance(source_id, str) or not source_id or ":" in source_id or any(
            ord(char) < 32 for char in source_id
        ):
            raise AssetPreparationError(f"asset {position} has an invalid id")
        if source_id in seen_ids:
            raise AssetPreparationError(
                f"duplicate asset id {source_id!r} in archive {archive!r}"
            )
        seen_ids.add(source_id)
        if asset_type not in ("image", "raw"):
            raise AssetPreparationError(
                f"asset {archive}:{source_id} has unsupported type {asset_type!r}"
            )
        relative = normalize_relative_path(entry.get("path"), "asset path")
        source_path = (export_dir / relative).resolve()
        if not _inside(source_path, export_dir):
            raise AssetPreparationError(f"asset escapes export root: {archive}:{source_id}")
        if not source_path.is_file():
            raise AssetPreparationError(f"asset file is missing: {source_path}")
        runtime_relative = normalize_relative_path(
            source_path.relative_to(index_root).as_posix(), "index asset path"
        )
        logical_key = f"{archive}:{source_id}"
        prepared.append(
            (
                logical_key,
                {
                    "archive": archive,
                    "source_id": source_id,
                    "type": asset_type,
                    "path": runtime_relative,
                },
            )
        )
    return prepared


def build_index(exports: Iterable[tuple[str, Path]], output: Path) -> dict[str, Any]:
    output = output.resolve()
    index_root = output.parent
    merged: dict[str, dict[str, str]] = {}
    for archive, export_dir in exports:
        for logical_key, entry in read_export(archive, export_dir, index_root):
            if logical_key in merged:
                raise AssetPreparationError(f"duplicate logical asset key: {logical_key}")
            merged[logical_key] = entry
    assets = []
    for key in sorted(merged):
        entry = {"key": key}
        entry.update(merged[key])
        assets.append(entry)
    return {"version": 1, "assets": assets}


def read_bmp_dimensions(path: Path) -> tuple[int, int] | None:
    """Read dimensions from an exported BMP without adding an image dependency."""
    try:
        header = path.read_bytes()[:26]
    except OSError:
        return None
    if len(header) < 26 or header[:2] != b"BM":
        return None
    width, height = struct.unpack_from("<ii", header, 18)
    if width <= 0 or height == 0:
        return None
    return width, abs(height)


def build_observation_report(index: dict[str, Any], output: Path) -> dict[str, Any]:
    """Summarize local exports; callers decide whether and where to retain it."""
    root = output.resolve().parent
    grouped: dict[str, dict[str, Any]] = {}
    for entry in index["assets"]:
        archive = entry["archive"]
        group = grouped.setdefault(
            archive, {"objects": 0, "images": 0, "raw": 0, "dimensions": Counter()}
        )
        group["objects"] += 1
        group["images" if entry["type"] == "image" else "raw"] += 1
        if entry["type"] == "image":
            dimensions = read_bmp_dimensions(root / entry["path"])
            if dimensions is not None:
                group["dimensions"][f"{dimensions[0]}x{dimensions[1]}"] += 1
    archives: list[dict[str, Any]] = []
    for archive in sorted(grouped):
        group = grouped[archive]
        dimension_rows = [
            {"size": size, "count": count}
            for size, count in sorted(group["dimensions"].items())
        ]
        archives.append(
            {
                "archive": archive,
                "objects": group["objects"],
                "images": group["images"],
                "raw": group["raw"],
                "dimensions": dimension_rows,
            }
        )
    return {"version": 1, "archives": archives}


def write_index(index: dict[str, Any], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")
    temporary.write_text(
        json.dumps(index, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(output)


def parse_assignment(raw: str, option: str) -> tuple[str, Path]:
    if "=" not in raw:
        raise AssetPreparationError(f"{option} requires ARCHIVE=PATH")
    archive, path = raw.split("=", 1)
    validate_archive_name(archive)
    if not path:
        raise AssetPreparationError(f"{option} path is empty")
    return archive, Path(path)


def invoke_egograbber(binary: Path, archive: str, dat_path: Path, export_dir: Path) -> None:
    if not binary.is_file():
        raise AssetPreparationError(f"EGOgrabber executable is missing: {binary}")
    if not dat_path.is_file():
        raise AssetPreparationError(f"DAT file is missing: {dat_path}")
    export_dir.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            [str(binary.resolve()), "extract", str(dat_path.resolve()), str(export_dir.resolve())],
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise AssetPreparationError(f"EGOgrabber extraction failed for {dat_path}: {exc}") from exc


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--export", action="append", default=[], metavar="ARCHIVE=DIR",
        help="consume an existing EGOgrabber export (repeatable)",
    )
    parser.add_argument(
        "--dat", action="append", default=[], metavar="ARCHIVE=FILE",
        help="extract an explicitly supplied DAT with --egograbber (repeatable)",
    )
    parser.add_argument("--egograbber", type=Path, help="explicit EGOgrabber executable")
    parser.add_argument(
        "--output", type=Path, default=DEFAULT_OUTPUT,
        help=f"index destination (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--report", action="store_true",
        help="print a local JSON archive/dimension observation report",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = make_parser().parse_args(argv)
    try:
        exports = [parse_assignment(value, "--export") for value in args.export]
        dat_inputs = [parse_assignment(value, "--dat") for value in args.dat]
        if not exports and not dat_inputs:
            raise AssetPreparationError("provide at least one --export or --dat")
        if dat_inputs and args.egograbber is None:
            raise AssetPreparationError("--dat requires --egograbber")
        output = args.output.resolve()
        for archive, dat_path in dat_inputs:
            export_dir = output.parent / "exports" / archive
            invoke_egograbber(args.egograbber, archive, dat_path, export_dir)
            exports.append((archive, export_dir))
        index = build_index(exports, output)
        write_index(index, output)
        image_count = sum(entry["type"] == "image" for entry in index["assets"])
        print(f"Prepared {len(index['assets'])} assets ({image_count} images) in {output}")
        if args.report:
            print(json.dumps(build_observation_report(index, output), indent=2, sort_keys=True))
        return 0
    except AssetPreparationError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
