class_name LegacyRng
extends RefCounted

## Genesis legacy RNG — MSVC CRT compatibility generator.
##
## Specification and golden vectors: docs/LEGACY_RNG.md (EXP-R4A-001,
## EXP-R4B-001). Binding scope: legacy_behavior.
##
## This is the Microsoft CRT `rand()` paired with `_holdrand`, plus the
## decimal-extension bounded adapter at `00454C70` and the weighted roller at
## `00454E80`. It is not a better generator and is not meant to be.
##
## ONE SHARED STATE IS THE POINT. Every ordinary consumer on the main game
## thread advances the same state, so adding or removing a single random call in
## one subsystem changes later outcomes everywhere else until the next explicit
## reseed. `Rng` (named streams) is correct for native mode and differential
## tests and cannot reproduce Genesis; `LegacyRng` reproduces Genesis and gives
## up stream isolation deliberately. Both satisfy the same contract:
##
##     roll(x, stream) -> int in [0, x - 1]
##
## `stream` is accepted and ignored here.
##
## TRAP: `Rng.roll` returns 0 for x <= 1 WITHOUT consuming a value. The original
## does not do that — bound 0 consumes nothing, but bound 1 consumes one value
## and returns 0. Short-circuiting bound 1 shifts every later result.
##
## GDScript ints are 64-bit signed, so every step masks back to 32 bits to match
## the Python oracle bit for bit.

const MASK32: int = 0xFFFFFFFF

var state: int = 1
var calls: int = 0          ## CRT advances, for trace assertions
var epoch: String = "unseeded"
var trace: Array = []
var _tracing: bool = false


func _init(p_seed: int = 1) -> void:
	state = p_seed & MASK32

# --- core generator ---------------------------------------------------------

func seed_with(value: int, p_epoch: String = "") -> void:
	state = value & MASK32
	if p_epoch != "":
		epoch = p_epoch


## Advances BEFORE returning, then takes bits 16..30.
func next_u15() -> int:
	state = (state * 214013 + 2531011) & MASK32
	calls += 1
	return (state >> 16) & 0x7FFF


## Bounded adapter at `00454C70`.
##
## Extends precision by appending decimal digits when the bound exceeds 30000.
## The loop condition is strictly `> 30000`; the reduced bound only controls how
## many digits are appended; the final modulo uses the ORIGINAL bound, so the
## modulo bias is preserved deliberately.
func below(bound: int) -> int:
	if bound == 0:
		return 0                       # consumes nothing
	var before: int = state
	var before_calls: int = calls
	var value: int = next_u15()
	var reduced: int = bound
	while reduced > 30000:
		@warning_ignore("integer_division")
		reduced = reduced / 10
		value = (value * 10 + next_u15() % 10) & MASK32
	var result: int = value % bound
	if _tracing:
		trace.append({
			"epoch": epoch, "consumer": "below", "bound": bound,
			"state_before": before, "state_after": state,
			"advances": calls - before_calls, "value": result,
		})
	return result


## Drop-in for `Rng.roll`. `stream` is accepted and ignored.
## x == 1 consumes a value here, because the original does.
func roll(x: int, _stream: StringName = &"") -> int:
	if x <= 0:
		return 0
	return below(x)

# --- weighted roller --------------------------------------------------------

## Weighted selection at `00454E80`.
##
## Removal is BY SELECTED VALUE, not by selected index: duplicate values all
## drop to weight zero. Returns [selected_value, weights_after].
##
## Total weight zero is open question 6b — the original's behaviour is not
## established, so this pushes an error rather than inventing a silent fallback.
func weighted(values: Array, weights: Array, remove_selected: bool = false) -> Array:
	if values.size() != weights.size():
		push_error("values and weights must be parallel")
		return [null, weights]
	var total: int = 0
	for w in weights:
		total += int(w)
	if total <= 0:
		push_error("total weight is zero — behaviour unrecovered (OPEN_QUESTIONS 6b)")
		return [null, weights]
	var rolled: int = below(total)
	var cumulative: int = 0
	var selected: Variant = null
	for i in values.size():
		cumulative += int(weights[i])
		if cumulative > rolled:
			selected = values[i]
			break
	var out: Array = weights.duplicate()
	if remove_selected and selected != null:
		for i in values.size():
			if values[i] == selected:
				out[i] = 0
	return [selected, out]

# --- recovered reseed epochs ------------------------------------------------

## `if map_seed == 0: map_seed = 111` then `crt_srand(map_seed)`.
## Returns the effective map seed; the zero substitution is observable.
func seed_map_generation(map_seed: int) -> int:
	var effective: int = 111 if map_seed == 0 else map_seed
	seed_with(effective, "map_generation")
	return effective


## `crt_srand(map_seed + strategic_turn)`, uint32 arithmetic. A strategic turn
## does NOT inherit the terminal state of the preceding turn, though call order
## within the turn is still binding.
func seed_strategic_turn(map_seed: int, strategic_turn: int) -> void:
	seed_with((map_seed + strategic_turn) & MASK32,
		"strategic_turn/%d" % strategic_turn)

# --- diagnostics ------------------------------------------------------------

func enable_trace(on: bool = true) -> void:
	_tracing = on


func snapshot() -> Dictionary:
	return {"state": state, "calls": calls, "epoch": epoch}


func restore(snap: Dictionary) -> void:
	state = int(snap.get("state", 1)) & MASK32
	calls = int(snap.get("calls", 0))
	epoch = String(snap.get("epoch", epoch))
