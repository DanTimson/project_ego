# Cross-review

| Topic | Status | Reconciliation |
|---|---|---|
| R8 arithmetic/order | agreed | Keep the recovered formula unchanged: provider contribution before stamina reductions; guarded `<5`, then `<3`; floor 1; strict live-capacity `< effective_speed`. |
| Query-on-demand | agreed | Recompute at use/refresh transitions; do not cache effective speed on `Combatant`. |
| Consumer plumbing | agreed | `ActionPoints` consumes a resolved modifier-7 contribution. Scenario/battle composition resolves it and threads it into round start, extra turn, rollback/reselection and live-capacity consumers using existing injected-parameter/resolver patterns. |
| Personal vs commander/squad channel | resolved_by_human | Build a **generic source-channel model**, not a Speed-7 special case. `.var` evidence distinguishes personal/hero (`Area: 0`, Hero Upgrades) from area/squad/commander (`Area: 1`, Squad Upgrades), including the same modifier id appearing in both channels with different powers. |
| Generic tactical `Auras` as commander substitute | rejected | Commander/squad contribution is not equivalent to the existing tactical `Auras.gd` provider. The recovered commander channel and battle-owned exclusion must remain explicit. |
| Unit/runtime contribution | agreed | Unit-local/persistent and runtime/status modifier-7 terms can be represented immediately through their corresponding personal/runtime channels. |
| Commander/squad contribution | architecture_resolved_evidence_held | Represent it as a separately named commander/squad source channel in battle context and compose it query-on-demand. Exact radius, adjacency, stacking and remaining eligibility semantics are still evidence-held. The known `battle_owned` exclusion must be preserved. |
| Scope of generic channel | resolved_by_human | Introduce the generic personal-vs-commander/squad channel infrastructure now because the distinction recurs across many modifiers; implement only consumers whose semantics are proven. |

## Result

Reconciliation status: **resolved_after_review with bounded evidence hold**.

The ownership/context architecture is decision-ready. Full legacy R8 modifier-7
parity must not be declared complete until commander/squad eligibility and stacking
semantics are resolved. The evidence hold is on compatibility semantics, not on the
channel architecture.
