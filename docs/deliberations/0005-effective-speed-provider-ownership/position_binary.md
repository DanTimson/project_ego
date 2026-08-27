# Binary/governance position — DELIB-0005

## Proven rule

The accepted R8 evidence fixes the arithmetic and provider ordering:

1. start from definition/base speed;
2. include recovered eligible modifier-7 providers, including the eligible
   commander/aura contribution;
3. sum those contributions before stamina-based decrements;
4. apply guarded `<5`, then `<3` decrements;
5. floor final effective speed at 1;
6. use strict live-capacity `< effective_speed`.

The existing implementation covers the live-capacity comparator but not the full
modifier-7 provider input.

## What the evidence does not decide

The evidence does not prescribe a Project EGO class hierarchy, cache location, or
API. It also does not justify assuming every provider is unit-local. Therefore an
implementation that merely sums currently convenient `Combatant` modifiers would
be incomplete.

The architecture must explicitly carry the battle context needed for
commander/aura eligibility.

## Governance requirements

- one authoritative provider aggregation seam;
- all accepted provider classes represented before claiming closure;
- no caller-specific reimplementation;
- explicit positive/negative commander/aura eligibility controls;
- no stale provider snapshot surviving a lifecycle transition unless the engine
  decision deliberately defines a snapshot boundary;
- Python/GDScript parity vectors separate provider contribution from stamina
  reduction.

## Preferred integration direction

The evidence side prefers calculating effective speed through a battle-context
query at each capacity-refresh transition rather than permanently caching the
provider sum on the unit. This minimizes stale cross-unit/aura state and keeps
non-unit-local providers explicit.

The engine side should decide the exact refresh/query sites, but they must cover at
least ordinary round start, accepted extra-turn refresh and rollback/reselection
paths that restore live capacity.

## Stop condition

If repository inspection reveals a lifecycle transition whose speed snapshot
semantics cannot be reconciled with the accepted rule, hold that transition rather
than inventing a new binary rule.

## Evidence request

No broad binary request is justified. Only a bounded request would be warranted
if a specific provider's eligibility or refresh timing remains materially
ambiguous after the engine maps current lifecycle call sites.
