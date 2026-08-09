# core/model/combatant.gd
class_name Combatant
extends RefCounted

## RefCounted already gives identity semantics and Dictionary-key usability, which
## auras rely on (an aura is keyed by the unit projecting it). The Python oracle
## needs @dataclass(eq=False) to match.

## Battle-time state for one unit.
##
## Plain data, no engine types. `flags` is a set of ability NAMES rather than an
## enum: which abilities exist is content and differs between the genesis and
## new_horizons packs, so it cannot be resolved at compile time.

enum AttackKind { MELEE, COUNTER, RANGED }

const DEFINITION_FIELDS: Array[String] = [
	"name", "content_id", "definition_id", "tier", "attack",
	"counter_attack", "ranged_attack", "shooting_range", "defence",
	"ranged_defence", "resist", "life_base", "stamina_base", "morale_base",
	"speed", "ammo_base", "flags", "subtypes", "modifiers",
]


## The content DEFINITION this instance was built from, e.g. "genesis:unit/5".
## Empty for inline synthetic scenario units, which are battle-local and are NOT
## pack content — DELIB-0001 decision item 6 keeps content identity,
## battle-instance identity and display name distinct. `name` is presentation.
var content_id: String = ""

## BATTLE-INSTANCE identity: the handle addressing this particular combatant
## within one battle. Distinct from `name`, which is presentation, and from
## `content_id`, which is the definition it came from. An army may field several
## units of one type: they share a content_id and a display name and must still
## be individually addressable. DELIB-0001 decision item 6.
##
## Defaults to the display name, so a scenario declaring no explicit id behaves
## exactly as before.
var instance_id: String = ""


## Address-free content-definition state used by the tactical death lifecycle.
## `original_definition` is a narrow static definition snapshot for temporary
## transformation rollback, never a clone of mutable battle state.
var definition_id: int = 0
var tier: int = 1
var original_definition: Dictionary = {}
var battle_owned: bool = false
var discarded: bool = false


var ammo_base: int = 0

## Recovered morale-underflow state and received-damage channel accounting.
var morale_break_accumulator: int = 0
var damage_received: Array[int] = [0, 0, 0, 0]

## Final death clears living occupancy but retains a neutral tactical coordinate
## for deterministic traces and a future corpse layer.
var last_position: Variant = null

func definition_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for field_name in DEFINITION_FIELDS:
		var value: Variant = get(field_name)
		snapshot[field_name] = value.duplicate(true) \
			if typeof(value) in [TYPE_ARRAY, TYPE_DICTIONARY] else value
	return snapshot


func restore_definition(snapshot: Dictionary) -> void:
	for field_name in DEFINITION_FIELDS:
		if not snapshot.has(field_name):
			continue
		var value: Variant = snapshot[field_name]
		set(field_name, value.duplicate(true) \
			if typeof(value) in [TYPE_ARRAY, TYPE_DICTIONARY] else value)


## Display text for logs and traces. The name alone, unless an explicit instance
## id was given — two units of one type share a name, so a line naming only
## «Мечник» would be ambiguous about which acted.
func label() -> String:
	if instance_id != "" and instance_id != name:
		return "%s(%s)" % [name, instance_id]
	return name

var name: String = "unit"

# base (unmodified) stats
var attack: int = 0
var counter_attack: int = 0
var ranged_attack: int = 0
var shooting_range: int = 0
var defence: int = 0
var ranged_defence: int = 0
var resist: int = 0
var life_base: int = 1
var life: int = 1
var stamina_base: int = 10
var stamina: int = 10
var morale_base: int = 10
var morale: int = 10
var speed: int = 1

## Additive bonuses INSIDE the multiplier chain — commander auras, spell buffs,
## the ones visible on the unit panel during battle.
var attack_bonus: int = 0
var defence_bonus: int = 0

## Already-applicable conditional attack contribution. For modifier 0x3D this
## is added after effective-stat and selected ordinary 1.5x processing, before
## attack randomisation; wound, stamina and morale do not scale it (R10).
var conditional_bonus: int = 0

## Ability names, e.g. &"Неутомимый". Membership only.
var flags: Dictionary = {}

## Unit subtypes, e.g. &"Крысолюд", &"Нежить". Membership only. Drives both
## action-cost exemptions and target exclusions.
var subtypes: Dictionary = {}

## Ammunition. Spent by ranged attacks and by several activated abilities.
var ammo: int = 0

# ---------------------------------------------------------------- per-round state
#
# There is no per-unit turn boundary: activation is free and re-entrant, so a
# unit may spend part of its movement, yield, and be reselected in the same
# round. Anything an ability needs to remember lives here and resets on
# ROUND_START, never on activation.

## Cumulative path length this round — NOT displacement. A unit pacing back and
## forth accrues every step. Retained as trace-visible movement history; Genesis
## charge and R8 attack stamina cost do not consume it.
var steps_this_round: int = 0

## Set when an action consuming the activation has been used this round.
## Movement is tracked separately: a unit may move, yield, and be reselected.
var action_spent: bool = false

## Tiles still spendable this round. Reset at ROUND_START from effective speed,
## which already includes the stamina penalty.
var movement_remaining: int = 0

## Set on reaching 0 stamina; consumes the whole of the next round.
var forced_rest: bool = false

## Rested this round, so it forgoes counterattacks.
var resting: bool = false

## Восстановление сил, added to the base +2 on rest.
var stamina_recovery: int = 0

var alive: bool = true

## Sources that have fired their «только один раз за ход» effect this round.
## Cleared by ActionPoints.begin_round and by NOTHING else — an extra turn must
## not refill it, or Кровавое безумие would chain without bound.
var once_per_round: Dictionary = {}

## Innate/content modifiers. Timed effects contribute additional modifiers
## through `statuses`; both sources are combined by Damage.effective_modifiers.
var modifiers: Array = []

## Timed effects. They contribute Modifiers through the same pipeline as
## everything else, so a status never computes a number itself.
var statuses: Array[Status] = []

## A flag is DERIVED, not stored.
##
## `flags` holds flags set directly — by a scenario, a test, or a rule. But a
## flag can also come from an ability, and abilities live in the modifier list;
## and a modifier can come from a status effect, whose explicit removal changes
## the live provider set.
##
## Checking all three sources means a temporary modifier appears when its status
## is applied and vanishes when the status is removed. Every existing has_flag
## call site —
## wounds, stamina, counterattack — follows along without knowing statuses exist.
##
## The alternative was to have the roster run grant_flag at build time and mutate
## `flags`. That works for innate abilities and silently fails for every
## temporary one, which is the worse failure: it looks correct in tests built
## from unit.var and breaks the first time a buff is cast.
func has_flag(f: StringName) -> bool:
	if flags.has(f):
		return true
	for m in modifiers:
		if m.handler == &"grant_flag" and StringName(String(m.params.get("flag", ""))) == f:
			return true
	for effect in statuses:
		for m in effect.modifiers:
			if m.handler == &"grant_flag" and StringName(String(m.params.get("flag", ""))) == f:
				return true
	return false


## Numeric modifier membership from the unit and active statuses. Environment
## providers remain battle-contextual and are added by Damage.has_effective_modifier.
func has_modifier_id(ability: int) -> bool:
	for m in modifiers:
		if int(m.ability) == ability:
			return true
	for effect in statuses:
		for m in effect.modifiers:
			if int(m.ability) == ability:
				return true
	return false


## Every flag from every source. For display and for the AI.
func all_flags() -> Array:
	var out: Dictionary = {}
	for f in flags:
		out[f] = true
	for m in modifiers:
		if m.handler == &"grant_flag" and String(m.params.get("flag", "")) != "":
			out[StringName(String(m.params["flag"]))] = true
	for effect in statuses:
		for m in effect.modifiers:
			if m.handler == &"grant_flag" and String(m.params.get("flag", "")) != "":
				out[StringName(String(m.params["flag"]))] = true
	var keys: Array = out.keys()
	keys.sort()
	return keys

func set_flag(f: StringName) -> void:
	flags[f] = true

func has_subtype(s: StringName) -> bool:
	return subtypes.has(s)

func add_subtype(s: StringName) -> void:
	subtypes[s] = true

func moved_this_round() -> bool:
	return steps_this_round > 0

func base_attack_for(kind: AttackKind) -> int:
	match kind:
		AttackKind.MELEE: return attack
		AttackKind.COUNTER: return counter_attack
		AttackKind.RANGED: return ranged_attack
	return 0

func base_defence_for(kind: AttackKind) -> int:
	return ranged_defence if kind == AttackKind.RANGED else defence

func reset_round() -> void:
	steps_this_round = 0
	action_spent = false
