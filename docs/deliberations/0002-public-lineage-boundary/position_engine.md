# Position

Engine side, written independently before reading `position_binary.md`, per the
process in `docs/deliberations/README.md`.

## Repository evidence examined

- `docs/PUBLIC_LINEAGE_AUDIT.md` and `docs/PUBLIC_LINEAGE_TRANSFER.csv` (24 rows)
- `docs/PROVENANCE_AND_DATA_POLICY.md`, accepted `DELIB-0001/decision.md`
- `docs/BINARY_REQUESTS.md` — ten closed requests, R1–R9 and R11
- measured: binary-address citations across implementation files
- measured: the state of the modifier `0x12` exemption in `core/rules/stamina.gd`,
  `core/battle/action_points.gd` and `oracle/combat.py`
- measured: `Stamina.speed_penalty` and `Stamina.is_exhausted` call sites

## Claims

### Claim 1 — the audit's §5.1 correctness finding is right, and worse than stated

**Support.** The audit marks the modifier `0x12` stamina exemption as an
immediate correctness defect. It is, and the measurement is more specific than
the audit's description:

| site | before | status |
|---|---|---|
| `oracle/combat.py` `stamina_mod` | exempted | wrong — attack multiplier |
| `core/rules/stamina.gd` `modifier` | exempted | wrong — attack multiplier |
| `core/rules/stamina.gd` `speed_penalty` | exempted | wrong, and **dead**: 0 call sites |
| `core/rules/stamina.gd` `is_exhausted` | exempted | wrong, and **dead**: 0 call sites |
| `oracle/turn.py` `spend_move` / `spend_attack` | gated | **correct** — these are mutations |

Two of the four defective sites were already unreachable, orphaned when
`ActionPoints.effective_speed` and the R9 defence tail replaced them. The
codebase therefore held two divergent implementations of the same penalty, one
corrected and one not, with nothing making the disagreement visible. That is the
project's recurring failure shape: not a subtle bug, but a gap no test could
fail.

The engine side has landed the fix alongside this position. All four sites now
derive penalties from the live stamina value; the two correct mutation gates are
untouched. `oracle/test_combat.py` asserted the old exemption and now asserts the
recovered rule.

**Position:** accept §5.1 as written. Add that the neutral rule should state both
halves — penalties derive from the live value, *and* `0x12` gating belongs only
at mutation sites. Otherwise a future reader may re-add the exemption at a third
site, which is how it survived the first correction.

### Claim 2 — accept the necessity gate, with one caveat about retroactivity

**Support.** All ten closed requests pass the gate on observability and
materiality. Several would fail **criterion 3 (unresolved)** if applied
retroactively: R1's morale bands were already fully specified by the published
table, and the binary confirmed rather than established them. R9's defence
ordering and R5's rounding direction, by contrast, were genuinely unresolvable
from public sources — no published material states a truncation direction.

That is not an argument against the gate. It is an argument that the gate applies
prospectively and must **not** be used to reclassify closed work as unnecessary.
R1's value was precisely that it was a preregistered prediction public
documentation could not confirm alone; the resulting cross-source agreement is
the strongest evidence in the ledger.

**Position:** accept the gate for future requests. Add that criterion 3 is
satisfied when public sources do not settle a question *to the precision the
engine needs* — a published table that omits rounding direction is not a
settlement for an integer pipeline.

### Claim 3 — the transfer classification is sound; `T2_REIMPLEMENT` is smaller than it looks

**Support.** Measured: **37 binary-address citations across 8 implementation
files**, concentrated in `damage.gd` (7), `oracle/turn.py` (7),
`oracle/combat.py` (7), `action_points.gd` (5) and the two `legacy_rng`
implementations (4 each).

Every one is a *comment*. None is control flow, register layout or
decompiler-shaped structure. The implementations were written as ordinary code
against a recovered behavioural rule and then annotated with where the rule came
from. That is what `T1_SANITIZE` describes, and it means most transfer work is
replacing provenance comments with public references rather than rewriting.

The genuine `T2_REIMPLEMENT` cases are those where the *rule itself* has no
public statement: the bounded-RNG decimal-extension adapter, the ranged
zero-entry branch, and the negative-morale rounding direction. Each is narrow.

**Position:** accept the classification. Recommend the CSV additionally record,
per row, whether the binary basis appears as *comment only* or as *structure*.
The two imply very different transfer costs and `transfer_class` alone does not
distinguish them.

### Claim 4 — freeze-and-fork is right, but the fork must inherit the tests

**Support.** This project's strongest asset is not its implementation. It is
roughly 128 passing checks, the differential fixtures, the golden vectors, and
the guards that make coverage gaps visible. Those artifacts are overwhelmingly
`T0`/`T1`: synthetic fixtures with invented names, published-table vectors, and
hand-authored dialect samples containing no original content.

A fresh repository without them starts with no way to tell whether a
reimplementation is correct. With them, a rule can be rewritten and immediately
checked.

**Position:** accept the stage gate, and make it an explicit condition that the
test corpus, fixtures and vectors transfer first and are classified before any
implementation file is rewritten. Rewriting against a passing suite is ordinary
work; rewriting against nothing is a rebuild.

### Claim 5 — rewrite timing: agree, with one addition

**Support.** The audit's rule — immediate only for correctness defects or
spreading binary-shaped dependencies — is exactly what the `0x12` case
demonstrated: the defect had already spread to a second implementation before it
was noticed, and the cost of delay was two divergent copies rather than one edit.

**Position:** accept. Add a third immediate trigger: **a rule two implementations
now disagree about**. Oracle/port divergence is cheap to fix the day it appears
and expensive once fixtures encode it, and it is mechanically detectable rather
than a judgement call.

### Claim 6 — open the ruleset-profile deliberation with four questions, not three

**Support.** Four decisions are already queued and are all profile questions in
disguise: charge semantics, restored-capacity attack cost, legacy versus native
RNG, and whether scenario units may name a canonical content definition. The
brief names the first three; the fourth is an open pending item in `DELIB-0001`.

**Position:** accept, and seed the new deliberation with all four so the
scenario-definition question stops being carried as an orphan.

## Disagreements or gaps

1. **The audit does not classify the evidence documents themselves.**
   `BINARY_REQUESTS.md`, `EVIDENCE_LEDGER.csv`, `FUNCTION_MAP.csv` and
   `REVERSE_ENGINEERING.md` hold the densest concentration of addresses and
   recovered control flow in the repository. They are plainly `T3_RESEARCH_ONLY`,
   but leaving them unclassified invites copying the whole `docs/` tree into a
   public repository on the grounds that it is "only documentation". Recommend
   explicit `T3` rows.

2. **`packs/*/bindings.json` is unclassified and is a real edge.** A generated
   binding file embeds roughly 136 opcode-to-name mappings drawn from
   `ability_num.var`. The committed skeleton is empty, so nothing is exposed
   today — but the question becomes live the moment real bindings are committed.
   This is the same edge previously raised about extracted tables and deserves a
   row rather than discovery later.

3. **No criterion distinguishes a rule recovered from the binary and
   independently confirmed by public sources.** R1's morale curve is supported by
   two independent sources that agree exactly, so the public source alone
   suffices to restate it. Its transfer status should not equal that of a rule
   known only from the binary. Recommend a `public_basis_sufficient` flag, which
   would move several `T2` rows to `T1`.
