# Status — Project EGO

This is a coverage map, not a release claim.

| subsystem | evidence | Python oracle | GDScript core | parity status |
|---|---|---|---|---|
| attack randomisation and chip damage | published tables + binary | implemented with native stream model | native + `LegacyRng` vector-tested | exact CRT generator and adapters implemented in isolation; end-to-end legacy call ordering pending |
| stamina and wound multipliers | published tables + binary; R11 complete `0x12` consumer audit | implemented | implemented | low-stamina penalties recovered; implemented tactical stamina mutation sites locally suppress writes under effective modifier `0x12` |
| effective ordinary/ranged defence | Genesis binary `004D0820`/`004D06B0` | implemented | implemented | R9 fixture-covered: all providers precede exact-zero-stamina trunc0 halving and final floor-zero clamp; provider sets remain distinct |
| morale attack multiplier | Genesis binary + independent NH table | implemented + binary fixture | implemented | full curve and signed rounding recovered; R6 early-provider cutoff and distinct melee/counter minimum handling are fixture-covered |
| modifier pipeline | docs, data, binary providers | implemented in part | implemented in part | R10 numeric placement is fixture-covered after effective-stat/selected 1.5× processing and before randomisation/defence; target applicability and wider provider coverage remain incomplete |
| activated actions | public/data families + selective binary edges | typed plan execution for Crushing Blow and Shield Bash | typed plan execution for Crushing Blow and Shield Bash | source ID → canonical `Action` → recipe → immutable ordered plan → shared primitive is implemented; the other twelve catalogue actions and generic battle effects remain unsupported |
| runtime statuses | public/project stable policy + unresolved binary lifecycle | stable container, stacking/resistance and explicit manipulation implemented | first-class `Status` model integrated through `Combatant`, later modifier providers and scenarios | stable container/parity fixture implemented; automatic duration tick/expiry and `UNTIL_NEXT_TURN` clock remain open pending R13 |
| level-up selection | data + binary | implemented in part | `core/model/option.gd` and `tests/test_options.gd` empty | ordinary selection is specified; R15 zero-total/underfull edge deferred until an executable consumer and fixture exist |
| battlefield coordinates and adjacency | binary + controlled observation | implemented | implemented | adjacency recovered; R14 large-unit logical-footprint protocol ready |
| pathfinding and occupancy | Project EGO design + observations | implemented | implemented | tie-break tests present |
| round/side control | binary `004EC4C0`/`004E6530`/`004E0280`/`004DE2B0`; owner-confirmed terminality | implemented | implemented | whole-side phases and pre-action capacity-preserving reselection remain; successful consuming commands close only their actor's activation; explicit order fixture still needed |
| melee execution | binary | partial compatibility model | counterattack path plus tactical fatal lifecycle implemented | EXP-CI11 fatal-event sequencing distinguishes first-strike survival from fatal-primary retaliation suppression; R17 secondary ordering remains excluded |
| ranged execution | binary | partial compatibility model | partial | one-shot `cmd_shoot`, exact ranged early-provider zero cutoff, live-capacity R8 stamina selection, CX-009 terminality and central fatal lifecycle routing are implemented; Extra Shot/two-shot action execution and special modes remain incomplete |
| damage channels and death | binary | implemented tactical lifecycle + ranged calculator | implemented tactical lifecycle + ranged calculator | CX-012 covers exact `0x1C` resistance/channel-2, `0x5F`, `0x11`, `0x4D` and non-`0x1C` `0x3C` routing through the CX-011 sink; lifecycle parity remains covered; large-hit morale delta/`0x19`, hero-wide cohort, strategy writeback, corpses, rewards and R17 remain outside this tranche |
| battle actions and target legality | public/data descriptions + selective binary evidence | adjacent enemy legality, exclusions and mutation-free refusal implemented for two unit actions | matching implementation | canonical typed unit-action command is covered; R16 stays retired and generic battle-action effects remain separate/unimplemented |
| battlefield generation from terrain data | `.var` documentation | partial | model supports tiles | generator not complete |
| scenario format and traces | Project EGO design | inline and canonical-definition units implemented | inline and canonical-definition units implemented | portable synthetic parity fixture covers provenance, merge and identity |
| content packs and bindings | data analysis | implemented; `ContentDb` is a scenario provider | implemented; `ContentDb` is a scenario provider | canonical content ID, battle-instance ID and display name remain separate; actual content requires a verified local pack snapshot |
| `.var` lexical parser | binary | tools exist | n/a | record schemas incomplete |
| unit upkeep/recruitment | binary | not normalized | not implemented | evidence available |
| province income/economy | binary | not normalized | not implemented | evidence available |
| tactical AI scoring | decompilation corpus | not consolidated | scaffold only | deferred |
| presentation | Project EGO Slice-3 contract + direct local visual inspection | n/a | playable hot-seat scene with layered field, inward facing, shadows, categorized ignored assets, and narrow tactical panel | real textured field/right panel and full authored fallback GUI-smoked; structural resemblance only, not original parity |

## Playable tactical slice and Milestone 0.1.1 release shell

Ordinary project play now opens the Milestone 0.1.1 demo menu; **Play Demo** enters
the accepted Tactical Visual Slice 3. Developers can still launch
`game/tactical/tactical_main.tscn` directly. The menu adds no battle semantics.

The tracked Windows x86-64 export preset and `tools/build_demo.py` establish a
tracked-HEAD-only public/private packaging pipeline. Public output is fallback
only. Private output adds an exact, validated mapping-reference closure under
executable-adjacent `local_assets/` while reusing byte-identical executable/PCK
payloads. Metadata and hygiene are external package gates. See
`docs/DEMO_RELEASE.md`.

Tactical Slice 3 preserves the synthetic 8×5 hot-seat battle, authoritative structured command
boundary, and placeholder-only fresh-clone behavior. Presentation now uses a
stable terrain/variation/decoration/grid/shadow/unit/overlay order. Direct
inspection established a naturally rightward `Units` set: the left deployment
keeps it and the right deployment is mirrored as render state. Health and target
rings are not mirrored, and coordinate hit-testing remains adapter-based.

The optional real path was exercised against clean EGOgrabber revision
`ca2df7001427266c07201cb22569d32a663f77e0` and the explicit local DAT corpus.
The ignored index held 1,953 namespaced objects (1,940 images) from `Units`, both
shadow archives, `Unit_icons`, `Battlefield`, `Nature`, `Interface`, `Buttons`,
`Portraits`, `SmallPort`, `Ability`, `Items`, and `Spells`. The demo mapping
loaded four units, four matched shadows, four unit icons, a tiled real ground,
three variations, four deterministic decorations, the legacy segmented battle
panel, and four recognizable UI icons. Runtime exact-magenta keying restores
binary transparency where demonstrated by the exports.

Milestone 0.1.1 hardens the provisional tactical UI at a 1152×648 default and
960×540 minimum logical content size. The right panel is an anchored 320-pixel
region; its portrait, values, actions, status, feedback, events, and restart
content uses wrapping and bounded scrolling. The battlefield scales uniformly in
the non-overlapping remainder, while adapter-based hit testing remains unchanged.
Portable scene tests cover minimum, default, and larger sizes plus representative
long text. Windows 100%, 125%, 150%, and 200% display scaling remain a documented
manual exported-build matrix; 150% is a required 0.1.1 release run, not an
automated claim. No unsupported ability or legacy terrain semantics were added.
Instance mappings remain explicit local presentation choices; no canonical
`genesis:unit/N` relationship is established.

Portable tests use only project-authored synthetic images and cover mapping
categories, malformed mappings, exact color keying, inward facing, layer order,
overlay transforms, real/fallback terrain paths, deterministic decoration,
right-panel construction, portrait fallback, and coordinate independence. The
local-only test skips without ignored data and otherwise proves unit, facing,
shadow, terrain/decor, and interface/portrait routing through the actual scene.
Detailed preparation and remaining fidelity limits are in
`docs/PLAYABLE_TACTICAL_SLICE.md`.

## Current compatibility boundary

The repository can already express deterministic combat scenarios and compare
Python/GDScript rule paths. It does **not** yet reproduce a complete original
battle end to end.

Content-backed scenarios now verify an explicit pack plus version/build and/or
observed canonical fingerprint before resolving canonical unit definitions.
Providers always recompute SHA-256 provenance from their current canonical
metadata/content snapshot; supplied or declared fingerprints are assertions and
stale assertions fail. Resolution reuses the injected `ContentDb`/roster path,
explicit overrides are closed and deep-copied, and inline scenarios remain
pack-free. Canonical `def` and scenario `id` exclusively own content and instance
identity; inline input cannot serialize either runtime identity field. The
default corpus uses only project-authored synthetic content; the separately
named `requires-pack` tests skip when local `packs/<id>/data` is unavailable.
Canonical scenarios are not pack-independent: callers must supply the declared
compatible snapshot, and a fingerprint identifies that snapshot without
asserting legal transferability or rules compatibility.

The most consequential blockers are:

1. end-to-end use of the recovered shared legacy RNG and exact call ordering;
2. automatic status duration tick/expiry and `UNTIL_NEXT_TURN` lifecycle boundary (R13);
3. battle-action effect classification;
4. conversion of remaining recovered binary rules into executable parity fixtures beyond the implemented numeric and tactical-death tranches.

## Documentation checkpoint

The current binary evidence checkpoint covers `closer_inspection_1` through
`closer_inspection_11`, closed requests R1–R11, and runtime schema version
14.

R10 closed without new extraction: Eadoropedia supplied the public morale carve-out and the complete `004D2E60` body already archived in `EXP-R9-001` supplied the exact wound, stamina, 1.5×-mode and randomisation placement.

DELIB-0002 is accepted. The current repository remains the mixed
research/prototype lineage. Future binary requests are necessity-gated, R16 is
retired as structural reconstruction, and a future public implementation lineage
will be created only at the community-release gate defined in
`PUBLIC_LINEAGE_GATE.md`.

Work is divided among human decision ownership, binary/governance authority,
engine semantic authority and bounded Codex execution. `CODEX_WORK_QUEUE.md`
records CX-001 through CX-004 as reviewed and accepted. CX-005 remains blocked
pending an explicit task-local activation; the exporter and CI tasks remain
dependency-blocked.

R12/R13 controlled-observation preflight is ready. One NH battle can use level-zero Harpy `/31`, Wind Seeker `/122` and Warlord `/111` to distinguish return-anchor lifetime, reselection timing and granted-turn start-effect firing without a new binary packet.

The public action-semantics audit is complete. The supplied NH snapshot contains
fourteen explicit unit actions matching the current catalogue boundary and at
least eighteen observable generic battle-action effect families. R16 remains
retired. R17 is reduced to a finite black-box matrix covering zero-damage
triggers, follow-up attack order, component damage, trample and instant-death
placement.



CX-013 establishes the engine-native explicit-unit-action boundary without
recreating the recovered dispatcher: source ability IDs remain content metadata;
the pure canonical recipe resolver creates a fresh immutable ordered plan; the
typed executor iterates operations; and Scenario owns validation, payment,
orchestration and neutral tracing while delegating to shared primitives.
`crushing_blow` is one melee `AttackOp` with integer-only signed truncation of the
initiating `3/2` scale at the R10 pre-randomisation stage. `shield_bash` is one
drain-only stamina `ResourceDeltaOp` with floor-zero and the battle-contextual
effective R11 `0x12` write gate. Both pay the resolved Action cost once and obey
CX-009 terminality. The other twelve catalogue actions, generic battle effects,
R12/R13/R14/R17, special ranged producers and exact legacy RNG ordering remain
outside this implementation.

CX-012 implements the narrowed `DAMAGE-RANGED-001` tranche. Python and
GDScript now select resistance plus received-damage channel 2 only when effective
modifier `0x1C` is nonzero, apply `0x5F` only to that resistance input, and return
before the non-resistance tail. The ordinary branch uses effective ranged
defence, exact integer-only signed-truncating `0x11` halving before `0x4D`,
then applies only the positive post-resolver `0x3C - resistance` excess.
Effective resistance now includes represented providers, truncates their total,
and clamps it to zero without defence stamina halving before either `0x5F` or
`0x3C` consumes it. Eight original branch vectors, four clamp/provider
correction vectors and a live one-shot scenario cover one ammunition, one CX-011
sink application, channel accounting, exact life, pre-terminal R8 cost selection
and CX-009 terminality. The Extra Shot/two-shot action producer and
`DAMAGE-MORALE-001` exact delta/`0x19` branch remain deferred; no claim is made
for complete `RANGED-EXEC-001`, exact shared RNG ordering, or special ranged
modes.

CX-011 implements the frozen tactical death lifecycle. Received damage now
accounts its channel, removes remove-on-damage statuses before life subtraction,
and routes a fatal event exactly once through a battle-contextual resolver.
Adjacent death morale precedes all survival branches; runtime-status-only
`0x49/0x4A/0x5A/0x5B` markers drive complete status clear, rollback, revival,
exact tier replacement, final cleanup and transfer in the accepted order.
Persistent and battle-owned final deaths are distinct, and surviving branches do
not refresh activation or advance status time. Aura upkeep routes only a newly
caused living-to-dead transition, so a retained finalized dead record is not
resolved again on later rounds. EXP-CI11 ordinary-melee sequencing
keeps `fatal_event` separate from final alive state. Synthetic Python/GDS
fixtures cover exact IDs and a parity scenario exposes neutral lifecycle events.
The fixed-slot hero-wide morale cohort, strategy writeback, corpse semantics,
rewards/statistics, kill credit and R17 remain explicit boundaries.

CX-010 implements the stable runtime-status tranche without selecting the R13
clock. `Combatant.statuses` now stores first-class, independently copyable
`Status` instances; per-effect cumulative/maximum/refresh/unique application,
zero-duration resistance, explicit group removal and explicit duration
shortening are parity-tested. Status numeric and flag modifiers traverse live
consumers, and the ranged zero-sum fixture proves they remain later providers
outside the CX-008 R6 early set. Synthetic scenario input/final state serializes
status identity, explicit duration and modifier payload. Round, side, selection,
activation and extra-turn transitions do not advance status duration.
The pre-existing explicit `tick_round` reference helper and its old vectors are
retained in a clearly provisional test section, but no battle hook calls it and
it is not compatibility truth. Automatic expiry, periodic effects,
`UNTIL_NEXT_TURN`, wake-on-damage and their ordering remain unimplemented rather
than inferred from the R13 protocol.

CX-009 implements the project-owner-confirmed activation rule at the shared
model/command boundary: successful ordinary melee/ranged and resolved consuming
active actions close only their actor, while reactions, refusals and resolved
non-consuming action policy remain non-terminal. Partial movement/reselection
before the action and existing round/extra-turn refresh semantics are preserved.
This records implementation status, not new binary verification.


CX-001 passed governance review and is classified `N0_PUBLIC / T0_RETAIN`. R14 now has a five-case giant-footprint observation packet. R15 is formally deferred until a level-up option consumer and synthetic underfull/all-zero fixtures exist. The stale broad dispatcher and melee matrix rows are reconciled with the public-family and finite-observation reductions.

When a new checkpoint is produced, update together:

- `eador_runtime.h`;
- `docs/REVERSE_ENGINEERING.md`;
- `docs/FUNCTION_MAP.csv`;
- this file;
- affected formula and open-question entries.
