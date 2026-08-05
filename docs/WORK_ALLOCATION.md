# Work allocation and delegated execution

Authority: DELIB-0002 and human approval on 2026-08-06
Status: active for the current mixed research/prototype lineage

## 1. Purpose

Project EGO has three reasoning authorities and may use additional coding
executors. This policy allocates work according to the decision being made, not
according to the extension of the file being edited.

A governance task may legitimately modify Python, GDScript, shell or CI files
when it does not decide gameplay semantics. Conversely, a one-line expected-value
change is semantic work even when it occurs in a test or documentation example.

## 2. Roles

| role | authority | normal work | may not decide |
|---|---|---|---|
| human decision owner | final project policy and contested behaviour | accept deliberations, resolve `T4`, approve exceptions and release gates | nothing, but decisions must be recorded |
| binary/governance side | evidence, necessity, provenance and neutral specification | binary research, public-source comparison, transfer classification, repository policy tooling, address-free specifications and fixtures | engine architecture or unresolved gameplay semantics |
| engine side | runtime semantics and architecture | profile API, gameplay behaviour, implementation design, semantic tests and approval of runtime patches | provenance conclusions unsupported by the evidence record |
| Codex executor | implementation of a bounded contract | tooling, mechanical changes, test scaffolding and approved specification implementation | new semantic, architectural, profile or expected-result decisions |

Codex is not a fourth deliberation participant. Its output is reviewed by the
authority that owns the task.

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
- semantic owner, executor and reviewer;
- goal and non-goals;
- authoritative inputs;
- allowed and prohibited inputs;
- allowed output paths;
- whether executable behaviour may change;
- acceptance commands and expected properties;
- escalation conditions;
- required handoff summary.

The reusable template is `docs/codex/TASK_TEMPLATE.md`.

## 5. Execution rules

1. The reviewer freezes the contract before execution.
2. The executor works only inside the allowed paths.
3. Existing tests may be repaired only when the contract defines the expected
   outcome; otherwise the task escalates.
4. An unexpected API change, semantic ambiguity or new expected value stops the
   task.
5. The executor reports every file changed and every command run.
6. The reviewer checks both the diff and the contract—not only whether tests pass.
7. A task may be split or reclassified, but its class may not be silently raised.
8. Generated reports do not edit binding registries unless the contract
   explicitly authorizes that write.
9. A task is complete only when the queue and task file record the review result.

## 6. Current mixed-lineage access

In the current repository, a Codex task may inspect research material only when
the contract lists it as an allowed input. This does not create or imply a clean
room; the repository is explicitly the mixed research/prototype lineage.

Even here, task prompts should prefer the smallest sufficient input set. Raw
Ghidra exports and source-derived material are unnecessary for repository
tooling, mechanical refactors and public-source fixture work.

## 7. Future public-lineage access

At the community-release gate, Codex or any other implementation executor may
receive only:

- the fresh public repository;
- neutral behavioural specifications;
- public/spec tests;
- synthetic fixtures;
- address-free golden vectors;
- public sources permitted by the gate.

It must not receive:

- this mixed repository or its implementation history;
- Ghidra exports, addresses or function maps;
- private evidence ledgers;
- source-derived material without an explicit licence;
- patches copied from the current prototype.

The public-lineage executor still has no authority to invent semantics.

## 8. Review routing

Use binary/governance review for:

- validators, scanners and export tooling;
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
- entry into the public-lineage gate.
