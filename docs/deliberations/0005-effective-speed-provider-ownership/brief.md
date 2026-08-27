# DELIB-0005 — Effective-speed provider and context ownership

## Question

Which battle-context interface owns the complete recovered modifier-7 contribution
to effective speed, and at which lifecycle transitions is effective speed queried
or refreshed?

## Decision required

Choose the engine ownership/lifetime model needed to implement the recovered R8
modifier-7 provider rule across ordinary round start, accepted extra turns,
rollback/reselection and commander/aura eligibility.

## Frozen base

`4e508b7ec42268d55df64199be1da414ea69c825`

## Accepted starting facts

The recovered R8 arithmetic is already authoritative:

- begin from definition/base speed;
- add modifier `7` contributions from the recovered eligible provider classes;
- include eligible commander/aura contribution where applicable;
- provider contribution is applied before stamina reductions;
- apply the guarded `<5`, then `<3` decrements;
- final effective speed floors at `1`;
- live-capacity restoration uses strict `< effective_speed`.

The strict live-capacity comparator is implemented. The complete modifier-7
provider aggregation is not.

The unresolved point is architecture/integration: some providers are not purely
unit-local, and no current authoritative battle-context seam covers every speed
consumer and commander-eligibility transition.

## Decision criteria

The accepted design must:
1. cover every provider class required by the accepted rule, not an easy subset;
2. avoid duplicating provider logic between Python/GDScript or call sites;
3. define who supplies commander/aura eligibility;
4. define query/refresh semantics at round start, accepted extra turn,
   rollback/reselection and any other current speed-capacity transition;
5. prevent stale cached provider state after battlefield/lifecycle changes;
6. preserve the already accepted R8 arithmetic and comparator.

## Non-goals

- Do not reopen the recovered arithmetic.
- Do not infer extra provider classes from current architecture.
- Do not implement modifier 7 in this deliberation.
- Do not decide action composition, status authority or death replacement.
- Do not infer NH-specific provider behavior.

## Questions for the binary/governance side

- Which provider/ordering facts are actually proven?
- Which lifecycle questions are not settled by the evidence?
- What neutral rule must an implementation preserve regardless of architecture?

## Questions for the engine side

- Query-on-demand or cached/snapshotted effective speed?
- Which battle-context/provider interface owns non-unit-local contributions?
- Exactly which current lifecycle transitions invoke/recompute it?
- How should tests isolate unit/status/aura/commander contributions and stale-state
  failures?

## Required output

An accepted decision must be sufficient for a later bounded modifier-7
implementation task without silently choosing provider ownership during coding.
