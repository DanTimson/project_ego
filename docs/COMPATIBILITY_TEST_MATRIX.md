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
- **PARTIAL** — an executable subset exists, but some listed assertions or lifecycle integration remain incomplete.
- **IMPLEMENTED** — an executable deterministic fixture covers the complete row.

| ID | subsystem | test | evidence | expected assertions | status |
|---|---|---|---|---|---|
| RNG-LEGACY-001 | RNG | raw MSVC sequence plus bounded helper at 0, 1, 10, 30000, 30001, 300000 and 3000001 | `EXP-R4A-001`, `EXP-R4B-001`, `LEGACY_RNG.md`; `tests/test_legacy_rng.gd` | exact values, uint32 wrap, modulo bias and CRT call count | IMPLEMENTED (isolated fixture) |
| RNG-STATE-001 | RNG | seed 0, 1 and 111 raw sequences | `00404B0B`, linked CRT `_rand`, `LEGACY_RNG.md`; `tests/test_legacy_rng.gd` | seed assignment and first eight 15-bit outputs | IMPLEMENTED (isolated fixture) |
| RNG-TOPOLOGY-001 | RNG | interleave direct rand, bounded and weighted consumers; call contextual selectors | `EXP-R4A-001`, `EXP-R4B-001`; `tests/test_legacy_rng.gd` | ordinary stream labels share one state; contextual selectors are non-CRT paths | PARTIAL — shared-state boundary passes; contextual/combat integration pending |
| RNG-SEED-001 | RNG | startup, map generation and two consecutive strategic turns | `EXP-R2-001`, `EXP-R4B-001`, `EXP-STRATEGIC-TICK-001`; `tests/test_legacy_rng.gd` | seeds are time%10000, map seed/default 111, and map_seed+turn | PARTIAL — map/turn epochs pass; startup/setup/menu/battle wiring incomplete |
| RNG-WEIGHT-001 | RNG | weighted selection and removal by selected value | `00454E80`, `LEGACY_RNG.md`; `tests/test_legacy_rng.gd` | cumulative interval, duplicate-value removal and exact seeded roll | IMPLEMENTED (isolated fixture) |
| RNG-WEIGHT-002 | RNG | total weight zero | open question 6b | explicit legacy behaviour | BLOCKED |
| TURN-STRUCTURE-001 | turn structure | two or more eligible units per side; partial action, reselection, explicit side pass and automatic exhaustion | `EXP-R7-001`; `004EC4C0`, `004E6530` | initiative chooses the first side; ordinary unit commands keep control on that side; any eligible current-side unit may be selected; explicit pass or no remaining eligible unit toggles the side exactly once | READY |
| XP-LEVEL-001 | progression | coefficient 100 thresholds for levels 1..5 | `00432660` | 20, 50, 90, 140, 200; cap 30 | READY |
| XP-ROUND-001 | progression | compare cumulative and per-term threshold helpers | `00432480`, `00432570`, `00432660` | preserve differing truncation where coefficients expose it | READY |
| LEVELUP-SELECT-001 | progression | prerequisites, repeated candidates and levels 21..30 | `00432B60` | candidate pool and weights before roll | READY |
| LEVELUP-APPLY-001 | progression | ordinary max-life increase | `00433130` | preserve absolute missing life, not percentage | READY |
| LEVELUP-TRANSFORM-001 | progression | first modifier ID `0x3E` | `00433130` | XP halved, definition replaced, level recalculated, tail cleared | READY |
| DAMAGE-BASE-001 | damage | raw power 1..20 versus defence gaps 0..11 | `004CEC40` | spread, clamp, exact/one/zero damage branches | READY |
| STATS-WOUND-001 | stats | life below half maximum | effective stat functions | 50% offensive penalty unless exempting modifier applies | READY |
| STATS-STAMINA-001 | stats | stamina 0..6 | effective stat functions | −10% per missing point below 6 | READY |
| STAMINA-IMMUNITY-001 | stamina | effective modifier `0x12` across movement, melee, ranged, action-definition costs, on-hit drains, scripted reductions, phase effect `0x0B`, AI scoring and selection availability | `EXP-R11-001`; `EXP-R11B-001`; `004D01C0` consumers | every recovered downward tactical `+0x10` mutation is skipped; signed effect `0x0B` restoration is also skipped; effective-stat penalties remain driven by live stamina | READY |
| STATS-DEFENCE-001 | stats | ordinary and ranged accumulated defence −1, 0, 1, 2, 3 and 7 at stamina nonzero and stamina 0 | `EXP-R9-001`; `004D0820`, `004D06B0` | nonzero stamina: `max(value,0)`; stamina 0: `max(trunc0(value/2),0)`; paired outputs are 0/0, 0/0, 1/0, 2/1, 3/1 and 7/3; all providers precede halving | READY |
| STATS-MORALE-001 | stats | morale 0..15 | effective attack stat functions + `DOC-NH-MORALE`; `EXP-R5-001`; `oracle/test_morale_binary.py` | low-band percentage is `10*morale-60`; neutral band is zero; pre-morale truncation and signed adjustment truncation match the executable | IMPLEMENTED |
| STATS-MORALE-002 | stats | high-morale breakpoints and integer application | `EXP-R1-001`; `DOC-NH-MORALE`; `oracle/test_morale_binary.py` | band `n` starts at `15 + n(n+1)/2`; +5 percentage points per band; first boundaries 16/18/21; truncate the pre-morale stat before applying the bonus | IMPLEMENTED |
| STATS-MORALE-003 | stats | negative morale bonus with pre-morale attack not divisible by 10 | `EXP-R5-001`; `oracle/test_morale_binary.py` | `pre + trunc0((10*morale-60)*pre/100)`, then clamp to 1; base 19/morale 0 is 8 and base 7/morale 0 is 3 | IMPLEMENTED |
| STATS-ATTACK-ZERO-001 | stats | zero effective attack entry paths | `EXP-R5-001`; `004D1890`, `004D1660`, `004D14A0` | attack/counterattack: modifier `0x26` returns 0, otherwise zero accumulated stat reaches minimum-one clamp; ranged: zero definition+instance+intrinsic sum returns 0 before later providers and final clamp | PARTIAL — melee/counterattack behaviour exists; ranged early-zero guard and corrected fixture pending |
| MELEE-ORDER-001 | combat | ordinary attack without retaliation | `004DCD90` | secondary effects before channel accounting and life subtraction | READY |
| MELEE-FIRST-001 | combat | defender modifier `0x10` | `004DCD90` | defender attacks first when all gating conditions pass | READY |
| MELEE-NORETAL-001 | combat | attacker modifier `0x1A` | `004DCD90` | suppresses both first-strike and ordinary retaliation paths | READY |
| CHARGE-001 | combat | modifier `0x25` with and without command movement | `EXP-CI11`, `004DCD90` | when movement is requested, compute `max(abs(current_attacker_x-target_x)+abs(current_attacker_y-target_y)-2,0)` before moving; no-movement attack leaves zero | READY |
| CHARGE-002 | combat | split activation, earlier movement and backtracking | `EXP-CI11`, `004DCD90` | recompute from the tile occupied when the attack command starts; prior path length is not accumulated; cumulative `steps_this_round` is non-legacy | READY |
| RANGED-EXEC-001 | combat | one and two shots | `004D7050` | cap by ammo, one ammo per shot, break on kill | READY |
| RANGED-STAMINA-001 | combat | capacity equal/above effective speed, capacity below it, move→restore→reselect→attack | `EXP-R8A-001`..`EXP-R8E-001`; `004D0560`, `004D7050`, `004E0280` | base cost 1 when `remaining_capacity >= effective_speed`, otherwise 2; modifier `0x12` blocks; reselection preserves capacity | READY — current `steps_this_round` model diverges |
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
| VAR-REFERENCE-001 | content references | distinguish unit ability indexes from direct item/medal/spell effect opcodes | `EXP-R2-001`; full Genesis var collection | unit Abilityes index 1 resolves through unit_upg; item effect 2 is Attack rather than unit_upg[2]; medal effect 12 is Morale rather than unit_upg[12]; spell effect 1 dispatches directly | READY |
| LAYOUT-MEDAL-001 | runtime layout | persistent medal slots and medal table stride | `0045EF60`, `00432950`, `medal.var` | +0x94/+0x98/+0x9C are three medal record indexes; record stride 0x88 | READY |
| VAR-LEXER-001 | parser | `:`, `;`, `#`, sign and EOF cases | parser helpers | token boundaries, consumed delimiter, integer sign | READY |
| ECON-UPKEEP-001 | economy | base, attachments, percent, flat and clamp | `00432E60` | exact integer ordering | READY |
| ECON-RECRUIT-001 | economy | route classes and resource surcharge | recruitment functions | exact gold/gem vectors | NEEDS VECTOR |
| ECON-PROVINCE-001 | economy | population, sites, ruler and army providers | province income functions | exact gold/gem vectors | NEEDS EXTRACTION |
| LAYOUT-UNIT-001 | runtime layout | persistent unit instance size and field offsets | `004331F0` | `0xA4` total; 30 level-upgrade IDs; three attachment IDs; `hero_state` present | READY |
| MOD-INSTANCE-001 | modifiers | persistent instance contribution | `00432950` | selected upgrades, attachments and personal hero contributions all summed | READY |
| MOD-AURA-001 | modifiers | commander aura channel is distinct from personal hero modifiers | `004A2690` | aura contribution does not enter the personal channel and vice versa | READY |
| DAMAGE-MELEE-001 | damage | ordinary attack and counterattack calculation | `004D2E60` | custom register storage; modifier-specific branches; integer ordering preserved | READY |
| DAMAGE-RANGED-001 | damage | ranged damage against ranged defence versus resistance | `004D2DA0` | correct defence selection; modifier-dependent branches | READY |
| MELEE-SECONDARY-001 | combat | melee hit secondary effects | `004D9800` | drains, debuffs, triggered actions, adjacent attacks, damage-proportional effects | NEEDS EXTRACTION |
| MORALE-ADJUST-001 | morale | morale adjustment and break accumulator | `004D0A70` | modifier `0x13` blocks adjustment; underflow raises break accumulator in ten-point steps and clamps | READY |
| DEATH-LIFECYCLE-001 | death | full death lifecycle in one pass | `004D1D30` | adjacent morale, revival, transformation rollback, replacement, persistent/battle-owned split | READY |
