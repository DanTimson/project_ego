extends SceneTree

const NativeScreen = preload("res://game/campaign/strategic_main.gd")
const Main = preload("res://game/campaign/contested_main.gd")
const Policy = preload("res://core/campaign/strategic_policy.gd")
var failures := 0
var viewport: SubViewport


func check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func settle() -> void:
	for frame in 5:
		await process_frame


func pointer(button: Control) -> void:
	await click_at(button.get_global_rect().get_center())


func click_at(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)
	await settle()


func keyboard(button: Control) -> void:
	button.grab_focus()
	await settle()
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = "ui_accept"
		event.pressed = pressed
		viewport.push_input(event, true)
	await settle()


func defend(screen: Main) -> void:
	await keyboard(screen.defend_button)
	check(screen.battle != null and not screen.screen.visible, "keyboard opens retained defense")
	if screen.battle == null:
		return
	var battle := screen.battle
	check(battle.automated_crimson and battle.session.active_side_id() == 0,
		"Crimson attacker acts automatically before Azure input")
	check(not battle.restart_button.visible
		and battle.return_button.text.contains("Concede"), "defense has explicit concession, no retry")
	var vanguard := battle.session.living_units(0)[0]
	var cell := battle.session.unit_position(vanguard)
	var view := battle.battlefield_view
	var centre := view.adapter.cell_to_pixel(cell)
	var head := centre + Vector2(0, -52)
	check(view.hit_test_local(head).x < 0, "top-row sprite extends above its hex")
	await click_at(view.to_global(head))
	check(battle.selected_unit == vanguard, "clicking the Vanguard sprite selects him")
	var raider := battle.session.living_units(1)[0]
	var raider_centre := view.adapter.cell_to_pixel(battle.session.unit_position(raider))
	await click_at(view.to_global(raider_centre))
	check(not raider.alive, "pointer melee resolves against the Raider")
	for index in 64:
		if battle.session.battle_complete():
			break
		battle.playback.cancel()
		var command := Policy.tactical_command(battle.session)
		var result := battle._issue_command(command)
		check(result.accepted, "UI retained session accepts real tactical command")
		battle._apply_command_result(result)
		battle.playback.cancel()
		await settle()
	check(battle.session.winning_side_id() == 0, "interactive defensive victory")
	await keyboard(battle.return_button)
	check(screen.battle == null and screen.screen.visible, "Apply returns to map")


func check_dialog_navigation() -> void:
	root.gui_embed_subwindows = true
	change_scene_to_file("res://game/campaign/strategic_main.tscn")
	await settle()
	var native := current_scene as NativeScreen
	native.show_campaign_controls()
	await settle()
	var dialog := native.campaign_dialog
	for child in dialog.get_child(0).get_children():
		if child is Button and child.text.begins_with("Contested"):
			for pressed in [true, false]:
				var event := InputEventMouseButton.new()
				event.position = child.get_global_rect().get_center()
				event.button_index = MOUSE_BUTTON_LEFT
				event.pressed = pressed
				dialog.push_input(event, true)
			check(dialog.is_inside_tree(), "campaign dialog survives its click dispatch")
			break
	await settle()
	check(current_scene is Main, "contested scene loads after dialog input dispatch")


func _run() -> void:
	InteractionAudio.muted = true
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(960, 540)
	viewport = SubViewport.new()
	viewport.size = root.size
	root.add_child(viewport)
	# Strategic Campaign exposes the contested entry; native startup remains available.
	var native := load("res://game/campaign/strategic_main.tscn").instantiate() as NativeScreen
	viewport.add_child(native)
	await settle()
	var actions: Node = native.campaign_dialog.get_child(0)
	var has_entry := false
	for child in actions.get_children():
		if child is Button and child.text.contains("Contested"):
			has_entry = true
	check(has_entry, "contested entry under Strategic Campaign")
	native.queue_free()
	await settle()
	var screen := load("res://game/campaign/contested_main.tscn").instantiate() as Main
	viewport.add_child(screen)
	screen.store = CampaignCheckpointStore.new("user://cx033-ui-%d.json" % Time.get_ticks_usec())
	await settle()
	check(screen.size == Vector2(960, 540) and screen.screen.size.x <= 960
		and screen.map_view.size.x >= 580, "minimum-size contested layout")
	for id in screen.map_view.buttons:
		var button: Button = screen.map_view.buttons[id]
		check(screen.map_view.get_global_rect().encloses(button.get_global_rect()),
			"authored graph button in viewport " + id)
	var before := screen.model.snapshot()
	await pointer(screen.map_view.buttons.ford)
	check(screen.selected_province == "ford" and screen.model.snapshot() == before,
		"pointer inspection costs no action")
	# Service selector is reachable through focus-following scrolling.
	screen.service_picker.select(0)
	screen._refresh_service()
	await keyboard(screen.service_button)
	check(screen.model.snapshot().factions.azure.gold == 4, "keyboard buys Market")
	await keyboard(screen.travel_button)
	check(screen.model.snapshot().provinces.ford.owner == "azure", "keyboard travels selected army")
	await pointer(screen.end_button)
	check(screen.model.in_battle() and screen.save_button.disabled,
		"pointer End Turn suspends rival phase and disables save")
	await defend(screen)
	check(screen.model.snapshot().round == 2 and screen.model.snapshot().factions.azure.gold == 11,
		"UI defense resumes remaining rival actions and one payout")
	await pointer(screen.map_view.buttons.home)
	screen.service_picker.select(screen.definition.buildings.size())
	screen._refresh_service()
	await keyboard(screen.service_button)
	check(screen.model.members("", "home").size() == 2, "UI recruits into Home garrison")
	for child in screen.roster_rows.get_children():
		if child is CheckButton and child.get_meta("unit") == "recruited-1":
			await keyboard(child)
	await keyboard(screen.form_button)
	check(screen.model.army_count("azure") == 2
		and screen.model.members("", "home") == ["azure-guard"],
		"keyboard forms selected individual troop, leaves garrison")
	check(screen.army_picker.has_focus(), "formation refresh retains keyboard focus")
	check(screen.save_checkpoint().ok, "UI explicit contested save")
	before = screen.model.snapshot()
	check(screen.resume_checkpoint().ok and screen.model.snapshot() == before, "UI resume same map")
	# Individual station/withdraw preserves life and leaves the field army disbanded if empty.
	screen.issue({"op": "transfer", "unit": "recruited-1", "army": ""})
	check(screen.model.army_count("azure") == 1, "UI transfer disbands empty army")
	DirAccess.remove_absolute(screen.store.path)
	screen.graph_picker.select(1)
	screen.new_campaign()
	await settle()
	check(screen.map_view.buttons.has("salt") and not screen.map_view.buttons.has("ford"),
		"second authored graph renders with no province-ID layout dependency")
	screen.issue({"op": "travel", "army": "coast-company", "to": "orchard"})
	screen.issue({"op": "end_turn"})
	check(screen.model.in_battle(), "alternate defense prompt")
	await settle()
	await pointer(screen.concede_button)
	check(not screen.model.in_battle() and screen.model.snapshot().round == 2,
		"pointer concession completes rival turn")
	screen.queue_free()
	viewport.queue_free()
	await settle()
	await check_dialog_navigation()
	print("CONTESTED PRESENTATION: %d failures" % failures)
	quit(0 if failures == 0 else 1)
