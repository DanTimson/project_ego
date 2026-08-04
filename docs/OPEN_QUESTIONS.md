# Open questions — Project EGO

Only unresolved facts, contradictions and implementation choices belong here.
A plausible interpretation is not a closure condition. Move an item to the
closed ledger only after assembly/data evidence, a controlled observation, or a
regression test settles it.

Confidence and evidence terminology is defined in `AGENTS.md`.

## Blocking compatibility questions

| ID | Question | Current evidence | How to close |
|---|---|---|---|
| 2 | **Large-unit battlefield footprint.** | The tactical grid and six-neighbour geometry are solved. It is still unclear whether `Гигант` or another category occupies more than one tactical cell in the inspected build. | Inspect placement/collision consumers for unit category and validate in-game. |
| 6 | **Exhausted level-up pools.** | Selection, prerequisite filtering and removal-by-value are recovered. The behaviour when every surviving weight is zero or a unit has fewer than the requested choices remains unclear. | Construct a save/unit that exhausts its pool, or inspect the caller after an all-zero weighted table. |

## Determinism

| ID | Question | Current evidence | How to close |
|---|---|---|---|
| 4c | **Residual RNG persistence and conditional reseed boundaries.** | `srand` has a conditional XREF from the battle-outcome path, but the supplied packet does not contain enough of that local expression to freeze it safely. No evidence yet establishes whether save files serialize live CRT `_holdrand` state. | Reduce the battle-outcome call site and inspect save/load code only when a fixture requires continuation inside one reseed epoch. |
| 6b | **All-zero weighted roller behaviour.** | Normal weighted selection is recovered, including removal by selected value. The normal path assumes a positive total. | Find or construct an all-zero caller state and inspect resulting control flow. |

## Current-model versus binary conflicts

| ID | Question | Conflict | How to close |
|---|---|---|---|
| 7 | **Where conditional attack bonuses enter the multiplier pipeline.** | Published prose only excludes them from morale multiplication. The recovered stat and damage paths have not yet been reduced into a complete provider-by-provider ordering table. | Trace one conditional modifier from provider through `004D2E60` and compare wounded/exhausted cases. |
| 8 | **Full `Неутомимый` semantics.** | Binary paths show modifier `0x12` suppressing several stamina costs. Whether every direct stamina-setting effect and the attack penalty are suppressed through the same check is not yet catalogued. | Build a consumer list for modifier `0x12`; test direct stamina drain and zero-stamina state. |
| 9 | **Defence halving and clamp order in every path.** | Effective defence is clamped and halved at zero stamina, but all integer/truncation orderings have not been converted into vectors. | Add binary-derived tests for negative, 0, 1, odd and even defence. |
| 11 | **Start-of-turn effects: round or activation.** | Current model fires once per round. Binary lifecycle evidence has not yet identified the exact boundary for every such effect. | Trace one `Прилив сил` or rage consumer across yield/re-entry. |
| 12 | **Stamina cost after prior movement/action spending.** | `004D7050` chooses the 1-versus-2 cost from remaining versus effective action capacity, not directly from `steps_this_round`. Equivalence across re-entry and non-movement spending is unproven. | Test move/yield/attack, partial action spending without movement, and restored movement. |
| 13 | **`Удар и возврат` anchor.** | Observation says command-start tile; no binary executor has yet established the stored anchor field and lifecycle. | Recover the action executor or instrument a split-activation case. |
| 16 | **Whole-side phases versus unit-by-unit side alternation.** | `RoundLoop` currently models one side acting until pass, then the other. Initiative documentation says which side moves first but does not settle subsequent alternation. | Record one full original round with deliberate partial activations on both sides or inspect the tactical battle loop. |

## Data dictionaries

| ID | Question | Needed result |
|---|---|---|
| D1 | **Modifier-ID dictionary.** | Numeric ID, providers, consumers, stacking/override rule, data/localized name, confidence. |
| D2 | **Battle-action effect-type dictionary.** | All eight-clause dispatcher cases, field use, resistance rule, immediate/runtime behaviour and damage channel. |
| D3 | **Action-definition flag at `+0x58`.** | Exact distinction between merge/update and always-create runtime effects. |
| D4 | **Game-facing meanings of damage channels 1 and 2.** | Channel 1 is ordinary ranged; modifier `0x1C` selects channel 2. Their localized/mechanical categories remain unnamed. |
| D5 | **Death/runtime effects `0x49`, `0x4A`, `0x5A`, `0x5B`.** | Mechanics are recovered; names and source content need `.var`/localization confirmation. |
| D6 | **Side-wide max-life multiplier source.** | `get_effective_battle_max_life_candidate` reads a per-side percentage; battle-setup source is unknown. |

## Incomplete systems

- **Timed status container in GDScript.** `core/model/status.gd` is currently
  empty, while the binary runtime node is a recovered `0x20` doubly linked
  object with source, duration/stack value, UI visibility and
  remove-on-damage behaviour.
- **Aura resolution.** Personal hero and commander-aura channels are distinct,
  but radius, adjacency and stacking coverage is incomplete.
- **Battlefield generation.** Tile storage/pathfinding exists; generation from
  `terrain.var` and `bf_object.var` is not complete.
- **`.var` schemas.** Lexical primitives are recovered and authoring tools
  exist, but startup-loader record schemas have not been extracted
  systematically.
- **Strategic economy.** Upkeep, recruitment and province-income functions are
  understood in fragments but lack normalized compatibility pseudocode and
  golden vectors.
- **Tactical AI.** Large scoring functions are collected but not consolidated.
  This remains downstream of mechanics parity.

## Closed ledger

| former ID | Result | Evidence |
|---|---|---|
| 4 | Genesis uses the statically linked Microsoft CRT generator. `00404B0B` writes the seed to thread-local `_ptiddata._holdrand`; ordinary random consumers use the paired CRT `_rand`. Principal reseed epochs are startup time modulo 10000, map/setup seed, map generation seed, and `map_seed + strategic_turn`. | `EXP-R4A-001`, `EXP-R4B-001`, `EXP-STRATEGIC-TICK-001`; see `LEGACY_RNG.md`. |
| 4b | Ordinary gameplay randomness on one thread consumes one shared CRT sequence. `00454DC0`, `00454F80`, and `00455050` are non-CRT contextual selector paths, not independently advancing PRNG streams. Named subsystem streams are non-legacy. | `EXP-R4A-001`, `EXP-R4B-001`; direct call topology. |
| 10 | Genesis modifier `0x25` reads the attacker's and target's current coordinates before the current command's movement, then calls the movement helper with the requested destination. The bonus is command-entry separation, not cumulative movement or destination displacement. | `EXP-CI11`, `004DCD90` at `004DCDCB..004DCE18`. |
| 14 | Back-and-forth accumulation is not Genesis compatibility behaviour. A cumulative-path implementation must be explicitly classified as a Project EGO-native alternative rather than a legacy-preservation mode. | Consequence of the closed item 10 call ordering. |
| R2 | `item.var`, `medal.var`, and `spell.var` `Effects` store direct effect/modifier opcodes in the namespace described by `ability_num.Number`; they do not store `unit_upg` record indexes. `unit.var Abilityes` remains the contrasting index-based path. | `EXP-R2-001`, `DATA-VAR-FULL-20260804`; consumers `004A1F90`, `00432950`, and the battle-action dispatcher. |
| 1 | Genesis uses triangularly widening high-morale offensive bands beginning at 16, 18, 21, 25, 30, 36, 43 and 51, with +5 percentage points per band. Attack, counterattack and ranged attack use the same integer branch. Fixed 5-point and fixed 2-point bands are rejected. | `EXP-R1-001`: `004D1890`, `004D1660`, `004D14A0`; independently agrees with `DOC-NH-MORALE`. Implementation fixture remains owned by the engine side. |
| 2, partial | Tactical field is an 8×8 odd-row offset hex grid; each side has 37 unit slots; six-neighbour adjacency is recovered. | `004CE9E0`, formation/deployment consumers, `eador_runtime.h`. |
| 17 | **Rounding direction of the negative morale bonus.** | The morale step applies `pre + bonus_percent * pre / 100` as C integer division. For positive bonuses truncation toward zero and flooring coincide, and the recovered evidence covers only that case. Below morale 6 the bonus is negative and the two differ by one point (base 19 at morale 0 gives 8 truncating, 7 flooring). The implementation assumes C truncation toward zero, inferred from the language rather than read from the branch. | Read the divide/negate sequence in the effective-attack morale branch for a negative bonus, or take one controlled observation of a unit at morale 0 with a base attack not divisible by 10. |
| 3 | Army-level initiative: higher leader value starts; ties go to attacker. | data/documentation and current tests. |
| 3b | Within-side unit selection is free and re-entrant. | observation and AI/UI consumers. |
| 5 | Level-up candidate collection, prerequisite filtering, weighting and selected-value removal order are recovered. | `00432B60`, `00454E80`. |
| C1 | Exact attack randomisation and negative-damage chip curve. | `004CEC40` and published tables. |
| C2 | Primary melee ordering, first strike and retaliation. | `004DCD90`, `004D9800`, `004D61E0`. |
| C3 | Ordinary ranged execution and damage channels. | `004D7050`, `004D61E0`. |
| C4 | Runtime modifier-node layout and head insertion. | `004CEC00`, `eador_runtime.h`. |
| C5 | Unit level cap and 30 selected-upgrade slots. | `00432660`, `00433130`, `eador_runtime.h`. |

Architectural obligations for these items — whether a recovered fact must be reproduced, imported, or merely recorded — are tracked by binding scope. The engine side's standing position is in `POSITION_ENGINE.md`.
