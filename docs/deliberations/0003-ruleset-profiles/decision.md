# Ruleset profiles

## Status

Accepted by the human decision owner; binding.

## Context

DELIB-0002 separates provenance governance from ruleset policy. Project EGO must
now identify which rules provide Genesis fidelity, which are supported for New
Horizons, and which are deliberate native rules without turning profile choices
into conditionals inside rule functions.

The independent positions and completed cross-review broadly agree on coherent
named profiles, explicit selection, profile-clean rule composition, and the need
to leave unsupported New Horizons cells unresolved. The human decision resolves
the remaining policy choices. Downstream observations can fill unresolved cells
but do not delay this decision.

## Decision drivers

- Exact Genesis compatibility must remain selectable and testable.
- New Horizons behaviour must not be inferred from Genesis or native behaviour.
- Native rules are first-class Project EGO policy, not an unnamed fallback.
- Scenarios, persistence and tests must make their rules identity explicit.
- Portable verification and pack-dependent content verification have different
  dependency requirements.
- Compatibility claims require observable, material and neutral evidence at the
  precision needed by the selected profile.

## Considered options

### Option A — one universal compatibility mode

Use one ruleset and resolve every discovered difference in favour of whichever
behaviour appears most useful.

### Option B — independent feature flags

Expose charge, stamina-cost, RNG and other differences as unrelated switches.

### Option C — named coherent profiles

Define Genesis, New Horizons and native rules profiles, select one at the
composition root, and test only their real differences.

## Decision

Adopt **Option C** with the following binding details.

1. **Profile identities and selection**
   - The rules-profile identities are exactly `genesis`, `new_horizons` and
     `native`.
   - `native` is a first-class Project EGO profile.
   - Profile identity is resolved once at the composition root. Rule functions
     remain profile-clean.
   - Independent compatibility flags are not a permanent model.
   - Committed scenarios and persisted configuration must declare profile
     identity explicitly. The old RNG selector may exist only as a temporary
     migration alias and never as an independent permanent rules axis.
   - An unassigned rule cell for a selected profile fails loudly.

2. **New Horizons support boundary**
   - The `new_horizons` identity is defined, but unresolved rule cells remain
     explicitly unresolved.
   - New Horizons content may run under an explicitly selected `native` rules
     profile. That pairing is not New Horizons rules compatibility.
   - Inherited Genesis or native behaviour must not be presented as verified NH
     behaviour without NH-specific support.

3. **Charge**
   - `genesis` uses the R3 command-entry-coordinate rule.
   - `new_horizons` remains blocked on NH-specific evidence.
   - `native` may use cumulative or travelled distance only as an explicitly
     named native rule, never as Genesis parity or verified NH behaviour.

4. **Attack stamina cost**
   - `genesis` uses the R8 strict comparison of live remaining capacity against
     effective speed.
   - `native` deliberately reuses that live-capacity rule.
   - `new_horizons` remains unassigned pending observation.
   - The NH observation must exercise stamina-driven effective-speed reduction,
     not only capacity restoration. That reduction creates ordinary divergence
     cases between live-capacity and movement-history rules.

5. **Randomness**
   - `genesis` uses one shared legacy CRT state, the original bounded adapter,
     modulo bias, and call-order-sensitive consumption.
   - `native` uses named project-authored streams.
   - `new_horizons` RNG topology remains unresolved.
   - Recovered reseed epochs are Genesis-specific. Only epochs actually
     integrated in Project EGO may be described as integrated.

6. **Project EGO persistence**
   - Persist the selected profile and initial seed.
   - Mid-battle continuation under `genesis` also persists the current CRT state
     and epoch.
   - Call count is recommended diagnostic information.
   - This Project EGO continuation contract does not establish that Genesis
     serialized its live CRT state; that historical persistence question remains
     evidence-open.

7. **Canonical scenario definitions**
   - A scenario may optionally reference a canonical content definition. This
     capability is profile-independent.
   - Content-definition identity and battle-instance identity remain separate.
   - Complete inline portable snapshots remain supported.
   - A canonical reference declares pack/build/version provenance, preferably an
     immutable fingerprint.
   - Missing or incompatible dependencies cause failure rather than silent
     substitution.

8. **Test corpus**
   - Portable tests must run on a fresh clone.
   - Pack-dependent tests occupy a separate, declared `requires-pack` tier.
   - Profile-neutral tests run once.
   - Profile matrices cover actual rule divergences rather than multiplying
     every fixture across every profile.

9. **Compatibility preservation threshold**
   - A behaviour is preserved only when it is observable, material,
     representable as a neutral testable rule or finite vector, and supported
     for the selected profile without stronger profile-specific evidence
     superseding it.

10. **Relationship to DELIB-0001**
    - DELIB-0001's exact-fidelity obligations are scoped to the `genesis`
      profile.
    - Its evidence, stable identity, `.var` importer and profile-clean
      architecture claims remain accepted.
    - DELIB-0001's accepted history is not rewritten.

## Consequences

### Positive

- Compatibility claims name the profile they cover.
- Rule code remains independent from profile selection.
- Native policy can diverge deliberately without weakening Genesis fidelity.
- Unsupported NH assignments are visible rather than silently inherited.
- Scenario dependencies and test portability become explicit.

### Negative

- Profile identity must be migrated into scenarios and persistence.
- Genesis shared RNG remains globally call-order-sensitive.
- Some NH rules cannot yet execute under the NH profile.
- Pack-dependent scenarios require provenance management and separate test
  infrastructure.

## Work allocation

- **Architecture-owned:** composition-root profile resolution, profile-clean
  rule injection, explicit scenario and persistence mechanics, canonical
  reference dependency checks, test-tier mechanics, and loud failure for
  unassigned rule cells.
- **Governance-owned:** pack/build/version provenance, `requires-pack`
  classification, compatibility-claim discipline, and application of the
  preservation threshold under DELIB-0002's necessity gate.
- **Human-owned:** profile identities and permanent policy, semantic assignments,
  deliberate native divergences, and any future decision that fills or changes
  an unresolved profile cell.
- **Evidence work:** NH observations and any historical Genesis persistence
  evidence inform later human assignments; they do not reopen this decision or
  require another review to record it.

## Confirmation

This decision is accepted and binding. It becomes verified after:

- composition-root resolution and explicit scenario/persistence profile identity
  are covered by tests;
- Genesis R3 charge and Genesis/native R8 assignments have profile-specific
  coverage;
- Genesis shared-CRT and native named-stream topology are covered without
  claiming an NH topology;
- Genesis mid-battle continuation preserves current CRT state and epoch;
- portable and `requires-pack` tiers are declared, and canonical dependency
  failures are tested;
- NH charge, NH attack stamina cost including stamina-driven effective-speed
  reduction, and NH RNG topology are recorded as observations or remain
  explicitly unsupported; and
- `python3 tools/check_deliberations.py` passes.

## Reconsideration triggers

- NH-specific evidence supports an assignment for an unresolved NH rule cell.
- A selected profile cannot be composed without profile branching inside rule
  functions.
- Persistence or canonical-reference implementation reveals an architectural
  conflict that cannot be resolved within the accepted identity boundaries.
- Stronger profile-specific evidence supersedes a currently preserved behaviour.
