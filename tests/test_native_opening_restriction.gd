extends SceneTree

const TACTICAL_SCENE := "res://game/tactical/tactical_main.tscn"
const RANGER := "azure-ranger-17"
const GUARD := "crimson-guard-42"
var failures := 0


class RestartProbeController extends TacticalController:
	var remove_ranger := false

	func _load_scenario_spec() -> Dictionary:
		var specification := super._load_scenario_spec()
		if remove_ranger:
			var roster: Array = specification["sides"][0]["units"]
			for index in range(roster.size() - 1, -1, -1):
				if roster[index]["id"] == RANGER:
					roster.remove_at(index)
		return specification


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _snapshot(battle: Scenario) -> Dictionary:
	return {"final": battle.final_state(), "rng": battle.rng.calls.duplicate(true),
		"streams": battle.rng._streams.duplicate(true),
		"log": battle.log.duplicate(), "round": battle.state.round_number,
		"side": battle.state.active_side}


func _effect() -> Status:
	return Status.from_dict({"id": "opening", "name": "Test Bowstring",
		"restrictions": ["ranged"]})


func _battle(profile: String = "native") -> Scenario:
	return Scenario.new({"profile": profile, "seed": 42,
		"content_compatibility_override": "genesis",
		"death_replacement_load_mode": "permissive",
		"battlefield": {"width": 4, "height": 2}, "sides": [
			{"id": 0, "name": "First", "is_attacker": true, "units": [
				{"id": "first", "name": "First", "at": [0, 0],
					"life": 20, "stamina": 10, "morale": 10, "speed": 2}]},
			{"id": 1, "name": "Second", "units": [
				{"id": "second", "name": "Second", "at": [2, 0],
					"life": 20, "stamina": 10, "morale": 10, "speed": 2}]}]})


func _expiry_count(battle: Scenario) -> int:
	var count := 0
	for line in battle.log:
		if line.contains("expires at end of"):
			count += 1
	return count


func _test_second_side() -> void:
	var battle := _battle()
	var unit: Combatant = battle.units["second"]
	var ordinary := Status.from_dict({"id": "ordinary", "duration": 3})
	Statuses.apply(unit, ordinary)
	_check(battle.setup_opening_restriction("second", _effect()) == "", "setup second side")
	var installed: Status = unit.statuses.back()
	installed.modifiers.append(Modifier.from_dict({"handler": "stat_delta", "power": 5,
		"params": {"stat": "speed"}}))
	var session := ManualBattleSession.new(battle)
	session.begin()
	_check(unit.movement_remaining == 7, "opening status participates in initial speed refresh")
	var before := _snapshot(battle)
	session.query_command({"op": "rest", "unit": "first"})
	_check(before == _snapshot(battle), "query does not expire or mutate")
	session.issue_command({"op": "end_phase"})
	_check(unit.statuses.has(installed) and _expiry_count(battle) == 0,
		"other side's pass preserves restriction")
	var result := session.issue_command({"op": "rest", "unit": "second"})
	_check(result["accepted"] and not unit.statuses.has(installed)
		and battle.state.round_number == 2 and _expiry_count(battle) == 1,
		"owning side exhaustion expires once and starts round")
	var expiry_index := -1
	var round_index := -1
	for i in battle.log.size():
		if battle.log[i].contains("expires at end of"):
			expiry_index = i
		if battle.log[i].begins_with("-- round 2"):
			round_index = i
	_check(expiry_index >= 0 and expiry_index < round_index,
		"expiry event precedes new-round event")
	_check(unit.movement_remaining == 2, "expiry precedes new-round speed refresh")
	_check(unit.statuses.has(ordinary) and ordinary.duration == 3,
		"ordinary duration remains unchanged")
	session.issue_command({"op": "end_phase"})
	session.issue_command({"op": "end_phase"})
	_check(_expiry_count(battle) == 1, "later boundaries do not duplicate expiry")
	before = _snapshot(battle)
	_check(battle.setup_opening_restriction("second", _effect()) != ""
		and before == _snapshot(battle), "late setup is mutation-free refusal")


func _test_instance_lifecycle() -> void:
	var battle := _battle()
	var unit: Combatant = battle.units["second"]
	battle.setup_opening_restriction("second", _effect())
	var installed: Status = unit.statuses.back()
	var unrelated := _effect()
	unrelated.stacking = Status.Stacking.CUMULATIVE
	Statuses.apply(unit, unrelated)
	# Change roster ownership, retaining the setup-side expiry contract.
	battle.state.side(1).units.erase(unit)
	var other: Combatant = battle.units["first"]
	battle.state.side(0).units.erase(other)
	battle.state.side(1).units.append(other)
	battle.state.side(0).units.append(unit)
	var session := ManualBattleSession.new(battle)
	session.begin()
	battle.cmd_end_phase()
	_check(unit.statuses.has(installed), "new owner's boundary does not expire restriction")
	_check(battle.state.active_side == 1, "side change preserves a playable opposing phase")
	battle.cmd_end_phase()
	_check(not unit.statuses.has(installed) and unit.statuses.has(unrelated)
		and _expiry_count(battle) == 1, "original side expires only tracked instance")

	for death in [false, true]:
		battle = _battle()
		unit = battle.units["second"]
		battle.setup_opening_restriction("second", _effect())
		if death:
			unit.life = 0
			battle._resolve_fatal_event(unit)
			_check(unit.statuses.is_empty() and not unit.alive,
				"real death lifecycle clears tracked restriction")
		else:
			Statuses.remove(unit, &"opening")
		unrelated = _effect()
		Statuses.apply(unit, unrelated)
		session = ManualBattleSession.new(battle)
		session.begin()
		battle.state.active_side = 1
		battle.cmd_end_phase()
		_check(unit.statuses.has(unrelated) and _expiry_count(battle) == 0,
			"stale tracking after %s preserves same-ID status without expiry" %
				("death" if death else "removal"))


func _test_setup_refusals() -> void:
	var battle := _battle("genesis")
	var unit: Combatant = battle.units["second"]
	var ordinary := _effect()
	Statuses.apply(unit, ordinary)
	_check(battle.setup_opening_restriction("second", _effect()).contains("native")
		and unit.statuses.size() == 1, "legacy setup refuses without status mutation")
	var session := ManualBattleSession.new(battle)
	session.begin()
	battle.cmd_end_phase()
	battle.cmd_end_phase()
	_check(unit.statuses.has(ordinary) and _expiry_count(battle) == 0,
		"legacy phase boundaries do not expire ordinary restriction")
	battle = _battle()
	var before := _snapshot(battle)
	_check(battle.setup_opening_restriction("missing", _effect()) != ""
		and before == _snapshot(battle), "missing instance refuses without mutation")
	_check(battle.setup_opening_restriction("second", null) != ""
		and before == _snapshot(battle), "invalid effect refuses without mutation")
	battle = _battle()
	battle.construction_error = "synthetic invalid battle"
	_check(battle.setup_opening_restriction("second", _effect()) != "",
		"invalid battle refuses setup")


func _test_refused_restart() -> void:
	var scene := (load(TACTICAL_SCENE) as PackedScene).instantiate()
	scene.set_script(RestartProbeController)
	var controller := scene as RestartProbeController
	root.add_child(controller)
	_check(controller.select_unit(RANGER), "select Ranger before refused restart")
	var previous := controller.session
	var selected := controller.selected_unit
	controller.remove_ranger = true
	_check(not controller.restart_battle(), "missing opening restriction target refuses restart")
	_check(controller.session == previous and previous.started
		and controller.scenario == previous.scenario and controller.selected_unit == selected,
		"refused restart preserves the live battle and selection")
	_check(controller.feedback_label.text.contains("living battle instance"),
		"refused restart shows the setup error")
	controller.queue_free()
	await process_frame


func _run() -> void:
	var controller := (load(TACTICAL_SCENE) as PackedScene).instantiate() as TacticalController
	root.add_child(controller)
	await process_frame
	_check(controller.select_unit(RANGER), "select Ranger in real scene")
	var ranger: Combatant = controller.scenario.units[RANGER]
	_check(controller.effects_label.text.contains("Tangled Bowstring")
		and controller.effects_label.text.contains("opening side phase"),
		"status UI names cause and expiry")
	_check(controller.dispatch_move(Vector2i(2, 3))["accepted"], "move while ranged-restricted")
	var before := _snapshot(controller.scenario)
	var query := controller.session.query_command({
		"op": "shoot", "unit": RANGER, "target": GUARD})
	print("Opening Ranger can shoot: ", query["accepted"])
	_check(not query["accepted"] and String(query["reason"]).contains("Tangled Bowstring"),
		"advisory refusal names bowstring")
	_check(before == _snapshot(controller.scenario), "advisory preserves state and RNG")
	controller.ranged_button.pressed.emit()
	_check(controller.latest_feedback.contains("Tangled Bowstring")
		and controller.latest_feedback.contains("opening side phase"),
		"Ranged control explains cause and expiry")
	var refusal := controller.dispatch_ranged(GUARD)
	_check(not refusal["accepted"] and String(refusal["reason"]).contains("Tangled Bowstring")
		and before == _snapshot(controller.scenario),
		"execution refusal preserves ammo, stamina, activation, RNG and restriction")
	controller.pass_side()
	controller.pass_side()
	_check(controller.select_unit(RANGER), "reselect Ranger next Azure phase")
	controller.ranged_button.pressed.emit()
	_check(controller.input_mode == controller.MODE_RANGED, "enter Ranged after expiry")
	_check(controller.dispatch_ranged(GUARD)["accepted"] and ranger.ammo == 5,
		"legal shot after expiry spends ammunition")
	_check(_expiry_count(controller.scenario) == 1, "scene logs one expiry")
	controller.queue_free()
	await process_frame
	_test_second_side()
	_test_instance_lifecycle()
	_test_setup_refusals()
	await _test_refused_restart()
	quit(0 if failures == 0 else 1)
