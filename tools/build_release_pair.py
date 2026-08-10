#!/usr/bin/env python3
"""Build and verify one official Project EGO public/private release pair."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import sys
import tempfile
from typing import Any
import zipfile

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from tools import build_demo
from tools.build_demo import BuildError, EXE_NAME, PCK_NAME


SCHEMA = "project-ego-release-pair"
SCHEMA_VERSION = 1


def pair_manifest_path(repo: Path, milestone: str) -> Path:
    return repo / build_demo.DIST_NAME / f"Project-EGO-Milestone-{milestone}-release-pair.json"


def _extract_validated_zip(artifact: Path, destination: Path) -> list[str]:
    inventory = build_demo.inspect_zip(artifact)
    destination.mkdir()
    with zipfile.ZipFile(artifact) as archive:
        infos = archive.infolist()
        if len(infos) != len(inventory):
            raise BuildError(f"ZIP inventory changed while reading {artifact}")
        for info, relative in zip(infos, inventory):
            if info.is_dir() or (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise BuildError(f"release ZIP contains a directory or symlink member: {relative}")
            target = destination.joinpath(*relative.split("/"))
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(info))
    return inventory


def _artifact_name(artifact: Path, repo: Path) -> str:
    try:
        return artifact.resolve().relative_to(repo.resolve()).as_posix()
    except ValueError:
        return artifact.name


def verify_release_pair(public_artifact: Path, private_artifact: Path, repo: Path,
                        runtime_smoke: dict[str, bool]) -> dict[str, Any]:
    """Revalidate both ZIPs with the authoritative package scanners."""
    if set(runtime_smoke) != {"public", "private"} or not all(
            value is True for value in runtime_smoke.values()):
        raise BuildError("both public and private runtime smokes must pass")
    missing = [str(path) for path in (public_artifact, private_artifact) if not path.is_file()]
    if missing:
        raise BuildError(f"release pair is incomplete; missing artifacts: {missing}")

    with tempfile.TemporaryDirectory(prefix="project-ego-pair-verify-") as temporary:
        temporary_root = Path(temporary)
        roots = {"public": temporary_root / "public", "private": temporary_root / "private"}
        artifacts = {"public": public_artifact, "private": private_artifact}
        zip_inventories: dict[str, list[str]] = {}
        tree_inventories: dict[str, list[str]] = {}
        metadata: dict[str, dict[str, Any]] = {}
        runtime: dict[str, dict[str, str]] = {}
        for mode in ("public", "private"):
            zip_inventories[mode] = _extract_validated_zip(artifacts[mode], roots[mode])
            tree_inventories[mode] = build_demo.scan_release_tree(roots[mode], mode)
            if zip_inventories[mode] != tree_inventories[mode]:
                raise BuildError(f"{mode} ZIP inventory differs from its validated package tree")
            metadata[mode] = build_demo.load_json(roots[mode] / "BUILD.json")
            runtime[mode] = build_demo.runtime_hashes(roots[mode])

        public_common = {key: value for key, value in metadata["public"].items() if key != "mode"}
        private_common = {key: value for key, value in metadata["private"].items() if key != "mode"}
        if public_common != private_common:
            raise BuildError("public/private BUILD.json metadata differs")
        exe_match = runtime["public"][EXE_NAME] == runtime["private"][EXE_NAME]
        pck_match = runtime["public"][PCK_NAME] == runtime["private"][PCK_NAME]
        if not exe_match or not pck_match:
            changed = EXE_NAME if not exe_match else PCK_NAME
            raise BuildError(f"public/private runtime identity mismatch for {changed}")

        try:
            built_at = str(public_common["built_at"])
            epoch = int(datetime.fromisoformat(built_at.replace("Z", "+00:00")).timestamp())
        except (KeyError, TypeError, ValueError, OverflowError) as exc:
            raise BuildError("release pair has an invalid deterministic built_at timestamp") from exc

        manifest: dict[str, Any] = {
            "schema": SCHEMA,
            "version": SCHEMA_VERSION,
            "project": public_common["project"],
            "milestone": public_common["milestone"],
            "commit": public_common["commit"],
            "godot_version": public_common["godot_version"],
            "built_at": built_at,
            "source_date_epoch": epoch,
            "runtime_identity": {"exe_payloads_match": exe_match, "pck_payloads_match": pck_match},
            "artifacts": {},
        }
        for mode in ("public", "private"):
            validation = ({"fallback_no_local_assets": True} if mode == "public" else
                          {"exact_mapping_reference_closure": True})
            manifest["artifacts"][mode] = {
                "path": _artifact_name(artifacts[mode], repo),
                "size": artifacts[mode].stat().st_size,
                "sha256": build_demo.sha256_file(artifacts[mode]),
                "exe_sha256": runtime[mode][EXE_NAME],
                "pck_sha256": runtime[mode][PCK_NAME],
                "inventory": zip_inventories[mode],
                "validation": validation,
                "runtime_smoke": {"passed": True},
            }
        return manifest


def write_pair_manifest(path: Path, public_artifact: Path, private_artifact: Path,
                        repo: Path, runtime_smoke: dict[str, bool]) -> dict[str, Any]:
    manifest = verify_release_pair(public_artifact, private_artifact, repo, runtime_smoke)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)
    return manifest


def _build_args(args: argparse.Namespace, mode: str) -> argparse.Namespace:
    return argparse.Namespace(
        mode=mode,
        milestone=args.milestone,
        asset_root=args.asset_root if mode == "private" else None,
        godot=args.godot,
        staging_parent=args.staging_parent,
        reproducible=True,
        skip_runtime_smoke=False,
    )


def build_pair(args: argparse.Namespace) -> tuple[Path, dict[str, Any]]:
    repo = build_demo.REPOSITORY_ROOT
    output = pair_manifest_path(repo, args.milestone)
    # A failed new attempt must not leave an older manifest looking successful.
    output.unlink(missing_ok=True)
    public_artifact, _, _, public_smoke = build_demo.build(_build_args(args, "public"))
    private_artifact, _, _, private_smoke = build_demo.build(_build_args(args, "private"))
    smoke = {
        "public": "DEMO_SMOKE PASS" in public_smoke,
        "private": "DEMO_SMOKE PASS" in private_smoke,
    }
    manifest = write_pair_manifest(
        output, public_artifact, private_artifact, repo, smoke
    )
    return output, manifest


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--milestone", required=True)
    parser.add_argument("--asset-root", type=Path, required=True,
                        help="prepared private local index/mapping root")
    parser.add_argument("--godot", help="Godot executable or wrapper override")
    parser.add_argument("--staging-parent", type=Path,
                        help="existing parent for uniquely owned temporary release directories")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = make_parser().parse_args(argv)
    try:
        path, manifest = build_pair(args)
    except BuildError as exc:
        print(f"error: {exc}")
        return 2
    print(f"Pair manifest: {path}")
    print(f"Public SHA-256: {manifest['artifacts']['public']['sha256']}")
    print(f"Private SHA-256: {manifest['artifacts']['private']['sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
