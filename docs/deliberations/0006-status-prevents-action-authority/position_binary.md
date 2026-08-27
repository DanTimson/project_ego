# Binary/governance position — DELIB-0006

## Evidence boundary

There is no accepted binary authority for `Status.prevents_action` as a generic
gameplay gate. It is a project-authored abstraction, and its name cannot establish
legacy semantics or project policy.

The project owner requires capability-specific restriction behavior. Supplied
Genesis content data is consistent with orthogonal restrictions: movement and
no-fight effects are separate, Sleep composes them, and ranged attack can be
modified independently. This supports the architectural requirement that
movement/melee/ranged/casting restrictions remain independently expressible,
without elevating any particular extracted spell entry into a universal rule.

Recovered R11 behavior remains separate and must not be reinterpreted through
`prevents_action`.

## Recommendation

Do **not** make the current boolean the authoritative umbrella for all commands.

Preferred choices, in order:
1. typed/capability-specific restriction queries are authoritative and
   `prevents_action` becomes a derived/advisory convenience query if useful;
2. otherwise rename/narrow the field to one precisely defined capability;
3. remove it in a later bounded cleanup if it has no useful role.

An implementation may expose a convenience "cannot perform any voluntary action"
aggregate, but it should be derived from explicit restrictions rather than being
the sole source of truth.

## Governance requirements

Any authoritative restriction model must:
- name exact affected command capabilities;
- define precedence relative to death/incapacity, exhaustion, movement,
  action-spent state, target legality and recipe-specific refusal;
- preserve independent restriction combinations;
- avoid assuming unresolved automatic status duration/expiry semantics.

## Evidence request

No broad binary request is required. Specific legacy status effects may later
need bounded evidence for their exact capability masks, but the engine should be
designed to represent them without redesign.
