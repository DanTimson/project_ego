# Public action-semantics and melee-secondary audit

Status: **public-source reduction complete; observation cells open**  
Source snapshot: `DOC-EADOROPEDIA-NH-26.0620-F01`  
Binary extraction authorized: **none**

## 1. Scope separation

Three mechanically different surfaces were previously at risk of being grouped
under one “action dispatcher” objective.

### 1.1 Explicit unit actions

The supplied NH 26.0620.f01 Eadoropedia snapshot contains exactly fourteen
ability descriptions using the explicit special-action formulation that the
current `Action` model uses as its catalogue boundary.

They are recorded in `UNIT_ACTION_COVERAGE.csv`.

The current Python/GDScript model already represents:

- action identity and public name;
- actor-side stamina/ammunition/action costs;
- coarse target category;
- attack-replacement flags;
- public suppression/scaling relationships;
- actor-only availability and payment.

It does not yet execute those actions against battlefield state.

### 1.2 Generic battle-action effects

Spells, unit spells and other data-driven battle actions expose observable effect
families such as direct damage, restoration, timed modifiers, dispelling,
summoning, teleportation, resurrection, transformation, control and extra-turn
granting.

Those families are recorded in `BATTLE_ACTION_FAMILY_COVERAGE.csv`.

A clean implementation needs:

- target and tile legality;
- effect-family inputs and outputs;
- resistance/immunity rules;
- duration and stacking policy;
- state transition order where order changes results.

It does not need Genesis's eight-clause jump-table shape, numeric switch grouping
or handler decomposition. R16 therefore remains retired.

### 1.3 Melee secondary effects

Passive attack, damage, kill and defender-reactive abilities are a separate
event-order problem. Their public trigger language already distinguishes:

- attack/hit triggers;
- explicit zero-damage behaviour;
- positive-damage or wound triggers;
- kill triggers;
- defender-reactive triggers;
- follow-up attacks;
- attack replacements that suppress the ordinary chain.

These are recorded in `MELEE_SECONDARY_COVERAGE.csv`.

## 2. Unit-action result

All fourteen public action names currently appear in the repository action
catalogue. This supports catalogue completeness for the supplied NH snapshot,
not complete battle execution.

The basic semantics divide as follows.

### Public specification is sufficient for the main effect

- `Удар щитом`;
- `Бешенство`;
- `Марш-бросок`;
- `Снайперский выстрел`;
- `Целительство` target/exclusion rules;
- `Трупоед` target and Ratman action-cost exception.

### Existing archived evidence should be reduced before any new extraction

- `Дополнительный выстрел`: the archived ranged executor already contains the
  two-shot loop and resource lifecycle;
- `Сокрушающий удар`: R10 settles the melee 1.5× placement;
- `Мощный выстрел`: review the archived ranged executor/calculator before asking
  for another packet;
- `Круговая атака`: reduce only per-target order and recursive-secondary policy.

### Public or black-box edge remains

- healing/repair/ammunition/corpse-consumption random distributions;
- the second public magnitude of `Глухая оборона`;
- repair's exact duration reduction;
- `Удар и возврат` anchor lifetime, already covered by R12.

## 3. Battle-action family result

The public corpus already demonstrates the observable need for at least the
following families:

1. single-target physical or magical damage;
2. stamina, morale and ammunition mutation;
3. immediate life/resource restoration;
4. timed scalar buffs and debuffs;
5. remove-on-damage statuses;
6. immobilization with defensive side effects;
7. healing plus status cleanup;
8. duration reduction and dispelling;
9. adjacent or corpse-based summoning;
10. area effects;
11. teleportation;
12. resurrection;
13. temporary transformation;
14. side control;
15. extra-turn grants;
16. instant death;
17. caster self-cost or sacrifice;
18. compound effects that combine several families.

The family matrix is intentionally address-free. Exact effect-opcode mappings
remain a data-dictionary task only when an implemented content record needs
them.

## 4. Melee-secondary result

Public wording settles many trigger classes without binary inspection.

### Explicitly zero-damage-aware

`Оглушающий удар` states a smaller stamina drain when the hit deals no damage.
This is a direct public control for zero-damage observations.

### Positive-damage or wound triggers

The public text explicitly ties these to wounding or dealt melee damage:

- `Сглаз`;
- `Кровопийца`;
- `Насылает уязвимость`;
- `Насылает чахотку`;
- successful `Удар в спину` morale gain.

These should not be generalized to every attempted attack.

### Kill triggers

The public text explicitly requires a kill for:

- `Похищение душ`;
- `Повелитель нежити`;
- `Кровавое безумие`;
- `Тёмное восполнение`;
- the kill component of `Жажда крови`.

### Attack replacements

`Удар щитом` publicly suppresses ordinary damage, the normal on-hit chain and
retaliation. Its implementation must bypass rather than simulate the ordinary
secondary processor with zero damage.

### Follow-up attacks

`Волчья стая`, `Сила в единстве` and `Двойной удар` publicly require the root
attacker or target to remain alive in different combinations. Exact placement
relative to retaliation and death remains materially observable.

## 5. Existing binary mapping

The already documented Genesis processor gives strong working mappings:

| Genesis modifier | public semantic candidate |
|---|---|
| `0x28` | `Оглушающий удар` |
| `0x2C` | `Кража снарядов` |
| `0x41` / `0x42` | `Общая атака` / `Круговая атака` |
| `0x44` | `Кровопийца` |

The automatic action-trigger branches labelled `0x4F`/`0x50` do not map cleanly
to the same-numbered NH public ability names. Do not name them by numeric
coincidence. Resolve their source content through the data dictionary only when
a reachable content record requires them.

## 6. Remaining high-value observation cells

The preregistered packet
`observations/OBS-R17-MELEE-SECONDARY-PREFLIGHT.md` covers the smallest
non-commutative cells:

1. ambiguous zero-damage triggers;
2. `Острое оружие` half-life duration check before or after the hit;
3. whether `Настороженность` affects the current hit or only later hits;
4. retaliation placement within `Двойной удар`;
5. follow-up pack/centaur attack placement;
6. additional magical damage relative to death and damage-based triggers;
7. `Затаптывание` threshold, death and tile occupation;
8. `Смертельное касание` relative to the ordinary hit chain.

No broad binary packet is justified before these observations are attempted.

## 7. Implementation consequence

The next implementation artifact should be an event vocabulary and fixture
matrix, not a translation of `004D9800`.

A suitable neutral event vocabulary is:

```text
ATTACK_DECLARED
PRIMARY_DAMAGE_COMPUTED
PRIMARY_DAMAGE_POSITIVE
PRE_COMMIT_SECONDARY
PRIMARY_DAMAGE_COMMITTED
TARGET_DIED
RETALIATION_WINDOW
FOLLOW_UP_ATTACK
POST_KILL_REWARD
RETURN_OR_OCCUPY
```

The vocabulary is a Project EGO architecture proposal. The public/binary evidence
constrains ordering outcomes but does not require these exact event names or one
monolithic processor.
