# Reverse-engineering checkpoint — Eador: Genesis

**Status:** documentation checkpoint after `closer_inspection_1.txt` through `closer_inspection_11.txt`
**Canonical runtime schema:** root `eador_runtime.h`, schema version 14
**Function index:** `docs/FUNCTION_MAP.csv`
**Scope:** compatibility-relevant runtime layouts, unit progression, tactical combat, battle actions, economy fragments, parser primitives, and open reverse-engineering work.

---

## 1. Why this checkpoint exists

The accumulated evidence has crossed the point where continuing to collect decompilations without consolidating them creates more risk than value.

The current corpus already supports implementation-grade descriptions of:

- persistent unit modifier composition;
- ordinary-unit experience and level-up flow;
- weighted random selection;
- effective tactical stat calculation;
- melee, counterattack, and ranged damage calculation;
- attack execution order;
- runtime tactical-effect nodes;
- damage application, morale reaction, death, revival, transformation, and side transfer;
- hex adjacency and battle formation coordinates;
- several province-economy and recruitment formulas;
- the low-level `.var` lexer.

At the same time, several names remain provisional, some calling conventions are nonstandard, and several large dispatchers remain only partly interpreted. This document separates proven facts from strong inference and open questions so later agents do not silently promote guesses into architecture.

---

## 2. Evidence and naming rules

Use these labels consistently:

- **Proven:** explicit in assembly, structure offsets, call sites, or concrete data flow.
- **Strong inference:** multiple independent observations agree, but no direct symbolic or data-file confirmation exists.
- **Candidate:** useful working name; do not treat as a game-facing canonical term.
- **Unknown:** preserve as an unnamed field or numeric modifier/effect ID.

Addresses are the source of truth. Ghidra names may differ between exports because functions were renamed during the investigation.

Do not replace legacy integer arithmetic with algebraically simplified floating-point code until compatibility tests prove equivalence. The original frequently truncates at intermediate integer divisions.

---

## 3. Canonical artifacts

Repository-bound artifacts should be organized approximately as:

```text
eador_runtime.h
docs/REVERSE_ENGINEERING.md
docs/FUNCTION_MAP.csv
docs/OPEN_QUESTIONS.md
```

Current generated artifacts:

```text
eador_runtime.h
docs/REVERSE_ENGINEERING.md
docs/FUNCTION_MAP.csv
```

The schema-14 header passed 32-bit syntax and established-size assertions before it was committed.

Current SHA-256:

```text
9db837ab8e690cd636c8dd0c6072d4240029a22ac4a81cdd258a4f1718f1aafb
```

---

## 4. Established runtime layouts

### 4.1 Persistent unit instance

```c
typedef struct EadorUnitInstancePartial {
    eador_s32 unit_definition_id;       /* +0x00 */
    eador_s32 current_life;             /* +0x04 */
    eador_s32 morale_delta_times_two;   /* +0x08 */
    eador_s32 experience;               /* +0x0C */
    eador_s32 level;                    /* +0x10 */

    eador_s32 formation_grid_x;         /* +0x14 */
    eador_s32 formation_grid_y;         /* +0x18 */

    eador_s32 level_upgrade_ids[30];    /* +0x1C..+0x93 */
    eador_s32 medal_ids[3];             /* +0x94..+0x9F */

    EadorHeroStatePartial *hero_state;  /* +0xA0 */
} EadorUnitInstancePartial;             /* size 0xA4 */
```

**Proven:**

- Ordinary-unit level is capped at 30.
- One selected upgrade ID is stored per level.
- `formation_grid_x/y` are persistent battle-deployment coordinates.
- Opposing-side deployment mirrors X as `7 - formation_grid_x`.

### 4.2 Runtime tactical modifier node

```c
typedef struct EadorRuntimeModifierNodePartial {
    eador_s32 modifier_id;                  /* +0x00 */
    eador_s32 magnitude;                    /* +0x04 */
    eador_s32 duration_or_stack_value;      /* +0x08 */

    eador_u8 visible_in_status_ui;           /* +0x0C */
    eador_u8 remove_on_damage;               /* +0x0D */
    eador_u8 unknown_0e[2];

    struct EadorRuntimeModifierNodePartial *next;     /* +0x10 */
    struct EadorRuntimeModifierNodePartial *previous; /* +0x14 */

    EadorBattleActionDefPartial *source_action;       /* +0x18 */
    EadorUnitUpgradeDef *source_upgrade;              /* +0x1C */
} EadorRuntimeModifierNodePartial;                    /* size 0x20 */
```

Nodes are allocated separately, initialized, and inserted at the list head. The list is doubly linked.

### 4.3 Tactical battle unit

The complete record size is `0x80`. Particularly strong fields:

```c
current_life                              /* +0x00 */
movement_or_action_points_candidate       /* +0x04 */
current_morale                            /* +0x08 */
morale_break_accumulator_candidate        /* +0x0C */
current_stamina                           /* +0x10 */
current_ammunition                        /* +0x14 */

melee_damage_dealt_accumulator_candidate  /* +0x18 */
ranged_damage_dealt_accumulator_candidate /* +0x1C */

damage_received_by_channel[4]             /* +0x20..+0x2F */

ranged_kills_candidate                    /* +0x38 */
melee_or_counterattack_kills_candidate    /* +0x3C */
stamina_spent_candidate                   /* +0x40 */

grid_x                                    /* +0x44 */
grid_y                                    /* +0x48 */

side_index_candidate                      /* +0x50 */
strategic_unit_slot_index_candidate       /* +0x54 */

present_on_field_candidate                /* +0x60 */
battle_owned_unit_instance_candidate      /* +0x62 */

battle_visual_object_candidate            /* +0x64 */
status_ui_control_candidate               /* +0x68 */
status_ui_bitmap_candidate                /* +0x6C */

unit_instance                             /* +0x70 */
original_or_backup_unit_instance_candidate/* +0x74 */
commander_or_army_context_candidate       /* +0x78 */
runtime_modifier_list                     /* +0x7C */
```

### 4.4 Damage channels

```c
enum EadorBattleDamageChannelCandidate {
    EADOR_DAMAGE_CHANNEL_MELEE_OR_COUNTERATTACK = 0,
    EADOR_DAMAGE_CHANNEL_RANGED                 = 1,
    EADOR_DAMAGE_CHANNEL_RANGED_MODIFIER_1C     = 2,
    EADOR_DAMAGE_CHANNEL_SPECIAL_NO_MORALE      = 3
};
```

Channel 3 bypasses the normal large-hit morale reaction.

### 4.5 Battle action definition

Established tail:

```c
eador_s32 effect_magnitude_hero_scale_percent_candidate; /* +0x30 */
eador_s32 effect_aux_hero_scale_percent_candidate;       /* +0x34 */
eador_s32 resistance_scale_percent_candidate;            /* +0x38 */

eador_s32 excluded_unit_categories[5];                    /* +0x5C */
eador_s32 evaluation_modifier_ids_candidate[3];           /* +0x70 */

eador_s32 effect_type_ids[8];                             /* +0x7C */
eador_s32 effect_magnitudes[8];                           /* +0x9C */
eador_s32 effect_aux_values[8];                           /* +0xBC */
```

Values above 1000 in `effect_type_ids` encode a unit-definition ID as `value - 1000` in the temporary-transformation path.

---

## 5. Function map

| Address | Working name | Status | Main result |
|---|---|---:|---|
| `00432950` | `sum_unit_instance_modifiers_candidate` | Proven | Sums selected upgrades, medals, and hero context. |
| `004328F0` | `sum_unit_intrinsic_modifiers_candidate` | Proven | Sums intrinsic UnitDef upgrade bundles. |
| `004A1F90` | `sum_hero_context_modifiers_candidate` | Strong | Personal hero/class/skill/equipment/set channel. |
| `004A2690` | `sum_commander_aura_modifiers_candidate` | Strong | Commander aura channel applied to troops. |
| `00454C70` | `random_below_ebx_candidate` | Proven | Bound in `EBX`, result in `EAX`; modulo-biased legacy RNG. |
| `00454E80` | `weighted_roll_candidate` | Proven | Returns selected ID; optional removal by selected value. |
| `00432480` | `calculate_unit_experience_threshold_by_definition_candidate` | Strong | Cumulative XP threshold with legacy truncation. |
| `00432570` | `calculate_unit_experience_threshold_candidate` | Strong | Instance-based threshold variant. |
| `00432660` | `calculate_unit_level_from_experience_candidate` | Proven | Returns level capped at 30. |
| `00432B60` | `choose_unit_level_upgrade_candidate` | Proven | Builds weighted candidate pool and returns selected upgrade ID. |
| `00433130` | `apply_unit_level_upgrade_candidate` | Proven | Applies upgrade or transformation modifier `0x3E`. |
| `004331F0` | `construct_unit_instance_candidate` | Proven | Initializes a `0xA4` persistent unit instance. |
| `00432E60` | `calculate_unit_gold_upkeep_candidate` | Proven | Base + attachments + percentage/flat modifiers, clamped to zero. |
| `004D01C0` | `get_effective_battle_modifier_candidate` | Proven | Runtime + persistent + intrinsic + aura with special override rules. |
| `004D0980` | `get_effective_battle_max_life_candidate` | Proven | Persistent max life plus side multiplier. |
| `004CEC40` | `resolve_attack_against_defence_candidate` | Proven | Legacy power variation, defence subtraction, minimum-damage chance. |
| `004D2DA0` | `calculate_ranged_attack_damage_candidate` | Proven | Ranged power versus ranged defence or resistance. |
| `004D2E60` | `calculate_melee_or_counterattack_damage_candidate` | Proven | Attack/counterattack versus defence or resistance. |
| `004D7050` | `execute_ranged_attack_candidate` | Proven | Full ordinary ranged execution lifecycle. |
| `004DCD90` | `execute_melee_attack_exchange_candidate` | Proven | Movement, first strike, primary melee hit, retaliation. |
| `004D9800` | `process_melee_or_counterattack_secondary_effects_candidate` | Strong | Hit-triggered debuffs, drains, cleave, action triggers, life steal. |
| `004D11C0` | `apply_attacker_on_hit_modifiers_candidate` | Strong | Narrow on-hit debuff stage. |
| `004D61E0` | `apply_damage_to_battle_unit_candidate` | Proven | Damage accounting, remove-on-damage effects, life, death, morale. |
| `004D1D30` | `resolve_battle_unit_death_candidate` | Proven | Morale propagation, revival, replacement, corpse/removal, rewards. |
| `004D1BF0` | `transfer_battle_unit_to_opposite_side_slot_candidate` | Proven | Copies full tactical record to opposite-side roster and clears source. |
| `004CE9E0` | `collect_adjacent_battle_units_candidate` | Proven | Returns six adjacent units on odd-row offset hex grid. |
| `004CEB40` | `sum_runtime_battle_modifiers_candidate` | Proven | Runtime-only modifier sum. |
| `004CEC00` | `initialize_runtime_modifier_node_candidate` | Proven | Initializes/inserts a preallocated `0x20` modifier node. |
| `004D0A70` | `adjust_battle_unit_morale_candidate` | Proven | Applies morale delta unless modifier `0x13`; tracks morale break. |
| `004D0B40` | `refresh_battle_unit_status_ui_candidate` | Proven | Presentation only; no combat mechanics. |
| `004D7A20` approx. | `apply_battle_action_to_unit_candidate` | Strong | Eight-clause action dispatcher; returns target current life. |
| `00458A90` | `calculate_province_gold_income_candidate` | Strong | Province gold-income pipeline. |
| `00456AF0` | `calculate_province_gem_income_candidate` | Strong | Province gem-income pipeline. |
| `00455C20` | `get_province_population_tier_candidate` | Strong | Maps population-like field to tier 1..11. |
| `00455630` | `sum_active_province_site_modifiers_candidate` | Strong | Sums active site modifier pairs. |
| `00458980` | `sum_army_province_income_modifier_candidate` | Strong | Army/provider modifier `0x3A` to province income. |
| `00469D20` | `sum_ruler_structure_modifiers_candidate` | Strong | Ruler-wide structure modifier aggregator. |
| `0046B2A0` | `calculate_unit_gold_recruitment_cost_candidate` | Strong | Base, ruler modifier, resource surcharge, distance multiplier. |
| `0046B1D0` | `calculate_unit_gem_recruitment_cost_candidate` | Strong | Gem counterpart. |
| `0045EE00` | `read_var_token_to_eax_candidate` | Strong | Reads until `:` or `;`, NUL-terminates, returns token length. |
| `0045EE70` | `parse_var_integer_candidate` | Proven | Signed decimal parser with delimiter termination. |
| `0045ED70` | `parse_var_string_candidate` | Strong | Allocates/returns parsed string; decompiler return type was wrong. |

---

## 6. Unit progression

### 6.1 Experience-to-level

`calculate_unit_level_from_experience_candidate` uses the unit definition’s experience coefficient and caps the result at 30.

For coefficient 100, thresholds begin:

```text
20, 50, 90, 140, 200, ...
```

The implementation compares cumulative integer values. Preserve original integer ordering.

### 6.2 Upgrade selection

`choose_unit_level_upgrade_candidate`:

1. clears the global weighted roller;
2. examines six candidates per static level row;
3. uses the first 20 rows as fresh option sources;
4. checks three prerequisite modifier IDs at `EadorUnitUpgradeDef +0x1C`;
5. adjusts weights for prior selections and repeated candidate appearances;
6. excludes conflicts with a supplied upgrade ID;
7. returns a weighted selection.

The static definition provides 20 rows, while the live unit stores 30 selected upgrade IDs. Levels 21–30 therefore continue from the accumulated candidate pool rather than receiving a new static row.

### 6.3 Applying an upgrade

Ordinary upgrade:

```text
save old max life
store upgrade at level_upgrade_ids[level]
increment level
recompute max life
add max-life delta to current life
```

This preserves absolute missing life rather than health percentage.

Special modifier `0x3E` in the first modifier slot means unit transformation:

```text
experience /= 2
unit_definition_id = modifier magnitude
recalculate level
clear upgrade entries from new level through index 29
```

---

## 7. Modifier composition

Persistent effective stat:

```text
UnitDef base scalar
+ intrinsic UnitDef bundles
+ selected level upgrades
+ attachments
+ personal hero context
```

Battle-time effective modifier additionally includes:

```text
runtime tactical nodes
+ commander aura
+ terrain/context contributions
+ resource-state penalties or bonuses
```

Important special rules in `get_effective_battle_modifier_candidate`:

- modifier IDs `0x20..0x22` return zero when modifier `0x0E` is active;
- for modifier `0x19`, a positive runtime value suppresses the persistent contribution rather than stacking normally;
- battle-owned/nonpersistent tactical units omit commander aura.

Personal hero modifiers and commander-aura modifiers are separate channels in class, skill, equipment, and set data.

---

## 8. Legacy RNG and weighted selection

The implementation-facing specification and vectors are in `LEGACY_RNG.md`.

### 8.1 CRT state and generator

`00404B0B` is `crt_srand`:

```c
__getptd()->_holdrand = seed;
```

The paired `_rand` symbol is the statically linked Microsoft CRT generator. Its
compatibility recurrence is:

```text
state = state * 214013 + 2531011       (uint32 wrap)
value = (state >> 16) & 0x7fff
```

The original state is thread-local CRT state. All ordinary random consumers
executed on the main game thread therefore share one call-order-sensitive
sequence. Project EGO's named independent streams are not Genesis-compatible.

### 8.2 Random below bound

`random_below_ebx_candidate`:

```text
input bound: EBX
return: EAX
```

It returns zero without advancing state when the bound is zero. Otherwise it
consumes one CRT value. For bounds above 30000 it repeatedly divides a copy of
the bound by ten and appends one `rand()%10` digit per loop before applying
modulo to the original bound. The modulo bias and variable call count are
original behaviour.

### 8.3 Weighted roller

The ordinary global roller at `00454E80`:

1. sums all weights;
2. calls `00454C70` for a roll in `[0,total-1]`;
3. finds the first cumulative interval containing the result;
4. returns the corresponding value;
5. optionally zeroes every entry whose value equals the selected value.

Removal is by value, not by array position. Total weight zero remains open.

### 8.4 Contextual selector family

`00454DC0`, `00454F80`, and `00455050` do not call CRT `_rand` or
`00454C70`. They are deterministic/contextual position selectors and must not
be represented as separately advancing RNG streams. Their hidden register
arguments and exact contextual formulas are not yet typed completely.

### 8.5 Recovered reseed epochs

Proven principal calls include:

```text
startup/content load     time64() % 10000
setup/map initialization stored map seed
map generation           map seed; zero becomes 111
global strategic tick    map_seed + strategic_turn
menu/transition paths    counter cycling 1..10000
```

The `crt_srand` XREF list also names a conditional battle-outcome call whose
local expression was not fully included in the packet. Save/load persistence of
live `_holdrand` state is not established. See open question 4c.

---

## 9. Tactical stat and damage model

### 9.1 Power-versus-defence resolver

For raw power `P`:

```text
spread = max(floor(P / 5), 1)
randomized power = P + spread - random_below(2*spread + 1)
power is clamped to at least 1
```

If power exceeds defence, return the difference.

When defence absorbs the attack, damage can still be 1 for small gaps. A defence gap of 10 or more guarantees zero in the ordinary random branch.

### 9.2 Offensive-state penalties

Attack, counterattack, and ranged attack are reduced by:

- severe wounds below half effective maximum life, unless modifier/ability `0x0D` applies;
- stamina below 6: minus 10% per missing point;
- morale below 6: minus 10% per missing point.

The three offensive-stat functions share the same final morale arithmetic:

```text
pre = trunc0(internal_scaled_value / 100)

morale 0..5:
    bonus_percent = 10 * morale - 60
morale 6..15:
    bonus_percent = 0
morale >=16:
    bonus_percent = 5 * triangular_band_index(morale)

result = max(1, pre + trunc0(bonus_percent * pre / 100))
```

`EXP-R5-001` proves that both divisions truncate signed values toward zero.
The final divide uses reciprocal `0x51EB851F`, arithmetic shift by five, then
adds the shifted value's sign bit as the correction. At morale 0, `pre=19`
returns 8 and `pre=7` returns 3; flooring a combined `0.4` multiplier would be
wrong.

Matching final tails:

```text
attack         004D1995..004D19ED
counterattack  004D1824..004D187B
ranged attack  004D15F6..004D164D
```

The executable's internal ×100 temporary representation is diagnostic only.
The binding behaviour is the truncation order, signed rounding direction,
percentage curve, and the entry-specific reachability of the final clamp.

The three functions differ before that shared tail:

```text
attack
    modifier 0x26 early return: 004D1895..004D18A7
    final minimum-one clamp:    004D19E8..004D19ED

counterattack
    modifier 0x26 early return: 004D1667..004D167B
    final minimum-one clamp:    004D1876..004D187B

ranged attack
    zero early-sum branch:      004D14D0..004D14D9
    final minimum-one clamp:    004D1648..004D164D
```

For attack and counterattack, absence of modifier `0x26` leaves no zero-stat
guard: a zero accumulated value reaches the clamp and returns `1`. Ranged
attack instead tests the sum of definition base, instance modifiers and
intrinsic modifiers. If that sum is zero, it returns zero before runtime-node
modifiers, commander aura and all wound/stamina/morale arithmetic.

This is a function-level result. It does not establish whether a ranged-only
unit is offered a melee command by the tactical command layer.

### 9.3 Melee damage calculator

Logical inputs:

```text
ECX attacker
EAX target
stack bool: ordinary attack versus counterattack
```

Notable modifier branches:

```text
0x1B  use target resistance instead of defence
0x27  halve target defence
0x3D  add alignment-dependent attack contribution
0x4C  subtract from target defence
0x35  conditional defensive contribution on target
```

### 9.4 Ranged damage calculator

Hidden register convention:

```text
EDI attacker
EAX target
```

Notable branches:

```text
0x1C  selects resistance-based path and damage accounting channel 2
0x11  halves ranged defence
0x4D  subtracts from ranged defence
0x5F  subtracts from resistance in the resistance path
0x3C  can add excess-over-resistance contribution
```

---

## 10. Tactical turn structure and attack execution

### 10.1 Whole-side phase scheduler

`004EC4C0` owns the tactical interaction loop. The active side is stored in
`g_current_battle_side` (`DAT_0052E43C`). The initiative comparison writes the
initial value at `004EEE1C` or `004EEE2D`.

The side-advance helper is `004E6530`. It snapshots the current side at
`004E6557`; when its first argument is nonzero, the assembly performs:

```asm
004E66F9  MOV ECX,1
004E66FE  SUB ECX,EBX
004E6700  MOV EBX,ECX
004E6709  MOV [g_current_battle_side],EBX
```

The helper then initializes units belonging to the newly current side. A zero
first argument bypasses this toggle.

Inside `004EC4C0`, battlefield selection at `004F13C8..004F1453` scans the
37 records belonging to `g_current_battle_side` and selects the record at the
clicked coordinates. Movement, attack and action paths return to the same
interaction loop without invoking the side-advance helper.

Normal phase advances occur in two places:

```text
004F2070..004F2077  explicit side pass/end-phase command -> 004E6530(1,1)
004F20AE..004F214D  all 37 current-side slots exhausted -> 004E6530(1,1)
```

Therefore Genesis uses whole-side phases. Units on one side may be selected in
any order and may be re-entered while still eligible; the enemy receives control
only after a side-level pass or exhaustion. Unit-by-unit side alternation is
rejected.

This control-flow result is binding for legacy RNG ordering. It does not by
itself settle whether a specific start-of-turn effect belongs to the side-phase
boundary, the complete two-side round boundary, or unit activation.

### 10.2 Ordinary ranged attack

`execute_ranged_attack_candidate`:

```text
determine one or two shots
cap by ammunition
for each shot:
    calculate ranged damage
    clamp to target life
    add to attacker ranged-damage accumulator
    consume ammunition
    apply narrow ranged on-hit modifiers
    apply central damage with channel 1 or 2
    increment ranged kill counter on death
apply stamina cost
clear remaining action/movement state
refresh UI
```

Special attacker modifiers `0x2E` and `0x2F` replace ordinary damage with disabling runtime-effect packages.

### 10.3 Melee exchange

`execute_melee_attack_exchange_candidate` uses the global current battle unit as attacker and receives destination coordinates plus target.

Flow:

```text
optional movement
possible target first strike
attacker normal attack
possible target retaliation
return whether attacker survived
```

First-strike conditions strongly support:

```text
0x10  first-strike/pre-emptive-retaliation candidate
0x1A  suppress enemy retaliation candidate
0x26  offensive disable
```

Modifier `0x25` provides the charge damage bonus. `004DCD90` first compares the
requested destination with the attacker's current coordinates. When movement is
required, it reads the attacker's and target's current `+0x44/+0x48` coordinates
and computes:

```text
max(abs(attacker_x-target_x) + abs(attacker_y-target_y) - 2, 0)
```

It stores that value before calling `move_battle_unit_candidate` with the
requested destination. This is command-entry target separation, not cumulative
movement history or destination displacement. A no-movement attack leaves the
bonus at zero.

### 10.4 Primary hit ordering

For melee/counterattack:

```text
calculate and clamp damage
record dealt damage
process secondary effects
record target damage channel 0
remove remove-on-damage effects
subtract life
resolve death or large-hit morale reaction
```

Secondary effects therefore run before the main hit is committed to `current_life`.

---

## 11. Hit-triggered secondary effects

`process_melee_or_counterattack_secondary_effects_candidate` handles:

- temporary penalties;
- stamina and ammunition drains;
- resistance-gated status packages;
- triggered battle actions;
- adjacent/cleave secondary attacks;
- healing proportional to primary damage.

Established candidates:

```text
0x28  stamina drain
0x2C  ammunition drain
0x41/0x42  adjacent secondary-hit branch
0x44  healing/life-steal proportional to dealt damage
0x4F/0x50  automatic battle-action triggers
```

Recursive secondary hits pass `is_root_hit = false`, preventing infinite propagation.

---

## 12. Central damage and morale

`apply_damage_to_battle_unit_candidate`:

```text
increment selected received-damage channel
remove runtime nodes with remove_on_damage
subtract current life
if zero:
    resolve death
else if large hit and channel != 3:
    process morale reaction
return death flag
```

A large hit is:

```text
damage >= max_life / 4
or damage > 9
```

Modifier `0x19` has special interaction with this reaction.

`adjust_battle_unit_morale_candidate` applies signed morale changes unless modifier `0x13` blocks them. Underflow is converted into `morale_break_accumulator_candidate` in ten-point steps and current morale is clamped to zero.

---

## 13. Death, revival, transformation, and side transfer

`resolve_battle_unit_death_candidate` handles several special runtime effects before ordinary removal.

### Established special modifier behaviours

```text
0x4A  full revival
0x5A  revert temporary battle transformation
0x5B  replace dead unit with a new persistent unit based on tier
0x49  opposite-side transfer/return-slot mechanic
```

The game-facing names remain unresolved.

### Morale propagation

Death causes:

- allied adjacent units: morale -1;
- opposing adjacent units: morale +1;
- a hero-associated death also applies a broader allied morale penalty to a fixed tactical-slot range.

### Persistent versus battle-owned units

`battle_owned_unit_instance_candidate` distinguishes tactical-only units:

- no commander aura;
- on death, the persistent instance is freed;
- reward/statistic accumulators are updated;
- the tactical slot is fully cleared.

Persistent units can leave corpses on the field depending on category and terrain.

### Side transfer

`transfer_battle_unit_to_opposite_side_slot_candidate`:

- copies the full `0x80` record into an opposite-side slot;
- changes side index;
- preserves slot-local UI resources;
- clears the source record.

---

## 14. Hex grid and formation

Battle adjacency uses an odd-row offset hex grid.

For center `(x, y)` with `p = y & 1`:

```text
(x + p - 1, y - 1)
(x + p,     y - 1)
(x + 1,     y)
(x + p,     y + 1)
(x + p - 1, y + 1)
(x - 1,     y)
```

The helper scans 37 tactical slots and returns at most six living adjacent units.

Persistent deployment coordinates are stored in each `EadorUnitInstancePartial`. Automatic placement resolves collisions and writes chosen coordinates back to the persistent unit.

---

## 15. Battle actions

The generic unit-targeted action function processes eight parallel clauses.

Per-clause scaling:

```text
effective magnitude =
    base magnitude
    + hero modifier 0x389 * action +0x30 / 100

effective positive auxiliary value =
    base auxiliary
    + hero modifier 0x38A * action +0x34 / 100

resistance component =
    target effective resistance * action +0x38 / 100
```

Most ordinary effect clauses create or update runtime modifier nodes. Existing effects from the same source action and same modifier ID generally keep the stronger magnitude/duration rather than stacking duplicates.

An action flag near `+0x58` selects a separate always-create branch. Its semantic name remains unresolved.

Values above 1000 trigger temporary tactical transformation and create runtime modifier `0x5A` for restoration.

The effect dispatcher contains many special cases. Only a subset has been interpreted. This is one of the largest remaining bodies of already-collected evidence.

---

## 16. Economy fragments

### 16.1 Unit gold upkeep

```text
base upkeep
+ three attachment gold-upkeep deltas
+ percentage modifier 0x55
- flat modifier 0x36
clamp to zero
```

### 16.2 Recruitment cost

Gold and gem recruitment costs follow parallel pipelines:

```text
base price
ruler modifier
strategic-resource surcharge
route/distance class
+10% per distance step beyond the first
```

Out-of-range distance is replaced or clamped to class 11.

### 16.3 Province income

Recovered components include:

- population/development tier 1..11;
- active province-site modifiers;
- ruler structure modifiers;
- stationed-army economic modifier `0x3A`;
- separate gold and gem pipelines.

The formulas are sufficiently important to preserve, but not yet normalized into a single compatibility specification or test suite.

---

## 17. `.var` parser

Established lexical behaviour:

```text
':' and ';' terminate ordinary tokens
'#' is used by the string path
non-digit terminates integer parsing
'-' marks a negative integer
```

`read_var_token_to_eax_candidate` receives the destination buffer in hidden `EAX`, consumes the delimiter, NUL-terminates, and returns token length.

`parse_var_integer_candidate` returns a signed decimal integer with no visible overflow handling.

The large startup loader contains enough repeated reads and error strings to
reconstruct per-file schemas, but that extraction has not yet been performed
systematically.

### 17.1 R2 reference namespaces

`initialize_game_content_and_state` at `0045EF60` and the corresponding
consumers establish two distinct source-reference conventions:

```text
unit.var Abilityes -> unit_upg record index

item.var Effects  -> direct modifier opcode
medal.var Effects -> direct modifier opcode
spell.var Effects -> direct action-effect opcode
```

The three direct opcode families use the numeric namespace documented by
`ability_num.Number`. The executable generally stores and dispatches the number
directly rather than looking up an `ability_num` record at runtime.

The item consumer `004A1F90` compares effect IDs directly with its requested
modifier. The medal consumer `00432950` does the same after indexing a `0x88`
medal record. The battle-action dispatcher switches on spell effect IDs and uses
ordinary IDs directly when creating runtime modifier nodes. None of these paths
multiplies the effect value by the `unit_upg` stride `0x58`.

The persistent fields at `EadorUnitInstancePartial +0x94..+0x9F`, previously
named generically as attachments, are three `medal.var` record indexes. This
semantic rename changes no layout. The stable header can adopt `medal_ids` at
the next schema checkpoint.

These source conventions do not require Project EGO to model named upgrades
such as `Жизнь +2` as runtime effect types. The normalization boundary is defined
in `CONTENT_REFERENCE_MODEL.md`.

---

## 18. Important work still present in the collected corpus

The next phase should process existing evidence before requesting broad new function dumps.

### Priority A — battle-action effect dictionary

Fully classify every `effect_type_id` branch in `apply_battle_action_to_unit_candidate`:

- immediate life damage/healing;
- stamina, morale, and ammunition changes;
- runtime modifiers;
- transfer/control effects;
- transformation;
- resurrection/replacement;
- special damage;
- action flags and resistance coefficients.

Deliverable:

```text
effect_type_id
input fields used
immediate/runtime behaviour
stacking rule
damage channel
death/morale interaction
confidence
```

### Priority B — modifier ID dictionary

The project has accumulated dozens of numeric modifier IDs. Their mechanics are often known, but names are not.

Cross-reference:

- `unit_up.var`;
- action/skill data;
- localized descriptions;
- UI labels;
- effect source-definition IDs.

Do not infer user-facing names solely from mechanics.

### Priority C — startup-loader schema extraction

Turn the startup loader into explicit schemas for each `.var` file:

```text
record count
record stride
field order
nested array counts
delimiters
validation limits
error strings
destination table
```

This is essential for data compatibility and mod support.

### Priority D — economy normalization

Convert recovered province and recruitment formulas into:

- exact pseudocode preserving integer truncation;
- field/offset map;
- modifier-provider list;
- golden test vectors from the original executable.

### Priority E — tactical AI scoring

`closer_inspection_5.txt` and the `unit_calls_*` files contain substantial AI evaluation and action-targeting logic that has barely been consolidated.

This is valuable after the mechanics layer is stable. It should not block implementation of deterministic combat rules.

### Priority F — regression tests

Before more renaming, add compatibility tests for:

- RNG and weighted selection;
- XP thresholds and level calculation;
- upgrade selection with fixed roller state;
- max-life delta on level-up;
- power-versus-defence;
- melee first strike and retaliation;
- ranged shot count and stamina cost;
- damage channels and large-hit morale;
- revival, transformation rollback, and side transfer;
- odd-row adjacency.

---

## 19. Recommended repository transfer

### Commit 1 — evidence checkpoint

```text
eador_runtime.h
docs/REVERSE_ENGINEERING.md
docs/FUNCTION_MAP.csv
```

No production code changes in this commit.

### Commit 2 — pure compatibility primitives

Implement and test:

```text
legacy RNG
weighted roller
XP/level thresholds
hex adjacency
power-versus-defence
```

These functions are comparatively isolated and suitable for golden tests.

### Commit 3 — unit modifier and progression layer

Implement:

```text
intrinsic modifiers
instance modifiers
hero personal modifiers
commander aura modifiers
level-up selection/application
upkeep
```

### Commit 4 — tactical runtime and damage layer

Implement:

```text
runtime modifier list
effective battle modifier
effective stats
damage calculators
central damage sink
morale adjustment
```

### Commit 5 — attack executors and death lifecycle

Implement:

```text
ranged executor
melee exchange
secondary hit effects
death/revival/transformation/side transfer
```

### Later commits

```text
generic battle actions
economy
data loaders
AI scoring
UI/presentation
```

---

## 20. Rules for future agents

1. Read `AGENTS.md`, this document and `eador_runtime.h` before opening new functions.
2. Navigate by address, not only by renamed symbol.
3. Preserve legacy integer division and hidden-register calling conventions.
4. Mark every claim as proven, strong inference, candidate, or unknown.
5. Do not rename numeric modifiers to localized ability names without data-file evidence.
6. Update the function map and open-question list in the same commit as any new reverse-engineering claim.
7. Add a compatibility test whenever a formula becomes implementation-grade.
8. Never silently replace a legacy-biased RNG or truncation order with a cleaner modern equivalent.
9. Separate mechanics from UI and animation helpers.
10. Treat `eador_runtime.h` as the stable Ghidra import target; keep versioned snapshots for provenance.

---

## 21. Immediate decision

The correct next action is **documentation and repository transfer now**, followed by targeted processing of the existing battle-action dispatcher and data loader.

Further broad decompilation collection should pause until:

- the current header is committed;
- the function map is available to other agents;
- core formulas have tests;
- the remaining effect and modifier dictionaries are explicit.

The reverse engineering has reached a coherent module boundary. Continuing without this checkpoint would increase duplication, naming drift, and the chance that later agents repeat already-solved work.
