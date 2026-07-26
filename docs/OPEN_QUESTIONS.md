# Open questions — project_ego

Everything that is *not* settled, with how to settle it. Items move out of this
file only when a test or an observation closes them, never because they seem
obvious.

## Blocking — no implementation possible without these

| # | Question | How to close it | Cost |
|---|---|---|---|
| 1 | **MoraleMod values.** The Eadoropedia states the mechanism but withholds numbers (*«точные цифры не разглашаются»*). | The map panel shows attack *without* morale, the battle panel *with* it. Fix a unit, vary only morale, read the ratio between the two screens. No combat needed. | ~1 hour |
| 2 | **Grid geometry.** Hex or square, dimensions, adjacency. Not in any `.var`. | Screenshot + count. Confirm whether `Гигант` occupies more than one tile. | ~30 min |
| 3 | ~~**Initiative.**~~ **CLOSED.** `ability_num` opcode 999, `unit_upg` /818, and `Initiative` fields in `defender.var` / `guard.var` / `item_set.var`. Army-level: the side whose **leader** has higher initiative moves first; ties go to the attacker. | — | done |
| 3b | ~~**Within-side activation order.**~~ **CLOSED.** Free player/AI selection with partial action-point spending and re-entry: a unit may spend some movement, yield control, and be re-selected later in the same round to finish acting. No HoMM-style initiative queue. | — | done |

## Determinism — wrong answers here invalidate every replay

| # | Question | How to close it |
|---|---|---|
| 4 | **Original PRNG.** Unidentified. `Rng` in `combat.py` is a placeholder LCG. | Identify from the binary (LCG constants are short and distinctive), or accept divergence and drop exact-replay as a goal. |
| 5 | **Level-up draw procedure.** With or without replacement; whether `Only Once` and prerequisite filtering happens before or after the weighted draw (this changes how many RNG values are consumed, so it shifts every subsequent roll). | Sample level-ups from a fixed save. |
| 6 | **Underfull pools.** 7 units have fewer than 2 options at level 1; 241 of 247 spell grants are once-only, so high-level casters exhaust their pools. | Observe what the game offers in that state. |

## Pipeline — assumptions currently baked into `combat.py`

| # | Assumption | Why it is uncertain | Test that settles it |
|---|---|---|---|
| 7 | Conditional bonuses (`Сокрушение зла` and similar) are added **after all three multipliers**. | The page says only that *morale* does not multiply them. It is silent on stamina and wound. | One wounded unit attacking a target the bonus applies to; compare against an unwounded one. |
| 8 | `Неутомимый` suppresses the stamina penalty via the flag, not via the value. | A debuff that sets stamina directly would otherwise penalise a unit that "never loses stamina". | Apply a stamina-draining effect to an undead unit. |
| 9 | Defence floors before clamping to 0, not after. | Ordering matters only when the halving produces a fraction below 1. | Exhausted unit with defence 1. |
| 10 | `Атака с разгона` charge distance is tracked **per round**, and accumulates across re-entries. | Interleaved activation means a unit can move 1, yield, return, move 1 more, then attack. Whether the charge bonus sees 1 tile or 2 is undetermined. | Move a charger in two separate activations, then attack. |
| 11 | "в начале хода" effects (`Прилив сил`, `Боевое безумие`'s rage check) fire **once per round**, not per activation. | With re-entry there is no single per-unit turn boundary. Per-activation firing would let a player farm the effect by yielding and reselecting. | Yield and reselect a unit with `Прилив сил`; check whether stamina rises twice. |
| 12 | The "moved before attacking" stamina distinction (−2 vs −1) uses a **per-round** moved flag. | Same re-entry problem: does moving, yielding, then returning to attack count as having moved? | Compare stamina drain across split vs single activation. |
| 13 | `Удар и возврат` returns to the **round-start** tile, not the activation-start tile. | Only distinguishable when the unit moved in an earlier activation the same round. | Move, yield, reselect, use the ability. |

## Architecture — decided, but revisit if evidence appears

- **`AbilityId` is opaque, resolved through a per-pack binding table.** Forced by the vanilla↔NH opcode reassignments (opcode 30 means different things in each).
- **`ContentDb` is a constructed instance, never an autoload.** Required for the headless harness.
- **Activated abilities need an `Action` type**, separate from `Modifier`. 14 identified so far (`Особое умение, позволяющее…` + a stamina or ammo cost). Not yet drafted — see `TODO` below.
- **Additive before multiplicative**, documented and not negotiable.

## Not started

- `Action` type: cost, targeting, availability, AI evaluation. The largest known gap.
- Status effect container with per-turn expiry (25 abilities carry decaying state).
- Aura resolution (26 abilities are area/adjacency scoped; radius and stacking unverified).
- Battlefield generation from `terrain.var` → `(BF_Pass, BF_Impass)` → `bf_object.var`.
- Scenario format for the headless harness. `Типы охраны` gives 166 ready-made compositions.
