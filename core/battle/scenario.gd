# core/battle/scenario.gd
class_name Scenario
extends RefCounted

## Deterministic battles as data.
##
## A scenario is a seed, a battlefield, two sides, and a command list. Running it
## produces a LOG: an ordered list of plain strings, compared line for line
## against the Python oracle.
##
## WHY A LOG AND NOT A FINAL STATE. A final state can match while the route to it
## differs — two implementations that disagree about pathfinding tie-breaks, or
## about when stamina is charged, can still land the same unit on the same hex
## with the same HP. The log catches the divergence at the step where it happens.
##
## THIS IS THE INTEGRATION POINT. Pathfinding feeds steps_this_round, which sets
## the stamina charge, which feeds StaminaMod, which scales the attack, which the
## RNG rolls, which the defence reduces. A scenario that reproduces exactly is
## evidence the whole chain agrees.

var spec: Dictionary = {}
var scenario_name: String = "unnamed"
var seed_value: int = 0
var log: Array[String] = []
## Either Rng (named streams) or LegacyRng (Genesis compatibility).
var rng: Variant
var field: Battlefield
var units: Dictionary = {}          ## name -> Combatant
var state: RoundLoop.BattleState
## unit -> its projected auras. Passive, so built once; which units an aura
## REACHES is recomputed on every query.
var auras_by_source: Dictionary = {}


func _init(p_spec: Dictionary, injected_rng: Variant = null) -> void:
	spec = p_spec
	scenario_name = String(spec.get("name", "unnamed"))
	seed_value = int(spec.get("seed", 0))
	# THE randomness boundary. Rules never choose a generator and never branch on
	# mode — they receive whatever is injected here and call roll(x, stream).
	# Genesis compatibility needs ONE shared LegacyRng because the original
	# advances a single CRT state across every consumer; native mode keeps
	# per-subsystem streams so adding a roll in one place does not invalidate
	# every stored replay. Those requirements are irreconcilable, which is why
	# this seam exists and why it is the only general seam in the engine.
	if injected_rng != null:
		rng = injected_rng
	elif String(spec.get("rng", "")).to_lower() == "legacy":
		rng = LegacyRng.new(seed_value)
	else:
		rng = Rng.new(seed_value)
	field = _build_field(spec.get("battlefield", {}))
	state = RoundLoop.BattleState.new()
	state.sides = _build_sides(spec.get("sides", []))
	auras_by_source = _build_auras(spec.get("sides", []))


func _build_field(s: Dictionary) -> Battlefield:
	var bf := Battlefield.new(int(s.get("width", 7)), int(s.get("height", 7)))
	for t in s.get("tiles", []):
		var h := Battlefield.offset_to_axial(int(t["col"]), int(t["row"]))
		var tile: Battlefield.Tile = bf.tile(h)
		if tile == null:
			continue
		if t.has("bf_object"):
			tile.bf_object = int(t["bf_object"])
		if t.has("move_cost"):
			tile.move_cost = int(t["move_cost"])
		if t.has("stam_cost"):
			tile.stam_cost = int(t["stam_cost"])
	return bf


func _build_sides(specs: Array) -> Array:
	var out: Array = []
	for s in specs:
		var side := RoundLoop.Side.new()
		side.id = int(s["id"])
		side.name = String(s.get("name", str(s["id"])))
		side.leader_initiative = int(s.get("leader_initiative", 0))
		side.is_attacker = bool(s.get("is_attacker", false))
		for u in s.get("units", []):
			var unit := Combatant.new()
			unit.name = String(u["name"])
			# Battle-instance identity, distinct from the display name; defaults
			# to the name so existing scenarios are unaffected.
			unit.instance_id = String(u.get("id", u["name"]))
			for key in u:
				var k := String(key)
				if k == "id":
					continue
				if k in ["name", "at", "flags", "subtypes", "modifiers", "auras"]:
					continue
				unit.set(k, u[key])
			for f in u.get("flags", []):
				unit.set_flag(StringName(String(f)))
			for m in u.get("modifiers", []):
				unit.modifiers.append(Modifier.make(
					int(m.get("ability", 0)), StringName(String(m["handler"])),
					Modifier.Hook[String(m.get("hook", "STAT_PASSIVE"))],
					int(m.get("power", 0)), m.get("params", {}),
					String(m.get("source", m["handler"]))))
			for st in u.get("subtypes", []):
				unit.add_subtype(StringName(String(st)))
			if not u.has("life_base"):
				unit.life_base = unit.life
			if not u.has("stamina_base"):
				unit.stamina_base = unit.stamina
			if not u.has("morale_base"):
				unit.morale_base = unit.morale
			var at: Array = u["at"]
			field.place(unit, Battlefield.offset_to_axial(int(at[0]), int(at[1])))
			if units.has(unit.instance_id):
				push_error("duplicate unit instance id '%s' — give each unit an explicit \"id\" when several share a display name" % unit.instance_id)
			units[unit.instance_id] = unit
			side.units.append(unit)
		out.append(side)
	return out


func _build_auras(specs: Array) -> Dictionary:
	var out: Dictionary = {}
	for side_spec in specs:
		for u in side_spec.get("units", []):
			var declared: Array = u.get("auras", [])
			if declared.is_empty():
				continue
			var unit: Combatant = units[String(u.get("id", u["name"]))]
			var built: Array = []
			for a in declared:
				var aura := Auras.Aura.new()
				aura.id = StringName(String(a["id"]))
				aura.name = String(a.get("name", a["id"]))
				aura.scope = Auras.Scope[String(a.get("scope", "ADJACENT"))]
				aura.affects = Auras.Side[String(a.get("affects", "ALLY"))]
				aura.stacking = Auras.Stacking[String(a.get("stacking", "MAXIMUM"))]
				aura.power = int(a.get("power", 0))
				aura.tick = a.get("tick", {})
				for st in a.get("only_subtypes", []):
					aura.only_subtypes.append(StringName(String(st)))
				for st in a.get("except_subtypes", []):
					aura.except_subtypes.append(StringName(String(st)))
				aura.source = unit
				for m in a.get("modifiers", []):
					aura.modifiers.append(Modifier.make(
						int(m.get("ability", 0)),
						StringName(String(m["handler"])),
						Modifier.Hook[String(m.get("hook", "STAT_PASSIVE"))],
						int(m.get("power", a.get("power", 0))),
						m.get("params", {}), aura.name))
				built.append(aura)
			out[unit] = built
	return out


func side_of(unit: Combatant) -> RoundLoop.Side:
	return _side_of(unit)


## Modifiers from the unit's surroundings — the auras reaching it now.
func environment(unit: Combatant) -> Array:
	return Auras.modifiers_for(unit, auras_by_source, field,
		Callable(self, "side_of"))


## Statuses and auras, at the top of each round.
##
## ORDER: auras first, then statuses. An aura is a continuous drain from a living
## source; a status is a stored effect that ages. Ticking statuses first would let
## an effect expire before an aura that might have killed its source resolves.
## Nothing documents the order — OPEN_QUESTIONS item 20.
func _round_upkeep() -> void:
	for side in state.sides:
		for unit in side.units.duplicate():
			if not unit.alive:
				continue
			var result: Array = Auras.tick_for(unit, auras_by_source, field,
				Callable(self, "side_of"))
			var totals: Dictionary = result[0]
			if not totals.is_empty():
				Auras.apply_tick(unit, totals)
				var parts: Array = []
				var keys: Array = totals.keys()
				keys.sort()
				for k in keys:
					parts.append("%s %+d" % [String(k), int(totals[k])])
				emit("  %s: auras (%s)" % [unit.label(), ", ".join(parts)])
				if not unit.alive:
					_fell(unit)
					continue
			if not unit.statuses.is_empty():
				var names: Array = []
				for e in unit.statuses:
					names.append(e.describe())
				Statuses.tick_round(unit)
				emit("  %s: %s" % [unit.label(), ", ".join(names)])
				if not unit.alive:
					_fell(unit)


# -- helpers -----------------------------------------------------------------

func _at(unit: Combatant) -> String:
	var h := field.find_unit(unit)
	if not field.contains(h):
		return "-"
	var o := Battlefield.axial_to_offset(h)
	return "%d,%d" % [o.x, o.y]


func emit(line: String) -> void:
	log.append(line)


func _side_of(unit: Combatant) -> RoundLoop.Side:
	for s in state.sides:
		if s.units.has(unit):
			return s
	return null


func _path_cost(path: Array) -> int:
	var c := 0
	for h in path:
		c += (field.tile(h) as Battlefield.Tile).move_cost
	return c


func _path_stamina(path: Array) -> int:
	var c := 0
	for h in path:
		c += (field.tile(h) as Battlefield.Tile).stam_cost
	return c


# -- commands ----------------------------------------------------------------

func cmd_move(unit: Combatant, col: int, row: int) -> void:
	var start := field.find_unit(unit)
	var goal := Battlefield.offset_to_axial(col, row)
	var path := field.path(start, goal, false, unit.movement_remaining)
	if path.is_empty():
		emit("%s cannot reach %d,%d" % [unit.label(), col, row])
		return
	var cost := _path_cost(path)
	if cost > unit.movement_remaining:
		emit("%s lacks movement for %d,%d" % [unit.label(), col, row])
		return
	field.remove_occupant(start)
	field.place(unit, goal)
	ActionPoints.spend_move(unit, cost, _path_stamina(path))
	emit("%s moves to %s (%d steps, %d total this round)"
		% [unit.label(), _at(unit), path.size(), unit.steps_this_round])


## Attack commands carry an implicit move: issuing an attack against a reachable
## target auto-paths the unit into contact, drawing from the same pool.
func _approach(unit: Combatant, target: Combatant) -> bool:
	var here := field.find_unit(unit)
	var there := field.find_unit(target)
	if Battlefield.distance(here, there) == 1:
		return true
	var best_cost := 1 << 30
	var best_dest := Vector2i.ZERO
	var best_path: Array[Vector2i] = []
	for h in field.neighbours(there):
		if not (field.tile(h) as Battlefield.Tile).free():
			continue
		var p := field.path(here, h, false, unit.movement_remaining)
		if p.is_empty():
			continue
		var cost := _path_cost(p)
		if cost > unit.movement_remaining or cost >= best_cost:
			continue
		best_cost = cost
		best_dest = h
		best_path = p
	if best_path.is_empty():
		return false
	field.remove_occupant(here)
	field.place(unit, best_dest)
	ActionPoints.spend_move(unit, best_cost, _path_stamina(best_path))
	emit("%s closes to %s (%d steps)" % [unit.label(), _at(unit), best_path.size()])
	return true


func _fell(unit: Combatant) -> void:
	var h := field.find_unit(unit)
	if field.contains(h):
		field.remove_occupant(h)
	emit("%s falls" % unit.label())


## One exchange: the attack and any retaliation, in the right order.
##
## Melee is answered; a shot is not. Первый удар moves the retaliation ahead of
## the blow that caused it, so a defender can kill an attacker before the attack
## lands.
func _strike(unit: Combatant, target: Combatant, kind: Combatant.AttackKind,
		action: Variant = null) -> void:
	var ex := Counterattack.resolve(unit, target, rng, kind, action)
	ActionPoints.spend_attack(unit)

	for entry in ex.order:
		if String(entry[0]) == "attack":
			emit("%s hits %s for %d (%s at %d/%d, stamina %d)"
				% [unit.label(), target.label(), int(entry[1]), target.label(),
					maxi(0, target.life), target.life_base, unit.stamina])
		else:
			emit("%s counters%s for %d (%s at %d/%d)"
				% [target.label(), " first" if ex.counter_first else "",
					int(entry[1]), unit.label(),
					maxi(0, unit.life), unit.life_base])
	if ex.defender_died:
		_fell(target)
	if ex.attacker_died:
		_fell(unit)
	if not ex.countered and ex.reason != Counterattack.NoCounter.RANGED \
			and ex.reason != Counterattack.NoCounter.DEAD:
		emit("  (%s does not counter: %s)"
			% [target.label(), Counterattack.REASON_TEXT[ex.reason]])


func cmd_attack(unit: Combatant, target: Combatant) -> void:
	if not target.alive:
		emit("%s has no target: %s is down" % [unit.label(), target.label()])
		return
	if unit.action_spent:
		emit("%s has already acted" % unit.label())
		return
	if not _approach(unit, target):
		emit("%s cannot reach %s" % [unit.label(), target.label()])
		return
	_strike(unit, target, Combatant.AttackKind.MELEE)


func cmd_shoot(unit: Combatant, target: Combatant) -> void:
	if not target.alive:
		emit("%s has no target: %s is down" % [unit.label(), target.label()])
		return
	if unit.action_spent:
		emit("%s has already acted" % unit.label())
		return
	if unit.ammo <= 0:
		emit("%s is out of ammunition" % unit.label())
		return
	var dist := Battlefield.distance(field.find_unit(unit), field.find_unit(target))
	if dist > unit.shooting_range:
		emit("%s is out of range of %s (%d > %d)"
			% [target.label(), unit.label(), dist, unit.shooting_range])
		return
	unit.ammo -= 1
	_strike(unit, target, Combatant.AttackKind.RANGED)


func cmd_rest(unit: Combatant) -> void:
	ActionPoints.rest(unit)
	emit("%s rests (stamina %d)" % [unit.label(), unit.stamina])


func cmd_extra_turn(unit: Combatant, c: Dictionary) -> void:
	var r: Array = ActionPoints.grant_extra_turn(
		unit, StringName(String(c.get("source", ""))),
		bool(c.get("once_per_round", false)),
		bool(c.get("fire_round_start", false)))
	emit("%s %s an extra turn (movement %d, steps %d)"
		% [unit.label(), "receives" if bool(r[0]) else "is refused",
			unit.movement_remaining, unit.steps_this_round])


func cmd_end_phase() -> void:
	if RoundLoop.end_phase(state):
		emit("-- round %d, side %d first --" % [state.round_number, state.active_side])
		_round_upkeep()
	else:
		emit("-- side %d --" % state.active_side)


# -- run ---------------------------------------------------------------------

## Install the pipeline AND the environment, then run.
##
## Both are needed and forgetting either is silent. Without a pipeline,
## Damage._run_hook returns immediately and NO modifier applies — innate
## abilities, statuses and auras alike. Without an environment, auras alone
## vanish. The first version of this bound only the environment, so a scenario
## ran with every modifier inert while looking entirely healthy.
func run() -> Dictionary:
	var registry := AbilityRegistry.new()
	Handlers.register_all(registry)
	Damage.bind_pipeline(Pipeline.new(registry))
	Damage.bind_environment(Callable(self, "environment"))
	var result := _run()
	Damage.bind_environment(Callable())
	Damage.bind_pipeline(null)
	return result


func _run() -> Dictionary:
	RoundLoop.begin_battle(state)
	emit("== %s (seed %d) ==" % [scenario_name, seed_value])
	emit("-- round %d, side %d first --" % [state.round_number, state.active_side])

	for c in spec.get("commands", []):
		var op := String(c["op"])
		if op == "end_phase":
			cmd_end_phase()
			continue
		var unit: Combatant = units.get(String(c.get("unit", "")))
		if unit == null:
			emit("unknown unit '%s'" % c.get("unit", ""))
			continue
		if not unit.alive:
			emit("%s is down and cannot act" % unit.label())
			continue
		var side := _side_of(unit)
		if side != null and side.id != state.active_side:
			emit("%s is not in the active side's phase" % unit.label())
			continue
		match op:
			"move":
				cmd_move(unit, int(c["to"][0]), int(c["to"][1]))
			"attack":
				cmd_attack(unit, units[String(c["target"])])
			"shoot":
				cmd_shoot(unit, units[String(c["target"])])
			"rest":
				cmd_rest(unit)
			"extra_turn":
				cmd_extra_turn(unit, c)
			_:
				emit("unknown command '%s'" % op)
		if RoundLoop.battle_over(state):
			emit("== battle over ==")
			break

	return {"name": scenario_name, "seed": seed_value,
			"log": log, "final": final_state()}


func final_state() -> Dictionary:
	var out: Dictionary = {}
	var names: Array = units.keys()
	names.sort()
	for n in names:
		var u: Combatant = units[n]
		out[n] = {
			"alive": u.alive, "life": maxi(0, u.life), "stamina": u.stamina,
			"at": _at(u), "steps_this_round": u.steps_this_round,
			"action_spent": u.action_spent,
			"movement_remaining": u.movement_remaining,
		}
	return out
