# Cross-review

| Topic | Status | Reconciliation |
|---|---|---|
| Generic `prevents_action` authority | agreed | A single boolean cannot be the gameplay authority. Genesis/NH content contains independently composable move/fight/ranged/casting restrictions. |
| Capability-specific authority | agreed | Movement, melee/fighting, ranged, casting and activated-action restrictions are independently representable and checked by their owning command/subsystem with surface-specific refusal semantics. |
| Storage representation | resolved_after_review | Storage is implementation-owned; numeric modifier ids, typed restriction data, or another representation are acceptable if checks remain capability-specific. |
| Fully preventing effects | resolved_by_human | Petrification/web-like effects that prevent all voluntary actions are represented by composing the applicable typed restrictions, not by a second authoritative umbrella boolean. |
| Fate of `Status.prevents_action` | resolved_by_human | Deprecate it as gameplay data. Keep it only temporarily for migration/fixture compatibility if necessary, then remove it once typed restrictions cover supported content. Do not maintain it as a proxy source of truth. |
| Unknown exact restriction ids | evidence_held | Known NH data already demonstrates distinct `NoCast`/`NoRangedAttack` and Genesis/NH move/fight restrictions, but exact legacy mappings for future consumers remain bounded evidence tasks rather than architecture blockers. |

## Result

Reconciliation status: **resolved_after_review**.

No remaining architecture disagreement blocks a canonical decision.
