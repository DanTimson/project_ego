from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import zipfile

import pytest


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from tools.build_demo import (
    BuildError,
    EXE_NAME,
    PCK_NAME,
    compare_runtime_with_zip,
    inspect_zip,
    load_json,
    build_timestamp,
    mapping_references,
    normalize_relative_path,
    owned_staging_directory,
    prepare_minimal_asset_bundle,
    release_epoch,
    runtime_hashes,
    scan_release_tree,
    verify_runtime_asset_bundle,
    write_package_documents,
    write_zip,
)


def mapping(*assets: str) -> dict:
    values = list(assets)
    unit = [{"id": "demo-unit", "asset": values[0]}] if values else []
    named = [
        {"id": f"slot-{position}", "asset": asset}
        for position, asset in enumerate(values[1:])
    ]
    return {
        "version": 2,
        "units": {"content": [], "instances": unit},
        "shadows": {"content": [], "instances": []},
        "portraits": {"content": [], "instances": []},
        "terrain": named,
        "decorations": [],
        "ui": [],
    }


def make_asset_root(root: Path) -> Path:
    root.mkdir()
    files = root / "prepared"
    files.mkdir()
    for name, body in (("unit.png", b"unit"), ("terrain.bmp", b"terrain"),
                       ("unused.png", b"unused")):
        (files / name).write_bytes(body)
    entries = []
    for key, name in (("Synthetic:Unit", "unit.png"),
                      ("Synthetic:Terrain", "terrain.bmp"),
                      ("Synthetic:Unused", "unused.png")):
        archive, source_id = key.split(":")
        entries.append({
            "key": key, "archive": archive, "source_id": source_id,
            "type": "image", "path": f"prepared/{name}",
        })
    (root / "index.json").write_text(
        json.dumps({"version": 1, "assets": entries}), encoding="utf-8")
    (root / "mapping.json").write_text(
        json.dumps(mapping("Synthetic:Unit", "Synthetic:Terrain")), encoding="utf-8")
    return root


def metadata(mode: str) -> dict[str, str]:
    return {
        "project": "Project EGO", "milestone": "0.2", "commit": "a" * 40,
        "godot_version": "4.3.test", "mode": mode,
        "built_at": "2026-01-02T03:04:05Z",
    }


def make_package(root: Path, mode: str, asset_root: Path | None = None) -> Path:
    root.mkdir()
    (root / EXE_NAME).write_bytes(b"identical engine")
    (root / PCK_NAME).write_bytes(b"identical pck")
    write_package_documents(root, metadata(mode))
    if mode == "private":
        assert asset_root is not None
        prepare_minimal_asset_bundle(asset_root, root / "local_assets")
    return root


def test_mapping_schema_collects_all_category_references():
    document = mapping("Synthetic:Unit", "Synthetic:Terrain")
    document["shadows"]["instances"] = [
        {"id": "demo-unit", "asset": "Synthetic:Shadow"}
    ]
    document["portraits"]["content"] = [
        {"id": "demo:unit/1", "asset": "Synthetic:Portrait"}
    ]
    document["decorations"] = [{"id": "tree", "asset": "Synthetic:Tree"}]
    document["ui"] = [{"id": "panel", "asset": "Synthetic:Panel"}]
    assert mapping_references(document) == {
        "Synthetic:Unit", "Synthetic:Terrain", "Synthetic:Shadow",
        "Synthetic:Portrait", "Synthetic:Tree", "Synthetic:Panel",
    }


def test_mapping_ids_match_runtime_identity_rules():
    document = mapping("Synthetic:Unit")
    document["units"]["content"] = [
        {"id": "genesis:unit/5", "asset": "Synthetic:Unit"}
    ]
    assert mapping_references(document) == {"Synthetic:Unit"}
    document["units"]["content"][0]["id"] = "genesis:ability/5"
    with pytest.raises(BuildError, match="canonical unit"):
        mapping_references(document)
    document = mapping("Synthetic:Unit")
    document["terrain"] = [{"id": "bad id", "asset": "Synthetic:Unit"}]
    with pytest.raises(BuildError, match="named presentation"):
        mapping_references(document)


def test_logical_source_ids_must_be_normalized():
    document = mapping("Synthetic:folder//unit.png")
    with pytest.raises(BuildError, match="empty components|normalized"):
        mapping_references(document)


def test_minimal_bundle_is_exact_referenced_closure(tmp_path: Path):
    source = make_asset_root(tmp_path / "source")
    destination = tmp_path / "local_assets"
    expected = prepare_minimal_asset_bundle(source, destination)
    assert expected == {"index.json", "mapping.json", "assets/0000.bmp", "assets/0001.png"}
    verify_runtime_asset_bundle(destination, expected)
    index = load_json(destination / "index.json")
    assert [item["key"] for item in index["assets"]] == [
        "Synthetic:Terrain", "Synthetic:Unit"
    ]
    assert all("prepared" not in item["path"] for item in index["assets"])
    assert not any("Unused" in item["key"] for item in index["assets"])


def test_missing_mapped_asset_is_rejected(tmp_path: Path):
    source = make_asset_root(tmp_path / "source")
    (source / "mapping.json").write_text(
        json.dumps(mapping("Synthetic:Missing")), encoding="utf-8")
    with pytest.raises(BuildError, match="missing assets"):
        prepare_minimal_asset_bundle(source, tmp_path / "bundle")


@pytest.mark.parametrize("bad_path", ["../escape.png", "/tmp/asset.png", "C:/asset.png"])
def test_asset_path_traversal_and_absolute_paths_are_rejected(tmp_path: Path, bad_path: str):
    source = make_asset_root(tmp_path / "source")
    index = load_json(source / "index.json")
    index["assets"][0]["path"] = bad_path
    (source / "index.json").write_text(json.dumps(index), encoding="utf-8")
    with pytest.raises(BuildError):
        prepare_minimal_asset_bundle(source, tmp_path / "bundle")


def test_escaping_symlink_is_rejected(tmp_path: Path):
    source = make_asset_root(tmp_path / "source")
    outside = tmp_path / "outside.png"
    outside.write_bytes(b"outside")
    linked = source / "prepared/unit.png"
    linked.unlink()
    linked.symlink_to(outside)
    with pytest.raises(BuildError, match="symlink|escapes"):
        prepare_minimal_asset_bundle(source, tmp_path / "bundle")


def test_unknown_keys_and_unsupported_types_are_rejected(tmp_path: Path):
    source = make_asset_root(tmp_path / "source")
    index = load_json(source / "index.json")
    index["assets"][0]["unexpected"] = True
    (source / "index.json").write_text(json.dumps(index), encoding="utf-8")
    with pytest.raises(BuildError, match="unknown"):
        prepare_minimal_asset_bundle(source, tmp_path / "bundle")

    source = make_asset_root(tmp_path / "second")
    index = load_json(source / "index.json")
    index["assets"][0]["type"] = "audio"
    (source / "index.json").write_text(json.dumps(index), encoding="utf-8")
    with pytest.raises(BuildError, match="unsupported asset type"):
        prepare_minimal_asset_bundle(source, tmp_path / "second-bundle")


def test_duplicate_json_keys_and_bad_relative_paths_are_rejected(tmp_path: Path):
    duplicate = tmp_path / "duplicate.json"
    duplicate.write_text('{"version": 1, "version": 2}', encoding="utf-8")
    with pytest.raises(BuildError, match="duplicate JSON key"):
        load_json(duplicate)
    for value in ("", "..", "a/../b", "D:\\asset.png"):
        with pytest.raises(BuildError):
            normalize_relative_path(value, "test path")


def test_public_scanner_accepts_fallback_package_and_rejects_local_material(tmp_path: Path):
    package = make_package(tmp_path / "public", "public")
    inventory = scan_release_tree(package, "public")
    assert EXE_NAME in inventory and PCK_NAME in inventory

    (package / "local_assets").mkdir()
    with pytest.raises(BuildError, match="local_assets"):
        scan_release_tree(package, "public")
    (package / "local_assets").rmdir()
    (package / "original.dat").write_bytes(b"dat")
    with pytest.raises(BuildError, match="DAT"):
        scan_release_tree(package, "public")


def test_public_scanner_rejects_manifest_and_machine_path_leaks(tmp_path: Path):
    package = make_package(tmp_path / "public", "public")
    (package / "manifest.json").write_text("{}", encoding="utf-8")
    with pytest.raises(BuildError, match="manifest"):
        scan_release_tree(package, "public")
    (package / "manifest.json").unlink()
    (package / "README.txt").write_text("built at /home/developer/project/", encoding="utf-8")
    with pytest.raises(BuildError, match="absolute developer path"):
        scan_release_tree(package, "public")


def test_scanner_rejects_wrong_identity_and_embedded_egograbber_text(tmp_path: Path):
    package = make_package(tmp_path / "public", "public")
    build = json.loads((package / "BUILD.json").read_text(encoding="utf-8"))
    build["mode"] = "private"
    (package / "BUILD.json").write_text(json.dumps(build), encoding="utf-8")
    with pytest.raises(BuildError, match="mode"):
        scan_release_tree(package, "public")

    write_package_documents(package, metadata("public"))
    (package / "README.txt").write_text("bundled from EGOgrabber", encoding="utf-8")
    with pytest.raises(BuildError, match="EGOgrabber"):
        scan_release_tree(package, "public")


def test_private_scanner_proves_runtime_closure(tmp_path: Path):
    source = make_asset_root(tmp_path / "source")
    package = make_package(tmp_path / "private", "private", source)
    scan_release_tree(package, "private")
    (package / "local_assets/extra.png").write_bytes(b"extra")
    with pytest.raises(BuildError, match="unreferenced"):
        scan_release_tree(package, "private")


def test_public_private_runtime_payloads_are_byte_identical(tmp_path: Path):
    source = make_asset_root(tmp_path / "source")
    public = make_package(tmp_path / "public", "public")
    private = make_package(tmp_path / "private", "private", source)
    assert runtime_hashes(public) == runtime_hashes(private)
    public_zip = tmp_path / "public.zip"
    write_zip(public, public_zip, metadata("public")["built_at"])
    compare_runtime_with_zip(private, public_zip)
    names = inspect_zip(public_zip)
    assert names[0] == "BUILD.json"
    assert not any(name.startswith("local_assets/") for name in names)


def test_identity_comparison_fails_closed_on_different_engine(tmp_path: Path):
    source = make_asset_root(tmp_path / "source")
    public = make_package(tmp_path / "public", "public")
    private = make_package(tmp_path / "private", "private", source)
    public_zip = tmp_path / "public.zip"
    write_zip(public, public_zip, metadata("public")["built_at"])
    (private / EXE_NAME).write_bytes(b"different")
    with pytest.raises(BuildError, match="identity mismatch"):
        compare_runtime_with_zip(private, public_zip)


def test_default_and_external_staging_are_uniquely_owned_and_cleaned(tmp_path: Path):
    repo = tmp_path / "repo"
    repo.mkdir()
    with owned_staging_directory(repo) as default_stage:
        default_parent = repo / ".release_staging"
        assert default_stage.parent == default_parent.resolve()
        (default_stage / "owned.txt").write_text("owned", encoding="utf-8")
    assert default_parent.is_dir()
    assert not default_stage.exists()

    external_parent = tmp_path / "windows-backed"
    external_parent.mkdir()
    sentinel = external_parent / "caller-owned.txt"
    sentinel.write_text("keep", encoding="utf-8")
    with pytest.raises(RuntimeError, match="synthetic failure"):
        with owned_staging_directory(repo, external_parent) as external_stage:
            assert external_stage.parent == external_parent.resolve()
            assert external_stage != external_parent
            (external_stage / "owned.txt").write_text("owned", encoding="utf-8")
            raise RuntimeError("synthetic failure")
    assert sentinel.read_text(encoding="utf-8") == "keep"
    assert external_parent.is_dir()
    assert not external_stage.exists()


def test_staging_rejects_a_non_directory_or_symlink_parent(tmp_path: Path):
    repo = tmp_path / "repo"
    repo.mkdir()
    not_a_directory = tmp_path / "file"
    not_a_directory.write_text("x", encoding="utf-8")
    with pytest.raises(BuildError, match="not a directory"):
        with owned_staging_directory(repo, not_a_directory):
            pass
    target = tmp_path / "target"
    target.mkdir()
    link = tmp_path / "link"
    link.symlink_to(target, target_is_directory=True)
    with pytest.raises(BuildError, match="symlink"):
        with owned_staging_directory(repo, link):
            pass


def test_reproducible_epoch_and_source_date_epoch_precedence(monkeypatch: pytest.MonkeyPatch,
                                                              tmp_path: Path):
    git_calls: list[tuple[str, ...]] = []

    def fake_git_output(repo: Path, *args: str) -> str:
        git_calls.append(args)
        return "1700000000"

    monkeypatch.setattr("tools.build_demo.git_output", fake_git_output)
    assert release_epoch(tmp_path, "a" * 40, True, {}) == 1700000000
    assert build_timestamp(tmp_path, "a" * 40, True, {}) == "2023-11-14T22:13:20Z"
    assert len(git_calls) == 2
    assert release_epoch(
        tmp_path, "a" * 40, True, {"SOURCE_DATE_EPOCH": "1700000123"}
    ) == 1700000123
    assert build_timestamp(
        tmp_path, "a" * 40, True, {"SOURCE_DATE_EPOCH": "1700000123"}
    ) == "2023-11-14T22:15:23Z"
    assert len(git_calls) == 2
    assert release_epoch(tmp_path, "a" * 40, False, {}) is None
    before = datetime.now(timezone.utc).replace(microsecond=0)
    ordinary = datetime.fromisoformat(
        build_timestamp(tmp_path, "a" * 40, False, {}).replace("Z", "+00:00")
    )
    after = datetime.now(timezone.utc).replace(microsecond=0)
    assert before <= ordinary <= after


def test_fixed_epoch_zip_packaging_is_byte_identical(tmp_path: Path):
    first = make_package(tmp_path / "first", "public")
    second = make_package(tmp_path / "second", "public")
    timestamp = metadata("public")["built_at"]
    first_zip = tmp_path / "first.zip"
    second_zip = tmp_path / "second.zip"
    write_zip(first, first_zip, timestamp)
    write_zip(second, second_zip, timestamp)
    assert first_zip.read_bytes() == second_zip.read_bytes()


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
