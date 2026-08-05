# Public-lineage community-release gate

Authority: DELIB-0002
Current state: **not triggered**

The current repository remains the mixed research/prototype lineage. This
checklist becomes operational before the first event that would materially turn
the project into a community implementation project.

## 1. Trigger conditions

The gate must be evaluated before any of the following:

- inviting unrestricted outside implementation contributions;
- presenting the repository as the durable public engine lineage;
- distributing a stable end-user build intended for broad adoption;
- accepting sponsorship, donations or commercial support tied to development;
- asking downstream projects to depend on the engine API;
- moving binary/source-derived research into a contributor-facing workspace.

Ordinary private-scale research, binary analysis and prototype implementation do
not trigger the gate.

## 2. G0 — current research/prototype stage

Required now:

- maintain `PUBLIC_LINEAGE_TRANSFER.csv` for new material artifacts;
- apply the binary necessity gate prospectively;
- keep populated generated bindings uncommitted unless separately decided;
- preserve raw evidence and commit history honestly;
- convert completed binary findings into neutral rules and fixtures where useful.

No migration or history rewrite is required at G0.

## 3. G1 — preparation before the trigger

- [ ] Confirm that the trigger is expected rather than speculative.
- [ ] Freeze a list of candidate transferable code, tests and specifications.
- [ ] Complete or explicitly defer every `T4_DELIBERATE` item.
- [ ] Classify implementation artifacts not yet present in the transfer registry.
- [ ] Classify the test and fixture corpus using `PUBLIC_TEST_TRANSFER.csv`.
- [ ] Separate public/spec fixtures from private differential and raw-evidence fixtures.
- [ ] Replace raw addresses in transferable tests with neutral claim IDs and vectors.
- [ ] Confirm that public documentation is paraphrased rather than copied.
- [ ] Confirm that no original/NH bulk content or populated generated bindings
      are planned for redistribution without permission.

## 4. G2 — freeze the mixed lineage

- [ ] Record the final mixed-lineage commit hash and archive hash.
- [ ] Preserve the full repository history; do not rewrite it to imply independent creation.
- [ ] Mark the repository as research/prototype lineage.
- [ ] Restrict access to `T3_RESEARCH_ONLY` evidence as appropriate.
- [ ] Record forks or public mirrors that cannot be made private.
- [ ] Establish read boundaries for future public-lineage implementers.

## 5. G3 — create the public specification and verification seed

Transfer in this order:

1. public/spec test inventory;
2. synthetic fixtures;
3. address-free golden vectors;
4. neutral behavioural specifications;
5. content schemas and parsers that do not bundle restricted content.

Checks:

- [ ] Every transferred fixture has a public, black-box or neutral-spec basis.
- [ ] Binary-only vectors contain no original control flow, addresses or decompiler names.
- [ ] Public-source quotations have been replaced by factual paraphrase unless
      short quotation is necessary and attributed.
- [ ] Profile-specific expectations name their profile explicitly.
- [ ] The verification corpus can run without access to the research repository.

## 6. G4 — create and populate the fresh implementation lineage

- [ ] Create a fresh repository with no inherited implementation history.
- [ ] Transfer `T0_RETAIN` artifacts after ordinary review.
- [ ] Transfer `T1_SANITIZE` artifacts only after provenance/comment sanitation.
- [ ] Reimplement `T2_REIMPLEMENT` artifacts from neutral specifications and tests.
- [ ] Exclude `T3_RESEARCH_ONLY` artifacts.
- [ ] Resolve every `T4_DELIBERATE` artifact before transfer.
- [ ] Use an architecture selected for the new engine rather than original
      function boundaries.
- [ ] Record specification/test references for each migrated subsystem.
- [ ] Run the transferred verification corpus before accepting new contributions.

## 7. G5 — open community implementation work

- [ ] Publish contributor instructions that prohibit importing raw executable or
      private source-derived material into the public lineage.
- [ ] Require contributors to identify public/spec sources for compatibility rules.
- [ ] Define how observed incompatibilities are escalated back to the research side.
- [ ] Keep binary investigation exceptional and necessity-gated.
- [ ] Keep user-supplied content external unless separately licensed.
- [ ] Record a reconsideration path if a rights holder grants explicit permission.

## 8. Stop conditions

Do not open the public implementation lineage when:

- the test/spec seed is not independently usable;
- unresolved `T4` choices affect foundational architecture;
- `T3` evidence is required by ordinary public-lineage development;
- populated generated data would be redistributed without a decided basis;
- the proposed separation exists only in names while implementers still consume
  raw research artifacts.

A failed gate does not invalidate the current research repository. It means the
project remains at G0/G1 until the boundary can be made operational.
