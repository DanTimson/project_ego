# Repository layout — Project EGO

## Invariant

**`core/` may never reference `game/`.**

The rules must remain usable without a scene tree. This is what permits the
Python/GDScript differential harness, deterministic scenarios, AI simulation
and future tooling.

A CI check should enforce the boundary:

```sh
! grep -rn --include='*.gd' -E '(res://game/|\bgame\.)' core/ \
  || { echo "core/ references game/ — dependency inversion"; exit 1; }
```

## Current high-level layout

```text
project_ego/
├── README.md
├── AGENTS.md
├── project.godot
├── eador_runtime.h               # schema-14 Ghidra import/evidence header
│
├── core/                         # pure GDScript model and rules
│   ├── ids.gd
│   ├── rng.gd
│   ├── trace.gd
│   ├── content/
│   ├── model/
│   ├── rules/
│   └── battle/
│
├── oracle/                       # Python reference implementation and tests
├── tests/                        # independently runnable headless GDScript tests
├── tools/                        # offline extraction/conversion/analysis
├── packs/                        # Project-owned bindings and overrides
├── scenarios/                    # deterministic scenario inputs
├── game/                         # Godot presentation and devtools
│
└── docs/
    ├── ARCHITECTURE.md
    ├── STATUS.md
    ├── FORMULAS.md
    ├── OPEN_QUESTIONS.md
    ├── REVERSE_ENGINEERING.md
    ├── FUNCTION_MAP.csv
    └── LAYOUT.md
```

This diagram is intentionally high-level. The filesystem is the authoritative
list of current modules; this document defines boundaries and ownership.

## Directory ownership

### `core/`

Pure, headless GDScript.

Current major areas:

- `content/` — content database, pack bindings and handler registry;
- `model/` — combatants, modifiers, actions, options, battlefield and status
  model;
- `rules/` — formulas, resolution hooks and handlers;
- `battle/` — state, action points, rounds, scenarios and AI scaffolding.

`core/model/status.gd` currently exists as an empty placeholder. Do not describe
timed statuses as ported until that file and its tests reproduce runtime-node
semantics.

### `oracle/`

Python reference rules, scenario machinery and tests. It is a permanent
compatibility layer, not disposable tooling.

### `tests/`

Headless GDScript tests. Each `test_*.gd` script is runnable independently with:

```sh
godot --headless --script tests/test_damage.gd
```

Fixtures and scenarios should compare ordered traces whenever ordering or RNG
consumption matters.

### `tools/`

Offline Python utilities for:

- `.var` parsing and conversion;
- pack construction from a local installation;
- schema and cross-reference analysis;
- documentation generation.

Nothing under `tools/` is required by the shipped runtime.

### `packs/`

Only Project EGO material:

- pack metadata;
- bindings from numeric opcode to stable handler;
- overrides and corrections;
- locally generated, ignored data.

Original game assets and tables are not committed.

### `game/`

Presentation and developer UI. It may depend on `core/`; the reverse dependency
is forbidden. The current main scene is the asset viewer, not a finished game
shell.

### `docs/`

- `ARCHITECTURE.md` — dependency and evidence architecture.
- `STATUS.md` — coverage matrix and compatibility boundary.
- `FORMULAS.md` — quantitative and ordering reference.
- `OPEN_QUESTIONS.md` — unresolved facts and contradictions.
- `REVERSE_ENGINEERING.md` — consolidated binary-derived checkpoint.
- `FUNCTION_MAP.csv` — address-indexed recovered-function map.
- `LAYOUT.md` — this file.

### Root reverse-engineering header

`eador_runtime.h` is the stable Ghidra import target. Its type names remain
unversioned while `EADOR_RUNTIME_SCHEMA_VERSION` records the layout checkpoint.
It is evidence/documentation, not production runtime code.

## Godot-specific rules

- Repository root is the Godot project root.
- Core types use `class_name` and do not require scene preloads.
- `core/` contains no `.tscn`.
- `.gdignore` belongs in non-Godot trees such as `docs/`, `oracle/` and
  `tools/`.
- Autoloads may coordinate presentation but may not become implicit
  dependencies of the core simulation.

## Where new work goes

| work | destination |
|---|---|
| new formula or mechanic | `oracle/`, `core/rules/`, tests, `FORMULAS.md` |
| activated ability | pack binding + `Action`/handler + tests |
| timed effect | status model/handler + trace events + expiry tests |
| extracted original data | local ignored pack data, never Git |
| recovered executable behaviour | `REVERSE_ENGINEERING.md`, function map, tests |
| unresolved conflict | `OPEN_QUESTIONS.md` |
| strategic province/economy work | new `core/strategic/` modules after oracle spec |
| UI/animation | `game/`, consuming core results or traces |

## Near-term integration order

1. Commit the documentation/evidence checkpoint.
2. Resolve charge and RNG compatibility conflicts.
3. Implement GDScript runtime statuses.
4. Classify battle-action effect types and modifier IDs.
5. Add binary-derived golden tests for progression and combat lifecycle.
6. Extract `.var` schemas.
7. Normalize strategic economy.
8. Consolidate tactical AI.
9. Expand presentation only after the relevant rules are trace-stable.
