extends SceneTree

var failures := 0

class NestedScenario extends Scenario:
	var nested_query: Callable
	var nested_attack: float
	var nested_unit: Combatant

	func _init(specification: Dictionary) -> void:
		super(specification)

	func environment(unit: Combatant) -> Array:
		if nested_query.is_valid() and (nested_unit == null or nested_unit == unit):
			var query := nested_query
			nested_query = Callable()
			nested_attack = query.call()
		return super.environment(unit)


func _battle_spec(bonus: int) -> Dictionary:
	return {
		"profile": "native", "seed": 42,
		"battlefield": {"width": 3, "height": 2},
		"sides": [
			{"id": 0, "name": "Azure", "is_attacker": true, "leader_initiative": 2,
				"units": [{"id": "actor", "name": "Actor", "at": [0, 0],
				"attack": 10, "life": 20, "stamina": 10, "morale": 10,
				"auras": [{"id": "attack-bonus", "scope": "SELF", "affects": "ALLY",
					"modifiers": [{"handler": "stat_delta", "power": bonus,
						"params": {"stat": "attack"}}]}]}]},
			{"id": 1, "name": "Crimson", "leader_initiative": 1,
				"units": [{"id": "enemy", "name": "Enemy", "at": [1, 0],
				"life": 20, "stamina": 10, "morale": 10}]},
		],
	}


func _test_nested_query() -> void:
	var outer := NestedScenario.new(_battle_spec(2))
	var inner := Scenario.new(_battle_spec(7))
	var outer_session := ManualBattleSession.new(outer)
	var inner_session := ManualBattleSession.new(inner)
	if not outer_session.begin()["ok"] or not inner_session.begin()["ok"]:
		push_error("Could not start synthetic sessions.")
		quit(2)
		return
	var before := outer_session.current_attack(outer.units["actor"])
	outer.nested_query = func() -> float:
		return inner_session.current_attack(inner.units["actor"])
	var after := outer_session.current_attack(outer.units["actor"])
	var observed := [before, outer.nested_attack, after]
	print("Nested attack values: ", observed)
	_check(observed == [12.0, 17.0, 12.0], "nested inspection retains outer providers")


func _check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _snapshot(battle: Scenario) -> Dictionary:
	var positions := {}
	for key in battle.units:
		positions[key] = battle.field.find_unit(battle.units[key])
	return {"final": battle.final_state(), "positions": positions,
		"log": battle.log.duplicate(), "rng": battle.rng.calls.duplicate(true),
		"streams": battle.rng._streams.duplicate(true),
		"round": battle.state.round_number, "side": battle.state.active_side,
		"error": battle.runtime_error}


func _test_nested_refusal() -> void:
	var outer := NestedScenario.new(_battle_spec(2))
	var inner := Scenario.new(_battle_spec(7))
	var a := ManualBattleSession.new(outer)
	var b := ManualBattleSession.new(inner)
	a.begin()
	b.begin()
	var before_a := _snapshot(outer)
	var before_b := _snapshot(inner)
	outer.nested_query = func() -> float:
		var result := b.issue_command({"op": "attack", "unit": "missing", "target": "enemy"})
		_check(not result.accepted and not result.state_changed and result.events.is_empty(),
			"nested command is refused without events")
		return b.current_attack(inner.units["actor"])
	_check(a.current_attack(outer.units["actor"]) == 12,
		"outer providers survive nested refusal")
	_check(_snapshot(outer) == before_a and _snapshot(inner) == before_b,
		"nested refusal and queries preserve both combat states and RNG counters")


func _fatal_spec() -> Dictionary:
	var specification := _battle_spec(0)
	specification.sides[1].units[0].life = 200
	specification.sides[1].units[0].counter_attack = 100
	return specification


func _test_nested_fatal_retaliation() -> void:
	var outer := NestedScenario.new(_fatal_spec())
	var inner := Scenario.new(_fatal_spec())
	var a := ManualBattleSession.new(outer)
	var b := ManualBattleSession.new(inner)
	a.begin()
	b.begin()
	var command := {"op": "attack", "unit": "actor", "target": "enemy"}
	var after_b := {}
	outer.nested_unit = outer.units["actor"]
	outer.nested_query = func() -> float:
		var before_a := _snapshot(outer)
		var result := b.issue_command(command)
		_check(result.accepted and not result.errored,
			"inner fatal retaliation completes during outer attack lookup")
		_check(_snapshot(outer) == before_a,
			"inner fatal exchange sends no events or mutations to outer battle")
		after_b.merge(_snapshot(inner))
		return 0.0
	var result := a.issue_command(command)
	_check(result.accepted and not result.errored, "outer exchange completes after nested fatal")
	for battle in [outer, inner]:
		var victim: Combatant = battle.units["actor"]
		_check(not victim.alive and victim.life == 0 and not battle.field.has_unit(victim),
			"retaliation victim is dead and removed from its owning battlefield")
		var fatal_count := 0
		for line in battle.log:
			if "death_started" in line:
				fatal_count += 1
		_check(fatal_count == 1, "each battle records exactly its own fatal event")
	_check(_snapshot(inner) == after_b,
		"outer fatal retaliation leaves completed inner battle and RNG untouched")


func _test_provider_eligibility() -> void:
	var specification := _battle_spec(0)
	specification.actions = [{"id": "shield_bash", "target": 1,
		"cost_stamina": 5, "magnitude": 1, "consumes_action": true}]
	var actor: Dictionary = specification.sides[0].units[0]
	actor.stamina = 1
	actor.auras[0].modifiers = [{"handler": "stat_delta", "power": 0,
		"params": {"stat": "attack"}, "semantics": ["stamina.mutation_suppressed"]}]
	var battle := Scenario.new(specification)
	var session := ManualBattleSession.new(battle)
	_check(session.begin().ok, "provider eligibility session begins")
	var command := {"op": "action", "action": "shield_bash", "unit": "actor", "target": "enemy"}
	var before := _snapshot(battle)
	var query := session.query_command(command)
	_check(query.accepted and _snapshot(battle) == before,
		"query sees aura stamina suppression without state or RNG mutation")
	var result := session.issue_command(command)
	_check(result.accepted == query.accepted and result.accepted,
		"execution agrees with provider-dependent query at equal state")
	_check(battle.units["actor"].stamina == 1, "execution uses same suppression for payment")

	# The provider is live: removing its source changes both decisions immediately.
	var fresh := Scenario.new(specification)
	var fresh_session := ManualBattleSession.new(fresh)
	fresh_session.begin()
	_check(fresh_session.query_command(command).accepted, "live provider initially grants eligibility")
	fresh.auras_by_source.clear()
	before = _snapshot(fresh)
	query = fresh_session.query_command(command)
	result = fresh_session.issue_command(command)
	_check(not query.accepted and not result.accepted and query.reason == result.reason,
		"execution rechecks after provider removal and agrees with current query")
	_check(_snapshot(fresh) == before,
		"refused provider-dependent action leaves state and RNG untouched")


func _initialize() -> void:
	_test_nested_query()
	_test_nested_refusal()
	_test_nested_fatal_retaliation()
	_test_provider_eligibility()
	quit(0 if failures == 0 else 1)
