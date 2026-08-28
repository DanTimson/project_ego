extends SceneTree

## CX-015 typed tactical capability restriction acceptance coverage.

var failures := 0


class CountingRng extends Rng:
	var roll_calls := 0

	func _init() -> void:
		super(0)

	func roll(x: int, _stream: StringName = &"combat") -> int:
		roll_calls += 1
		return maxi(0, x - 1)


func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		(" — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1


func _fighter(unit_name: String, at: Array) -> Dictionary:
	return {
		"name": unit_name, "at": at, "life": 40, "life_base": 40,
		"attack": 9, "ranged_attack": 9, "shooting_range": 5, "ammo": 3,
		"ammo_base": 3, "counter_attack": 0, "defence": 1,
		"ranged_defence": 1, "speed": 3, "movement_remaining": 3,
		"stamina": 10, "stamina_base": 10, "morale": 10,
	}


func _action(action_id: String, magnitude: int = 4) -> Dictionary:
	if action_id == "crushing_blow":
		return {"id": action_id, "source_id": 59, "name": "Synthetic",
			"target": 1, "attack_surcharge": true, "is_attack": true,
			"damage_scale": 1.5}
	return {"id": "shield_bash", "source_id": 388, "name": "Synthetic",
		"target": 1, "cost_stamina": 1, "attack_surcharge": true,
		"consumes_action": true, "magnitude": magnitude, "is_attack": true,
		"damage_scale": 0.0, "excluded_targets": ["Бестелесный"]}


func _battle(rng: Variant = null) -> Scenario:
	var spec := {
		"name": "cx015", "profile": "native", "seed": 5,
		"battlefield": {"width": 4, "height": 3},
		"actions": [_action("crushing_blow"), _action("shield_bash")],
		"sides": [
			{"id": 0, "is_attacker": true, "leader_initiative": 1,
				"units": [_fighter("actor", [0, 0])]},
			{"id": 1, "leader_initiative": 0,
				"units": [_fighter("target", [1, 0])]},
		], "commands": [],
	}
	return Scenario.new(spec, rng)


func _restrict(unit: Combatant, capability: int, identity: String = "block") -> Status:
	var effect := Status.new()
	effect.id = StringName(identity)
	effect.name = "Synthetic %s block" % Status.capability_name(capability)
	effect.duration = 3
	effect.hostile = true
	effect.restrictions.append(capability)
	Statuses.apply(unit, effect)
	return effect


func _snapshot(sc: Scenario) -> Array:
	var actor: Combatant = sc.units["actor"]
	var target: Combatant = sc.units["target"]
	var status_state: Array = []
	for effect in actor.statuses:
		status_state.append([String(effect.id), effect.duration])
	var target_status_state: Array = []
	for effect in target.statuses:
		target_status_state.append([String(effect.id), effect.duration])
	return [
		actor.alive, actor.life, actor.stamina, actor.ammo, actor.action_spent,
		actor.movement_remaining, actor.steps_this_round, actor.forced_rest,
		actor.resting, actor.damage_received.duplicate(), sc.unit_position_offset(actor),
		target.alive, target.life, target.stamina, target.ammo, target.action_spent,
		target.movement_remaining, target.steps_this_round, target.forced_rest,
		target.resting, target.damage_received.duplicate(), sc.unit_position_offset(target),
		status_state, target_status_state,
	]


func _declarative_battle() -> Scenario:
	var actor_definition := _fighter("Actor", [0, 0])
	var target_definition := _fighter("Target", [0, 0])
	actor_definition.erase("at")
	target_definition.erase("at")
	var recipe := {"version": 1, "operations": [{
		"kind": "attack", "mode": "melee",
		"scale": {"numerator": 1, "denominator": 1},
	}]}
	var provider := ScenarioContentProvider.new("alpha", {
		"alpha:unit/1": actor_definition,
		"alpha:unit/2": target_definition,
	}, "v1", "", "", {
		"definitions": [{"source_id": 700, "name": "Synthetic pack action",
			"target": "enemy_melee", "recipe": recipe}],
		"grants": {"alpha:unit/1": [{"source_id": 700}]},
	})
	var spec := {
		"name": "cx015 declarative", "profile": "native", "seed": 5,
		"content": {"pack": "alpha", "version": "v1"},
		"battlefield": {"width": 3, "height": 2},
		"sides": [
			{"id": 0, "units": [{"id": "actor", "def": "alpha:unit/1",
				"at": [0, 0]}]},
			{"id": 1, "units": [{"id": "target", "def": "alpha:unit/2",
				"at": [1, 0]}]},
		], "commands": [],
	}
	return Scenario.new(spec, null, provider)


func _has_property(value: Object, property_name: StringName) -> bool:
	for property in value.get_property_list():
		if StringName(property["name"]) == property_name:
			return true
	return false


func _test_independence_matrix() -> void:
	print("\n[A] independence matrix and diagnostics")
	var capabilities := [Status.Capability.MOVEMENT, Status.Capability.MELEE,
		Status.Capability.RANGED, Status.Capability.CASTING,
		Status.Capability.ACTIVATED_ACTION]
	for blocked in capabilities:
		var unit := Combatant.new()
		unit.name = "unit"
		_restrict(unit, blocked, Status.capability_name(blocked))
		for queried in capabilities:
			var result := Statuses.can_perform(unit, queried)
			var expected_allowed: bool = queried != blocked
			_check(bool(result[0]) == expected_allowed,
				"%s restriction leaves %s %s" % [Status.capability_name(blocked),
					Status.capability_name(queried), "allowed" if expected_allowed else "blocked"])
			if not expected_allowed:
				_check(String(result[1]) == "Synthetic %s block" % Status.capability_name(blocked),
					"blocking status is diagnostic")
	var unknown := Statuses.can_perform(Combatant.new(), 999)
	_check(not bool(unknown[0]) and String(unknown[1]) == "unknown capability",
		"unknown typed query fails closed")


func _test_composition_and_lifecycle() -> void:
	print("\n[B/C] composition, contributors, and existing lifecycle")
	var capabilities := [Status.Capability.MOVEMENT, Status.Capability.MELEE,
		Status.Capability.RANGED, Status.Capability.CASTING,
		Status.Capability.ACTIVATED_ACTION]
	var parsed := Status.parse_restrictions([
		"movement", "melee", "ranged", "casting", "activated_action", "melee"])
	_check(bool(parsed["ok"]) and parsed["restrictions"].size() == 5,
		"duplicate declarations are idempotent")
	var unit := Combatant.new()
	var all_status := Status.from_dict({"id": "all", "restrictions": [
		"movement", "melee", "ranged", "casting", "activated_action", "melee"]})
	Statuses.apply(unit, all_status)
	_check(capabilities.all(func(capability):
		return not bool(Statuses.can_perform(unit, capability)[0])),
		"one status composes a full disable")
	_check(all_status.to_dict()["restrictions"] == [
		"movement", "melee", "ranged", "casting", "activated_action"],
		"serialization preserves normalized restrictions")

	var split := Combatant.new()
	for capability in capabilities:
		_restrict(split, capability, Status.capability_name(capability))
	_restrict(split, Status.Capability.MELEE, "melee-second")
	_check(capabilities.all(func(capability):
		return not bool(Statuses.can_perform(split, capability)[0])),
		"split statuses union to the same full disable")
	Statuses.remove(split, &"melee")
	_check(not bool(Statuses.can_perform(split, Status.Capability.MELEE)[0]),
		"one of two melee contributors keeps blocking")
	Statuses.remove(split, &"melee-second")
	_check(bool(Statuses.can_perform(split, Status.Capability.MELEE)[0])
		and not bool(Statuses.can_perform(split, Status.Capability.RANGED)[0]),
		"removal restores only unblocked capabilities")

	var expiring := Combatant.new()
	var temporary := _restrict(expiring, Status.Capability.RANGED, "temporary")
	temporary.duration = 1
	Statuses.reduce_duration(expiring, 1)
	_check(bool(Statuses.can_perform(expiring, Status.Capability.RANGED)[0]),
		"existing explicit duration removal leaves no stale restriction")


func _test_model_boundary_and_generic_removal() -> void:
	print("\n[F] model boundary and generic authority removal")
	var original := Status.from_dict({"id": "copy",
		"restrictions": ["movement", "movement"]})
	var cloned := original.copy()
	original.restrictions.clear()
	_check(cloned.restrictions == [Status.Capability.MOVEMENT],
		"copy preserves restrictions without mutable aliasing")
	var invalid := Status.parse_restrictions(["raw-legacy-name"])
	_check(not bool(invalid["ok"]) and "unknown status capability" in invalid["reason"],
		"unknown serialized capability fails closed")
	_check(not bool(Status.parse_restrictions(null)["ok"])
		and not bool(Status.parse_restrictions("movement")["ok"])
		and not bool(Status.parse_restrictions([1])["ok"]),
		"malformed restriction declarations fail closed")
	_check(not _has_property(Status.new(), &"prevents_action"),
		"Status has no generic prevents_action field")
	_check(Status.from_dict({"id": "obsolete", "prevents_action": true}) == null,
		"removed prevents_action input is rejected")
	_check(not Statuses.new().has_method("can_act"),
		"Statuses has no generic can_act query")


func _test_integrated_refusals() -> void:
	print("\n[D] integrated mutation-free refusal and precedence")
	var spent := Combatant.new()
	spent.action_spent = true
	spent.movement_remaining = 0
	_restrict(spent, Status.Capability.MOVEMENT)
	_check(ActionPoints.can_move(spent) == ActionPoints.Refusal.ACTION_SPENT,
		"action-spent keeps precedence over movement restriction")
	spent.action_spent = false
	_check(ActionPoints.can_move(spent) == ActionPoints.Refusal.RESTRICTED,
		"movement restriction precedes capacity refusal")

	var cases := [
		[Status.Capability.MOVEMENT, "move"],
		[Status.Capability.MELEE, "attack"],
		[Status.Capability.RANGED, "shoot"],
		[Status.Capability.ACTIVATED_ACTION, "crushing_blow"],
		[Status.Capability.ACTIVATED_ACTION, "shield_bash"],
	]
	for case in cases:
		var rng := CountingRng.new()
		var sc := _battle(rng)
		var actor: Combatant = sc.units["actor"]
		var target: Combatant = sc.units["target"]
		_restrict(actor, int(case[0]))
		var before := _snapshot(sc)
		match String(case[1]):
			"move":
				sc.cmd_move(actor, 0, 1)
			"attack":
				sc.cmd_attack(actor, target)
			"shoot":
				sc.cmd_shoot(actor, target)
			_:
				sc.cmd_action(actor, String(case[1]), target)
		_check(_snapshot(sc) == before and rng.roll_calls == 0,
			"%s refusal precedes payment/RNG/damage/terminality" % case[1], str(sc.log))
		_check(Status.capability_name(int(case[0])) in sc.log[-1],
			"%s refusal identifies capability" % case[1])

	# query_command is the authoritative presentation gate and must be equally inert.
	var query_cases := [
		[Status.Capability.MOVEMENT,
			{"op": "move", "unit": "actor", "to": [0, 1]}],
		[Status.Capability.MELEE,
			{"op": "attack", "unit": "actor", "target": "target"}],
		[Status.Capability.RANGED,
			{"op": "shoot", "unit": "actor", "target": "target"}],
		[Status.Capability.ACTIVATED_ACTION,
			{"op": "action", "unit": "actor", "action": "shield_bash",
				"target": "target"}],
	]
	for query_case in query_cases:
		var query_rng := CountingRng.new()
		var manual := _battle(query_rng)
		RoundLoop.begin_battle(manual.state)
		var query_actor: Combatant = manual.units["actor"]
		_restrict(query_actor, int(query_case[0]))
		var query_before := _snapshot(manual)
		var query := manual.query_command(query_case[1])
		var capability_name := Status.capability_name(int(query_case[0]))
		_check(not bool(query["accepted"]) and capability_name in query["reason"]
			and _snapshot(manual) == query_before and query_rng.roll_calls == 0,
			"manual %s query refuses without mutation or RNG" % capability_name,
			str(query))
		var execution := manual.execute_command(query_case[1])
		_check(not bool(execution["accepted"]) and not bool(execution["state_changed"])
			and execution["events"].is_empty() and _snapshot(manual) == query_before,
			"manual %s execution gate remains mutation-free" % capability_name,
			str(execution))


func _test_command_independence() -> void:
	print("\n[A/E] command and activated-action boundary independence")
	var movement_only := _battle(CountingRng.new())
	_restrict(movement_only.units["actor"], Status.Capability.MOVEMENT)
	movement_only.cmd_attack(movement_only.units["actor"], movement_only.units["target"])
	_check(movement_only.units["target"].life < 40,
		"movement restriction leaves ordinary melee allowed")

	var melee_only := _battle(CountingRng.new())
	_restrict(melee_only.units["actor"], Status.Capability.MELEE)
	melee_only.cmd_action(melee_only.units["actor"], "crushing_blow", melee_only.units["target"])
	_check(melee_only.units["target"].life < 40,
		"melee restriction leaves Crushing Blow allowed")

	var activated_only := _battle(CountingRng.new())
	_restrict(activated_only.units["actor"], Status.Capability.ACTIVATED_ACTION)
	activated_only.cmd_attack(activated_only.units["actor"], activated_only.units["target"])
	_check(activated_only.units["target"].life < 40,
		"activated-action restriction leaves ordinary melee allowed")

	var ranged_only := _battle(CountingRng.new())
	_restrict(ranged_only.units["actor"], Status.Capability.RANGED)
	ranged_only.cmd_move(ranged_only.units["actor"], 0, 1)
	_check(ranged_only.unit_position_offset(ranged_only.units["actor"]) == Vector2i(0, 1),
		"ranged restriction leaves movement allowed")

	var declarative_blocked := _declarative_battle()
	_restrict(declarative_blocked.units["actor"], Status.Capability.ACTIVATED_ACTION)
	var before := _snapshot(declarative_blocked)
	declarative_blocked.cmd_action(declarative_blocked.units["actor"],
		"alpha:action/700", declarative_blocked.units["target"])
	_check(_snapshot(declarative_blocked) == before
		and "activated_action restricted" in declarative_blocked.log[-1],
		"activated restriction blocks declarative pack action before execution")

	var declarative_melee := _declarative_battle()
	_restrict(declarative_melee.units["actor"], Status.Capability.MELEE)
	declarative_melee.cmd_action(declarative_melee.units["actor"],
		"alpha:action/700", declarative_melee.units["target"])
	_check(declarative_melee.units["target"].life < 40
		and declarative_melee.log.any(func(line): return "resolved plan [AttackOp]" in line),
		"melee restriction does not inspect AttackOp inside activated action")


func _test_restriction_serialization_canonicalizes_noncanonical_input() -> void:
	print("\n[CX-015] canonical restriction serialization")
	var effect := Status.from_dict({
		"id": "serialization-order",
		"restrictions": ["ranged", "movement"],
	})
	_check(effect != null, "non-canonical restriction input parses")
	if effect == null:
		return
	_check(
		effect.to_dict()["restrictions"] == ["movement", "ranged"],
		"restriction serialization uses canonical capability order",
	)


func _init() -> void:
	_test_restriction_serialization_canonicalizes_noncanonical_input()
	_test_independence_matrix()
	_test_composition_and_lifecycle()
	_test_model_boundary_and_generic_removal()
	_test_integrated_refusals()
	_test_command_independence()
	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures else 0)
