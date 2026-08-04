# Preserve exact compatibility behind narrow, evidence-driven seams

## Status

Accepted

## Context

Project EGO must reproduce Eador: Genesis behaviour while remaining usable for
New Horizons and future `.var` modifications. The risk is not fidelity itself;
it is allowing facts about the original executable, source tables or runtime
layouts to become universal engine architecture without a demonstrated need.

Genesis and New Horizons already traverse the same normalized, pack-agnostic
rules pipeline. The deliberation therefore focused on irreversible correctness
issues and proven variation points rather than speculative mod APIs.

## Decision drivers

- Exact Genesis mechanics and call ordering remain compatibility targets.
- New Horizons is an existing large `.var` modification, not a hypothetical
  future consumer.
- Localized names already collide and can resolve to plausible wrong records.
- R4 proves a global incompatibility between Genesis shared-CRT call order and
  independently named native streams.
- Public extension points designed before a real consumer are likely to be
  misplaced.
- Binary evidence must distinguish what is true of the executable from what the
  engine is obligated to reproduce.

## Considered options

### Encode Genesis structures and quirks directly into the universal engine

Rejected. It would make source indexes, fixed arrays, CRT storage details and
other implementation accidents part of the normalized model.

### Build a broad mod platform now

Rejected. Scripting, plugins, hot reload, manifests, editors and generalized
rule hooks do not yet have concrete consumers.

### Faithful implementation with narrow, proven seams

Accepted.

## Decision

1. **Binding scope**
   - Every important evidence claim states where Project EGO must honour it:
     `legacy_behavior`, `eador_var_import`, `original_persistence`,
     `diagnostic_only`, or `unresolved`.
   - Confidence, observation status and binding scope remain independent axes.
   - Claims include a one-sentence engine obligation.

2. **Stable content identity**
   - Imported content uses pack-qualified, source-record-based IDs such as
     `genesis:unit/5`.
   - Display names are localization/presentation fields, not canonical keys.
   - Imported definitions retain source provenance.
   - Name lookup is transitional, pack-scoped and must reject ambiguity.

3. **`.var` importer**
   - The importer is a first-class mod inlet for Eador content.
   - It must tolerate dialect differences across Genesis, New Horizons and
     future `.var` packs.
   - Source conventions are normalized before rules consume them.

4. **Randomness**
   - Genesis compatibility uses one shared `LegacyRng` implementing the
     recovered CRT sequence, bounded adapter, call order and reseed epochs.
   - Rules receive randomness through one minimal injected boundary.
   - No pack or mode branch is added inside rule functions.
   - Independently named streams remain a non-legacy/native facility.

5. **No speculative policy layer**
   - Do not add separate morale, charge, counterattack, effect-dispatch or
     turn-structure policy interfaces without a demonstrated second
     implementation or invasive duplication.

6. **Identity layers**
   - Content-definition identity, battle-instance identity and display name are
     distinct.
   - A future scenario format may use `instance_id`, optional `content_id`, and
     `display_name`; existing inline synthetic scenarios are not silently
     reclassified as pack content.

7. **Empirical extension probe**
   - Before designing a public mod API, attempt one altered rule, one genuinely
     new action and one ID-based save/load round trip.
   - Add only abstractions that those concrete cases prove necessary.

## Rejected proposals

- Public scripting API now
- Plugin framework now
- Hot reload now
- Generalized hook system
- Universal policy objects for every recovered mechanic
- A separate “proper” mod format designed over the existing `.var` ecosystem
- Making original struct layouts or ×100 temporary arithmetic binding engine
  representations

## Consequences

### Positive

- Binary work can continue at full precision without silently dictating engine
  architecture.
- Genesis parity remains exact where behaviour and ordering are binding.
- Existing `.var` mod content remains a primary supported path.
- Identity and RNG migration costs are addressed before they spread further.
- Future abstractions are justified by concrete failure points.

### Negative

- Some future mod mechanics may require refactoring when a real second
  implementation appears.
- Legacy RNG remains globally call-order-sensitive by design.
- The importer must carry source-specific dialect knowledge.
- The project maintains separate compatibility and native randomness semantics.

## Work allocation

- **Engine side:** canonical identity propagation, `LegacyRng` integration,
  importer regressions, scenario instance identity and the empirical extension
  probe.
- **Binary side:** evidence extraction, binding-scope classification, exact
  compatibility vectors and focused answers to implementation ambiguities.
- **Human:** accept decisions, resolve genuine remaining disputes and control
  scope.

## Confirmation

- Canonical content IDs distinguish same-named records and ambiguous name lookup
  fails loudly.
- Genesis and New Horizons still traverse one normalized rules pipeline.
- `LegacyRng` passes raw, bounded, weighted and reseed vectors.
- At least one end-to-end compatibility path uses the injected shared legacy
  state.
- Scenario evolution does not conflate content IDs with battle-instance IDs.
- The altered-rule/new-action/save-round-trip probe is completed before a
  public extension API is designed.

## Reconsideration triggers

- A real mod requires a mechanic that cannot be expressed without invasive
  rule edits.
- A second implementation demonstrates a stable policy variation point.
- Original save compatibility becomes a committed target.
- `.var` dialect evidence invalidates the current source-record identity model.
- End-to-end RNG traces reveal an additional state owner or reseed boundary.
