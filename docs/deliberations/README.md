# Cross-agent deliberations

This directory formalizes questions that require independent engine-side and
binary-analysis reasoning before a human decision.

It is deliberately repository-native. The protocol preserves the useful part
of the earlier paired-document process—independent analysis—while adding a
shared brief, structured reconciliation, a canonical decision and a
verification gate.

## Directory layout

```text
docs/deliberations/
  README.md
  _template/
  0001-short-topic/
    brief.md
    position_binary.md
    position_engine.md
    cross_review.md
    decision.md
    status.yaml
```

Use a four-digit sequence followed by a lowercase hyphenated slug.

## Artifact roles

### `brief.md`

Human-owned statement of the question, decision required, constraints and
starting evidence. Both sides receive the same brief.

### `position_binary.md`

Independent analysis from the binary/evidence side. It should separate proven
facts, inferences, implementation obligations and open evidence requests.

### `position_engine.md`

Independent analysis from the engine/implementation side. It should cite
repository behaviour, tests, architectural costs and concrete implementation
risks.

### `cross_review.md`

A reconciliation table, not a third position essay. Each topic is marked:

- `agreed`
- `terminology_only`
- `resolved_after_review`
- `human_decision_required`
- `blocked_on_evidence`

### `decision.md`

The canonical decision record. Use the included MADR-style headings. Position
files remain historical reasoning and do not become specifications by
themselves.

### `status.yaml`

Machine-readable lifecycle and ownership. It intentionally uses a small
dependency-free YAML subset: top-level scalar keys and top-level lists.

## Lifecycle

Allowed states:

```text
draft
independent_review
cross_review
decision_required
decided
implementing
verified
archived
```

Typical progression:

```text
draft
  -> independent_review
  -> cross_review
  -> decision_required
  -> decided
  -> implementing
  -> verified
  -> archived
```

A deliberation may move directly from `cross_review` to `decided` when no human
choice remains beyond accepting the converged result.

## Process

1. A human creates the directory from `_template/` and writes `brief.md`.
2. The two sides write their positions independently.
3. Both sides read the other position and populate `cross_review.md`.
4. Remaining choices are isolated for the human.
5. The human accepts `decision.md`.
6. `status.yaml` names the implementation owner and verification targets.
7. The package becomes `verified` only when its confirmation criteria pass.

## History and supersession

Do not rewrite an accepted decision to make later work appear inevitable.
Minor factual corrections may be appended with a dated note. A material change
gets a new deliberation whose `supersedes` field names the old ID.

Working position documents outside this directory may continue to evolve.
Snapshots stored inside a deliberation package are frozen inputs to that
decision.

## Validation

Run from the repository root:

```bash
python3 tools/check_deliberations.py
```

The validator checks naming, required files, status vocabulary, ID alignment,
decision presence for decided states and verification targets for verified
states. It has no third-party dependencies.
