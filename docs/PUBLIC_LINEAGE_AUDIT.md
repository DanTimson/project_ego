# Public-lineage necessity and transfer audit

Status: **accepted prospective governance under DELIB-0002; living registry**
Opened: 2026-08-06
Scope: current mixed research/prototype repository, completed binary work through
R11, the remaining binary queue, selected engine/oracle implementations, and the
supplied Eadoropedia New Horizons corpus.

This document is an engineering and provenance-control artifact. DELIB-0002
accepts its necessity gate and transfer taxonomy as prospective governance. It
remains a living registry rather than a frozen completeness claim.

It is not a legal opinion, does not claim that the present repository is a
clean-room implementation, and does not by itself authorize redistribution of
third-party text, code, data or assets.

## 1. Operational question

For each rule, binary finding and implementation artifact, determine:

1. whether exact legacy behaviour is materially necessary;
2. whether public documentation or controlled black-box observation can establish
   the needed behaviour without binary-derived implementation detail;
3. whether a difference would noticeably damage gameplay, content compatibility,
   save/data compatibility or deterministic legacy parity;
4. whether current implementation can transfer to a future public lineage,
   requires comment/source sanitization, must be reimplemented from a neutral
   specification, or should remain research-only.

The audit intentionally does **not** ask whether every recovered Genesis detail
can be reproduced. It asks what a competent public reimplementation actually
needs.

## 2. Sources examined

### 2.1 Public black-box/documentation source

Local snapshot:

```text
source candidate: PUB-EADOROPEDIA-NH-26.0620-F01
archive: eadoropedia_nh_26.0620.f01(1).zip
SHA-256: 05b7469fabd539643f9cff8712a40d72dbbefb9e2f6a8a726875e4f1d73906c2
format: generated HTML, data pages and browser-side tools
rights note: publicly accessible corpus; no explicit redistribution licence
             was identified in the supplied archive
```

The snapshot publicly documents, among other things:

- the broad current-attack formula;
- attack randomisation and negative-damage probability;
- stamina attack/speed/defence effects;
- `Неутомимый` preventing current stamina from decreasing through actions;
- broad `Удар и возврат` return-anchor semantics;
- charge placement and the documented legacy coordinate-based charge quirk;
- many ability descriptions, magnitudes and interaction statements.

The corpus may support factual rules, black-box expectations, source comparison
and neutral test vectors. It is not treated as permission to copy its prose,
JavaScript, generated content corpus, images or game text wholesale.

### 2.2 Repository evidence

Primary repository inputs include:

- `docs/PROVENANCE_AND_DATA_POLICY.md`;
- `docs/FORMULAS.md`;
- `docs/BINARY_REQUESTS.md`;
- `docs/OPEN_QUESTIONS.md`;
- `docs/EVIDENCE_LEDGER.csv`;
- `docs/COMPATIBILITY_TEST_MATRIX.md`;
- accepted `DELIB-0001`;
- completed binary requests R1–R9 and R11;
- selected `core/` and `oracle/` implementations listed in
  `PUBLIC_LINEAGE_TRANSFER.csv`.

## 3. Two independent classifications

Evidence confidence, gameplay necessity and transferability are different
questions. A rule may be proven from the executable yet unnecessary to transfer,
or publicly documented yet currently implemented incorrectly.

### 3.1 Necessity class

| class | meaning |
|---|---|
| `N0_PUBLIC` | Public documentation/data and ordinary implementation reasoning are sufficient. Binary evidence may confirm but is not needed by the public lineage. |
| `N1_BLACKBOX` | Behaviour is materially player-observable and can be established with controlled original-game or NH observation. Binary inspection should not be the first method. |
| `N2_EXACT_EDGE` | Several plausible implementations produce materially different outcomes; exact rounding, ordering, trigger or lifecycle semantics may require a sanitized binary-derived rule after public/black-box evidence is exhausted. |
| `N3_INTERNAL` | Internal structure, ABI, helper boundaries, unreachable arithmetic or non-material quirks. Do not transfer as public-engine requirements. |
| `N4_PROFILE` | Observable legacy/build-specific behaviour whose preservation is a profile/governance choice rather than a universal engine requirement. |

### 3.2 Transfer class

| class | meaning |
|---|---|
| `T0_RETAIN` | Conventional project-authored architecture or implementation; suitable for transfer with ordinary review. |
| `T1_SANITIZE` | Behaviour and code shape may remain, but binary-address/decompiler-shaped commentary or unnecessary private provenance must be replaced with public/spec references. |
| `T2_REIMPLEMENT` | Reduce to a neutral rule and tests, then independently rewrite before transfer to a future public lineage. |
| `T3_RESEARCH_ONLY` | Keep only in the mixed/private research lineage. Do not transfer to the public implementation repository. |
| `T4_DELIBERATE` | Transfer treatment depends on an unresolved ruleset/profile or governance decision. |

These labels are planning controls, not conclusions about copyrightability or
liability.

### 3.3 Transfer-evidence fields

`PUBLIC_LINEAGE_TRANSFER.csv` records two additional distinctions:

| field | values | meaning |
|---|---|---|
| `binary_basis_surface` | `none`, `comment_only`, `behavioural_structure`, `research_artifact`, `generated_content`, `mixed` | Where binary-derived knowledge appears in the current artifact. A source citation in a comment is substantially cheaper to sanitize than rule-specific control flow or a research document containing addresses and reductions. |
| `public_basis_sufficient` | `yes`, `no`, `partial`, `conditional` | Whether public documentation/data alone is sufficient to restate the transferable rule at the precision required by the engine. Independent binary confirmation may remain valuable evidence even when this field is `yes`. |

These fields refine transfer cost without changing the `T0`–`T4` decision.

## 4. Necessity gate for future binary work

This gate applies prospectively. It does not retroactively invalidate closed
requests or downgrade cross-source confirmation already recorded in the evidence
ledger.

A new binary request should proceed only if all of the following are true:

1. **Observable:** a player, scenario, content pack, save or deterministic parity
   target can observe the difference.
2. **Material:** the difference can reasonably alter an action, outcome,
   persistent state, compatibility result or recurring AI decision.
3. **Unresolved at required precision:** Eadoropedia, public forum material, data
   files, existing fixtures and controlled black-box observation do not settle
   the question to the precision the engine needs. A published table that omits
   integer rounding, trigger order or lifecycle boundaries does not settle those
   details.
4. **Ambiguous:** at least two reasonable implementations produce different
   material results.
5. **Reducible:** the result can be exported as a neutral behavioural rule or
   finite test vector without transferring original control flow.

Failure of any gate normally closes or reframes the binary request rather than
expanding it.

## 5. Preliminary implementation findings

The binding per-artifact registry is `PUBLIC_LINEAGE_TRANSFER.csv`. The following
are the highest-priority findings.

### 5.1 Resolved correctness issue: stamina penalty exemption

The initial audit found that `core/rules/stamina.gd` and `oracle/combat.py`
incorrectly made `Неутомимый` bypass low-stamina penalties. Two additional
helpers, `Stamina.speed_penalty` and `Stamina.is_exhausted`, contained the same
wrong exemption but had no call sites.

The engine side corrected all four sites during independent review. Attack,
speed, exhaustion and defence consequences now derive from the live stamina
value. The correct modifier-`0x12` gates at stamina-mutation sites remain
unchanged, and the oracle test now asserts the recovered rule.

The neutral transferable rule is:

```text
Effective modifier 0x12 gates stamina mutation sites only.
Low- and zero-stamina consequences are determined from the live stamina value
and do not independently test modifier 0x12.
```

The current conventional implementations are therefore reclassified from an
immediate `T2_REIMPLEMENT` defect to `T1_SANITIZE`: retain their ordinary code
shape, transfer public/spec tests, and replace private binary-address provenance
where necessary.

The seventeen-site consumer inventory, addresses and duplicated Genesis control
flow remain research evidence, not public implementation requirements.

### 5.2 Publicly specified combat core

The following broad behaviours are already public-source-supported and should
not depend on binary provenance in a future lineage:

- additive attack bonuses before stamina, morale and wound modifiers;
- stamina, morale and wound curves;
- random attack range;
- negative-damage/chip probability;
- defence halving at zero stamina;
- broad `Неутомимый` stamina-mutation immunity.

Current conventional implementations may generally be retained or sanitized.

Exact intermediate truncation, early-return boundaries and provider cut-offs are
separate `N2_EXACT_EDGE` or `N3_INTERNAL` items. They should not cause the broad
public formula to be labelled binary-derived.

The R10 precheck is now closed. Eadoropedia establishes that morale does not
scale `Сокрушение зла`; the already archived `EXP-R9-001` body establishes the
remaining exact edge without new extraction. The qualifying contribution is
added after effective attack/counterattack and after the selected ordinary-attack
1.5× branch, but before attack randomisation and defence/resistance resolution.
This is an `N2_EXACT_EDGE` reduced to an address-free rule and finite vectors;
the current conventional generic placement may remain `T1_SANITIZE`.

### 5.3 Charge is a ruleset/profile question, not an architecture mandate

The supplied Eadoropedia mechanics page itself documents the legacy
coordinate-based charge calculation and calls out its inaccurate cell count.
Current `oracle/turn.py` instead describes `steps_this_round` as cumulative path
length feeding charge.

This is a real semantic divergence, but it does not justify transferring
Genesis's internal coordinate implementation as a universal engine rule. It is
marked `N4_PROFILE / T4_DELIBERATE`.

A later deliberation should decide whether:

- Genesis compatibility preserves the documented legacy quirk;
- NH compatibility follows a separately verified NH rule;
- a native/corrected profile uses intuitive path-distance semantics.

Until that decision, cumulative movement must not be described as established
Genesis behaviour.

### 5.4 Attack stamina cost contains a narrow public-versus-binary edge

Eadoropedia describes the ordinary rule as two stamina after moving and one
while stationary. R8 found that the executor actually compares live remaining
capacity against effective speed. These agree during ordinary play and diverge
after capacity restoration or unusual command sequencing.

This is not a reason to transfer the original comparison structure everywhere.
It is a narrow `N2_EXACT_EDGE / N4_PROFILE` case:

- create a minimal black-box fixture involving movement, capacity restoration,
  reselection and attack;
- measure whether the divergence is materially reachable in Genesis and NH;
- decide whether exact legacy preservation belongs only to a compatibility
  profile.

### 5.5 Lifecycle boundaries remain high-value

R12 and R13 survive the necessity audit in narrowed form.

Public text establishes:

- `Удар и возврат` returns to the tile from which movement began;
- `Прилив сил` restores stamina each turn.

It does not necessarily settle:

- whether the return anchor is captured at round start, first selection, command
  entry or movement start under free re-entry and extra turns;
- whether "start of turn" means round start, side phase, activation, reselection
  or an extra-turn refresh;
- expiry/tick order relative to forced rest, retaliation and additional actions.

These can visibly alter frequent gameplay and should be tested black-box first.
Binary inspection is justified only for a remaining inaccessible ambiguity.

### 5.6 Whole dispatcher reconstruction fails the necessity gate

R16 as a request to reconstruct the complete eight-clause action dispatcher is
mostly `N3_INTERNAL / T3_RESEARCH_ONLY`.

The public engine needs a finite catalogue of:

- action kinds;
- target legality;
- resource costs;
- observable state transitions;
- trigger order where order is material;
- profile-specific differences.

It does not need the same switch table, numeric grouping, function decomposition
or decompiler-shaped dispatcher. R16 should be replaced by a coverage matrix of
unimplemented or ambiguous player-facing action semantics.

### 5.7 Melee secondary processing should become a finite interaction matrix

R17 remains useful only after reduction. Do not reconstruct the monolithic
processor as an implementation target.

Retain questions such as:

- hit versus positive-damage versus kill triggers;
- effect owner and target;
- zero-damage triggering;
- resistance and immunity;
- order relative to retaliation, return, death and tile occupation;
- ordering only where two effects are non-commutative.

Each surviving question should have a concrete public description, black-box
fixture or material ambiguity. Everything else is research-only structure.

### 5.8 Exact legacy RNG is optional-profile compatibility work

The MSVC CRT recurrence is public. The recovered bounded adapter, bound-one
consumption, shared call topology and reseed epochs are exact Genesis parity
facts.

They matter for replay/differential parity, but not for a generally good engine.
`LegacyRng` is therefore `N4_PROFILE / T2_REIMPLEMENT`: retain its neutral
contract and golden vectors, but rewrite from an address-free specification
before a future public-lineage transfer. Native named-stream RNG remains a
separate project-authored mode.

## 6. Remaining binary queue after the audit

| request | audit result | next action |
|---|---|---|
| R10 conditional attack-bonus placement | `CLOSED / N2_EXACT_EDGE` | Public material established the morale carve-out; existing `EXP-R9-001` already proved the remaining placement. Export neutral vectors; no new binary packet. |
| R12 hit-and-return anchor | `N1_BLACKBOX`, possibly `N2_EXACT_EDGE` | Observation protocol ready: NH Harpy `/31`, same-phase reselection and Warlord-granted second turn; no binary packet unless a decisive case is unreachable. |
| R13 start-of-turn lifecycle | `N1_BLACKBOX` and high materiality | Observation protocol ready: NH Wind Seeker `/122` supplies a +2 start effect and Warlord `/111` supplies a direct +2 plus second-turn control; binary only for an inaccessible remaining boundary. |
| R16 action dispatcher | mostly `N3_INTERNAL` | Retire as whole-function reconstruction. Replace with player-facing action-semantics coverage matrix. |
| R17 melee secondary effects | selective `N2_EXACT_EDGE` | Replace with finite trigger/order matrix; inspect only unresolved material cells. |

Broad binary progression should pause until this triage is accepted or amended.

## 7. Rewrite timing

A `T2_REIMPLEMENT` label does not require immediate deletion from the current
mixed repository.

Rewrite now when:

- current behaviour contradicts established requirements;
- binary-shaped structure is spreading into additional subsystems;
- two maintained implementations or the oracle and port disagree about the rule;
- the neutral specification is already stable;
- postponement would make later separation significantly more expensive.

Defer until the public-lineage gate when:

- current prototype behaviour is useful for research;
- exact rules/profile policy remains unresolved;
- a rewrite would be discarded during near-term architectural changes;
- the artifact can remain isolated and clearly marked.

Do not rewrite Git history or claim that a later rewrite retroactively made the
current lineage clean. Preserve provenance truthfully.

## 8. Proposed public-lineage gate

Before unrestricted community implementation contributions, stable public
distribution, sponsorship or other project-scale expansion:

1. freeze the mixed research/prototype lineage;
2. preserve its history and evidence rather than cosmetically erasing it;
3. make research-only binary/source materials private where appropriate;
4. resolve `T4_DELIBERATE` items into named ruleset profiles;
5. classify and transfer the public/spec test corpus, synthetic fixtures and
   address-free golden vectors before rewriting implementation code;
6. export address-free behavioural specifications;
7. create a fresh public implementation lineage;
8. transfer `T0`, sanitize `T1`, independently rewrite `T2`, and exclude `T3`;
9. record claim-level provenance for transferred rules;
10. keep original/NH content external and user-supplied unless separately
    licensed;
11. reconsider the boundary if explicit source/data licences are obtained.

The gate and rewrite policy require cross-agent and human acceptance through
`DELIB-0002`.

## 9. Follow-up deliberation

After the lineage boundary is decided, open a separate ruleset deliberation for
legacy fidelity versus NH/native correction. It should cover at minimum:

- charge semantics;
- attack stamina cost after capacity restoration;
- exact legacy RNG;
- whether scenario units may name a canonical content definition;
- which observable Genesis quirks deserve a compatibility profile;
- whether DELIB-0001's exact-fidelity target applies universally or only inside
  an explicit legacy profile.

Keeping this separate prevents provenance governance and game-design policy from
being collapsed into one decision.
