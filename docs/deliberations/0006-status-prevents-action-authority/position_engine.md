# Engine position — DELIB-0006

## Current repository facts

**`Status.prevents_action`** (`core/model/status.gd:32`) is a plain `bool`
field, set from data by `Status.from_dict` (`status.gd:49`,
`specification.get("prevents_action", false)`), round-tripped by `copy()` and
`to_dict()`. It carries no capability qualifier — it is a single undifferentiated
flag, exactly the "one global action-block boolean" the brief's human policy
section says cannot be the whole model.

**`Statuses.can_act(unit) -> Array`** (`core/rules/statuses.gd:212`) is the
only reader: `for effect in unit.statuses: if effect.prevents_action: return
[false, name]`. Its own doc comment already flags it as descriptive, not
prescriptive: `## «не может действовать» — existing stable query, not an
action executor.`

**Grep confirms zero gameplay call sites.** `prevents_action`/`can_act`
appear nowhere in `core/battle/*.gd` or `core/rules/*.gd` outside
`status.gd`/`statuses.gd` themselves (and `tests/test_statuses.gd`). Concretely,
`Scenario.query_command`, `Scenario.execute_command`, `Scenario._resolve_action_command`,
`Scenario.cmd_move`, `cmd_attack`, `cmd_shoot`, `cmd_action`, `cmd_rest` —
every command surface — consult none of it. This matches the brief's accepted
fact and the post-0.2 audit classification exactly: the predicate is fully
disconnected from command authority today.

**A typed, capability-specific restriction mechanism already exists for one
capability — "cannot fight"/offense — and is already authoritative,
independently of `Status.prevents_action`:**

- `Damage._offensive_disabled(u)` (`core/rules/damage.gd:74`):
  `Damage.has_effective_modifier(u, 0x26) or u.has_flag(&"Не сражается")`.
- Consulted at two real gameplay decision points: `damage.gd:121` (inside
  attack resolution) and `damage.gd:489`.
- `Counterattack.why_no_counter` (`core/rules/handlers/counterattack.gd:107`)
  independently checks the identical pair —
  `Damage.has_effective_modifier(defender, 0x26) or defender.has_flag(&"Не сражается")`
  — to produce `NoCounter.CANNOT_FIGHT`, a distinct, named refusal reason
  alongside `RANGED`, `DEAD`, `NO_STAT`, `EXHAUSTED`, `RESTING`, `EVADED`,
  `SUPPRESSED`.

This is the load-bearing precedent for this deliberation: **the codebase
already answers "how should a typed, capability-specific restriction be
represented and enforced?"** — not with a `Status.prevents_action`-style
generic boolean consulted by a central gate, but with (a) a numeric effective
modifier id and/or flag, checked by (b) a small number of named predicate
functions living next to the exact subsystem the capability restricts
(`Damage` for offense/attack, `Counterattack` for retaliation), each
producing its own typed refusal enum member rather than a shared boolean.
`Status.prevents_action` was never plugged into this pattern; it is a
parallel, unconnected abstraction that predates it (or was never finished).

**Refusal-enum precedent for command surfaces already exists in two other
places**, both distinct per-surface enums, not a shared one:
`Action.Refusal` (`OK, NO_STAMINA, NO_AMMO, ACTION_SPENT, EXHAUSTED,
NO_LEGAL_TARGET` — `action.gd:35`) for activated actions, and
`ActionPoints.Refusal` (`OK, NO_MOVEMENT, ACTION_SPENT, EXHAUSTED,
NOT_YOUR_PHASE` — `action_points.gd:15`) for movement. `Scenario.query_command`
(`scenario.gd:505`) and `_resolve_action_command` (`scenario.gd:622`) are the
two central command-validation points, but they do not use one shared refusal
model between move/attack/shoot/action — each surface currently expresses
refusal its own way (dedicated enum, or ad hoc reason strings for
attack/shoot/rest inside `query_command`).

**No movement-blocking or ranged-attack-specific-restriction mechanism exists
at all today.** Grep for movement-immobilization finds only
`movement_remaining = 0` assignments from ordinary resource exhaustion
(resting, ranged-attack activation-ending, forced rest) — nothing
representing an externally imposed "this unit cannot move this round"
condition distinct from having simply spent its movement. There is likewise
no ranged-specific restriction predicate parallel to `_offensive_disabled`.
The brief's human policy section (Sleep composing "movement-blocking" and
"no-fight," ranged modifiable independently) describes content the engine has
no representation for yet, beyond the one already-built melee/offense case.

## Architectural options

**A. Promote `Status.prevents_action` to the single authoritative gameplay
gate, consulted centrally in `Scenario.query_command`/`execute_command`.**
Rejected outright by the brief's own human policy constraint: "a single
authoritative `prevents_action` umbrella cannot be the only restriction
model," and the existing `_offensive_disabled`/`Counterattack.CANNOT_FIGHT`
precedent already demonstrates melee/offense restriction is *not* modeled as
one umbrella boolean even where it already is authoritative — building a
second, conflicting authority for the same kind of restriction would be
actively worse than doing nothing.

**B. Remove `Status.prevents_action`/`Statuses.can_act` entirely now.**
Rejected as premature. The field is harmless dead weight today (unreachable,
per the facts above), but removing it forecloses using it as the eventual
umbrella *derived* query once typed restrictions exist — see C. Removal can
be revisited in a later bounded cleanup task if, once typed restrictions
exist, nothing ever needs the umbrella.

**C. Keep `Status.prevents_action` as a narrow, explicitly-named advisory
field; build typed, capability-specific restriction predicates (following the
already-established `_offensive_disabled`/`CANNOT_FIGHT` pattern) as the
actual authoritative mechanism, one per command class; do not wire
`prevents_action` into any command surface.** Recommended.

## Recommended position

**`Status.prevents_action` remains advisory/reference-only. It must not
become the authoritative gameplay gate.** Rename is optional and low-value —
see below — but the decisive point is behavioral, not naming: no command
surface may treat it as sufficient grounds for refusal.

**The authoritative model is typed, capability-specific, and follows the
pattern the codebase already uses for offense/counterattack, extended to the
other named command classes:**

1. **Movement** — new predicate, e.g. `Damage.movement_blocked(u)` (or a
   `Statuses`-owned equivalent, kept next to `_offensive_disabled` for
   consistency of location), backed by a specific numeric modifier id/flag —
   *not* by scanning `unit.statuses` for `prevents_action`. Consulted from
   `ActionPoints.can_move`/`Scenario.movement_plan`/`query_command`'s `"move"`
   branch, producing a distinct `ActionPoints.Refusal` member (e.g.
   `MOVEMENT_BLOCKED`) alongside the existing `NO_MOVEMENT`/`ACTION_SPENT`.
2. **Melee/fighting** — already built (`Damage._offensive_disabled`,
   `Counterattack.CANNOT_FIGHT`). No change needed beyond, optionally,
   exposing `_offensive_disabled` as a non-private `Damage.offense_disabled`
   if command surfaces outside `Damage`/`Counterattack` need to consult it
   directly (currently they don't — attack refusal flows through the damage
   pipeline itself, which is arguably already the right place; a bounded
   follow-up should confirm `Scenario.query_command`'s `"attack"` branch does
   not need its own separate pre-check).
3. **Ranged attacks** — new predicate, parallel in shape to melee's but
   independently gateable per the brief's evidence that ranged can be
   modified independently of melee. Same treatment: numeric modifier id/flag,
   named predicate, consulted where ranged refusal is currently decided
   (`Scenario.query_command`'s ranged branch, `Scenario.cmd_shoot`).
4. **Casting** — out of scope for concrete design here (no casting command
   surface exists yet in `core/battle` — grep finds no `cmd_cast`/spell
   command path), but the same pattern applies whenever it is built: a named
   predicate, not `prevents_action`.
5. **Activated actions** — `Action.availability`/`Scenario._resolve_action_command`
   already has its own typed `Action.Refusal` enum; a "this status blocks
   activated actions" restriction, if evidence ever requires one, is a new
   `Action.Refusal` member fed by a named predicate, following the same
   pattern, not a `prevents_action` check.

Each restriction is therefore independently representable — Sleep composing
"movement-blocked" and "no-fight" is simply a `Status` whose runtime-owned
`Modifier`s carry both restriction-specific numeric ids at once (the same
multi-modifier-per-status shape `Status.modifiers: Array[Modifier]` already
supports today, no new plumbing needed), while a hypothetical ranged-only
restriction sets only the ranged-specific id. `Status.prevents_action` is not
involved in expressing any of this — it would be redundant with, and could
silently conflict with, the typed predicates if it were ever wired in
alongside them.

**`Status.prevents_action`'s remaining advisory purpose:** it may continue to
exist as a coarse, non-authoritative, human/AI/UI-facing summary hint
("does this status broadly read as action-preventing, for tooltip/AI-triage
purposes") — explicitly documented as never consulted by gameplay command
code. `Statuses.can_act`'s existing doc comment already asserts almost
exactly this; the gap is that nothing currently *enforces* the "not an action
executor" claim structurally. Recommend adding an explicit code comment on
`prevents_action` itself (not just on `can_act`) stating it is
non-authoritative, and a regression test (see below) that fails if any
command path starts consulting it, so the claim stays true rather than merely
documented.

**On renaming:** not recommended. `prevents_action` is already an accurate
description of what it advisorially claims ("this status broadly prevents
acting"); the problem was never the name, it was the risk of a future
contributor assuming the name implies authority. A code comment plus a
locked-down test closes that risk without a rename's blast radius (every
existing `.to_dict()`/`from_dict()` fixture, save file, and test that
currently spells the key `prevents_action`).

## Implementation consequences

- No change to `Status`/`Statuses` is strictly required by this decision
  alone — `prevents_action`/`can_act` can be left exactly as they are, with
  an added doc comment. This deliberation's job is to prevent them from
  being wired into gameplay by name, not to modify them.
- New restriction predicates (movement-blocked, ranged-attack-restricted) are
  **not implemented here** (per this deliberation's own non-goals: "do not
  modify status effects or commands"). This position specifies *where* they
  would go and *what shape* they'd take (mirroring
  `_offensive_disabled`/`CANNOT_FIGHT`) so a later bounded task has a
  concrete pattern to follow rather than inventing one under implementation
  pressure.
- `ActionPoints.Refusal` and `Scenario.query_command`'s ad hoc reason-string
  branches are the eventual insertion points for movement/ranged refusals;
  no enum/structure change is needed until that later task actually adds a
  predicate.

## Verification required if accepted

- A regression test asserting that setting `prevents_action = true` on a
  `Status` applied to a unit does **not** change the result of
  `Scenario.query_command`/`execute_command` for `move`, `attack`, `shoot`,
  `action`, or `rest` — i.e., a status with only `prevents_action` set and no
  typed restriction modifiers is gameplay-invisible. This is the concrete
  enforcement of "must not become authoritative merely for backward
  compatibility with its name."
- Positive/negative tests for `_offensive_disabled`/`CANNOT_FIGHT` already
  exist per `tests/test_counterattack.gd`/`tests/test_damage.gd` — confirm
  they remain the template a future movement/ranged predicate task must
  match (same positive-status / negative-status-absent pairing, per surface).
- No new test is required for casting, since no casting command surface
  exists yet; a future casting task inherits this deliberation's pattern
  requirement rather than needing a placeholder test now.

## Risks / rejected shortcuts

- **Rejected:** "wire `prevents_action` in now as a stopgap, refine to typed
  restrictions later." This is exactly the shortcut the brief warns against
  ("should not become the authoritative generic gameplay gate merely for
  backward compatibility with its current name") — a stopgap gate would
  immediately need Sleep-style composed semantics (movement-blocked AND
  no-fight as two separately toggleable things) that one boolean cannot
  express, guaranteeing a breaking rework rather than a refinement.
- **Rejected:** building one generic `RestrictionKind` enum + a single
  `Status.restricts: Array[RestrictionKind]` field as a halfway house between
  "one boolean" and "fully typed predicates." This would still be a single
  undifferentiated mechanism gameplay code would be tempted to consult
  centrally and generically — the existing, working precedent
  (`_offensive_disabled`, `CANNOT_FIGHT`) is deliberately *not* built this
  way: it is a plain numeric modifier id plus a named predicate living next
  to its own subsystem, and introducing a competing generic enum would
  fragment rather than unify the pattern.
- **Risk carried forward:** until the movement/ranged predicates are actually
  built (a later bounded task, explicitly out of scope here), any content
  data claiming "blocks movement" or "restricts ranged only" has no
  enforcement mechanism at all — this deliberation only guarantees
  `prevents_action` won't be mistakenly used to fake that enforcement, not
  that the real enforcement exists yet.

## Remaining human choice

- Exact modifier id(s)/flag(s) that should back movement-blocked and
  ranged-restricted predicates — an evidence question for the binary/content
  side, out of scope here per the brief's non-goals ("do not choose R13
  duration/expiry semantics," "do not broaden into generic crowd-control
  reconstruction").
- Whether `Status.prevents_action` should eventually be removed once typed
  restrictions cover every case current content needs, versus kept
  indefinitely as a UI/AI advisory summary — a product decision this
  position deliberately defers rather than forces, per option B's rejection
  rationale above.
- Whether casting, when it gets a command surface, needs its own `Refusal`
  enum or can share `Action.Refusal` — depends on how casting is eventually
  modeled (as an `Action` subtype or a wholly separate command), which is
  unrelated to this deliberation's scope.
