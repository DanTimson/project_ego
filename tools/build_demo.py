#!/usr/bin/env python3
"""Build the public or private Project EGO Windows milestone demo.

Exports always come from a clean ``git archive HEAD`` materialization.  Private
assets are added only after export and never enter the Godot project or PCK.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from typing import Any, Iterable
import zipfile


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
STAGING_ROOT_NAME = ".release_staging"
DIST_NAME = "dist"
PRESET_NAME = "Windows Desktop x86-64"
EXE_NAME = "Project EGO.exe"
PCK_NAME = "Project EGO.pck"
INDEX_NAME = "index.json"
MAPPING_NAME = "mapping.json"
ASSET_CATEGORIES = ("units", "shadows", "portraits", "terrain", "decorations", "ui")
IDENTITY_CATEGORIES = ("units", "shadows", "portraits")
NAMED_CATEGORIES = ("terrain", "decorations", "ui")
IMAGE_SUFFIXES = {".bmp", ".png", ".jpg", ".jpeg", ".webp"}
LOGICAL_KEY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*:[^:]+$")
NAMED_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]*$")
CANONICAL_UNIT_ID_RE = re.compile(r"^[a-z0-9_]+:unit/[0-9]+$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40,64}$")
WINDOWS_ABSOLUTE_RE = re.compile(r"^[A-Za-z]:[/\\]")
LEAK_PATTERNS = (
    re.compile(rb"/(?:home|Users)/[^/\x00\r\n]+/"),
    re.compile(rb"/mnt/[a-zA-Z]/"),
    re.compile(rb"/(?:tmp|opt|var/tmp)/[^\x00\r\n]+"),
    re.compile(rb"[A-Za-z]:[\\/]Users[\\/][^\\/\x00\r\n]+[\\/]", re.IGNORECASE),
)


class BuildError(RuntimeError):
    """A fail-closed release precondition or validation failure."""


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise BuildError(f"duplicate JSON key: {key!r}")
        result[key] = value
    return result


def load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as stream:
            value = json.load(stream, object_pairs_hook=_unique_object)
    except BuildError:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise BuildError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise BuildError(f"JSON root must be an object: {path}")
    return value


def require_keys(value: dict[str, Any], expected: set[str], label: str) -> None:
    unknown = set(value) - expected
    missing = expected - set(value)
    if unknown or missing:
        details = []
        if missing:
            details.append(f"missing {sorted(missing)}")
        if unknown:
            details.append(f"unknown {sorted(unknown)}")
        raise BuildError(f"{label} has " + " and ".join(details))


def normalize_relative_path(raw: Any, label: str) -> str:
    if not isinstance(raw, str) or not raw or "\x00" in raw:
        raise BuildError(f"{label} must be a non-empty string")
    normalized = raw.replace("\\", "/")
    if normalized.startswith("/") or WINDOWS_ABSOLUTE_RE.match(normalized):
        raise BuildError(f"{label} must be relative: {raw!r}")
    parts = normalized.split("/")
    if not parts or any(part in ("", ".", "..") for part in parts):
        raise BuildError(f"{label} contains traversal or empty components: {raw!r}")
    return "/".join(parts)


def _inside(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _logical_key(raw: Any, label: str) -> str:
    if not isinstance(raw, str) or not LOGICAL_KEY_RE.fullmatch(raw):
        raise BuildError(f"{label} is not a valid logical asset key: {raw!r}")
    archive, source_id = raw.split(":", 1)
    normalized_source = normalize_relative_path(source_id, f"{label} source id")
    if normalized_source != source_id:
        raise BuildError(f"{label} source id must use a normalized relative path")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", archive):
        raise BuildError(f"{label} has an invalid archive namespace")
    return raw


def _mapping_entries(value: Any, label: str, canonical: bool = False) -> set[str]:
    if not isinstance(value, list):
        raise BuildError(f"{label} must be an array")
    references: set[str] = set()
    identities: set[str] = set()
    identity_pattern = CANONICAL_UNIT_ID_RE if canonical else NAMED_ID_RE
    for position, item in enumerate(value):
        if not isinstance(item, dict):
            raise BuildError(f"{label}[{position}] must be an object")
        require_keys(item, {"id", "asset"}, f"{label}[{position}]")
        identity = item["id"]
        if not isinstance(identity, str) or not identity_pattern.fullmatch(identity):
            kind = "canonical unit" if canonical else "named presentation"
            raise BuildError(f"{label}[{position}] has an invalid {kind} id")
        if identity in identities:
            raise BuildError(f"{label} duplicates id {identity!r}")
        identities.add(identity)
        references.add(_logical_key(item["asset"], f"{label}[{position}].asset"))
    return references


def mapping_references(mapping: dict[str, Any]) -> set[str]:
    version = mapping.get("version")
    references: set[str] = set()
    if version == 1:
        require_keys(mapping, {"version", "content", "instances"}, "mapping")
        references |= _mapping_entries(mapping["content"], "mapping.content", canonical=True)
        references |= _mapping_entries(mapping["instances"], "mapping.instances")
        return references
    if version != 2:
        raise BuildError(f"unsupported mapping version: {version!r}")
    require_keys(mapping, {"version", *ASSET_CATEGORIES}, "mapping")
    for category in IDENTITY_CATEGORIES:
        section = mapping[category]
        if not isinstance(section, dict):
            raise BuildError(f"mapping.{category} must be an object")
        require_keys(section, {"content", "instances"}, f"mapping.{category}")
        references |= _mapping_entries(
            section["content"], f"mapping.{category}.content", canonical=True
        )
        references |= _mapping_entries(section["instances"], f"mapping.{category}.instances")
    for category in NAMED_CATEGORIES:
        references |= _mapping_entries(mapping[category], f"mapping.{category}")
    return references


def load_source_index(asset_root: Path) -> dict[str, dict[str, Any]]:
    index = load_json(asset_root / INDEX_NAME)
    require_keys(index, {"version", "assets"}, "asset index")
    if index["version"] != 1 or not isinstance(index["assets"], list):
        raise BuildError("asset index must be version 1 with an assets array")
    entries: dict[str, dict[str, Any]] = {}
    root = asset_root.resolve(strict=True)
    for position, item in enumerate(index["assets"]):
        if not isinstance(item, dict):
            raise BuildError(f"asset index entry {position} must be an object")
        require_keys(item, {"key", "archive", "source_id", "type", "path"},
                     f"asset index entry {position}")
        key = _logical_key(item["key"], f"asset index entry {position}.key")
        archive, source_id = key.split(":", 1)
        if item["archive"] != archive or item["source_id"] != source_id:
            raise BuildError(f"asset index entry {position} has inconsistent identity")
        if key in entries:
            raise BuildError(f"duplicate asset index key: {key}")
        if item["type"] not in ("image", "raw"):
            raise BuildError(f"unsupported asset type for {key}: {item['type']!r}")
        relative = normalize_relative_path(item["path"], f"asset path for {key}")
        source = asset_root / relative
        if source.is_symlink():
            raise BuildError(f"symlink assets are not accepted: {key}")
        try:
            resolved = source.resolve(strict=True)
        except OSError as exc:
            raise BuildError(f"missing referenced asset {key}: {source}") from exc
        if not _inside(resolved, root) or not resolved.is_file():
            raise BuildError(f"asset escapes local root or is not a file: {key}")
        copied = dict(item)
        copied["_source"] = resolved
        entries[key] = copied
    return entries


def prepare_minimal_asset_bundle(asset_root: Path, destination: Path) -> set[str]:
    if asset_root.is_symlink() or not asset_root.is_dir():
        raise BuildError(f"asset root is missing or is a symlink: {asset_root}")
    mapping = load_json(asset_root / MAPPING_NAME)
    references = mapping_references(mapping)
    if not references:
        raise BuildError("mapping references no playable presentation assets")
    entries = load_source_index(asset_root)
    missing = references - set(entries)
    if missing:
        raise BuildError(f"mapping references missing assets: {sorted(missing)}")
    destination.mkdir(parents=True, exist_ok=False)
    runtime_assets: list[dict[str, Any]] = []
    expected_files = {INDEX_NAME, MAPPING_NAME}
    for position, key in enumerate(sorted(references)):
        item = entries[key]
        if item["type"] != "image":
            raise BuildError(f"mapped asset is not a supported image: {key}")
        source: Path = item["_source"]
        suffix = source.suffix.lower()
        if suffix not in IMAGE_SUFFIXES:
            raise BuildError(f"unsupported image extension for {key}: {suffix}")
        relative = f"assets/{position:04d}{suffix}"
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        expected_files.add(relative)
        runtime_assets.append({
            "key": key,
            "archive": item["archive"],
            "source_id": item["source_id"],
            "type": "image",
            "path": relative,
        })
    (destination / INDEX_NAME).write_text(
        json.dumps({"version": 1, "assets": runtime_assets}, ensure_ascii=False,
                   indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (destination / MAPPING_NAME).write_text(
        json.dumps(mapping, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8")
    verify_runtime_asset_bundle(destination, expected_files)
    return expected_files


def verify_runtime_asset_bundle(root: Path, expected_files: set[str] | None = None) -> None:
    mapping = load_json(root / MAPPING_NAME)
    references = mapping_references(mapping)
    entries = load_source_index(root)
    if references != set(entries):
        raise BuildError("private runtime index is not the exact mapping-reference closure")
    actual = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*") if path.is_file()
    }
    indexed = {INDEX_NAME, MAPPING_NAME} | {
        normalize_relative_path(item["path"], "runtime asset path")
        for item in entries.values()
    }
    if actual != indexed:
        raise BuildError(f"private runtime bundle contains unreferenced files: {sorted(actual - indexed)}")
    if expected_files is not None and actual != expected_files:
        raise BuildError("private runtime bundle differs from its constructed closure")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run_checked(command: list[str], cwd: Path, timeout: int = 300) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise BuildError(f"command failed to run: {command[0]}: {exc}") from exc
    if result.returncode != 0:
        raise BuildError(f"command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}")
    return result


def git_output(repo: Path, *arguments: str) -> str:
    return run_checked(["git", *arguments], repo).stdout.strip()


def require_clean_tracked_head(repo: Path) -> str:
    head = git_output(repo, "rev-parse", "--verify", "HEAD")
    changes = git_output(repo, "status", "--porcelain=v1", "--untracked-files=no")
    if changes:
        raise BuildError(
            "tracked worktree/index changes make HEAD ambiguous; commit or restore them "
            "before release building (Git state was not modified):\n" + changes
        )
    return head


def materialize_tracked_head(repo: Path, destination: Path, head: str) -> None:
    if destination.exists():
        raise BuildError(f"tracked staging destination already exists: {destination}")
    result = subprocess.run(["git", "archive", "--format=tar", head], cwd=repo,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode != 0:
        raise BuildError(f"git archive failed: {result.stderr.decode(errors='replace')}")
    destination.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(result.stdout), mode="r:") as archive:
        for member in archive.getmembers():
            relative = normalize_relative_path(member.name.rstrip("/"), "git archive member")
            target = destination / relative
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                source = archive.extractfile(member)
                if source is None:
                    raise BuildError(f"cannot read git archive member: {relative}")
                target.write_bytes(source.read())
                target.chmod(0o755 if member.mode & 0o111 else 0o644)
            else:
                raise BuildError(f"git archive contains unsupported link/type: {relative}")
    after = require_clean_tracked_head(repo)
    if after != head:
        raise BuildError("Git HEAD changed while the tracked-only staging tree was built")
    forbidden = (".local/", "local_assets/", "dist/", ".release_staging/", ".git/")
    staged = [path.relative_to(destination).as_posix() for path in destination.rglob("*")]
    if any(path == prefix[:-1] or path.startswith(prefix) for path in staged for prefix in forbidden):
        raise BuildError("tracked HEAD unexpectedly contains release/local generated content")
    if any(Path(path).suffix.lower() == ".dat" for path in staged):
        raise BuildError("tracked HEAD unexpectedly contains a DAT file")


def locate_godot(requested: str | None = None) -> str:
    candidate = requested or os.environ.get("GODOT_BIN")
    if candidate:
        resolved = shutil.which(candidate)
        if resolved:
            return resolved
        path = Path(candidate).expanduser()
        if path.is_file():
            return str(path.resolve())
        raise BuildError(f"Godot executable not found: {candidate}")
    for name in ("godot-ci", "godot"):
        resolved = shutil.which(name)
        if resolved:
            return resolved
    raise BuildError("Godot was not found (set GODOT_BIN or use --godot)")


def godot_version(godot: str) -> str:
    output = run_checked([godot, "--version"], REPOSITORY_ROOT, timeout=60).stdout.strip()
    if not output:
        raise BuildError("Godot did not report a version")
    return output.splitlines()[0].strip()


def windows_accessible_path(path: Path) -> str:
    if os.name == "nt":
        return str(path)
    wslpath = shutil.which("wslpath")
    if wslpath and str(path.resolve()).startswith("/mnt/"):
        return run_checked([wslpath, "-w", str(path.resolve())], REPOSITORY_ROOT).stdout.strip()
    return str(path.resolve())


def export_engine(godot: str, source: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    executable = output / EXE_NAME
    command = [godot, "--headless", "--path", ".", "--export-release",
               PRESET_NAME, windows_accessible_path(executable)]
    result = run_checked(command, source, timeout=600)
    for marker in ("Parse Error:", "Compile Error:", "SCRIPT ERROR:"):
        if marker.lower() in result.stdout.lower():
            raise BuildError(f"Godot export log contains {marker}\n{result.stdout}")
    pck = output / PCK_NAME
    if not executable.is_file() or executable.stat().st_size == 0:
        raise BuildError(f"Godot did not create {executable}")
    if not pck.is_file() or pck.stat().st_size == 0:
        raise BuildError("Godot did not create the required external Project EGO.pck")


def engine_cache(repo: Path, head: str, version: str) -> Path:
    safe_version = re.sub(r"[^A-Za-z0-9_.-]+", "-", version)
    return repo / DIST_NAME / ".engine-cache" / f"{head}-{safe_version}"


def validate_or_create_engine_cache(repo: Path, head: str, version: str,
                                    godot: str, source_stage: Path) -> Path:
    cache = engine_cache(repo, head, version)
    manifest_path = cache / "engine.json"
    if cache.exists():
        try:
            manifest = load_json(manifest_path)
            require_keys(manifest, {"head", "godot_version", "exe_sha256", "pck_sha256"},
                         "engine cache manifest")
            if (manifest["head"] == head and manifest["godot_version"] == version
                    and manifest["exe_sha256"] == sha256_file(cache / EXE_NAME)
                    and manifest["pck_sha256"] == sha256_file(cache / PCK_NAME)):
                return cache
        except (BuildError, OSError):
            pass
        shutil.rmtree(cache)
    export_output = source_stage.parent / "engine-export"
    export_engine(godot, source_stage, export_output)
    cache.mkdir(parents=True)
    shutil.copyfile(export_output / EXE_NAME, cache / EXE_NAME)
    shutil.copyfile(export_output / PCK_NAME, cache / PCK_NAME)
    manifest = {
        "head": head,
        "godot_version": version,
        "exe_sha256": sha256_file(cache / EXE_NAME),
        "pck_sha256": sha256_file(cache / PCK_NAME),
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                             encoding="utf-8")
    return cache


def build_timestamp() -> str:
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    try:
        moment = datetime.fromtimestamp(int(epoch), timezone.utc) if epoch is not None \
            else datetime.now(timezone.utc)
    except (ValueError, OverflowError, OSError) as exc:
        raise BuildError("SOURCE_DATE_EPOCH must be a valid Unix timestamp") from exc
    return moment.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def readme_text(mode: str) -> str:
    controls = """Controls
--------
Mouse: select units and click highlighted move/melee/ranged targets.
R: ranged mode.  Space: pass the side phase.  Escape: cancel selection.
"""
    if mode == "private":
        return f"""Project EGO — Private Tactical Prototype

1. Extract this ZIP.
2. Run "Project EGO.exe".
3. Choose "Play Demo".

No installation or configuration is required. Keep the local_assets directory
beside the executable.

{controls}"""
    return f"""Project EGO — Public Tactical Prototype

1. Extract this ZIP.
2. Run "Project EGO.exe".
3. Choose "Play Demo".

This public package intentionally contains only project-authored/fallback
presentation. Original artwork is not included. Developers may prepare their
own optional local asset root separately; no local assets are required.

{controls}"""


def write_package_documents(root: Path, metadata: dict[str, str]) -> None:
    (root / "BUILD.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    lines = [f"{key}: {value}" for key, value in metadata.items()]
    (root / "BUILD.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (root / "demo-info.txt").write_text(
        "Project EGO\nTactical Prototype — Milestone %s\nMode: %s\nCommit: %s\n" %
        (metadata["milestone"], metadata["mode"], metadata["commit"]),
        encoding="utf-8")
    (root / "README.txt").write_text(readme_text(metadata["mode"]), encoding="utf-8")


def _forbidden_name(relative: str) -> str | None:
    lowered = relative.lower()
    parts = PurePosixPath(lowered).parts
    if Path(lowered).suffix == ".dat":
        return "DAT file"
    if ".local" in parts:
        return ".local tree"
    if any(part in (".git", ".release_staging", "dist") for part in parts):
        return "repository/release staging material"
    if "egograbber" in lowered:
        return "EGOgrabber material"
    if any(part in ("manifest.json", "mapping-manifest.json") for part in parts):
        return "extraction manifest"
    return None


def validate_build_metadata(path: Path, mode: str) -> None:
    metadata = load_json(path)
    expected = {"project", "milestone", "commit", "godot_version", "mode", "built_at"}
    require_keys(metadata, expected, "BUILD.json")
    if metadata["project"] != "Project EGO" or metadata["mode"] != mode:
        raise BuildError("BUILD.json project or mode does not match the package")
    for key in ("milestone", "godot_version", "built_at"):
        if not isinstance(metadata[key], str) or not metadata[key]:
            raise BuildError(f"BUILD.json {key} must be a non-empty string")
    if not isinstance(metadata["commit"], str) or not COMMIT_RE.fullmatch(metadata["commit"]):
        raise BuildError("BUILD.json commit is not an exact hexadecimal Git object id")


def scan_release_tree(root: Path, mode: str) -> list[str]:
    if mode not in ("public", "private"):
        raise BuildError(f"unsupported scan mode: {mode}")
    required = {EXE_NAME, PCK_NAME, "README.txt", "BUILD.json", "BUILD.txt", "demo-info.txt"}
    missing = [name for name in sorted(required) if not (root / name).is_file()]
    if missing:
        raise BuildError(f"release package is missing files: {missing}")
    validate_build_metadata(root / "BUILD.json", mode)
    local = root / "local_assets"
    if mode == "public" and local.exists():
        raise BuildError("public package contains local_assets")
    if mode == "private":
        if not local.is_dir():
            raise BuildError("private package has no local_assets directory")
        verify_runtime_asset_bundle(local)
    files = sorted(path for path in root.rglob("*") if path.is_file())
    inventory: list[str] = []
    specific_leaks = {
        str(REPOSITORY_ROOT.resolve()).encode(),
        str(Path.home().resolve()).encode(),
    }
    username = Path.home().name
    if username and username.lower() not in {"root", "home"}:
        specific_leaks.add(username.encode())
    dat_root = os.environ.get("EADOR_DAT_ROOT")
    if dat_root:
        specific_leaks.add(dat_root.encode())
    for path in files:
        relative = path.relative_to(root).as_posix()
        inventory.append(relative)
        reason = _forbidden_name(relative)
        if reason:
            raise BuildError(f"release package contains forbidden {reason}: {relative}")
        data = path.read_bytes()
        if any(leak and leak in data for leak in specific_leaks):
            raise BuildError(f"machine-specific path leaked into {relative}")
        if path.suffix.lower() in {".json", ".txt", ".md", ".cfg"}:
            if b"egograbber" in data.lower():
                raise BuildError(f"EGOgrabber material leaked into {relative}")
            if any(pattern.search(data) for pattern in LEAK_PATTERNS):
                raise BuildError(f"absolute developer path leaked into {relative}")
    return inventory


def write_zip(source: Path, output: Path, timestamp: str) -> None:
    moment = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    year = max(1980, moment.year)
    date_time = (year, moment.month, moment.day, moment.hour, moment.minute,
                 moment.second - moment.second % 2)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED,
                         compresslevel=9) as archive:
        for path in sorted(source.rglob("*"), key=lambda item: item.relative_to(source).as_posix()):
            if not path.is_file():
                continue
            relative = path.relative_to(source).as_posix()
            info = zipfile.ZipInfo(relative, date_time)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o755 if path.name == EXE_NAME else 0o644) << 16
            archive.writestr(info, path.read_bytes(), compresslevel=9)
    temporary.replace(output)


def inspect_zip(path: Path) -> list[str]:
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            normalized = [normalize_relative_path(name.rstrip("/"), "ZIP member") for name in names]
            if len(normalized) != len(set(normalized)):
                raise BuildError("ZIP contains duplicate member names")
            bad = archive.testzip()
            if bad:
                raise BuildError(f"ZIP CRC validation failed: {bad}")
            return normalized
    except (OSError, zipfile.BadZipFile) as exc:
        raise BuildError(f"cannot validate release ZIP {path}: {exc}") from exc


def runtime_hashes(root: Path) -> dict[str, str]:
    return {EXE_NAME: sha256_file(root / EXE_NAME), PCK_NAME: sha256_file(root / PCK_NAME)}


def compare_runtime_with_zip(root: Path, counterpart: Path) -> None:
    if not counterpart.is_file():
        return
    with zipfile.ZipFile(counterpart) as archive:
        for name, digest in runtime_hashes(root).items():
            try:
                other = hashlib.sha256(archive.read(name)).hexdigest()
            except KeyError as exc:
                raise BuildError(f"counterpart package lacks {name}: {counterpart}") from exc
            if other != digest:
                raise BuildError(f"public/private runtime identity mismatch for {name}")


def smoke_exported_executable(package: Path, mode: str) -> str:
    package = package.resolve()
    executable = package / EXE_NAME
    try:
        result = subprocess.run(
            [str(executable), "--headless", "--", "--demo-smoke"], cwd=package,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            timeout=90, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise BuildError(f"exported executable smoke could not run: {exc}") from exc
    expected_assets = (
        "loaded local tactical visual mapping"
        if mode == "private" else "local tactical asset index absent; using placeholders"
    )
    if (result.returncode != 0 or "DEMO_SMOKE PASS" not in result.stdout
            or expected_assets not in result.stdout):
        raise BuildError(
            f"exported {mode} executable smoke failed ({result.returncode}); "
            f"expected asset marker {expected_assets!r}:\n{result.stdout}"
        )
    return result.stdout


def build(args: argparse.Namespace) -> tuple[Path, list[str], dict[str, str], str]:
    repo = REPOSITORY_ROOT
    head = require_clean_tracked_head(repo)
    godot = locate_godot(args.godot)
    version = godot_version(godot)
    timestamp = build_timestamp()
    staging_root = repo / STAGING_ROOT_NAME
    if staging_root.exists():
        shutil.rmtree(staging_root)
    source_stage = staging_root / "source"
    package = staging_root / "package"
    try:
        materialize_tracked_head(repo, source_stage, head)
        cache = validate_or_create_engine_cache(repo, head, version, godot, source_stage)
        package.mkdir(parents=True)
        shutil.copyfile(cache / EXE_NAME, package / EXE_NAME)
        shutil.copyfile(cache / PCK_NAME, package / PCK_NAME)
        if args.mode == "private":
            if args.asset_root is None:
                raise BuildError("private mode requires --asset-root")
            prepare_minimal_asset_bundle(args.asset_root.resolve(), package / "local_assets")
        metadata = {
            "project": "Project EGO",
            "milestone": args.milestone,
            "commit": head,
            "godot_version": version,
            "mode": args.mode,
            "built_at": timestamp,
        }
        write_package_documents(package, metadata)
        inventory = scan_release_tree(package, args.mode)
        counterpart_name = (
            f"Project-EGO-Milestone-{args.milestone}-private-Windows-x86_64.zip"
            if args.mode == "public" else
            f"Project-EGO-Milestone-{args.milestone}-Windows-x86_64.zip"
        )
        counterpart_mode = "private" if args.mode == "public" else "public"
        compare_runtime_with_zip(package, repo / DIST_NAME / counterpart_mode / counterpart_name)
        smoke = "skipped by explicit option"
        if not args.skip_runtime_smoke:
            smoke = smoke_exported_executable(package, args.mode)
        filename = (
            f"Project-EGO-Milestone-{args.milestone}-Windows-x86_64.zip"
            if args.mode == "public" else
            f"Project-EGO-Milestone-{args.milestone}-private-Windows-x86_64.zip"
        )
        artifact = repo / DIST_NAME / args.mode / filename
        write_zip(package, artifact, timestamp)
        zip_inventory = inspect_zip(artifact)
        if zip_inventory != inventory:
            raise BuildError("ZIP inventory differs from validated package inventory")
        hashes = runtime_hashes(package)
        return artifact, inventory, hashes, smoke
    finally:
        if staging_root.exists():
            shutil.rmtree(staging_root)


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("public", "private"), required=True)
    parser.add_argument("--milestone", required=True,
                        help="milestone label used in metadata and artifact name")
    parser.add_argument("--asset-root", type=Path,
                        help="prepared local index/mapping root (private mode only)")
    parser.add_argument("--godot", help="Godot executable or wrapper override")
    parser.add_argument("--skip-runtime-smoke", action="store_true",
                        help="explicitly skip executable smoke (package tests only)")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = make_parser().parse_args(argv)
    if args.mode == "public" and args.asset_root is not None:
        print("error: public mode refuses --asset-root", file=sys.stderr)
        return 2
    try:
        artifact, inventory, hashes, smoke = build(args)
    except BuildError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    print(f"Artifact: {artifact}")
    print(f"Size: {artifact.stat().st_size} bytes")
    print(f"SHA-256: {sha256_file(artifact)}")
    print("ZIP inventory:")
    for item in inventory:
        print(f"  {item}")
    print(f"Runtime identity: exe={hashes[EXE_NAME]} pck={hashes[PCK_NAME]}")
    print("Executable smoke: " + ("PASS" if "DEMO_SMOKE PASS" in smoke else smoke))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
