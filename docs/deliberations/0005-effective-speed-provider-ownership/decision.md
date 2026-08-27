# Decision record — DELIB-0005

## Status

Accepted by project owner on 2026-08-27.

## Context

Recovered R8 behavior requires modifier-7 provider contribution before stamina
reductions. Existing engine code implements only unit-local speed/stamina arithmetic.
Cross-review and Genesis/NH content establish that personal/hero and
commander/squad source channels are distinct and recurring across modifiers; generic
tactical `Auras.gd` is not a faithful commander substitute.

## Decision

Adopt **query-on-demand effective-speed composition with generic source channels**:

1. Preserve the recovered R8 arithmetic and strict live-capacity comparator exactly.
2. Do not cache effective speed on `Combatant`; resolve contributions freshly at
   every existing speed/capacity transition.
3. Introduce generic modifier source-channel metadata/context distinguishing at
   least:
   - personal/unit/persistent sources;
   - runtime/status sources;
   - commander/squad sources.
   This is generic infrastructure, not Speed-7-specific plumbing.
4. Source parsing/composition must preserve the legacy personal-vs-squad distinction
   represented by channels such as `Area: 0/1` and Hero/Squad upgrade sections.
5. `ActionPoints` consumes only a resolved modifier-7 contribution. Scenario/battle
   context composes that contribution and injects it into round start, accepted
   extra turns, rollback/reselection, movement/attack live-capacity consumers and
   other current R8 call sites.
6. Unit/personal/runtime modifier-7 contributions may be implemented from proven
   channels immediately.
7. Commander/squad modifier-7 contribution remains an explicitly separate term; it
   must not be approximated with generic tactical `Auras`.
8. Preserve the recovered exclusion of battle-owned/nonpersistent tactical units
   from commander contribution.
9. Exact commander/squad radius, adjacency, stacking and any additional eligibility
   semantics remain an evidence hold. Full R8 modifier-7 compatibility must not be
   declared complete until that bounded evidence is resolved.
10. Implement only consumers whose semantics are proven; the generic channel may be
    reused by future attack/defence/morale/etc. compatibility work.

## Consequences

- AD-1's architecture is resolved without overclaiming binary semantics.
- Generic personal/commander channel infrastructure can proceed now.
- A bounded commander-context evidence request is still required before full R8
  closure.
- Existing `Auras.gd` remains a distinct tactical-aura subsystem.
