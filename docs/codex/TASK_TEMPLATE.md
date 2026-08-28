# CX-NNN — title

## Contract

- **Class:** `NON_SEMANTIC_TOOLING`
- **State:** `DRAFT`
- **Semantic owner:** binary/governance or engine
- **Executor:** Codex
- **Reviewer:** named authority
- **Runtime behaviour may change:** no

Every CX-019+ implementation task must include exactly one declaration outside code
fences:

- `PYTHON_ORACLE: REQUIRED`, with structured
  `PYTHON_ORACLE_RETENTION_CRITERION:`, `PYTHON_ORACLE_SCOPE:`, and
  `PYTHON_ORACLE_INDEPENDENT_VALUE:` lines;
- `PYTHON_ORACLE: EXISTING_HARNESS_ONLY`, with a
  `PYTHON_ORACLE_HARNESS:` line saying existing O2 coverage stays green/valid and
  that broadening is not authorized; or
- `PYTHON_ORACLE: NOT_REQUIRED`, followed by a short `Reason:` or
  `PYTHON_ORACLE_REASON:` line.

## Goal

One measurable outcome.

## Non-goals

- Explicit exclusions.

## Authoritative inputs

- Files/specifications that define the task.

## Allowed inputs

- Files the executor may inspect.

## Prohibited inputs

- Files or evidence classes the executor must not use.

## Allowed output paths

- Exact files or path prefixes that may change.

## Required behaviour

- Observable properties of the tooling or implementation.

## Acceptance

```bash
# Commands fixed before execution.
```

Expected properties:

- Property one.

## Escalate instead of deciding when

- A semantic, expected-result, profile or architectural choice appears.

## Handoff

Report changed files, commands, results, assumptions, ambiguities and whether
runtime behaviour changed.

## Oracle-scope validator review boundary

`tools/check_oracle_scope.py` is a mechanical path/scope guard. A passing result does
not prove that an `EXISTING_HARNESS_ONLY` change remains semantically inside the
existing O2 capability envelope, nor that `REQUIRED` work satisfies its claimed
independence/retention criterion. Review remains authoritative for those judgments
under DELIB-0008.

Under `EXISTING_HARNESS_ONLY`, the oracle inventory is frozen relative to the task's
frozen base; reclassification requires `REQUIRED` or a dedicated
governance/reclassification task.
