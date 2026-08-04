# Cross-review

| topic | binary position | engine position | status | required evidence or resolution |
|---|---|---|---|---|
| Fidelity boundary | Preserve every recovered quirk, but bind it only at the appropriate layer. | Observable behaviour is binding; internal representation is not. | `resolved_after_review` | Adopt per-claim binding scope and engine obligation. |
| Broad mod infrastructure | Defer scripting, plugins, editors, hot reload and speculative hooks. | Same after repository measurement. | `agreed` | None. |
| Stable content identity | Required because localized names are unsafe across packs and persistence. | More urgent than RNG; intra-pack duplicate names prove a live defect. | `resolved_after_review` | Use pack-qualified, source-record-based IDs with provenance. |
| RNG topology | One shared CRT stream is a Genesis compatibility requirement; native streams may differ. | Add the one minimal substitution seam now because retrofitting call order is expensive. | `agreed` | Implement and vector-test `LegacyRng` behind injected randomness. |
| Other policy interfaces | Initially proposed morale, charge, counterattack, dispatch and turn policies. | No demonstrated second implementation; defer them. | `resolved_after_review` | Apply the “second consumer or irreversible cost” rule. |
| `.var` importer | Normalize source-specific records before rules consume them. | Treat `.var` as the primary real mod inlet, not a temporary compatibility corner. | `resolved_after_review` | Require dialect tolerance across Genesis and New Horizons. |
| Scenario identity | Content IDs should not be confused with display names. | Existing scenario names are battle-local handles for inline synthetic units. | `resolved_after_review` | Separate future `instance_id`, optional `content_id`, and `display_name`. |
| Persistence | Versioned stable IDs should be used when persistence is built. | Agreed; no save implementation is scheduled merely for this decision. | `agreed` | Exercise one ID-based save/load probe before formalizing a public format. |

## Remaining human decisions

None. The two positions converged after repository measurements and evidence
review.

## Resolved during review

- The binary side withdrew five speculative policy interfaces.
- The engine side replaced the observable/internal split with binding scope.
- Identity moved ahead of RNG after duplicate-name measurements.
- The importer was reclassified as a first-class `.var` mod inlet.
- Scenario content identity was separated from battle-instance identity.
