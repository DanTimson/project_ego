# DELIB-0006 — `Status.prevents_action` authority

## Question

Is `Status.prevents_action` an advisory/reference query only, or an authoritative
gameplay predicate? If authoritative, which exact command/action surfaces must
consult it and what refusal semantics are exposed?

## Decision required

Choose project policy for the stable status abstraction. This is an engine/human
policy question: no accepted binary evidence currently makes the predicate
authoritative merely because of its name.

## Frozen base

`4e508b7ec42268d55df64199be1da414ea69c825`

## Accepted starting facts

- CX-010 established a stable first-class status container and explicit status
  query/manipulation behavior.
- Automatic duration/expiry lifecycle remains a separate open boundary.
- `Status.prevents_action` exists but is disconnected from gameplay command
  authority.
- The post-0.2 audit classified this as `PROJECT_POLICY_REQUIRED /
  DEAD_ABSTRACTION_CANDIDATE`.
- Naming is not semantic evidence.

## Human policy constraints

The project must represent **capability-specific restrictions**, not only one
global action-block boolean.

Known game functionality includes restrictions that can independently affect
movement, ranged attacks, melee/fighting, casting, and related command classes.
Therefore a single authoritative `prevents_action` umbrella cannot be the only
restriction model.

The supplied Genesis content data independently supports this direction:
movement-blocking and no-fight effects are separate, Sleep composes both, and
ranged attack can be modified independently. Exact spell/status semantics remain
subject to their own evidence, but the architecture must be able to express such
orthogonal restrictions.

The engine side should therefore decide whether the current
`Status.prevents_action` field:
- remains only as an advisory/derived convenience query over typed restrictions;
- is renamed/narrowed to a specific capability;
- or is removed in favor of typed restriction queries.

It should not become the authoritative generic gameplay gate merely for backward
compatibility with its current name.


## Decision criteria

If advisory/reference-only:
1. say explicitly that gameplay command code must not treat it as authoritative;
2. define its supported query purpose, or remove/rename it in a later bounded task
   if it has no useful purpose;
3. ensure tests prevent accidental gameplay wiring.

If authoritative:
1. enumerate exact affected surfaces (movement, melee, ranged, activated actions,
   or another precisely named set);
2. define precedence relative to death, exhaustion, action-spent and target
   legality;
3. define stable refusal/result semantics;
4. require positive and negative tests for every named surface;
5. avoid making automatic status lifecycle assumptions not yet accepted.

## Non-goals

- Do not infer authority from the member name.
- Do not choose R13 duration/expiry semantics.
- Do not modify status effects or commands in this deliberation.
- Do not broaden into generic crowd-control reconstruction.
- Do not decide AD-1, AD-3 or AD-4.

## Questions for the binary/governance side

- Is there any evidence obligation for this predicate? If not, what must remain
  explicitly project-owned?
- What evidence-derived behavior must not be accidentally conflated with it?

## Questions for the engine side

- Does the abstraction earn an authoritative role in the current command model?
- If yes, what exact surfaces and refusal ordering?
- If no, should it remain advisory, be renamed, or be removed in a later cleanup?

## Required output

The decision must make it impossible for a future implementation executor to
"wire it by name" without an explicit accepted surface list.
