# Open requests to binary analysis

Requests from the implementation side (`oracle/`, `core/`) to the Ghidra side.
Format follows the request template in `GHIDRA_WORKFLOW.md`. Each item names what
would falsify the current hypothesis, so a packet can close it rather than merely
add detail.

Priority order below is by *what unblocks implementation*, which is not the same
as what is most interesting in the binary.

**Current active request:** R11 — modifier `0x12` (`Неутомимый`) consumer list. R1–R9 are closed.

---

## R1 — CLOSED: high-morale branch confirmed the preregistered prediction

**Closes:** `OPEN_QUESTIONS` item 1 · `COMPATIBILITY_TEST_MATRIX` STATS-MORALE-002
**Ledger:** MORALE-001 (`004D0A70`) and the effective-attack stat functions

**Result (2026-08-04).** `EXP-R1-001` confirms the prediction in all three
offensive-stat functions (`004D1890`, `004D1660`, `004D14A0`):

- first boundaries: `16`, `18`, `21`;
- continuation: `25`, `30`, `36`, `43`, `51`, `60`, ...;
- increment: exactly five percentage points per band;
- attack, counterattack and ranged attack use the same loop;
- arithmetic is integer: the internal ×100 value is truncated back to an
  integer before the morale bonus is applied.

The result independently agrees with `DOC-NH-MORALE`. Rejected alternatives:
fixed five-point bands, fixed two-point bands, and float application through the
complete pipeline. Matrix implementation remains with the engine side.

**Question.** Above morale 15, what are the exact band boundaries and multipliers
in the effective attack / counterattack / ranged-attack path?

**Why this one first.** It is the only open item where the implementation side can
state a complete falsifiable prediction in advance, so a single packet either
closes it outright or produces a large architectural consequence. It is also
already implemented, so a mismatch is immediately visible as a test failure
rather than a silent divergence.

**Current state.** Morale 0..15 is settled and needs no further work. The binary's
"−10% per missing point below morale 6" and the published table's
`0.4 + 0.1 * morale` are the same function at every point:

```text
morale   0     1     2     3     4     5     6..15
mult    0.40  0.50  0.60  0.70  0.80  0.90  1.00
```

Two independent sources, two different builds, exact agreement. Do not spend
packet budget re-deriving this range.

**Prediction to test.** Above 15 both sources agree the step is 5%. The band
*widths* come only from NH 26.0620.f01 documentation and are implemented as
band `n` starting at `15 + n(n+1)/2`, multiplier `1.0 + 0.05n`:

| morale | 15 | 16 | 17 | 18 | 20 | 21 | 24 | 25 | 29 | 30 | 35 | 36 | 42 | 43 | 50 | 51 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| predicted | 1.00 | 1.05 | 1.05 | 1.10 | 1.10 | 1.15 | 1.15 | 1.20 | 1.20 | 1.25 | 1.25 | 1.30 | 1.30 | 1.35 | 1.35 | 1.40 |

**Minimum sufficient answer.** The first three boundaries — that the multiplier
steps at 16, again at 18, and again at 21. That alone distinguishes the
triangular-widening rule from the obvious alternatives (fixed 5-point bands would
step at 16/21/26; fixed 2-point bands at 16/18/20).

**What would falsify it.** Any step at a morale value not in {16, 18, 21, 25, 30,
36, 43, 51}, or a step size other than 5%.

**Consequence if falsified.** Genesis and New Horizons have different morale
curves, which means the published table cannot be used as evidence for Genesis
anywhere, and the two builds need separate content profiles rather than one
ruleset with different data. That is a large enough architectural fork to be
worth knowing early.

**Also useful, if cheap.** Whether the multiplier is applied as float or as
integer arithmetic, and where truncation lands. The implementation currently uses
float; ordering matters for parity.

---

## R2 — CLOSED: `Effects` use direct opcodes, not `unit_upg` indexes

**Closes:** the remaining half of the extraction→roster reference typing
**Ledger:** new claim required
**Blocks:** wiring spells and items into the rules pipeline at all

**Result (2026-08-04).** The three tables use direct numeric effect identifiers,
not `unit_upg` record indexes:

```text
unit.var Abilityes
    -> unit_upg record index

item.var Effects
medal.var Effects
spell.var Effects
    -> direct effect/modifier opcode
       in the namespace described by ability_num.Number
```

The runtime generally does not perform a second lookup through `ability_num`.
It stores the integer and compares or dispatches it directly. `ability_num.var`
is therefore a descriptor dictionary for the opcode namespace, not a required
runtime indirection table.

Decisive consumers:

- `004A1F90` compares item effect IDs directly with the requested modifier ID;
- `00432950` indexes a `0x88` medal record and compares its effect IDs directly;
- `apply_battle_action_to_unit_candidate` switches on spell effect IDs and
  passes ordinary IDs directly into runtime modifier nodes;
- the contrasting `unit.var Abilityes` path multiplies its value by the
  `unit_upg` stride `0x58`.

Rejected alternatives:

- `Effects` values are `unit_upg` record indexes;
- `Effects` values are physical record indexes into `ability_num.var`;
- localized labels such as `Жизнь +2` are mechanical identities.

The source-format result does not prescribe Project EGO's runtime model. Import
should normalize source references into explicit effect/magnitude records while
retaining source provenance. See `CONTENT_REFERENCE_MODEL.md`.

**Question.** For `item.var`, `spell.var` and `medal.var`, does the `Effects`
block reference `ability_num` **by `Number`**, or `unit_upg` **by record index**?
And is the answer the same for all three tables?

**Why this matters more than it looks.** `unit.var`'s `Abilityes` block references
`unit_upg` by *index*, while `Effects` is documented in `core/content/roster.gd`
as referencing `ability_num` by *Number*. Both are dense integer spaces starting
near zero. Resolving against the wrong one does not throw — it silently returns a
different, entirely plausible ability, and every cross-reference integrity check
still reports zero dangling references.

This is not hypothetical. The unit-side extractor was recently fixed after
exactly this failure: a heuristic that identified ability references by excluding
known stat fields misclassified Genesis's `Race` and `UnitKind` metadata as
ability references. Both resolve to `unit_upg[1]` = «Жизнь +1», so `xref` reported
zero dangling references while every Genesis unit silently gained two phantom
abilities. It was caught only because real Genesis data was run through it; the
NH corpus does not contain those fields. The fix was to stop inferring and read
the structure positionally.

The same trap is waiting on the `Effects` side and cannot be resolved from the
data alone, because a wrong answer looks correct.

**Preferred evidence.** The startup loader or the effect-application consumer,
showing which table the integer indexes and whether the lookup is by array offset
or by a `Number` field search. A single unambiguous call site per table is
enough.

**What to include.** The `.var` records for one item, one spell and one medal that
carry `Effects`, CP1251-decoded, alongside the resolving code.

---

## R3 — CLOSED: charge uses command-entry coordinates, not accumulated movement

**Closes:** `OPEN_QUESTIONS` item 10 · matrix CHARGE-002
**Ledger:** existing, `004DCD90` modifier `0x25`

**Result.** `004DCD90` settles the ordering unambiguously.

At function entry:

```text
ECX       = destination_x
stack +4  = destination_y
stack +8  = target
global    = current attacker
```

The function first checks whether the requested destination already equals the
attacker's current `+0x44/+0x48` coordinates. When movement is required and the
attacker has modifier `0x25`, it computes:

```text
max(
    abs(attacker.current_x - target.current_x)
  + abs(attacker.current_y - target.current_y)
  - 2,
    0
)
```

Only after storing that value does it call `move_battle_unit_candidate` with the
requested destination coordinates. The calculation therefore reads the
attacker's actual current tile at the start of this attack command and the
target's current tile, before the command's approach movement.

Consequences:

- it is not cumulative `steps_this_round`;
- it is not the displacement to the selected destination tile;
- movement earlier in the round matters only insofar as it changed the
  attacker's current tile;
- moving away and back does not accumulate a larger legacy bonus;
- split activation recomputes from the tile occupied when the attack command is
  issued;
- a no-movement melee attack bypasses the charge calculation and leaves the
  bonus at zero.

The cumulative movement model may remain as an explicit Project EGO-native rule,
but it is not Genesis compatibility behaviour.

Already well specified in the open-questions entry; restated here only to place
it in priority order. The binary computes
`max(|attacker_x − target_x| + |attacker_y − target_y| − 2, 0)` before movement,
while the current model uses cumulative `steps_this_round`. These are different
rules, not different spellings of one rule.

**What the implementation side needs.** Not just which is correct, but whether the
coordinate operands are read before or after the movement for the current
command. That determines whether the existing accumulation model is wrong or
merely differently anchored, and it decides open question 14 (whether the
accumulation exploit is preserved as legacy behaviour or corrected).

---

## R4 — CLOSED: MSVC CRT state, shared topology and seed epochs

**Closes:** `OPEN_QUESTIONS` items 4 and 4b · matrix RNG-LEGACY-001
**Ledger:** RNG-001 through RNG-005
**Implementation handoff:** `LEGACY_RNG.md`

**Result (2026-08-04).**

`00404B0B` is the statically linked CRT `srand` implementation:

```c
__getptd()->_holdrand = seed;
```

The paired `_rand` symbol is the Microsoft CRT generator. The compatibility
target is the standard 32-bit recurrence:

```text
state = state * 214013 + 2531011       (mod 2^32)
value = (state >> 16) & 0x7fff
```

The state belongs to the calling thread's CRT data. On the ordinary game thread,
all direct `_rand()` calls, `00454C70`, and `00454E80` consume the same sequence.
Project EGO's named independent streams are therefore test conveniences or a
native rules mode, not exact Genesis compatibility behaviour.

`00454C70` keeps its original modulo bias and consumes a variable number of CRT
values for bounds above 30000. `00454E80` uses that helper for weighted
selection. By contrast, `00454DC0`, `00454F80`, and `00455050` do not call
`_rand`; they are contextual/deterministic selector paths, not independent
advancing PRNG streams.

Recovered seed boundaries include:

- startup/content initialization: `time64() % 10000`;
- map/setup initialization: stored map seed;
- map generation: map seed, with zero replaced by `111`;
- each global strategic tick: `map_seed + strategic_turn`;
- two menu/transition paths: a counter cycling through `1..10000`.

The `srand` XREF list also names a conditional battle-outcome path whose local
seed expression was not included completely enough in the supplied packet to
freeze safely. Save/load persistence of live `_holdrand` state is likewise not
established. Those residual boundaries do not block implementation of the
generator, shared topology, bounded adapter, weighted roller, or the recovered
principal reseed epochs.

Golden vectors, exact bounded-helper call counts, architecture constraints, and
the engine-agent handoff are in `LEGACY_RNG.md`.

---

## R5 — CLOSED: negative morale division truncates toward zero

**Closes:** `OPEN_QUESTIONS` item 17 · matrix STATS-MORALE-003
**Ledger:** MORALE-003
**Evidence:** `EXP-R5-001`

**Result (2026-08-04).** The complete listings for effective attack
(`004D1890`), counterattack (`004D1660`), and ranged attack (`004D14A0`) use the
same signed divide-by-100 sequence for both the pre-morale integer conversion
and the final morale adjustment.

For the final adjustment, the compiler emits signed multiplication by the
`0x51EB851F` reciprocal, arithmetic shift by five, and an explicit sign
correction:

```asm
imul EDX, ECX
mov  EAX, 0x51EB851F
imul EDX
sar  EDX, 5
mov  EAX, EDX
shr  EAX, 31
add  EAX, EDX
```

The correction converts arithmetic-shift flooring for negative non-integral
values into C-style signed division truncating toward zero.

The recovered rule is therefore:

```text
pre = trunc_toward_zero(internal_scaled_value / 100)

if morale < 6:
    bonus_percent = 10 * morale - 60
elif morale <= 15:
    bonus_percent = 0
else:
    bonus_percent = 5 * triangular_band_index(morale)

result = pre + trunc_toward_zero(bonus_percent * pre / 100)
result = max(result, 1)
```

Decisive examples:

```text
pre 19, morale 0:
    19 + trunc_toward_zero(-1140 / 100)
  = 19 - 11
  = 8

pre 7, morale 0:
    7 + trunc_toward_zero(-420 / 100)
  = 7 - 4
  = 3
```

Flooring would produce 7 and 2 respectively. A direct
`floor(pre * morale_multiplier)` is therefore not equivalent in the low-morale
bands.

Matching instruction ranges:

- attack: pre conversion `004D1995..004D19A7`, final signed percentage division
  `004D19D2..004D19E6`, clamp `004D19E8..004D19ED`;
- counterattack: pre conversion `004D1824..004D1833`, final division
  `004D185E..004D1874`, clamp `004D1876..004D187B`;
- ranged attack: pre conversion `004D15F6..004D1605`, final division
  `004D1630..004D1646`, clamp `004D1648..004D164D`.

The original's internal ×100 representation remains `diagnostic_only`; the
binding compatibility requirements are the two truncation points, signed
rounding direction, percentage construction, and final minimum-one clamp.

---

## R6 — CLOSED: zero melee/counterattack reaches the clamp; ranged attack has an earlier zero return

**Closes:** the last unresolved consequence of the R5 morale packet
**Ledger:** extends MORALE-001 / the effective-attack functions
**Cost:** small — resolved from the existing `EXP-R5-001` assembly packet

**Result (2026-08-05).** The three functions share a final minimum-one tail, but they do not share the same entry semantics.

Attack (`004D1890`) and counterattack (`004D1660`) first test modifier `0x26` and return zero when it is present:

```text
attack         004D1895..004D18A7
counterattack  004D1667..004D167B
```

Otherwise neither function has a zero-stat guard before its final clamp:

```text
attack clamp         004D19E8..004D19ED
counterattack clamp  004D1876..004D187B
```

Therefore a zero accumulated melee or counterattack value returns `1` if the function is called and modifier `0x26` is absent.

Ranged attack (`004D14A0`) differs. After adding only the definition base, instance modifiers and intrinsic modifiers, it branches at `004D14D2`. A zero sum returns immediately through `004D14D4..004D14D9`, before runtime-node modifiers, commander aura, wound/stamina processing, morale processing and the final clamp. Only the nonzero path reaches `004D1648..004D164D`.

This closes the effective-stat question without a new observation. It does not establish whether the tactical command layer offers melee to a ranged-only siege unit; command reachability remains separate.

**Implementation consequence.** A single unconditional clamp for all three attack kinds is not Genesis-compatible. Melee and counterattack retain the minimum-one result on the reached path, subject to modifier `0x26`; ranged attack needs the recovered early-zero guard.

**Question.** `FORMULAS.md` §1.4 now records the final line of all three
recovered effective-attack functions as

```text
result = max(1, pre_morale + trunc0(bonus_percent * pre_morale / 100))
```

Taken literally the clamp is unconditional, so a unit whose melee attack is 0
returns 1. Is that right, or is the clamp guarded — reached only when the unit
actually has an attack value, or only when a morale bonus is non-zero?

**Why it matters.** It is not an edge case in this corpus. **2 Genesis units and
22 New Horizons units carry `Attack 0`** — Баллиста, Катапульта, Гномья пушка
and the other siege engines, which are ranged-only. A base attack of 1 reduced by
the stamina-0 halving also truncates to 0 before the clamp. Under the literal
reading every one of those deals 1 melee damage rather than none, which is a
visible gameplay difference, not a rounding detail.

**Engine state at closure.** The engine currently applies the final clamp
uniformly across melee, counterattack and ranged attack. That matches the
reached melee/counterattack paths but not the ranged early-zero branch. The
engine side owns the implementation and fixture correction.

**Minimum sufficient answer.** Either the branch guarding that `max` in one of
`004D1890` / `004D1660` / `004D14A0`, or one controlled observation: put a
ballista adjacent to an enemy in the original and see whether a melee attack is
offered at all, and if so whether it deals 1.

**Note on scope.** If melee is simply never offered to those units, the clamp
question becomes unreachable in practice and the honest resolution is
`diagnostic_only` for that case rather than a behavioural change.

---

## R7 — CLOSED: tactical combat uses whole-side phases

**Closes:** `OPEN_QUESTIONS` item 16 · matrix TURN-STRUCTURE-001
**Ledger:** TURN-001
**Source:** `EXP-R7-001`
**Method:** decompilation and assembly cross-check
**Cost:** resolved from the existing `unit_calls_3.txt` export and canonical binary

**Result (2026-08-05).** Genesis does not alternate sides after each unit.
The battle scheduler holds one `g_current_battle_side` through the interaction
loop. Any eligible unit on that side may be selected and acted with; control
passes to the opponent only when the side explicitly ends its phase or has no
actionable unit left.

The controlling global is `DAT_0052E43C`, now named
`g_current_battle_side`. Battle setup writes the initiative-selected side at
`004EEE1C` or `004EEE2D`. The phase helper `004E6530` reads that global at
`004E6557`. When its first argument is nonzero, it performs the only ordinary
side transition:

```asm
004E66F9  MOV ECX,1
004E66FE  SUB ECX,EBX
004E6700  MOV EBX,ECX
004E6709  MOV [g_current_battle_side],EBX
```

The main tactical interaction loop in `004EC4C0` repeatedly indexes the
37-slot roster using the unchanged current side. A battlefield click scans
current-side slots and selects the matching unit at
`004F13C8..004F1453`. Ordinary movement, attack and action paths return to this
same loop; they do not call the side-transition helper.

The two normal calls that pass `(1,1)` to `004E6530` are:

- `004F2070..004F2077`: the explicit side-pass/end-phase input path;
- `004F20AE..004F214D`: the automatic path after scanning all 37 slots and
  finding no remaining selectable/actionable current-side unit.

Calls with a zero first argument do not execute the toggle branch and belong to
battle-control/exit handling rather than unit alternation.

**Compatibility rule.**

```text
choose initial side from army initiative
repeat until battle ends:
    current side may select and reselect its eligible units in any order
    ordinary unit commands do not transfer control
    explicit side pass, or exhaustion of all eligible units:
        current_side = 1 - current_side
        initialize the next side phase
```

**Pass semantics.** Pass is a side-level operation. A unit ending its own
action, being deselected, or retaining only part of its capacity does not yield
control to the opposing side. The already-observed within-side re-entry
behaviour is therefore consistent with the scheduler.

**Rejected alternative.** Unit-by-unit side alternation is incompatible with
both the side-global write topology and the absence of a transition-helper call
from ordinary unit command paths.

**Engine consequence.** The existing whole-side `RoundLoop` ordering is the
correct Genesis compatibility model. Preserve this ordering for the shared
legacy RNG: all random consumers from the current side's phase occur before the
opponent's phase begins.

**Residual scope.** This result does not settle whether a particular
start-of-turn effect fires at each side phase, once per complete two-side round,
or on unit activation. That remains R13.

---

## R8 — CLOSED: ranged stamina cost uses live capacity, not movement history

**Closes:** `OPEN_QUESTIONS` item 12 · matrix `RANGED-STAMINA-001`
**Ledger:** new `STAMINA-001`; extends `COMBAT-002` and `TURN-001`
**Evidence:** `EXP-R8A-001` through `EXP-R8E-001`
**Method:** complete decompilation/listing, write-XREF reduction and caller tracing

**Result (2026-08-05).** At `004D7953..004D797D`,
`execute_ranged_attack_candidate` passes the attacker in `EAX` to `004D0560`,
then compares the live tactical-unit field at `+0x04` with the returned effective
speed:

```text
effective_speed = get_effective_battle_speed_candidate(attacker)

if attacker.remaining_capacity < effective_speed:
    base_stamina_cost = 2
else:
    base_stamina_cost = 1
```

The branch is strict less-than. Equality and temporary over-capacity both select
cost 1. Modifier `0x12` suppresses the deduction. After the ranged command, the
executor clears both remaining capacity (`+0x04`) and the active/actionable flag
(`+0x5C`).

`004D0560` receives the battle-unit pointer in `EAX`, returns in `EAX`, takes no
stack arguments and uses plain `RET`. Its recovered formula is:

```text
speed =
    unit-definition speed
  + persistent-instance modifier 7
  + intrinsic modifier 7
  + runtime-node modifier 7
  + eligible commander-aura modifier 7

if stamina < 5 and speed > 1:
    speed -= 1
if stamina < 3 and speed > 1:
    speed -= 1

return max(speed, 1)
```

Numeric modifier ID `7` remains the evidence identity; the working semantic name
is effective battle speed.

**Re-entry and restoration.** The comparison is not equivalent to movement
history:

- battle-action effect type `7` can increase `+0x04` and cap it to the current
  `004D0560` result;
- a separate non-movement tactical command increments `+0x04` by one;
- `004E0280` performs ordinary player selection by writing
  `g_current_battle_unit` and updating presentation links, but does not write the
  selected unit's `+0x04` or `+0x5C`;
- `004DE2B0` only returns the next living `+0x5C`-eligible unit on the current
  side and does not mutate selection or capacity.

Therefore a unit may move, have capacity restored to effective speed, be
deselected and reselected, and then pay the one-point ranged cost. A
`steps_this_round > 0` discriminator would incorrectly charge two.

**Correction to R7 evidence wording.** `004F13C8..004F1453` is not the ordinary
selection interval. It scans the clicked coordinates and opens
`004DA6B0`, the battle-unit details interface. The whole-side-phase conclusion
remains valid; actual selection is performed through `004E0280`.

**Rejected alternatives.**

- Cost 1 only when remaining capacity equals effective capacity: rejected,
  because the branch is `remaining >= effective`.
- `+0x04` is merely another encoding of accumulated movement: rejected, because
  non-movement effects restore or increment it.
- Ordinary same-side reselection refreshes capacity: rejected, because
  `004E0280` preserves the unit record.

**Engine consequence.** Genesis compatibility must derive ranged attack stamina
cost from live remaining capacity versus current effective speed.
`steps_this_round` may remain diagnostic or support an explicit native rules
mode, but it is not the compatibility input. The existing engine implementation
requires correction and a restored-capacity/reselection fixture.

---

## R9 — CLOSED: aggregate, halve at exactly zero stamina, then clamp to zero

**Closes:** `OPEN_QUESTIONS` item 9 · matrix STATS-DEFENCE-001
**Evidence:** `EXP-R9-001`; complete `004D0820` and `004D06B0` bodies and callers

**Result (2026-08-05).** Ordinary defence and ranged defence use the same final
state-reduction order:

```text
value = aggregate_all_applicable_providers(unit)

if unit.current_stamina == 0:
    value = trunc0(value / 2)

return max(value, 0)
```

The stamina predicate is exactly equality with zero. The signed divide uses
`CDQ; SUB EAX,EDX; SAR EAX,1`, so negative odd values truncate toward zero.
The floor-zero clamp follows the halving and every provider contribution.
Modifier `0x12` is not consulted by either effective-defence function.

The requested vectors are identical for both functions:

| accumulated value | stamina nonzero | stamina 0 |
|---:|---:|---:|
| -1 | 0 | 0 |
| 0 | 0 | 0 |
| 1 | 1 | 0 |
| 2 | 2 | 1 |
| 3 | 3 | 1 |
| 7 | 7 | 3 |

The provider sets differ before the shared tail:

- `004D0820` uses modifier ID `4`, UnitDef `+0x2C`, terrain-definition
  `+0x24`, and terrain-linked modifiers `0x20..0x22` divided by four;
- `004D06B0` uses modifier ID `5`, UnitDef `+0x30`, terrain-definition
  `+0x28`, terrain-linked modifiers `0x20..0x22` divided by eight, and a
  conditional `+3` tactical contribution when `DAT_00520782 != 0` and the
  battle-unit field at `+0x44` is greater than five; their game-facing meanings
  remain unnamed.

Both also include persistent instance, intrinsic, runtime-node and eligible
commander-aura providers before tactical providers and state reduction. The
tactical block runs only when `DAT_0052E438 == 0` and current life is positive;
the direct terrain-definition contribution is skipped under effective modifier
`0x0E`.

Both functions receive the target battle-unit pointer in hidden register `ESI`
and return the signed effective value in `EAX`; there are no stack arguments and
each ends with a plain `RET`. Later damage-path modifiers such as `0x27`, `0x11`,
`0x4C` and `0x4D` operate on the already-returned effective defence and are not
part of this provider pipeline.

**Rejected alternatives.** Clamp-before-halve, minimum-one clamping,
floor-like arithmetic right shift for negative odd values, stamina predicates
other than exactly zero, providers added after halving, and differing ordinary
versus ranged final reduction order.

**Documentation consequence.** Preserve the provider distinction and the exact
integer tail in compatibility fixtures. The executable evidence is PROVEN but
remains not independently observed at runtime.

---

## R10 — OPEN: where conditional attack bonuses enter the multiplier pipeline

**Closes:** `OPEN_QUESTIONS` item 7
**Ledger:** damage path `004D2E60`
**Method:** decompilation
**Cost:** medium

**Question.** Conditional bonuses such as «Сокрушение зла» are excluded from
morale multiplication. Where exactly do they enter relative to the additive
bonuses, the stamina and wound multipliers, the integer truncation before
morale, and the morale percentage itself?

**Why the ordering is the whole question.** §1.4 established that the pipeline
truncates to an integer before applying morale. That makes ordering observable
rather than academic: a conditional bonus added before the truncation and one
added after produce different results for the same unit. The engine has a
provider order that has never been checked against the binary.

**Minimum sufficient answer.** One conditional modifier traced from its provider
through `004D2E60`, with the insertion point named relative to the four steps
above, plus one wounded and one exhausted case to show whether the multipliers
apply to the bonus or only to the base.

---

## R11 — OPEN: modifier `0x12` («Неутомимый») consumer list

**Closes:** `OPEN_QUESTIONS` item 8
**Method:** decompilation — XREF enumeration, little reduction needed
**Cost:** small

**Question.** Which stamina consumers check modifier `0x12`? Specifically: does
the same check suppress direct stamina-setting effects and the zero-stamina
attack penalty, or only the ordinary per-action costs?

**Why it is cheap and worth doing early.** This is an XREF list rather than a
semantic reduction, so it is one of the least expensive items here, and it
determines whether the engine models the ability as "costs are skipped" or as
"stamina cannot fall," which are different implementations rather than different
wordings.

**Minimum sufficient answer.** The list of call sites testing `0x12`, and for
each, one word on what it suppresses. If any direct stamina-setting effect
bypasses the check, say so explicitly — that is the case that distinguishes the
two models.

---

## R12 — OPEN: `Удар и возврат` return anchor

**Closes:** `OPEN_QUESTIONS` item 13
**Method:** action executor, or instrumented observation
**Cost:** medium

**Question.** Observation says the unit returns to its command-start tile. What
field stores that anchor, when is it written, and does it survive a split
activation — move, yield, then attack later in the same round?

**Why the lifecycle matters more than the value.** The engine can already return
a unit to where it started. What is unproven is what "started" means when the
activation is not contiguous. If the anchor is written at command entry it is one
rule; if written at activation start and rewritten on re-entry it is another, and
they differ exactly in the split case.

**Minimum sufficient answer.** The write site of the anchor field and whether
re-entry rewrites it.

---

## R13 — OPEN: start-of-turn effects — round boundary or activation?

**Closes:** `OPEN_QUESTIONS` item 11
**Method:** decompilation
**Cost:** medium

**Question.** Do start-of-turn effects fire once per round, or once per unit
activation?

**Coupling worth noting.** This interacts with R7. If turn structure is per-unit
alternation, "start of turn" is ambiguous in a way it is not under whole-side
phases, so answering R7 first may make this question sharper or may collapse it.
Please take them in that order if both are in scope.

**Minimum sufficient answer.** One `Прилив сил` or rage consumer traced across a
yield and re-entry, showing whether it fires again.

---

## R14 — OPEN: does any unit occupy more than one tactical cell?

**Closes:** `OPEN_QUESTIONS` item 2
**Method:** observation is decisive and cheap
**Cost:** very small

**Question.** Does `Гигант` — or any category — occupy more than one hex in the
inspected build?

**Why it is worth asking despite looking settled.** The engine models every unit
as single-cell. If that is right, this closes permanently and the battlefield
geometry is finished. If it is wrong, placement, adjacency, movement blocking,
area effects and aura reach all change at once. It is a cheap question with an
expensive wrong answer, and it can be settled by placing a giant on the field and
looking at it.

**Minimum sufficient answer.** Yes or no, plus the footprint shape if yes.

---

## R15 — OPEN: all-zero weighted table and exhausted level-up pools

**Closes:** `OPEN_QUESTIONS` items 6 and 6b together
**Ledger:** weighted roller `00454E80`
**Method:** constructed state, or the caller's guard
**Cost:** small

**Question.** Two halves of one situation. (a) What does the weighted roller do
when every surviving weight is zero? (b) What does the level-up path do when a
unit's pool is exhausted, or offers fewer choices than requested?

**Current engine behaviour, stated so it can be contradicted.** `LegacyRng`
raises on a zero total rather than returning a value, deliberately, because
`LEGACY_RNG.md` says compatibility code must not invent a fallback. That is a
placeholder for the real answer, not a claim about the original. If the original
returns a sentinel, returns the first entry, or skips the selection entirely,
the engine should match it.

**Minimum sufficient answer.** The control flow after a zero total — whichever
of return-early, sentinel, or caller-side guard it turns out to be. If the
caller guarantees a positive total and the roller is never reached in that
state, that is a complete answer and closes 6b as unreachable.

---

## R16 — OPEN: action dispatch table

**Closes:** matrix ACTION-DISPATCH-001 (NEEDS EXTRACTION)
**Method:** decompilation
**Cost:** medium to large

**Question.** How are tactical actions dispatched — a jump table, a chain of
comparisons, or an indexed handler array — and what is the action ID space?

**Why it is on the list despite being large.** It is the last structural unknown
in the tactical layer. Everything else open is a rule detail inside a step whose
existence is already known; this is the step list itself. It is also the
prerequisite for the "one genuinely new action" half of the extension probe, so
it gates agreed future work rather than only current work.

**Minimum sufficient answer.** The dispatch mechanism and the ID-to-handler
mapping for the ordinary actions — move, attack, ranged attack, wait, defend.
Exotic actions can follow later.

---

## R17 — OPEN: melee hit secondary effects

**Closes:** matrix MELEE-SECONDARY-001 (NEEDS EXTRACTION)
**Ledger:** `004D9800`
**Method:** decompilation
**Cost:** large

**Question.** The order and conditions of secondary effects on a melee hit:
drains, debuffs, triggered actions, adjacent attacks and damage-proportional
effects.

**Priority note.** Lowest of the tactical set, and deliberately so. It is large,
it is one function, and the engine can execute complete battles without it — the
effects it governs are additive to a working hit rather than part of it. Take it
only when the smaller items above are exhausted, or when a specific ability
needs it.

**Minimum sufficient answer.** The sequence of effect categories with their
guards. Individual effect formulas can be separate follow-ups.

---

## Deferred, deliberately

`ECON-RECRUIT-001` and `ECON-PROVINCE-001` remain open in the matrix. The engine
is tactical-first and has no economy layer, so these would produce evidence with
no consumer for some time. Recording the deferral so it reads as a decision
rather than an oversight.

`OPEN_QUESTIONS` item 4c — residual RNG persistence and the conditional
battle-outcome reseed — stays deferred on its own stated condition: it becomes
relevant when a fixture needs continuation inside one reseed epoch, or when save
compatibility enters scope. Neither is true yet.

---

## Suggested batching

Two clusters, because they use different tools and can proceed independently.

**Original-game observation work.** R14 (place a giant and inspect its
footprint) and the observation half of R6 (put a ranged-only unit adjacent to an
enemy) remain useful, but they are separate from the binary queue.

**Ghidra work, in rising cost.** R11 is the remaining small XREF-enumeration
item. R10, R12 and R13 are medium. R16 and R17 are the large reductions and
should come last.

If only one binary item is done next: **R11**. It is bounded, mechanically
falsifiable, and resolves whether modifier `0x12` means “skip listed costs” or
“stamina cannot fall.”

---

## Reporting conventions requested

**Record both confidence axes.** `AGENTS.md` defines PROVEN (assembly, layout,
call-site or data-flow evidence) and VERIFIED (checked against a table, fixture or
controlled observation) as separate labels, and `EVIDENCE_LEDGER.csv` carries
`confidence` and `confirmed_by_observation` as separate columns. A correct reading
of a decompiled branch establishes what the code does; it does not establish that
the shipped game behaves that way in every reachable state. Most ledger claims
remain at `confirmed_by_observation = no`, which is accurate and worth keeping
visible rather than quietly upgrading.

**Say when two sources agree.** Cross-source agreement — binary and published
table, or binary and controlled observation — is the strongest evidence available
short of an executed vector, and it is currently under-recorded. Cite both source
IDs when it happens.

**Record the binding scope.** A recovered fact must state where it constrains
Project EGO:

- `legacy_behavior` — Genesis compatibility execution must reproduce it;
- `eador_var_import` — the `.var` importer must parse or resolve it;
- `original_persistence` — it matters only for original-compatible layouts or
  persistence;
- `diagnostic_only` — it is true of the executable but does not prescribe engine
  representation;
- `unresolved` — the evidence does not yet establish an obligation.

The ledger also carries a one-sentence `engine_obligation`. This prevents
register layouts, temporary scaling, and fixed source-array sizes from becoming
accidental universal architecture.

**Preserve rejected alternatives.** When a packet rules something out, the
rejected hypothesis is worth a line in the ledger. Several open questions exist
because a plausible reading was recorded without the alternatives it displaced.

**Prefer one closed item to three partial ones.** The matrix and ledger are
already large, while many evidence-ready rows still lack executable fixtures.
The constraint on this project is conversion of evidence into fixtures, not
acquisition of more evidence.
