# OBS-R17 — melee-secondary interaction preflight

Status: **ready for controlled observation**  
Source: `DOC-EADOROPEDIA-NH-26.0620-F01`  
Request: reduced R17 cells only  
Binary extraction authorized: **no**, unless a completed case remains materially
ambiguous

## 1. Method

Use a deterministic or repeatable tactical setup where possible. Restore the
same save before each comparison. Record:

- build and content version;
- attacker and defender names/levels;
- public abilities active on each;
- life, stamina, ammunition, morale and relevant defences before and after;
- exact command sequence;
- retaliation and follow-up order;
- screenshots or video.

Do not combine several unresolved abilities in one subject unless the case
explicitly requires their interaction.

## 2. M17-A — zero-damage trigger matrix

Create a hit that resolves to zero ordinary damage against a high-defence target.

Run separate attackers with:

- `Оглушающий удар` as the public control;
- `Ядовитая атака`;
- `Повреждение брони`;
- `Устрашение`;
- `Корни`;
- `Повреждение ауры`.

Record each resulting drain/status.

The control is explicit: `Оглушающий удар` should still drain its documented
smaller zero-damage amount. The other rows distinguish attack/hit triggers from
positive-damage triggers.

## 3. M17-B — `Острое оружие` threshold timing

Set the target just above half maximum life before the hit and below half after
the hit.

Record whether bleeding is created with the short or long duration.

- short duration supports a pre-hit life check;
- long duration supports a post-hit life check.

Repeat once with regeneration to confirm the public duration-halving rule.

## 4. M17-C — `Настороженность` current-hit scope

Use a defender with `Настороженность` and two attackers acting in the same turn.

Record defence:

1. before the first hit;
2. during/after the first hit if visible;
3. before the second hit.

Compare first- and second-hit damage under controlled attack rolls if possible.

The case determines whether the defence increase protects against the triggering
hit or only subsequent hits.

## 5. M17-D — `Двойной удар`

Use a target guaranteed to survive the first hit.

Record the exact order:

```text
first hit
retaliation?
second hit
retaliation?
```

Also record whether ordinary on-hit effects fire on the second hit.

Repeat with a target killed by the first hit as a control; the public description
requires no second hit when the target is dead.

## 6. M17-E — follow-up pack/centaur attacks

Run `Волчья стая` and `Сила в единстве` separately.

Record:

- whether the root attacker retaliates before follow-ups begin;
- whether follow-ups occur when the root attacker dies to retaliation;
- whether target death stops later followers;
- follower order;
- stamina payment for centaur follow-ups.

## 7. M17-F — additional magical damage

Use `Зачарованный клинок` against a target whose physical defence absorbs the
ordinary hit but whose resistance allows positive magical damage.

Record:

- life changes by component if visible;
- whether positive-damage abilities such as `Кровопийца` or a wound-triggered
  status activate;
- whether death is attributed before or after the magical component;
- retaliation when the magical component kills.

This case is profile-sensitive and should be run without unrelated on-hit
abilities first, then with exactly one damage-based trigger.

## 8. M17-G — `Затаптывание`

Set target life so the ordinary hit leaves it alive but at or below the public
threshold.

Record:

- whether trample kills immediately;
- whether retaliation occurs;
- when the attacker occupies the target tile;
- behaviour against a flying or large control target.

## 9. M17-H — `Смертельное касание`

Use an eligible living target and an attacker with an available charge.

Record:

- whether ordinary damage is displayed or accumulated;
- whether ordinary on-hit effects occur;
- whether the target retaliates;
- whether charge is consumed on an excluded or invalid target;
- kill rewards and corpse creation.

The result determines whether instant death replaces the ordinary chain or is a
secondary stage within it.

## 10. Submission

Enter results in `OBS-R17-MELEE-SECONDARY.csv`.

A case marked `NOT_REACHABLE` must explain why. Only a specific unreachable
non-commutative cell may generate a later binary request.
