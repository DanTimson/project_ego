# Public-lineage boundary and transfer policy

## Status

Accepted by the human decision owner on 2026-08-06; binding.

## Context

Project EGO currently combines public documentation, game/mod data observation,
binary reverse engineering, behavioural specifications and implementation in one
lineage. That is acceptable for the present research/prototype stage but does not
provide a persuasive formal clean-room history if the project later opens to
broad community implementation contributions.

The supplied Eadoropedia corpus also shows that much of the required gameplay
surface is already publicly documented. Exact binary fidelity is necessary only
for a smaller set of material edge, lifecycle and ruleset-profile questions.

Independent review found that current binary-address references in implementation
files are comments rather than copied register layouts or decompiler-shaped
functions. Most eventual transfer work is therefore sanitation, not wholesale
rewrite. Narrow binary-only behavioural rules remain rewrite candidates.

## Decision drivers

- Preserve useful reverse-engineering research and its true history.
- Avoid false retrospective clean-room claims.
- Minimize unnecessary rewrites.
- Prevent internal binary structure from becoming a public-engine requirement.
- Prefer public documentation and controlled black-box evidence.
- Preserve exact legacy compatibility only where deliberately selected.
- Transfer the verification corpus before rewriting implementation.
- Keep future community-contribution provenance understandable.

## Considered options

### Option A — Continue the current lineage unchanged

Keep research, implementation and eventual community contributions in one
repository. Rely on the factual nature of gameplay rules and practical project
tolerance.

### Option B — Sanitize the current repository in place

Remove raw evidence and binary-shaped comments, rewrite selected functions, and
continue the same Git lineage as the public project.

### Option C — Prospective public-lineage boundary

Keep the current repository as the mixed research/prototype lineage. Maintain a
necessity/transfer registry. At the community-release gate, transfer neutral
tests and specifications into a fresh implementation repository and apply the
`T0`–`T4` policy.

## Decision

Adopt **Option C**.

1. The current repository remains the truthful mixed research/prototype lineage.
   It is not described as a formal clean-room implementation.
2. `PUBLIC_LINEAGE_AUDIT.md` and `PUBLIC_LINEAGE_TRANSFER.csv` become the
   provisional governance instruments for necessity and transfer planning.
3. The binary necessity gate applies prospectively. A public source settles a
   question only when it supplies the precision required by the engine; closed
   cross-source confirmation is not retroactively invalidated.
4. New binary work must be observable, material, unresolved at required
   precision, genuinely ambiguous, and reducible to a neutral rule or finite
   vector.
5. At the community-release gate:
   - freeze and preserve the mixed lineage;
   - make research-only evidence private where appropriate;
   - classify and transfer public/spec tests, synthetic fixtures and
     address-free golden vectors first;
   - export neutral behavioural specifications;
   - create a fresh public implementation lineage;
   - retain `T0`, sanitize `T1`, independently rewrite `T2`, exclude `T3`, and
     resolve `T4` through deliberation.
6. Immediate rewrite or correction is required when:
   - current behaviour contradicts established requirements;
   - binary-shaped structure is spreading;
   - maintained implementations or oracle and port disagree;
   - delay would materially increase later separation cost.
7. Binary addresses, ABI maps, decompiler reductions, focused extraction packets
   and private evidence exports are `T3_RESEARCH_ONLY`.
8. Populated generated `packs/*/bindings.json` files are not committed by default
   until their redistribution policy is explicitly decided.
9. R16 is retired as whole-dispatcher reconstruction. R17 is reframed as a finite
   observable interaction matrix. R10, R12 and R13 proceed only under the
   necessity gate.
10. A follow-up ruleset-profile deliberation will decide:
    - charge semantics;
    - restored-capacity attack stamina cost;
    - legacy versus native RNG;
    - whether scenario units may name canonical content definitions;
    - which Genesis quirks belong in a compatibility profile;
    - whether DELIB-0001 exact fidelity is universal or profile-scoped.

## Rejected proposals

### Option A

Rejected because it provides no meaningful future information boundary and makes
community-scale provenance harder to explain.

### Option B

Rejected because deleting or rewriting the existing lineage cannot create
retrospective independent development and would destroy useful provenance while
still leaving the mixed history materially true.

## Consequences

### Positive

- Preserves an honest research history.
- Retains useful private evidence.
- Avoids rewriting conventional public-rule implementations unnecessarily.
- Transfers the strongest verification assets before implementation work.
- Creates a prospective, auditable boundary.
- Makes exact legacy quirks explicit profile decisions.
- Reduces binary work to materially necessary ambiguities.

### Negative

- Requires classification maintenance.
- May require a second repository and selective rewrites.
- Creates temporary duplication during migration.
- Does not guarantee immunity from legal claims.
- Depends on disciplined separation rather than labels alone.
- Leaves detailed ruleset-profile choices for another deliberation.

## Work allocation

- **Decision owner:** Human.
- **After acceptance:** engine side owns implementation migration and test
  classification; binary side maintains necessity evidence and neutral
  specifications.
- **Shared:** both sides maintain transfer labels for artifacts they introduce.

## Confirmation

This decision is accepted and binding. It becomes verified after:

- `python3 tools/check_deliberations.py` passes;
- the remaining binary queue is reissued under the necessity gate;
- the public/spec test corpus has a transfer inventory;
- a public-lineage gate checklist exists;
- the follow-up ruleset-profile deliberation is opened;
- all implementation artifacts intended for transfer are classified before the
  gate is exercised.

## Reconsideration triggers

- A written licence authorizes source/code/data reuse.
- Project scope remains permanently private and non-contributory.
- A contributor or distributor requires a different provenance model.
- Audit shows that fresh-lineage migration cost is disproportionate.
- New evidence shows substantial binary-shaped implementation inseparable from
  otherwise transferable architecture.
