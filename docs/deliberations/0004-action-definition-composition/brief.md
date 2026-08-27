# DELIB-0004 — Production action-definition composition

## Question

How should a selected content pack bind source ability/action IDs to canonical
action definitions, costs, availability and per-unit magnitudes, and how should
that resolved production definition set enter `Scenario`?

## Decision required

Choose the production composition boundary for activated actions before CX-014+
adds more recipes. The decision must also dispose of the currently dormant
`Action.suppresses_counterattack` field: remove it, or retain it only with an
explicitly defined reachable purpose and owner.

## Frozen base

`4e508b7ec42268d55df64199be1da414ea69c825`

## Accepted starting facts

- CX-013's canonical action -> recipe -> execution-plan -> typed primitive
  boundary is accepted.
- Crushing Blow and Shield Bash execute through that boundary.
- The other twelve entries in the current reference catalogue remain unsupported.
- Python's hand-authored fourteen-action catalogue is not production truth.
- Source IDs are pack/content identities; they are not universal canonical IDs.
- Per-unit availability/magnitude and production Scenario injection are unresolved.
- Display names are not semantic identifiers.
- `Action.suppresses_counterattack` is currently dead/unreachable and has no
  accepted gameplay authority.
- Pack-agnostic engine rules must not depend directly on `.var` indices.

## Human policy constraints

The project owner has resolved these product-policy points:

- Content packs/mods must be able to introduce **genuinely new activated-action
  identities**, not merely bind source IDs to a closed engine-known action list.
  The engine may still require an explicit executable recipe/effect implementation
  for behavior it cannot express generically, but the identity/composition model
  must not make Genesis' current catalogue the universe of possible actions.
- Shared action definitions should provide sensible defaults, while a unit grant
  may override cost/magnitude/other explicitly overridable parameters where
  needed. The engine side should recommend a clean precedence model rather than
  duplicating whole definitions per unit.
- The only presently identified generic-looking counter-suppression use case is
  multiattack sequencing: later attacks in one sequence may not trigger additional
  retaliation even though the later attack itself otherwise behaves normally.
  Prefer expressing that at attack/exchange-plan operation scope if architecturally
  cleaner; do not preserve `Action.suppresses_counterattack` merely for this
  hypothetical.
- Content-definition validation should be strict at load time by default, but an
  explicit permissive/unsafe override must allow loading with unresolved optional
  bindings. In permissive mode, an unresolved definition must fail explicitly if
  and when the affected action path is actually invoked; unrelated runtime paths
  may continue to function.
- Modded Genesis/New Horizons data is legitimate content. Compatibility must not
  require byte-identical stock `.var/.dat` files.


## Decision criteria

The accepted design must:
1. keep pack/source identity separate from canonical engine action identity;
2. let selected content/profile data supply source bindings without making source
   IDs global engine constants;
3. represent action cost and any per-unit magnitude/availability at the correct
   ownership layer;
4. inject the resolved production action-definition source into Scenario rather
   than relying on a global hard-coded catalogue;
5. fail closed on absent, malformed or cross-pack bindings;
6. preserve the accepted CX-013 plan/executor architecture;
7. keep recipe semantics separate from provenance/content extraction policy;
8. state the fate of `Action.suppresses_counterattack`.

## Non-goals

- Do not add new action recipes.
- Do not infer unsupported action semantics from names/descriptions.
- Do not copy the Python fourteen-action catalogue into GDScript.
- Do not decide AD-1, AD-2 or AD-4 here.
- Do not assign NH/Genesis source IDs beyond tracked evidence.
- Do not implement anything in this deliberation.

## Questions for the binary/governance side

- Which parts are evidence-backed identity facts versus project-owned composition?
- What must remain pack-qualified?
- Does existing evidence justify any generic action-level counter-suppression flag?
- What fail-closed boundaries are required to avoid false cross-pack identity?

## Questions for the engine side

- Which production interface should own action definitions and source binding?
- Where should unit-specific magnitude/availability be represented?
- How should Scenario receive and query that interface?
- What is the smallest migration from the current reference catalogue?
- Should the dead suppression field be removed or retained, and why?

## Required output

An accepted decision must be concrete enough to contract a bounded implementation
without inventing policy during execution.
