"""Requires-pack scenario dependency and provenance checks.

Fresh clones skip this declared tier because extracted pack tables are local.
Run explicitly with: python3 -m pytest -q -m requires_pack
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

import content
import handlers
import roster
import scenario

pytestmark = pytest.mark.requires_pack
ROOT = Path(__file__).parents[1]
PACK_DIR = ROOT / "packs" / "genesis"
TABLES = {"unit": "unit.json", "unit_upg": "unit_upg.json",
          "ability_num": "ability_num.json"}


def local_db():
    if not (PACK_DIR / "data" / "unit.json").is_file():
        pytest.skip(
            "requires-pack: packs/genesis/data is absent; generate it with "
            "python3 tools/extract/build_pack.py <path-to>/var genesis")
    registry = content.AbilityRegistry()
    handlers.register_all(registry)
    return content.ContentDb.load("genesis", str(PACK_DIR), registry, TABLES)


def test_local_pack_discovery_provenance_and_one_definition():
    db = local_db()
    provenance = db.content_provenance()
    assert provenance["pack"] == "genesis"
    assert provenance["fingerprint"].startswith("sha256:")
    assert len(provenance["fingerprint"]) == 71
    # Same loaded snapshot must produce the same canonical fingerprint twice.
    assert db.content_provenance() == provenance

    selected = None
    for content_id in roster.Roster(db).ids():
        try:
            definition = db.resolve_definition(content_id)
        except ValueError:
            continue
        if definition and definition.get("name") not in ("", "Пусто", "?"):
            selected = (content_id, definition)
            break
    assert selected is not None, "local Genesis pack exposes no complete scenario unit"
    content_id, definition = selected

    spec = {
        "name": "requires-pack dependency probe", "profile": "native", "seed": 1,
        "content": provenance,
        "battlefield": {"width": 3, "height": 3, "tiles": []},
        "sides": [
            {"id": 0, "is_attacker": True, "units": [
                {"id": "local-1", "def": content_id, "at": [0, 0], "overrides": {}}]},
            {"id": 1, "units": [{
                "id": "portable-target", "name": "Portable target", "at": [2, 0],
                "life": 10, "stamina": 10, "morale": 10, "speed": 1,
            }]},
        ],
        "commands": [],
    }
    built = scenario.Scenario(spec, content_provider=db).units["local-1"]
    assert built.content_id == content_id
    assert built.instance_id == "local-1"
    assert built.name == definition["name"]
