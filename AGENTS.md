# AGENTS.md — Project EGO working rules

This file is for coding agents and human contributors working on Project EGO.

## Read first

Before changing mechanics, read:

1. `docs/ARCHITECTURE.md`
2. `docs/STATUS.md`
3. `docs/OPEN_QUESTIONS.md`
4. the relevant section of `docs/FORMULAS.md`
5. `docs/REVERSE_ENGINEERING.md` when binary compatibility is involved
6. `eador_runtime.h` when working with recovered layouts
7. `docs/deliberations/README.md` for cross-agent architecture decisions
8. `docs/WORK_ALLOCATION.md` before delegating implementation
9. `docs/CODEX_WORK_QUEUE.md` and the relevant file under
   `docs/codex/tasks/` when executing or reviewing a bounded task

Use `docs/FUNCTION_MAP.csv` to navigate recovered functions by address.

## Evidence labels

Two questions are being answered, and they are independent:

1. **How well is the rule established?** — PROVEN, STRONG INFERENCE, CANDIDATE,
   STATED, RECOVERED, OPEN.
2. **Has it been confirmed against observed behaviour?** — VERIFIED, or not.

A claim can be PROVEN and not VERIFIED: reading the disassembly correctly
establishes what the code does, not that the shipped game behaves that way in
every reachable state. Most current ledger claims are in exactly that position.
Never let VERIFIED be implied by a strong reading; it requires a table, fixture
or controlled original-game observation.

Use these labels in documentation and comments:

- **PROVEN** — explicit assembly, layout, call-site or data-flow evidence.
- **RECOVERED** — behaviour reconstructed from the executable, with enough
  detail to implement but still tied to the inspected build.
- **VERIFIED** — implementation checked against a table, fixture or controlled
  original-game observation.
- **STATED** — documented by a source but not independently checked.
- **STRONG INFERENCE** — several observations agree, but one link remains
  indirect.
- **CANDIDATE** — useful working name only.
- **OPEN** — unresolved or contradictory.

Do not silently upgrade a candidate name into a game-facing term, and do not
upgrade PROVEN to VERIFIED without naming the vector that confirmed it.

`docs/EVIDENCE_LEDGER.csv` records the two axes in separate columns:
`confidence` and `confirmed_by_observation`.

## Source hierarchy

No source is infallible. When sources conflict, record the conflict.

For exact compatibility with the inspected executable, direct assembly and
concrete call-site behaviour normally outrank prose descriptions. `.var` data
outranks names inferred from mechanics. Published documentation and observation
remain essential for semantics and for detecting build differences.

A protocol or planned observation is not an observation result. Never turn an
empty result sheet, an unexecuted experiment, or an architectural convenience
into an expected compatibility value.

## Mechanical compatibility rules

- Preserve integer division and its original ordering.
- Preserve modulo bias and random-call order when reproducing legacy paths.
- Do not replace hidden-register calling conventions with invented ordinary
  prototypes in reverse-engineering notes.
- Navigate recovered functions by address; Ghidra names have changed during
  analysis.
- Keep numeric modifier and action-effect IDs numeric until data or localization
  proves a name.
- Distinguish current Project EGO design from recovered original behaviour.
  A cleaner design is allowed, but compatibility divergence must be explicit.
- Keep profile-specific behavior explicit; do not silently promote one profile's
  rule to a repository-wide invariant.

## Architecture constraints

- `core/` may not reference `game/`, scenes, Nodes, or autoloads.
- `ContentDb` is constructed and injected; it is not a rules singleton.
- Original game data is never committed.
- `oracle/` is a permanent reference implementation, not disposable tooling.
- UI and animation functions do not define mechanics.
- Traces and scenario logs are part of the deterministic contract.
- Content-definition identity, battle-instance identity, and display text are
  separate concepts; do not use one as a shortcut for another.

## Required companion changes

A mechanics change should normally include:

- a Python oracle change or an explanation why none is required;
- a GDScript test or fixture;
- a formula/status/open-question update when the compatibility boundary changes;
- a trace-visible reason for any ordering-sensitive behaviour.

A reverse-engineering change should normally include:

- address and confidence;
- exact input/output storage when known;
- function-map update;
- header update when a layout changes;
- a regression-test target when the rule is implementation-grade.

## Deliberations and decisions

Use `docs/deliberations/` when a question needs independent engine-side and
binary-analysis positions before a binding decision.

- The human-owned `brief.md` defines the question and constraints.
- Each side writes its own position before reading or editing the other's.
- `cross_review.md` records agreements, disagreements and missing evidence.
- `decision.md` is the canonical outcome; position files are analysis, not
  specifications.
- Accepted decisions name implementation ownership and verification criteria.
- A changed decision is superseded by a new deliberation rather than silently
  rewriting the old one.

Run:

```bash
python3 tools/check_deliberations.py
```

before committing changes under `docs/deliberations/`.

## Delegated execution

Prime Agent, Codex, and similar coding agents are **bounded implementation
executors**, not independent semantic authorities or additional deliberation
participants.

The repository retains `docs/codex/` as the task-contract namespace regardless
of which implementation executor runs a task.

Every delegated task must:

- have a repository task contract under `docs/codex/tasks/`;
- name its semantic owner, executor, and reviewer;
- declare one task class from `docs/WORK_ALLOCATION.md`;
- identify the exact frozen base revision when implementation depends on one;
- list authoritative inputs, allowed outputs, and explicit non-goals;
- state whether runtime behaviour may change;
- define acceptance commands/properties before implementation;
- stop and escalate when a semantic choice, new expected value, profile decision,
  or architecture decision is required;
- end in reviewer inspection of the complete diff, not merely green tests.

For substantial frozen-spec implementation, the preferred pattern is:

1. freeze the semantic contract and base revision;
2. give the executor an isolated worktree;
3. let it inspect/edit/test only inside the contract;
4. leave the task at `REVIEW`;
5. independently inspect semantics, tests, documentation, and diff;
6. record reviewer acceptance before marking `DONE`;
7. land the accepted commit through the normal human-owned VCS flow.

Executors should not commit, stage, reset, rebase, push, or create/remove
worktrees unless a task contract explicitly authorizes those operations.

Governance-owned tasks may touch executable files only when the task is
non-semantic and behaviour-preserving. Gameplay semantics, profile policy,
architecture, and expected-result decisions remain engine-side or human-owned.

A task that discovers a higher-risk decision is reclassified; the executor must
not silently make the decision.

## Validation expectations

Use the narrowest relevant tests while iterating, then run the repository gates
required by the task contract. The common portable gate set is:

```bash
python3 tools/run_godot_tests.py
python3 -m pytest -q
python3 oracle/test_fixtures_current.py
python3 tools/check_deliberations.py
python3 oracle/test_repository_hygiene.py
git diff --check
```

Inherited lint debt is not a reason to refactor unrelated files inside a bounded
task. When touched files already contain gdlint failures, compare the exact same
file set against the frozen base and require **no new findings** unless the task
is specifically a lint-cleanup task.

Machine-specific non-headless smoke tests may supplement the portable gates but
should not become hidden semantic requirements.

## Current work

Use `docs/STATUS.md`, `docs/OPEN_QUESTIONS.md`, `docs/BINARY_REQUESTS.md`, and
`docs/CODEX_WORK_QUEUE.md` as the live work/coverage entry points. Do not copy
their priority lists into `AGENTS.md`; copied lists become stale.

Do not request broad new decompilation dumps while an existing dispatcher,
loader, focused binary request, or controlled observation can answer the current
question.
