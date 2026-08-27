# Cross-review

| Topic | Status | Reconciliation |
|---|---|---|
| Source identity vs canonical action identity | resolved_after_review | Source/opcode identities remain pack-local. Runtime recipes use canonical action identities. Novel pack-defined canonical ids are pack-qualified/namespaced by default; explicitly shared engine-known canonical ids remain reusable across compatible packs. |
| Open action namespace | agreed | Packs/mods may define genuinely new action identities. Genesis/NH are content profiles, not a closed engine enum. |
| Executable extensibility | resolved_by_human | Use a two-tier model: declarative action execution plans built from safe engine primitives for data-defined behavior; later, a trusted extension/plugin recipe API for behavior that cannot be expressed declaratively. A new identity may exist even when no executable recipe is available. |
| Legacy mod compatibility | resolved_by_human | Existing Genesis/NH `.var`/supported `.dat` edits must work without requiring an EGO-specific manifest. Legacy imports inherit the selected stock compatibility profile/bindings automatically; an optional overlay manifest is only needed for new/remapped semantics or EGO-native additions. |
| Production composition owner | agreed | Scenario receives an injected, pack/profile-qualified action-definition provider. Static hand-authored catalogues are not production truth. Inline scenario definitions remain fixture/test overrides. |
| Shared defaults and per-unit variation | agreed | Shared definitions own defaults. Unit grants carry availability and explicit parameter overrides without mutating the shared definition. Source `Quantity`/equivalent may supply per-grant magnitude when evidence says it does. |
| Strict vs permissive loading | resolved_by_human | Strict/default validation fails closed. One explicit load-level permissive/incomplete-content mode retains diagnostics and defers unresolved-path failure until that path is exercised. Per-diagnostic waiver machinery is not required initially. |
| `Action.suppresses_counterattack` | agreed | Remove the unreachable action-global field. A future accepted multiattack may attach retaliation policy to the individual attack/exchange operation if needed. |
| UI treatment of unsupported actions | deferred | Whether valid-but-non-executable actions are hidden or shown unavailable is UX policy and does not block composition architecture. |

## Result

Reconciliation status: **resolved_after_review**.

No architecture/evidence disagreement remains. The human policy choices above are
resolved and ready for canonical decision.
