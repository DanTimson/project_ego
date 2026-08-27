# Engine position — DELIB-0004

## Current repository facts

**The Action model today (`core/model/action.gd`, mirrored by `oracle/actions.py`):**

- `Action` is a flat `RefCounted` with `id` (canonical `StringName`), `source_id`
  (int, content-boundary only — the doc comment on `source_id` and on
  `canonical_id_for_source` is explicit that "Runtime recipes resolve from
  canonical `id` and never dispatch on this"), cost fields
  (`cost_stamina`, `cost_ammo`, `consumes_action`, `attack_surcharge`,
  `free_action_for`), and effect fields (`magnitude`, `is_attack`,
  `damage_scale`, `suppresses`, `scales`, `excluded_targets`, `grants`,
  `suppresses_counterattack`).
- `Action.CATALOGUE` is a `static var Dictionary` populated by
  `Action.load_catalogue(entries: Array)`, which calls `Action.from_dict` per
  entry. There is currently exactly one call site that populates it in
  practice: hand-authored data mirroring `oracle/actions.py`'s fourteen-entry
  Python `CATALOGUE`. Nothing in `core/` currently calls `load_catalogue` from
  a content pack — the fourteen entries exist only as parallel hand-written
  Python/GDScript literals, which the brief already records as "not
  production truth."
- `Scenario._init` (`core/battle/scenario.gd:280`) does
  `catalogue = Action.CATALOGUE.duplicate()` and then merges any
  `spec.get("actions", [])` entries via `Action.from_dict`. This is the
  **existing Scenario-injection precedent**: a scenario file can already
  carry self-contained action entries that override/extend the global
  catalogue. AD-3 needs to generalize this seam so the base layer is a
  resolved pack binding rather than the static hand-authored `CATALOGUE`.
- `ActionRecipeResolver.resolve(action: Action)` (`core/battle/action_recipe_resolver.gd`)
  is a pure `match String(action.id)` switch producing an
  `ActionExecutionPlan`. Only `"crushing_blow"` and `"shield_bash"` are wired;
  every other id returns `Resolution.new(false, null, "known action has no
  frozen recipe")`. This is the accepted CX-013 boundary and this
  deliberation must not touch it — recipes stay keyed by canonical `id`,
  independent of how that `Action` was constructed.
- `Scenario._resolve_action_command` (`scenario.gd:622`) looks the action up
  in `catalogue` by `StringName(action_id)`, i.e. by whatever id the command
  names — currently a canonical id, since nothing feeds it a source id.
- There is **no existing content-pack binding mechanism for activated
  actions**, unlike the parallel machinery that already exists for passive
  modifiers:
  - `ContentPack.load_bindings` reads `bindings.json`'s `"abilities"` map:
    `opcode -> {name, hook, handler, params, uses}` — a per-pack manifest
    binding an **opcode** to an **engine handler name**, because "opcode 30 is
    magic immunity in Genesis and armour-piercing strike in New Horizons."
  - `Roster._resolve_one` (`core/content/roster.gd:254`) resolves
    `unit_upg.Quantity` into a `Modifier`'s `power`, and `db.resolve(opcode)`
    (`ContentDb.resolve`, `content_db.gd:34`) turns an opcode into
    `[handler, params]` via that binding, falling back to an `Unresolved`
    record (not a silent drop, not a hard failure) when unbound/unimplemented.
  - `ContentPack.LoadReport` (`content_pack.gd:28`) already splits load-time
    diagnostics into `unbound` / `missing` / `orphaned` / `errors` and exposes
    `ok()` plus `detail()`. This is the model's existing strict/report-driven
    validation surface for modifiers; it has no equivalent for activated
    actions.
  - `ContentId` (`core/content/content_id.gd`) defines canonical identity as
    `<pack>:<kind>/<source record id>` for `unit`, `upgrade`, `ability`,
    `spell`, `medal`, `item`. There is no `action` kind, and no reason one is
    needed at the `ContentId` grain — see "architectural options" below.
  - `ContentDb.resolve_definition(content_id)` and
    `ScenarioContentProvider.resolve_definition(content_id)` are the two
    existing implementations of the **provider seam** `Scenario.prepare_content`
    already consumes (`provider.has_method("content_provenance")` and
    `resolve_definition`) to turn a canonical unit id into a construction
    dictionary, with strict provenance checking
    (`content_provenance()`/fingerprint matching) already enforced in
    `Scenario.prepare_content`. AD-3 should reuse this exact seam shape for
    actions rather than inventing a second provider protocol.
- `Action.suppresses_counterattack` is read by
  `Counterattack._suppresses_counterattack(action: Variant)`
  (`core/rules/handlers/counterattack.gd:89`), called from
  `Counterattack.why_no_counter(... action: Variant = null)`. Tracing the
  actual call chain: `Scenario._strike` passes `attack_context` into
  `ScenarioNumericOrdering.resolve_exchange`, which is what ultimately reaches
  `why_no_counter`. `Scenario.cmd_attack` (ordinary attacks) passes
  `attack_context = null`. `Scenario._execute_action_attack`
  (the CX-013 action-executed path) passes `operation` — an
  `ActionExecutionPlan.AttackOp` — as `attack_context`, **never the `Action`
  object itself**. `AttackOp`'s only fields are `kind`, `mode`,
  `initiating_attack_scale_numerator/denominator`; it has no
  `suppresses_counterattack` property, so
  `_suppresses_counterattack`'s reflection check
  (`action.get_property_list()` scan) always returns `false` for it.
  **`Action.suppresses_counterattack` is therefore provably unreachable from
  any executed attack today**, confirming the brief's accepted fact from the
  code, not just from history.
- `docs/codex/tasks/CX-013.md` R5 records that GDScript/Python **already had**
  an `AttackOp.suppresses_counterattack` field at the execution-plan operation
  scope, and it was deliberately **removed** ("Remove
  `AttackOp.suppresses_counterattack` from Python and GDScript. Neither
  current recipe needs it; ordinary counterattack suppression remains owned
  by shared melee exchange.") This is not a fresh design question: the
  operation-scope field was tried, found to have no consumer, and stripped.
  Any recommendation here must not silently re-propose the same speculative
  field without a bound recipe that actually needs it.

## Architectural options

**A. Keep `Action.CATALOGUE` as the production source, extend `from_dict`.**
Rejected outright by the brief's decision criteria (#4: "inject the resolved
production action-definition source into Scenario rather than relying on a
global hard-coded catalogue") and by accepted fact #3 ("Python's hand-authored
fourteen-action catalogue is not production truth"). Not evaluated further.

**B. New `ContentId` kind `"action"`, action defined as its own top-level
content table resolved like a unit.**
Rejected. Units are addressed by `.var` record index because that index *is*
the game's own persistent identity for that record. Activated actions are not
`.var` records at all — per `Action.gd`'s own header comment, "COST IS NOT IN
THE DATA... Costs are literals in the prose." The thing a pack actually
supplies for an action is (a) which `unit_upg`/`ability_num` opcode the source
prose ability corresponds to, and (b) prose-derived cost/magnitude literals
that do not live in any table row. Modeling this as a `ContentId` record
lookup would invent a source-record identity that doesn't exist in the .var
data, contradicting decision criterion #1 (pack/source identity separate from
canonical engine identity) by pretending pack identity has more structure than
the data supports.

**C. Extend the existing opcode-binding manifest
(`bindings.json`/`ContentPack.Binding`) with an action-specific binding
table, keyed by opcode, producing a canonical action id plus
cost/magnitude/availability, loaded through a new `ActionCatalog` sibling to
`ContentDb`.** Recommended — detailed below.

The deciding factor between B and C: `Roster` already resolves the exact same
kind of prose-cost problem for **passive** modifiers by keeping `unit_upg`'s
numeric `Quantity` as `power` and letting the *pack's bindings* (not the
`.var` data) supply the `handler`/`hook`/interpretation. Action costs are the
same shape of problem — numeric magnitude in `.var` (`unit_upg.Quantity`),
non-numeric cost/behavior supplied by pack-level authored data — so it should
reuse the binding-manifest pattern rather than a second, table-shaped
mechanism.

## Recommended position

**1. Pack/source binding.** Add an `"actions"` section to the pack's
bindings manifest (same `bindings.json`, alongside the existing
`"abilities"` opcode table), keyed by **source opcode** (the `unit_upg` ->
`ability_num` opcode already resolved by `Roster`/`ContentDb`, exactly the
number `Action.source_id` already exists to record), each entry declaring:

```jsonc
"actions": {
  "59": {                        // opcode, same numeric space as "abilities"
    "canonical_id": "crushing_blow",
    "target": "ENEMY_MELEE",
    "cost_stamina": 0,
    "cost_ammo": 0,
    "attack_surcharge": true,
    "consumes_action": true,
    "free_action_for": [],
    "magnitude_source": "quantity",   // or "literal" + explicit "magnitude"
    "damage_scale": 1.5,
    "is_attack": true,
    "suppresses": [],
    "scales": [],
    "excluded_targets": [],
    "grants": [],
    "notes": "..."
  }
}
```

This is deliberately the same shape `ContentPack.Binding` already has for
passive opcodes (opcode -> handler/params), extended with the
cost/target/effect fields `Action` already carries. It answers decision
criterion #2 directly: source ids stay pack-local keys into this table; they
never become global engine constants, because nothing outside pack loading
ever reads a raw opcode as if it meant something universal — `Action.id`
(the canonical id) is what recipes and command code key off of, exactly as
today.

**2. Canonical action definition.** Introduce `ActionDefinition` (new class,
`core/content/`, sibling to how `ContentDb`/`Roster` sit next to
`ContentPack`) as the resolved, pack-independent record: canonical `id`,
`target`, cost fields, and the shared-default effect fields. This is
*not* a rename of `Action` — `Action` (`core/model/action.gd`) stays the
runtime-facing value object `availability()`/`pay()` operate on; the new type
is what pack loading produces before it becomes an `Action` instance, mirroring
how `Roster.Built.unit` is a `Combatant` assembled from `ContentDb` lookups
rather than `ContentDb` returning `Combatant` objects directly. Concretely:
`ActionCatalog.resolve_definition(canonical_id) -> Dictionary` returning the
same shape `Action.from_dict` already consumes, so the existing
`Action.from_dict` factory is the single assembly point regardless of whether
the dictionary came from a pack binding or (as today, for tests/fixtures) an
inline scenario `"actions"` entry.

**3. Cost.** Cost fields (`cost_stamina`, `cost_ammo`, `consumes_action`,
`attack_surcharge`, `free_action_for`) are **pack-binding-owned defaults**,
per accepted fact: "COST IS NOT IN THE DATA... they must come from our
binding/override layer." They live in the `"actions"` binding entry, not in
any `.var` table.

**4. Per-unit availability/magnitude.** `magnitude` is the one field that
legitimately *can* come from `.var` data (`unit_upg.Quantity`, per-unit, exactly
like passive modifier `power`). Give the binding entry a
`magnitude_source` discriminator: `"quantity"` (read the resolved upgrade
row's `Quantity` the same way `Roster._resolve_one` reads `power` for
modifiers) or `"literal"` (use an explicit binding-declared constant, for
actions whose magnitude truly has no per-unit table value). This keeps
per-unit magnitude at the same ownership layer Roster already uses for
modifier `power`, rather than inventing a second per-unit override
mechanism — decision criterion #3.

For `free_action_for` (documented actor-dependent cost, e.g. Трупоед is free
for Крысолюд) — this is already actor-resolved at *use time* by
`Action.resolved_consumes_action(actor)`, checking `actor.has_subtype(s)`. No
architecture change needed; the binding just supplies the subtype list as
today, unit-agnostic.

**5. Shared defaults with per-unit override.** Decision: **the pack binding
entry is the shared default; a per-unit override lives at the same
`overrides` seam `Scenario.prepare_content` already validates for stat fields**
(`FORBIDDEN_OVERRIDE_FIELDS`/`SETTABLE_UNIT_FIELDS`, `scenario.gd:34-53`).
Concretely: extend `Roster`'s unit-construction output (or `ContentDb`'s
`resolve_definition` for units) to carry a `granted_actions` list of
`{canonical_id, overrides: {cost_stamina?, magnitude?, ...}}` per unit
(sourced from whatever `.var` grants a unit that ability — the same
`Abilityes` resolution chain `Roster` already walks), and apply the
overrides dictionary onto the shared `ActionDefinition` at the point a
`Combatant` is granted the action, using the identical "shared object plus a
small override map, applied field-by-field" shape `Scenario.prepare_content`
already uses for unit stat overrides. This avoids duplicating whole
definitions per unit (explicit human policy requirement) while keeping
override validation centralized and pattern-consistent with the one override
mechanism the codebase already has.

**6. Scenario injection.** Replace `Scenario.catalogue = Action.CATALOGUE.duplicate()`
with: `catalogue` built from the **injected content provider's** resolved
action definitions (new method on the existing provider seam —
`provider.resolve_action_definitions()` or reuse `resolve_definition` with an
`action:`-shaped id string; either is acceptable, but it must go through the
same `injected_content_provider` parameter `Scenario._init` already takes,
not a second injection channel). The existing `spec.get("actions", [])` merge
stays exactly as-is on top — it is already the correct "self-contained
scenario/fixture override" tier and needs no change, only a different base
layer underneath it (resolved provider definitions instead of the static
`Action.CATALOGUE`).

**7. Absent/malformed binding behavior.** Strict-default: at pack load time,
`ContentPack`/a new `ActionCatalog.report()` (same shape as
`ContentPack.LoadReport`) must flag: opcodes with no `"actions"` entry despite
being referenced by `Roster` ability resolution as candidate activated
abilities (best-effort — actions cannot always be distinguished from passive
modifiers purely from `.var` data, so this is a "known gap" list, not a hard
requirement that every opcode be classified); `"actions"` entries with a
missing/malformed `canonical_id`, `target`, or cost field; and canonical id
collisions between two different opcodes claiming the same `canonical_id`
within one pack (violates criterion #5, "fail closed on ... cross-pack
bindings" — extended here to same-pack collisions too, since a collision is
just as dangerous). An explicit permissive/unsafe load mode
(mirroring `LoadReport.ok()` being advisory rather than blocking — packs
already load with a non-`ok()` report today) allows construction to proceed
with unresolved action bindings recorded; per the human policy constraint,
the *specific* unresolved action definition must fail explicitly and loudly
only if a command actually tries to invoke it — i.e.
`Scenario._resolve_action_command` returns a refusal
(`"refusal": "unresolved"`, parallel to the existing `"unsupported"` refusal
for known-but-unrecipeed actions) rather than the load step itself hard
failing, while unrelated actions/units continue to function.

**8. New pack-defined action identities.** Because `canonical_id` is
pack-binding-declared data (a string in `bindings.json`), not a closed engine
enum, a mod's `bindings.json` can bind its own opcode to any new
`canonical_id` string it chooses. `ActionRecipeResolver.resolve` is a pure
canonical-id match; a genuinely new action identity with novel behavior the
engine cannot express generically will resolve its `Action` fields (cost,
target, magnitude, suppress/scale/grant lists — all already-generic,
data-driven effect primitives `Action` already supports) but
`ActionRecipeResolver` will return `supported = false` until a recipe is
authored for it, exactly the existing behavior for the twelve
already-cataloged-but-unrecipeed Genesis actions. This satisfies the human
policy requirement without changing `ActionRecipeResolver`'s architecture:
the identity/composition layer (this deliberation) and the
executable-recipe layer (already CX-013, unchanged) are already properly
separated — a new pack action identity is immediately a legal `Action`, and
separately may or may not have an executable recipe yet.

**9. `Action.suppresses_counterattack` disposition — remove it now.**
The field is (a) proven unreachable today (traced above), (b) the
operation-scope sibling (`AttackOp.suppresses_counterattack`) was already
built and deliberately removed by CX-013 for having no consumer, and (c) the
brief's own human policy constraint says explicitly not to preserve the
`Action`-level field "merely for this hypothetical" multiattack hypothetical.
Recommendation: **delete `Action.suppresses_counterattack`
(`action.gd`/`actions.py`/`from_dict`/`action_from_dict`) entirely.** If a
future accepted recipe genuinely needs "later attacks in one sequence don't
trigger additional retaliation," re-add a boolean at
**`ActionExecutionPlan.AttackOp`** scope (the same field CX-013 already
prototyped once) at that time, wired through the same `attack_context`
parameter `Scenario._strike`/`Counterattack.why_no_counter` already accept —
no new plumbing is needed, only the field and the one recipe that sets it.
Do not pre-build that field now; CX-013 already demonstrated the cost of
carrying it unused.

## Implementation consequences

- New `core/content/action_catalog.gd` (name illustrative): parses the
  `"actions"` bindings section, exposes `resolve_definition(canonical_id)` and
  a `report()`/`LoadReport`-shaped diagnostic object, following
  `ContentDb`/`ContentPack.LoadReport`'s existing split of `unbound` /
  `missing` / collision errors.
- `Roster`/`ContentDb.resolve_definition` (unit path) gains a
  `granted_actions` list per resolved unit, each entry
  `{canonical_id, overrides}`, populated from whichever `Abilityes` entries
  resolve to an action-classified opcode rather than a passive-modifier
  opcode (the binding entry's presence in `"actions"` vs `"abilities"` is the
  discriminator — an opcode should not appear in both).
- `Scenario._init`/`prepare_content` change: `catalogue` sourced from the
  injected provider's action definitions instead of
  `Action.CATALOGUE.duplicate()`. `Scenario.units` construction applies
  per-unit action overrides at the same point stat overrides are already
  applied.
- `Action.suppresses_counterattack` removed from `action.gd`, `actions.py`,
  `from_dict`, `action_from_dict`; `Counterattack._suppresses_counterattack`'s
  reflection-based dictionary/object check can stay as dead-but-harmless
  generality, or be deleted along with the field — deleting is cleaner since
  nothing will ever set the key again once the `Action`/`AttackOp` fields are
  both gone.
- `Action.CATALOGUE`/`Action.load_catalogue`/`Action.canonical_id_for_source`
  (static, global) become dead once the provider seam is live; a follow-up
  bounded task should remove them rather than leaving two parallel action
  sources.

## Verification required if accepted

- A load-time test that a pack `bindings.json` with an `"actions"` entry for
  Crushing Blow's known opcode (59) round-trips to the same `Action` fields
  the current hand-authored entry has, and that Crushing Blow continues to
  execute through the unchanged `ActionRecipeResolver`/CX-013 path end to end.
- A test that a per-unit `granted_actions` override (e.g. a cheaper cost for
  one unit) changes only that unit's resolved `Action.cost_stamina`, not the
  shared canonical definition (no cross-unit mutation).
- A test that an opcode with no `"actions"` binding entry produces a load
  report entry, not a silent gap, and that in strict mode construction fails
  while in permissive mode construction proceeds and only fails when that
  specific action is actually invoked in a command.
- A test that two different packs binding different opcodes to the same
  `canonical_id` string do **not** cross-resolve — i.e., `catalogue` is
  always sourced from the single active pack's provider, never merged across
  packs.
- A test (or explicit code comment) confirming
  `Action.suppresses_counterattack`/`AttackOp.suppresses_counterattack` no
  longer exist anywhere in `core/`/`oracle/`, so a future contributor cannot
  silently resurrect the dead field by copy-pasting an old fixture.

## Risks / rejected shortcuts

- **Rejected:** keying action bindings by canonical `unit_upg` index instead
  of the `ability_num` opcode. The opcode is what already varies meaning
  between packs (per `ContentPack`'s own header comment); binding at the
  `unit_upg` index would conflate "which upgrade row grants this" with "what
  ability this opcode means," breaking the same two-namespace trap
  `Roster.gd`'s header comment already warns about for modifiers.
  Action bindings must use the same opcode space passive-modifier bindings
  already use, for the same reason.
- **Rejected:** silently treating "opcode present in neither `"abilities"`
  nor `"actions"`" as passive-by-default. That would make an unrecognized
  activated ability quietly vanish (no effect, no diagnostic) rather than
  surfacing as an `Unresolved` entry, contradicting `Roster`'s existing
  explicit refusal to silently drop unresolved abilities.
- **Rejected (again):** reintroducing `AttackOp.suppresses_counterattack`
  speculatively "just in case" multiattack is accepted later. CX-013 already
  paid this cost once and reversed it; re-adding it without a consumer
  repeats a decision already made and reverted in this same codebase.
- **Risk carried forward, not resolved here:** distinguishing "action opcode"
  from "passive modifier opcode" purely from `.var` data is not always
  possible without the binding manifest's own classification — this
  deliberation relies on the pack author correctly placing an opcode in
  `"actions"` vs `"abilities"`; there is no independent oracle to verify that
  placement from data alone. Load-time collision detection (an opcode in
  both sections) is the only automatic backstop.

## Remaining human choice

- Exact JSON schema/field names for the `"actions"` bindings section (this
  position proposes a shape consistent with existing `"abilities"` bindings,
  but the literal key names are a project style choice, not an architectural
  one).
- Whether newly-introduced pack-defined action identities that have no
  accepted recipe should be surfaced to players/AI as "known but
  unavailable" (current `"unsupported"` refusal text) or hidden entirely from
  UI/AI candidate lists — a UX/product policy question, not an engine
  ownership question.
- Whether a future multiattack recipe (and therefore a revived
  operation-scope suppression field) is ever actually accepted — this
  deliberation only fixes where such a field would live *if* one is ever
  needed; whether it is needed remains open and explicitly out of scope here.
