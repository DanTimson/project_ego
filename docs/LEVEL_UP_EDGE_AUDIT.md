# Level-up exhausted-pool necessity audit

Status: **deferred until an executable consumer exists**  
Request: R15  
Questions: OPEN_QUESTIONS 6 and 6b  
Binary extraction authorized: **no**

## 1. Separated questions

R15 previously combined two different layers:

1. **weighted primitive:** what a legacy weighted roll does when total weight is
   zero;
2. **level-up caller policy:** what the option-selection flow does when filtering
   leaves fewer candidates than requested, no candidates, or only zero-weight
   candidates.

The first may be unreachable by contract. The second is player-visible only when
a level-up option consumer actually invokes it.

## 2. Current reachability

The ordinary candidate collection, prerequisites, weighting and selected-value
removal are already recovered.

The edge does not currently unblock a runnable parity path:

- `core/model/option.gd` is empty;
- `tests/test_options.gd` is empty;
- the compatibility matrix has no executable underfull/all-zero level-up fixture;
- `LegacyRng` deliberately raises on a zero total so the prototype does not
  invent an undocumented fallback.

This does not prove the edge is impossible in Genesis or NH. It means new binary
work presently has no implementation consumer and fails the DELIB-0002
material-reachability gate.

## 3. Behaviour not to invent

Until a profile decision or evidence exists, do not silently choose among:

- return the first entry;
- return a sentinel;
- skip the draw;
- expose fewer choices;
- duplicate a choice;
- refill from rejected candidates;
- treat zero weights as uniform;
- abort the level-up operation.

The current explicit exception is preferable to an accidental compatibility
claim.

## 4. Reactivation trigger

R15 becomes active only after all of the following exist:

1. an implemented level-up option consumer;
2. synthetic fixtures for:
   - empty candidate pool;
   - one positive candidate when several choices are requested;
   - fewer positive candidates than requested;
   - all surviving weights zero;
   - mixed zero and positive weights;
   - duplicate values plus removal-by-selected-value;
3. a stated Genesis/NH/native profile need;
4. a public/data search and controlled observation attempt, or a recorded reason
   those cannot reach the state.

Only the still-material unresolved branch may then generate a binary request.

## 5. Future neutral fixture

The future fixture should record, without binary addresses:

```text
input candidates
prerequisite-filtered candidates
weights
requested choice count
RNG seed/profile
selected sequence
remaining candidates after each selection
caller result or explicit error
```

The weighted primitive and the caller policy must be tested separately. A caller
guard that guarantees positive totals would close 6b as unreachable while
leaving the underfull-choice policy independently testable.

## 6. Classification

- ordinary level-up selection: existing recovered specification;
- zero-total primitive: `N3_INTERNAL` unless a reachable caller is demonstrated;
- underfull/exhausted user-facing choice flow: conditional `N2_EXACT_EDGE`;
- current action: `DEFERRED_UNTIL_CONSUMER`;
- transfer consequence: neutral fixtures may transfer; raw roller/caller control
  flow remains research evidence.
