# Public-lineage boundary and transfer policy

## Status

Proposed — not binding until cross-review and human acceptance.

## Context

Project EGO currently combines public documentation, game/mod data observation,
binary reverse engineering, behavioural specifications and implementation in one
lineage. This is acceptable for the current research/prototype stage but does not
provide a persuasive formal clean-room history if the project later opens to
broad community implementation contributions.

The supplied Eadoropedia corpus also shows that much of the required gameplay
surface is already publicly documented. Exact binary fidelity is necessary for
only a smaller set of material edge, lifecycle and profile questions.

## Decision drivers

- Preserve useful reverse-engineering research.
- Avoid false retrospective clean-room claims.
- Minimize unnecessary rewrites.
- Prevent internal binary structure from becoming a public-engine requirement.
- Prefer public and black-box evidence.
- Preserve exact legacy compatibility where it is deliberately selected.
- Keep future community contribution provenance understandable.

## Considered options

### Option A — Continue the current lineage unchanged

Keep all research, implementation and eventual community contributions in one
repository. Rely on the factual nature of gameplay rules and practical project
tolerance.

### Option B — Sanitize the current repository in place

Remove raw evidence and binary-shaped comments, rewrite selected functions, and
continue the same Git lineage as the public project.

### Option C — Prospective public-lineage boundary

Keep the current repository as the mixed research/prototype lineage. Maintain a
necessity/transfer registry. At the community-release gate, export neutral
specifications/tests into a fresh implementation repository and apply the
`T0`–`T4` transfer policy.

## Decision

Pending cross-review and human acceptance.

The binary-side proposal is Option C, with immediate engine-side correction only
for current behavioural defects and otherwise deferred migration.

## Rejected proposals

None yet.

## Consequences

### Positive

- Preserves an honest research history.
- Retains useful private evidence.
- Avoids rewriting conventional public-rule implementations unnecessarily.
- Creates an auditable future boundary.
- Makes exact legacy quirks explicit profile decisions.
- Reduces binary work to materially necessary ambiguities.

### Negative

- Requires classification maintenance.
- May require a second repository and selective rewrites.
- Creates temporary duplication during migration.
- Does not provide a guarantee against legal claims.
- Depends on disciplined separation rather than labels alone.

## Work allocation

- **Owner:** Human until decision; engine side after implementation allocation.
- **Supporting side:** Binary side maintains necessity evidence and neutral
  specifications; engine side evaluates architecture and rewrite costs.

## Confirmation

- `python3 tools/check_deliberations.py`
- engine-side independent position completed;
- cross-review records agreement and remaining human choices;
- transfer registry reviewed against current implementation;
- immediate stamina contradiction has a tracked engine-side resolution;
- remaining binary queue is reissued under the necessity gate.

## Reconsideration triggers

- A written licence authorizes source/code/data reuse.
- Project scope remains permanently private and non-contributory.
- A contributor or distributor requires a different provenance model.
- Audit shows that fresh-lineage migration cost is disproportionate.
- New evidence shows substantial binary-shaped implementation already
  inseparable from otherwise transferable architecture.
