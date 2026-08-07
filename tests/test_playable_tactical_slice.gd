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


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("\n[playable tactical slice]")
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

	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "tactical main scene resource loads")
	var controller := packed.instantiate() as TacticalController
	root.add_child(controller)
	await process_frame
	_check(controller != null and controller.scenario != null,
		"real tactical main scene tree instantiates and begins")

	_check(controller.select_unit("azure-vanguard-01"),
		"active-side selection succeeds")
	_check(not controller.select_unit("crimson-guard-42"),
		"inactive-side selection is rejected")

	controller.restart_battle()
	controller.select_unit("azure-vanguard-01")
	var mover: Combatant = controller.selected_unit
	var before_move := controller.session.unit_position(mover)
	var move_result := controller.dispatch_move(Vector2i(2, 1))
	_check(bool(move_result["ok"]) and controller.session.unit_position(mover) != before_move,
		"legal movement dispatches through Scenario/core")
	var after_move := controller.session.unit_position(mover)
	var movement_left := mover.movement_remaining
	var bad_move := controller.dispatch_move(Vector2i(99, 99))
	_check(not bool(bad_move["ok"])
		and controller.session.unit_position(mover) == after_move
		and mover.movement_remaining == movement_left,
		"illegal movement leaves authoritative state unchanged")

	controller.restart_battle()
	controller.select_unit("azure-vanguard-01")
	var melee_target: Combatant = controller.scenario.units["crimson-guard-42"]
	var melee_life := melee_target.life
	var melee_result := controller.dispatch_melee(melee_target.instance_id)
	_check(bool(melee_result["ok"]) and melee_target.life < melee_life,
		"melee dispatches through Scenario/core with automatic approach")

	controller.restart_battle()
	controller.select_unit("azure-ranger-17")
	var ranger: Combatant = controller.selected_unit
	var ranged_target: Combatant = controller.scenario.units["crimson-guard-42"]
	var ranged_life := ranged_target.life
	var ranged_ammo := ranger.ammo
	var ranged_result := controller.dispatch_ranged(ranged_target.instance_id)
	_check(bool(ranged_result["ok"]) and ranged_target.life < ranged_life
		and ranger.ammo == ranged_ammo - 1,
		"ranged attack dispatches and spends core ammunition")

	controller.restart_battle()
	var first_side := controller.session.active_side_id()
	var first_pass := controller.pass_side()
	var second_side := controller.session.active_side_id()
	var second_pass := controller.pass_side()
	_check(bool(first_pass["ok"]) and second_side != first_side,
		"passing hands control to the other side")
	_check(bool(second_pass["ok"]) and controller.scenario.state.round_number == 2
		and controller.session.active_side_id() == first_side,
		"both passes advance the round according to RoundLoop")

	var victory := Scenario.new(_victory_spec())
	var victory_session := ManualBattleSession.new(victory)
	victory_session.begin()
	var win_result := victory_session.issue_command({
		"op": "attack", "unit": "killer-01", "target": "target-99",
	})
	_check(bool(win_result["ok"]) and victory_session.battle_complete()
		and victory_session.winning_side_id() == 0,
		"victory is detected from authoritative living rosters")
	var winner_life := (victory.units["killer-01"] as Combatant).life
	var post_result := victory_session.issue_command({"op": "end_phase"})
	_check(not bool(post_result["ok"])
		and (victory.units["killer-01"] as Combatant).life == winner_life,
		"post-victory commands are rejected without state mutation")

	var old_scenario := controller.scenario
	controller.restart_battle()
	_check(controller.scenario != old_scenario
		and controller.scenario.state.round_number == 1
		and (controller.scenario.units["azure-vanguard-01"] as Combatant).life == 16,
		"restart constructs fresh Scenario state")

	var resolver := TacticalAssetResolver.new()
	_check(resolver.texture_for_key("missing") == null,
		"absent optional asset uses placeholder fallback")
	var manifest_path := "user://playable_slice_manifest.json"
	var manifest := {
		"version": 1, "root": ".", "assets": [
			{"id": "unit/token", "type": "image", "path": "images/z.bmp"},
			{"id": "unit/token", "type": "image", "path": "images/a.bmp"},
			{"id": "other", "type": "raw", "path": "raw/x.bin"},
		],
	}
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	var loaded_manifest := resolver.load_manifest(manifest_path)
	_check(loaded_manifest and resolver.asset_path("unit/token").ends_with("images/a.bmp")
		and resolver.asset_path("unit/token") == resolver.asset_path("unit/token"),
		"synthetic local asset-manifest lookup is deterministic")

	controller.queue_free()
	await process_frame
	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(0 if failures == 0 else 1)
