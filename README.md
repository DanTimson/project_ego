# Project EGO

Project EGO is a clean-room, data-driven reimplementation and extension platform
for **Eador: Genesis** combat and content systems.

The immediate goal is not presentation parity. It is a deterministic,
headless-compatible rules core whose results can be compared with:

1. a Python reference implementation;
2. published mechanics and extracted `.var` data;
3. controlled observations of the original game;
4. behaviour recovered from the original executable.

The Godot presentation layer is deliberately downstream of the rules core.

## Current state

Implemented or substantially scaffolded:

- deterministic Python and GDScript rule paths;
- attack, defence, stamina and wound calculations;
- modifiers, activated actions and level-up options;
- battlefield coordinates, adjacency, pathfinding and occupancy;
- round/side state, scenarios, traces and headless tests;
- content packs and opaque opcode bindings;
- reverse-engineered runtime layouts and combat execution order.

Still incomplete:

- exact legacy PRNG and seeding compatibility;
- timed status parity in GDScript;
- full battle-action and modifier-ID dictionaries;
- aura and battlefield-generation parity;
- `.var` schema extraction;
- strategic economy and tactical AI parity.

See [docs/STATUS.md](docs/STATUS.md) and
[docs/OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md).

## Repository map

- `core/` — pure GDScript rules and model code; no scene-tree dependency.
- `oracle/` — Python reference implementation and executable evidence.
- `tests/` — headless GDScript parity and integration tests.
- `tools/` — offline extraction, conversion and analysis.
- `packs/` — Project EGO bindings and overrides; original game data is not
  committed.
- `game/` — presentation and developer tools, depending on `core/`.
- `docs/` — architecture, formulas, evidence, status and unresolved questions.
- `eador_runtime.h` — schema-14 Ghidra import header for the inspected
  32-bit executable.

The dependency rule is strict:

```text
tools/data → packs → oracle/core → game
                         ↑
                       tests
```

`core/` must never reference `game/`.

## Useful entry points

- [Architecture](docs/ARCHITECTURE.md)
- [Repository layout](docs/LAYOUT.md)
- [Formula reference](docs/FORMULAS.md)
- [Reverse-engineering checkpoint](docs/REVERSE_ENGINEERING.md)
- [Function map](docs/FUNCTION_MAP.csv)
- [Open questions](docs/OPEN_QUESTIONS.md)
- [Agent instructions](AGENTS.md)

## Running representative tests

Python oracle:

```sh
cd oracle
python3 test_combat.py
```

Individual Godot headless test:

```sh
godot --headless --script tests/test_damage.gd
```

Each `tests/test_*.gd` file is an independently runnable `SceneTree` test.

## Data and compatibility policy

Project EGO does not redistribute original game assets or `.var` content.
Extraction tools operate on a local installation. The repository may contain
Project EGO's own schemas, bindings, tests, traces and independently recovered
behavioural descriptions.

Recovered executable behaviour is version-specific evidence, not permission to
copy original code. Implementations should reproduce behaviour in new code and
preserve uncertainty where the evidence is incomplete.
