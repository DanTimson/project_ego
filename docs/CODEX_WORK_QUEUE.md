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
| CX-001 | `NON_SEMANTIC_TOOLING` | validate public-lineage registries | binary/governance | `DONE` | none |
| CX-002 | `NON_SEMANTIC_TOOLING` | inventory unclassified tests and fixtures | binary/governance | `DONE` | none |
| CX-003 | `NON_SEMANTIC_TOOLING` | scan transfer candidates for research-only tokens | binary/governance | `DONE` | none |
| CX-004 | `NON_SEMANTIC_TOOLING` | guard populated generated bindings | binary/governance | `DONE` | none |
| CX-005 | `NON_SEMANTIC_TOOLING` | aggregate public-lineage preflight report | binary/governance | `BLOCKED` | CX-001, CX-003, CX-004 |
| CX-006 | `NON_SEMANTIC_TOOLING` | dry-run public-lineage exporter | binary/governance | `BLOCKED` | CX-001, CX-002, CX-003, CX-005 and explicit manifest |
| CX-007 | `NON_SEMANTIC_TOOLING` | repository-governance CI integration | binary/governance | `BLOCKED` | CX-001 through CX-005 accepted |
| CX-008 | `SPEC_IMPLEMENTATION` | tactical numeric mechanics closure (R3/R6/R8/R9/R10/R11) | engine | `DONE` | accepted R3, R6, R8, R9, R10 and R11 specifications |
| CX-009 | `SPEC_IMPLEMENTATION` | tactical action terminality | engine | `DONE` | CX-008; human-confirmed action-terminal rule |

Task contracts live in `docs/codex/tasks/`.

## Assignment rule

CX-001 through CX-004 are accepted and complete. Their task-local review
records identify the accepted files, commands, results and remaining findings.

CX-005 remains `BLOCKED` in this reconciliation. Its declared dependencies are
now reviewed, but activating it also requires changing its own task-local state;
`docs/codex/tasks/CX-005.md` is deliberately outside this patch's allowed paths.
CX-006 and CX-007 therefore remain blocked as well.

## Engine-directed Codex work

Engine-owned tasks may be added after their semantic contract and reviewer are
named. In particular, DELIB-0003 implementation work must wait until the engine
side defines or accepts the profile API.

No engine task is implicitly authorized by this queue.
