# Decision record — DELIB-0008

## Status

Accepted by the human project owner on 2026-08-28.

## Context

The Python oracle has grown into a near-complete second tactical engine with a
roughly comparable implementation and test surface to GDScript. Both independent
positions and both reciprocal reviews reject automatic full-engine mirroring as the
default, while retaining the value of independent executable compatibility logic and
selected end-to-end differential scenarios.

See `brief.md`, `position_binary.md`, `position_engine.md`, and `cross_review.md`.

## Decision

Project EGO adopts **Option B: a permanent selective executable oracle**.

### 1. Production-runtime ownership

GDScript is the only complete production runtime by default.

Python remains permanent as an independent compatibility/reference layer, but there
is no standing obligation to implement every production subsystem twice.

### 2. Oracle classes

Python oracle work is classified into four categories:

- **O1 — permanent independent reference kernels**
  - recovered exact arithmetic/truncation/order;
  - RNG/state topology and call-order behavior;
  - legacy parser/import edges;
  - compact high-risk compatibility decisions;
  - independently grounded neutral vector/fixture generation.

- **O2 — curated executable compatibility integration harness**
  - selected end-to-end scenario/log differential execution remains live;
  - the harness may run new scenarios using semantics already inside its supported
    capability envelope;
  - new production features do not automatically expand that envelope;
  - extend the harness only when a compatibility-critical end-to-end interaction is
    materially better protected by executable differential sequencing than by
    focused vectors/local tests.

- **O3 — maintenance-only existing mirror**
  - existing mirrored project/orchestration modules may remain while current
    compatibility coverage depends on them;
  - they stop receiving new feature parity by default;
  - maintain only the behavior required by explicitly retained compatibility
    coverage.

- **O4 — vectors/specification/research only**
  - executable mirroring may be narrowed to committed vectors, properties, traces or
    historical/research artifacts where those preserve the semantic contract.

The current scenario/log dependency graph is an inventory starting point, not a
permanent entitlement to full tactical feature parity.

### 3. Retention criteria

New or expanded executable Python logic requires an explicit justification based on
at least one of:

1. recovered exact arithmetic/order;
2. RNG/state/call topology;
3. legacy parser/import semantics;
4. compact high-risk compatibility decision logic;
5. independently grounded fixture/vector generation;
6. compatibility-critical end-to-end sequencing for which focused vectors/local
   tests are materially weaker;
7. temporary research prototyping, without implying permanent parity.

### 4. Default non-retention

Do not mirror by default:

- generic Scenario/command orchestration outside the declared O2 harness envelope;
- generic mutable state containers;
- campaign/strategic turn orchestration;
- AI planners/controllers;
- economy/progression orchestration;
- EGO-native persistence/migration plumbing;
- UI/presentation;
- package/mod composition architecture;
- plugin/deep-mod hosting;
- generic project-owned context/service plumbing.

A small recovered/high-risk kernel inside any of these systems may independently
qualify for O1/O2.

### 5. Future task-contract rule

Every future implementation task must explicitly declare one of:

- `PYTHON_ORACLE: REQUIRED`
  - cite the retention criterion;
  - name the exact Python kernel/module/test surface;
  - state what independent evidence/value it checks.

- `PYTHON_ORACLE: EXISTING_HARNESS_ONLY`
  - existing curated compatibility scenarios must remain valid;
  - the task does not authorize broadening Python feature scope.

- `PYTHON_ORACLE: NOT_REQUIRED`
  - ordinary project-owned runtime/orchestration or behavior already protected by
    neutral vectors/specification.

Silence is not permission to mirror.

### 6. Mechanical enforcement

Before the next major subsystem, add a lightweight repository/task validator that:

- requires the oracle-scope declaration on future implementation tasks;
- flags new or expanded production `oracle/*.py` work without an explicitly
  justified oracle scope.

The validator must not attempt to infer whether an implementation is genuinely
independent; that remains a review judgment.

### 7. Existing-module transition

Do not launch a wholesale deletion/refactor campaign.

Create a bounded inventory/classification of existing oracle modules using O1–O4.

Executable O3 coverage may leave standing-implementation status only in a dedicated
narrowing/retirement task, not as an incidental side effect of unrelated feature
work.

Such a task must preserve or create distinguishing vectors/traces/properties and
retain provenance for expected artifacts.

### 8. Full-engine application

The decision boundary is semantic, not tactical-versus-strategic.

Examples:

- recovered province-income arithmetic may justify an O1 Python calculator;
- a complete campaign-turn engine normally does not;
- recovered recruitment eligibility may justify focused reference logic;
- the whole strategic content graph normally does not;
- original-format save parsing may qualify if that compatibility goal is later
  adopted;
- EGO-native persistence remains one-runtime by default.

### 9. Fixture/provenance rule

A frozen or retired Python generator does not invalidate a committed expected
artifact, but the artifact must remain traceable to accepted evidence/specification
or a retained historical reference implementation.

GDScript must not become the sole generator and checker of compatibility expectations
that are claimed to be independently grounded.

## Consequences

- Future work no longer mirrors Python by habit.
- The high-value independent reference layer remains permanent.
- Selected end-to-end differential scenarios remain executable without forcing full
  future tactical/strategic parity.
- Existing tactical oracle code remains available while it is classified; no
  deletion campaign is required.
- Campaign/economy/AI/persistence/mod-host architecture will normally be implemented
  once, with focused Python reference kernels where recovered semantics justify them.
- A bounded follow-up governance task must create the initial O1–O4 inventory and
  mechanical oracle-scope guard.
- Original-format persistence compatibility remains an open product question.

## Reconsideration triggers

Reopen this decision if:

- narrowed Python coverage misses concrete compatibility regressions that the former
  live mirror would plausibly have caught;
- systematic evidence shows orchestration-level differential execution has unusually
  high defect-detection value per maintenance cost;
- tooling makes genuinely independent broad mirroring materially cheaper;
- EGO intentionally gains a second production runtime;
- a compatibility target requires full-system differential execution that O1/O2 plus
  vectors cannot adequately provide.
