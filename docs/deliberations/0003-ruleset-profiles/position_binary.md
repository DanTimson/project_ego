# Position

## Repository evidence examined

- DELIB-0001 and accepted DELIB-0002
- `docs/PUBLIC_LINEAGE_AUDIT.md`
- `docs/PUBLIC_LINEAGE_TRANSFER.csv`
- `docs/PUBLIC_TEST_TRANSFER.csv`
- R3, R4 and R8 evidence
- `docs/LEGACY_RNG.md`
- supplied Eadoropedia NH snapshot

## Claims

### Claim 1 — exact fidelity must be profile-scoped

Genesis compatibility can preserve materially observable legacy behaviour without
making every historical quirk the engine default. New Horizons and native rules
must not silently inherit Genesis behaviour that their own evidence contradicts.

**Consequence:** define explicit `genesis_legacy`, `new_horizons`, and
`native_corrected` rule profiles, or equivalent names.

### Claim 2 — charge requires separate Genesis and NH/native decisions

R3 proves that Genesis computes charge from command-entry attacker/target
coordinates before approach movement. It is not cumulative path length.

The supplied Eadoropedia material publicly describes the legacy coordinate quirk,
but the claim that New Horizons uses travelled hexes still needs NH-specific
black-box or source-authorized evidence.

**Consequence:**

- Genesis legacy: recovered command-entry-coordinate rule.
- New Horizons: unresolved pending NH observation.
- Native/corrected: path-distance or travelled-hex rule may be chosen explicitly,
  not described as Genesis parity.

### Claim 3 — restored-capacity attack cost is a narrow profile edge

Ordinary play makes “moved versus stationary” and the recovered live-capacity
comparison agree. They diverge after capacity restoration or unusual split
sequencing.

**Consequence:** run a minimal Genesis/NH black-box fixture before deciding
whether the recovered edge belongs only to Genesis legacy or is common to both.

### Claim 4 — exact legacy RNG is an optional compatibility contract

The standard CRT recurrence is public. Exact shared topology, modulo bias,
bound-one consumption and reseed epochs are useful for Genesis parity and
differential replay, not for ordinary engine quality.

**Consequence:** retain native named streams as a project-authored mode. Expose
exact legacy RNG only through an explicit Genesis parity profile and rebuild it
from address-free contracts/golden vectors in a future public lineage.

### Claim 5 — canonical scenario definitions are an identity/profile question

A scenario may either embed a complete unit snapshot or reference a canonical
content definition plus overrides. The latter improves content compatibility but
couples scenarios to pack identity/version.

**Consequence:** decide whether canonical references are permitted per profile
and require explicit pack/version provenance when they are.

### Claim 6 — quirks require a preservation threshold

A Genesis quirk belongs in the compatibility profile only when it is observable,
material, specified well enough to test, and not superseded by the selected
profile's public or black-box evidence.

**Consequence:** implementation accidents and negligible unreachable edges remain
research-only; corrected/native behaviour need not emulate them.

## Proposed decision

1. Create explicit Genesis legacy, New Horizons and native/corrected profiles.
2. Scope DELIB-0001 exact fidelity to the selected compatibility profile rather
   than the universal engine architecture.
3. Bind the recovered Genesis charge rule only to Genesis legacy.
4. Require NH black-box evidence before assigning charge semantics to NH.
5. Decide restored-capacity attack cost after a two-build black-box fixture.
6. Keep exact legacy RNG opt-in and profile-specific.
7. Permit canonical scenario definitions only with explicit pack/version
   provenance; embedded snapshots remain portable.
8. Preserve a quirk only when it passes the observable/material/testable/profile
   threshold.

## Risks

- Too many profiles can multiply the test matrix.
- A native profile can become an excuse to leave compatibility gaps.
- Exact legacy RNG may be expensive to maintain end to end.
- Canonical scenario references can become fragile across pack versions.
- NH public documentation may describe intent rather than shipped execution.

## Strongest objection to this position

Three profiles may over-formalize differences before enough of the game exists
to exercise them. A single engine mode with selective compatibility flags could
be simpler.

The response is that flags still constitute profiles; naming coherent profiles
prevents silent mixtures and gives fixtures a stable target.

## Questions for the other side

1. What is the smallest profile API that avoids conditionals spread throughout
   engine code?
2. Should native/corrected be a first-class shipped profile or merely developer
   options until gameplay is complete?
3. Can charge and attack-cost differences live in action policy objects?
4. How should scenario pack/version references survive content upgrades?
5. Which RNG settings must be serialized in scenarios and saves?

## Changes after cross-review

- Genesis R8 is already evidence-closed and implemented.
- NH observation, not another Genesis extraction, is required for NH assignment.
- Recovered reseed epochs are Genesis-specific and only partly integrated.
- Canonical-reference capability is profile-independent but requires declared
  provenance.
