# Playable Tactical Slice 2

This slice is a project-authored tactical hot-seat battle. It uses the existing
deterministic `Scenario`, `Battlefield`, combat commands, and `RoundLoop`; it is
not a visual- or content-parity claim for the original game.

## Launch and controls

From the repository root with Godot 4.3:

```bash
godot --path .
```

Ordinary launch opens `game/tactical/tactical_main.tscn`, never an asset viewer.
The controls remain:

- select a highlighted active-side unit with left click;
- click a green empty hex to move;
- click an orange enemy for automatic-approach melee;
- press `R` or the Ranged button, then click a magenta enemy to shoot;
- press `Space` or Pass to finish the active side;
- right-click, `Escape`, or Cancel to clear selection;
- use Restart Battle after victory.

The selection ring, side-colored ring, and life bar are presentation overlays.
They remain independent of an optional sprite, and sprite dimensions never
define model coordinates or hit boxes.

## Authoritative command results

`Scenario.execute_command()` is the single execution gate used by
`ManualBattleSession.issue_command()`. Its compact result is:

```text
{
  accepted: bool,
  command: "move" | "melee" | "ranged" | "rest" | "pass",
  reason: String,
  events: Array,
  state_changed: bool
}
```

The Slice 1 `ok`, `message`, and `log` aliases remain during migration. Refused
commands contain a stable reason, report no state change, emit no new event, and
mutate no command resource. Accepted commands contain only the new core log
entries emitted by that execution. `TacticalController` reads `accepted`,
`reason`, and `events`; it does not search free-form logs to decide success.

`Scenario.query_command()` uses the same movement plan, melee approach plan,
and ranged eligibility checks as execution. `ManualBattleSession` uses those
queries for green/orange/magenta highlights. A highlight is advisory: state can
change after it is drawn, so execution is always authoritative.

`Damage` still has legacy process-global bindings. A manual session therefore
binds its own pipeline and `Scenario.environment` only for a command or neutral
damage query and clears both before returning. Two manual sessions can be
alternated without retaining one another's aura/environment. This is scoped
isolation, not a new global service architecture.

## Optional local Eador presentation assets

A fresh clone requires no DAT or local file. Generated colored tokens are the
fallback. Original files and all generated real-data artifacts remain ignored
below:

```text
.local/eador_assets/
  exports/
    Units/manifest.json, images/, raw/
    Unit_icons/manifest.json, images/, raw/
    Unit_shadow/manifest.json, images/, raw/
    Unit_shadowf/manifest.json, images/, raw/
  index.json
  mapping.json
.local/tools/eador_dat
```

The resolver auto-detects `res://.local/eador_assets/index.json` and
`mapping.json`. `EGO_ASSET_INDEX` and `EGO_ASSET_MAPPING` can explicitly select
other paths. Missing, malformed, unreadable, unsafe, raw, or unmapped assets
produce useful resolver status and fall back to placeholders. Restart reloads
the index/mapping.

### Actual EGOgrabber checkout

The inspected clean checkout is revision
`ca2df7001427266c07201cb22569d32a663f77e0` on `main...origin/main`. It has no
build files or README. The verified local build and CLI are:

```bash
g++ -std=c++17 -O2 -Wall -Wextra \
  -I"$EGOGRABBER_REPO/src" "$EGOGRABBER_REPO/src/main.cpp" \
  -o .local/tools/eador_dat
.local/tools/eador_dat list "$EADOR_DAT_ROOT/Units.dat"
.local/tools/eador_dat extract "$EADOR_DAT_ROOT/Units.dat" \
  .local/eador_assets/exports/Units
```

Source and real-corpus behavior establish these capabilities and limitations:

- wrappers accepted by the reader are big-endian `slh!` (`0x736c6821`, packed
  LZSS) and `slh ` (`0x736c6820`, unpacked), followed by `ALL.`; the comments
  still label the wrapper constants placeholders, while all four inspected
  corpus files successfully used `slh!`;
- a negative per-object uncompressed size invokes Allegro-style LZSS; a
  nonnegative size is kept unpacked;
- `FILE` payloads are recursively parsed and extracted, with nested `NAME`
  segments joined by `/`; the four inspected tactical archives had no nested
  `FILE` groups;
- `BMP ` payloads are decoded only for signed depths `24`, `32`, and `-32`;
  8/15/16-bit and malformed payloads become raw files;
- decoded images are always written as bottom-up 24-bit BGR BMP. For 32/-32
  input the fourth byte is discarded, so exported BMP has no alpha channel;
  no palette is read or emitted;
- output is `images/<nested-id>.bmp` or `raw/<nested-id>.<fourcc>.bin`, plus a
  version-1 manifest with `root` and array entries `{id,type,path}`;
- `NAME` is used verbatim; missing `NAME` becomes `obj_<index>`. EGOgrabber does
  not reject duplicate IDs: duplicate output paths can overwrite while
  duplicate manifest entries remain;
- the manifest writer does not JSON-escape values;
- it emits no frame timing, animation, palette, alpha, or arbitrary property
  metadata. Nested `FILE` IDs retain grouping only as slash-separated paths;
- EGOgrabber itself adds no archive namespace, so Project EGO must add one.

EGOgrabber remains read-only and Project EGO never parses DAT.

### Prepare real exports

First prove the destination is ignored:

```bash
mkdir -p .local/eador_assets
git check-ignore -q .local/eador_assets/probe
```

Consume ready exports:

```bash
python3 tools/prepare_tactical_assets.py \
  --export Units=.local/eador_assets/exports/Units \
  --export Unit_icons=.local/eador_assets/exports/Unit_icons \
  --output .local/eador_assets/index.json
```

Or explicitly invoke a ready EGOgrabber binary on user-selected files (the tool
never searches the computer):

```bash
python3 tools/prepare_tactical_assets.py \
  --egograbber .local/tools/eador_dat \
  --dat Units="$EADOR_DAT_ROOT/Units.dat" \
  --dat Unit_icons="$EADOR_DAT_ROOT/Unit_icons.dat"
```

The tool validates EGOgrabber version-1 manifests and rejects malformed JSON,
duplicate JSON keys/asset IDs, unsupported versions/types, missing root/assets,
absolute or traversing paths (including Windows separators), escaping symlinks,
and missing files. Existing exports must be under the selected index directory;
this keeps runtime paths relative and contained.

### Project EGO index schema

`index.json` is deterministic, sorted by archive-qualified key, and contains no
machine-specific source path:

```json
{
  "version": 1,
  "assets": [
    {
      "key": "Units:Unit01",
      "archive": "Units",
      "source_id": "Unit01",
      "type": "image",
      "path": "exports/Units/images/Unit01.bmp"
    }
  ]
}
```

The array form permits duplicate logical keys to be detected after JSON parsing.
The resolver revalidates key consistency, type, containment, and file existence.
Raw assets are indexed but can never be mapped as textures.

### Local presentation mapping

Identity is separate from archive objects. `mapping.json` uses arrays so
conflicting duplicate mappings are rejected:

```json
{
  "version": 1,
  "content": [
    {"id": "genesis:unit/5", "asset": "Units:Unit05"}
  ],
  "instances": [
    {"id": "azure-ranger-17", "asset": "Units:Unit12"}
  ]
}
```

Resolution priority is canonical `Combatant.content_id`, explicit battle
`instance_id`, then placeholder. Display names are never identities. References
must name known image entries; malformed identities, unknown assets, duplicate
IDs, raw references, and injection-like keys are rejected.

The real local demonstration maps the four playable instance IDs explicitly.
Those are **local presentation/demo mappings only**. The inspected `Unit01`…
`Unit71` names and matching names across sprite/icon/shadow archives do not prove
which canonical `genesis:unit/N` each depicts. No numeric canonical relationship
is claimed; that semantic bridge remains unresolved.

### Real tactical archive observations

All four required archives extracted successfully with no failures:

| archive | objects | stable names | images | exported dimensions | format |
|---|---:|---|---:|---|---|
| `Units` | 72 | `Unit01`…`Unit71`, `GrabberInfo` | 71 | width 60–103, height 80–130 | 24-bit BMP, no alpha |
| `Unit_icons` | 72 | same | 71 | 64×80 | 24-bit BMP, no alpha |
| `Unit_shadow` | 72 | same | 71 | width 60–103, height 80–130 | 24-bit BMP, no alpha |
| `Unit_shadowf` | 72 | same | 71 | width 60–103, height 80–130 | 24-bit BMP, no alpha |

Each archive also yielded one raw `GrabberInfo.info.bin`. There were no duplicate
names within an archive. All 72 names collide across every archive pair, which
is why archive namespace is mandatory. Each named object produced one image;
no frame groups or animation metadata were present. Shadows are separate
archives, not alpha layers attached to `Units`.

## Validation

Portable validation is:

```bash
python3 tools/run_godot_tests.py
python3 -m pytest -q
```

`tests/test_local_tactical_assets.gd` clearly skips when the ignored index is
absent. When local data is configured it validates index/mapping loading, loads
mapped textures, and proves those textures reach the playable battlefield draw
path without committing an original-derived fixture.
