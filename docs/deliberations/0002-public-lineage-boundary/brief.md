# Brief

## Question

How should Project EGO govern the current mixed reverse-engineering/prototype
lineage and create a prospectively auditable public implementation lineage if
the project reaches community-contribution scale?

## Decision required

Accept, amend or reject:

1. the necessity and transfer classifications in
   `docs/PUBLIC_LINEAGE_AUDIT.md`;
2. the rule that future binary work must pass an observable/material/unresolved
   ambiguity gate;
3. a public-lineage stage gate that freezes the current mixed lineage and creates
   a fresh implementation repository;
4. the `T0` retain, `T1` sanitize, `T2` reimplement, `T3` research-only and `T4`
   deliberate transfer policy;
5. rewrite timing: immediate only for current correctness defects or spreading
   binary-shaped dependencies, otherwise after neutral specification stabilizes;
6. opening a separate deliberation for Genesis/NH/native ruleset profiles.

## Constraints

- Preserve the true history and mixed provenance of the current repository.
- Do not describe the existing lineage as a formal clean-room implementation.
- Do not halt useful private-scale research merely to create retrospective
  appearances.
- Do not transfer raw decompiler output, addresses, original control flow or
  source-derived implementation structure into a future public implementation.
- Permit public documentation and controlled black-box observations as
  implementation-room sources.
- Do not treat public availability as a licence to copy third-party prose, code,
  assets or bulk data.
- Keep original/NH content external and user-supplied unless separately licensed.
- Do not rewrite accepted `DELIB-0001`; qualify its future scope through a new
  decision where necessary.
- Engine implementation changes remain engine-side work.

## Starting evidence

- `docs/PROVENANCE_AND_DATA_POLICY.md`
- `docs/PUBLIC_LINEAGE_AUDIT.md`
- `docs/PUBLIC_LINEAGE_TRANSFER.csv`
- accepted `docs/deliberations/0001-fidelity-and-moddability/decision.md`
- completed binary requests R1–R9 and R11
- current implementations in `core/rules/`, `core/battle/`, `oracle/`
- supplied Eadoropedia snapshot
  `eadoropedia_nh_26.0620.f01(1).zip`,
  SHA-256
  `05b7469fabd539643f9cff8712a40d72dbbefb9e2f6a8a726875e4f1d73906c2`

## Out of scope

- A legal opinion or determination of ownership/infringement.
- A decision to publish or commercialize now.
- The exact ruleset decision for charge, restored-capacity attack cost or legacy
  RNG; those belong to a follow-up profile deliberation.
- Immediate deletion or Git-history rewriting.
- Engine-side implementation edits.
