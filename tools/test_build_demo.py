import json
from pathlib import Path
import zipfile

import pytest

from tools.build_demo import (
    BuildError,
    EXE_NAME,
    PCK_NAME,
    compare_runtime_with_zip,
    inspect_zip,
    load_json,
    mapping_references,
    normalize_relative_path,
    prepare_minimal_asset_bundle,
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
        "project": "Project EGO", "milestone": "0.1", "commit": "a" * 40,
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
