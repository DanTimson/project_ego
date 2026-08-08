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

Unit-command eligibility is model-owned by `ActionPoints.action_spent` and
`ActionPoints.has_resources()`. Partial movement leaves the activation open and
may survive deselection/reselection; after a successful turn-consuming action,
`action_spent` closes only that actor's activation even if capacity remains.
Round start and accepted extra-turn refreshes reopen it. Generic active actions
use `Action.resolved_consumes_action(actor)`, so an explicitly non-consuming
resolved action remains eligible rather than bypassing this boundary in UI code.

`TacticalCoordinateAdapter` is the sole model/screen coordinate boundary. It
maps offset battlefield cells to pointy-top screen polygons and performs the
inverse hit lookup. Input and drawing code do not duplicate projection
arithmetic.

Optional original presentation assets remain outside both core and rules:

```text
user DAT -> explicit local EGOgrabber -> ignored archive exports
         -> tools/prepare_tactical_assets.py -> ignored namespaced index
         -> explicit categorized local visual mapping
         -> TacticalAssetResolver -> keyed texture or authored fallback
         -> TacticalBattlefieldView / tactical right panel
```

Project EGO never parses DAT. The preparation tool treats EGOgrabber manifests
as untrusted, preserves archive namespace, rejects duplicate/traversing/missing
entries, emits only sorted relative runtime paths, and can print a local BMP
inventory/dimension report. The resolver independently contains every path
below the configured index root.

The Slice-3 visual mapping separates `units`, `shadows`, `portraits`, `terrain`,
`decorations`, and `ui`. Unit-like categories may bind canonical content or an
explicit battle instance; named field/UI categories bind only an explicit
presentation slot. Canonical content has priority within an identity category.
Display name and guessed numeric relationships are never identity. Version-1
Slice-2 mappings remain unit-only compatibility input.

Inspected sprite-like exports use exact RGB magenta as a reserved matte. The
resolver clears only that exact value at runtime; original files and ignored
exports are untouched. This treatment is presentation-only and does not pretend
to recover discarded partial alpha.

`TacticalBattlefieldView` encodes the visual order rather than relying on scene
insertion: terrain, variation, decoration, grid, all shadows, all unit sprites,
bars, then target/selection overlays. Side 0's left deployment retains the
inspected natural rightward sprite facing; side 1 uses a negative horizontal
render scale. The transform is reset before overlays. UI is a separate anchored
320-logical-pixel right-side Control layer. Its textual regions use Containers,
wrapping, and bounded scrolling; the outer panel scroll keeps every action
reachable when vertical space is limited. The 840×720 battlefield presentation
is uniformly scaled and centered inside the remaining clipped region. All input
continues through `TacticalCoordinateAdapter` and the battlefield node transform,
so UI/window scale and facing cannot change a model cell or hit test. No local
file is required: authored terrain, directional tokens, portrait initials,
panels, and buttons form the complete fallback.

### `tests/`

Two kinds of proof are required:

- focused rule tests for formulas, ordering and edge cases;
- deterministic scenarios that compare complete event logs, not only final
  state.

A matching final state can hide a different random call, path tie-break or
status-expiry order. Ordered traces expose the first divergence.

## Distributable demo boundary

The exported composition root is `game/demo/demo_main.tscn`; it is a small
presentation shell that transitions to the existing tactical scene. Release
metadata is external to the PCK and is read from `BUILD.json` beside the
executable, with a development fallback when absent.

The release UI baseline is a 1152×648 logical content area with a 960×540
minimum. Godot 4.3 high-DPI support remains enabled. `canvas_items` scaling with
`expand` aspect handling scales Controls, fonts, tactical drawing, and optional
textures together; the project does not apply a second font-only or DPI factor.
These settings define logical layout coverage, not proof of a particular Windows
scale setting. Exported Windows DPI acceptance remains a manual release gate.

`TacticalAssetResolver` treats extracted artwork as optional presentation. An
explicit tool/test root wins; exported builds next probe executable-adjacent
`local_assets/`, while editor development probes ignored
`res://.local/eador_assets/`. Failure at every probe leaves the authored fallback
path intact. These paths never define `ContentId` or model identity.

`tools/build_demo.py` is the single public/private release pipeline. It rejects
tracked changes, exports a `git archive HEAD` staging tree, and uses one cached
executable/PCK payload per commit and Godot version. Public packaging never
consults a local asset root. Private packaging adds only the strict mapped-image
closure after export and regenerates a self-contained runtime index. Both
staging and final artifacts are ignored; detailed prerequisites, hygiene gates
and recipient workflow are in `docs/DEMO_RELEASE.md`.

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
