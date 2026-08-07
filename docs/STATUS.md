# Status — Project EGO

This is a coverage map, not a release claim.

| subsystem | evidence | Python oracle | GDScript core | parity status |
|---|---|---|---|---|
| attack randomisation and chip damage | published tables + binary | implemented with native stream model | native + `LegacyRng` vector-tested | exact CRT generator and adapters implemented in isolation; end-to-end legacy call ordering pending |
| stamina and wound multipliers | published tables + binary; R11 complete `0x12` consumer audit | implemented | implemented | low-stamina penalties recovered; every recovered tactical stamina mutation is locally suppressed by effective modifier `0x12` |
| effective ordinary/ranged defence | Genesis binary `004D0820`/`004D06B0` | not assessed | not assessed | R9 closed: all providers precede exact-zero-stamina trunc0 halving and final floor-zero clamp; provider sets differ |
| morale attack multiplier | Genesis binary + independent NH table | implemented + binary fixture | implemented | full curve and signed rounding recovered; R6 proves the final clamp is reached differently by melee/counterattack and ranged attack |
| modifier pipeline | docs, data, binary providers | implemented in part | implemented in part | R10 closed: `0x3D` conditional contribution is after effective-stat and selected 1.5× processing but before randomisation/defence; explicit fixture pending; wider provider coverage incomplete |
| activated actions | public/data families + selective binary edges | implemented | `Action` catalogue implemented | fourteen explicit NH unit actions and public effect-family matrix catalogued; battlefield execution and consumer-triggered opcode mappings incomplete |
| timed statuses | docs + binary runtime nodes | implemented in Python | `core/model/status.gd` empty | major gap |
| level-up selection | data + binary | implemented in part | `core/model/option.gd` and `tests/test_options.gd` empty | ordinary selection is specified; R15 zero-total/underfull edge deferred until an executable consumer and fixture exist |
| battlefield coordinates and adjacency | binary + controlled observation | implemented | implemented | adjacency recovered; R14 large-unit logical-footprint protocol ready |
| pathfinding and occupancy | Project EGO design + observations | implemented | implemented | tie-break tests present |
| round/side control | binary `004EC4C0`/`004E6530`/`004E0280`/`004DE2B0` | implemented | implemented | whole-side phases and capacity-preserving reselection proven; explicit order fixture still needed |
| melee execution | binary | partial compatibility model | counterattack path implemented | execution order and charge source recovered; full legacy lifecycle not yet ported |
| ranged execution | binary | partial compatibility model | partial | special modes and ranged zero-entry guard incomplete; current `steps_this_round` stamina discriminator diverges from live-capacity rule |
| damage channels and death | binary | partial | partial | revival/transfer lifecycle not ported |
| battle actions and target legality | public/data descriptions + selective binary evidence | partial | content model only | R16 whole-dispatcher reconstruction retired; observable action-semantics coverage matrix required |
| battlefield generation from terrain data | `.var` documentation | partial | model supports tiles | generator not complete |
| scenario format and traces | Project EGO design | inline and canonical-definition units implemented | inline and canonical-definition units implemented | portable synthetic parity fixture covers provenance, merge and identity |
| content packs and bindings | data analysis | implemented; `ContentDb` is a scenario provider | implemented; `ContentDb` is a scenario provider | canonical content ID, battle-instance ID and display name remain separate; actual content requires a verified local pack snapshot |
| `.var` lexical parser | binary | tools exist | n/a | record schemas incomplete |
| unit upkeep/recruitment | binary | not normalized | not implemented | evidence available |
| province income/economy | binary | not normalized | not implemented | evidence available |
| tactical AI scoring | decompilation corpus | not consolidated | scaffold only | deferred |
| presentation | Project EGO slice contract | n/a | playable hot-seat tactical scene + optional ignored local assets | structured command boundary and real EGOgrabber-to-resolver pipeline validated locally; not an original parity target |

## Playable tactical slice

Playable Tactical Slice 2 is the ordinary project entry point:

```bash
godot --path .
```

It preserves the synthetic 8×5 hot-seat battle and placeholder-only fresh-clone
behavior. Manual move, melee, ranged, rest, and pass execution now returns an
authoritative structured core result with refusal reason, new events, and an
accurate state-change flag. Advisory highlights query the same movement,
automatic-approach, and ranged eligibility helpers. `ManualBattleSession` scopes
legacy `Damage` bindings per call, so alternating sessions do not retain one
another's environment.

The full optional local presentation path has been exercised with the actual
clean EGOgrabber revision `ca2df7001427266c07201cb22569d32a663f77e0` and the
user-provided `Units.dat`, `Unit_icons.dat`, `Unit_shadow.dat`, and
`Unit_shadowf.dat`. Each archive yielded 71 images plus one raw info object; the
ignored combined index contained 288 archive-qualified assets. Four explicit
battle-instance demo mappings loaded real textures and reached the playable
battlefield draw path. Removing the ignored mapping returns the same build to
placeholders. These instance mappings are presentation choices only: no
canonical `genesis:unit/N` to `Units:UnitNN` relationship is established.

Portable tests use only project-authored synthetic assets. The local-only real
asset test skips when `.local/eador_assets/index.json` is absent. Preparation,
security schema, launch, fallback, and observed archive details are documented
in `docs/PLAYABLE_TACTICAL_SLICE.md`.

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
2. GDScript timed-status/runtime-effect model;
3. battle-action effect classification;
4. porting death, revival, transformation and side-transfer semantics;
5. conversion of recovered binary rules into executable parity fixtures, including the ranged live-capacity stamina correction and effective-defence vectors.

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


CX-001 passed governance review and is classified `N0_PUBLIC / T0_RETAIN`. R14 now has a five-case giant-footprint observation packet. R15 is formally deferred until a level-up option consumer and synthetic underfull/all-zero fixtures exist. The stale broad dispatcher and melee matrix rows are reconciled with the public-family and finite-observation reductions.

When a new checkpoint is produced, update together:

- `eador_runtime.h`;
- `docs/REVERSE_ENGINEERING.md`;
- `docs/FUNCTION_MAP.csv`;
- this file;
- affected formula and open-question entries.
