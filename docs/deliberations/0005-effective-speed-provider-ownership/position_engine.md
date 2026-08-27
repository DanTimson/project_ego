# Engine position — DELIB-0005

## Current repository facts

**`ActionPoints.effective_speed(u: Combatant) -> Array` (`core/battle/action_points.gd:20`)**
is the sole implementation of R8 speed today. It is **purely unit-local**:
reads only `u.speed` and `u.stamina`, applies the two guarded `<5`/`<3`
decrements, floors at 1. It has no modifier-7 aggregation, no environment
input, and no caching — it is computed fresh on every call from the two raw
Combatant fields.

**Every current call site calls it fresh, on demand; there is no cached
"effective speed" field anywhere on `Combatant`:**

| Call site | File:line | Lifecycle transition |
|---|---|---|
| `RoundLoop.begin_new_round` -> `ActionPoints.begin_round(u)` -> `effective_speed(u)` | `round_loop.gd:72`, `action_points.gd:76` | Ordinary round start |
| `ActionPoints.refresh_for_extra_turn(u, ...)` -> `effective_speed(u)` | `action_points.gd:111` | Accepted extra turn (called from `ActionPoints.grant_extra_turn`, called from `Scenario.cmd_extra_turn`) |
| `DeathLifecycle.resolve` rollback branch -> `ActionPoints.effective_speed(unit)` | `death_lifecycle.gd:220` | Rollback/reselection (transformation reverted) |
| `ActionPoints.spend_move` -> `effective_speed(u)` (zero-speed extra-stamina check) | `action_points.gd:205` | Movement stamina cost |
| `ActionPoints.attack_stamina_cost(u)` -> `effective_speed(u)` | `action_points.gd:233` | Live-capacity discriminator (documented R8 rule) |
| `ActionPoints._spend_attack(u, ...)` -> `effective_speed(u)` | `action_points.gd:240` | Melee/ranged attack stamina cost, same live-capacity discriminator |

`RoundLoop.begin_new_round` (`round_loop.gd:65`) is called from exactly two
places — `RoundLoop.begin_battle` and `RoundLoop.end_phase` — so it is the
**single choke point** for round-start speed refresh; there is no scattered
duplication to hunt down for that transition specifically.

**Commander/aura eligibility has no dedicated interface today.** There is no
`Commander` class and no "commander" concept anywhere in `core/` outside one
doc comment (`combatant.gd:106`, "commander auras, spell buffs" as prose
describing what *kind* of thing feeds `attack_bonus`/`defence_bonus`, not a
class). The only existing mechanism capable of representing a non-unit-local,
battlefield-position-dependent contribution is **`Auras`**
(`core/rules/auras.gd`): `Auras.Aura` objects live in
`Scenario.auras_by_source` (`unit -> Array[Aura]`, built once in
`Scenario._build_auras`), and `Auras.modifiers_for`/`Auras.active_for`
recompute which auras currently *reach* a unit on every call (deliberately —
see the file's own header: "AURAS ARE DERIVED, NEVER APPLIED... `modifiers_for()`
recomputes from the battlefield each time"). A "commander" in this codebase's
existing terms is simply a unit projecting an `Aura` whose `modifiers` include
a `Modifier` with `ability == 7`; there is no separate commander-eligibility
gate to design beyond what `Auras.collect`/`_side_matches`/`Aura.reaches`
already enforce (alive source, side match, adjacency/battlefield scope,
subtype filters).

**The existing environment-aggregation seam:** `Damage`
(`core/rules/damage.gd`) already solves exactly this class of problem for
combat-stat modifiers:

- `Damage._environment: Callable` is a **static** binding, set once by
  `Scenario.run()` via `Damage.bind_environment(Callable(self, "environment"))`
  before battle execution begins, and cleared after. `Scenario.environment(unit)`
  (`scenario.gd:441`) delegates straight to `Auras.modifiers_for`.
- `Damage.effective_modifiers(u)` = `u.modifiers` (unit-owned) +
  `Statuses.active_modifiers(u)` (status-owned) + `_environment.call(u)`
  (aura-owned) — already the complete three-tier aggregation this
  deliberation needs for modifier 7.
- `Damage.effective_modifier_value(u, ability) -> int` (`damage.gd:65`)
  already sums signed power across every tier for one numeric modifier id.
  This is the exact primitive a modifier-7 provider needs; it requires no new
  code to exist, only a caller.
- Because `_environment` is an **unbound (invalid) `Callable` by default**,
  `Damage.effective_modifier_value`/`effective_modifiers` degrade safely
  (unit+status modifiers only, no aura contribution, no crash) when called
  outside an active `Scenario.run()` — e.g. from isolated `ActionPoints` unit
  tests that construct a `Combatant` directly. This matters for the next
  section: it means `Damage` is always safe to call, even when no Scenario is
  running.

**The existing layering convention `ActionPoints` already follows for exactly
this shape of problem: modifier 0x12 (stamina-mutation suppression).**
`ActionPoints` (`core/battle/`) never references `Damage` (`core/rules/`)
anywhere — confirmed by grep, zero hits. Every `ActionPoints` function that
needs to know whether modifier 0x12 is effectively active
(`spend_move`, `_spend_attack`) takes it as an **already-resolved boolean
parameter** (`modifier_0x12_effective: bool`), which its callers (`Scenario`)
compute via `Damage.has_effective_modifier(unit, 0x12)` before calling down.
`core/model/action.gd` follows the identical convention for the same
modifier. This is a deliberate, consistent existing layering boundary, not
incidental: `core/battle` and `core/model` stay ignorant of `core/rules`'
static pipeline/environment bindings; only `Scenario` (the composition root)
touches both and passes resolved values downward.

**`DeathLifecycle.resolve`** (`core/rules/death_lifecycle.gd:190`) already
takes injected `Callable`s for exactly this reason —
`definition_resolver` and `event_sink` are both parameters, bound by
`Scenario.resolve_for_scenario` (`scenario.gd:788`) via `.bind(...)`. Its
rollback branch's `ActionPoints.effective_speed(unit)[0]` call
(`death_lifecycle.gd:220`) currently receives **no** modifier-7 input at all —
this is a real gap, not merely a style inconsistency, since rollback is one
of the four transitions this deliberation must cover.

## Architectural options

**A. Cache/snapshot effective speed on `Combatant`, invalidated on
battlefield/aura change.** Rejected. Nothing in the current codebase caches
any derived combat value — `effective_modifiers`, `effective_modifier_value`,
`environment`, and `effective_speed` itself are all recomputed per call by
design (`Auras.gd`'s header comment states the principle generally: deriving
avoids the bookkeeping of invalidating a cache on every move/death/expiry).
Introducing the first cached derived value specifically for speed would add a
new invalidation-correctness burden (exactly the "prevent stale cached
provider state" risk decision criterion #5 warns about) without a matching
existing pattern to justify the inconsistency, and Godot's `Combatant` is
mutated in place by many call sites (movement, statuses, auras, death
lifecycle) with no single mutation-tracking hook to invalidate a cache
correctly.

**B. Let `ActionPoints` call `Damage.effective_modifier_value` directly.**
Technically safe (per the "degrades gracefully when unbound" fact above) but
**rejected** because it breaks the one layering convention this exact
function already follows one line away (`_modifier_0x12_suppresses`, same
file, same kind of aggregated-modifier need). Doing modifier 7 differently
from modifier 0x12 inside the same file for no architectural reason would be
an inconsistency future maintainers would have to explain away.

**C. Query-on-demand, parameter-injected — extend `effective_speed` to accept
a pre-resolved modifier-7 contribution, computed by callers via
`Damage.effective_modifier_value(u, 7)`, exactly mirroring the existing
`modifier_0x12_effective` convention.** Recommended.

## Recommended position

**Query-on-demand, not cached** — this is not a new choice, it is
*continuing* the existing, universal pattern: every single current
`effective_speed` call site already calls it fresh; there is no precedent
anywhere in this codebase for caching a derived battle value, and Combatant
mutation is too diffuse (movement, statuses, auras, death lifecycle all touch
it from different files) for a cache-invalidation scheme to be added safely
in this pass. Recommend against introducing one now.

**Ownership: `Damage` remains the sole environment-aggregation owner; a
provider-parameter, not a `core/battle` -> `core/rules` dependency.**

1. Change `ActionPoints.effective_speed` signature to
   `effective_speed(u: Combatant, modifier_7_bonus: int = 0) -> Array`,
   adding the resolved contribution as a flat additive term to the R8
   formula (before the `<5`/`<3` decrements — same "provider contribution is
   applied before stamina reductions" ordering already accepted in the
   brief's frozen facts) — mirroring exactly how `modifier_0x12_effective`
   is threaded as a parameter into `spend_move`/`_spend_attack` in the same
   file today. `ActionPoints` still never imports `Damage`.
2. Every caller resolves the bonus via
   `Damage.effective_modifier_value(unit, 7)` before calling down, exactly
   as `Scenario` already does for modifier 0x12 at each of its call sites.
   Concretely:
   - `RoundLoop.begin_new_round`/`begin_round` need a new
     `speed_bonus_resolver: Callable` parameter (unit -> int), threaded from
     `Scenario._run`/`cmd_end_phase` (the only two callers of
     `RoundLoop.begin_battle`/`end_phase`), bound to
     `Callable(Damage, "effective_modifier_value").bind(7)`-shaped glue (or
     an explicit small wrapper function on `Scenario`, matching the existing
     `Callable(self, "environment")`/`Callable(self, "_resolve_fatal_event")`
     style already used throughout `scenario.gd`). Because `begin_new_round`
     is the single choke point identified above, this is one seam change,
     not N call-site changes.
   - `ActionPoints.grant_extra_turn`/`refresh_for_extra_turn` need the same
     resolved-`int` (or resolver `Callable`) parameter, threaded from
     `Scenario.cmd_extra_turn`, its only caller.
   - `DeathLifecycle.resolve`'s rollback branch needs the same treatment as
     its existing `definition_resolver`/`event_sink` parameters: add a
     `speed_resolver: Callable` parameter to `DeathLifecycle.resolve`,
     bound by `Scenario.resolve_for_scenario` the same way the other two
     already are. This closes the currently-real gap where rollback's
     `effective_speed` call gets zero modifier-7 input.
   - `attack_stamina_cost`/`_spend_attack`/`spend_move` already take
     `modifier_0x12_effective` as a parameter from `Scenario`; add
     `modifier_7_bonus` alongside it, resolved at the same call sites the
     same way.
3. **Commander/aura eligibility supplies itself through the existing `Auras`
   mechanism** — no new eligibility interface is needed. A commander
   contributing modifier 7 is simply a unit with a projected `Aura` whose
   `modifiers` array contains a `Modifier.make(7, ...)`, exactly like any
   other aura-sourced stat bonus already flowing through
   `Scenario.environment` -> `Damage._environment` ->
   `Damage.effective_modifiers`. `Auras.Aura.reaches`/`_side_matches`
   already gate adjacency, liveness, side, and subtype eligibility; nothing
   commander-specific needs to be built. If unit-owned (non-aura, "innate")
   modifier-7 providers exist (e.g. a unit's own speed-boosting item/ability,
   not projected from another unit), those already flow through
   `u.modifiers` into the same `Damage.effective_modifier_value` sum with no
   extra work, since `effective_modifiers` already includes `u.modifiers` as
   the first tier.

## Implementation consequences

- `ActionPoints.effective_speed` gains a `modifier_7_bonus: int = 0`
  parameter; the default keeps every existing test/call site that doesn't
  pass it compiling and behaviorally unchanged (contribution 0).
- `RoundLoop.begin_battle`/`begin_new_round`/`end_phase` gain a
  `speed_bonus_resolver: Callable = Callable()` parameter (empty-callable
  default = 0 contribution, matching `Damage`'s own "unbound is safe" default
  behavior), threaded from `Scenario`.
- `DeathLifecycle.resolve`/`resolve_for_scenario` gain a `speed_resolver`
  parameter alongside the existing `definition_resolver`/`event_sink`.
- `ActionPoints.grant_extra_turn`/`refresh_for_extra_turn`/`spend_move`/
  `attack_stamina_cost`/`_spend_attack` gain the same resolved-value
  parameter, all sourced from `Scenario` the same way `modifier_0x12_effective`
  already is.
- No change to `Damage`, `Auras`, or `Combatant` is required — the
  aggregation primitive (`effective_modifier_value`) and the eligibility
  mechanism (`Auras`) already exist and already handle every listed
  lifecycle transition's non-unit-local case.

## Verification required if accepted

- A test that a unit under an aura projecting `Modifier(ability=7, power=N)`
  sees `ActionPoints.effective_speed` increased by `N` at **each** of the
  four named transitions independently: ordinary round start (via
  `RoundLoop.begin_new_round`), an accepted extra turn (via
  `cmd_extra_turn`), rollback (via a scenario that grants ROLLBACK status
  then triggers death/revert), and a live-capacity attack-cost query
  (`attack_stamina_cost`) — isolating unit/status/aura/commander
  contributions per the brief's own required test isolation.
- A staleness test: aura source dies or moves out of range between two
  queries in the same round: the second query must reflect the withdrawn
  contribution (this should pass "for free" given query-on-demand, but must
  be asserted explicitly since it is the exact failure mode a cache would
  have introduced).
- A test that `effective_speed(u)` with no resolver bound (default `0`)
  produces byte-identical results to current pre-modifier-7 behavior, so
  existing scenario fixtures do not need regeneration for units with no
  modifier-7 provider present.
- A test that the rollback branch (`DeathLifecycle.resolve`) picks up an
  active modifier-7 contribution at the moment of reversion, closing the gap
  identified above where it currently receives none.

## Risks / rejected shortcuts

- **Rejected:** having `ActionPoints`/`RoundLoop`/`DeathLifecycle` call
  `Damage` statically and directly. Safe in isolation, but inconsistent with
  the one existing convention this exact code already follows for modifier
  0x12; would leave two different patterns for "aggregate an effective
  numeric modifier" inside the same file.
- **Rejected:** caching effective speed. No existing precedent, real
  invalidation risk given how many files mutate `Combatant`, and the brief's
  own criterion #5 explicitly warns against stale cached provider state —
  the cheapest way to satisfy that criterion is to not introduce a cache.
- **Risk carried forward:** this position assumes modifier ability `7` is the
  correct/only opcode identity for the R8 speed-provider contribution, per
  the brief's frozen accepted arithmetic; if binary evidence later refines
  which opcode(s) qualify, only the resolver's `.bind(7)` argument (or
  equivalent) changes — the ownership/plumbing design here does not depend
  on the exact opcode number.

## Remaining human choice

- Whether "eligible provider classes" (per the brief's frozen R8 rule) is
  exhaustively "any modifier-7-bearing source reaching the unit through
  existing `Auras`/status/unit-modifier tiers," or whether some sources
  (e.g. self-buffs) should be excluded from the R8 contribution even though
  they are otherwise `Damage.effective_modifier_value`-visible. This is an
  evidence question (which opcode-7 sources are documented as eligible),
  not an architecture question, and is explicitly out of scope for this
  engine position per the brief's non-goals.
- Whether the `speed_bonus_resolver`/`speed_resolver` Callables introduced
  here should be a single unified "battle context" object instead of several
  independently-threaded Callables, once a similar need arises for another
  R8-adjacent rule. This position keeps the minimal, pattern-consistent
  per-parameter approach for this deliberation; a broader battle-context
  consolidation is a separate, larger architectural decision this
  deliberation does not force.
