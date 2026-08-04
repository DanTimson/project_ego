# Legacy RNG compatibility specification

This is the engine-side handoff for R4. It records the exact compatibility
surface recovered from the Genesis executable while keeping unresolved
persistence boundaries explicit.

## Evidence status

Proven directly from the supplied executable packets:

- `00404B0B` calls `__getptd()` and writes the seed to
  `_ptiddata._holdrand`;
- ordinary direct `_rand()` calls, `00454C70`, and `00454E80` use the same CRT
  generator on the calling thread;
- `00454DC0`, `00454F80`, and `00455050` do not consume that CRT state;
- `00454C70` implements the decimal-extension bounded adapter;
- startup, map/setup, map-generation, strategic-turn, and two
  menu/transition reseeds are present.

The `_rand` symbol is the linked Microsoft CRT generator paired with
`_holdrand`. The implementation target is the canonical MSVC recurrence below.
A separate export of the library `_rand` body would strengthen the evidence
locator, but is not required to implement or test the compatibility sequence.

## Required compatibility object

Use one mutable legacy RNG state for each emulated game thread/session:

```text
LegacyRng
    uint32 state

    seed(uint32 value)
    next_u15() -> uint32
    below(uint32 exclusive_bound) -> uint32
```

Do not use the host language's random library. Do not create independent combat,
AI, progression, generation, or loot streams in Genesis compatibility mode.

Named streams may remain available for isolated tests or an explicitly
Project-EGO-native deterministic mode, but they must not be described as legacy
parity.

For trace/replay infrastructure it is useful to expose state snapshot and
restore methods. That is an engine facility; the current binary evidence does
not establish that Genesis save files serialize live CRT state.

## Seed and next value

```text
seed(value):
    state = value & 0xffffffff

next_u15():
    state = (state * 214013 + 2531011) & 0xffffffff
    return (state >> 16) & 0x7fff
```

`next_u15()` advances before returning its value.

## Raw golden vectors

Each row starts from a fresh seed.

```text
seed 1:
41, 18467, 6334, 26500, 19169, 15724, 11478, 29358

seed 111:
401, 21144, 5313, 19256, 6893, 21680, 26167, 2270

seed 0:
38, 7719, 21238, 2437, 8855, 11797, 8365, 32285
```

These vectors test seed assignment, uint32 wraparound, advance-before-return,
right shift, and the 15-bit mask.

## Bounded adapter at `00454C70`

Logical pseudocode:

```text
below(bound):
    if bound == 0:
        return 0

    value = next_u15()
    reduced = bound

    while reduced > 30000:
        reduced = floor(reduced / 10)
        value = (value * 10 + next_u15() % 10) & 0xffffffff

    return value % bound
```

Compatibility requirements:

- bound zero consumes no value;
- a positive bound consumes at least one value;
- the loop condition is strictly `> 30000`;
- the reduced bound controls only the number of appended digits;
- the final modulo uses the original bound;
- modulo bias is preserved;
- the accumulator uses 32-bit wraparound.

### Bounded golden vectors

Each row begins from a fresh `seed(1)`.

| bound | result | calls to `next_u15()` |
|---:|---:|---:|
| 0 | 0 | 0 |
| 1 | 0 | 1 |
| 10 | 1 | 1 |
| 30000 | 41 | 1 |
| 30001 | 417 | 2 |
| 300000 | 417 | 2 |
| 3000001 | 4174 | 3 |

The 30000/30001 pair is important because it catches an incorrect `>= 30000`
loop condition.

## Weighted roller at `00454E80`

The global source representation contains parallel value and weight arrays,
terminated by value zero. The normalized engine API does not need to preserve
those globals, but compatibility behaviour is:

```text
total = sum(weights)
roll = below(total)

cumulative = 0
for entry in order:
    cumulative += entry.weight
    if cumulative > roll:
        selected_value = entry.value
        break

if remove_selected_value:
    for entry in entries:
        if entry.value == selected_value:
            entry.weight = 0

return selected_value
```

Removal is by selected value, not by selected index.

### Weighted golden vector

Start with `seed(0)`:

```text
values  = [7, 9, 7]
weights = [1, 1, 3]
total   = 5
first CRT output = 38
roll = 38 % 5 = 3
selected value = 7
```

With `remove_selected_value = true`, resulting weights are:

```text
[0, 1, 0]
```

This catches implementations that remove only the selected array entry.

Total weight zero remains open question 6b. Compatibility code must not invent a
fallback silently.

## Shared topology

On the main game thread, these all advance the same state:

```text
direct _rand()
00454C70 random_below
00454E80 weighted_roll
all callers that reach either function
```

Therefore adding or removing a random call in one subsystem changes later
outcomes in other subsystems until the next explicit reseed.

A compatibility trace should optionally record:

```text
epoch label
state before call
consumer label/address
bound or total weight
number of CRT advances
state after call
returned value
```

That trace format will make call-order mismatches diagnosable without coupling
the rules engine to Ghidra addresses.

## Non-advancing contextual selectors

The following functions do not call `_rand()` or `00454C70`:

```text
00454DC0 weighted_roll_contextual_candidate
00454F80 contextual_roll_position_candidate
00455050 weighted_roll_contextual_biased_candidate
```

They are not separate random streams. They derive weighted positions from
contextual arithmetic. Their hidden register arguments and exact formulas are
not yet typed sufficiently for a stable engine API.

Until those formulas are implemented, route only callers proven to use the
ordinary roller through `LegacyRng`. Do not substitute a second RNG for the
contextual paths.

## Recovered reseed epochs

### Startup/content initialization

```text
seed = time64() % 10000
crt_srand(seed)
```

This is a wall-clock initialization epoch, not the persistent campaign seed.

### Setup and map generation

A setup path copies a chosen/stored value into the map-seed global and calls
`crt_srand` before consuming setup randomness.

The map-generation function:

```text
if map_seed == 0:
    map_seed = 111

strategic_turn = 0
crt_srand(map_seed)
```

### Strategic turn

The global strategic tick starts with:

```text
crt_srand(map_seed + strategic_turn)
```

Use uint32 arithmetic for the addition. Random activity in one strategic turn
therefore does not inherit the terminal CRT state of the preceding turn, though
all random calls inside the turn remain call-order-sensitive.

### Menu/transition counter

Two menu/transition paths call:

```text
crt_srand(seed_counter)
```

The counter increments and wraps through `1..10000`. The precise user-facing
meaning of these two operations is still provisional.

### Residual boundaries

The `crt_srand` XREF list also names a conditional call in the battle-outcome
path. The supplied local body is incomplete for its seed expression, so it is
not frozen here.

No supplied evidence establishes whether save/load code serializes live
`_holdrand`. Treat those as deferred parity questions, not reasons to block the
core generator and principal epochs.

## Suggested engine-side fixture order

1. Implement `seed()` and `next_u15()` against all three raw vectors.
2. Implement `below()` against the seven bound/call-count vectors.
3. Implement weighted selection and duplicate-value removal.
4. Replace compatibility-mode named streams with one shared injected
   `LegacyRng`.
5. Add explicit epoch reseeds for map generation and strategic turns.
6. Add trace assertions that contextual selectors do not advance `LegacyRng`.
7. Wire the remaining setup/menu epochs when their owning workflows are ported.
8. Revisit open question 4c only when battle outcome or save continuation enters
   executable parity scope.

## Evidence references

- `EXP-R4A-001`: `binary_analysis_3.txt`
- `EXP-R4B-001`: `binary_analysis_4.txt`
- `EXP-R2-001`: startup loader containing `time64()%10000`
- `EXP-STRATEGIC-TICK-001`: global strategic tick reseed
- functions `00404B0B`, `00454C70`, `00454DC0`, `00454E80`,
  `00454F80`, and `00455050`
