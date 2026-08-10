# Project EGO

Project EGO is an independent, data-driven reimplementation and extension
platform for **Eador: Genesis** combat and content systems, with compatibility
profiles for the original game, New Horizons, and intentionally modernized
native behavior.

The project is built around a deterministic rules core rather than around copied
original code or bundled game data. Mechanics are recovered from published
descriptions, controlled observation, extracted local data, and inspection of
the original executable, then restated as new specifications, tests, oracle
logic, and GDScript implementation.

See [docs/PROVENANCE_AND_DATA_POLICY.md](docs/PROVENANCE_AND_DATA_POLICY.md) for
the evidence and data policy.

## Current state

Project EGO is no longer only a headless rules prototype. The repository now
contains a **playable tactical vertical slice** backed by the same deterministic
core used by the oracle and headless tests. Milestone 0.2 remains the mixed
research/prototype lineage at G0; it is not a stable community API or a complete
Eador battle implementation.

Implemented or substantially integrated:

- deterministic Python and GDScript rule paths with scenario/trace parity;
- ordinary melee, counterattack, ranged attack, defence, stamina, wound, morale,
  charge, and action-terminal mechanics;
- modifiers, activated actions, auras, level-up options, and first-class runtime
  statuses with stable stacking, resistance, and explicit manipulation semantics;
- battlefield coordinates, occupancy, pathfinding, movement, and side/round
  scheduling;
- content packs, profile routing, opaque opcode bindings, and strict
  battle-instance/content identity;
- a playable tactical Godot scene with mouse routing, responsive layout, local
  asset resolution, and committed fallback presentation;
- reproducible public/private demo packaging with a verified pair manifest;
- reverse-engineering evidence, function maps, compatibility matrices, and
  deterministic fixtures.

Important remaining work includes:

- exact legacy PRNG call ordering and reseed lifecycle;
- exact timed-status automatic tick/expiry boundaries;
- incomplete battle-action/effect and modifier dictionaries;
- remaining lifecycle boundaries including automatic status timing, strategy
  writeback, corpses, rewards, and wider battle effects;
- large-unit footprint and several observation-backed edge cases;
- tactical AI and the strategic layer;
- broader presentation fidelity and original-style UI work.

The precise compatibility boundary changes frequently. See
[docs/STATUS.md](docs/STATUS.md) and
[docs/OPEN_QUESTIONS.md](docs/OPEN_QUESTIONS.md) rather than relying on this
summary for individual mechanics.

## Quick start

The repository root is the Godot project root. The current engine baseline is
Godot 4.3.

Launch the playable tactical slice:

```sh
godot --path . game/tactical/tactical_main.tscn
```

The public repository is designed to remain runnable without redistributing
original Eador assets. Committed project-owned fallback visuals support the
portable tactical/demo path; locally extracted content and assets can be used by
the separate local-content tier where supported. Milestone 0.2 release commands,
Windows-backed WSL staging, reproducible timestamps, the public/private pair
manifest and fresh-clone acceptance are documented in
[docs/DEMO_RELEASE.md](docs/DEMO_RELEASE.md).

Run the main validation suites:

```sh
python3 tools/run_godot_tests.py
python3 -m pytest -q
python3 oracle/test_fixtures_current.py
python3 tools/check_deliberations.py
python3 oracle/test_repository_hygiene.py
```

Individual GDScript tests remain independently runnable, for example:

```sh
godot --headless --script tests/test_damage.gd
```

Tests that require locally generated pack data are explicitly marked and skip
when that data is unavailable:

```sh
python3 -m pytest -q -m requires_pack
godot --headless --script tests/test_scenario_requires_pack.gd
```

Original content remains untracked and is never copied into portable fixtures.

## Architecture

The dependency direction is strict:

```text
tools / local data
        ↓
      packs
        ↓
 oracle ↔ core
          ↓
         game

tests exercise oracle, core, and integration boundaries
```

`core/` must never reference `game/`. The Python oracle is a permanent
compatibility implementation rather than disposable test tooling.

Repository map:

- `core/` — pure GDScript model, rules, content, and battle state.
- `oracle/` — Python reference implementation, deterministic scenario machinery,
  and oracle tests.
- `tests/` — headless GDScript parity, integration, UI, and tactical-slice tests.
- `tools/` — offline extraction, build, validation, release, and governance
  utilities.
- `packs/` — Project EGO pack metadata, bindings, overrides, and ignored local
  generated data.
- `scenarios/` — deterministic scenario inputs.
- `game/` — Godot presentation, tactical UI, demo, and developer tools.
- `docs/` — architecture, formulas, evidence, status, governance, and research
  checkpoints.
- `evidence/` — repository-side research-support material that is permitted to
  remain in the mixed research/prototype lineage.
- `eador_runtime.h` — schema-versioned Ghidra import/evidence header for the
  inspected 32-bit executable.

See [docs/LAYOUT.md](docs/LAYOUT.md) for ownership and placement rules.

## Compatibility and evidence

Project EGO separates three things that are easy to conflate:

1. what the original executable or data demonstrably does;
2. what has been independently observed or verified;
3. what the current Project EGO architecture chooses to expose.

Binary evidence is version-specific. Candidate names remain provisional until
supported by data or localization, and unresolved behavior stays explicitly
open rather than being filled in from architectural convenience.

Useful references:

- [Architecture](docs/ARCHITECTURE.md)
- [Current status](docs/STATUS.md)
- [Formula and ordering reference](docs/FORMULAS.md)
- [Open questions](docs/OPEN_QUESTIONS.md)
- [Playable tactical slice](docs/PLAYABLE_TACTICAL_SLICE.md)
- [Demo/release workflow](docs/DEMO_RELEASE.md)
- [Content reference model](docs/CONTENT_REFERENCE_MODEL.md)
- [Reverse-engineering checkpoint](docs/REVERSE_ENGINEERING.md)
- [Function map](docs/FUNCTION_MAP.csv)
- [Compatibility test matrix](docs/COMPATIBILITY_TEST_MATRIX.md)
- [Provenance and data policy](docs/PROVENANCE_AND_DATA_POLICY.md)
- [Agent/contributor rules](AGENTS.md)

## Data and redistribution policy

Project EGO does **not** redistribute original game executables, assets,
localization corpora, or bulk `.var` content. Extraction and conversion tooling
operates on a user's local installation.

The repository may contain independently written schemas, bindings, tests,
traces, behavioral specifications, and narrowly necessary synthetic fixtures.
Recovered executable behavior is evidence for compatibility, not permission to
copy original code.

The repository is currently the mixed research/prototype lineage described in
[docs/PUBLIC_LINEAGE_GATE.md](docs/PUBLIC_LINEAGE_GATE.md); a separate
community/public implementation lineage has not been triggered.
