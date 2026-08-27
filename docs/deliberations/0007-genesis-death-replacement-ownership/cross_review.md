# Cross-review

| Topic | Status | Reconciliation |
|---|---|---|
| Genesis mapping | agreed | Genesis rules fix tiers 1..4 -> source records 21/37/56/65. Those are Genesis source identities, not universal canonical ids. |
| Modded content at fixed records | agreed | Genesis-compatible data mods may change the definitions at those source records; they do not change the mapping itself. NH preserving those records is a useful compatibility fixture but does not prove NH 0x5B runtime equivalence. |
| Compatibility declaration / legacy imports | resolved_by_human | Legacy `.var`/supported `.dat` mods inherit the stock Genesis/NH compatibility profile automatically and do not need a new EGO manifest. EGO-native/overlay manifests may explicitly declare or extend compatibility. |
| Rules/content independence | resolved_by_human | Content packs and rules profiles are independent dimensions. Normal compatible pairings are default; unusual pairings produce diagnostics but can be explicitly overridden. A Genesis-compatible content pack under a non-Genesis rules profile is legitimate, with Genesis-only rules inactive unless selected. |
| Custom rules profiles | resolved_by_human | Custom rules profiles are first-class modding features. They may inherit Genesis/NH and deliberately override rules constants, but once a rule such as tier->record mapping changes, that profile is a custom derivative rather than strict Genesis rules compatibility. |
| Resolver owner | agreed | A profile-qualified resolver outside generic `DeathLifecycle` converts the fixed Genesis source record into a canonical replacement definition and feeds the existing injected resolver seam. |
| Strict/permissive loading | resolved_by_human | Strict/default mode validates/fails closed. One explicit load-level permissive mode preserves diagnostics and defers unresolved replacement failure until the affected path is exercised. |
| RS-1 | held | NH content preserving records 21/37/56/65 does not prove NH modifier-0x5B executable semantics. That remains a future bounded binary question. |

## Result

Reconciliation status: **resolved_after_review**.

No remaining architecture/evidence disagreement blocks the content/rules ownership
decision. RS-1 remains separately deferred.
