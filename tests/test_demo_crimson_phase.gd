extends SceneTree

const MENU := "res://game/demo/demo_main.tscn"

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var menu := (load(MENU) as PackedScene).instantiate() as DemoMain
	root.add_child(menu)
	if menu.play_demo() != OK:
		push_error("Could not launch the tactical demo from the menu.")
		quit(2)
		return
	await process_frame
	await process_frame
	var controller := current_scene as TacticalController
	if controller == null or controller.session == null or not controller.session.started:
		push_error("The menu did not start a tactical session.")
		quit(2)
		return
	var azure := controller.session.active_side_id()
	var result := controller.pass_side()
	if not result["accepted"]:
		push_error("The opening Azure pass was refused.")
		quit(2)
		return
	for frame in range(4):
		await process_frame
	var returned := controller.session.active_side_id() == azure
	print("Crimson phase returned control: ", returned)
	_check(returned and controller.last_crimson_report.commands.size() > 1,
		"Crimson makes a useful command before returning")
	_check(controller.latest_feedback.contains("Crimson:")
		and controller.events_label.text != "", "readable summary and retained events")
	var first := _snapshot(controller)
	controller.restart_battle()
	controller.pass_side()
	_check(first == _snapshot(controller), "same seed and input repeat commands, events and state")
	controller.restart_battle()
	_check(controller.automated_crimson and controller.session.active_side_id() == 0
		and controller.last_crimson_report.is_empty(), "restart retains mode with fresh Azure phase")
	for id in ["azure-ranger-17", "azure-vanguard-01"]:
		controller._apply_command_result(controller.session.issue_command({"op": "rest", "unit": id}))
	_check(controller.session.active_side_id() == 0
		and not controller.last_crimson_report.is_empty(), "Azure exhaustion starts Crimson")
	_check(controller.scenario.opening_restriction_description(
		controller.scenario.units["azure-ranger-17"]) == "", "opening restriction expires")
	var manual := load("res://game/tactical/tactical_main.tscn").instantiate() as TacticalController
	root.add_child(manual)
	manual.pass_side()
	_check(manual.session.active_side_id() == 1 and manual.last_crimson_report.is_empty(),
		"direct tactical scene remains hot-seat")
	manual.queue_free()
	_test_policy()
	_test_action_handoff(controller)
	controller.queue_free()
	menu.queue_free()
	await process_frame
	quit(0 if returned and failures == 0 else 1)


func _test_action_handoff(controller: TacticalController) -> void:
	_check(controller.restart_battle(), "restart for action handoff")
	var battle := controller.scenario
	var vanguard: Combatant = battle.units["azure-vanguard-01"]
	battle.field.remove_occupant(battle.field.find_unit(vanguard))
	_check(battle.field.place(vanguard, Battlefield.offset_to_axial(4, 1)),
		"place Vanguard next to Guard")
	battle.units["azure-ranger-17"].action_spent = true
	_check(controller.select_unit(vanguard.instance_id), "select last Azure activation")
	var result := controller.dispatch_action("crimson-guard-42")
	_check(result["accepted"] and controller.session.active_side_id() == 0
		and not controller.last_crimson_report.commands.is_empty(),
		"terminal Stamina Drain hands off to Crimson and returns")
	_check(controller.feedback_label.text.begins_with("Stamina Drain: Guard stamina 10 → 7\n")
		and controller.feedback_label.text.contains("Crimson:"),
		"handoff shows drain result before Crimson summary")


func _check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _snapshot(controller: TacticalController) -> Dictionary:
	var report := controller.last_crimson_report.duplicate(true)
	for result in report.get("results", []):
		var detached: Array = []
		for observation in result.get("observations", []):
			detached.append(observation.to_dict())
		result["observations"] = detached
	return {"state": controller.scenario.final_state(),
		"log": controller.scenario.log.duplicate(),
		"rng": controller.scenario.rng.calls.duplicate(true),
		"report": report}


class RefusingSession extends ManualBattleSession:
	var attempts: Array = []

	func issue_command(command: Dictionary) -> Dictionary:
		attempts.append(command)
		if command.op != "end_phase":
			return {"accepted": false, "reason": "synthetic refusal"}
		return super.issue_command(command)


class NonAdvancingSession extends ManualBattleSession:
	var attempts := 0

	func issue_command(command: Dictionary) -> Dictionary:
		attempts += 1
		if command.op == "end_phase":
			return super.issue_command(command)
		return {"accepted": true}


func _session(blocked: bool = false) -> ManualBattleSession:
	var battle := Scenario.new({"profile": "native", "seed": 42,
		"battlefield": {"width": 5, "height": 2}, "sides": [
			{"id": 0, "name": "Azure", "is_attacker": true, "units": [
				{"id": "azure", "name": "Azure", "at": [0, 0], "life": 50, "stamina": 10}]},
			{"id": 1, "name": "Crimson", "units": [
				{"id": "crimson", "name": "Crimson", "at": [4, 0], "life": 50,
					"stamina": 10, "speed": 2}]}]})
	var session := ManualBattleSession.new(battle)
	session.begin()
	session.issue_command({"op": "end_phase"})
	if blocked:
		Statuses.apply(battle.units["crimson"], Status.from_dict({"id": "blocked",
			"restrictions": ["movement", "melee", "ranged"]}))
	return session


func _test_policy() -> void:
	var session := _session(true)
	var report := CrimsonPolicy.run_phase(session)
	_check(report.commands == [{"op": "end_phase"}], "blocked side passes exactly once")
	_check(CrimsonPolicy.run_phase(session).commands.is_empty(), "no Azure commands")
	session = _session()
	var before := session.scenario.final_state()
	var rng: Dictionary = session.scenario.rng.calls.duplicate(true)
	var chosen := CrimsonPolicy.choose_command(session)
	_check(chosen == {"op": "move", "unit": "crimson", "to": [2, 0]},
		"move chooses lowest distance then row and column")
	_check(before == session.scenario.final_state() and rng == session.scenario.rng.calls,
		"choice preserves state and RNG")
	var refusing := RefusingSession.new(session.scenario)
	refusing.started = true
	report = CrimsonPolicy.run_phase(refusing)
	_check(refusing.attempts == [chosen, {"op": "end_phase"}]
		and report.reason == "synthetic refusal", "refusal has no retry and one yield")
	session = _session()
	session.scenario.runtime_error = "synthetic runtime failure"
	_check(CrimsonPolicy.run_phase(session).commands.is_empty(), "runtime error stops without pass")
	session = _session()
	session.end()
	_check(CrimsonPolicy.run_phase(session).commands.is_empty(), "ended session stops without pass")
	session = _session()
	session.scenario.units["azure"].alive = false
	_check(CrimsonPolicy.run_phase(session).commands.is_empty(), "completed battle stops without pass")

	session = _session()
	var crimson: Combatant = session.scenario.units["crimson"]
	crimson.ranged_attack = 1
	crimson.shooting_range = 8
	crimson.ammo = 5
	var expected := {"op": "shoot", "unit": "crimson", "target": "azure"}
	_check(CrimsonPolicy.choose_command(session) == expected, "legal shot precedes movement")
	report = CrimsonPolicy.run_phase(session)
	_check(report.commands == [expected] and session.active_side_id() == 0,
		"automatic exhaustion returns control without an extra pass")

	session = _session()
	crimson = session.scenario.units["crimson"]
	crimson.ranged_attack = 1000
	crimson.shooting_range = 8
	crimson.ammo = 5
	report = CrimsonPolicy.run_phase(session)
	_check(report.commands == [expected] and session.battle_complete(),
		"fatal command ends battle without an extra pass")

	session = _session()
	var non_advancing := NonAdvancingSession.new(session.scenario)
	non_advancing.started = true
	report = CrimsonPolicy.run_phase(non_advancing)
	_check(non_advancing.attempts == 65 and report.commands.back().op == "end_phase"
		and non_advancing.active_side_id() == 0, "64-command cap yields with one authoritative pass")
