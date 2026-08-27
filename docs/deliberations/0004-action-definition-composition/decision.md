# Decision record — DELIB-0004

## Status

Accepted by project owner on 2026-08-27.

## Context

CX-013 established canonical action -> recipe -> execution-plan -> typed primitive
execution, but production composition remained unresolved. The project must support
Genesis, New Horizons and legacy/new mods without treating the current hand-authored
fourteen-action catalogue as production truth.

## Decision

Adopt an **open, profile-aware, injected action composition system**:

1. Source action/opcode identities are local to the selected content pack/profile.
   They never become universal engine constants.
2. Explicitly shared engine-known canonical actions may use a shared canonical id.
   Genuinely novel pack-defined identities are pack-qualified/namespaced by default.
3. Shared action definitions own default costs/targets/effect parameters. Per-unit
   grants own availability and explicit overrides, including source-derived
   magnitude where applicable, without mutating the shared definition.
4. Scenario receives resolved action definitions through the existing injected
   content-provider/composition boundary. Static reference catalogues are not a
   production source. Inline scenario definitions remain test/fixture overrides.
5. Legacy Genesis/NH `.var` and supported `.dat` mods inherit the selected stock
   compatibility bindings/profile automatically. They do not require an EGO
   manifest merely to modify existing content. Optional overlay/EGO-native manifests
   are used for new identities, remaps and extensions.
6. Composition validity is separate from executable behavior. A pack may define a
   valid action identity even when no executable implementation exists.
7. Executable extensibility uses two tiers:
   - declarative execution plans composed from safe engine primitives for
     data-defined behavior;
   - a future trusted extension/plugin recipe API for novel behavior outside the
     declarative primitive set.
8. Strict/default loading validates definitions and fails closed. One explicit
   load-level permissive/incomplete-content mode retains diagnostics and allows
   unrelated runtime paths; invoking an unresolved action fails explicitly.
9. Remove `Action.suppresses_counterattack`. If a future accepted multiattack needs
   suppression on a later strike, attach it to that individual attack/exchange-plan
   operation when a real consumer exists.
10. Exact schema key names, class names and namespace separators are implementation
    details.

## Consequences

- AD-3 is architecture-ready for bounded implementation.
- The system is extensible beyond Genesis/NH without silently granting semantics to
  unknown actions.
- Legacy data-only mods remain low-friction.
- CL-1 is resolved by removal of the dead action-global suppression field.
- A later plugin-security/sandbox decision may be needed before exposing arbitrary
  trusted extension code to third-party packs.
