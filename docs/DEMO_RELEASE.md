# Milestone demo releases

Project EGO Milestone 0.1 has one Windows x86-64 engine payload and two package
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

From a clean committed revision:

```bash
python3 tools/build_demo.py --mode public --milestone 0.1
python3 tools/build_demo.py --mode private --milestone 0.1 \
    --asset-root .local/eador_assets
```

The builder refuses tracked index/worktree changes. It materializes `git archive
HEAD` under ignored `.release_staging/`, exports only that tree, and removes
staging on success or failure. Ignored `.local/` data is not part of the export
project. The engine/PCK are cached by exact commit and Godot version under the
ignored `dist/.engine-cache/`; both package modes copy that identical payload.
If the other mode's ZIP already exists, hashes are compared again.

Output is written to:

```text
dist/public/Project-EGO-Milestone-0.1-Windows-x86_64.zip
dist/private/Project-EGO-Milestone-0.1-private-Windows-x86_64.zip
```

Each ZIP opens directly at the application files. `BUILD.json`, `BUILD.txt` and
`demo-info.txt` record Project EGO, milestone, exact commit, Godot version, mode
and UTC build time. The About dialog reads adjacent `BUILD.json`; development
runs use an explicit fallback and generate no tracked metadata file.

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
