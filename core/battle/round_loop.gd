class_name RoundLoop
extends RefCounted

## Round -> side phase -> free interleaved activation.
##
## ASSUMPTION, NOT ESTABLISHED (OPEN_QUESTIONS item 16): sides alternate in whole
## PHASES — one side activates every unit it wants to, then the other. The
## alternative is unit-by-unit alternation between sides. The documented
## initiative rule speaks of a SIDE moving first, which fits phases, but does
## not exclude alternation. One observed battle settles it.

class Side extends RefCounted:
	var id: int = 0
	var name: String = ""
	var units: Array[Combatant] = []
	var leader_initiative: int = 0
	var is_attacker: bool = false

	func living() -> Array[Combatant]:
		var out: Array[Combatant] = []
		for u in units:
			if u.alive:
				out.append(u)
		return out


class BattleState extends RefCounted:
	var sides: Array = []
	var round_number: int = 0
	var active_side: int = 0
	var log: Array[String] = []

	func side(sid: int) -> Side:
		for s in sides:
			if s.id == sid:
				return s
		return null

	func other(sid: int) -> Side:
		for s in sides:
			if s.id != sid:
				return s
		return null


## «Первый ход в бою получает отряд, у лидера которого выше инициатива. Если
## инициатива равна, первым ходит атакующий.» Army-level, one comparison at
## battle start — not a per-unit stat.
static func first_side(sides: Array) -> int:
	var a: Side = sides[0]
	var b: Side = sides[1]
	if a.leader_initiative != b.leader_initiative:
		return a.id if a.leader_initiative > b.leader_initiative else b.id
	return a.id if a.is_attacker else b.id


static func begin_battle(state: BattleState) -> void:
	state.round_number = 0
	state.active_side = first_side(state.sides)
	begin_new_round(state)


static func begin_new_round(state: BattleState) -> void:
	state.round_number += 1
	for s in state.sides:
		for u in s.units:
			if u.alive:
				ActionPoints.begin_round(u)
	state.active_side = first_side(state.sides)
	state.log.append("round %d begins, side %d first" % [state.round_number, state.active_side])


## Units the player may select right now. Free choice among them, and a unit may
## be selected again later in the round while it still has resources — that
## re-entry is the whole point of the model.
static func activatable(state: BattleState, side_id: int) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for u in state.side(side_id).living():
		if ActionPoints.has_resources(u):
			out.append(u)
	return out


static func phase_done(state: BattleState, side_id: int) -> bool:
	return activatable(state, side_id).is_empty()


## Hand control to the other side. Returns true if a new round started.
static func end_phase(state: BattleState) -> bool:
	var other: Side = state.other(state.active_side)
	if phase_done(state, other.id):
		begin_new_round(state)
		return true
	state.active_side = other.id
	state.log.append("side %d takes over" % state.active_side)
	return false


static func battle_over(state: BattleState) -> bool:
	for s in state.sides:
		if s.living().is_empty():
			return true
	return false
