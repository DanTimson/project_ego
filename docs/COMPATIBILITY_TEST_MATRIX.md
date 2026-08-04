# Compatibility test matrix

This document defines tests before compatibility code is considered complete.
Expected values should be copied into executable fixtures rather than left only
in prose.

Status values:

- **READY** — enough evidence exists to write a deterministic golden test now.
- **NEEDS VECTOR** — rule is understood, but a concrete original-game example
  or exact PRNG sequence is still required.
- **NEEDS EXTRACTION** — an existing dispatcher/loader must be classified first.
- **BLOCKED** — depends on an unresolved open question.

| ID | subsystem | test | evidence | expected assertions | status |
|---|---|---|---|---|---|
| RNG-LEGACY-001 | RNG | bounded helper with bounds 0, 1, 10, 30000 and >30000 | `00454C70` | result range, decimal extension, modulo behaviour, call count | NEEDS VECTOR |
| RNG-WEIGHT-001 | RNG | weighted selection and removal by selected value | `00454E80` | cumulative interval, duplicate-value removal, unchanged values | READY except exact roll sequence |
| RNG-WEIGHT-002 | RNG | total weight zero | open question 6b | explicit legacy behaviour | BLOCKED |
| XP-LEVEL-001 | progression | coefficient 100 thresholds for levels 1..5 | `00432660` | 20, 50, 90, 140, 200; cap 30 | READY |
| XP-ROUND-001 | progression | compare cumulative and per-term threshold helpers | `00432480`, `00432570`, `00432660` | preserve differing truncation where coefficients expose it | READY |
| LEVELUP-SELECT-001 | progression | prerequisites, repeated candidates and levels 21..30 | `00432B60` | candidate pool and weights before roll | READY |
| LEVELUP-APPLY-001 | progression | ordinary max-life increase | `00433130` | preserve absolute missing life, not percentage | READY |
| LEVELUP-TRANSFORM-001 | progression | first modifier ID `0x3E` | `00433130` | XP halved, definition replaced, level recalculated, tail cleared | READY |
| DAMAGE-BASE-001 | damage | raw power 1..20 versus defence gaps 0..11 | `004CEC40` | spread, clamp, exact/one/zero damage branches | READY except PRNG sequence |
| STATS-WOUND-001 | stats | life below half maximum | effective stat functions | 50% offensive penalty unless exempting modifier applies | READY |
| STATS-STAMINA-001 | stats | stamina 0..6 | effective stat functions | −10% per missing point below 6 | READY |
| STATS-MORALE-001 | stats | morale 0..15 | `004D0A70` effective stat functions + published table | multiplier `0.4 + 0.1*morale` for 0..5, exactly `1.0` for 6..15; both sources agree at every point | READY |
| STATS-MORALE-002 | stats | high-morale breakpoints | published table; binary confirms 5% step size only | band `n` starts at `15 + n(n+1)/2`, multiplier `1.0 + 0.05n` (16-17 → 1.05 … 43-50 → 1.35) | NEEDS VECTOR for the Genesis build |
| MELEE-ORDER-001 | combat | ordinary attack without retaliation | `004DCD90` | secondary effects before channel accounting and life subtraction | READY |
| MELEE-FIRST-001 | combat | defender modifier `0x10` | `004DCD90` | defender attacks first when all gating conditions pass | READY |
| MELEE-NORETAL-001 | combat | attacker modifier `0x1A` | `004DCD90` | suppresses both first-strike and ordinary retaliation paths | READY |
| CHARGE-001 | combat | modifier `0x25` at coordinate distances | `004DCD90` | `max(abs(dx)+abs(dy)-2,0)` contribution | READY for binary rule |
| CHARGE-002 | combat | compare coordinate rule with cumulative movement observation | open question 10 | identify build/context difference | BLOCKED |
| RANGED-EXEC-001 | combat | one and two shots | `004D7050` | cap by ammo, one ammo per shot, break on kill | READY |
| RANGED-STAMINA-001 | combat | no prior expenditure versus prior expenditure | `004D7050` | base stamina cost 1 versus 2; modifier `0x12` blocks | READY |
| RANGED-SPECIAL-001 | combat | modifiers `0x2E` and `0x2F` | `004D7050` | ordinary damage replaced by disabling runtime packages | READY |
| DAMAGE-SINK-001 | damage | all four received-damage channels | `004D61E0` | correct counter increment and life loss | READY |
| DAMAGE-MORALE-001 | morale | 25% max-life hit, damage 10, channel 3 | `004D61E0` | large-hit reaction except channel 3 | READY |
| STATUS-NODE-001 | runtime effects | head insertion and links | `004CEC00` | next/previous, source pointers and flags initialized | READY |
| STATUS-REMOVE-001 | runtime effects | remove-on-damage list mutation | `004D61E0` | flagged nodes unlinked/freed before life subtraction | READY |
| DEATH-REVIVE-001 | death | runtime effect `0x4A` | `004D1D30` | full life, runtime list cleared, record remains active | READY |
| DEATH-REVERT-001 | death | runtime effect `0x5A` | `004D1D30` | restore backup instance and clamp resources | READY |
| DEATH-REPLACE-001 | death | runtime effect `0x5B`, tiers 1..4 | `004D1D30` | replacement definition IDs and strategic slot update | READY |
| CONTROL-TRANSFER-001 | control | runtime/action effect `0x49`/73 | `004D1BF0` | side toggled, destination record copied, source cleared | READY mechanically |
| GRID-ADJ-001 | battlefield | every border/parity case | `004CE9E0` | exact six odd-row neighbours and no duplicates | READY |
| FORMATION-001 | battlefield | mirrored deployment | `004E4660` | side 1 uses `7 - formation_x`; collision writes back | READY |
| ACTION-DISPATCH-001 | battle actions | all observed effect IDs | `004D7A20~`, `spell.var` | per-case fields, resistance, runtime/immediate result | NEEDS EXTRACTION |
| VAR-LEXER-001 | parser | `:`, `;`, `#`, sign and EOF cases | parser helpers | token boundaries, consumed delimiter, integer sign | READY |
| ECON-UPKEEP-001 | economy | base, attachments, percent, flat and clamp | `00432E60` | exact integer ordering | READY |
| ECON-RECRUIT-001 | economy | route classes and resource surcharge | recruitment functions | exact gold/gem vectors | NEEDS VECTOR |
| ECON-PROVINCE-001 | economy | population, sites, ruler and army providers | province income functions | exact gold/gem vectors | NEEDS EXTRACTION |
| LAYOUT-UNIT-001 | runtime layout | persistent unit instance size and field offsets | `004331F0` | `0xA4` total; 30 level-upgrade IDs; three attachment IDs; `hero_state` present | READY |
| MOD-INSTANCE-001 | modifiers | persistent instance contribution | `00432950` | selected upgrades, attachments and personal hero contributions all summed | READY |
| MOD-AURA-001 | modifiers | commander aura channel is distinct from personal hero modifiers | `004A2690` | aura contribution does not enter the personal channel and vice versa | READY |
| DAMAGE-MELEE-001 | damage | ordinary attack and counterattack calculation | `004D2E60` | custom register storage; modifier-specific branches; integer ordering preserved | READY except PRNG sequence |
| DAMAGE-RANGED-001 | damage | ranged damage against ranged defence versus resistance | `004D2DA0` | correct defence selection; modifier-dependent branches | READY except PRNG sequence |
| MELEE-SECONDARY-001 | combat | melee hit secondary effects | `004D9800` | drains, debuffs, triggered actions, adjacent attacks, damage-proportional effects | NEEDS EXTRACTION |
| MORALE-ADJUST-001 | morale | morale adjustment and break accumulator | `004D0A70` | modifier `0x13` blocks adjustment; underflow raises break accumulator in ten-point steps and clamps | READY |
| DEATH-LIFECYCLE-001 | death | full death lifecycle in one pass | `004D1D30` | adjacent morale, revival, transformation rollback, replacement, persistent/battle-owned split | READY |
