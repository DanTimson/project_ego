# Engine-side position: fidelity and modifiability

Paired document. The binary-analysis side maintains its own position file; each
side updates its own and reads the other's. This file records the engine side's
standing view, the evidence behind it, and what remains disputed. It is not a
specification — decisions that become binding move into `ARCHITECTURE.md`,
`FORMULAS.md` or the ledger.

Round 2. Previous round's disagreements that are now settled are listed under
*Resolved*, so the file records movement rather than only current state.

---

## Standing position

**Faithful implementation first, mod-safe seams only where a later change would
be disproportionately expensive, formal mod surface later.**

Both sides converged on this independently, and the engine side has since
narrowed further in response to the binary side's argument. Concretely:

- implement recovered Genesis behaviour exactly — morale arithmetic, charge
  ordering, CRT sequence and topology, status lifecycle, action dispatch;
- keep the existing normalized data layer, which is already working;
- add the RNG substitution seam, and nothing else general;
- defer scripting API, manifests, plugin framework, hot reload, mod tooling, ECS
  migration, universal hook points, and speculative extension points.

A new abstraction should require one of: a real content case that cannot be
represented; duplicated engine logic revealing an actual variation point; an
irreversible concern such as identity or persistence; or a proven conflict such
as legacy/native RNG. Otherwise defer.

---

## What the evidence currently supports

These are measurements against the repository, not design opinion. They are the
reason the engine side stopped arguing for broader mod infrastructure.

**The rules layer is profile-agnostic.** No rule in `core/rules/` or the oracle
branches on pack identity. Opcode integers terminate at
`core/content/ability_registry.gd`, which maps them to handler names; rules never
see a `.var` index or an opcode.

**Two content profiles already traverse the whole pipeline.** Genesis (71 units,
152 upgrades) and New Horizons (291 units, 904 upgrades) both parse, build, and
resolve abilities through identical rule code. Every observed divergence between
them is carried by data. NH is a real 291-unit modification, not a hypothetical.

**Fidelity work has not eroded this.** The morale, charge and RNG findings landed
as leaf functions and one execution property; none of them introduced a
pack-specific branch.

Conclusion the engine side draws: the architecture is not currently overfitted to
Genesis, and the burden of proof is on anyone proposing general mod machinery.

---

## Accepted from the binary side

**Binding scope replaces the engine side's observable/internal split.** The
earlier two-way cut was too coarse. Reference typing and struct layouts are
binding somewhere but not in general runtime rules, and a mechanism that is
internal in origin — shared CRT state — can still be observably binding through
its cross-call consequences. The five-way classification is adopted:

| scope | meaning |
|---|---|
| `legacy_behavior` | reproduced by the Genesis compatibility rules |
| `genesis_import` | honoured while parsing and resolving original content |
| `original_persistence` | matters only for original save/runtime layout compatibility |
| `diagnostic_only` | true of the executable; need not shape engine implementation |
| `unresolved` | the obligation itself is not yet known |

The accompanying **engine obligation** sentence is the part that does the work:
one sentence saying what must be reproduced, if anything. The `×100` internal
representation is the canonical example — `diagnostic_only`, with the obligation
being the truncation point and morale application order, not the scaling.

**RNG seam placement.** Agreed: the boundary belongs at session construction or
the composition root. Rules must not branch on `legacy`/`native`, pack ID, or
subsystem name. The contract stays minimal — `seed`, `next_value`,
`below(bound)` — with Genesis compatibility receiving one shared `LegacyRng`
carrying the MSVC CRT recurrence, the bounded adapter, and the recovered reseed
epochs. Weighted selection remains an ordinary utility over `below()`. Dependency
injection is the goal, not an RNG framework.

---

## Proposed refinement: scope is orthogonal to confidence

`unresolved` should not be used for claims whose *fact* is unknown, only for
claims whose *obligation* is unknown. These are different axes and the ledger
already separates two others (`confidence`, `confirmed_by_observation`).

Worked example — `OPEN_QUESTIONS` item 17, the rounding direction of the negative
morale bonus:

```text
confidence:               inferred   (from the source language, not a read branch)
confirmed_by_observation: no
binding_scope:            legacy_behavior
engine obligation:        Genesis compatibility must reproduce whichever
                          direction the executable uses; the engine currently
                          assumes truncation toward zero.
```

The fact is unknown; the obligation is perfectly clear. Marking this `unresolved`
would lose that, and would let an unknown fact masquerade as an unknown
requirement. Scope should be assignable at the moment a question is *asked*,
usually before it is answered — which is also what makes it cheap.

Practically: `unresolved` should be rare. If a packet cannot assign a scope, that
is usually a sign the claim has not been connected to any consumer yet.

---

## Open disagreement: identity ranks above the RNG seam

The engine side holds this position after the binary side's narrowing, because
the narrowing did not address the evidence.

**Claim.** Stable namespaced identity, with source provenance, should be done
before the RNG seam.

**Evidence.** Content identity is currently the *localized display name*:
`roster.build("Мечник")`. Across the two profiles that exist today, Genesis and
NH share **69 unit names, of which 27 carry different stats** — Громила 14 vs 13
attack, Маг 4 vs 2, Пегас 10 vs 12. The display name is therefore already an
ambiguous key across the project's own content, and it is already load-bearing in
8 source files and 5 committed artifacts (87 references, 54 of them in
`scenario_fixture.json` alone).

**Honest limits of the claim.** There is no live defect today: `test_both_packs`
iterates profiles separately and the Genesis/NH comparison loads each in
isolation, so nothing currently keys across packs. The cost is migration cost,
and it is proportional to committed fixtures and scenarios, which grow every
week. This is a claim about slope, not about a present failure.

**Why it is not mod infrastructure.** This is the point the engine side thinks
got mis-filed. Namespaced identity is not an extension point and grants no
capability to modders. It is a correctness property of a project that already
ships two content profiles, in the same family as the reference-table trap: a
key that resolves to a plausible wrong record rather than failing. Judging it
under "should we add mod machinery now" applies the wrong test.

**It also satisfies the binary side's own criteria.** Their list admits "an
irreversible concern such as stable identity or persistence" as sufficient
grounds. Identity is named explicitly there; the disagreement is only about
whether the trigger has fired. The engine side's evidence says it has.

**Minimal proposal, deliberately smaller than the general case.** Not a mod
identity system:

- add a stable ID alongside the display name, derived from the source record
  index, with the display name demoted to a localization field;
- carry `source_kind`, `source_file`, `source_record_index`, `source_opcode` as
  provenance;
- have lookup accept either form during migration, so fixtures convert
  incrementally rather than in one commit.

Open sub-question, on which the engine side has no strong view: whether IDs are
transliterated (`genesis:unit/swordsman`) or index-based
(`genesis:unit/1`). Index-based is less readable in fixtures and considerably
more stable.

---

## Resolved

- **Whether the project is overfitted to Genesis.** It is not; measured, not
  argued. Both sides accept the NH result as dispositive for the data layer.
- **Whether to build general mod infrastructure now.** No. The engine side
  withdrew the broader version of this after the binary side's argument.
- **Five of six proposed policy interfaces.** Withdrawn by the binary side.
  `MoralePolicy` in particular had no second implementation: the Genesis binary
  and the NH published table agree at every point of the morale curve, so the one
  real modification in existence did not vary it. Only `RngPolicy` survives, and
  it survives as dependency injection rather than as a policy object.
- **Observable vs internal.** Superseded by binding scope.

---

## Standing note on the `.var` importer

Recorded because it affects how importer work is justified, not because it is
disputed. The existing Eador modding community is `.var`-native, and NH is a
291-unit `.var` modification that the project already builds and tests against.
The importer is therefore a primary mod inlet in practice, and its requirement is
*dialect tolerance across content sets*, not Genesis fidelity alone.

The ability-extraction defect is the concrete case: a heuristic tuned on NH data
misread Genesis `Race`/`UnitKind` metadata as ability references, and every
cross-reference check passed because the wrong values resolved to a valid
`unit_upg` record. That was a mod-compatibility failure, not a fidelity failure,
and it was caught only by running real content from both profiles. Importer
robustness earns investment on those grounds.

---

## Engine-side commitments

1. Recovered facts are reproduced exactly where their binding scope says they
   must be, and are not promoted into general engine architecture where it says
   they need not be.
2. New abstractions require a demonstrated second implementation, an
   irreversible concern, or a proven conflict.
3. Fixtures and vectors accompany every recovered rule, in the same change. A
   rule without a vector is not considered landed — the morale rework shipped
   with 144 whole-stat vectors precisely because the previous fixtures all sat at
   neutral morale and would have passed a wrong implementation.
4. Where the engine assumes rather than knows, the assumption is recorded as an
   open question with a stated close condition, not left in a comment.

---

## Round 3 update: identity landed, and one claim corrected

Canonical identity is implemented. `genesis:unit/5`, `genesis:upgrade/76`,
`genesis:ability/53` — pack-qualified, keyed on the source record id, with
display names demoted to localization and provenance carried alongside.

**A correction to this document's own round-2 evidence.** It stated there was no
live defect, only accumulating migration cost. That was wrong, and only because
the check had not been run: New Horizons uses **11 display names for more than
one record in the same pack**. «Паладин» is 22 attack / 55 life at record 57 and
6 attack / 22 life at record 265; «Убийца», «Жрец», «Маг», «Колдун», «Снайпер»
and «Атаман» are the same story. `build("Паладин")` returned whichever record
came first. The cross-pack argument was correct but was not the strongest one
available, and the intra-pack case was a present silent-wrong-answer bug rather
than a future cost.

Ambiguous names now fail loudly in both implementations rather than resolving to
the first match. `coverage()` iterates canonical ids, so it no longer
mis-attributes or under-counts on NH.

**Scenario files were deliberately not migrated,** against the letter of the
agreed task. Scenario units are not content references: they declare stats inline
and use the name as a battle-local handle. `tests/scenarios/skirmish.json` gives
«Мечник» 8 attack where the Genesis pack has 7, and «Ополченец» 12 life / 5
attack where Genesis has 17 / 4 — matching neither profile. Rewriting those names
to `genesis:unit/5` would assert a content identity the inline stats contradict,
which is the opposite of what canonical identity is for. If scenarios should
instantiate from a pack, that is a separate feature: an optional `def` field
naming a canonical id, with the inline stats becoming overrides. Flagged rather
than assumed.
