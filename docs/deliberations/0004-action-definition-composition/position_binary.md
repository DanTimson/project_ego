# Binary/governance position — DELIB-0004

## Evidence boundary

The evidence supports pack-qualified source identity and a limited set of
action-effect semantics; it does **not** support a universal fourteen-action
production catalogue. Source IDs are facts of selected content. Canonical engine
composition interfaces and Scenario injection are project-owned architecture.

The project owner additionally requires that packs/mods can introduce genuinely
new action identities. This is compatible with the evidence boundary: a source
identity need not map only to a closed Genesis-derived canonical list.

No accepted evidence establishes a generic `Action.suppresses_counterattack`
property. The one identified product use case—suppressing extra retaliation on
later attacks in a multiattack sequence—does not itself require action-global
metadata and may be better represented on an individual attack/exchange-plan
operation.

## Governance requirements

1. Keep source identity under the selected pack/content boundary.
2. Do not let display names or raw `.var` indices become universal engine dispatch
   keys.
3. Allow packs to define new canonical/namespaced action identities without
   pretending their executable semantics are known automatically.
4. Separate:
   - shared definition defaults;
   - per-unit grants/availability;
   - explicit per-unit parameter overrides.
5. Preserve provenance of source-derived costs/parameters and do not infer missing
   semantics from names.
6. Validate bindings/definitions strictly at load time by default.
7. Support an explicit permissive/unsafe loading mode in which unresolved optional
   definitions remain diagnosed and fail explicitly only if invoked.
8. Preserve the CX-013 recipe -> plan -> primitive execution boundary.

## Preferred architectural shape

Use an injected, pack-qualified action-definition provider owned by the
content/composition layer:

- the selected pack/profile resolves its source action identities;
- definitions carry canonical/namespaced identities and shared defaults;
- unit grants reference those definitions and may carry explicit overrides;
- Scenario receives the resolved provider explicitly;
- recipe resolution consumes canonical identity plus resolved parameters, not raw
  source indices;
- unknown/new action identity is representable even when no executable recipe is
  currently registered, but attempting to execute unsupported behavior must fail
  clearly rather than silently substitute another recipe.

The exact class/API belongs to the engine side.

## `Action.suppresses_counterattack`

Recommendation: remove the current generic field unless the engine side can show
a concrete, reachable need that is superior to per-attack/per-exchange-plan
retaliation policy. Multiattack sequencing should not by itself force a global
action property.

## Rejected shortcuts

- copying the Python fourteen-entry list into GDScript;
- making "canonical action" mean "engine-known Genesis action only";
- global source-ID constants;
- display-name dispatch;
- silently synthesizing missing definitions;
- treating unsupported recipes as production-ready.

## Evidence request

No new binary request is required to choose this composition architecture. Later
specific recipes may require bounded evidence for their own semantics.
