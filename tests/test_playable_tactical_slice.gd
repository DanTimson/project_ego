extends SceneTree

const MAIN_SCENE := "res://game/tactical/tactical_main.tscn"
const PLAYABLE_SCENARIO := "res://scenarios/playable_tactical_slice.json"

var failures: int = 0


func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		(" — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1


func _scenario_spec() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PLAYABLE_SCENARIO))


func _fresh_session() -> ManualBattleSession:
	var session := ManualBattleSession.new(Scenario.new(_scenario_spec()))
	session.begin()
	return session


func _victory_spec() -> Dictionary:
	return {
		"name": "manual victory", "profile": "native", "seed": 7,
		"battlefield": {"width": 3, "height": 2, "tiles": []},
		"sides": [
			{"id": 0, "name": "Alpha", "leader_initiative": 2,
				"is_attacker": true, "units": [{
					"id": "killer-01", "name": "Killer", "at": [0, 0],
					"attack": 50, "counter_attack": 0, "defence": 0,
					"ranged_defence": 0, "life": 20, "stamina": 10,
					"morale": 10, "speed": 2,
				}]},
			{"id": 1, "name": "Beta", "leader_initiative": 1,
				"units": [{
					"id": "target-99", "name": "Target", "at": [1, 0],
					"attack": 0, "counter_attack": 0, "defence": 0,
					"ranged_defence": 0, "life": 1, "stamina": 10,
					"morale": 10, "speed": 1,
				}]},
		],
		"commands": [],
	}


func _environment_spec(power: int, label: String) -> Dictionary:
	return {
		"name": label, "profile": "native", "seed": power,
		"battlefield": {"width": 4, "height": 3, "tiles": []},
		"sides": [
			{"id": 0, "name": "Allies", "leader_initiative": 2,
				"is_attacker": true, "units": [
					{"id": "%s-subject" % label, "name": "Subject", "at": [0, 0],
						"attack": 10, "counter_attack": 0, "life": 20,
						"stamina": 10, "morale": 10, "speed": 2},
					{"id": "%s-source" % label, "name": "Source", "at": [0, 1],
						"attack": 1, "counter_attack": 0, "life": 20,
						"stamina": 10, "morale": 10, "speed": 2,
						"auras": [{"id": "boost", "scope": "ADJACENT",
							"affects": "ALLY", "modifiers": [{
								"handler": "stat_delta", "hook": "STAT_PASSIVE",
								"power": power, "params": {"stat": "attack"},
							}]}]},
				]},
			{"id": 1, "name": "Enemy", "leader_initiative": 1,
				"units": [{"id": "%s-enemy" % label, "name": "Enemy", "at": [3, 2],
					"attack": 1, "counter_attack": 0, "life": 20,
					"stamina": 10, "morale": 10, "speed": 1}]},
		], "commands": [],
	}


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "  "))
	file.close()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("\n[playable tactical slice 2]")
	var scripted_spec := _scenario_spec()
	scripted_spec["commands"] = [{
		"op": "move", "unit": "azure-vanguard-01", "to": [2, 1],
	}]
	var manual := Scenario.new(scripted_spec)
	var manual_session := ManualBattleSession.new(manual)
	var manual_start := manual_session.unit_position(
		manual.units["azure-vanguard-01"])
	manual_session.begin()
	_check(manual_session.unit_position(
		manual.units["azure-vanguard-01"]) == manual_start,
		"manual construction does not execute scripted commands")
	_check(manual.log.size() == 2, "manual begin emits only battle/round headers")

	print("\n[structured command boundary and shared queries]")
	var movement_session := _fresh_session()
	var mover: Combatant = movement_session.scenario.units["azure-vanguard-01"]
	var highlighted := movement_session.reachable_cells(mover)
	_check(not highlighted.is_empty(), "movement query highlights reachable cells")
	var move_result := movement_session.issue_command({
		"op": "move", "unit": mover.instance_id,
		"to": [highlighted[0].x, highlighted[0].y],
	})
	_check(bool(move_result["accepted"]) and bool(move_result["state_changed"]),
		"highlighted reachable cell executes in unchanged state")
	_check(String(move_result["command"]) == "move"
		and not (move_result["events"] as Array).is_empty(),
		"accepted movement returns its newly emitted events")
	var before_bad_position := movement_session.unit_position(mover)
	var before_bad_move := mover.movement_remaining
	var before_bad_stamina := mover.stamina
	var bad_move := movement_session.issue_command({
		"op": "move", "unit": mover.instance_id, "to": [99, 99],
	})
	_check(not bool(bad_move["accepted"]) and not bool(bad_move["state_changed"])
		and String(bad_move["reason"]) != "",
		"non-highlighted movement is refused with a reason")
	_check(movement_session.unit_position(mover) == before_bad_position
		and mover.movement_remaining == before_bad_move
		and mover.stamina == before_bad_stamina,
		"impossible movement consumes no resources")

	var melee_session := _fresh_session()
	var melee_actor: Combatant = melee_session.scenario.units["azure-vanguard-01"]
	var melee_targets := melee_session.legal_melee_targets(melee_actor)
	_check(not melee_targets.is_empty(), "melee query highlights a target")
	var melee_target: Combatant = melee_targets[0]
	var melee_life := melee_target.life
	var melee_result := melee_session.issue_command({
		"op": "attack", "unit": melee_actor.instance_id,
		"target": melee_target.instance_id,
	})
	_check(bool(melee_result["accepted"]) and melee_target.life < melee_life
		and not (melee_result["events"] as Array).is_empty(),
		"highlighted melee target executes and returns events")
	_check(melee_actor.action_spent and not melee_session.can_select(melee_actor),
		"successful melee closes the actor's activation authoritatively")
	var melee_follow_up := melee_session.issue_command({
		"op": "move", "unit": melee_actor.instance_id, "to": [0, 0],
	})
	_check(not bool(melee_follow_up["accepted"])
			and not bool(melee_follow_up["state_changed"]),
		"manual session refuses an ordinary follow-up for the terminal actor")
	var melee_ally: Combatant = melee_session.scenario.units["azure-ranger-17"]
	_check(melee_session.active_side_id() == 0 and melee_session.can_select(melee_ally),
		"manual session keeps the side active and exposes another friendly unit")

	var ranged_session := _fresh_session()
	var ranger: Combatant = ranged_session.scenario.units["azure-ranger-17"]
	var ranged_targets := ranged_session.legal_ranged_targets(ranger)
	_check(not ranged_targets.is_empty(), "ranged query highlights a target")
	var ranged_target: Combatant = ranged_targets[0]
	var ranged_life := ranged_target.life
	var ranged_ammo := ranger.ammo
	var ranged_result := ranged_session.issue_command({
		"op": "shoot", "unit": ranger.instance_id,
		"target": ranged_target.instance_id,
	})
	_check(bool(ranged_result["accepted"]) and ranged_target.life < ranged_life
		and ranger.ammo == ranged_ammo - 1
		and not (ranged_result["events"] as Array).is_empty(),
		"highlighted ranged target executes, spends ammo, and returns events")
	_check(ranger.action_spent and not ranged_session.can_select(ranger),
		"successful ranged command closes the actor's activation")
	var ranged_follow_up := ranged_session.issue_command({
		"op": "shoot", "unit": ranger.instance_id,
		"target": ranged_target.instance_id,
	})
	_check(not bool(ranged_follow_up["accepted"])
			and ranger.ammo == ranged_ammo - 1,
		"manual session refuses a second shot without spending more ammo")

	var refusal_session := _fresh_session()
	var inactive: Combatant = refusal_session.scenario.units["crimson-guard-42"]
	var inactive_result := refusal_session.issue_command({
		"op": "move", "unit": inactive.instance_id, "to": [6, 1],
	})
	_check(not bool(inactive_result["accepted"])
		and String(inactive_result["reason"]).contains("active side"),
		"inactive-side actor is refused authoritatively")
	var spent: Combatant = refusal_session.scenario.units["azure-vanguard-01"]
	spent.action_spent = true
	var spent_result := refusal_session.issue_command({
		"op": "attack", "unit": spent.instance_id,
		"target": inactive.instance_id,
	})
	_check(not bool(spent_result["accepted"])
		and String(spent_result["reason"]).contains("already acted"),
		"spent actor is refused authoritatively")
	spent.action_spent = false
	spent.alive = false
	var dead_actor_result := refusal_session.issue_command({
		"op": "move", "unit": spent.instance_id, "to": [2, 1],
	})
	_check(not bool(dead_actor_result["accepted"])
		and String(dead_actor_result["reason"]).contains("down"),
		"dead actor is refused authoritatively")
	spent.alive = true
	inactive.alive = false
	var dead_target_result := refusal_session.issue_command({
		"op": "attack", "unit": spent.instance_id, "target": inactive.instance_id,
	})
	_check(not bool(dead_target_result["accepted"])
		and String(dead_target_result["reason"]).contains("down"),
		"dead target is refused authoritatively")

	var range_session := _fresh_session()
	var short_ranger: Combatant = range_session.scenario.units["azure-ranger-17"]
	var far_target: Combatant = range_session.scenario.units["crimson-guard-42"]
	short_ranger.shooting_range = 1
	var range_ammo := short_ranger.ammo
	var range_stamina := short_ranger.stamina
	var range_spent := short_ranger.action_spent
	var target_life := far_target.life
	var out_of_range := range_session.issue_command({
		"op": "shoot", "unit": short_ranger.instance_id,
		"target": far_target.instance_id,
	})
	_check(not bool(out_of_range["accepted"])
		and short_ranger.ammo == range_ammo
		and short_ranger.stamina == range_stamina
		and short_ranger.action_spent == range_spent
		and far_target.life == target_life,
		"out-of-range shooting consumes no resources or life")

	print("\n[manual session isolation]")
	var scenario_a := Scenario.new(_environment_spec(2, "a"))
	var scenario_b := Scenario.new(_environment_spec(7, "b"))
	var session_a := ManualBattleSession.new(scenario_a)
	var session_b := ManualBattleSession.new(scenario_b)
	session_a.begin()
	session_b.begin()
	var subject_a: Combatant = scenario_a.units["a-subject"]
	var subject_b: Combatant = scenario_b.units["b-subject"]
	var a_first := session_a.current_attack(subject_a)
	var b_first := session_b.current_attack(subject_b)
	var a_command := session_a.issue_command({"op": "rest", "unit": "a-subject"})
	var b_second := session_b.current_attack(subject_b)
	var b_command := session_b.issue_command({"op": "rest", "unit": "b-subject"})
	var a_second := session_a.current_attack(subject_a)
	_check(a_first == 12.0 and a_second == 12.0
		and b_first == 17.0 and b_second == 17.0,
		"alternating session queries retain only their own aura environment",
		"A %.1f/%.1f, B %.1f/%.1f" % [a_first, a_second, b_first, b_second])
	_check(bool(a_command["accepted"]) and bool(b_command["accepted"]),
		"alternating session commands execute under scoped bindings")

	print("\n[controller structured feedback]")
	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "tactical main scene resource loads")
	var controller := packed.instantiate() as TacticalController
	root.add_child(controller)
	await process_frame
	_check(controller != null and controller.scenario != null,
		"real tactical main scene tree instantiates and begins")
	_check(controller.select_unit("azure-vanguard-01"),
		"active-side selection succeeds")
	var controller_bad := controller.dispatch_move(Vector2i(99, 99))
	_check(not bool(controller_bad["accepted"])
		and controller.latest_feedback == String(controller_bad["reason"]),
		"TacticalController displays the structured refusal reason")
	var controller_source := FileAccess.get_file_as_string(
		"res://game/tactical/tactical_controller.gd")
	_check(controller_source.contains('result.get("accepted"')
		and not controller_source.contains('result.get("log"'),
		"TacticalController does not determine acceptance by searching log text")

	controller.restart_battle()
	_check(controller.select_unit("azure-vanguard-01"),
		"controller selects the melee actor for terminality integration")
	var controller_targets := controller.session.legal_melee_targets(
		controller.selected_unit)
	var controller_melee := controller.dispatch_melee(
		(controller_targets[0] as Combatant).instance_id)
	_check(bool(controller_melee["accepted"]) and controller.selected_unit == null,
		"controller drops a successfully terminal actor")
	var controller_follow_up := controller.dispatch_move(Vector2i(0, 0))
	_check(not bool(controller_follow_up["accepted"]),
		"controller cannot issue another ordinary command for that actor")
	_check(controller.select_unit("azure-ranger-17"),
		"controller can select another eligible unit on the same side")

	controller.restart_battle()
	var first_side := controller.session.active_side_id()
	var first_pass := controller.pass_side()
	var second_side := controller.session.active_side_id()
	var second_pass := controller.pass_side()
	_check(bool(first_pass["accepted"]) and bool(first_pass["state_changed"])
		and second_side != first_side and String(first_pass["command"]) == "pass",
		"structured pass hands control to the other side")
	_check(bool(second_pass["accepted"])
		and controller.scenario.state.round_number == 2
		and controller.session.active_side_id() == first_side,
		"both passes advance the round according to RoundLoop")

	var victory := Scenario.new(_victory_spec())
	var victory_session := ManualBattleSession.new(victory)
	victory_session.begin()
	var win_result := victory_session.issue_command({
		"op": "attack", "unit": "killer-01", "target": "target-99",
	})
	_check(bool(win_result["accepted"]) and victory_session.battle_complete()
		and victory_session.winning_side_id() == 0,
		"victory is detected from authoritative living rosters")
	var winner_life := (victory.units["killer-01"] as Combatant).life
	var post_result := victory_session.issue_command({"op": "end_phase"})
	_check(not bool(post_result["accepted"]) and not bool(post_result["state_changed"])
		and (victory.units["killer-01"] as Combatant).life == winner_life,
		"post-victory commands are rejected without state mutation")

	print("\n[portable synthetic asset resolver]")
	var asset_root := "user://tactical_asset_test"
	DirAccess.make_dir_recursive_absolute(asset_root)
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color("44aa66"))
	var image_path := asset_root.path_join("token.png")
	image.save_png(image_path)
	var raw_path := asset_root.path_join("data.bin")
	var raw_file := FileAccess.open(raw_path, FileAccess.WRITE)
	raw_file.store_buffer(PackedByteArray([1, 2, 3]))
	raw_file.close()
	var index_path := asset_root.path_join("index.json")
	var mapping_path := asset_root.path_join("mapping.json")
	_write_json(index_path, {"version": 1, "assets": [
		{"key": "Synthetic:Token01", "archive": "Synthetic",
			"source_id": "Token01", "type": "image", "path": "token.png"},
		{"key": "Synthetic:Raw01", "archive": "Synthetic",
			"source_id": "Raw01", "type": "raw", "path": "data.bin"},
	]})
	_write_json(mapping_path, {"version": 1,
		"content": [{"id": "demo:unit/5", "asset": "Synthetic:Token01"}],
		"instances": [{"id": "portable-unit", "asset": "Synthetic:Token01"}],
	})
	var resolver := TacticalAssetResolver.new()
	_check(resolver.load_index(index_path) and resolver.load_mapping(mapping_path),
		"synthetic index and mapping load")
	var synthetic_unit := Combatant.new()
	synthetic_unit.instance_id = "portable-unit"
	_check(resolver.texture_for_unit(synthetic_unit) != null,
		"mapped synthetic image loads as a Godot texture")
	synthetic_unit.content_id = "demo:unit/5"
	_check(resolver.logical_key_for_unit(synthetic_unit) == "Synthetic:Token01",
		"canonical content mapping has priority over instance mapping")
	_write_json(mapping_path, {"version": 1, "content": [], "instances": [
		{"id": "portable-unit", "asset": "Synthetic:Token01"},
		{"id": "portable-unit", "asset": "Synthetic:Raw01"},
	]})
	_check(not resolver.load_mapping(mapping_path),
		"duplicate/conflicting mapping identities are rejected")
	_write_json(mapping_path, {"version": 1, "content": [], "instances": [
		{"id": "portable-unit", "asset": "Synthetic:Raw01"},
	]})
	_check(not resolver.load_mapping(mapping_path),
		"raw data requested as an image is rejected")
	_write_json(mapping_path, {"version": 1, "content": {}, "instances": []})
	_check(not resolver.load_mapping(mapping_path),
		"malformed mapping sections are rejected")
	_write_json(mapping_path, {"version": 1, "content": [], "instances": [
		{"id": "portable-unit", "asset": "Synthetic:Missing"},
	]})
	_check(not resolver.load_mapping(mapping_path),
		"unknown mapping asset references are rejected")
	_write_json(mapping_path, {"version": 1, "content": [], "instances": [
		{"id": "portable-unit", "asset": "Synthetic:../token.png"},
	]})
	_check(not resolver.load_mapping(mapping_path),
		"mapping key path injection is rejected")
	_write_json(index_path, {"version": 1, "assets": [
		{"key": "Synthetic:Escape", "archive": "Synthetic",
			"source_id": "Escape", "type": "image", "path": "../token.png"},
	]})
	_check(not resolver.load_index(index_path),
		"resolver rejects index traversal outside its configured root")

	controller.queue_free()
	await process_frame
	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(0 if failures == 0 else 1)
