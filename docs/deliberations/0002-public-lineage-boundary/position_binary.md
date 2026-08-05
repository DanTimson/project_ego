# Position

## Repository evidence examined

- `docs/PROVENANCE_AND_DATA_POLICY.md`
- `docs/FORMULAS.md`
- `docs/BINARY_REQUESTS.md`
- `docs/OPEN_QUESTIONS.md`
- `docs/EVIDENCE_LEDGER.csv`
- `docs/COMPATIBILITY_TEST_MATRIX.md`
- `docs/PUBLIC_LINEAGE_AUDIT.md`
- `docs/PUBLIC_LINEAGE_TRANSFER.csv`
- accepted `DELIB-0001`
- completed R1–R9 and R11 evidence
- selected `core/` and `oracle/` files listed in the transfer registry
- supplied Eadoropedia NH 26.0620.f01 snapshot

## Claims

### Claim 1 — strict retrospective clean-room status cannot be manufactured

The current repository deliberately mixes executable inspection, public sources,
specification work and implementation. A later repository rename, history
rewrite or mechanical rewrite cannot make that history independently created.

**Support:**

The current provenance policy acknowledges mixed binary/implementation work.
Implementation comments already cite executable addresses and recovered branch
order. The same actors and agents have exchanged both evidence and
implementation consequences.

**Binding scope or architectural consequence:**

Preserve the current lineage truthfully as research/prototype work. Create only
a prospective information boundary for a future public lineage.

### Claim 2 — evidence confidence and transferability require separate labels

A binary claim can be proven and still be unnecessary or inappropriate to
transfer. A public rule can be safe to use yet currently be implemented
incorrectly.

**Support:**

R11's complete consumer inventory is strong evidence, but the future engine only
needs the neutral rule that modifier `0x12` suppresses stamina mutations and does
not separately suppress stat penalties. Conversely, the public stamina curve is
sufficient for implementation, while current stamina helpers contradict the
established live-value penalty rule.

**Binding scope or architectural consequence:**

Adopt the two-axis `N*` necessity and `T*` transfer registry. Do not infer one
axis from the other.

### Claim 3 — public documentation and black-box evidence should be primary

The Eadoropedia snapshot publicly documents a large part of the combat and
ability surface. Direct gameplay can settle many remaining timing questions
without exposing implementation structure.

**Support:**

The corpus includes the current-attack formula, stamina effects, broad tireless
semantics, charge, hit-and-return descriptions and numerous ability rules.

**Binding scope or architectural consequence:**

Every future binary request must first record the public-source search and
minimal black-box attempt, unless the behaviour cannot be reached without
prohibitive setup.

### Claim 4 — binary work should be necessity-driven, not completeness-driven

Whole-function reconstruction is unjustified where only a few observable cells
matter.

**Support:**

R16's dispatcher structure is internal. R17's monolithic secondary processor
contains many effects already documented publicly; only trigger and
non-commutative order ambiguities can materially harm gameplay.

**Binding scope or architectural consequence:**

Retire broad dispatcher reconstruction. Reframe secondary-effect work as finite
behaviour matrices. Continue R10/R12/R13 only after the necessity gate.

### Claim 5 — rewriting should be staged

Immediate rewrite is warranted for current functional contradictions or where
binary-shaped structure is spreading. Other `T2` items should remain isolated in
the private prototype until neutral specifications and ruleset profiles are
stable.

**Support:**

`Stamina.modifier`, `Stamina.speed_penalty`, `Stamina.is_exhausted` and the
Python oracle's stamina multiplier currently encode separate tireless penalty
immunity contradicted by R11. By contrast, rewriting exact legacy RNG before
deciding its profile status may create avoidable churn.

**Binding scope or architectural consequence:**

Engine side should correct the stamina defect now. Most other `T2` rewrites are
gate work, not immediate deletion.

### Claim 6 — the future public lineage should be a fresh implementation line

A new implementation repository should receive public sources, neutral
specifications, synthetic fixtures and address-free behavioural vectors, but not
the current prototype's binary-shaped implementation history.

**Support:**

This preserves useful research while giving future contributors a meaningful
information boundary. It is more honest and auditable than trying to sanitize
the current history in place.

**Binding scope or architectural consequence:**

At the community-release gate, freeze/private the mixed lineage as appropriate,
create a fresh public repository, and apply the `T0`–`T4` transfer decisions.

## Proposed decision

1. Accept `PUBLIC_LINEAGE_AUDIT.md` and `PUBLIC_LINEAGE_TRANSFER.csv` as
   provisional governance instruments.
2. Require the necessity gate before new binary requests.
3. Keep the present repository as the mixed research/prototype lineage.
4. Create a fresh public implementation lineage at the defined release gate.
5. Transfer `T0`, sanitize `T1`, independently rewrite `T2`, exclude `T3`, and
   resolve `T4` through deliberation.
6. Correct the current tireless/stat-penalty contradiction immediately on the
   engine side.
7. Pause broad R16 and reframe R17.
8. Open a follow-up ruleset-profile deliberation after this decision.

## Risks

- Over-classification may create unnecessary rewrite work.
- Under-classification may transfer binary-shaped implementation structure.
- A fresh public lineage doubles short-term maintenance.
- Deferring rewrites can accumulate debt if labels are not enforced.
- Public documentation may itself contain errors or build-specific rules.
- A provenance process can become performative unless specifications and tests
  are genuinely neutral.

## Strongest objection to this position

A formal separation may add substantial work without changing the practical
risk of a small, tolerated fan project. Much current code is conventional and
could be retained after comment cleanup; a fresh repository and broad rewrite
may sacrifice momentum for an evidentiary benefit nobody ever demands.

The response is that the proposed gate is deferred until community scale, not an
immediate rewrite mandate. The registry also permits `T0` retention and `T1`
sanitization rather than presuming contamination.

## Questions for the other side

1. Which `T2` classifications are architecturally cheap to rewrite now, and which
   should wait until the public-lineage gate?
2. Can current tests be partitioned into public/spec fixtures and private
   differential fixtures without duplicating the entire suite?
3. Does a fresh repository create unacceptable dependency or migration costs?
4. Which current functions contain genuinely distinctive binary-shaped
   structure rather than ordinary implementation of a factual rule?
5. What enforcement mechanism should prevent new `T3` evidence from leaking
   into transferable code?
6. Should the immediate stamina correction be a direct fix or a rewrite behind a
   new neutral stamina-policy interface?

## Changes after cross-review

After reading the independently prepared engine position, the binary side makes
the following amendments:

1. **Necessity gate:** accept that the gate is prospective and that “unresolved”
   means unresolved at the precision the engine requires. Closed cross-source
   confirmation remains valid evidence and is not retrospectively labelled
   waste.
2. **Transfer cost:** accept the measurement that current binary-address
   references in implementation files are comments rather than copied register
   layout or decompiler-shaped control flow. Most implementation transfer is
   therefore `T1_SANITIZE`; reserve `T2_REIMPLEMENT` for narrow rules whose
   behavioural structure itself depends on binary-only evidence.
3. **Tests first:** accept that public/spec tests, synthetic fixtures and
   address-free golden vectors must be classified and transferred before any
   implementation rewrite begins.
4. **Immediate rewrite trigger:** add maintained-implementation disagreement,
   including oracle/port divergence, to the immediate-fix conditions.
5. **Audit schema:** accept `binary_basis_surface` and
   `public_basis_sufficient` fields, explicit `T3_RESEARCH_ONLY` rows for the
   principal evidence documents, and a separate generated-bindings row.
6. **Stamina issue:** record the engine-side correction as landed. The
   transferable rule explicitly states that modifier `0x12` gates mutations
   only, while penalties derive from live stamina.
7. **Follow-up profile deliberation:** include the unresolved canonical
   scenario-definition question alongside charge, restored-capacity attack cost
   and legacy/native RNG.
8. **Fresh lineage:** no objection was established to the prospective
   freeze-and-fork boundary. The binary side retains Option C as the converged
   recommendation.

No further evidence request is required for DELIB-0002. The remaining action is
human acceptance or rejection of the converged decision.
