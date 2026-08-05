# Brief

## Question

Which behaviours belong to an exact Genesis compatibility profile, a New
Horizons profile, and a Project EGO native/corrected profile?

## Decision required

Define profile boundaries for:

1. charge;
2. attack stamina cost after restored capacity or split command sequences;
3. exact legacy RNG versus named native streams;
4. whether scenario units may reference canonical content definitions;
5. which observable Genesis quirks deserve preservation;
6. whether DELIB-0001 exact fidelity is universal or scoped to an explicit
   compatibility profile.

## Constraints

- DELIB-0002 is binding: public documentation and controlled black-box evidence
  are primary; binary evidence is necessity-gated.
- Do not assume New Horizons retained or corrected a Genesis quirk without
  profile-specific evidence.
- Keep engine architecture independent from profile rules.
- A profile must be explicit in tests, scenarios and saved configuration.
- Avoid one “mostly compatible” mode whose rules change silently.
- Do not reopen internal Genesis implementation details that have no material
  observable consequence.

## Starting evidence

- accepted DELIB-0001 and DELIB-0002;
- `PUBLIC_LINEAGE_AUDIT.md`;
- `PUBLIC_LINEAGE_TRANSFER.csv`;
- `PUBLIC_TEST_TRANSFER.csv`;
- R3 charge result;
- R4 legacy RNG result and `LEGACY_RNG.md`;
- R8 attack-stamina-cost result;
- public Eadoropedia NH snapshot;
- current `core/` and `oracle/` profile assumptions.

## Out of scope

- Whether to create the future public repository now.
- Rights to redistribute original/NH data.
- Raw binary function reconstruction.
- General balance changes not tied to profile compatibility.
