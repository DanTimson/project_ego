class_name BattleObservation
extends RefCounted

## Detached presentation facts. No command execution, text parsing or RNG.
enum Kind { MOVE, STRIKE, IMPACT, RESOURCE, EFFECT, DEFEAT, PHASE }
var kind: Kind
var source := ""
var target := ""
var amount := 0
var state: Dictionary

func _init(p_kind: Kind, p_state: Dictionary, p_source := "", p_target := "",
        p_amount := 0) -> void:
	kind = p_kind
	state = p_state.duplicate(true)
	source = p_source
	target = p_target
	amount = p_amount

static func unit_state(unit: Combatant) -> Dictionary:
	return {"alive": unit.alive, "life": unit.life, "stamina": unit.stamina,
		"ammo": unit.ammo, "action_spent": unit.action_spent,
		"movement_remaining": unit.movement_remaining,
		"steps_this_round": unit.steps_this_round}


func to_dict() -> Dictionary:
	return {"kind": kind, "source": source, "target": target, "amount": amount,
		"state": state.duplicate(true)}
