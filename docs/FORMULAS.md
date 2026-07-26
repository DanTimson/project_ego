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
| `[OBS]` | Established by play observation |
| `[ASSUMED]` | Our reading, not confirmed — see `OPEN_QUESTIONS.md` |

**Verification status**

| tag | meaning |
|---|---|
| `VERIFIED` | Implemented and checked against a published table by `test_combat.py` |
| `STATED` | Documented but with no table to check against |
| `OPEN` | Value or behaviour still unknown |

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

### 1.1 The morale carve-out

`[GM] Боевой дух` · **STATED**

Morale multiplies only *direct* attack bonuses — those visible on the unit panel
during battle (commander auras, spell effects). It does **not** multiply
conditional damage such as `Сокрушение зла`.

*«Боевой дух не увеличивает урон от Сокрушения зла и подобных эффектов, только
прямые бонусы на атаки.»*

So the additive stack is partitioned: part of it sits inside the multiplier
chain, part outside. Whether stamina and wound multipliers also skip the
conditional part is **not stated** — we currently apply conditional bonuses
after all three. `[ASSUMED]`, `OPEN_QUESTIONS` item 7.

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

Suppressed by `Неутомимый` (undead, mechanisms, some hero artefacts), which
never loses stamina for any action at all.

### 1.4 MoraleMod

`[GM] Боевой дух` · **OPEN**

The mechanism is documented; the numbers are deliberately withheld —
*«точные цифры не разглашаются»*. `combat.py` carries a linear placeholder.

Cheap to close and it does **not** require combat: the map panel shows attack
*without* morale, the battle panel *with* it, so the ratio between the two
screens is the multiplier. Fix a unit, vary morale, read both. ~1 hour.

---

## 2. Attack randomisation

`[GM] Расчёт урона при атаках` · **VERIFIED**

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

`[GM] Расчёт урона при атаках` · **VERIFIED**

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

**The "moved" discriminator is `steps_this_round > 0`, not a position
comparison.** `[OBS]` Starting and ending the round on the same hex still
counts as having moved.

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

`[OBS]` · **STATED**

**Attack commands carry an implicit movement component.** Issuing an attack
against a reachable target auto-paths the unit into position; the player does
not move and then attack as two separate commands. Auto-path movement draws
from the same action-point pool.

Activation is free and re-entrant: a unit may spend part of its movement, yield
control, and be reselected later in the same round to finish acting. There is
no initiative queue within a side.

Consequences for state:
- `steps_this_round` is **cumulative path length**, not displacement. A
  4-movement cavalry pacing back and forth between two hexes accrues 4.
- `Атака с разгона` reads that counter directly (`+N damage per tile`).
- The stamina −2/−1 discriminator reads `steps_this_round > 0`.
- `Удар и возврат` returns to the tile where **the attack command was issued**,
  not the round-start tile. Move 2, then command an attack 2 tiles further: the
  unit paths out, strikes, and lands on the middle tile. The anchor belongs on
  the command, not on the unit.
- "В начале хода" effects fire once per **round**, not per activation —
  otherwise a player could farm them by yielding and reselecting.

Charge is therefore farmable by shuffling in place. That is original behaviour;
whether to preserve it is a design call, `OPEN_QUESTIONS` item 14.

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