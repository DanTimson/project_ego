# Decision record — DELIB-0006

## Status

Accepted by project owner on 2026-08-27.

## Context

Legacy content independently expresses movement, fighting, ranged and casting
restrictions. A single project-authored `Status.prevents_action` boolean cannot
serve as authoritative gameplay state.

## Decision

Adopt **capability-specific restriction authority**:

1. Movement, melee/fighting, ranged attacks, casting and activated actions are
   independently representable restrictions.
2. Each command/subsystem checks the restrictions relevant to its own capability
   and returns its own refusal/result semantics. There is no universal authoritative
   `cannot_act` gate.
3. Fully disabling effects (for example petrification/web-like states) are expressed
   by composing the relevant typed restrictions rather than by a separate umbrella
   source of truth.
4. Storage representation is implementation-owned. Numeric legacy modifier ids,
   typed restriction data, or another backing representation are acceptable if
   authoritative checks remain capability-specific.
5. `Status.prevents_action` / `Statuses.can_act` are not gameplay authority.
   Deprecate the field/query as gameplay data; retain temporarily only where needed
   for migration/fixture compatibility, then remove once typed restrictions cover
   supported content.
6. Exact legacy restriction ids/flags for not-yet-implemented capabilities remain
   bounded evidence tasks and must not be invented from names.

## Consequences

- AD-2 is resolved.
- Existing no-fight/counterattack behavior remains a precedent, not a universal
  implementation template.
- Future movement/ranged/casting work can be added independently.
- Tests must prevent `prevents_action` from accidentally becoming authoritative
  during migration.
