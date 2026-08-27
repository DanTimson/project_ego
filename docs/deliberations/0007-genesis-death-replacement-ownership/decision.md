# Decision record — DELIB-0007

## Status

Accepted by project owner on 2026-08-27.

## Context

Genesis rules fix tier 1..4 death replacement to source records 21/37/56/65.
Those are Genesis source identities, while data editing is a legitimate legacy
modding method and Project EGO should support deliberate custom rules profiles.

## Decision

Adopt **profile-qualified rules/content resolution with legacy-profile inheritance**:

1. Strict Genesis rules fix `{1:21, 2:37, 3:56, 4:65}`. A Genesis-compatible data
   mod may alter the definitions at those records but does not alter the mapping.
2. Legacy Genesis/NH `.var` and supported `.dat` mods inherit the corresponding
   stock compatibility profile/bindings automatically; no EGO-specific manifest is
   required merely to edit existing content.
3. Content packs and rules profiles are independent dimensions. Normal matching
   combinations are defaults; unusual combinations produce diagnostics and may be
   explicitly overridden.
4. Genesis death replacement is active only when Genesis rules are selected and the
   content is Genesis-compatible under the selected/inherited compatibility
   contract.
5. A dedicated profile/content resolver outside generic `DeathLifecycle` converts
   the fixed Genesis source record into a canonical replacement definition and
   feeds the existing injected resolver seam.
6. Strict/default loading validates required targets and fails closed.
7. One explicit load-level permissive/incomplete-content mode may load despite
   diagnostics; unresolved replacement fails explicitly only if that path is
   exercised, while unrelated runtime behavior remains usable.
8. Custom rules profiles are first-class. They may inherit Genesis/NH behavior and
   deliberately override rules constants, but a profile that changes the
   tier->record mapping is a custom derivative, not strict Genesis rules
   compatibility.
9. Non-Genesis-compatible contexts never inherit this mapping through coincidental
   numeric record ids.
10. NH retention of records 21/37/56/65 is useful content compatibility evidence but
    does not prove NH modifier-0x5B runtime semantics; RS-1 remains deferred.

## Consequences

- AD-4 is implementation-ready without conflating content modification with rules
  modification.
- Legacy data mods remain supported without extra manifests.
- Custom rules extensions have a principled first-class home.
- Generic `DeathLifecycle` becomes pack-agnostic at the raw source-id boundary.
