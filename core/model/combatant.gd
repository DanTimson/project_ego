class_name Combatant
extends RefCounted

## Battle-time state for one unit.
##
## Plain data, no engine types. `flags` is a set of ability NAMES rather than an
## enum: which abilities exist is content and differs between the genesis and
## new_horizons packs, so it cannot be resolved at compile time.

enum AttackKind { MELEE, COUNTER, RANGED }

var name: String = "unit"

# base (unmodified) stats
var attack: int = 0
var counter_attack: int = 0
var ranged_attack: int = 0
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

## Additive bonuses applied AFTER the multipliers. Morale demonstrably skips
## these (Сокрушение зла and similar); whether stamina and wound do too is not
## documented. See OPEN_QUESTIONS item 7.
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
## forth accrues every step. Feeds Атака с разгона directly; its `> 0` test is
## the stamina -2/-1 discriminator.
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

func has_flag(f: StringName) -> bool:
	return flags.has(f)

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
