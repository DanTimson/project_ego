# Repository layout — project_ego

## The one rule everything else serves

**`core/` may never reference `game/`.** Not a class, not a signal, not a
`preload`. The dependency runs one way only.

That single constraint is what keeps the headless harness possible, which is
what keeps differential testing against the original possible, which is the
only way to know the remake is correct. Everything below is arranged to make
violating it obvious.

Enforce it in CI with a grep, not with discipline:

```sh
! grep -rn --include='*.gd' -E '(res://game/|\bgame\.)' core/ \
  || { echo "core/ references game/ — dependency inversion"; exit 1; }
```

---

## Layout

```
project_ego/
├── project.godot                 # Godot project root == repo root
├── .gdignore-note                # see "Godot specifics" below
│
├── core/                         # PURE LOGIC. No Node. No scene tree. Headless.
│   ├── ids.gd                    # AbilityId / UpgradeId / UnitId wrappers
│   ├── rng.gd                    # named streams; swap point for the real PRNG
│   ├── trace.gd                  # self-explaining values
│   │
│   ├── content/
│   │   ├── content_db.gd         # constructed instance, never an autoload
│   │   ├── content_pack.gd       # tables + bindings; fails loudly on unbound
│   │   ├── ability_registry.gd   # handler NAME -> implementation
│   │   └── loader.gd             # reads the converted JSON
│   │
│   ├── model/
│   │   ├── combatant.gd          # base stats + modifiers + per-round state
│   │   ├── modifier.gd           # the atomic value type
│   │   ├── action.gd             # ACTIVATED abilities — cost, targeting, legality
│   │   ├── status.gd             # timed effects with expiry
│   │   ├── option.gd             # level-up options + availability schedules
│   │   └── battlefield.gd        # grid, tiles, adjacency
│   │
│   ├── rules/
│   │   ├── hooks.gd              # the Hook enum — THE resolution order
│   │   ├── pipeline.gd           # resolve(base, mods, hook, ctx) -> [value, trace]
│   │   ├── damage.gd             # verified against the published tables
│   │   ├── stamina.gd
│   │   ├── morale.gd
│   │   ├── wounds.gd
│   │   ├── spells.gd             # PowerMod / DurationMod / resist model
│   │   └── handlers/             # one file per hook family, ~10 files
│   │       ├── stat_passive.gd
│   │       ├── defence_apply.gd
│   │       ├── on_hit.gd
│   │       ├── counterattack.gd
│   │       └── ...
│   │
│   ├── battle/
│   │   ├── battle_state.gd
│   │   ├── round_loop.gd         # round -> side phase -> free interleaved activation
│   │   ├── action_points.gd      # movement points, attack availability, per-round flags
│   │   └── ai/
│   │       ├── evaluator.gd
│   │       └── policy.gd
│   │
│   └── strategic/                # later: province layer, economy, karma
│
├── packs/                        # OUR files only. Original data is NOT committed.
│   ├── genesis/
│   │   ├── pack.toml             # id, display name, expected source fingerprint
│   │   ├── bindings.toml         # opcode number -> handler name
│   │   └── overrides/            # our corrections and additions
│   └── new_horizons/
│       ├── pack.toml
│       └── bindings.toml
│
├── game/                         # GODOT PRESENTATION. Depends on core. Never reverse.
│   ├── autoload/
│   │   ├── vfs.gd                # existing — manifest-driven asset access
│   │   ├── logger.gd
│   │   └── app.gd                # holds the ACTIVE ContentDb for the UI only
│   ├── battle/
│   │   ├── battle_view.tscn
│   │   ├── unit_sprite.gd
│   │   └── trace_replay.gd       # plays back a trace file — no rules here
│   ├── ui/
│   ├── theme/
│   └── devtools/
│       └── asset_viewer.tscn     # moved from scenes/tools/
│
├── tools/                        # OFFLINE. Python. Never ships.
│   ├── var/
│   │   ├── eador_var.py          # parser, schema inference, xref, selftest
│   │   ├── options.py            # unit-major -> option-major transposition
│   │   ├── hooks.py              # hook taxonomy + opcode classifier
│   │   └── doc_merge.py          # Eadoropedia join
│   ├── extract/
│   │   └── build_pack.py         # local install -> packs/<id>/data/ (gitignored)
│   └── reference/
│       └── abil_doc.json         # extracted ability documentation
│
├── oracle/                       # Python reference implementation. CI only.
│   ├── combat.py                 # the verified pipeline
│   ├── test_combat.py            # checks against published tables
│   └── fixtures/                 # expected traces the GDScript port must match
│
├── tests/                        # GDScript. Run headless.
│   ├── test_damage.gd
│   ├── test_pipeline.gd
│   ├── test_options.gd
│   └── scenarios/
│       └── *.json                # deterministic battles: seed + actions + expected
│
├── docs/
│   ├── ARCHITECTURE.md
│   ├── FORMULAS.md               # every formula with its source citation
│   ├── OPEN_QUESTIONS.md
│   └── LAYOUT.md                 # this file
│
└── .github/workflows/ci.yml      # dependency grep, oracle tests, headless GDScript tests
```

---

## Why the unusual bits

**`packs/` holds only our bindings.** The `.var` data belongs to Bokulev and
Jazz. `tools/extract/build_pack.py` reads a local install and writes
`packs/<id>/data/`, which is gitignored. The repo ships the opcode-to-handler
mapping — which is our work — and nothing else. This also removes the current
`var.zip`, which is Jazz's content sitting in a public repo.

**`oracle/` is separate from `tools/`** because they have different lifetimes.
Tools run once at authoring time and their output is committed. The oracle runs
on every CI pass forever, because it is what the GDScript port is diffed
against. Mixing them invites someone to "clean up" the oracle as dead code.

**`core/battle/ai/` sits inside core, not in game.** The AI evaluates rules, so
it needs the headless simulation. Putting it in `game/` would force the rules to
depend on presentation to think.

**`handlers/` is a directory, not a file.** ~10 hook families, each with its own
file. The alternative — one giant match statement — is the thing we are
replacing.

---

## Godot specifics

- **Repo root is the Godot project root.** Nesting the Godot project one level
  down would keep `tools/` and `oracle/` outside the import scanner, but breaks
  every convention and confuses tooling. Keep it flat.
- **Use `class_name` on every core class** so they resolve globally without
  `preload` chains. Core has no scenes, so path coupling would be pure cost.
- **Drop a `.gdignore` in `tools/`, `oracle/`, and `docs/`.** Godot skips `.py`
  and `.md` anyway, but `.gdignore` stops it walking those trees at all, which
  matters once the JSON fixtures get large.
- **`core/` contains no `.tscn`.** If a scene file appears there, the dependency
  rule has already been broken.

---

## Migration from the current repo

| now | goes to | note |
|---|---|---|
| `autoload/vfs.gd` | `game/autoload/vfs.gd` | keep as-is, it's sound |
| `autoload/logger.gd` | `game/autoload/logger.gd` | still a stub |
| `autoload/content_db.gd` | `core/content/content_db.gd` | **stop being an autoload** — becomes a constructed instance; `game/autoload/app.gd` holds the active one for the UI |
| `scenes/tools/asset_viewer.*` | `game/devtools/` | also delete the `ass*.tmp` files |
| `tools/import_vars_full.py` | delete | superseded by `tools/var/eador_var.py` |
| `var.zip` | delete | not ours to redistribute |
| `node_2d.tscn` | delete or rename | placeholder main scene |

---

## Build order

1. `core/rules/` — port `oracle/combat.py`, diff against its fixtures.
2. `core/model/` — `Combatant`, `Modifier`, per-round state.
3. `core/battle/action_points.gd` + `round_loop.gd` — the interleaved activation model.
4. `core/model/action.gd` — activated abilities. Largest known gap.
5. `core/content/` — pack loading, unbound-opcode report as the progress meter.
6. `tests/scenarios/` — first deterministic battle.
7. Only then `game/battle/` — and via `trace_replay.gd`, not by computing anything.
