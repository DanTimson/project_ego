# Open requests to binary analysis

Requests from the implementation side (`oracle/`, `core/`) to the Ghidra side.
Format follows the request template in `GHIDRA_WORKFLOW.md`. Each item names what
would falsify the current hypothesis, so a packet can close it rather than merely
add detail.

Priority order below is by *what unblocks implementation*, which is not the same
as what is most interesting in the binary.

**Current active request:** none. R1–R4 are closed. Engine-side implementation and executable fixtures are next; add a new binary request only when a test exposes a remaining ambiguity.

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

## Reporting conventions requested

**Record both confidence axes.** `AGENTS.md` defines PROVEN (assembly, layout,
call-site or data-flow evidence) and VERIFIED (checked against a table, fixture or
controlled observation) as separate labels, and `EVIDENCE_LEDGER.csv` now carries
`confidence` and `confirmed_by_observation` as separate columns. A correct reading
of a decompiled branch establishes what the code does; it does not establish that
the shipped game behaves that way in every reachable state. Currently 25 of 26
ledger claims sit at `confirmed_by_observation = no`, which is accurate and worth
keeping visible rather than quietly upgrading.

**Say when two sources agree.** Cross-source agreement — binary and published
table, or binary and controlled observation — is the strongest evidence available
short of an executed vector, and it is currently under-recorded. Cite both source
IDs when it happens.

**Preserve rejected alternatives.** When a packet rules something out, the
rejected hypothesis is worth a line in the ledger. Several open questions exist
because a plausible reading was recorded without the alternatives it displaced.

**Prefer one closed item to three partial ones.** The matrix and ledger are
already large, while many evidence-ready rows still lack executable fixtures.
The constraint on this project is conversion of evidence into fixtures, not
acquisition of more evidence.
