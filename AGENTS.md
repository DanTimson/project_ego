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

## Mechanical compatibility rules

- Preserve integer division and its original ordering.
- Preserve modulo bias and random-call order when reproducing legacy paths.
- Do not replace hidden-register calling conventions with invented ordinary
  prototypes in reverse-engineering notes.
- Navigate recovered functions by address; Ghidra names have changed during
  analysis.
- Keep numeric modifier and action-effect IDs numeric until data or localization
  proves a name.
- Distinguish the current Project EGO design from recovered original behaviour.
  A cleaner design is allowed, but compatibility divergence must be explicit.

## Architecture constraints

- `core/` may not reference `game/`, scenes, Nodes or autoloads.
- `ContentDb` is constructed and injected; it is not a rules singleton.
- Original game data is never committed.
- `oracle/` is a permanent reference implementation, not disposable tooling.
- UI and animation functions do not define mechanics.
- Traces and scenario logs are part of the deterministic contract.

## Required companion changes

A mechanics change should normally include:

- a Python oracle change or an explanation why none is required;
- a GDScript test or fixture;
- a formula/status/open-question update;
- a trace-visible reason for any ordering-sensitive behaviour.

A reverse-engineering change should normally include:

- address and confidence;
- exact input/output storage when known;
- function-map update;
- header update when a layout changes;
- a regression-test target when the rule is implementation-grade.

## Current high-priority work

1. Resolve and document the charge-distance discrepancy.
2. Recover the underlying CRT `rand()` sequence and seed lifecycle.
3. Complete the battle-action effect-type dictionary.
4. Cross-reference modifier IDs with `.var` and localization.
5. Implement timed status parity in `core/model/status.gd`.
6. Extract explicit `.var` record schemas from the startup loader.
7. Normalize economy formulas and add golden vectors.
8. Consolidate tactical AI scoring only after mechanics parity is stable.

Do not request broad new decompilation dumps while an existing dispatcher or
loader can answer the current question.
