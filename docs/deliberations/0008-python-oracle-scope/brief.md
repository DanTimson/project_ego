# DELIB-0008 — Python oracle long-term scope

## Question

Should Project EGO continue treating the Python oracle as a near-complete second
engine, or narrow it to selected independent semantic/reference implementations and
neutral vectors while GDScript becomes the only complete production runtime?

## Decision required

Define the long-term ownership and expansion policy for `oracle/**` before campaign,
economy, AI, persistence and other full-engine subsystems multiply the current
cross-language mirroring cost.

The decision must say which categories of behavior still justify an independent
Python implementation, which categories should no longer be mirrored by default,
and how existing mirrored modules should be treated during the transition.

## Frozen base

`fba4d88b6cb5d30efffc55e9d7d28f332bdb8986`

## Accepted starting facts

- The Python oracle is intentionally permanent as a compatibility/reference asset,
  but existing documentation does not require "permanent" to mean "complete second
  engine forever."
- The current Python side now mirrors most tactical production responsibilities:
  combatants/state, battlefield/pathing, round/turn logic, actions and plans,
  content loading/composition, modifiers/statuses/auras, damage/counterattack,
  death lifecycle and Scenario execution.
- The post-CX-017 architecture audit measured roughly comparable nonblank production
  size in `core/**` and oracle production modules and classified the duplication as
  HIGH-propagation architectural debt.
- Independent adversarial review accepted that finding: recent mechanics routinely
  require synchronized GDScript production changes, Python production changes and
  two test surfaces.
- The audit did **not** recommend deleting the oracle wholesale. It recommended
  deciding whether a permanent selective semantic/reference oracle gives better
  long-term value than a permanent near-complete mirror.
- Exact deterministic vectors, RNG behavior, integer ordering and selected recovered
  semantic kernels have demonstrated compatibility value.
- Full-engine scope includes campaign/strategy, economy, persistence, tactical and
  strategic AI, content/mod systems and eventual deep mods.
- No current internal API is a public stability commitment merely because both
  languages implement it.

## Options to evaluate

### A — permanent near-complete mirror

Continue implementing essentially every production game subsystem in both GDScript
and Python, maintaining broad differential execution.

### B — selective permanent executable oracle

Keep Python executable implementations only where independent reference logic has
material evidentiary/testing value, while stopping default duplication of generic
runtime orchestration and future full-engine systems.

### C — mostly specification/vector oracle

Use one complete production runtime. Retain Python primarily for neutral
fixture/vector/property generation and small compatibility calculators rather than
standing mirrored subsystems.

The decision may choose a staged combination rather than one pure label, but it must
define a default rule future task authors can apply without reopening this question.

## Decision criteria

The accepted policy must:

1. preserve independent executable checks where they materially catch or distinguish
   compatibility errors;
2. stop automatic double implementation where the second engine provides little
   independent evidence;
3. define concrete **retention criteria** for a permanent Python implementation;
4. define concrete **non-retention criteria** for new systems that should normally
   exist only in GDScript;
5. distinguish an independent reference implementation from a line-for-line port
   that reproduces the same bug;
6. explain how neutral vectors/property tests continue to verify semantics after a
   mirrored orchestration module stops expanding;
7. define what happens to existing mirrored modules without requiring a disruptive
   deletion campaign;
8. state how future CX/task contracts decide whether Python parity is required;
9. preserve provenance/evidence traceability and public-lineage boundaries;
10. avoid making the Python oracle an accidental second public API;
11. account for full-engine scale and eventual deep mods;
12. provide reconsideration triggers if future evidence shows broad differential
    execution is more valuable than expected.

## Non-goals

- Do not delete or refactor oracle modules in this deliberation.
- Do not change production gameplay behavior.
- Do not decide APA-001 event/log architecture, APA-002 battle-context ownership,
  APA-004 package composition or APA-006 command processing.
- Do not redesign CI in detail.
- Do not require campaign/strategy implementation now.
- Do not treat Python implementation agreement as binary evidence by itself.
- Do not discard historical fixtures or recovered semantic evidence.
- Do not freeze external/public APIs.

## Questions for the binary/governance side

- Which kinds of executable oracle logic constitute meaningful independent evidence?
- When does mirrored code cease to be independent enough to justify its maintenance?
- What compatibility/provenance artifacts must survive if orchestration ceases to be
  mirrored?
- What default should future implementation tasks use for Python parity?

## Questions for the engine side

- Which current Python responsibilities actually provide differential-testing value
  beyond vectors/property tests?
- Which current mirrored responsibilities are primarily duplicate product code?
- What is the least disruptive transition from today's near-complete mirror?
- Should existing mirrored orchestration be frozen, retired opportunistically or
  maintained until replaced by vector/spec tests?
- What task/CI rule prevents the mirror from regrowing accidentally?
- What risks are introduced by making GDScript the sole complete runtime?

## Required output

An accepted decision must be operational enough that a future task author can answer
"does this new feature require Python implementation?" from the policy rather than
from habit.
