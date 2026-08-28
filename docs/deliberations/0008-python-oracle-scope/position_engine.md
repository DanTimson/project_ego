# Engine position — DELIB-0008

## Repository evidence examined

- `docs/deliberations/0008-python-oracle-scope/brief.md`.
- `docs/ARCHITECTURE.md` (dependency-direction diagram, `oracle/` and `core/`
  layer responsibilities, evidence-flow diagram at line ~229).
- `docs/POSITION_ENGINE.md` (the standing engine/binary paired-position doc —
  a different, older artifact from this deliberation's `position_engine.md`;
  read for continuity of the project's own stated abstraction discipline).
- `docs/COMPATIBILITY_TEST_MATRIX.md`, full table.
- `docs/codex/tasks/CX-016.md`, `CX-017.md` (recent full task contracts).
- Module inventory: `oracle/*.py` (48 files) vs `core/**/*.gd` (43 files),
  compared by responsibility name (`oracle/scenario.py` ↔
  `core/battle/scenario.gd`, `oracle/turn.py` ↔ `core/battle/round_loop.gd`,
  `oracle/death_replacement.py` ↔
  `core/rules/genesis_death_replacement_resolver.gd`, `oracle/legacy_rng.py`
  ↔ `core/legacy_rng.gd`, `oracle/statuses.py` ↔ `core/rules/statuses.gd`,
  etc.).
- Line counts: oracle production (excluding `test_*.py`, `conftest.py`,
  `make_fixtures.py`) ≈ 6,849 `wc -l` lines across 22 files; `core/**/*.gd`
  ≈ 7,181 lines across 43 files. Comparable order of magnitude, confirming
  the brief's "accepted starting fact" rather than contradicting it.
- Test surface: `oracle/test_*.py` ≈ 6,900 lines / 33 files;
  `tests/**/*.gd` ≈ 6,785 lines. Two full test suites for one behavior set.
- Full text of `oracle/legacy_rng.py` (167 lines) — read in detail as the
  strongest retention candidate.
- Full text of `oracle/scenario.py` header (lines 1–120) and
  `tests/test_scenario.gd` header (lines 1–40) — the log-diff mechanism.
- `oracle/test_fixtures_current.py` and `oracle/make_fixtures.py` header —
  the actual cross-language comparison mechanism (fixture generation +
  byte-for-byte staleness check, not a live dual-engine run).
- `oracle/death_replacement.py` (lines 1–70) vs
  `core/rules/genesis_death_replacement_resolver.gd` (lines 1–70) — read
  side by side. Same constant names, same method names
  (`_diagnostic`/`_diagnostic`, `_normalize_compatibility`/
  `_normalize_compatibility`), same control flow, same field names in a
  different syntax. This is a structural port, not an independently derived
  implementation.
- `oracle/test_repository_hygiene.py` — precedent for a mechanically
  enforced repository policy (provenance/`.var` redistribution), used below
  as a template for a possible mirror-regrowth guard.
- `git show --stat` on the three most recent commits
  (`fba4d88`, `487ca22`, `75abb21`): each touches `core/**`, `oracle/**`,
  `tests/**` (GDScript) and `docs/**` simultaneously. CX-016 alone (`75abb21`)
  changed 34 files: a 194-line new GDScript resolver and a 221-line new
  Python resolver landed in the same commit, structurally identical.
- `docs/STATUS.md` — confirms economy, campaign, and tactical/strategic AI
  are not yet implemented in either language ("not implemented", "scaffold
  only", "deferred"), so this policy is genuinely prospective for full-engine
  scope rather than retroactive.

## Current architecture assessment

The audit's core measurement — comparable nonblank production size in
`core/**` and oracle production modules — replicates under a fresh count
(≈6,849 vs ≈7,181 lines) and the module-name correspondence is almost 1:1:
every tactical subsystem in `core/battle`, `core/content`, `core/model`,
`core/rules` has a same-named or clearly-paired oracle module. This is not
the audit overstating the case. **Answering question 1 directly: the Python
oracle is a near-complete second tactical engine, not an exaggeration.**

But "near-complete second engine" is not one uniform kind of duplication, and
the brief's own decision criterion 5 (distinguish an independent reference
implementation from a line-for-line port that reproduces the same bug)
matters more than the aggregate line count. Reading actual module pairs
shows at least three distinct categories coexisting under one "oracle" label:

1. **Recovered-behavior kernels**, authored *from* reverse-engineering
   evidence independently of the GDScript port, with their own vectors
   transcribed by hand from documentation rather than generated from either
   implementation. `oracle/legacy_rng.py` is the clean example: its own
   docstring records two "traps" (bound-1 consuming a value; the
   `30000`/`30001` loop boundary) that are exactly the kind of thing a
   translation, done casually, would silently get wrong in one language and
   not the other. `docs/POSITION_ENGINE.md`'s Round 4 entry independently
   confirms this: "no published vector except the `bound 1` row catches it."
   These vectors were transcribed from `LEGACY_RNG.md`, not derived from
   either codebase, so they are actual third-party ground truth, not a
   comparison of two things built by the same person in the same sitting.

2. **Formula/primitive kernels** with `docs/COMPATIBILITY_TEST_MATRIX.md`
   rows backed by a decompiled address (damage curves, morale bands, XP
   thresholds, defence clamps). These have a similar shape to (1) — a
   specific numeric contract recovered from a binary address — but are
   smaller, more self-contained, and more naturally expressed as vectors
   than as standing classes.

3. **Orchestration/composition modules** — `scenario.py`, `turn.py`,
   `content.py`, `content_actions.py`, `death_replacement.py`, `roster.py`,
   `handlers.py`, `action_execution.py`. These are the modules that wire
   primitives together into the actual game loop: command dispatch, phase
   transitions, content loading and composition, plan resolution. Reading
   `oracle/death_replacement.py` next to
   `core/rules/genesis_death_replacement_resolver.gd` shows these are built
   by translating one implementation into the other's syntax — identical
   private method names, identical constant tables, identical branch
   structure. A reasoning error made once (e.g. an off-by-one in tier
   mapping) would be typed twice, by the same person, in the same task, and
   both languages would agree while being wrong. `docs/POSITION_ENGINE.md`'s
   own "Standing note" language — "new abstraction requires demonstrated
   second implementation... or proven conflict" — is a principle the project
   already applies to internal abstractions; it has not yet been applied to
   whether the *second engine itself* is warranted per subsystem.

Category (3) is where "roughly comparable size" comes from — `scenario.py`
(1,082 lines) and `combat.py` (1,015 lines) alone are ~30% of oracle
production, and their GDScript counterparts (`scenario.gd` 1,312 lines,
`round_loop.gd` + `damage.gd` + handlers) are comparably large. It is also
where the CX-016/CX-017 co-change evidence lands: every recent task that
touched `core/rules/` or `core/battle/` also touched the corresponding
oracle orchestration file in the same commit, confirming the brief's "two
production changes and two test surfaces" claim as observed fact, not
audit rhetoric.

## Option comparison

**Option A (permanent near-complete mirror).** Steelmanning it: the log-diff
mechanism described in `oracle/scenario.py`'s docstring — "a scenario that
reproduces exactly is evidence the whole chain agrees, far stronger than any
subsystem test" — is real and has caught real problems (the R7 automatic
side-transition fixture drift that `oracle/test_fixtures_current.py`'s own
docstring cites as the motivating incident). A believer in A would argue that
narrowing removes exactly the end-to-end integration check that unit-level
vectors cannot reconstruct, and that "orchestration" is precisely where
subtle cross-subsystem ordering bugs live (charge-then-defence-then-RNG
ordering, stamina mutation suppression interacting with morale, etc.) — the
things a per-formula vector cannot exercise because it doesn't cross module
boundaries.

This argument is not baseless, but it proves too much: it argues for the
value of *end-to-end scenario coverage*, not for the value of *two
hand-maintained orchestration implementations*. The mechanism that actually
catches the R7 regression is "committed fixture vs port," and the committed
fixture is generated once from the oracle and diffed byte-for-byte
(`test_fixtures_current.py`) — nothing about that mechanism requires the
oracle's `scenario.py`/`turn.py`/`content.py` to be full re-implementations
of composition, dispatch, and phase logic rather than thin executors that
answer to a smaller, deliberately-scoped surface. Option A's real cost, which
the recent-commit evidence quantifies directly, is that every full-engine
subsystem still to come (campaign, economy, persistence, tactical/strategic
AI — none yet started per `docs/STATUS.md`) would multiply today's 34-file,
two-language commit pattern indefinitely, with no natural point where the
second implementation stops earning its keep. That is not sustainable at
full-engine scale and the brief is right to force a decision before it
compounds.

**Option C (mostly specification/vector oracle).** Steelmanning it: if the
value is genuinely in vectors and neutral fixtures (categories 1 and 2
above), C says stop pretending category 3 needs a standing implementation at
all — collapse the oracle to calculators and fixture generators, and let
GDScript be graded against data, not against a second program. This is
attractive for its simplicity and for eliminating co-change cost entirely.

It goes further than the evidence supports, though. `oracle/scenario.py`'s
log-diff mechanism has demonstrated value beyond what static vectors can
give: it exercises *emergent* cross-subsystem sequencing (pathfinding →
charge → stamina → RNG → defence → death) that no one hand-writes vectors
for, because the combinatorics are the point. Under C, that mechanism either
disappears (accepting a real coverage loss for exactly the integration bugs
category 3 modules currently catch) or gets rebuilt as a "spec runner" that
executes the *composition* from a declarative description — which is,
functionally, most of `scenario.py` and `turn.py` again, just renamed. C's
promise of eliminating orchestration mirroring is largely illusory for the
scenario-log mechanism specifically; it would have to keep enough executable
composition logic to drive a log that GDScript can be compared against,
which is most of what makes category 3 modules expensive today.

**Option B (selective permanent executable oracle).** This matches what the
evidence actually separates cleanly: keep standing executable
implementations for category 1 (recovered-behavior kernels with independent
vectors — `legacy_rng.py`, morale/damage/stamina primitives) and for the
scenario/log-diff *mechanism* narrowly construed (enough of `scenario.py` /
`turn.py` to drive command sequences and emit a log — not full orchestration
parity with every GDScript composition feature), while treating category 3
modules that do not feed the log mechanism (`content_actions.py`,
`roster.py`, `handlers.py`, `identity.py`, `death_replacement.py`,
`action_execution.py`, most of `content.py`) as candidates for narrowing:
either demoted to producing input fixtures/expected-output vectors consumed
once by GDScript tests, or retired opportunistically as GDScript coverage
matures, rather than kept as a standing parallel implementation that every
future task must touch.

## Recommended position

**Option B**, staged, with the scenario/log-diff mechanism named explicitly
as a retained asset rather than folded generically into "orchestration."
Full near-complete mirroring (A) does not survive contact with the
per-commit cost evidence at full-engine scale, and full vector-only scope
(C) would sacrifice the one mechanism — differential scenario logs — that
has demonstrated catching a class of bug (cross-subsystem sequencing
regressions) that neither unit vectors nor GDScript-only tests are
positioned to catch alone.

## Retention criteria

A responsibility keeps (or gets) a standing Python executable implementation
when it satisfies at least one of:

1. **Independently recovered, not co-derived.** The expected values come
   from a source outside both codebases — a decompiled address, a published
   formula document, a hand-transcribed vector set (`legacy_rng.py`'s
   traps, the `docs/COMPATIBILITY_TEST_MATRIX.md` "READY"/"IMPLEMENTED" rows
   backed by an address). If the Python and GDScript values would be typed
   by the same person reasoning from the same recovered fact in the same
   session, this criterion is not met by that fact alone — the *vector* is
   the independent artifact, not the *code that produces it*.
2. **Feeds the scenario/log-diff mechanism.** The module is load-bearing for
   producing or interpreting the committed `tests/scenarios/*.json` →
   log-line comparison described in `oracle/scenario.py` and
   `tests/test_scenario.gd`. This is a narrow, named exception, not a
   license to keep every module a scenario happens to import fully general.
3. **Compatibility-only arithmetic with no natural GDScript-side vector
   representation** — e.g. legacy RNG call-ordering, where the *sequence* of
   calls, not just final values, is the thing under test, and reproducing
   that sequence requires executing equivalent logic, not just comparing
   numbers.
4. **A proven conflict has already occurred** between the two
   implementations that a vector would not have caught (the R7 fixture-drift
   incident cited in `test_fixtures_current.py`'s docstring is the kind of
   evidence that qualifies a *mechanism*, though not automatically every
   module the mechanism happens to route through).

## Non-retention criteria

A responsibility should default to GDScript-only (no new standing Python
implementation) when:

1. **It is generic runtime orchestration**: command dispatch, plan
   resolution, content composition/loading, roster/identity bookkeeping,
   phase/turn bookkeeping not directly feeding the log mechanism. These are
   software-engineering structure, not recovered facts — there is nothing a
   second implementation is independently checking that a well-designed
   GDScript unit test cannot check directly.
2. **It is a full-engine subsystem with no legacy binary counterpart to
   recover from** — campaign/strategy, economy, persistence, tactical or
   strategic AI as newly designed systems (not ports of a decompiled
   formula). There is no "independent evidence" a Python port could offer
   for logic invented for this project, since both implementations would be
   equally first-party.
3. **The expected behavior can be captured as a data vector** (input →
   output table) rather than requiring executable process. If a
   responsibility's contract can be exhaustively described as rows in a
   fixture, prefer generating that fixture once (by calculator script or by
   hand from the spec) over maintaining a parallel class hierarchy.
4. **Same-session structural translation.** If implementing a feature in
   Python would consist of transliterating the GDScript design (or vice
   versa) with matching private method names and matching control flow —
   the `death_replacement.py` /
   `genesis_death_replacement_resolver.gd` pattern — the second
   implementation is not independent evidence and should not be produced by
   default.

## Existing-module transition

No wholesale deletion. Three-tier reclassification, applied opportunistically
rather than as a scheduled migration:

- **Tier 1 — retain and keep current.** `legacy_rng.py`, morale/damage/
  stamina primitive modules backed by `COMPATIBILITY_TEST_MATRIX.md`
  addresses, and the minimal scenario/log-diff spine (`scenario.py`,
  `turn.py`, `battlefield.py`, `combat.py`, `modifier.py`,
  `modifier_semantic.py`, `statuses.py`, `auras.py`, `counterattack.py` —
  the modules a differential scenario log actually exercises end to end).
  These keep receiving parity updates as before; nothing changes for them
  under this policy.
- **Tier 2 — freeze, do not expand.** Orchestration modules not directly
  needed by the log mechanism but currently load-bearing for existing
  committed fixtures/tests (`content.py`, `content_actions.py`, `roster.py`,
  `identity.py`, `handlers.py`, `death_replacement.py`,
  `action_execution.py`, `declarative_action_recipe.py`, `bind_blockers.py`,
  `charge.py`). Bug fixes land in both languages as today (a divergence here
  is still a real bug even if the second implementation isn't earning new
  differential value). New *features* in these areas get GDScript-only by
  default; a Python addition requires citing which retention criterion
  applies, in the task contract, the same way CX task contracts already
  state scope explicitly (see CX-017's "Purpose"/"Architectural invariant"
  sections as the existing template for this kind of explicit justification).
- **Tier 3 — opportunistic retirement.** As GDScript-side test coverage for
  a Tier-2 module's contract becomes self-sufficient (property tests,
  exhaustive vectors, or scenario coverage subsuming what the module
  checked), its Python counterpart may be reduced to the vectors it
  produces and the executable class retired, in a task whose explicit
  purpose is that retirement — not silently, and not bundled into an
  unrelated feature task.

This mirrors the transition shape the project already used for
`docs/POSITION_ENGINE.md`'s own abstraction discipline ("new abstraction
requires a demonstrated second implementation... otherwise defer") — applied
here to *removing* an existing duplicate rather than *adding* a new
abstraction, which is the same discipline pointed the other direction.

## Test/CI consequences

Narrowing Tier 2/3 modules must not let GDScript grade its own homework.
Concretely:

- When a Tier-2/3 Python class is retired to vectors, the **vectors it
  produced must be captured as committed fixtures before retirement**, using
  the existing `make_fixtures.py` → `tests/fixtures/*.json` →
  `test_fixtures_current.py` pattern, so the fixture keeps being an
  independently-committed, diffable artifact rather than something GDScript
  generates and checks against itself. `test_fixtures_current.py`'s own
  stated purpose — catching a fixture that silently drifted from its
  generator — is exactly the discipline that prevents "narrowing the mirror"
  from becoming "GDScript grades itself": the fixture's *values* remain
  external to GDScript even after the *generating code* stops being
  actively maintained as a parallel engine.
- Property-based and edge-matrix tests (the `COMPATIBILITY_TEST_MATRIX.md`
  rows already marked READY/IMPLEMENTED with an address) should be
  preferentially expressed as data tables consumed by both languages'
  test runners from one source of truth where practical, rather than as
  parallel executable assertions that happen to agree.
- The scenario/log-diff mechanism (Tier 1) is explicitly preserved as
  cross-executable, because it is the one mechanism whose evidentiary value
  depends on genuinely running two independent programs, not on comparing
  against static data.
- A retired Tier-3 module's Python source should not simply disappear from
  the repository in the same act that stops it being test-relevant;
  historical fixtures and recovered evidence are a non-goal to discard
  (brief's non-goals list) and the module itself is provenance for how a
  fixture was produced.

## Full-engine consequences

Campaign/strategy, economy, persistence, and tactical/strategic AI are
unimplemented in both languages today (`docs/STATUS.md`: "not implemented",
"scaffold only", "deferred"), so this policy is genuinely preventive rather
than requiring retrofit. The default for these systems:

- Where a subsystem is a **port of recovered binary behavior** (e.g.
  province income formulas at `00432E60`-class addresses per
  `docs/COMPATIBILITY_TEST_MATRIX.md`'s `ECON-*` rows), it qualifies under
  retention criterion 1/3 — implement the formula kernel in Python with
  vectors, same as `legacy_rng.py` and the damage/morale primitives, before
  or alongside the GDScript formula.
- Where a subsystem is **project-designed** (AI scoring policy, persistence
  schema, campaign turn structure, anything without a decompiled reference),
  it is GDScript-only by default under non-retention criterion 2. A Python
  implementation of project-original AI or campaign logic would not be
  "independent evidence" of anything — both sides would be equally
  first-party design, and the co-change tax (CX-016/CX-017's 22–34-file
  pattern) would apply to systems an order of magnitude larger than
  tactical combat with zero corresponding benefit.
- Persistence is a partial exception worth flagging now rather than
  deciding: if original-format save compatibility becomes a project goal (as
  opposed to an EGO-native save format), that specific serialization layer
  would be a `original_persistence`-scope concern in the same sense
  `docs/POSITION_ENGINE.md`'s five-way binding-scope table already uses, and
  might independently qualify under retention criterion 1 — but only for the
  serialization/layout logic itself, not for a full persistence engine
  mirror.

## Risks

- **Divergence blind spot in Tier 2/3.** Freezing rather than actively
  differential-testing orchestration modules means a future GDScript-only
  bug in, say, content composition or plan resolution will not be caught by
  a parallel Python failure the way it might be today. Mitigated by keeping
  those modules' existing fixture coverage rather than deleting it, and by
  Tier 1 (scenario log) still exercising much of the same code path
  end-to-end even without a standing parallel orchestration class.
- **Criteria are judgment calls, not a formula.** "Feeds the scenario/log
  mechanism" and "would be typed by the same person from the same fact" both
  require a task author to make a real assessment, not run a script. A
  future author could misclassify a genuinely valuable kernel as
  orchestration, or the reverse. Mitigated by requiring the citation to
  appear in the task contract (visible for review), matching the existing
  practice of explicit scope statements in `docs/codex/tasks/CX-*.md`.
- **Tier boundaries drift as GDScript evolves.** A module frozen as Tier 2
  today because it's genuinely mid-transition may quietly become permanent
  simply because nobody schedules the Tier 3 retirement task. Mitigated by
  making retirement an explicit task type rather than requiring it be
  bundled — visible, plannable work, not a silent expectation.
- **Loss of the R7-class regression catch for non-Tier-1 modules.** The
  fixture-staleness mechanism (`test_fixtures_current.py`) only catches
  drift between the oracle and its own committed fixtures; it does not by
  itself catch GDScript drifting from a fixture whose Python generator has
  been frozen and stopped evolving. This is an accepted trade under B, not
  an oversight — mitigated by scenario-log coverage remaining live for the
  modules that matter most to sequencing bugs.

## Strongest objection to this position

The strongest version of Option A's case is that "orchestration" is
precisely where the hardest bugs live, and precisely where per-formula
vectors are structurally unable to help, because the bug is in the
*sequence and interaction* of otherwise-correct primitives, not in any one
primitive. `docs/POSITION_ENGINE.md`'s own R7 fixture-drift story is a bug
of exactly this shape: not a formula error, an ordering change. If most of
the historically-caught bugs turn out, on inspection of `AUDIT_LEDGER.csv`
or task retrospectives, to be orchestration-level rather than formula-level,
this position's Tier-2 freeze would be freezing exactly the thing that has
been earning its cost, and the "same-session translation" argument, while
true of the *code*, would be missing that the *value* was never in the code
being independent — it was in having a second, differently-timed execution
run the same commands and disagree when a change had an unintended
consequence. That is a real possibility this position does not have hard
evidence to rule out; the commit-level evidence gathered here shows *cost*
clearly (34-file commits) but only anecdotal evidence of *catch value*
(the single R7 incident cited in a docstring), not a systematic count of how
many defects orchestration-level differential execution caught versus how
many a vector-based check would have caught equally well.

## Reconsideration triggers

Revisit this decision, or a specific Tier-2 freeze, if:

- A defect ships to GDScript-only production that a *frozen* (Tier 2/3)
  Python module would plausibly have caught had it still been actively
  maintained and exercised — not hypothetically, but traceable to a specific
  frozen module's prior behavior.
- Retirement-task load in Tier 3 stalls: modules sit "frozen" for multiple
  full-engine milestones without ever being retired, indicating the
  three-tier system has become a place duplication goes to persist
  indefinitely rather than a genuine transition.
- Full-engine work (campaign/economy/AI/persistence) reveals that a
  significant fraction of its logic *is* recoverable-binary-derived (i.e.
  the "project-designed, no decompiled reference" assumption in the
  Full-engine consequences section turns out wrong for a specific system),
  which would move that system's retention classification without changing
  the policy's criteria.
- A future audit can produce a systematic (not anecdotal) count showing
  orchestration-level differential execution catches materially more
  defects per maintenance-hour than the vector/fixture approach, directly
  answering this position's own "Strongest objection" gap.

## Questions for the other side

- Does the binary/governance side have provenance or evidentiary reasons
  (beyond executable differential value) to keep specific Tier-2/3 modules
  standing as *evidence artifacts* even where this position finds no
  differential-testing case for them — e.g. because a module's structure
  itself documents a recovered decision that would otherwise only live in a
  commit message?
- For the `original_persistence` binding-scope category in
  `docs/POSITION_ENGINE.md`'s five-way table: does the governance side
  expect original-save-format compatibility to become an actual project
  goal, which would change this position's persistence carve-out from
  speculative to concrete?
- Is there a lighter-weight mechanical guard than a task-contract citation
  requirement (e.g. something like `test_repository_hygiene.py`'s committed-
  file scan, but for "new oracle module added without a cited retention
  criterion") that the governance side would consider enforceable, to reduce
  reliance on review discipline alone for preventing mirror regrowth?
