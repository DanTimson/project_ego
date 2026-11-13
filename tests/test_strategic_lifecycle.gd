extends SceneTree

const Main = preload("res://game/campaign/strategic_main.gd")
const MENU := "res://game/demo/demo_main.tscn"
var failures := 0
var viewport := SubViewport.new()
var directory: String


func check(condition: bool, message: String) -> void:
	print("%s  %s" % ["PASS" if condition else "FAIL", message])
	if not condition:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func settle() -> void:
	await process_frame
	await process_frame


func launch() -> Main:
	change_scene_to_file(MENU)
	await settle()
	(current_scene.get_node("%StrategicButton") as Button).pressed.emit()
	await settle()
	var screen := current_scene as Main
	if screen == null:
		return null
	screen.reparent(viewport, false)
	screen.store = CampaignCheckpointStore.new(directory.path_join("checkpoint.json"))
	await settle()
	return screen


func click(battle: TacticalController, cell: Vector2i) -> void:
	var position := battle.battlefield_view.to_global(
		battle.battlefield_view.adapter.cell_to_pixel(cell)
	)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	await settle()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		viewport.push_input(event, true)
	await settle()


func battle_win(screen: Main, province: String, sacrifice := false) -> CampaignEncounter:
	(screen.map_view.buttons[province] as Button).pressed.emit()
	check(screen.inspected == province and screen.battle == null, "inspect before campaign travel")
	screen.travel_button.pressed.emit()
	await settle()
	var battle := screen.battle
	check(
		battle != null and battle.automated_crimson,
		"strategic map opens automated battle " + province
	)
	if battle == null:
		return null
	var encounter: CampaignEncounter = battle.encounter
	if sacrifice:
		await click(battle, Vector2i(1, 1))
		await click(battle, Vector2i(1, 0))
	await click(battle, Vector2i(0, 0))
	await click(battle, Vector2i(1, 0))
	check(battle.session.winning_side_id() == 0, "mouse commands win " + province)
	(battle.return_button as Button).pressed.emit()
	await settle()
	check(
		(
			screen.battle == null
			and screen.screen.visible
			and screen.campaign.snapshot().position == province
		),
		"return commits capture and exposes map " + province
	)
	return encounter


func _run() -> void:
	root.size = Vector2i(960, 540)
	viewport.size = root.size
	root.add_child(viewport)
	directory = "user://cx028-lifecycle-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(directory)
	var screen := await launch()
	if screen == null:
		check(false, "menu strategic entry initialized")
		quit(1)
		return
	screen.new_button.pressed.emit()
	await settle()
	check(not FileAccess.file_exists(screen.store.path), "new run does not implicitly save")
	check(
		(
			screen.get_rect().encloses(screen.screen.get_rect())
			and screen.map_view.size.x >= 580
			and screen.map_view.size.y >= 260
		),
		"map has usable minimum-window geometry"
	)
	for id in screen.map_view.buttons:
		var button: Button = screen.map_view.buttons[id]
		check(
			(
				screen.map_view.get_rect().size.x >= button.get_rect().end.x
				and button.size.x >= button.get_combined_minimum_size().x
			),
			"province button fits at minimum window: " + id
		)
	var first := await battle_win(screen, "ford", true)
	var life: int = screen.campaign.snapshot().roster.entries["azure-vanguard"].life
	check(
		(
			life > 0
			and life < 20
			and screen.roster_label.text.contains("CASUALTY")
			and screen.heading.text.contains("Gold 19")
			and screen.heading.text.contains("1 / 12")
		),
		"first capture visibly retains wounds, casualty and exact economy"
	)
	screen.save_button.pressed.emit()
	var saved: Dictionary = screen.campaign.checkpoint().data
	screen.new_button.pressed.emit()
	check(
		screen.campaign.snapshot().roster.entries["azure-vanguard"].life == 20,
		"New produces fresh full-life run"
	)
	screen.resume_button.pressed.emit()
	check(
		(
			screen.campaign.checkpoint().data == saved
			and screen.roster_label.text.contains("CASUALTY")
		),
		"New did not overwrite slot; Resume restores persistent map values"
	)
	# Leave the entry and reconstruct both UI and model, like a process restart.
	screen.reparent(root, false)
	screen.return_to_menu()
	await settle()
	screen = await launch()
	check(
		(
			screen.campaign == null
			and screen.resume_checkpoint().ok
			and screen.campaign.checkpoint().data == saved
		),
		"fresh entry resumes checkpoint without healing"
	)
	var original := screen.campaign.snapshot()
	var file := FileAccess.open(screen.store.path, FileAccess.WRITE)
	file.store_string("corrupt")
	file.close()
	check(
		(
			not screen.resume_checkpoint().ok
			and screen.campaign.snapshot() == original
			and screen.feedback.text.contains("Malformed")
		),
		"failed Resume preserves current run with readable reason"
	)
	screen.save_checkpoint()
	screen.travel("home")
	screen.recovery_button.pressed.emit()
	screen.recruit_button.pressed.emit()
	check(
		(
			screen.campaign.snapshot().turn == 4
			and screen.campaign.snapshot().gold == 22
			and screen.campaign.snapshot().roster.entries["azure-scout"].life == 0
		),
		"Home services spend turns and gold, retain casualty"
	)
	screen.save_checkpoint()
	screen.resume_checkpoint()
	screen.travel("ford")
	var opened := screen.travel("watchpost")
	await settle()
	var battle := screen.battle
	var deployed: CampaignEncounter = opened.encounter
	var carried: Combatant = battle.scenario.units[deployed._mapping["azure-vanguard"].instance_id]
	check(
		(
			carried.life == mini(20, life + 6)
			and not deployed._mapping.has("azure-scout")
			and deployed._mapping.has("recruit-1")
			and deployed._mapping.size() == 2
			and (
				carried
				!= first.session.scenario.units[first._mapping["azure-vanguard"].instance_id]
			)
		),
		"later battle has fresh object/IDs, healed life, recruit and no casualty"
	)
	battle.restart_button.pressed.emit()
	var retried: Combatant = battle.scenario.units[
		battle.encounter._mapping["azure-vanguard"].instance_id
	]
	check(
		(
			retried != carried
			and retried.instance_id != carried.instance_id
			and retried.life == carried.life
		),
		"retry preserves post-recovery wounds and refreshes identities"
	)
	battle.scenario.runtime_error = "synthetic halt"
	battle._refresh()
	check(
		(
			battle.feedback_label.text.contains("halted")
			and battle.return_button.text.contains("Abandon")
		),
		"halt has visible safe return"
	)
	var before_halt := screen.campaign.snapshot()
	battle.return_button.pressed.emit()
	await settle()
	check(
		screen.battle == null and screen.campaign.snapshot() == before_halt,
		"halt return applies no strategic values"
	)
	await battle_win(screen, "watchpost")
	await battle_win(screen, "keep")
	check(
		(
			screen.objective_label.text.contains("Victory")
			and screen.heading.text.contains("7 / 12")
			and screen.heading.text.contains("Gold 61")
		),
		"service route completion remains inspectable"
	)
	print(
		"PLAYTHROUGH FORD SERVICES: life=",
		screen.campaign.snapshot().roster.entries["azure-vanguard"].life
	)
	screen.new_campaign()
	await battle_win(screen, "quarry")
	await battle_win(screen, "mill")
	await battle_win(screen, "keep")
	check(
		(
			screen.campaign.snapshot().status == "victory"
			and screen.campaign.snapshot().turn == 3
			and screen.campaign.snapshot().gold == 51
		),
		"other route completes through real tactical mouse commands"
	)
	print(
		"PLAYTHROUGH QUARRY: life=",
		screen.campaign.snapshot().roster.entries["azure-vanguard"].life
	)
	screen.queue_free()
	viewport.queue_free()
	await settle()
	DirAccess.remove_absolute(directory.path_join("checkpoint.json"))
	DirAccess.remove_absolute(directory)
	print("STRATEGIC LIFECYCLE: %d failures" % failures)
	quit(0 if failures == 0 else 1)
