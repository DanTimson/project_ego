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
| CX-010 | `SPEC_IMPLEMENTATION` | runtime status container and stable status semantics | engine | `DONE` | CX-009; stable status architecture; R13 lifecycle excluded |
| CX-011 | `SPEC_IMPLEMENTATION` | tactical death lifecycle and control transfer | engine | `DONE` | CX-010; mandatory tactical tranche implemented; strategy/corpse/reward/kill-credit/R17 boundaries excluded |
| CX-012 | `SPEC_IMPLEMENTATION` | ranged damage branch parity closure | engine | `DONE` | CX-011; DAMAGE-RANGED-001 plus one-shot channel integration accepted; two-shot producer and DAMAGE-MORALE deferred |
| CX-013 | `SPEC_IMPLEMENTATION` | typed unit-action execution-plan foundation | engine | `DONE` | CX-012; engine-native plan layer + Crushing Blow/Shield Bash accepted; final substantial pre-0.2 tranche |
| CX-014 | `SPEC_IMPLEMENTATION` | declarative data-defined action plans v1 | engine | `DONE` | CX-013; DELIB-0004 decided; A-F pass in Python/GDScript; awaiting engine/human acceptance |
| CX-015 | `SPEC_IMPLEMENTATION` | typed tactical capability restrictions | engine | `DONE` | CX-014; DELIB-0006 accepted; AD-2 architecture resolved; legacy restriction-id binding excluded |
| CX-016 | `SPEC_IMPLEMENTATION` | profile-qualified Genesis death replacement | engine | `DONE` | CX-015; DELIB-0007 accepted; AD-4 architecture resolved; RS-1/NH replacement and custom tier maps excluded |
| CX-017 | `ARCHITECTURE_IMPLEMENTATION` | semantic modifier binding boundary v1 | engine/content | `DONE` | accepted legacy-boundary inventory/review; migrates only 0x12/0x26/0x13 query authority |

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

## Post-0.2 audit disposition

`docs/AUDIT_LEDGER.csv` is the canonical governance record for IR/AD/GV/PV/CL/RS
findings. The post-0.2 remediation/resume gate is closed: AD-3 and CL-1 are
implemented and review-accepted, while DELIB-0004 through DELIB-0007 record the
accepted architecture decisions. AD-1 implementation remains separately fenced;
AD-2 is review-accepted through CX-015, while AD-4 is implemented awaiting review
through CX-016; PV-1 remains
provenance-held; RS-1 remains deferred. CX-008 through CX-015 are `DONE`; CX-016 and CX-017 are `REVIEW`.
CX-015 does not claim raw legacy restriction-ID binding, casting-command
implementation, status lifecycle changes, or AD-1 provider aggregation. CX-016
does not claim NH replacement semantics or custom tier maps.
