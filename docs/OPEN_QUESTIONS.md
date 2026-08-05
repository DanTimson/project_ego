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
| 11 | **Start-of-turn effects: round or activation.** | Public NH data provides a level-zero Wind Seeker with `Прилив сил +1` ×2 and a level-zero Warlord whose second-turn spell directly restores +2 stamina. The preregistered matrix distinguishes side-phase, repeatable selection and granted-turn triggers without binary access. | Run `docs/observations/OBS-R12-R13-PREFLIGHT.md` and submit `OBS-R13-START-EFFECT.csv`; request binary evidence only for an unreachable remaining boundary. |
| 13 | **`Удар и возврат` anchor.** | Public NH data provides a level-zero Harpy with the ability and a level-zero Warlord for a granted second turn. The decisive split case distinguishes an earlier phase/turn anchor from the current attack-command movement start. | Run `docs/observations/OBS-R12-R13-PREFLIGHT.md` and submit `OBS-R12-HIT-RETURN.csv`; request binary evidence only if the decisive case is not reachable. |

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
| 16 / R7 | Tactical combat uses whole-side phases. `g_current_battle_side` remains fixed across ordinary unit selection and command paths. `004E6530` toggles it only when called with a nonzero first argument from explicit side pass or automatic current-side exhaustion. Pass is side-level; unit-by-unit side alternation is rejected. | `EXP-R7-001`; `004EC4C0` inspection path `004F13C8..004F1453` through `004DA6B0`; ordinary selection `004E0280`; phase calls `004F2070..004F214D`; `004E6530` toggle `004E66EE..004E670F`. |
| R6 | The final minimum-one clamp is reachable for zero attack and counterattack values when modifier `0x26` is absent. Ranged attack differs: a zero sum of definition base, instance modifiers and intrinsic modifiers returns zero at `004D14D4..004D14D9` before later providers and the final clamp. Tactical command availability for ranged-only units remains a separate reachability question. | `EXP-R5-001`; attack `004D1895..004D19ED`, counterattack `004D1667..004D187B`, ranged attack `004D14D0..004D1657`. |
| 9 / R9 | Ordinary and ranged defence aggregate all applicable providers, halve only when current stamina is exactly zero using signed truncation toward zero, then clamp the final value to a minimum of zero. Their final reduction order is identical; their modifier IDs and tactical provider sets differ. | `EXP-R9-001`; `004D0820` tail `004D0958..004D097C`; `004D06B0` tail `004D07F8..004D081C`. |
| 7 / R10 | `Сокрушение зла` modifier `0x3D` is added to the already finalized effective attack or counterattack value. Wound, stamina, morale and the selected ordinary-attack 1.5× branch do not scale it. The combined value then enters attack randomisation and defence/resistance resolution, so it is not flat post-resolution damage. | `EXP-R9-001`; `004D2E6D`, `004D2E88`, `004D2E93..004D2EA5`, `004D2EA9..004D2EE7`, `004D2F68..004D2F6D`; `DOC-EADOROPEDIA-NH-26.0620-F01` morale carve-out. |
| 8 / R11 | Effective modifier `0x12` exempts a unit from every recovered tactical stamina mutation. The implementation uses distributed local checks, not a central setter. Related AI, aggregate, path and selection-interface consumers also treat stamina mechanics as inapplicable. Effective-stat functions do not query `0x12`; live stamina still determines penalties. | `EXP-R11-001`, `EXP-R11B-001`; consumer sites `004D0AC3`, `004D1A12`, `004D1B9A`, `004D26F1`, `004D795D`, `004D79B9`, `004D998E`, `004DD851`, `004DD8AE`, `004DD93B`, `004E305D`, `004E6A1B`, `004EF3DE`, `004F5FAE`; selection-interface supplement `004E1973`. |
| 17 | Negative morale adjustment uses signed division truncating toward zero after the pre-morale stat has already been truncated to an integer. The final result is `max(1, pre + trunc0(percent*pre/100))`; at morale 0, pre 19 returns 8 and pre 7 returns 3. | `EXP-R5-001`; identical reciprocal-multiply, arithmetic-shift and sign-correction sequences in `004D1890`, `004D1660`, and `004D14A0`. |
| 4 | Genesis uses the statically linked Microsoft CRT generator. `00404B0B` writes the seed to thread-local `_ptiddata._holdrand`; ordinary random consumers use the paired CRT `_rand`. Principal reseed epochs are startup time modulo 10000, map/setup seed, map generation seed, and `map_seed + strategic_turn`. | `EXP-R4A-001`, `EXP-R4B-001`, `EXP-STRATEGIC-TICK-001`; see `LEGACY_RNG.md`. |
| 4b | Ordinary gameplay randomness on one thread consumes one shared CRT sequence. `00454DC0`, `00454F80`, and `00455050` are non-CRT contextual selector paths, not independently advancing PRNG streams. Named subsystem streams are non-legacy. | `EXP-R4A-001`, `EXP-R4B-001`; direct call topology. |
| 10 | Genesis modifier `0x25` reads the attacker's and target's current coordinates before the current command's movement, then calls the movement helper with the requested destination. The bonus is command-entry separation, not cumulative movement or destination displacement. | `EXP-CI11`, `004DCD90` at `004DCDCB..004DCE18`. |
| 14 | Back-and-forth accumulation is not Genesis compatibility behaviour. A cumulative-path implementation must be explicitly classified as a Project EGO-native alternative rather than a legacy-preservation mode. | Consequence of the closed item 10 call ordering. |
| R2 | `item.var`, `medal.var`, and `spell.var` `Effects` store direct effect/modifier opcodes in the namespace described by `ability_num.Number`; they do not store `unit_upg` record indexes. `unit.var Abilityes` remains the contrasting index-based path. | `EXP-R2-001`, `DATA-VAR-FULL-20260804`; consumers `004A1F90`, `00432950`, and the battle-action dispatcher. |
| 1 | Genesis uses triangularly widening high-morale offensive bands beginning at 16, 18, 21, 25, 30, 36, 43 and 51, with +5 percentage points per band. Attack, counterattack and ranged attack use the same integer branch. Fixed 5-point and fixed 2-point bands are rejected. | `EXP-R1-001`: `004D1890`, `004D1660`, `004D14A0`; independently agrees with `DOC-NH-MORALE`. Implementation fixture remains owned by the engine side. |
| 2, partial | Tactical field is an 8×8 odd-row offset hex grid; each side has 37 unit slots; six-neighbour adjacency is recovered. | `004CE9E0`, formation/deployment consumers, `eador_runtime.h`. |
| 3 | Army-level initiative: higher leader value starts; ties go to attacker. | data/documentation and current tests. |
| 3b | Within-side unit selection is free and re-entrant. | observation and AI/UI consumers. |
| 18 | **Provider classes are coarser in the engine than in the binary.** | R6 establishes that ranged attack returns zero after summing only the definition base, persistent-instance modifiers and intrinsic modifiers — before runtime-node modifiers, commander aura, wound/stamina, morale and the clamp. This engine does not separate those provider classes, so the early-zero guard is placed after additive bonuses and before the STAT_PASSIVE chain, which is the closest available boundary. The two models diverge only if a runtime-node or aura provider raises a ranged attack from zero. | Determine whether any runtime-node or aura provider can contribute ranged attack to a unit whose definition base and instance modifiers sum to zero. If none can, the approximation is exact and this closes; if some can, the engine needs the provider split. |
| 5 | Level-up candidate collection, prerequisite filtering, weighting and selected-value removal order are recovered. | `00432B60`, `00454E80`. |
| C1 | Exact attack randomisation and negative-damage chip curve. | `004CEC40` and published tables. |
| C2 | Primary melee ordering, first strike and retaliation. | `004DCD90`, `004D9800`, `004D61E0`. |
| C3 | Ordinary ranged execution and damage channels. | `004D7050`, `004D61E0`. |
| C4 | Runtime modifier-node layout and head insertion. | `004CEC00`, `eador_runtime.h`. |
| C5 | Unit level cap and 30 selected-upgrade slots. | `00432660`, `00433130`, `eador_runtime.h`. |

Architectural obligations for these items — whether a recovered fact must be reproduced, imported, or merely recorded — are tracked by binding scope. The engine side's standing position is in `POSITION_ENGINE.md`.
