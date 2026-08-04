# Open requests to binary analysis

Requests from the implementation side (`oracle/`, `core/`) to the Ghidra side.
Format follows the request template in `GHIDRA_WORKFLOW.md`. Each item names what
would falsify the current hypothesis, so a packet can close it rather than merely
add detail.

Priority order below is by *what unblocks implementation*, which is not the same
as what is most interesting in the binary.

**Current active request:** R2. R1 was closed on 2026-08-04 by `EXP-R1-001`.

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

## R2 — Which table do `Effects` references resolve against?

**Closes:** the remaining half of the extraction→roster reference typing
**Ledger:** new claim required
**Blocks:** wiring spells and items into the rules pipeline at all

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

## R3 — Charge distance: two rules that cannot both be exact

**Closes:** `OPEN_QUESTIONS` item 10 · matrix CHARGE-002
**Ledger:** existing, `004DCD90` modifier `0x25`

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

## R4 — PRNG seeding and call topology

**Closes:** `OPEN_QUESTIONS` items 4 and 4b · matrix RNG-LEGACY-001
**Ledger:** RNG-001 (`00454C70`), RNG-002 (`00454E80`)

Listed last deliberately, despite `STATUS.md` calling it the most consequential
blocker. It is the largest item and the least likely to be closed by one packet,
and every other test in the matrix marked "READY except PRNG sequence" is
blocked behind it — which means it should be attacked when there is budget for a
sustained effort, not interleaved with quick closures.

**The narrower question that would help immediately.** Not the full seed
lifecycle, but whether the executable consumes **one shared sequence** or several
independent ones. The current implementation isolates named streams. If the
original uses a single sequence, named streams can never reproduce it and must be
reclassified as a test-only convenience rather than a compatibility mechanism.
That is a design decision blocked on one bit of information, and it does not
require recovering the CRT implementation.

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

**Prefer one closed item to three partial ones.** There are now 44 matrix rows and
26 ledger claims, and no matrix test has an executable implementation yet. The
constraint on this project is conversion of evidence into fixtures, not
acquisition of more evidence.
