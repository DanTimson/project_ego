# Position

Engine side, written independently before reading `position_binary.md`, per
`docs/deliberations/README.md`.

## Repository evidence examined

- `docs/deliberations/0003-ruleset-profiles/brief.md`, `status.yaml`
- accepted `DELIB-0001/decision.md`, `DELIB-0002/decision.md`
- `docs/BINARY_REQUESTS.md` — R3 (charge), R4 (legacy RNG), R8 (attack stamina cost)
- `docs/FORMULAS.md` §charge (`004DCD90`), `docs/LEGACY_RNG.md`
- `docs/ARCHITECTURE.md`, `docs/STATUS.md`
- measured: every `steps_this_round` consumer in `oracle/` and `core/`
- measured: profile references in `core/rules/*.gd` and `oracle/`
- measured: the `rng` key in all five committed scenarios

## Framing claim — current selection is single-axis and will not carry six decisions

**Current implementation.** Exactly one profile axis exists, and it is an ad-hoc
scenario key: `"rng": "legacy"` selects `LegacyRng`, anything else (including
absence) selects the named-stream generator
(`oracle/scenario.py` `_make_rng`, `core/battle/scenario.gd`). Measured: **none
of the five committed scenarios sets it**, so every committed fixture exercises
the native path only.

Rules themselves are profile-clean. Measured: **zero** pack or profile
references in any of `core/rules/*.gd`; the two occurrences in
`oracle/combat.py` (lines 137, 166) are comments. DELIB-0001's "keep engine
architecture independent from profile rules" is currently satisfied.

**Recommendation.** Replace the single `rng` key with one explicit
`profile` identity (`genesis`, `new_horizons`, `native`) resolved once at the
composition root, from which every profile-varying rule is derived. Six
decisions cannot each acquire their own scenario key without reintroducing the
"mostly compatible mode whose rules change silently" the brief prohibits — five
independent booleans give thirty-two configurations, only three of which are
coherent.

**Class:** architectural. Engine-owned. No evidence dependency.

---

## Decision 1 — charge

**Current implementation.** The charge bonus is **not implemented at all**. No
consumer applies it in `core/rules/damage.gd` or `oracle/combat.py`. What exists
is the *input to the superseded model*: `steps_this_round`, maintained in
`oracle/turn.py` (lines 113, 152–153, 230–232) and serialised into fixtures.

This matters for the decision. There is no cumulative-charge behaviour to
preserve or migrate — only a counter, and a documented rule
(`docs/FORMULAS.md` §`004DCD90`) that nothing reads.

**Recommended assignment.**

| profile | rule |
|---|---|
| `genesis` | R3 command-entry form: `max(abs(dx) + abs(dy) - 2, 0)` from the tile occupied when the attack command is issued, computed before approach movement, zero when no movement is requested |
| `new_horizons` | **unassigned pending observation** — `status.yaml` already carries "NH charge observation" |
| `native` | may adopt cumulative path length as an explicit, differently-named rule; must not be called charge compatibility |

**Engine note.** R3's split-activation and move-away-and-back consequences fall
out of the command-entry form automatically; they need no special handling.
`steps_this_round` should remain, because R8 keeps it correct for nothing else
in the compatibility profile — it becomes native-only state, and I would not
delete it inside this deliberation.

**Class:** semantic, evidence-closed for `genesis`, evidence-dependent for
`new_horizons`.

---

## Decision 2 — attack stamina cost after restored capacity or split commands

**Current implementation.** Already the R8 rule, on both sides: cost is 2 when
live remaining capacity is strictly below effective speed, else 1
(`oracle/turn.py` `attack_stamina_cost`, `core/battle/action_points.gd`). The
superseded `steps_this_round > 0` discriminator is gone. 144 committed vectors
pin it, each with `steps_this_round` deliberately non-zero so a
movement-history rule fails the fixture.

**Recommended assignment.** `genesis` = live capacity. `native` inherits it
unchanged; the rule is not a quirk but a more coherent model than the one it
replaced, and giving native a different rule here would create divergence with
no benefit. `new_horizons` inherits unless observation contradicts.

**Engine note.** `status.yaml` lists a pending "restored-capacity attack-cost
fixture". The vectors exist; what is absent is a *scenario-level* fixture
exercising Рывок-restored capacity end to end. That is engine work, not a
decision.

**Class:** semantic, evidence-closed. Lowest-risk item in the brief.

---

## Decision 3 — exact legacy RNG versus named native streams

**Current implementation.** The seam exists and is the only general abstraction
DELIB-0001 accepted. `LegacyRng` implements the CRT recurrence, the bounded
adapter and the recovered reseed epochs, verified against every published golden
vector. Named streams remain for native mode and are reclassified in code as
not-legacy-parity.

**The gap is coverage, not capability.** No committed scenario selects legacy, so
the shared-sequence path is exercised only by isolated vectors and one
injection-based test. `STATUS.md` names end-to-end legacy call ordering as
blocker 1, and I agree.

**Recommended assignment.** `genesis` = one shared `LegacyRng` per battle,
including modulo bias and call ordering. `native` = named per-subsystem streams.
These are irreconcilable by construction — one added roll shifts everything
downstream under legacy and nothing under native — which is why this must be a
profile property and not a toggle.

**Human-policy question I cannot settle:** which profile is the **default** when
a scenario names none. Current default is native. Defaulting to native means
compatibility is opt-in and stays under-tested; defaulting to genesis makes
every existing fixture change. I recommend making `profile` **required** in
scenarios rather than defaulted, which converts a silent choice into an explicit
one and satisfies the brief's "explicit in tests, scenarios and saved
configuration".

**Class:** architectural (settled) + human-policy (default/required).

---

## Decision 4 — may scenario units reference canonical content definitions

**Current implementation.** Scenario units declare stats **inline** and use
`name` as presentation with `instance_id` as the battle-local handle
(`oracle/scenario.py`, `core/model/combatant.gd`). `content_id` exists on
`Combatant` and is populated by the roster, but is empty for inline scenario
units. Measured previously and unchanged: committed scenario stats match neither
pack — `skirmish.json` gives Мечник attack 8 where Genesis has 7.

So today a scenario unit is a synthetic combatant, not a content reference, and
labelling one `genesis:unit/5` would assert an identity its inline stats
contradict.

**Recommended assignment.** Profile-independent, and additive: an optional `def`
field naming a canonical content ID, with inline fields acting as explicit
overrides and absence preserving current behaviour exactly. Instance identity
stays separate from both.

**Human-policy question I cannot settle:** a scenario using `def` depends on
pack data, which is never committed, so such a scenario cannot run on a fresh
clone or in CI. Either the committed corpus stays inline-only and `def`
scenarios are local-only, or the test corpus splits into
runs-anywhere/requires-pack tiers. That is a policy choice about the public test
transfer inventory, adjacent to DELIB-0002, and not mine.

**Class:** architectural + human-policy. Not evidence-dependent.

---

## Decision 5 — which observable Genesis quirks deserve preservation

**Recommended criterion**, rather than a list that will go stale: preserve in
`genesis` when the behaviour is **observable in play** and **materially changes
outcomes**; correct it in `native` only when the correction is stated as a
different rule, never as a silent improvement.

Applying it to what is currently implemented:

| behaviour | preserve in `genesis` | `native` may correct |
|---|---|---|
| integer truncation toward zero in the morale step | yes — changes stat values | no; ordering is coherent |
| minimum-one attack clamp, and the paths that skip it (R6) | yes — 24 units have `Attack 0` | no |
| exact-zero stamina defence halving, trunc0, floor-zero (R9) | yes | no |
| modulo bias in the bounded RNG adapter | yes — changes distributions | **yes**, as an explicitly named unbiased adapter |
| shared-sequence RNG ordering | yes | yes — named streams |
| cumulative charge accumulation | **not a quirk** — never original behaviour | may exist as a native rule |

**Engine note.** The last row matters: cumulative charge has been described as a
quirk to preserve or discard, and it is neither. It is a Project EGO invention
that R3 superseded before it was ever implemented.

**Class:** semantic. Evidence-closed for everything listed; the criterion itself
is architectural and engine-owned.

---

## Decision 6 — is DELIB-0001 exact fidelity universal or profile-scoped

**Position: profile-scoped, explicitly.**

DELIB-0001 was decided when one target existed. Two facts since then make
universal fidelity untenable. First, DELIB-0002 established that binary evidence
is necessity-gated and public sources are primary — a universal fidelity mandate
would keep generating binary requests for behaviours no profile needs. Second,
`native` cannot be exactly faithful and also correct the modulo bias, and both
have been accepted as desirable.

Scoping costs little because the architecture is already clean: rules take
inputs and do not branch on profile, so fidelity is a property of which rules a
profile selects, not of the engine.

**Recommended wording:** DELIB-0001's exact-fidelity requirement binds the
`genesis` compatibility profile. Other profiles inherit each rule unless they
name a replacement, and every replacement is recorded as a profile divergence
with its reason.

**Class:** human-policy — it amends an accepted decision, which only the human
decision owner can do.

---

## Risks

1. **A profile identity is cheap to add and expensive to retrofit.** Fixtures,
   scenarios and any future save format all encode it. Deciding it after
   persistence is scoped would be materially more expensive.
2. **Legacy remains under-tested while native is the default.** If the default
   stays native, blocker 1 in `STATUS.md` will not close on its own.
3. **`new_horizons` risks becoming a rules profile by accident.** Today NH is a
   pure content profile with zero rule divergences. The brief forbids assuming
   NH retained or corrected a Genesis quirk without profile-specific evidence; I
   would add that NH should carry **no** rule overrides until observation forces
   one, so the profile does not silently accumulate them.

## Strongest objection to this position

Introducing a `profile` identity now is exactly the premature abstraction
DELIB-0001 argued against, and my own extension probe found that a rule can
already be replaced without one. If the honest answer is that only RNG varies,
then one key is proportionate and a profile identity is over-engineering.

My response: the probe replaced a rule by rebinding a module-level function,
which is process-global and cannot express two profiles at once. And this
deliberation is being asked to assign **five** behaviours, not one. The
abstraction is being demanded by the decisions on the table rather than
anticipated.

## Questions for the other side

1. Does any recovered evidence bear on whether NH altered the charge rule, or is
   the pending NH observation the only route?
2. Is there evidence about whether the reseed epochs differ per profile, or is
   the epoch structure Genesis-specific by construction?
3. Does the necessity gate permit a request whose only purpose is to assign an
   already-recovered behaviour to a profile — or must profile assignment be
   settled by observation and policy alone?

## Changes after cross-review

- NH R8 remains unresolved; the earlier proposed inheritance is withdrawn.
- Adopt the four-part observable, material, neutrally testable and
  profile-supported preservation threshold.
- Unassigned NH rule variants must fail loudly rather than inherit by silence.
- NH RNG inheritance by silence is an unresolved gap.
