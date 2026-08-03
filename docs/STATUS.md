# Status — Project EGO

This is a coverage map, not a release claim.

| subsystem | evidence | Python oracle | GDScript core | parity status |
|---|---|---|---|---|
| attack randomisation and chip damage | published tables + binary | implemented | implemented | strong, legacy PRNG pending |
| stamina and wound multipliers | published tables + binary | implemented | implemented | strong |
| morale attack multiplier | binary partial | placeholder/partial | partial | high-morale curve open |
| modifier pipeline | docs, data, binary providers | implemented in part | implemented in part | provider coverage incomplete |
| activated actions | docs, data, binary dispatcher | implemented | `Action` implemented | effect dictionary incomplete |
| timed statuses | docs + binary runtime nodes | implemented in Python | `core/model/status.gd` empty | major gap |
| level-up selection | data + binary | implemented in part | options implemented | legacy RNG/underfull cases open |
| battlefield coordinates and adjacency | binary | implemented | implemented | adjacency recovered |
| pathfinding and occupancy | Project EGO design + observations | implemented | implemented | tie-break tests present |
| round/side control | observation + partial binary | implemented | implemented | whole-side-phase model open |
| melee execution | binary | partial compatibility model | counterattack path implemented | full legacy lifecycle not yet ported |
| ranged execution | binary | partial compatibility model | partial | special modes incomplete |
| damage channels and death | binary | partial | partial | revival/transfer lifecycle not ported |
| battle actions: eight-clause dispatcher | binary | partial | content model only | high-priority extraction |
| battlefield generation from terrain data | `.var` documentation | partial | model supports tiles | generator not complete |
| scenario format and traces | Project EGO design | implemented | implemented | usable |
| content packs and bindings | data analysis | implemented | implemented | usable |
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

1. exact original random sequence and seeding;
2. GDScript timed-status/runtime-effect model;
3. battle-action effect classification;
4. reconciliation of movement/charge evidence;
5. porting death, revival, transformation and side-transfer semantics.

## Documentation checkpoint

The current binary evidence checkpoint covers `closer_inspection_1` through
`closer_inspection_11` and runtime schema version 14.

When a new checkpoint is produced, update together:

- `eador_runtime.h`;
- `docs/REVERSE_ENGINEERING.md`;
- `docs/FUNCTION_MAP.csv`;
- this file;
- affected formula and open-question entries.
