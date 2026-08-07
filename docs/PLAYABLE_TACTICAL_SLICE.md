# Playable Tactical Slice 3

This project-authored hot-seat battle uses the existing deterministic `Scenario`,
`Battlefield`, combat commands, and `ManualBattleSession`. Slice 3 changes only
presentation and optional ignored local-asset integration; it is not a combat
formula, terrain-rule, canonical-content, or pixel-parity claim.

## Launch and controls

With Godot 4.3, the ordinary entry point remains:

```bash
godot --path .
```

The battle supports the same manual play:

- select an active-side unit;
- click a green hex to move or an orange enemy for automatic-approach melee;
- use `R`/Ranged and click a magenta enemy to shoot;
- use `Space`/Pass to finish the side;
- use right-click, `Escape`, or Cancel to clear selection;
- use Restart Battle after victory.

The narrow right column now contains selected visual identity, combat/state
values, ammunition, only the actions the slice implements, effects/status,
round/side feedback, recent events, and victory/restart. The battlefield still
occupies model cells through `TacticalCoordinateAdapter`; texture bounds, visual
scale, shadows, and horizontal mirroring never define a hit box.

## Authoritative execution boundary

`ManualBattleSession.issue_command()` continues to use
`Scenario.execute_command()`. The structured result exposes `accepted`, the
normalized command, refusal `reason`, new `events`, and `state_changed`.
Highlights use the corresponding neutral queries, but execution is authority.
No visual function computes or changes combat outcomes.

## Stable presentation layers and facing

`TacticalBattlefieldView` encodes this order explicitly:

```text
base terrain < tile variation < decoration < hex grid
             < unit shadows < unit sprites < health/status bars
             < target/selection overlays < right-side UI
```

Direct inspection of the 71 extracted `Units.dat` images found that the ordinary
figure set is naturally oriented toward screen-right (some individual figures
are frontal, but the consistently directional weapons/poses use the rightward
set). In the synthetic scenario side 0 deploys on the left and retains the
natural facing. Side 1 deploys on the right and receives render-state scale
`x = -1`. One unit mapping therefore remains one asset. Its mapped shadow is
mirrored in the same local sprite transform; rings and bars are drawn only after
the transform is reset. Placeholder arrow-shaped units apply the same side
rule. Model coordinates and hit tests are unchanged.

## Shadow findings

All matching `Unit01`…`Unit71` entries in `Units`, `Unit_shadow`, and
`Unit_shadowf` have exactly matching canvas dimensions (35 dimension families,
most commonly 64×80). Direct paired-image inspection shows:

- neither shadow archive is an alternate left/right-facing sprite set;
- both contain black, unit-specific, ground-projected silhouettes on exact
  magenta matte, already positioned within the same canvas as the unit;
- `Unit_shadow` is generally the broader/taller flattened projection (for the
  first samples its occupied region begins around y=46–58);
- `Unit_shadowf` is a more compact, lower projection (first samples begin around
  y=55–61);
- both preserve the source's rightward geometry, so a mapped shadow must be
  mirrored with an opposing sprite rather than selected as an opposing-facing
  archive.

The suffix alone does not establish a gameplay mode. The local synthetic demo
explicitly maps `Unit_shadow`; the resolver can map either archive, but Project
EGO does not infer a flying/stance rule for `Unit_shadowf`. Missing shadows are
simply omitted. Shadows are rendered at reduced opacity and have no model role.

## Real battlefield reconnaissance

The following counts come from successful local EGOgrabber exports. Each archive
also has one raw `GrabberInfo` object.

| archive | objects | images | dimension families | repeated families / direct visual observations |
|---|---:|---:|---:|---|
| `Battlefield` | 113 | 112 | 74 | 100×100 (9), 50×50 (6); the contact sheet shows 100×100 grass/stone floors, a 104×120 hex graphic, narrow wall/hole pieces, small props, target/selection marks, and a 140×768 segmented battle panel |
| `Nature` | 325 | 324 | 154 | 29×31 (15), 31×31 (11), 42×63 (10); direct inspection shows 100×100 ground images plus isolated trees, plants, stones, puddles, structures and corresponding dark shadow-like images |

Names are sequential descriptive strings, for example `03Grass01`,
`74Stone1`, `000Grass`, `052Leaf_tree_1_1`, and many repeated tree/plant groups.
These names help a human make an explicit presentation mapping but do not grant
terrain mechanics. Visually paired base/shadow and multi-image tree groups are
present, but EGOgrabber exports no frame/group property beyond each object name.

The real local profile uses a mapped 100×100 grass image as a tiled base, three
mapped ground variations at low opacity, and an explicitly chosen deterministic
set of flowers/stone/tree/grass decorations. Selection uses a stable cell hash;
it does not consume gameplay RNG and does not claim that a decorated cell is a
forest, swamp, obstacle, or terrain effect. Existing model passability still
only controls the dark tile overlay. Without mappings, a complete
project-authored green patterned field and readable hex grid are drawn.

## Transparency and matte handling

EGOgrabber emits bottom-up 24-bit BMP and discards a source fourth channel.
Inspection found an exact `RGB(255, 0, 255)` key:

- every unit and both matching shadow sets has the key at the canvas edge;
- 323/324 `Nature` images and 97/112 `Battlefield` images have it at a corner;
- keyed interface assets also use the exact value, while opaque floors,
  portraits, icons, and many panels do not.

At runtime the resolver converts a loaded image to RGBA and clears **only**
pixels exactly equal to `(255, 0, 255)`, including matte islands disconnected by
sprite geometry. It does not use a tolerance: near-magenta artwork and all other
interior colors remain. A synthetic test covers both disconnected exact matte
and retained `(254, 0, 255)`. This reconstructs the demonstrated color key but
cannot recover discarded partial alpha; antialiasing against the original matte
can still leave a one-pixel color fringe.

## Tactical interface reconnaissance

| archive | objects | images | main size families / directly visible organization |
|---|---:|---:|---|
| `Interface` | 142 | 141 | 88 families; 512×768 (14), 1024×768 (10), 312×470 (7), 52×52 (5); contact sheets show full-screen backdrops, parchment/dialog frames, segmented inventory/info panels and slots |
| `Buttons` | 382 | 381 | 15 families; 51×37 (174), 52×52 (48), 57×32 (44), 53×39 (35); repeated adjacent `N/A/P/I`-suffixed images visibly form normal/highlight/pressed/disabled-like state groups |
| `Portraits` | 38 | 37 | all 130×150; painted hero-scale portraits |
| `SmallPort` | 38 | 37 | 35 at 52×52 plus one each at 52×51 and 52×53; cropped versions of the same portrait subjects |
| `Unit_icons` | 72 | 71 | all 64×80; framed visuals matching the corresponding local `Unit01`…`Unit71` images |
| `Ability` | 138 | 137 | all 52×52; framed stat/action/effect-like icons visible in contact sheets |
| `Items` | 411 | 410 | all 52×52; repeated equipment/icon families |
| `Spells` | 78 | 77 | all 52×52; repeated spell-icon frames |

The extracted `Battlefield:02Panel` is directly recognizable as the original
narrow segmented battle column and is used, when mapped, as a translucent panel
backdrop. Explicit local UI slots also use directly recognizable attack/ranged,
hourglass/end, and X/cancel visuals. Project-authored Godot controls remain on
top so current supported actions stay legible; no legacy slot or button is
assigned an unsupported gameplay meaning.

`Portraits` and `SmallPort` depict hero subjects, not the four synthetic unit
instances. For this battle the local profile therefore maps the corresponding
`Unit_icons` object as selected-unit visual identity. That is an explicit
instance presentation choice, not a claim that `Unit01` is a canonical content
ID. Unmapped selection shows a project-authored initial tile.

## Local index and visual mapping

Original files, exports, the generated index/mapping, reports, screenshots, and
movies stay below ignored `.local/eador_assets/`. The deterministic index remains
version 1 and archive-qualified. Slice 3 mapping version 2 separates meanings:

```json
{
  "version": 2,
  "units": {"content": [], "instances": [{"id": "battle-id", "asset": "Units:Unit01"}]},
  "shadows": {"content": [], "instances": [{"id": "battle-id", "asset": "Unit_shadow:Unit01"}]},
  "portraits": {"content": [], "instances": [{"id": "battle-id", "asset": "Unit_icons:Unit01"}]},
  "terrain": [{"id": "base", "asset": "Battlefield:03Grass01"}],
  "decorations": [{"id": "tree", "asset": "Nature:052Leaf_tree_1_1"}],
  "ui": [{"id": "panel", "asset": "Battlefield:02Panel"}]
}
```

Identity categories retain canonical-content priority over battle-instance
mapping. Named categories use explicit presentation slots. All categories
require known indexed images and reject duplicates, malformed slots, raw data,
unknown keys, and traversal. Slice-2 version-1 `content`/`instances` mappings
remain accepted as the `units` category; every new category then falls back.
No real mapping is committed.

## Exact local preparation workflow

First prove ignore coverage:

```bash
mkdir -p .local/eador_assets
git check-ignore -q .local/eador_assets/probe
```

Build the inspected read-only EGOgrabber checkout if necessary:

```bash
mkdir -p .local/tools
g++ -std=c++17 -O2 -Wall -Wextra   -I"$EGOGRABBER_REPO/src" "$EGOGRABBER_REPO/src/main.cpp"   -o .local/tools/eador_dat
```

The preparation tool never searches for DAT files and never parses DAT. Supply
each source explicitly; this invocation extracts, indexes, and prints a local
dimension report:

```bash
python3 tools/prepare_tactical_assets.py   --egograbber .local/tools/eador_dat   --dat Units="$EADOR_DAT_ROOT/Units.dat"   --dat Unit_shadow="$EADOR_DAT_ROOT/Unit_shadow.dat"   --dat Unit_shadowf="$EADOR_DAT_ROOT/Unit_shadowf.dat"   --dat Unit_icons="$EADOR_DAT_ROOT/Unit_icons.dat"   --dat Battlefield="$EADOR_DAT_ROOT/Battlefield.dat"   --dat Nature="$EADOR_DAT_ROOT/Nature.dat"   --dat Interface="$EADOR_DAT_ROOT/Interface.dat"   --dat Buttons="$EADOR_DAT_ROOT/Buttons.dat"   --dat Portraits="$EADOR_DAT_ROOT/Portraits.dat"   --dat SmallPort="$EADOR_DAT_ROOT/SmallPort.dat"   --dat Ability="$EADOR_DAT_ROOT/Ability.dat"   --output .local/eador_assets/index.json   --report
```

Ready exports can instead be passed as repeated `--export ARCHIVE=DIR`. Output
is sorted, namespaced, relative to the index, traversal-contained, and written
atomically. `--report` prints object/image/raw counts and BMP dimension families;
it writes no report artifact unless the user explicitly redirects stdout.

## Structural reference comparison and remaining gaps

The current 1152×720 layout allocates 840 pixels (73%) to the field and 312
pixels (27%) to a fixed right panel, versus Slice 2's roughly 56%/42% split.
Eight by five large visible hexes use radius 50; a 94-pixel-high unit occupies a
substantial fraction of the 100-pixel hex height. Textured terrain fills the
entire field instead of leaving dark unused space. Portrait/stats/actions/effects
are visibly segmented, and portrait plus state values dominate the upper panel.
Opposing deployments face inward.

This is a structural advance, not pixel parity. Remaining gaps include the
synthetic scenario's lower hex density than the reference, a proportionally
wider panel than the legacy 140-pixel asset, static rather than generated
legacy terrain composition, no animation or recovered partial alpha, no
canonical unit/portrait/terrain mapping, no authoritative display semantics for
legacy effect slots, and limited responsive behavior beyond the project's
canvas stretch.
