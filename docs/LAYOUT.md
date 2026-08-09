# Repository layout — Project EGO

## Invariant

**`core/` may never reference `game/`.**

The rules must remain usable without a scene tree. This keeps deterministic
scenario execution, Python/GDScript differential testing, AI simulation, and
future tooling independent of presentation.

A simple boundary check is:

```sh
! grep -rn --include='*.gd' -E '(res://game/|\bgame\.)' core/ \
  || { echo "core/ references game/ — dependency inversion"; exit 1; }
```

The full repository hygiene suite is the preferred routine check:

```sh
python3 oracle/test_repository_hygiene.py
```

## Current high-level layout

```text
project_ego/
├── README.md
├── AGENTS.md
├── project.godot
├── export_presets.cfg
├── eador_runtime.h               # schema-versioned Ghidra evidence header
│
├── core/                         # pure GDScript model/rules/battle state
│   ├── content/
│   ├── model/
│   ├── rules/
│   └── battle/
│
├── oracle/                       # Python reference implementation + fixtures
├── tests/                        # headless GDScript and integration tests
├── tools/                        # offline build/extraction/validation utilities
├── packs/                        # project-owned bindings/overrides + ignored data
├── scenarios/                    # deterministic portable scenario inputs
├── game/                         # Godot tactical/demo/devtool presentation
│   ├── autoload/
│   ├── battle/
│   ├── tactical/
│   ├── demo/
│   └── devtools/
│
├── evidence/                     # permitted mixed-lineage research support
└── docs/                         # architecture, evidence, governance, research
```

This diagram is intentionally high-level. The filesystem is the authoritative
module list; this document defines dependency direction, ownership, and where
new work belongs.

## Directory ownership

### `core/`

Pure, headless GDScript. It may not depend on scenes, Nodes, autoloads, or
presentation state.

Current major areas:

- `content/` — content database, pack/profile resolution, bindings, and handler
  registry;
- `model/` — combatants, modifiers, actions, battlefield state, options, and
  status/runtime models;
- `rules/` — formulas, modifier aggregation, action/status policy, resolution
  hooks, and handlers;
- `battle/` — action points, rounds, scenarios, command execution, traces, and
  manual-session state.

Mechanics should live here only after their semantics are sufficiently specified.
Do not use an implementation convenience in `core/` to settle an unresolved
compatibility question.

### `oracle/`

The Python reference implementation and deterministic scenario machinery.

It is a permanent compatibility layer, not disposable tooling. When a mechanic
exists in both languages, oracle/GDScript parity should be explicit and tests
should distinguish ordering-sensitive behavior rather than only matching final
numbers.

Generated fixture freshness is checked with:

```sh
python3 oracle/test_fixtures_current.py
```

### `tests/`

Headless GDScript tests and integration coverage.

The suite now includes:

- rules/model parity tests;
- scenario/content tests;
- tactical input and playable-slice integration;
- responsive UI/layout coverage;
- local-asset and portable-fallback behavior;
- demo/release checks.

Each `test_*.gd` script remains independently runnable, for example:

```sh
godot --headless --script tests/test_damage.gd
```

The normal aggregate runner is:

```sh
python3 tools/run_godot_tests.py
```

### `tools/`

Offline Python utilities for repository work. Current responsibilities include:

- `.var` parsing and pack construction from a local installation;
- generated-binding checks;
- scenario/demo build support;
- public-lineage inventory and transfer-surface checks;
- validation/test runners;
- documentation/governance support.

Nothing under `tools/` should become a runtime dependency of the shipped Godot
project.

### `packs/`

Project EGO-owned pack metadata and generated-data boundaries:

- pack/profile metadata;
- numeric opcode bindings to stable handlers;
- Project EGO overrides/corrections;
- locally generated ignored data.

Original game assets and extracted tables are not committed. Committed binding
files may intentionally remain unpopulated skeletons when local generation is
required.

### `scenarios/`

Portable deterministic scenario inputs used by the oracle/core harness.

Scenario identity is intentionally split between stable content identity and
battle-instance identity. Synthetic fixtures must not smuggle bulk original
content into the repository.

### `game/`

Godot presentation. It may depend on `core/`; the reverse dependency is
forbidden.

Current presentation areas include:

- `tactical/` — the playable tactical vertical slice, battlefield view,
  controller, coordinate adapter, asset resolver, and tactical scene;
- `battle/` — trace/presentation helpers;
- `demo/` — repeatable demo/release entry point;
- `devtools/` — asset and development viewers;
- `autoload/` — presentation coordination only.

The tactical scene is now a real integration surface, not merely a future
placeholder. Presentation still remains downstream of rules and deterministic
battle state.

### `evidence/`

Research-support material allowed in the current mixed research/prototype
lineage. This directory does not change the rule that original executables,
assets, bulk extracted data, Ghidra databases, and large raw decompiler dumps
remain local/private.

See `docs/PROVENANCE_AND_DATA_POLICY.md` and
`docs/PUBLIC_LINEAGE_GATE.md`.

### `docs/`

The main navigation documents are:

- `ARCHITECTURE.md` — dependency, state, profile, and evidence architecture;
- `STATUS.md` — current implementation/compatibility coverage;
- `FORMULAS.md` — quantitative and ordering reference;
- `OPEN_QUESTIONS.md` — unresolved facts and contradictions;
- `PLAYABLE_TACTICAL_SLICE.md` — current tactical integration surface;
- `DEMO_RELEASE.md` — repeatable demo/export workflow;
- `CONTENT_REFERENCE_MODEL.md` — content/instance identity rules;
- `REVERSE_ENGINEERING.md` — consolidated binary-derived checkpoint;
- `FUNCTION_MAP.csv` — address-indexed recovered-function map;
- `COMPATIBILITY_TEST_MATRIX.md` — rule-to-test/evidence coverage;
- `WORK_ALLOCATION.md` — semantic ownership and delegated execution;
- `CODEX_WORK_QUEUE.md` and `codex/tasks/` — bounded executor task contracts;
- `PUBLIC_LINEAGE_*.md/csv` — mixed-lineage/public-lineage transfer governance;
- `observations/` — controlled observation protocols and result sheets;
- `deliberations/` — cross-side architecture/evidence decisions.

The task directory name `docs/codex/` is retained as a repository namespace even
when the bounded executor is Prime Agent or another implementation agent.

### Root reverse-engineering header

`eador_runtime.h` is the stable Ghidra import target. Its type names remain
unversioned while `EADOR_RUNTIME_SCHEMA_VERSION` records the layout checkpoint.
It is evidence/documentation, not production runtime code.

## Godot-specific rules

- Repository root is the Godot project root.
- Core types use `class_name` and do not require scene preloads.
- `core/` contains no `.tscn`.
- `.gdignore` belongs in non-Godot trees such as `docs/`, `oracle/`, and
  `tools/`.
- Autoloads may coordinate presentation but may not become implicit dependencies
  of core simulation.
- `export_presets.cfg` and release tooling belong to the presentation/build
  layer, not the rules layer.

## Where new work goes

| work | destination |
|---|---|
| new formula or mechanic | `oracle/`, `core/rules/`, tests, `FORMULAS.md` |
| combatant/runtime state | `core/model/`, oracle parity, tests |
| activated ability | pack binding + `Action`/handler + tests |
| status/runtime effect | status model/rules + tests; lifecycle only when evidence-ready |
| extracted original data | local ignored pack data, never Git |
| recovered executable behaviour | evidence docs/function map + neutral tests/spec |
| unresolved conflict | `OPEN_QUESTIONS.md` or a deliberation |
| controlled original-game observation | `docs/observations/` |
| strategic province/economy work | future `core/strategic/` modules after specification |
| tactical UI/animation | `game/tactical/`, consuming core results/traces |
| demo/export packaging | `game/demo/`, `tools/`, `export_presets.cfg` |
| delegated implementation contract | `docs/codex/tasks/` + queue row |

## Integration priorities

Do not maintain a numbered implementation roadmap here; it becomes stale as
research closes individual questions. Current priorities and blockers live in:

- `docs/STATUS.md`;
- `docs/OPEN_QUESTIONS.md`;
- `docs/BINARY_REQUESTS.md`;
- `docs/CODEX_WORK_QUEUE.md`;
- accepted deliberation decisions and observation protocols.

`LAYOUT.md` should change when ownership or dependency boundaries change, not
every time a mechanic advances.
