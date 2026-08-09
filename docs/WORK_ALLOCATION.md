# Work allocation and delegated execution

Authority: DELIB-0002 and human approval on 2026-08-06
Status: active for the current mixed research/prototype lineage

## 1. Purpose

Project EGO has three reasoning authorities and may use additional implementation
executors. This policy allocates work according to the decision being made, not
according to the extension of the file being edited or the name of the tool
performing the edit.

A governance task may legitimately modify Python, GDScript, shell, or CI files
when it does not decide gameplay semantics. Conversely, a one-line expected-value
change is semantic work even when it occurs in a test or documentation example.

## 2. Roles

| role | authority | normal work | may not decide |
|---|---|---|---|
| human decision owner | final project policy and contested behaviour | accept deliberations, resolve `T4`, approve exceptions and release gates | nothing, but decisions must be recorded |
| binary/governance side | evidence, necessity, provenance and neutral specification | binary research, public-source comparison, transfer classification, repository policy tooling, address-free specifications and fixtures | engine architecture or unresolved gameplay semantics |
| engine side | runtime semantics and architecture | profile API, gameplay behaviour, implementation design, semantic tests and approval of runtime patches | provenance conclusions unsupported by the evidence record |
| implementation executor | implementation of a bounded frozen contract | sustained repository inspection/edit/test loops, tooling, mechanical changes, test scaffolding, approved specification implementation | new semantic, architectural, profile or expected-result decisions |

Prime Agent, Codex, or another coding agent may occupy the implementation-executor
role. The role is defined by authority, not by product name.

The implementation executor is not a fourth deliberation participant. Its output
is reviewed by the authority that owns the task.

## 3. Task classes

| class | runtime change allowed | semantic authority | required reviewer |
|---|---|---|---|
| `NON_SEMANTIC_TOOLING` | tooling execution only; engine behaviour unchanged | none | binary/governance |
| `COMMENT_OR_METADATA_ONLY` | no executable-token change | none | binary/governance |
| `MECHANICAL_REFACTOR` | yes, but observable behaviour and public API fixed | frozen by existing tests/spec | engine |
| `TEST_SCAFFOLDING` | test structure only; expected outcomes supplied | task owner | specification owner |
| `SPEC_IMPLEMENTATION` | yes, within an accepted address-free specification | specification and API already approved | engine |
| `SEMANTIC_DECISION_REQUIRED` | prohibited as an executor task | unresolved | human or deliberation |

`SEMANTIC_DECISION_REQUIRED` is an escalation result, not an executable queue
item.

## 4. Mandatory task contract

Every delegated task must name:

- task ID and class;
- exact base revision when the task depends on a frozen repository state;
- semantic owner, executor, and reviewer;
- goal and non-goals;
- authoritative inputs;
- allowed and prohibited inputs;
- allowed output paths;
- whether executable behaviour may change;
- acceptance commands and expected properties;
- escalation/stop conditions;
- required handoff summary.

The reusable template is `docs/codex/TASK_TEMPLATE.md`. The `docs/codex/`
namespace is retained for continuity even when Prime Agent or another executor
runs the task.

## 5. Execution rules

1. The semantic owner/reviewer freezes the contract before execution.
2. The executor works against the named base and only inside the allowed scope.
3. For substantial implementation, prefer an isolated worktree so the canonical
   checkout remains available for review and unrelated work.
4. Existing tests may be repaired only when the contract defines the expected
   outcome; otherwise the task escalates.
5. An unexpected API change, semantic ambiguity, profile choice, architectural
   choice, or new expected value stops the task.
6. The executor reports every file changed, relevant validation result, and any
   intentional unresolved boundary.
7. The reviewer checks the complete diff against the contract—not only whether
   tests pass.
8. A task may be split or reclassified, but its class may not be silently raised.
9. Generated reports do not edit binding registries unless the contract
   explicitly authorizes that write.
10. The executor normally leaves a completed implementation at `REVIEW`; `DONE`
    requires independent reviewer acceptance.
11. VCS integration is human/reviewer owned by default. Executors should not
    commit, stage, reset, rebase, push, or create/remove worktrees unless the
    contract explicitly authorizes it.
12. A task is complete only when the queue and task file record the review
    result.

## 6. Validation and inherited debt

Acceptance commands belong in the task contract before implementation.

The common portable validation set is:

```bash
python3 tools/run_godot_tests.py
python3 -m pytest -q
python3 oracle/test_fixtures_current.py
python3 tools/check_deliberations.py
python3 oracle/test_repository_hygiene.py
git diff --check
```

Task-specific tests and non-headless smoke checks may be added where relevant.

Bounded work must not expand into unrelated style cleanup merely because a
touched file has inherited lint debt. When whole-file gdlint already fails at the
frozen base, compare the same touched-file set against that base and require no
new findings unless the task explicitly owns lint cleanup.

Green gates are necessary but not sufficient for semantic acceptance.

## 7. Current mixed-lineage access

In the current repository, an implementation task may inspect research material
only when the contract lists it as an allowed input. This does not create or
imply a clean room; the repository is explicitly the mixed research/prototype
lineage.

Even here, task prompts should prefer the smallest sufficient input set. Raw
Ghidra exports and source-derived material are unnecessary for repository
tooling, mechanical refactors, and public-source fixture work.

The preferred division for broad evidence-backed implementation is:

- binary/governance side: establish evidence, provenance, and address-free rule;
- engine side: freeze semantic/architectural interpretation and acceptance
  criteria;
- implementation executor: carry out the bounded repository edit/test loop;
- engine/human reviewer: inspect and accept before landing.

## 8. Future public-lineage access

At the community-release gate, any implementation executor may receive only:

- the fresh public repository;
- neutral behavioural specifications;
- public/spec tests;
- synthetic fixtures;
- address-free golden vectors;
- public sources permitted by the gate.

It must not receive:

- this mixed repository or its implementation history;
- Ghidra exports, addresses, or function maps;
- private evidence ledgers;
- source-derived material without an explicit licence;
- patches copied from the current prototype.

The public-lineage executor still has no authority to invent semantics.

## 9. Review routing

Use binary/governance review for:

- validators, scanners, and export tooling;
- provenance metadata;
- comments and source-label sanitation;
- task and fixture inventories;
- CI wiring that only runs existing checks.

Use engine review for:

- runtime code;
- public APIs;
- serializers used by engine state;
- refactors of executable paths;
- implementation of accepted gameplay specifications;
- any test whose expected result changes.

Use human review for:

- `T4` choices;
- task-scope exceptions;
- whether a disputed change is truly non-semantic;
- contested architecture or profile policy;
- entry into the public-lineage gate.
