# Binary/governance position — DELIB-0008

## Evidence/governance assessment

No recovered binary fact requires Project EGO to maintain two complete engines.
Binary evidence can require an independent implementation of a *particular*
observable rule, arithmetic edge, RNG sequence, parser behavior or ordering
constraint; it does not imply that Scenario orchestration, campaign state, AI,
content composition, persistence and every future feature must be duplicated in
Python.

The evidentiary value of a second implementation depends on independence. A Python
module derived separately from neutral evidence can catch a GDScript
misimplementation. A Python module ported in the same task from the same design and
using the same intermediate assumptions increasingly tests transcription/parity,
not the underlying semantic claim. That can still be useful, but it is a weaker
benefit and does not justify doubling the whole engine by default.

The permanent artifacts that matter most for clean compatibility governance are:

- source/evidence records;
- address-free semantic reductions;
- neutral deterministic vectors and fixtures;
- independent reference calculators for evidence-sensitive rules;
- distinguishing tests that fail when the production runtime violates the accepted
  semantic contract;
- provenance showing which outputs depend on recovered behavior versus
  project-authored architecture.

None of those require the complete Python Scenario/content/campaign architecture to
remain co-authoritative.

## Recommended position

Adopt **Option B: a permanent selective executable oracle**, with a deliberate
tendency toward Option C for low-risk and project-authored orchestration.

"Permanent oracle" should mean that Project EGO permanently retains an independent
reference/evidence layer. It should **not** mean that every complete production
subsystem must have a Python twin.

### Default future-task rule

A new feature is **GDScript-only by default** unless the task explicitly satisfies
at least one oracle-retention criterion below.

Task contracts must state either:

- `PYTHON_ORACLE_REQUIRED: <criterion and scope>`; or
- `PYTHON_ORACLE_NOT_REQUIRED: project/runtime orchestration or otherwise covered by
  neutral vectors/spec tests`.

Silence must no longer mean "mirror it because previous tasks did."

### Retention criteria

A permanent executable Python implementation is justified when at least one of
these is materially true:

1. **Recovered exact arithmetic/order**
   - integer truncation, clamping, precedence or operation order is compatibility
     sensitive and an independently written calculator can distinguish mistakes.

2. **RNG/topology/state**
   - deterministic stream behavior, call count/order, seed/state transitions or
     profile-specific RNG topology needs an independent executable check.

3. **Recovered parser/import semantics**
   - a legacy format/dialect edge benefits from independent decoding or validation
     rather than trusting one production parser.

4. **Small high-risk semantic decision kernel**
   - a compact lifecycle, selection or compatibility rule is subtle enough that a
     separately derived implementation materially increases confidence.

5. **Neutral fixture/vector generation**
   - Python is a convenient independent producer/checker of committed vectors whose
     expected values come from evidence/specification rather than from GDScript.

6. **Research prototype before ownership is frozen**
   - temporary Python experimentation may be useful while reducing evidence, but it
     does not automatically become a permanent mirrored production module.

Retention is strongest when the Python logic is small, deterministic, independently
derived and directly traceable to evidence or an accepted semantic decision.

### Non-retention criteria

The following should normally **not** receive a new permanent Python twin merely for
parity:

- Scenario/command orchestration;
- generic mutable game-state containers;
- campaign/strategic turn machinery;
- economy/progression systems;
- AI controllers/planners;
- save/load orchestration and migration plumbing;
- UI/presentation;
- package/mod composition architecture;
- plugin/deep-mod hosting infrastructure;
- generic project-authored service/context plumbing;
- broad content catalogues whose semantics are already validated at boundaries.

A small evidence-sensitive kernel inside one of these systems may still meet a
retention criterion; the surrounding subsystem does not thereby become mirrored.

## Existing oracle modules

Do **not** launch a deletion rewrite.

Classify existing modules opportunistically into:

1. `retain_reference` — continue independent executable maintenance;
2. `retain_vectors_only` — preserve fixtures/properties, stop expanding mirrored
   orchestration;
3. `maintenance_only` — keep current compatibility coverage while no new feature
   work is added; retire when a touched feature has equivalent neutral tests;
4. `research_only` — historical/research utility, not a parity obligation.

The classification should happen in a bounded follow-up inventory. Existing tests
remain authoritative only for the semantics they actually distinguish.

When future work touches an existing mirrored orchestration module, the task should
first ask whether the touched behavior meets a retention criterion. If not, prefer
adding/strengthening neutral semantic tests and stop growing the mirror rather than
automatically porting the feature.

## Independence requirements

For retained reference logic:

- derive expected behavior from evidence/accepted semantic specification, not by
  translating the production implementation;
- prefer different implementation structure where practical;
- keep the reference surface smaller than the production subsystem;
- include distinguishing positive/negative/boundary vectors;
- avoid importing production GDScript-derived serialized internals merely to obtain
  parity;
- treat cross-language disagreement as a diagnostic requiring adjudication, not as
  proof that Python is automatically correct.

## Full-engine consequence

This policy should be adopted **before** campaign/economy/AI implementation. Those
systems are large, primarily project-owned and likely to have far less value as
full duplicated engines. Letting the current mirroring habit continue into them
would turn a tactical verification convenience into a long-term two-engine product
commitment.

Current tactical closure does not need to stop while the classification inventory
is prepared.

## Provenance and public lineage

Narrowing the executable oracle does not weaken clean-room governance provided that
the project keeps:

- evidence/source classifications;
- address-free reductions;
- neutral vectors;
- retained independent reference kernels where needed;
- explicit lineage for recovered versus project-authored behavior.

A removed or frozen orchestration mirror must not cause its generated fixture to
become an unexplained authority. Expected outputs must remain tied to a semantic
specification/evidence source or independently retained calculator.

## Risks

### Reduced broad differential coverage

Some port/transcription bugs may no longer be caught by whole-scenario Python/Godot
comparison.

Mitigation: retain a limited number of end-to-end deterministic renderer/scenario
fixtures where useful, but derive their semantic expectations from neutral vectors
and focused invariants rather than requiring the entire future engine to be
implemented twice.

### Production implementation becomes the only executable expression of project policy

This is acceptable for ordinary project-authored orchestration, provided the policy
is documented and tested at boundaries. It is not acceptable for recovered
high-risk kernels that still satisfy retention criteria.

### Opportunistic retirement becomes inconsistent

Mitigation: record the four-way module classification and make every new CX task
declare whether Python oracle work is required.

## Strongest objection

A complete second implementation can catch emergent integration bugs that isolated
vectors cannot, especially where multiple correct local rules interact in a wrong
global order. Shrinking Python too aggressively could trade visible maintenance cost
for hidden compatibility regressions.

The answer is not to discard broad differential scenarios immediately. Preserve
selected high-value end-to-end fixtures during the transition and require explicit
evidence before retiring coverage that has historically caught real divergences.
What should end is the **default obligation to duplicate every future subsystem**.

## Reconsideration triggers

Reopen this decision if:

- selective/vector coverage repeatedly misses compatibility regressions that the
  retained full mirror would have caught;
- automated translation/tooling makes near-complete independent mirroring
  dramatically cheaper without correlating the two implementations;
- Project EGO gains a second production runtime whose independent maintenance is a
  product goal rather than a test oracle;
- a future compatibility target requires full-system executable differential
  behavior that cannot be represented by retained kernels and vectors.
