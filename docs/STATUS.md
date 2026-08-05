# Status — Project EGO

This is a coverage map, not a release claim.

| subsystem | evidence | Python oracle | GDScript core | parity status |
|---|---|---|---|---|
| attack randomisation and chip damage | published tables + binary | implemented with native stream model | native + `LegacyRng` vector-tested | exact CRT generator and adapters implemented in isolation; end-to-end legacy call ordering pending |
| stamina and wound multipliers | published tables + binary; R11 complete `0x12` consumer audit | implemented | implemented | low-stamina penalties recovered; every recovered tactical stamina mutation is locally suppressed by effective modifier `0x12` |
| effective ordinary/ranged defence | Genesis binary `004D0820`/`004D06B0` | not assessed | not assessed | R9 closed: all providers precede exact-zero-stamina trunc0 halving and final floor-zero clamp; provider sets differ |
| morale attack multiplier | Genesis binary + independent NH table | implemented + binary fixture | implemented | full curve and signed rounding recovered; R6 proves the final clamp is reached differently by melee/counterattack and ranged attack |
| modifier pipeline | docs, data, binary providers | implemented in part | implemented in part | R10 closed: `0x3D` conditional contribution is after effective-stat and selected 1.5× processing but before randomisation/defence; explicit fixture pending; wider provider coverage incomplete |
| activated actions | docs, data, binary dispatcher | implemented | `Action` implemented | effect dictionary incomplete |
| timed statuses | docs + binary runtime nodes | implemented in Python | `core/model/status.gd` empty | major gap |
| level-up selection | data + binary | implemented in part | options implemented | legacy RNG/underfull cases open |
| battlefield coordinates and adjacency | binary | implemented | implemented | adjacency recovered |
| pathfinding and occupancy | Project EGO design + observations | implemented | implemented | tie-break tests present |
| round/side control | binary `004EC4C0`/`004E6530`/`004E0280`/`004DE2B0` | implemented | implemented | whole-side phases and capacity-preserving reselection proven; explicit order fixture still needed |
| melee execution | binary | partial compatibility model | counterattack path implemented | execution order and charge source recovered; full legacy lifecycle not yet ported |
| ranged execution | binary | partial compatibility model | partial | special modes and ranged zero-entry guard incomplete; current `steps_this_round` stamina discriminator diverges from live-capacity rule |
| damage channels and death | binary | partial | partial | revival/transfer lifecycle not ported |
| battle actions and target legality | public/data descriptions + selective binary evidence | partial | content model only | R16 whole-dispatcher reconstruction retired; observable action-semantics coverage matrix required |
| battlefield generation from terrain data | `.var` documentation | partial | model supports tiles | generator not complete |
| scenario format and traces | Project EGO design | implemented | implemented | usable |
| content packs and bindings | data analysis | implemented | canonical IDs implemented | content-ID propagation and battle-instance identity remain incomplete |
| `.var` lexical parser | binary | tools exist | n/a | record schemas incomplete |
| unit upkeep/recruitment | binary | not normalized | not implemented | evidence available |
| province income/economy | binary | not normalized | not implemented | evidence available |
| tactical AI scoring | decompilation corpus | not consolidated | scaffold only | deferred |
| presentation | original observation | n/a | devtools only | not a current parity target |

## Current compatibility boundary

The repository can already express deterministic combat scenarios and compare
Python/GDScript rule paths. It does **not** yet reproduce a complete original
battle end to end.

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
opens seven non-semantic repository-conformance tasks; CX-001 through CX-004 are
ready, while aggregate preflight, export and CI work remain dependency-blocked.

R12/R13 controlled-observation preflight is ready. One NH battle can use level-zero Harpy `/31`, Wind Seeker `/122` and Warlord `/111` to distinguish return-anchor lifetime, reselection timing and granted-turn start-effect firing without a new binary packet.

The public action-semantics audit is complete. The supplied NH snapshot contains
fourteen explicit unit actions matching the current catalogue boundary and at
least eighteen observable generic battle-action effect families. R16 remains
retired. R17 is reduced to a finite black-box matrix covering zero-damage
triggers, follow-up attack order, component damage, trample and instant-death
placement.


When a new checkpoint is produced, update together:

- `eador_runtime.h`;
- `docs/REVERSE_ENGINEERING.md`;
- `docs/FUNCTION_MAP.csv`;
- this file;
- affected formula and open-question entries.
