# CX-031 reference layout review

State: DONE. Reviewer: Daniel Timson. Frozen base:
`baa2c6393778dba27e2a6c9999f8be84ce6a126d`.
The host capture and independent visual review are complete.

The menu now gives its panorama 62% of the viewport and places six narrow rows
in a continuous red-and-gold lower frame. Three playable routes, disabled
Multiplayer, Options, and the Controls/About/Quit utility row remain reachable.
Options contains the existing shared sound controls. Panorama movement, center
stop and crop remain in `PresentationLandscape`; hitboxes do not move with it.
The public fallback supplies parchment states as well as landscape art.

The strategic field fills the area above a persistent resource and navigation
strip sized by its contents. Map and Home share one context card. Every province can be
inspected by focus, hover or click, including the army's location and distant
provinces. Inspection does not travel: the named Travel/Battle button uses the
existing campaign query and travel command. The inspected province, actual army
location, ownership, income and legal destination cues remain distinct. Home
puts recovery/recruitment costs and availability reasons beside their controls;
roster rows and services scroll within the card. Campaign controls expose New,
Resume, Save, Main Menu and sound. Capture, casualties, recovery, recruitment,
retry and checkpoint routes use the existing authoritative model.

The battle rail uses a native portrait crop, aligned live values, a two-column
action grid, effects, targeting instructions and a persistent footer. Pass,
Cancel and Skip stay visible without scrolling. Campaign return/continuation
controls stay in the footer; restart, logs, settings, sound and longer feedback
live in Battle details. Normal/Fast/Instant and reduced motion retain the same
playback and command paths. Space, R and Escape retain their battle meaning
while command buttons have focus; dialogs own their own keys. The chooser pairs
illustrated action slots with scrollable descriptions and returns focus on
choice or cancellation. Stamina Drain uses the actual grant, command query and
field targeting path. Life and stamina bars on the field use detached
intermediate observations during playback; primary rail vitals also use those
observations when a unit remains selected. Terrain extends across the surrounding
field without changing hex transforms or hit tests.

No rules, scenario data, RNG, state schema, checkpoint format or Python oracle
changed. `PYTHON_ORACLE: NOT_REQUIRED` remains the task's declaration.

## Availability and future connections

| Surface | Working now | Temporarily illegal | Unavailable / connection boundary |
|---|---|---|---|
| Menu | Three playable entries, Options sound, Controls, About, Quit | — | Multiplayer is disabled and labeled; a future implementation needs its own real route. |
| Map | Province inspection, legal Travel/Battle, Map/Home, campaign controls, actual gold/turn/objective | Travel query reasons; saving before a run or during battle | Crystals are a labeled em dash, with no authored resource value. A future value must come from the model. |
| Home | Roster inspection, recovery, recruitment | Existing service queries decide location, cost, wounds and capacity; reasons are inline | Construction is disabled with a visible reason. It requires a future authoritative command/query. |
| Battle | Move/melee, ranged, granted Stamina Drain, picker, effects/details, pass/cancel, playback, skip, campaign return/retry | Selection, target/range/ammo/restrictions, spent actions, completion and playback gates | Spell casting is explicitly unavailable in the picker, with a persistent description. Future casting must enter through an authorized catalogue and command path. Empty cells are inert and outside tab order. |

An ungranted Stamina Drain remains disabled in the chooser with a grant reason;
the existing direct granted-action control remains specific to its unit.
Disabled artwork never substitutes for an enabled command.

## Measured geometry

These are scene measurements from the private capture rehearsal, with native
font metrics and no display rendering. Tests disable root window stretching
when measuring SubViewports: Godot's headless dummy window is only 64×64 and
otherwise distorts font metrics. Runtime window settings are unchanged.

| Viewport | Panorama height / split | Menu row width | Row height | Map/Home field | Resource strip | Battle field / rail |
|---|---|---|---|---|---|---|
| 960×540 | 334.8 px / 62% | 259 px / 26.98% | 29 px | 696×493 | 960×47 | 720×540 / 240×540 |
| 1152×648 | 401.76 px / 62% | 311 px / 27.00% | 36 px | 876×601 | 1152×47 | 912×648 / 240×648 |
| 1440×810 | 502.2 px / 62% | 389 px / 27.01% | 46 px | 1120×763 | 1440×47 | 1152×810 / 288×810 |

The frozen menu split was 24%, with 378-pixel main buttons. The chooser measures
463×261, 552×261 and 691×261 at the three sizes with fallback artwork, with
a scrollable description that takes the extra width. The context card ranges
from 264 to 320 pixels. The battle rail is deliberately wider than the
reference's approximate 14% to fit EGO labels and hit targets: 25%, 20.83% and
20% respectively, down from the frozen 320-pixel rail. Pass, Cancel, Skip and
campaign return fit at minimum size with local artwork.

## Validation and capture evidence

- `python3 tools/run_godot_tests.py`: attempted from a clean cache. The editor
  scan is blocked by prohibited TCP listening (`_sock == -1`, `ERR_CANT_CREATE`).
  The runner classifies the resulting `FAILED` marker as compile failure.
  No GDScript parse/compiler errors are reported.
- Supplemental execution using the runner's own discovery, process execution,
  timeout and error classification: **41 passed, one expected missing-pack
  skip, zero failed**. This does not replace the normal-WSL clean runner.
  Includes existing deterministic combat/playback tests, both full strategic
  routes, casualty/recovery/recruitment/save/resume/retry, short campaign and
  playable entry points.
- The presentation matrix covers local, missing and partial assets at 960×540,
  1152×648 and 1440×810. Bounds checks include compact resource strips,
  separate province targets, action-picker bounds and focus return. New tests
  exercise keyboard Map → Home → Map, chooser activation/targeting/cancel via
  keyboard and pointer, inert spell activation, selected/unselected state,
  playback stamina, persistent Skip, global Space with button focus, and no
  model/RNG changes from inspection or cancellation.
- `python3 -m pytest -q`: **356 passed, nine skipped, four subtests passed**.
- `python3 oracle/test_fixtures_current.py`: all **14** fixture families match.
- Task-qualified scope check against the frozen base, deliberations, repository
  hygiene and `git diff --check`: passed.
- `gdlint`: zero findings on the identical touched existing file set at both the
  frozen base and working tree; new GDScript files also pass.
- Capture choreography: before-local and after-local/fallback/partial rehearsal
  passed at all three sizes. Measurements and logs are private under
  `captures/cx031/`. The actual rendering attempt failed because WSLg X11
  display `:0` and Wayland are unavailable in the sandbox. **No new rendered
  stills, video or audio acceptance is claimed.**

Private output root:
`/home/dantimson/project_ego/.local/eador-art-review.TxEjLB`.
`CX-031-review.md` records native DAT inspection, selected keys, exact crops,
rejected/ambiguous candidates, geometry and the media manifest. Validation logs
and the changed-file inventory are under `captures/cx031/validation/`.

## Exact WSL host capture command

Run from this checkout on normal WSL after the clean Godot runner passes:

```bash
python3 tools/capture_reference_review.py \
  --godot /home/dantimson/.local/opt/godot-4.3/Godot_v4.3-stable_linux.x86_64 \
  --asset-root /home/dantimson/project_ego/.local/eador-art-review.TxEjLB
```

The command requires a working WSLg display. It archives the frozen base into
temporary sources without VCS operations and writes only private review output.
Expected output is `captures/cx031/capture-results.json`, before-local and
three after-mode directories containing PNGs and `*-geometry.json` files. At
1152×648 each before set contains menu, selected-province map, Home and
selected-unit battle; each after set adds the real granted-action chooser and
targeting view. The same stills at 960×540 include the dense fallback chooser
and battle, and 1440×810 supplements the geometry review. The JSON manifest
names every file; a successful run reports all four groups PASS and
`rendered: true`. Rendered acceptance still requires inspecting these images.

For a single optional movement/audio review, the accepted CX-030 Movie Maker
path remains available (ffmpeg/ffprobe required):

```bash
python3 tools/capture_interaction_review.py \
  --godot /home/dantimson/.local/opt/godot-4.3/Godot_v4.3-stable_linux.x86_64 \
  --asset-root /home/dantimson/project_ego/.local/eador-art-review.TxEjLB \
  --mode local --size 1152x648
```

Its output remains `captures/cx030/local-1152x648/interaction.mkv`; it is not
needed to produce CX-031 stills. For measurements without claiming rendering,
add `--rehearse` to the CX-031 command. This writes
`rehearsal-results.json` separately from rendered results.

## Changed-file inventory

- Scene composition: `game/demo/demo_main.gd`,
  `game/campaign/strategic_main.gd`, `game/campaign/province_map.gd`,
  `game/tactical/tactical_controller.gd`.
- Presentation: `game/presentation/presentation_theme.gd`,
  `game/presentation/unit_dossier.gd`,
  `game/tactical/tactical_battlefield_view.gd`.
- Private mapping/capture tooling: `tools/map_campaign_art.py`,
  `tools/capture_reference.gd`, `tools/capture_reference_review.py`.
- Tests: `tests/test_reference_layout.gd`,
  `tests/test_campaign_presentation.gd`, `tests/test_ui_layout.gd`,
  `tests/test_demo_release.gd`, `tests/test_strategic_lifecycle.gd`.
- Task record: this review, `docs/codex/tasks/CX-031.md`,
  `docs/CODEX_WORK_QUEUE.md`.


## Review follow-up

The original normal-WSL clean run passed 41 scripts with one expected skip,
and all four capture groups completed. The first captures exposed repeated
action descriptions and an estate sprite enlarged to fill most of the Home
field. This follow-up caps the estate at twice its source dimensions, sizes
the context card with the viewport, and lets the footer follow its controls'
minimum height. The chooser reflows while open and lists each availability
reason once. A scrollable battle rail body keeps the command footer reachable
when content grows.

The clean Godot suite passed after the follow-up (41 passed, one expected
skip). Updated host stills show the smaller estate in the settlement, a
single description for the selected action, and visible Pass, Cancel,
Skip and campaign return at 960×540. Home roster details and additional
chooser reasons remain in their respective scroll regions.
