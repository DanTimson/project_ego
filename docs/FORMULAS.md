# Formulas — project_ego

Every quantitative rule recovered so far, with its source and its verification
status. This is the reference; `oracle/combat.py` is the executable form and
`oracle/test_combat.py` is the proof.

**Sources**

| tag | meaning |
|---|---|
| `[GM]` | Eadoropedia, *Игровая механика* — named section given |
| `[AB]` | Eadoropedia, *Способности* — the game's own tooltip templates (still carry `%d`/`%s`) |
| `[VAR]` | Derived from the `.var` data directly |
| `[OBS]` | Established by controlled play observation |
| `[PROJECT]` | Project EGO policy frozen by an accepted task/fixture |
| `[BIN]` | Recovered from the inspected 32-bit executable |
| `[ASSUMED]` | Our reading, not confirmed — see `OPEN_QUESTIONS.md` |

**Verification status**

| tag | meaning |
|---|---|
| `VERIFIED` | Implemented and checked against a published table by `test_combat.py` |
| `STATED` | Documented but with no table to check against |
| `RECOVERED` | Implementable binary behaviour; version-specific until tested |
| `OPEN` | Value or behaviour still unknown or contradictory |

> **Version caution.** The Eadoropedia build (NH 25.0101.f03) does **not** match
> our local `.var` set — same abilities and ordering, different numbers. Use the
> wiki for *mechanisms*, never as numeric ground truth for our data.

---

## 1. Attack value

`[GM] Тяжёлые ранения` · **VERIFIED**

```
ТекущаяАтака = (БазоваяАтака + ПлюсуемыеБонусы) * StaminaMod * MoraleMod * WoundMod
```

Additive bonuses apply **before** multiplicative ones. Stated outright:
*«Сначала к Атаке применяются "плюсуемые" бонусы … а потом уже "умножаемые"»*.
This is not a stylistic choice — it is the resolution order and it is fixed.

Applies identically to Атака, Контратака and Дистанционная Атака.

### 1.1 Conditional attack contributions

`[GM] Боевой дух` · `[AB] Сокрушение зла` ·
`[BIN:004D2E60; EXP-R9-001]` · **RECOVERED / PUBLICLY CORROBORATED**

Eadoropedia states that morale multiplies direct attack bonuses visible on the
battle panel but does not increase conditional damage such as
`Сокрушение зла`. The executable resolves the previously unstated wound and
stamina placement.

For ordinary melee attack and counterattack:

```text
direct =
    effective_attack(attacker)
    or effective_counterattack(attacker)

if ordinary_attack and selected_1_5x_attack_mode:
    direct += trunc0(direct / 2)

conditional = 0
if smite_evil > 0 and target_alignment < 0:
    conditional = smite_evil * abs(target_alignment)

attack_power = direct + conditional
damage = resolve_attack_against_defence(attack_power, defence_or_resistance)
```

The effective-stat call has already completed:

1. direct definition/instance/intrinsic/runtime/aura provider addition;
2. wound and stamina multiplication;
3. truncation to the pre-morale integer;
4. morale adjustment;
5. final effective-stat minimum handling.

Consequently the conditional contribution is not reduced by wounds, exhaustion
or low morale and is not enlarged by high morale. It is also added after the
selected ordinary-attack 1.5× branch. It is nevertheless added **before** the
legacy attack randomisation and defence/resistance resolver, so it is an attack
power contribution rather than flat post-resolution damage.

Minimal distinguishing vectors, with direct attack `20` and qualifying
conditional contribution `5`:

| state | recovered attack-power input | if conditional were inside multiplier |
|---|---:|---:|
| healthy, neutral | `25` | `25` |
| 25% life (`×0.75`) | `20` | `18` |
| stamina 0 (`×0.4`) | `13` | `10` |
| morale 0 | `13` | `10` |
| selected 1.5× ordinary attack | `35` | `37` |

The vectors stop at the input to `resolve_attack_against_defence_candidate`;
final life damage also depends on random attack variation, selected defence or
resistance, and the minimum-damage rule.

The public description supports the morale carve-out. Exact wound, stamina,
1.5×-mode and randomisation placement comes from the already archived
`EXP-R9-001` function body. No additional binary extraction was required.

The live engine and oracle accept the already-resolved applicable contribution
through `conditional_bonus`; this is a numeric stage boundary, not a target-name
classifier. Address-free fixtures cover attack-power inputs `25`, `20`, `13`,
`13`, and `35`, plus counterattack inclusion and ranged exclusion. Scenario
traces expose the already-applicable conditional input before attack randomisation.

### 1.2 WoundMod

`[GM] Тяжёлые ранения` · **VERIFIED** against the published table

```
life >= 50% of base  ->  1.0
life <  50% of base  ->  0.5 + CurrentLife / BaseLife
```

| life | ×    | life | ×    |
|------|------|------|------|
| 50%  | 1.0  | 20%  | 0.7  |
| 40%  | 0.9  | 10%  | 0.6  |
| 30%  | 0.8  | ~0%  | ~0.5 |

Suppressed entirely by `Не чувствует боли` and by the `Боевое безумие` effect.

### 1.3 StaminaMod

`[GM] Выносливость` · **VERIFIED** against the published table

```
stamina >  5  ->  1.0
stamina <= 5  ->  0.4 + 0.1 * stamina
```

| stamina | atk × | speed | def × |
|---------|-------|-------|-------|
| 5 | 0.9 | −0 | 1.0 |
| 4 | 0.8 | −1 | 1.0 |
| 3 | 0.7 | −1 | 1.0 |
| 2 | 0.6 | −2 | 1.0 |
| 1 | 0.5 | −2 | 1.0 |
| 0 | 0.4 | −2 | **0.5** + forced Rest |

Speed floors at 1. At stamina 0 the unit is forced to Rest next round, does not
counterattack, both defence values are halved, and `Оглушающий удар`,
`Оглушающий выстрел` and `Удар щитом` against it drain an extra point of morale.

#### Effective defence at zero stamina

`[BIN:004D0820,004D06B0]` · **RECOVERED**

Both effective-defence functions aggregate their complete applicable provider
set before the stamina branch. Their shared final reduction is:

```text
value = aggregate_all_applicable_providers(unit)

if unit.current_stamina == 0:
    value = trunc0(value / 2)

return max(value, 0)
```

The predicate is exactly `current_stamina == 0`. The signed halving sequence
corrects an arithmetic shift so negative odd values truncate toward zero. The
minimum-zero clamp occurs afterward.

| accumulated value | stamina nonzero | stamina 0 |
|---:|---:|---:|
| -1 | 0 | 0 |
| 0 | 0 | 0 |
| 1 | 1 | 0 |
| 2 | 2 | 1 |
| 3 | 3 | 1 |
| 7 | 7 | 3 |

The engine/oracle trace records the complete provider total, any exact-zero
halving, and the final clamp as separate ordered stages. Deterministic ordinary
and ranged integration vectors use base `3` plus provider `4`: the trace must
show `7 -> 3`, so halving before providers fails.

Provider differences before this shared tail:

| contribution | ordinary defence `004D0820` | ranged defence `004D06B0` |
|---|---|---|
| UnitDef field | `+0x2C` | `+0x30` |
| primary modifier ID | `4` | `5` |
| persistent/intrinsic/runtime/aura | ID `4` | ID `5` |
| terrain-definition field | `+0x24` | `+0x28` |
| matching terrain modifier `0x20..0x22` | `trunc0(value/4)` | `trunc0(value/8)` |
| extra tactical contribution | none recovered | `+3` when `DAT_00520782 != 0` and battle-unit `+0x44 > 5`; semantics unnamed |

The tactical block runs only when `DAT_0052E438 == 0` and current life is
positive. Effective modifier `0x0E` suppresses the direct terrain-definition
contribution. Modifier `0x12` does not gate defence halving; its wider consumer
scope remains R11.

#### Modifier `0x12` (`Неутомимость`) stamina exemption

`[BIN:004D01C0; EXP-R11-001; EXP-R11B-001]` · **RECOVERED**

The executable implements the exemption through local consumer checks. All
recovered reachable tactical stamina decreases query effective modifier `0x12`
and skip the mutation when it is present. This includes movement, ordinary and
additional melee/ranged costs, action-definition costs, on-hit stamina drain,
phase effect type `0x0B`, and the recovered scripted direct reduction.

The common spend shape is:

```text
if modifier_0x12 == 0:
    actual = min(current_stamina, requested_cost)

    if current_stamina < requested_cost:
        apply morale adjustment for the shortfall

    stamina_spent += actual
    current_stamina -= actual
```

Exceptions remain guarded but use different accounting:

- the `004EF3DE` scripted reduction clamps stamina to at least two and does not
  update `stamina_spent`;
- action-effect type `0x0B` applies a signed adjustment and clamps to
  `[0, effective_max_stamina]` without updating `stamina_spent`. Its `0x12`
  guard blocks positive restoration as well as negative drain.

AI scoring, movement/path comparison, aggregate construction and
selection-interface availability also query `0x12` and treat stamina mechanics
as inapplicable.

The currently executable movement, ordinary/ranged attack-cost and
activated-action-cost sites perform this local numeric-ID check and emit a
suppression trace. Missing on-hit, scripted and generic phase-effect executors
were not manufactured merely to add consumers.

Effective attack, counterattack, ranged attack, speed, ordinary defence and
ranged defence do **not** query `0x12`. They continue to derive penalties from
the live stamina value. The recovered invariant is therefore:

```text
modifier 0x12 blocks every recovered tactical stamina mutation;
it does not separately suppress low- or zero-stamina stat penalties.
```

### 1.4 MoraleMod

`[BIN]` effective attack/counterattack/ranged-attack functions ·
`[GM]` «Боевой дух», Eadoropedia «Игровая механика» (NH 26.0620.f01)

Keyed on **absolute** morale. `morale_base` does not enter the attack
multiplier. Applies to the three attack values only — never to defence, which is
touched only by the stamina-0 halving in §1.3.

```text
morale 0..5   ->  0.4 + 0.1 * morale        (0 -> 0.4, and the unit panics)
morale 6..15  ->  1.0
morale >= 16  ->  1.0 + 0.05 * n,  where band n starts at 15 + n(n+1)/2
                  16-17 = 1.05   18-20 = 1.10   21-24 = 1.15   25-29 = 1.20
                  30-35 = 1.25   36-42 = 1.30   43-50 = 1.35   … («и так далее»)
```

**Low and neutral bands (0..15) — VERIFIED.** Two independent sources agree at
every point. The binary gives −10% attack per missing point below morale 6; the
published table gives `0.4 + 0.1 * morale` for 0..5. These are the same function:
morale 0 → 0.40, 3 → 0.70, 5 → 0.90, 6..15 → 1.00. The agreement holds across
two different builds (Genesis 1.05.2 binary, NH 26.0620.f01 documentation),
which is also weak evidence that New Horizons did not alter this curve.

**High band (≥16) — RECOVERED and independently corroborated.** The Genesis
functions for attack (`004D1890`), counterattack (`004D1660`) and ranged attack
(`004D14A0`) contain the same loop. It subtracts successively wider band widths
`1, 2, 3, ...` from `morale - 15`, adding five percentage points for each band.
The boundaries are therefore:

```text
16, 18, 21, 25, 30, 36, 43, 51, 60, ...
```

This exactly matches the preregistered NH 26.0620.f01 table. Rejected
alternatives are fixed five-point bands (`16/21/26/...`) and fixed two-point
bands (`16/18/20/...`).

The binary does not multiply by a float. After the earlier wound and stamina
steps it first converts the internal ×100 value back to an integer, then applies
the morale percentage:

```text
pre_morale = trunc0(scaled_attack / 100)
result = max(1, pre_morale + trunc0(bonus_percent * pre_morale / 100))
```

This is the shared **final tail after entry-specific guards**, not an
unconditional definition for every possible raw stat:

- attack (`004D1890`) and counterattack (`004D1660`) return zero first when
  modifier `0x26` is present; otherwise a zero accumulated stat reaches the
  final clamp and returns `1`;
- ranged attack (`004D14A0`) returns zero at `004D14D4..004D14D9` when the
  early sum of definition base, instance modifiers and intrinsic modifiers is
  zero. This occurs before runtime-node modifiers, commander aura and the
  wound/stamina/morale tail. Only a nonzero early sum reaches the minimum-one
  clamp.

The engine and oracle preserve this cutoff through source containers already in
the model: definition base plus unit modifiers form the early ranged sum, while
timed-status and environment/aura providers remain later. A deterministic
synthetic aura contributes `+6` ranged attack to a unit whose early sum is zero;
both live paths still return zero without resolving that aura. This implements
the provider cutoff without assigning new gameplay semantics to modifier source
text.

The effective-stat functions alone do not prove whether the command layer
offers melee to a ranged-only unit.

`trunc0` is signed truncation toward zero. The final division is compiled as a
signed reciprocal multiply followed by a sign correction in all three recovered
functions, so the negative low-morale branch is no longer inferred only from the
source language. Thus base 19 at morale 16 still returns 19, base 20 returns 21,
and base 19 at morale 0 returns 8 rather than 7. Preserve both truncation points,
the signed rounding direction, and the minimum-one clamp.

The internal ×100 representation is diagnostic rather than binding. An engine
implementation may use another representation if it reproduces these observable
results. Implementation and executable fixtures are maintained by the engine
side.

Carve-out: morale multiplies only direct attack bonuses, not conditional damage
such as «Сокрушение зла» — see §1.1.

---

## 2. Attack randomisation

`[GM][BIN:004CEC40] Расчёт урона при атаках` · **VERIFIED / RECOVERED**

```
Атака >= 5:  ИтоговаяАтака = Атака + Атака/5 - Random(2 * (Атака/5) + 1)
Атака <  5:  ИтоговаяАтака = Атака + 1     - Random(3)
```

- `Random(x)` is an integer in `[0, x-1]`.
- **All division is integer and floors.**
- Result clamps to a minimum of 1 — except under `Не сражается`, where attack,
  counterattack and ranged attack are all 0 and the unit cannot attack or
  retaliate at all.

Equivalent support, which the page itself gives as a cross-check: a uniform
integer over `[Атака − Атака/5, Атака + Атака/5]` at 5 and above, and over
`[Атака − 1, Атака + 1]` below.

**The clamp makes low values non-uniform.** At attack 1 the roll is
`2 − Random(3)` = `{2, 1, 0}` → clamped to `{2, 1, 1}`, so 1 lands twice as
often as 2. Real behaviour, not a defect; `test_combat.py` asserts it.

### 2.1 Do not use the simplified form

The page offers `Урон = Атака * Random(0.8; 1.2) − Защита` as a friendlier
equivalent and warns of *«небольшое отклонение»*. Measured:

| attack | exact mean | simplified mean | bias |
|--------|-----------|-----------------|------|
| 5  | 5.00  | 4.49  | −0.50 (10.1%) |
| 10 | 9.98  | 9.50  | −0.49 (4.9%)  |
| 20 | 19.99 | 19.48 | −0.50 (2.5%)  |
| 50 | 49.91 | 49.51 | −0.40 (0.8%)  |

`floor()` truncating a symmetric distribution biases it low by a **constant**
~0.5. That is a 10% error on weak units and negligible on strong ones — so an
implementation built from the simplified formula systematically under-damages
exactly where it is most noticeable. Use the exact form.

---

## 3. Damage

`[GM][BIN:004CEC40] Расчёт урона при атаках` · **VERIFIED / RECOVERED**

```
Урон = ИтоговаяАтака - Защита
```

`Защита` is the defender's final Защита / Защита от выстрела / Сопротивление
after all its own modifiers, clamped to a minimum of 0.

### 3.1 Negative damage still lands sometimes

```
if -9 <= Урон <= 0:   one point of damage if  Random(20 + Урон) >= 10
if Урон <= -10:       nothing
```

Probability `1 − 10/(20 + Урон)`:

| Урон | P | Урон | P | Урон | P |
|------|-----|------|-----|------|-----|
| 0 | 50% | −4 | 38% | −8 | 17% |
| −1 | 47% | −5 | 33% | −9 | 9% |
| −2 | 44% | −6 | 29% | ≤−10 | 0% |
| −3 | 41% | −7 | 23% | | |

All twelve rows are asserted by `test_combat.py`. (The page prints 38% at −4
where the closed form gives 37.5%; it rounds up.)

This rule is why chip damage exists against heavily armoured targets, and no
amount of play observation would have recovered the exact curve.

---

## 4. Stamina economy

`[GM] Выносливость` · **STATED**

Base and current values; current resets to base after every battle.

| event | Δ |
|---|---|
| attack, having moved this round | −2 |
| attack, without having moved | −1 |
| casting a spell | per spell description; `Умелый заклинатель (X)` reduces by X, to 0 |
| skipping the turn | +(2 + `Восстановление сил`) |
| Rest command | +(2 + `Восстановление сил`); also forgoes counterattacks |
| each hill or swamp tile crossed | −1, unless `Знание холмов` / `Знание болот` |
| each tile, if Speed reduced to ≤0 | −1 |
| any movement at all, with `Тяжёлая броня` | −(ability value) |
| start of round, with `Прилив сил` | +(ability value) |
| using an activated ability | its stated cost **+1** (the extra is for the attack itself) |

Under the `Зуд` effect (ability #249) the `Восстановление сил` bonus is 0
regardless of its value.

`Летающий` and `Низколетающий` pay no stamina for hills, forest or swamp.

`[OBS]` Starting and ending the round on the same hex still counts as having
moved in the observed build.

`[BIN:004D0560,004D7050,004E0280]` · **RECOVERED**

The executable's predicate is live capacity, not movement history:

```text
effective_speed =
    unit-definition speed
  + numeric modifier 7 from persistent, intrinsic and runtime providers
  + eligible commander-aura modifier 7

if stamina < 5 and effective_speed > 1:
    effective_speed -= 1
if stamina < 3 and effective_speed > 1:
    effective_speed -= 1
effective_speed = max(effective_speed, 1)

base_ranged_attack_stamina_cost =
    2 if remaining_capacity < effective_speed else 1
```

The comparison is strict less-than. Capacity equal to or temporarily above the
current effective speed costs 1. Modifier `0x12` suppresses the deduction.

Ordinary same-side deselection/reselection writes the selected-unit global and
presentation links but preserves the unit's remaining capacity. Non-movement
action effects can increment or restore that capacity, including restoration
capped to current effective speed. Consequently `steps_this_round > 0` is not
an equivalent Genesis compatibility predicate: move → restore to full capacity
→ reselect → ranged attack costs 1 in the executable.

The published “moved this round” wording remains useful player-facing prose, but
the binding compatibility rule is the live-capacity comparison above.

---

## 5. Morale

`[GM] Боевой дух` · **STATED**

Rises when the unit kills an enemy, when an enemy dies on an adjacent tile, or
when an enemy hero dies. Falls when the unit takes a heavy wound, when an ally
dies on an adjacent tile, or when its own leading hero dies. Heroes
additionally gain from enemy unit losses and lose from their own.

Out of combat: capped at base when a battle ends (excess is discarded), then
+1 toward base immediately after a battle and per 2 map turns without one.

Exceptions:
- `Неустрашимый` — never loses morale, but gains at half rate.
- `Боевое безумие` — restores morale to base and blocks all morale effects,
  positive and negative alike.
- `Великан` subtype — loses at most 1 morale to any fear ability, and is harder
  to frighten through damage.

---

## 6. Movement and commands

`[OBS][BIN:004EC4C0,004E6530]` · **RECOVERED / STATED**

**Attack commands carry an implicit movement component.** Issuing an attack
against a reachable target auto-paths the unit into position; the player does
not move and then attack as two separate commands. Auto-path movement draws
from the same action-point pool.

Activation is free and re-entrant **before a terminal action**: a unit may
spend part of its movement, yield control, and be reselected later in the same
round to finish moving or take its action. There is no initiative queue within
a side.

`[OWNER:2026-08-09]` · **STATED** — After successful resolution, ordinary melee
and ranged attacks, and activated actions whose resolved actor policy consumes
the action, close only the acting unit's activation. Leftover movement does not
keep that actor eligible afterward. Reactions and rejected commands do not spend
their source's activation. An action for which
`resolved_consumes_action(actor)` is false remains explicitly non-terminal.
This owner-confirmed rule is not labelled binary-verified.

**Battle scheduling is whole-side.** Initiative chooses the first side once.
Ordinary unit movement, attacks and actions do not yield control to the enemy.
The current side retains control until the player/AI passes the side phase or no
eligible current-side unit remains; `004E6530` then toggles
`g_current_battle_side = 1 - g_current_battle_side` and initializes the next
side phase. Pass is therefore per side, not per unit.

This ordering is compatibility-significant because ordinary random consumers
from the entire current-side phase advance one shared legacy CRT sequence before
the opposing phase begins.

Current Project EGO state:

- `steps_this_round` is cumulative path length, not displacement.
- the recovered ranged-attack stamina cost keys on live remaining capacity
  versus effective speed (R8), not on prior movement state; the existing
  non-ranged cost boundary remains separate;
- the observed `Удар и возврат` anchor is the tile where the attack command was
  issued;
- start-of-turn effects currently fire once per round.

Genesis compatibility rule:

`[BIN:004DCD90]` Modifier `0x25` (`Charge / Атака с разгона`) is calculated
before the current attack command's approach movement:

```text
movement_requested =
    destination_x != attacker.current_x
    or destination_y != attacker.current_y

charge_bonus =
    movement_requested and attacker has modifier 0x25
    ? max(
          abs(attacker.current_x - target.current_x)
        + abs(attacker.current_y - target.current_y)
        - 2,
          0
      )
    : 0
```

The movement helper is called only after this value is stored. The formula
therefore uses the tile occupied when the attack command begins, not cumulative
path length and not the displacement to the selected destination.

Consequences:

- earlier movement affects charge only by changing the unit's current tile;
- yielding and reselecting does not preserve a separate accumulated distance;
- moving away and back cannot farm a larger Genesis bonus;
- a cumulative `steps_this_round` rule is a Project EGO-native alternative, not
  an exact legacy rule.

Only the initiating attacker's primary ordinary melee hit consumes the stored
integer. It is added after randomized/defended ordinary damage, without another
randomisation or defence pass, and the combined value is capped to the target's
current life before central application. Defender first strike, retaliation,
ranged attacks and actions do not receive it. Command-entry resolution and
primary-hit consumption are separate ordered trace stages.

The separate `Удар и возврат` anchor remains outside this tranche.

---

## 7. Spells

`[GM] Урон от заклинаний`, `Сила и длительность заклинаний` · **STATED**

```
TotalDamage = MagAttak * random(0.8; 1.2) - TotalResist * ResistPower
MagAttak    = BaseDamage + Power * PowerMod
```

`PowerMod`, `DurationMod`, `ResistPower` and `ResistDuration` are the hidden
per-spell fields, and they map one-to-one onto the `spell.var` columns of the
same names. They are **percentages per point of concentration**:

- `DurationMod 100` → +1 turn per point of concentration
- `DurationMod 200` → +2 turns per point
- `DurationMod 50`  → +1 turn per 2 points

`ResistPower` / `ResistDuration` work the same way in reverse, reducing power or
duration, and only for hostile spells. `Тавматургия` subtracts from the target's
resist before the calculation.

Worked example from the page, which checks out: concentration 3, thaumaturgy 2,
target resist 7 → effective resist 5. Base duration 6, both mods 100 →
`6 + 3 − 5 = 4` turns.

---

## 8. Non-combat rules worth recording

`[AB] Жизнь` · **STATED**
Attack is reduced below half maximum life (see §1.2). Out of combat, life
regenerates 10% per turn; province buildings can modify the rate.

`[GM] Уровни сложности` · **STATED**
Difficulty scales neutral unit life (55%→145%), battle XP (130%→70%), gold and
crystal income, corruption, and starting points across seven tiers from
Начинающий to Властелин.

`[VAR] terrain.var`, `bf_object.var` · **STATED**
Battlefield generation is fully data-driven: each province terrain maps to a
`(BF_Pass, BF_Impass)` pair of `bf_object` indices. Tiles carry `MoveCost`,
`StamCost`, and modifiers to `CounterAttack`, `Defence`, `RangedDefence` and
`ShootingRange`. `MoveCost: 0` means impassable.

`[GM] Стражи провинций` · **STATED**
Initiative is army-level: *«Первый ход в бою получает отряд, у лидера которого
выше инициатива. Если инициатива равна, первым ходит атакующий.»* One
comparison at battle start, on the leader's value, ties to the attacker.
Sources: `ability_num` opcode 999, `unit_upg` /818, and `Initiative` fields in
`defender.var`, `guard.var`, `item_set.var`.

---

## 9. Selected ability semantics

`[AB]` · **STATED**. Full table in the generated hook documentation; these are
the ones whose behaviour was not guessable from the name.

| ability | actual behaviour |
|---|---|
| `Первый удар` | When **attacked**, strikes first. Cancelled if the attacker also has it. Not an initiative mechanic. |
| `Парирование` | Adds to Defence when attacked in melee, with a **per-turn use cap**. |
| `Уклонение` | Reduces the attacker's ranged figure, and **accumulates** by the same amount per incoming shot until end of next turn. |
| `Бронебойный выстрел` | Ranged defence counted at **half**. Excluded against incorporeal targets and when using `Дополнительный выстрел`. |
| `Устрашение` | Melee attack reduces the target's morale. |
| `Затаптывание` | On melee attack, tramples if the target is left at or below N life; the attacker then moves onto its tile. |
| `Похищение душ` | On melee kill, restores N life. |
| `Мощь гноллов` | On another gnoll's death, a survivor **absorbs** the ability. Cross-unit state. |
| `Глухая оборона` | Activated: +N to both defences, grants `Бдительность` until next turn, at −N attack and counterattack. |

**14 abilities are activated actions, not passives** — the tell is
*«Особое умение, позволяющее воину…»* plus a stamina or ammo cost. They compete
for the unit's action and need an `Action` type, not a `Modifier`. Across the
documented set: 16 mention a stamina cost, 26 an ammo cost, 25 carry per-turn or
decaying state, 26 are area/adjacency scoped, 33 have explicit exclusion
clauses, and 8 state stacking rules outright.

---

## 10. Legacy CRT random and weighted selection

`[BIN:00404B0B,00454C70,00454E80]` · **RECOVERED**

Full implementation notes and golden vectors are in `LEGACY_RNG.md`.

### 10.1 CRT generator

```text
seed:
    state = seed mod 2^32

next:
    state = state * 214013 + 2531011 mod 2^32
    return (state >> 16) & 32767
```

This is one shared state per calling thread, not one state per gameplay
subsystem.

### 10.2 Bounded adapter

```text
random_below(0):
    return 0                         # consume no CRT value

random_below(bound > 0):
    value = crt_rand()
    reduced = bound
    while reduced > 30000:
        reduced = floor(reduced / 10)
        value = value * 10 + crt_rand() % 10
    return value % bound
```

All arithmetic in the accumulator is 32-bit legacy arithmetic. Do not replace
the final modulo with rejection sampling: its bias is original behaviour.

### 10.3 Weighted selection

```text
total = sum(weights)
roll = random_below(total)
select first entry whose cumulative weight exceeds roll
```

When removal is requested, every weight attached to the selected *value* is
zeroed. Removal is not limited to the selected array index. Total weight zero
remains unresolved.

### 10.4 Seed boundaries

Principal recovered seeds are:

```text
startup            time64() % 10000
map generation     map_seed, with 0 replaced by 111
strategic tick     map_seed + strategic_turn
```

Additional setup and menu/transition reseeds are documented in
`LEGACY_RNG.md`. Independent named streams are a Project EGO-native design
choice, not exact Genesis compatibility.

---

## 11. Unit progression

`[BIN:00432660,00432B60,00433130]` · **RECOVERED**

Ordinary unit level is capped at 30. The live unit stores 30 selected upgrade
IDs, while static unit definitions supply six fresh candidates for only the
first 20 levels.

For coefficient 100, the level thresholds begin:

```text
level 1: 20
level 2: 50
level 3: 90
level 4: 140
level 5: 200
```

The level calculator is equivalent to testing the cumulative threshold

```text
experience_coefficient * (5 * n * (n + 3)) / 100
```

with legacy integer arithmetic. Related display/threshold helpers divide during
individual summation steps and can differ by rounding; do not merge them without
vectors.

Ordinary upgrade application preserves absolute missing life:

```text
old_max = max_life(unit)
store selected upgrade at current level
level += 1
new_max = max_life(unit)
current_life += new_max - old_max
```

When the first modifier is ID `0x3E`, its magnitude is a replacement unit
definition. The unit's experience is halved, its definition changes, level is
recalculated and upgrade entries from that level through 29 are cleared.

---

## 12. Tactical execution and damage accounting

`[BIN:004D7050,004DCD90,004D61E0]` · **RECOVERED**

### Melee exchange

```text
optional approach movement
possible defender first strike
attacker primary attack
possible defender retaliation
```

For each melee/counterattack hit:

```text
calculate and clamp damage
record dealt damage
process melee secondary effects
record received damage channel 0
remove remove-on-damage statuses
subtract life
resolve death or large-hit morale
```

Secondary effects run before the primary life loss is committed.

### Ranged attack

```text
determine shot count and cap by ammunition
calculate and clamp ranged damage
record ranged dealt damage
consume ammunition
apply ranged on-hit effects
apply central damage
record ranged kill
spend stamina and end activation
```

### Received-damage channels

```text
0 -> melee or counterattack
1 -> ordinary ranged
2 -> ranged when attacker modifier 0x1C is active
3 -> special/action damage; skips ordinary large-hit morale reaction
```

The large-hit morale test is reached when damage is at least one quarter of
effective maximum life or exceeds 9, except on channel 3.

---

## 13. Runtime effects and death

### Stable Project EGO status operations

`[GM: Сила и длительность заклинаний]` · **STATED**
`[PROJECT: core/rules/statuses.gd; oracle/statuses.py]` · fixture-covered

For an ordinary duration-bearing application:

```text
effective_resist = max(0, target_resist - thaumaturgy)
gain = trunc0(concentration * DurationMod / 100)
loss = trunc0(effective_resist * ResistDuration / 100)
duration = max(0, base_duration + gain - loss)
```

A zero result rejects the application and leaves the target status collection
unchanged. `0` is not used here to define an `UNTIL_NEXT_TURN` boundary.

Stacking policy is a property of each effect identity/group:

- `CUMULATIVE` keeps a separate runtime instance;
- `MAXIMUM` retains the strongest-power instance;
- `REFRESH` retains one instance and takes the maximum current/new duration and
  power;
- `UNIQUE` ignores a reapplication while one is present.

Explicit group removal deletes every matching instance. Explicit duration
reduction subtracts the caller-supplied non-negative amount from matching,
non-permanent statuses, removes a result of zero, and may be narrowed to hostile
statuses and tags. These are direct operations, not a battle clock.

A status owns its modifier objects. Provider resolution remains:

```text
unit-owned/intrinsic modifiers                 # R6 ranged early provider
status/runtime modifiers + environment/auras  # later providers
```

No formula in this tranche selects an automatic round/selection/activation/
extra-turn decrement point, periodic-effect order, or `UNTIL_NEXT_TURN` expiry
edge. Those remain OPEN pending R13 observation. The pre-existing explicitly
called `tick_round` reference helper retains its provisional vectors but is not
wired to battle flow and is not compatibility truth.

### Recovered binary runtime node

`[BIN:004CEC00,004D1D30,004D1BF0]` · **RECOVERED**

A runtime modifier node stores:

```text
modifier ID
magnitude
duration/stack value
visible-in-status-UI flag
remove-on-damage flag
next/previous pointers
source action
source upgrade
```

Nodes are inserted at the head of a doubly linked list.

Established death-time special effects:

```text
0x4A -> full revival
0x5A -> revert temporary battle transformation
0x5B -> replace dead unit with a tier-dependent persistent unit
0x49 -> transfer/return through an opposite-side tactical slot
```

These are mechanical descriptions, not confirmed localized names.

### Implemented normalized tactical lifecycle

`[BIN: central damage/death/control summaries]` · `[PROJECT: CX-011]` ·
**RECOVERED / fixture-covered**

The live damage boundary is:

```text
account received-damage channel
remove runtime statuses explicitly marked remove-on-damage
subtract and floor current life at zero
if life is zero: resolve one fatal event immediately
```

`fatal_event` means only that this hit reached zero life and invoked the death
resolver. It is separate from final post-lifecycle alive state and does not mean
permanent death, kill credit, reward or an R17 trigger.

For each fatal event, living adjacent allies receive morale `-1` and living
adjacent opponents receive morale `+1` before any survival branch. Modifier
`0x13` suppresses the adjustment. Morale underflow floors current morale at zero
and adds ten break-accumulator points per missing morale point. The wider
hero-associated fixed-slot allied cohort has no address-free current-model
equivalent and remains intentionally unimplemented.

Only runtime `Status`-owned modifiers activate the special marker scan:

```text
remember 0x49 transfer, 0x4A revival and 0x5B replacement
apply 0x5A original-definition rollback and downward resource clamps
clear the complete runtime status collection
if 0x4A: revive to restored/current life maximum
elif 0x5B: replace by original tier (1->21, 2->37, 3->56, 4->65)
else: finalize death and remove living occupancy
apply representable 0x49 side transfer last
```

Revival clears morale break but preserves stamina, ammunition, morale, movement
capacity and action terminality. Replacement resets life/stamina/ammunition/
morale to the replacement maxima and clears morale break, but preserves
movement capacity, position and `action_spent`. Neither operation grants an
activation or advances a status clock.

Ordinary melee has two deliberately different continuation gates:

```text
lethal defender first strike -> resolve lifecycle -> primary occurs iff initiator is finally alive
lethal initiating primary    -> resolve lifecycle -> no ordinary retaliation, even if defender survives
```

This does not define secondary/R17 sequencing, kill credit or rewards.

---

## 14. Tactical grid

`[BIN:004CE9E0]` · **RECOVERED**

The inspected battle field uses an 8×8 odd-row offset hex grid. For offset
coordinate `(x, y)` and `p = y & 1`, the six neighbours are:

```text
(x + p - 1, y - 1)
(x + p,     y - 1)
(x + 1,     y)
(x + p,     y + 1)
(x + p - 1, y + 1)
(x - 1,     y)
```

Each side owns 37 tactical unit slots. Slot count is not the number of map
cells.

---

## 15. Recovered economy fragments

`[BIN]` · **RECOVERED, PARTIAL**

Gold upkeep:

```text
base gold upkeep
+ three attachment upkeep deltas
+ percentage modifier 0x55
- flat modifier 0x36
clamp to zero
```

Gold and gem recruitment costs follow parallel pipelines:

```text
base price
-> ruler modifier
-> strategic-resource surcharge
-> route/distance class
-> +10% per distance step beyond the first
```

Province gold and gem income include population/development tier, active site
modifiers, ruler structure modifiers and stationed-army provider modifier
`0x3A`. Exact normalized formulas and golden vectors are still required.
