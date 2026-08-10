import json
from pathlib import Path
import sys

import pytest


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from tools import build_release_pair
from tools.build_demo import BuildError, EXE_NAME, PCK_NAME, sha256_file, write_zip
from tools.build_release_pair import verify_release_pair, write_pair_manifest
from tools.test_build_demo import make_asset_root, make_package, metadata


def make_artifacts(tmp_path: Path) -> tuple[Path, Path, Path, Path]:
    asset_root = make_asset_root(tmp_path / "assets")
    public_package = make_package(tmp_path / "public-package", "public")
    private_package = make_package(tmp_path / "private-package", "private", asset_root)
    public_artifact = tmp_path / "public.zip"
    private_artifact = tmp_path / "private.zip"
    write_zip(public_package, public_artifact, metadata("public")["built_at"])
    write_zip(private_package, private_artifact, metadata("private")["built_at"])
    return public_artifact, private_artifact, public_package, private_package


def passing_smokes() -> dict[str, bool]:
    return {"public": True, "private": True}


def test_build_pair_routes_official_arguments_and_forwards_smokes(
        tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    asset_root = tmp_path / "prepared-private-root"
    staging_parent = tmp_path / "staging-parent"
    args = build_release_pair.make_parser().parse_args([
        "--milestone", "0.2",
        "--asset-root", str(asset_root),
        "--staging-parent", str(staging_parent),
    ])
    artifacts = {
        "public": tmp_path / "public.zip",
        "private": tmp_path / "private.zip",
    }
    delegated: list[object] = []

    def fake_build(build_args):
        delegated.append(build_args)
        smoke = f"synthetic output for {build_args.mode}: DEMO_SMOKE PASS"
        return artifacts[build_args.mode], tmp_path / build_args.mode, {}, smoke

    written: dict[str, object] = {}

    def fake_write(path, public, private, repo, runtime_smoke):
        written.update({
            "path": path,
            "public": public,
            "private": private,
            "repo": repo,
            "runtime_smoke": runtime_smoke,
        })
        return {"synthetic": True}

    monkeypatch.setattr(build_release_pair.build_demo, "REPOSITORY_ROOT", tmp_path)
    monkeypatch.setattr(build_release_pair.build_demo, "build", fake_build)
    monkeypatch.setattr(build_release_pair, "write_pair_manifest", fake_write)

    output, manifest = build_release_pair.build_pair(args)

    assert [item.mode for item in delegated] == ["public", "private"]
    assert all(item.reproducible is True for item in delegated)
    assert [item.asset_root for item in delegated] == [None, asset_root]
    assert all(item.milestone == "0.2" for item in delegated)
    assert all(item.staging_parent == staging_parent for item in delegated)
    assert written == {
        "path": output,
        "public": artifacts["public"],
        "private": artifacts["private"],
        "repo": tmp_path,
        "runtime_smoke": {"public": True, "private": True},
    }
    assert manifest == {"synthetic": True}


def test_build_pair_removes_stale_manifest_before_attempt_and_leaves_none_on_failure(
        tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    asset_root = tmp_path / "prepared-private-root"
    args = build_release_pair.make_parser().parse_args([
        "--milestone", "0.2", "--asset-root", str(asset_root),
    ])
    monkeypatch.setattr(build_release_pair.build_demo, "REPOSITORY_ROOT", tmp_path)
    output = build_release_pair.pair_manifest_path(tmp_path, "0.2")
    output.parent.mkdir(parents=True)
    output.write_text("stale successful manifest\n", encoding="utf-8")
    delegated_modes: list[str] = []

    def fake_build(build_args):
        delegated_modes.append(build_args.mode)
        assert not output.exists()
        if build_args.mode == "public":
            return tmp_path / "public.zip", tmp_path / "public", {}, "DEMO_SMOKE PASS"
        raise BuildError("synthetic private failure")

    monkeypatch.setattr(build_release_pair.build_demo, "build", fake_build)

    with pytest.raises(BuildError, match="synthetic private failure"):
        build_release_pair.build_pair(args)

    assert delegated_modes == ["public", "private"]
    assert not output.exists()


def test_pair_manifest_records_hashes_inventories_identity_and_validation(tmp_path: Path):
    public, private, public_package, private_package = make_artifacts(tmp_path)
    packages = {"public": public_package, "private": private_package}
    output = tmp_path / "dist" / "pair.json"
    manifest = write_pair_manifest(output, public, private, tmp_path, passing_smokes())
    written = json.loads(output.read_text(encoding="utf-8"))
    assert written == manifest
    assert manifest["schema"] == "project-ego-release-pair"
    assert manifest["version"] == 1
    assert manifest["project"] == "Project EGO"
    assert manifest["milestone"] == "0.2"
    assert manifest["source_date_epoch"] == 1767323045
    assert manifest["runtime_identity"] == {
        "exe_payloads_match": True, "pck_payloads_match": True,
    }
    for mode, artifact in (("public", public), ("private", private)):
        item = manifest["artifacts"][mode]
        assert item["size"] == artifact.stat().st_size
        assert item["sha256"] == sha256_file(artifact)
        assert item["exe_sha256"] == sha256_file(packages[mode] / EXE_NAME)
        assert item["pck_sha256"] == sha256_file(packages[mode] / PCK_NAME)
        assert item["inventory"] == sorted(item["inventory"])
        assert item["runtime_smoke"] == {"passed": True}
    assert manifest["artifacts"]["public"]["validation"] == {
        "fallback_no_local_assets": True,
    }
    assert manifest["artifacts"]["private"]["validation"] == {
        "exact_mapping_reference_closure": True,
    }


@pytest.mark.parametrize("payload", [EXE_NAME, PCK_NAME])
def test_pair_rejects_runtime_identity_mismatch_and_writes_no_manifest(
        tmp_path: Path, payload: str):
    public, _, _, private_package = make_artifacts(tmp_path)
    (private_package / payload).write_bytes(b"different payload")
    private = tmp_path / "different-private.zip"
    write_zip(private_package, private, metadata("private")["built_at"])
    output = tmp_path / "pair.json"
    with pytest.raises(BuildError, match="runtime identity mismatch"):
        write_pair_manifest(output, public, private, tmp_path, passing_smokes())
    assert not output.exists()


def test_pair_reuses_public_scanner_to_reject_local_assets(tmp_path: Path):
    _, private, public_package, _ = make_artifacts(tmp_path)
    (public_package / "local_assets").mkdir()
    (public_package / "local_assets" / "synthetic.png").write_bytes(b"synthetic")
    public = tmp_path / "invalid-public.zip"
    write_zip(public_package, public, metadata("public")["built_at"])
    output = tmp_path / "pair.json"
    with pytest.raises(BuildError, match="public package contains local_assets"):
        write_pair_manifest(output, public, private, tmp_path, passing_smokes())
    assert not output.exists()


def test_pair_reuses_private_closure_validator(tmp_path: Path):
    public, _, _, private_package = make_artifacts(tmp_path)
    (private_package / "local_assets" / "extra.png").write_bytes(b"unreferenced")
    private = tmp_path / "invalid-private.zip"
    write_zip(private_package, private, metadata("private")["built_at"])
    output = tmp_path / "pair.json"
    with pytest.raises(BuildError, match="unreferenced"):
        write_pair_manifest(output, public, private, tmp_path, passing_smokes())
    assert not output.exists()


def test_pair_rejects_incomplete_pair_metadata_difference_and_failed_smoke(tmp_path: Path):
    public, private, _, private_package = make_artifacts(tmp_path)
    output = tmp_path / "pair.json"
    with pytest.raises(BuildError, match="incomplete"):
        write_pair_manifest(output, public, tmp_path / "missing.zip", tmp_path, passing_smokes())
    assert not output.exists()

    private_metadata = json.loads((private_package / "BUILD.json").read_text(encoding="utf-8"))
    private_metadata["built_at"] = "2026-01-02T03:04:06Z"
    (private_package / "BUILD.json").write_text(
        json.dumps(private_metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    mismatched = tmp_path / "metadata-private.zip"
    write_zip(private_package, mismatched, private_metadata["built_at"])
    with pytest.raises(BuildError, match="metadata differs"):
        write_pair_manifest(output, public, mismatched, tmp_path, passing_smokes())
    assert not output.exists()

    with pytest.raises(BuildError, match="both public and private runtime smokes"):
        verify_release_pair(public, private, tmp_path, {"public": True, "private": False})
