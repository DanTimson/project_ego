# Fidelity and modifiability

## Question

Should Project EGO encode recovered Genesis details directly into its universal
engine model, and how much modification infrastructure should be designed
before mechanics parity is complete?

## Decision required

Choose which seams are justified now, where executable fidelity is binding, and
which mod-facing systems should be deferred.

## Constraints

- Exact Genesis-compatible behaviour remains a project goal.
- Genesis and New Horizons `.var` content must continue to use one normalized
  rules pipeline.
- Binary evidence must remain maximally precise without becoming accidental
  engine architecture.
- New abstractions need a demonstrated consumer, irreversible migration cost or
  proven compatibility conflict.
- The existing Eador modding community is `.var`-native.

## Starting evidence

- `docs/POSITION_ENGINE.md`
- `docs/FIDELITY_AND_MODDABILITY_BINARY_VIEW.md`
- `docs/EVIDENCE_LEDGER.csv`
- `docs/LEGACY_RNG.md`
- Genesis and New Horizons importer/build tests
- R1–R5 binary findings

## Out of scope

- Public scripting API
- Plugin loading
- Hot reload
- Mod-management UI
- Graphical editors
- A replacement non-`.var` mod format
