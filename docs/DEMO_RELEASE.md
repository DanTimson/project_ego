# Milestone demo releases

Project EGO Milestone 0.2 has one Windows x86-64 engine payload and two package
modes. Release packaging changes presentation and distribution only; it does not
change combat rules.

## Prerequisites

- a clean tracked worktree and index at the revision to release;
- Git and Python 3 for the builder;
- Godot 4.3 with Windows release export templates.

The active development setup uses the Steam 4.3 stable editor and its portable
template directory:

```text
/mnt/d/SteamLibrary/steamapps/common/Godot Engine/editor_data/export_templates/4.3.stable/
```

`windows_release_x86_64.exe` must be present. `GODOT_BIN` or `--godot` can select
another compatible editor/wrapper. The tracked preset is `Windows Desktop
x86-64` in `export_presets.cfg`; it exports `Project EGO.exe` plus the external
`Project EGO.pck`.

## Build commands

`tools/build_demo.py` remains the authoritative single-mode packager for
ordinary developer builds. From a clean committed revision, for example:

```bash
python3 tools/build_demo.py --mode public --milestone 0.2
```

The official public/private path is the small pair wrapper. In the accepted WSL
setup, run it from the Windows-backed worktree and put its temporary export tree
under a Windows-backed caller-owned parent:

```bash
python3 tools/build_release_pair.py --milestone 0.2 \
    --asset-root .local/eador_assets --staging-parent /mnt/d
```

The pair wrapper runs the existing packager once per mode, requires both runtime
smokes, and then reopens both ZIPs through the existing public/private scanners,
exact private-closure validator and runtime identity checks. It writes the
ignored sidecar `dist/Project-EGO-Milestone-0.2-release-pair.json` only after the
complete pair passes. The sidecar records commit, Godot version, deterministic
epoch, artifact and runtime hashes, inventories, content-boundary results and
smoke results.

An official pair uses the exact released commit timestamp. An explicitly set
`SOURCE_DATE_EPOCH` takes precedence. Thus both modes receive the same
`built_at`, and repeated packaging with the same tracked commit, Godot payload
and private closure is byte-identical. This is not a promise across arbitrary
Godot versions: the exact reported Godot 4.3 version is recorded. Single-mode
ad-hoc builds retain wall-clock timestamps unless `--reproducible` or
`SOURCE_DATE_EPOCH` is selected.

The builder refuses tracked index/worktree changes. It materializes exact
tracked `HEAD` with `git archive`, so ignored files, untracked worktree material
and local/private data cannot enter the export project. Each invocation creates
one uniquely owned temporary directory below the selected parent and removes
only that child; it never recursively removes the caller's parent. The portable
default remains ignored `.release_staging/`. The engine/PCK cache remains keyed
by exact commit and Godot version under ignored `dist/.engine-cache/`.

Output is written to:

```text
dist/public/Project-EGO-Milestone-0.2-Windows-x86_64.zip
dist/private/Project-EGO-Milestone-0.2-private-Windows-x86_64.zip
```

Each ZIP opens directly at the application files. `BUILD.json`, `BUILD.txt` and
`demo-info.txt` record Project EGO, milestone, exact commit, Godot version, mode
and UTC build time. The visible menu subtitle and About dialog use adjacent
`BUILD.json`; development runs use an explicit development fallback and generate
no tracked metadata file.


## Window, resizing, and Windows DPI acceptance

Milestone 0.2 requests a 1152×648 logical content area and enforces a 960×540
minimum. This default was selected to leave room for Windows decorations and the
taskbar on a 1920×1080 desktop at 150% scaling; it is not an arbitrary increase
to conceal clipping. Below the minimum the OS blocks further resize. Between the
minimum and default, the battlefield uniformly scales inside its region and the
right panel remains fixed-width with vertical scrolling. Above the default,
`expand` aspect handling uses the additional logical area and the battlefield
continues to fit without crossing the panel.

Godot 4.3 high-DPI support is explicitly enabled. The project uses
`canvas_items` plus `expand` with the default content scale factor of 1.0, so
fonts, Controls, battlefield presentation, and optional textures share one
scaling path. Do not add a Windows compatibility override or a separate font DPI
multiplier, either of which can double-apply scaling. Pointer input is transformed
back into `TacticalBattlefieldView` local coordinates before
`TacticalCoordinateAdapter` hit testing.

Portable tests validate logical layout at 960×540, 1152×648, and 1440×810. They
do **not** change or simulate the user's Windows display scale. Before a
Milestone 0.2 release, run the exported public and private builds using this
manual matrix and record the scale shown by **Settings → System → Display →
Scale**:

| Windows scale | required check |
|---:|---|
| 100% | menu, both dialogs, tactical play, minimum/default/larger resize |
| 125% | same checks; verify text and mapped/fallback artwork scale together |
| 150% | **required release gate** on 1920×1080; verify the default opens wholly inside the work area |
| 200% | verify minimum-size usability on an available work area and record any OS work-area limitation |

At every scale verify Play Demo, Controls, About This Build, Quit, selection,
movement, melee, ranged, pass, cancel, long refusal/event text, scrollbars, panel
containment, and pointer-to-hex accuracy. A headless logical-size PASS must never
be reported as a Windows DPI PASS. Do not change the user's scale automatically.

## Public/private content boundary

The **public** package has the executable/PCK, build metadata and recipient
README. It intentionally has no original-derived presentation. The packager
fails closed on local-asset trees, `.local`, DAT files, extraction manifests,
EGOgrabber material and developer path leakage. Fallback terrain, units,
portraits and UI remain playable without any local files.

The **private** package adds only `local_assets/` beside the same executable and
PCK. The builder strictly validates the prepared version-1 index and version-1
or version-2 mapping, calculates the exact set of mapped image keys, rejects
unknown fields/types, missing files, traversal, absolute paths and escaping
symlinks, then copies only that closure. It writes a new runtime index whose
relative paths stay inside `local_assets/`; DAT files and extraction directory
layout are never copied. Private/local artifacts remain outside the public
release pipeline and are never tracked.

At runtime `TacticalAssetResolver` chooses presentation roots in this order:

1. explicit index/mapping or `EGO_ASSET_ROOT` supplied by a test/tool;
2. exported executable-adjacent `local_assets/`;
3. development `res://.local/eador_assets/`;
4. project-authored fallback rendering.

An absent optional root is normal and does not affect canonical content
identity or combat state.

## Fresh-clone rebuild and reproducibility procedure

Milestone 0.2 and its official public/private pair are already accepted. The
following commands document how to rebuild or repeat the accepted checks from a
fresh clone at the exact release commit on a Windows-backed volume; they are not
pending original-release acceptance instructions. A public-only rebuild does not
require local/private assets:

```bash
git clone <reviewed-project-ego-source> /mnt/d/project-ego-release-0.2
cd /mnt/d/project-ego-release-0.2
git checkout --detach <exact-release-commit>
python3 tools/build_demo.py --mode public --milestone 0.2 \
    --reproducible --staging-parent /mnt/d
python3 -m pytest -q tools/test_build_demo.py tools/test_build_release_pair.py
```

With a valid prepared private root outside tracked Git content, repeat the
official pair build/check:

```bash
python3 tools/build_release_pair.py --milestone 0.2 \
    --asset-root <prepared-private-root> --staging-parent /mnt/d
```

A public-only rebuild can be checked without the private root. Repeating the
pair checks requires that root, both artifacts passing all scanner, smoke,
identity and closure gates, and the generated pair manifest. Record the exact
commit, Godot version, pair-manifest hash, both artifact hashes, runtime smoke
results and Windows DPI matrix. Determinism is guaranteed for packaging a fixed
Godot export payload; independent PCK export byte identity is not claimed.

## Recipient workflow

Private-demo recipients need only:

1. Extract the ZIP.
2. Run **Project EGO.exe**.
3. Choose **Play Demo**.

They do not install or configure Git, Python, Godot, EGOgrabber or an original
game. The public workflow is the same, using authored fallback visuals. For a
developer's direct tactical route, run:

```bash
godot --path . game/tactical/tactical_main.tscn
```

The normal project launch opens the milestone menu.
