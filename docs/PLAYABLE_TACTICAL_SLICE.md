# Playable Tactical Slice 1

This slice is a project-authored tactical hot-seat battle. It uses the existing
deterministic `Scenario`, `Battlefield`, combat commands, and `RoundLoop`; it is
not a visual-parity claim for the original game.

## Launch

From the repository root with the verified Godot 4.3 runtime:

```bash
godot --path .
```

Ordinary project launch opens `game/tactical/tactical_main.tscn` at 1152×720.
The initial screen shows an 8×5 hex field, two blue Azure units, two red Crimson
units, round 1, and Azure Company as the active side.

## Controls

- **Left-click an active-side unit:** select it and inspect its state.
- **Left-click a green empty hex:** move the selected unit there.
- **Left-click an orange enemy:** melee attack; the core automatically approaches
  when an adjacent reachable hex exists.
- **Ranged button or `R`:** enter ranged mode; click a magenta enemy to shoot.
- **Pass button or `Space`:** finish the active side's phase.
- **Right-click, `Escape`, or Cancel:** clear selection and ranged mode.
- **Restart Battle:** appears after victory and builds a fresh `Scenario`.

Invalid clicks leave authoritative state unchanged and put the refusal in the
Latest field. Dark cells are impassable. Cyan rings indicate selection; the HUD
shows display name, instance ID, life, stamina, remaining movement, ammunition,
mode, and recent core events.

## Short smoke-test loop

1. Select **Ranger** (`azure-ranger-17`), click a green hex to test movement,
   then press `R` and shoot a magenta Crimson unit.
2. Select **Vanguard** (`azure-vanguard-01`) and click the orange **Guard**.
   Vanguard walks into contact automatically and resolves the melee exchange.
3. Press `Space` to hand the same battlefield to the Crimson player.
4. Select **Marksman**, press `R`, and shoot a magenta Azure unit. Select
   **Guard** and move or melee when highlighted, then pass.
5. Continue selecting, moving, attacking, shooting, and passing. When either
   roster has no living unit, input locks, the winning side is displayed, and
   **Restart Battle** creates the original fresh battle.

Exact damage is deterministic for the committed seed, but counterattacks and
remaining life can make the shortest winning sequence depend on target order.

## Optional EGOgrabber bridge

The battle needs no extracted assets. Generated colored tokens are the default
and are committed/project-authored.

EGOgrabber source revision `ca2df7001427266c07201cb22569d32a663f77e0`
was inspected. Its actual `main.cpp` provides noninteractive commands:

```text
eador_dat list <file.dat>
eador_dat extract <file.dat> <out_dir>
```

The repository contains `Ability.dat`, but has no README, build configuration,
or named Eador `.dat` support matrix. The reader is intended for Allegro `ALL.`
datafiles with packed or unpacked wrappers; its pack-magic constants are
explicitly marked placeholders. Accordingly, the inspected code does **not**
establish verified production support for a particular list of Eador `.dat`
files.

Extraction walks `FILE` children. A `NAME` property supplies each path segment;
otherwise it uses `obj_<index>`. Nested IDs are slash-separated. Decodable
`BMP ` objects with 24-, 32-, or -32-bit payloads become 24-bit BMP files at
`images/<nested-id>.bmp`. Other objects become
`raw/<nested-id>.<fourcc>.bin`.

Extraction writes `manifest.json` version 1 with `root` and an `assets` array.
Each asset has traversal-derived `id`, `type` (`image` or `raw`), and relative
`path` fields. The writer does not escape JSON strings or enforce unique IDs,
so archives with unusual/duplicate `NAME` values may not yield an unambiguous
valid manifest. Project EGO accepts valid JSON, sorts entries by ID/path, and
chooses the lexicographically first duplicate deterministically. It resolves
asset paths relative to the manifest location and never parses `.dat` files. To
opt in after locally building/running EGOgrabber:

```bash
export EGO_ASSET_MANIFEST=/absolute/path/to/export/manifest.json
godot --path .
```

EGOgrabber's IDs describe archive objects, not Project EGO unit semantics. Do
not guess a unit mapping. If exact filenames/metadata establish one locally,
create an ignored mapping such as `/absolute/path/unit_asset_map.json`:

```json
{
  "version": 1,
  "units": {
    "azure-vanguard-01": "exact/nested/EGOgrabber-id"
  }
}
```

Then set:

```bash
export EGO_ASSET_UNIT_MAP=/absolute/path/unit_asset_map.json
```

As an alternative, place both files under ignored
`local_assets/egograbber/` using the names `manifest.json` and
`unit_asset_map.json`. Lookup is exact and deterministic; absent, malformed, or
unloadable images fall back to generated tokens. No original/extracted asset is
committed, and the current synthetic scenario intentionally supplies no guessed
mapping.

## Intentional limitations

- no AI: one human controls both sides in hot-seat form;
- no campaign transition, strategy map, persistence, multiplayer, sound, or
  animation framework;
- only existing move, ordinary melee, ordinary ranged, rest/core phase paths are
  exposed; incomplete special actions remain incomplete;
- synthetic content and placeholder graphics are not original visual parity;
- EGOgrabber's current reader limitations and lack of semantic unit mapping do
  not block play.

## Tests

```bash
godot --headless --path . --script tests/test_playable_tactical_slice.gd
python3 tools/run_godot_tests.py
```
