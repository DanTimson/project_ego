# Codex work queue

Status: active
Policy: `WORK_ALLOCATION.md`

Codex is a bounded executor. Queue order indicates readiness, not semantic
priority.

## States

- `DRAFT` — contract incomplete;
- `READY` — may be assigned;
- `ASSIGNED` — executor has the frozen contract;
- `IN_PROGRESS` — implementation underway;
- `REVIEW` — patch returned to the named reviewer;
- `BLOCKED` — dependency or decision missing;
- `DONE` — reviewer accepted and validation passed;
- `CANCELLED` — task intentionally withdrawn.

## Queue

| ID | class | title | owner/reviewer | state | dependencies |
|---|---|---|---|---|---|
| CX-001 | `NON_SEMANTIC_TOOLING` | validate public-lineage registries | binary/governance | `REVIEW` | none |
| CX-002 | `NON_SEMANTIC_TOOLING` | inventory unclassified tests and fixtures | binary/governance | `READY` | none |
| CX-003 | `NON_SEMANTIC_TOOLING` | scan transfer candidates for research-only tokens | binary/governance | `READY` | none |
| CX-004 | `NON_SEMANTIC_TOOLING` | guard populated generated bindings | binary/governance | `READY` | none |
| CX-005 | `NON_SEMANTIC_TOOLING` | aggregate public-lineage preflight report | binary/governance | `BLOCKED` | CX-001, CX-003, CX-004 |
| CX-006 | `NON_SEMANTIC_TOOLING` | dry-run public-lineage exporter | binary/governance | `BLOCKED` | CX-001, CX-002, CX-003, CX-005 and explicit manifest |
| CX-007 | `NON_SEMANTIC_TOOLING` | repository-governance CI integration | binary/governance | `BLOCKED` | CX-001 through CX-005 accepted |

Task contracts live in `docs/codex/tasks/`.

## Assignment rule

The first assignment should be CX-001. CX-002 through CX-004 may proceed in
parallel only when each receives a separate worktree or branch and returns an
independent patch.

Do not combine the first four tasks into one broad “implement the governance
tooling” prompt. Separate contracts keep review and rollback cheap.

## Engine-directed Codex work

Engine-owned tasks may be added after their semantic contract and reviewer are
named. In particular, DELIB-0003 implementation work must wait until the engine
side defines or accepts the profile API.

No engine task is implicitly authorized by this queue.
