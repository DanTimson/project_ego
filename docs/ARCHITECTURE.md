# Architecture — Project EGO

## Objective

Project EGO separates three concerns that the original executable combines:

1. **content interpretation** — loading pack data and mapping opaque IDs;
2. **deterministic rules** — computing state transitions without presentation;
3. **presentation** — rendering and input in Godot.

The rules layer must be usable headlessly. This enables differential tests,
scenario replay, AI simulation and future tooling without a live scene tree.

## Dependency direction

```text
local game install
       │
       ▼
tools/ extraction and schema conversion
       │
       ▼
packs/ bindings + locally generated data
       │
       ├──────────────► oracle/ Python reference
       │                         │
       ▼                         ▼
core/ GDScript rules ◄──── fixtures and differential tests
       │
       ▼
game/ presentation
```

The central invariant is:

> `core/` may never reference `game/`.

The reverse dependency is expected: `game/` may construct and call core objects.

## Layer responsibilities

### `tools/`

Offline authoring and analysis:

- parse and convert `.var` files;
- infer schemas and generate reports;
- build local content packs;
- merge documentation and localization;
- process reverse-engineering evidence.

Tools may depend on ordinary Python libraries. Their output must be deterministic
when committed as a fixture or schema.

### `packs/`

Project-owned metadata:

- pack identity and source fingerprint;
- opcode-to-handler bindings;
- compatibility overrides;
- locally generated data under ignored paths.

Original game data and assets are not repository content.

### `oracle/`

The Python reference implementation:

- favors clarity and instrumentation over presentation concerns;
- keeps rules executable before the GDScript port is complete;
- produces fixtures and traces;
- preserves known legacy arithmetic and random-call ordering.

The oracle is permanent. It is not a temporary migration script.

### `core/`

Pure GDScript model and rules:

- `RefCounted` data and services;
- no Nodes or scene-tree access;
- no presentation assets;
- no autoload dependency;
- deterministic results for a given state, content database and RNG.

`ContentDb` is constructed and passed to consumers. `game/autoload/app.gd` may
hold an active instance for UI convenience, but core rules may not require that
autoload.

### `game/`

Presentation:

- input;
- scenes;
- animation;
- audio;
- UI;
- developer viewers;
- replay of core traces.

Presentation may display or animate a result, but it must not recompute the
mechanic differently.

### `tests/`

Two kinds of proof are required:

- focused rule tests for formulas, ordering and edge cases;
- deterministic scenarios that compare complete event logs, not only final
  state.

A matching final state can hide a different random call, path tie-break or
status-expiry order. Ordered traces expose the first divergence.

## Evidence flow

Reverse-engineering artifacts are evidence, not runtime dependencies.

```text
assembly / call sites / layouts
              │
              ▼
docs/REVERSE_ENGINEERING.md
docs/FUNCTION_MAP.csv
eador_runtime.h
              │
              ▼
compatibility pseudocode and tests
              │
              ▼
oracle/ and core/
```

Recovered executable behaviour is tied to the inspected build. Conflicts with
published documentation or play observation are recorded in
`OPEN_QUESTIONS.md`; they are not silently reconciled.

## IDs and content binding

Ability, upgrade, action and unit identifiers are opaque pack-scoped values.
Vanilla and New Horizons can assign different semantics to the same numeric
opcode.

Core code therefore resolves numeric IDs through pack bindings:

```text
numeric opcode → pack binding → stable handler name → implementation
```

A missing binding or handler must be reported explicitly. It must not fall
through to a plausible default.

## Resolution pipeline

Modifiers are not actions.

- A **modifier** passively participates at a defined resolution hook.
- An **action** is selected, has legality and costs, and can temporarily alter
  which modifiers participate.
- A **runtime status** has source, magnitude, duration/stack state, visibility
  and removal rules.
- An **event** records a resolved transition for trace/replay.

Ordering is part of the mechanic. In particular, the recovered melee path
processes secondary effects before committing the primary life loss.

## Determinism policy

Exact replay requires agreement on:

- underlying PRNG and seed lifecycle;
- bounded-random adapter;
- number and order of random calls;
- integer truncation points;
- fixed iteration order;
- pathfinding tie-breaks;
- status insertion/removal order;
- action and reaction ordering.

Named independent streams are currently a Project EGO design. They are useful
for testing, but they are not established as original-game behaviour.

## Compatibility versus modernization

A modernized rule may coexist with a legacy-compatible rule when both are named
and selectable. It may not replace recovered behaviour while continuing to
claim exact compatibility.

Typical acceptable split:

```text
legacy_genesis: preserve modulo bias and integer quirks
ego_default:    corrected or generalized behaviour
```

The legacy path should have golden tests before a divergence is introduced.

## Documentation ownership

- `FORMULAS.md` — quantitative and ordering rules.
- `OPEN_QUESTIONS.md` — unresolved facts and contradictions.
- `STATUS.md` — implementation and evidence coverage.
- `REVERSE_ENGINEERING.md` — binary-derived checkpoint.
- `FUNCTION_MAP.csv` — address-indexed navigation.
- `LAYOUT.md` — physical repository organization.
- `AGENTS.md` — contribution and evidence discipline.
