import json
from pathlib import Path
import stat

import pytest

from tools.prepare_tactical_assets import (
    AssetPreparationError,
    build_index,
    load_json,
    main,
    normalize_relative_path,
)


def make_export(root: Path, archive: str = "Units", assets=None) -> Path:
    export = root / "exports" / archive
    (export / "images").mkdir(parents=True)
    if assets is None:
        assets = [
            {"id": "Unit02", "type": "image", "path": "images/Unit02.bmp"},
            {"id": "Unit01", "type": "image", "path": "images/Unit01.bmp"},
        ]
    for entry in assets:
        raw = entry.get("path")
        if not isinstance(raw, str):
            continue
        normalized = raw.replace("\\", "/")
        if normalized.startswith("images/") and ".." not in normalized:
            path = export / normalized
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"synthetic")
    (export / "manifest.json").write_text(
        json.dumps({"version": 1, "root": str(export), "assets": assets}),
        encoding="utf-8",
    )
    return export


def test_valid_exports_are_namespaced_sorted_and_relative(tmp_path: Path):
    units = make_export(tmp_path, "Units")
    icons = make_export(
        tmp_path,
        "Unit_icons",
        [{"id": "Unit01", "type": "image", "path": "images\\Unit01.bmp"}],
    )
    index = build_index(
        [("Unit_icons", icons), ("Units", units)], tmp_path / "index.json"
    )
    keys = [entry["key"] for entry in index["assets"]]
    assert keys == ["Unit_icons:Unit01", "Units:Unit01", "Units:Unit02"]
    assert all(not Path(entry["path"]).is_absolute() for entry in index["assets"])
    assert index["assets"][0]["path"] == "exports/Unit_icons/images/Unit01.bmp"


def test_duplicate_json_keys_are_rejected(tmp_path: Path):
    path = tmp_path / "duplicate.json"
    path.write_text('{"version": 1, "version": 2}', encoding="utf-8")
    with pytest.raises(AssetPreparationError, match="duplicate JSON key"):
        load_json(path)


@pytest.mark.parametrize("text", ["{", "[]", '"text"'])
def test_malformed_json_roots_are_rejected(tmp_path: Path, text: str):
    path = tmp_path / "bad.json"
    path.write_text(text, encoding="utf-8")
    with pytest.raises(AssetPreparationError):
        load_json(path)


@pytest.mark.parametrize(
    "mutate, message",
    [
        (lambda manifest: manifest.update(version=2), "unsupported manifest version"),
        (lambda manifest: manifest.pop("root"), "manifest root"),
        (lambda manifest: manifest.update(assets={}), "assets must be an array"),
        (lambda manifest: manifest.update(assets=["bad"]), "must be an object"),
    ],
)
def test_manifest_schema_is_strict(tmp_path: Path, mutate, message: str):
    export = make_export(tmp_path)
    manifest = json.loads((export / "manifest.json").read_text(encoding="utf-8"))
    mutate(manifest)
    (export / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(AssetPreparationError, match=message):
        build_index([("Units", export)], tmp_path / "index.json")


def test_duplicate_ids_within_archive_are_rejected(tmp_path: Path):
    export = make_export(
        tmp_path,
        assets=[
            {"id": "Unit01", "type": "image", "path": "images/Unit01.bmp"},
            {"id": "Unit01", "type": "image", "path": "images/Unit01.bmp"},
        ],
    )
    with pytest.raises(AssetPreparationError, match="duplicate asset id"):
        build_index([("Units", export)], tmp_path / "index.json")


@pytest.mark.parametrize(
    "bad_path",
    ["/tmp/asset.bmp", "C:/asset.bmp", "C:\\asset.bmp", "../asset.bmp", "images/../asset.bmp"],
)
def test_absolute_and_traversing_paths_are_rejected(tmp_path: Path, bad_path: str):
    export = make_export(
        tmp_path,
        assets=[{"id": "Unit01", "type": "image", "path": bad_path}],
    )
    with pytest.raises(AssetPreparationError):
        build_index([("Units", export)], tmp_path / "index.json")


def test_symlink_escape_is_rejected(tmp_path: Path):
    outside = tmp_path / "outside.bmp"
    outside.write_bytes(b"synthetic")
    export = make_export(tmp_path)
    linked = export / "images/Linked.bmp"
    linked.symlink_to(outside)
    manifest = json.loads((export / "manifest.json").read_text(encoding="utf-8"))
    manifest["assets"] = [
        {"id": "Linked", "type": "image", "path": "images/Linked.bmp"}
    ]
    (export / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(AssetPreparationError, match="escapes export root"):
        build_index([("Units", export)], tmp_path / "index.json")


def test_missing_referenced_file_is_rejected(tmp_path: Path):
    export = make_export(tmp_path)
    (export / "images/Unit01.bmp").unlink()
    with pytest.raises(AssetPreparationError, match="asset file is missing"):
        build_index([("Units", export)], tmp_path / "index.json")


def test_unknown_asset_type_is_rejected(tmp_path: Path):
    export = make_export(
        tmp_path,
        assets=[{"id": "Unit01", "type": "sound", "path": "images/Unit01.bmp"}],
    )
    with pytest.raises(AssetPreparationError, match="unsupported type"):
        build_index([("Units", export)], tmp_path / "index.json")


def test_export_outside_index_root_is_rejected(tmp_path: Path):
    export = make_export(tmp_path / "external")
    with pytest.raises(AssetPreparationError, match="outside index root"):
        build_index([("Units", export)], tmp_path / "local/index.json")


def test_repeated_archive_namespace_is_rejected(tmp_path: Path):
    export = make_export(tmp_path)
    with pytest.raises(AssetPreparationError, match="duplicate logical asset key"):
        build_index(
            [("Units", export), ("Units", export)], tmp_path / "index.json"
        )


def test_cli_writes_deterministic_index(tmp_path: Path):
    export = make_export(tmp_path)
    output = tmp_path / "index.json"
    assert main(["--export", f"Units={export}", "--output", str(output)]) == 0
    first = output.read_bytes()
    assert main(["--export", f"Units={export}", "--output", str(output)]) == 0
    assert output.read_bytes() == first


def test_cli_can_invoke_explicit_egograbber(tmp_path: Path):
    fake = tmp_path / "fake_egograbber.py"
    fake.write_text(
        """#!/usr/bin/env python3
import json, pathlib, sys
out = pathlib.Path(sys.argv[3])
(out / 'images').mkdir(parents=True)
(out / 'images/Unit01.bmp').write_bytes(b'synthetic')
(out / 'manifest.json').write_text(json.dumps({'version': 1, 'root': str(out), 'assets': [{'id': 'Unit01', 'type': 'image', 'path': 'images/Unit01.bmp'}]}))
""",
        encoding="utf-8",
    )
    fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
    dat = tmp_path / "Units.dat"
    dat.write_bytes(b"synthetic dat supplied explicitly")
    output = tmp_path / "index.json"
    assert main(
        [
            "--egograbber", str(fake), "--dat", f"Units={dat}",
            "--output", str(output),
        ]
    ) == 0
    assert json.loads(output.read_text())["assets"][0]["key"] == "Units:Unit01"


def test_path_normalizer_rejects_empty_and_injection():
    for value in ("", "..", "a/../b", "/a", "D:/a"):
        with pytest.raises(AssetPreparationError):
            normalize_relative_path(value)
