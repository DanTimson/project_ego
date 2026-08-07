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

The playable tactical entry point is `game/tactical/tactical_main.tscn`. Its
controller constructs one `Scenario`, retains that exact model, and drives it
through `ManualBattleSession`. `Scenario.execute_command()` returns the
small structured result (`accepted`, normalized command, refusal reason, new
events, and whether state changed) from the same core path that decides and
applies move, melee, ranged, rest, and pass. `Scenario.query_command()` shares
movement plans, automatic melee approach, and ranged eligibility with that
execution gate. Presentation highlights are advisory UX; a fresh execution
result is authority. The controller never parses battle-log prose for success.

The session remains a neutral `core/` facade: it begins a round without
consuming scripted commands, exposes model queries, and owns no second tactical
state or formula. Because the legacy `Damage` bindings are process-global, each
manual command/damage query scopes its own pipeline and `Scenario.environment`
and clears them before returning. Alternating manual sessions therefore do not
retain one another's environment. Scripted `Scenario.run()` remains the
deterministic fixture/replay path.

`TacticalCoordinateAdapter` is the sole model/screen coordinate boundary. It
maps offset battlefield cells to pointy-top screen polygons and performs the
inverse hit lookup. Input and drawing code do not duplicate projection
arithmetic.

Optional original presentation assets remain outside both core and rules:

```text
user DAT -> explicit local EGOgrabber -> ignored archive exports
         -> tools/prepare_tactical_assets.py -> ignored namespaced index
         -> explicit content/instance presentation mapping
         -> TacticalAssetResolver -> texture or project-authored placeholder
```

Project EGO never parses DAT. The preparation tool treats EGOgrabber manifests
as untrusted, preserves archive namespace, rejects duplicate/traversing/missing
entries, and emits only sorted relative runtime paths. The resolver independently
contains every path below the configured index root. Canonical content mapping
has priority over battle-instance mapping; display name and guessed numeric
relationships are never identity. No local file is required and generated
tokens remain the fallback.

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

## Scenario profiles and content dependencies

Rules-profile identity and content-pack identity are orthogonal. A scenario
selects exactly one `profile` (`native` or a supported compatibility profile),
while an optional scenario-level `content` declaration selects and verifies a
pack snapshot. A canonical scenario uses:

```json
{"content":{"pack":"genesis","version":"...","fingerprint":"sha256:..."}}
```

`pack` is required, as is at least one of `version`, `build` or `fingerprint`;
every supplied discriminator is checked. Selecting `genesis` rules does not
select Genesis content, and `native` rules may consume any compatible injected
pack.

Inline scenario units remain complete portable snapshots and do not consult
content. A canonical unit instead has the closed envelope:

```json
{"id":"attacker-1","def":"genesis:unit/5","at":[0,0],
 "overrides":{"stamina":4}}
```

`def` is content-definition identity, `id` is battle-instance identity, `at` is
battle placement, and `name` in the resolved definition is presentation. The
composition-root `Scenario` receives a small content provider. It verifies the
scenario's declared pack plus every supplied version, build and/or `sha256:`
fingerprint, resolves definitions before constructing combatants, deep-copies
the definition, applies explicit overrides, and finally applies scenario-owned
identity and placement. `ContentDb` implements this seam through the existing
pack and roster loader; rule code never loads a pack or branches on pack ID.

A fingerprint identifies the exact local metadata/content snapshot used. Each
provider computes it from canonical JSON with SHA-256 when provenance is
requested; a fingerprint declared by pack metadata or supplied to a synthetic
provider is only an assertion, is rejected if stale, and is never returned in
place of the observed digest. The snapshot excludes paths, timestamps,
enumeration order and machine state. It does not establish legal transferability
or semantic compatibility. Portable synthetic scenario fixtures run on a fresh
clone. Actual locally extracted pack checks are isolated in the `requires-pack`
tier and skip clearly when `packs/<id>/data` is absent.

Serialized identity has one owner per field: canonical `def` supplies
`Combatant.content_id`, while scenario `id` supplies
`Combatant.instance_id`. Inline units cannot serialize either runtime field;
they remain pack-free, receive an empty `content_id`, and take instance identity
from `id` (or the established display-name fallback when `id` is absent).

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
