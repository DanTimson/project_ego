# OBS-R12/R13 — return-anchor and start-effect lifecycle preflight

Status: **ready for controlled observation**  
Requests: R12 and R13  
Public source: `DOC-EADOROPEDIA-NH-26.0620-F01`  
Binary extraction authorized: **no**, unless the completed matrix leaves a
material ambiguity

## 1. Public basis and test subjects

The New Horizons Eadoropedia snapshot provides the following factual inputs:

- upgrade `/274`, `Удар и возврат`: after attacking, the unit returns to the
  tile from which its movement began;
- upgrade `/629`, `Прилив сил +1`: the unit restores one additional stamina each
  turn;
- spell/upgrade `/212`, `Слово вождя`: damages a friendly eligible creature,
  restores two stamina, and grants a second turn.

Recommended NH 26.0620.f01 units:

| role | unit | public data |
|---|---|---|
| R12 subject | `/31 Гарпия` | level 0; `Удар и возврат`; speed 4 |
| R13 subject | `/122 Искатель ветра` | level 0; `Прилив сил +1` ×2; stamina 11 |
| second-turn source | `/111 Вожак` | level 0; `Слово вождя` |

These identities are NH test conveniences, not claims about Genesis content
indexes. For Genesis, use equivalent publicly visible units/abilities and record
their names rather than assuming numeric identity.

## 2. Common setup

Use one friendly side containing:

- the R12 subject;
- the R13 subject;
- the second-turn source;
- one disposable friendly unit for reselection where needed.

Use one stationary, high-life enemy dummy. Avoid a target that dies, teleports,
pushes, immobilizes or changes the attacker's position. Disable or tolerate
retaliation, but record it.

Label relevant tiles on a screenshot or sketch:

```text
A = subject's phase/turn starting tile
B = tile reached by an earlier manual move
C = attack-command approach tile adjacent to target
T = target tile
```

The labels are sufficient; executable coordinates are not required.

Before each case:

1. restore the same save/scenario;
2. record build and content-pack version;
3. record subject tile, stamina, remaining capacity and eligibility;
4. preregister the command sequence in the result sheet;
5. run only that sequence.

## 3. R12 — `Удар и возврат`

### R12-A: adjacent control

Place the Harpy at `A`, already adjacent to `T`. Attack without command movement.

Expected control: final tile `A`.

This confirms that the ability does not move a stationary attacker elsewhere,
but does not distinguish anchor lifetime.

### R12-B: contiguous approach attack

Place the Harpy at `A` far enough from `T` that selecting the attack makes it
approach to `C`, strike, and return.

Record the final tile.

Expected public baseline: `A`, because `A` is the movement-start and
attack-command-start tile in this case.

### R12-C: split same-side re-entry — decisive case

1. Harpy starts at `A`.
2. Move it manually to `B` without attacking.
3. Select and act with another friendly unit.
4. Reselect the Harpy during the same side phase.
5. Command an attack that approaches to `C`.
6. Record the Harpy's final tile.

Interpretation:

| final tile | supported rule |
|---|---|
| `A` | an earlier phase/turn/activation anchor survives reselection |
| `B` | the anchor is the current attack-command movement start |
| `C` | no return, post-approach anchor, or another rule; record video |
| other | unexpected displacement; record all effects |

This is the minimum observation capable of closing the ordinary split-activation
half of R12.

### R12-D: granted second turn

1. Let the Harpy complete an ordinary turn and return.
2. Use `Слово вождя` or another recorded second-turn effect on it.
3. On the granted turn, move manually from `A` to `B`.
4. Reselect if the interface permits.
5. Command an attack that approaches to `C`.
6. Record the final tile.

Interpretation:

- return to `B`: the granted turn/attack command establishes a new anchor;
- return to `A`: an earlier anchor survives the second-turn reset;
- another tile: record the complete sequence.

Do not use the spell's damage or stamina restoration as R12 evidence.

## 4. R13 — `Прилив сил`

The recommended Wind Seeker has two copies of `Прилив сил +1`, producing an
expected increment of `+2` whenever the effect fires.

Keep the subject at least four stamina below maximum before the second-turn test
so both the spell's direct `+2` and a possible `Прилив сил +2` remain visible
without cap saturation.

### R13-A: own side-phase boundary before selection

At the transition into the Wind Seeker's side phase:

1. inspect its stamina before selecting it, using the details interface if
   available;
2. select it;
3. inspect stamina again.

Interpretation:

- increase before selection: round/side-phase boundary;
- increase only on selection: activation/selection boundary;
- no increase: wrong subject/setup or a later boundary.

### R13-B: same-phase deselect and reselect

1. Select the Wind Seeker once.
2. Move or act partially so its current stamina is visible below maximum.
3. Select another friendly unit.
4. Reselect the Wind Seeker in the same side phase.
5. Compare stamina immediately before and after reselection.

Interpretation:

- additional `+2`: selection/activation is a repeatable trigger;
- no additional increase: firing is phase/turn-gated.

### R13-C: opponent-side transition

Record the Wind Seeker's stamina:

1. immediately before ending its side phase;
2. immediately after the opponent's side phase begins;
3. immediately after its own next side phase begins, before selection.

Interpretation:

- increase on opponent phase start: global side-phase trigger;
- increase only on its own next phase: owner-side or round trigger;
- increase only on later selection: activation trigger.

### R13-D: granted second turn — decisive extra-turn case

1. Let the Wind Seeker act and reduce its stamina to at most `max - 4`.
2. Record stamina `S`.
3. Warlord casts `Слово вождя`.
4. Record stamina immediately after the spell, before selecting the Wind Seeker.
5. Select the Wind Seeker for the granted turn.
6. Record stamina immediately after selection and before another command.

Public spell behaviour supplies the control:

```text
direct spell restoration = +2 stamina
Прилив сил on granted-turn start, if it fires = additional +2
```

Interpretation, before cap:

| observed change from `S` | supported rule |
|---:|---|
| `+2` | spell restored stamina; `Прилив сил` did not fire for the granted turn |
| `+4` | spell restored `+2` and `Прилив сил +2` fired again |
| other | cap, another modifier, or different spell data; record all values |

This is the minimum observation capable of closing the extra-turn half of R13.

## 5. Build separation

Run and record New Horizons first because the public subjects are fully
specified there.

Genesis results must be stored in separate rows. Do not infer Genesis lifecycle
from NH agreement or disagreement. If no equivalent Genesis fixture can be made
without extensive save construction, submit the NH sheet first; it still settles
the NH profile and narrows any later Genesis-only request.

## 6. Closure criteria

R12 may close from observation when:

- R12-C has an unambiguous final tile;
- R12-D establishes whether a granted turn resets the anchor;
- the build and command sequence are recorded.

R13 may close from observation when:

- R13-A/B distinguish phase from repeatable selection;
- R13-C identifies whether the opponent transition triggers;
- R13-D distinguishes direct spell restoration from an extra start-effect tick.

If a case cannot be executed, record `NOT_REACHABLE` and why. Only then may a
narrow binary request be considered. Such a request must ask for the unresolved
boundary alone, not for a broad executor export.
