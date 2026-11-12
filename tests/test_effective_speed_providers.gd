extends SceneTree


var failures := 0


func _specification() -> Dictionary:
	return {
		"profile": "native",
		"seed": 42,
		"battlefield": {"width": 3, "height": 2},
		"sides": [
			{"id": 0, "is_attacker": true, "units": [{
				"id": "actor", "name": "Actor", "at": [0, 0],
				"speed": 1, "life": 20, "stamina": 2, "morale": 10,
				"modifiers": [
					{"ability": 101, "handler": "stat_delta", "power": 3,
						"params": {"stat": "speed"}},
					{"ability": 7, "handler": "noop", "power": 99},
				],
				"statuses": [{"id": "runtime-speed", "duration": -1, "modifiers": [
					{"ability": 102, "handler": "stat_delta", "power": 2,
						"params": {"stat": "speed"}},
				]}],
				"auras": [{"id": "ordinary-aura", "scope": "SELF", "affects": "ALLY",
					"modifiers": [{"handler": "stat_delta", "power": 9,
						"params": {"stat": "speed"}}]}],
			}]},
			{"id": 1, "units": [{"id": "enemy", "name": "Enemy", "at": [1, 0],
				"life": 20, "stamina": 10, "morale": 10}]},
		],
	}

func _check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _speed(battle: Scenario, unit: Combatant) -> int:
	return int(ActionPoints.effective_speed(unit, battle.combat.speed_contribution(unit))[0])


func _test_terms() -> void:
	var battle := Scenario.new(_specification())
	var unit: Combatant = battle.units.actor
	var personal: Array = unit.modifiers.duplicate()
	var runtime: Array[Status] = unit.statuses.duplicate()
	_check(battle.combat.stat_contributions(unit, &"speed") ==
		{"personal": 3, "runtime": 2, "commander": 0}, "separate provider channels")
	_check(_speed(battle, unit) == 4, "combined terms precede both decrements")
	unit.statuses.clear()
	_check(_speed(battle, unit) == 2, "personal alone")
	unit.modifiers = [personal[1]]
	_check(_speed(battle, unit) == 1, "raw ID and tactical aura contribute zero")
	unit.statuses = runtime
	_check(_speed(battle, unit) == 1, "runtime alone at stamina two")
	unit.stamina = 5
	_check(_speed(battle, unit) == 3, "runtime alone before stamina reductions")
	unit.modifiers = personal
	for vector in [[2, 4], [3, 5], [4, 5], [5, 6]]:
		unit.stamina = vector[0]
		_check(_speed(battle, unit) == vector[1], "fixed stamina boundary %d" % vector[0])
	unit.modifiers[0].power = -1
	_check(_speed(battle, unit) == 2, "signed negative delta reduces a positive total")
	unit.modifiers[0].power = -4
	_check(_speed(battle, unit) == 1, "signed negative contribution floors at one")
	unit.stamina = 2
	_check(_speed(battle, unit) == 1, "negative total cannot trigger a decrement")
	_check(ActionPoints.effective_speed(unit)[0] == 1, "standalone zero contribution")
	unit.modifiers[0].power = 3
	var trace: Trace = ActionPoints.effective_speed(unit, 5)[1]
	_check(trace.steps[0].source == "speed provider contribution"
		and trace.steps[1].after == 5.0 and trace.steps[2].after == 4.0,
		"trace exposes provider addition before guarded decrements")

	unit.stamina = 10
	unit.movement_remaining = 4
	ScenarioNumericOrdering.spend_attack(unit, Combatant.AttackKind.MELEE, battle.combat)
	_check(unit.stamina == 9 and unit.movement_remaining == 4,
		"battle melee cost keeps its established boundary despite speed providers")


func _test_lifecycle() -> void:
	var battle := Scenario.new(_specification())
	var session := ManualBattleSession.new(battle)
	_check(bool(session.begin().ok), "manual battle begins")
	var unit: Combatant = battle.units.actor
	print("Round-start movement capacity: ", unit.movement_remaining)
	_check(unit.movement_remaining == 4, "starter round capacity")
	unit.movement_remaining = 1
	Statuses.remove(unit, &"runtime-speed")
	_check(session.can_select(unit) and session.selectable_units().has(unit)
		and unit.movement_remaining == 1, "status removal and selection preserve live capacity")
	_check(bool(session.issue_command({"op": "move", "unit": "actor", "to": [0, 1]}).accepted)
		and unit.movement_remaining == 0 and unit.speed == 1,
		"ordinary movement spends live capacity without refreshing or rewriting base speed")
	battle.cmd_extra_turn(unit, {"source": "synthetic", "once_per_round": true})
	_check(unit.movement_remaining == 2, "accepted extra turn resolves current providers")
	unit.movement_remaining = 1
	unit.modifiers[0].power = 5
	battle.cmd_extra_turn(unit, {"source": "synthetic", "once_per_round": true})
	_check(unit.movement_remaining == 1, "refused extra turn cannot refresh capacity")
	_check(bool(session.issue_command({"op": "end_phase"}).accepted), "manual explicit pass")
	_check(bool(session.issue_command({"op": "end_phase"}).accepted)
		and unit.movement_remaining == 4 and battle.state.round_number == 2,
		"manual explicit true round refresh uses fresh providers")
	unit.modifiers[0].power = 4
	_check(bool(session.issue_command({"op": "rest", "unit": "actor"}).accepted),
		"manual exhaustion switches side")
	_check(bool(session.issue_command({"op": "rest", "unit": "enemy"}).accepted)
		and battle.state.round_number == 3 and unit.movement_remaining == 3,
		"manual exhaustion true round refresh uses fresh stamina and providers")
	for commands in [[], [{"op": "end_phase"}, {"op": "end_phase"}],
			[{"op": "rest", "unit": "actor"}, {"op": "rest", "unit": "enemy"}],
			[{"op": "extra_turn", "unit": "actor"}]]:
		var specification := _specification()
		specification["commands"] = commands
		var scripted := Scenario.new(specification)
		scripted.run()
		var expected := 4  # Rest is capped at the original stamina maximum of two.
		_check(scripted.units.actor.movement_remaining == expected,
			"scripted start/pass/exhaustion/extra-turn path %s" % str(commands))


func _test_ranged() -> void:
	for vector in [[5, 2], [6, 1], [7, 1]]:
		var specification := _specification()
		specification.profile = "genesis"
		specification.death_replacement_load_mode = "permissive"
		var actor: Dictionary = specification.sides[0].units[0]
		actor.stamina = 10
		actor.ranged_attack = 1
		actor.ammo = 10
		actor.shooting_range = 4
		specification.sides[1].units[0].at = [2, 0]
		var battle := Scenario.new(specification)
		var session := ManualBattleSession.new(battle)
		_check(bool(session.begin().ok), "Genesis ranged session begins")
		var unit: Combatant = battle.units.actor
		unit.movement_remaining = vector[0]
		_check(ActionPoints.attack_stamina_cost(unit) == 1,
			"standalone melee cost retains its existing base-speed boundary")
		var result := session.issue_command({"op": "shoot", "unit": "actor", "target": "enemy"})
		_check(bool(result.accepted) and unit.stamina == 10 - vector[1],
			"authoritative ranged capacity %d costs %d" % [vector[0], vector[1]])
		_check(unit.action_spent and unit.movement_remaining == 0, "ranged terminal clearing")
	# Change the provider after refresh: old speed 6, new speed 4, capacity 4.
	for suppressed in [false, true]:
		var specification := _specification()
		specification.profile = "genesis"
		specification.death_replacement_load_mode = "permissive"
		var actor: Dictionary = specification.sides[0].units[0]
		actor.stamina = 10
		actor.ranged_attack = 1
		actor.ammo = 10
		actor.shooting_range = 4
		if suppressed:
			actor.modifiers.append({"handler": "noop", "semantics": ["stamina.mutation_suppressed"]})
		specification.sides[1].units[0].at = [2, 0]
		var battle := Scenario.new(specification)
		var session := ManualBattleSession.new(battle)
		session.begin()
		var unit: Combatant = battle.units.actor
		unit.movement_remaining = 4
		Statuses.remove(unit, &"runtime-speed")
		var result := session.issue_command({"op": "shoot", "unit": "actor", "target": "enemy"})
		_check(bool(result.accepted) and unit.stamina == (10 if suppressed else 9),
			"ranged spend resolves changed provider; suppression %s" % str(suppressed))
		_check(unit.movement_remaining == 0 and unit.action_spent, "changed-provider terminal clearing")


func _test_rollback() -> void:
	var battle := Scenario.new(_specification())
	var unit: Combatant = battle.units.actor
	var original := unit.definition_snapshot()
	original.speed = 2
	original.modifiers = [Modifier.make(103, &"stat_delta", Modifier.Hook.STAT_PASSIVE,
		4, {"stat": "speed"})]
	unit.original_definition = original
	unit.modifiers[0].power = 20
	unit.movement_remaining = 12
	var marker := Status.new()
	marker.id = &"rollback"
	marker.modifiers.append(Modifier.make(
		DeathLifecycle.ROLLBACK, &"noop", Modifier.Hook.STAT_PASSIVE))
	unit.statuses.append(marker)
	unit.life = 0
	DeathLifecycle.resolve(unit, battle.field, battle.state.sides,
		Callable(), Callable(), battle.combat)
	_check(unit.speed == 2 and unit.modifiers[0].power == 4
		and unit.movement_remaining == 6,
		"rollback clamps using restored personal and live runtime terms")
	_check(unit.statuses.is_empty(), "rollback preserves later status-clear ordering")


func _initialize() -> void:
	_test_terms()
	_test_lifecycle()
	_test_ranged()
	_test_rollback()
	quit(0 if failures == 0 else 1)
