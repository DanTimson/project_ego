extends SceneTree

const Main = preload("res://game/campaign/province_main.gd")
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


func keyboard(button: Control) -> void:
	button.grab_focus()
	await settle()
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = "ui_accept"
		event.pressed = pressed
		viewport.push_input(event, true)
	await settle()


func pointer(button: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)
	await settle()


func find_button(parent: Node, starts: String) -> Button:
	if parent is Button and parent.text.begins_with(starts):
		return parent
	for child in parent.get_children():
		var found := find_button(child, starts)
		if found != null:
			return found
	return null


func _run() -> void:
	InteractionAudio.muted = true
	root.size = Vector2i(960, 540)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	viewport = SubViewport.new()
	viewport.size = root.size
	root.add_child(viewport)
	var screen := load("res://game/campaign/province_main.tscn").instantiate() as Main
	viewport.add_child(screen)
	await settle()
	screen.store = CampaignCheckpointStore.new("user://cx034-ui-test.json")
	check(
		(
			screen.size == Vector2(960, 540)
			and screen.screen.size.x <= 960
			and screen.map_view.size.x >= 550
		),
		"province mode fits minimum size"
	)
	for id in screen.map_view.buttons:
		check(
			screen.map_view.get_global_rect().encloses(
				screen.map_view.buttons[id].get_global_rect()
			),
			"map marker inside minimum viewport " + id
		)
	check(
		screen.map_view.buttons.watchpost.text == "Unexplored space",
		"hidden marker redacts terrain"
	)
	await pointer(screen.map_view.buttons.watchpost)
	check(
		(
			screen.details.text.begins_with("Unexplored space")
			and not screen.details.text.contains("Woodland")
		),
		"pointer unknown inspection stays redacted"
	)
	await pointer(screen.map_view.buttons.quarry)
	await keyboard(screen.travel_button)
	check(
		(
			screen.choice_panel.visible
			and not screen.model.in_battle()
			and screen.choice_text.text.contains("Opposition unknown")
		),
		"keyboard opens pre-battle choice"
	)
	check(
		screen.negotiate_button.disabled and not screen.fight_button.disabled,
		"exact unaffordable tribute disables negotiation only"
	)
	await keyboard(screen.withdraw_button)
	check(
		(
			not screen.choice_panel.visible
			and screen.model.snapshot().armies["azure-first"].moves == 1
		),
		"keyboard withdraw preserves origin movement"
	)
	await pointer(screen.end_button)
	await keyboard(screen.travel_button)
	await keyboard(screen.negotiate_button)
	check(
		screen.model.snapshot().provinces.quarry.owner == "azure" and screen.battle == null,
		"keyboard negotiation captures without combat"
	)
	await pointer(screen.end_button)
	await keyboard(screen.explore_button)
	check(
		screen.details.text.contains("50%") and screen.details.text.contains("Crystal seam"),
		"keyboard explore renders real discoveries"
	)
	await pointer(screen.end_button)
	await keyboard(screen.site_button)
	check(screen.choice_text.text.contains("Old ruin"), "discovered site encounter panel")
	await keyboard(screen.fight_button)
	check(
		screen.battle != null and screen.save_button.disabled,
		"Fight opens existing tactical UI, blocks save"
	)
	if screen.battle != null:
		var battle := screen.battle
		for index in 64:
			if battle.session.battle_complete():
				break
			battle.playback.cancel()
			var result := battle._issue_command(Policy.tactical_command(battle.session))
			check(result.accepted, "UI ordinary tactical command")
			battle._apply_command_result(result)
			battle.playback.cancel()
			await settle()
		await keyboard(battle.return_button)
		check(screen.battle == null, "UI Apply returns to province mode")
	# Districts and roster remain reachable by keyboard tab focus and scrolling.
	screen.pages.current_tab = 1
	await settle()
	check(screen.districts.get_child_count() > 2, "noncapital district catalogue with unlocks")
	screen.pages.current_tab = 2
	await settle()
	check(screen.heroes_panel.get_child_count() > 3, "hero catalogue and formation panes")
	var hire := find_button(screen.heroes_panel, "Hire Warden")
	check(hire != null and not hire.disabled, "hero hire quote is actionable")
	if hire != null:
		await keyboard(hire)
	var assign := find_button(screen.heroes_panel, "Assign selected army")
	if assign != null:
		await keyboard(assign)
	var first := find_button(screen.heroes_panel, "Move to first slot")
	if first != null:
		await keyboard(first)
	check(
		screen.model.members("azure-first")[0] == "azure:warden",
		"keyboard assigns and orders leader"
	)
	screen.pages.current_tab = 0
	await pointer(screen.end_button)
	if screen.model.in_battle():
		# This route's guard is intentionally resolved by the existing UI controller.
		screen.defend()
		await settle()
		var battle := screen.battle
		for index in 64:
			if battle.session.battle_complete():
				break
			battle.playback.cancel()
			var result := battle._issue_command(Policy.tactical_command(battle.session))
			check(result.accepted, "hero-led defense tactical command")
			battle._apply_command_result(result)
			battle.playback.cancel()
			await settle()
		await keyboard(battle.return_button)
	screen.pages.current_tab = 2
	await settle()
	var buy := find_button(screen.heroes_panel, "Buy Steel blade")
	if buy != null:
		await keyboard(buy)
	var equip := find_button(screen.heroes_panel, "Equip Steel blade")
	if equip != null:
		await keyboard(equip)
	check(
		screen.model.snapshot().inventory.get("azure:warden:steel", {}).get("equipped", false),
		"keyboard purchases and equips owned item"
	)
	await settle()
	check(
		screen.screen.size.x <= 960 and screen.pages.size.x >= 550,
		"populated hero/equipment panes retain minimum-size layout"
	)
	check(screen.save_checkpoint().ok, "UI explicit province save")
	var before := screen.model.snapshot()
	check(screen.resume_checkpoint().ok and screen.model.snapshot() == before, "UI province resume")
	DirAccess.remove_absolute(screen.store.path)
	screen.graph_picker.select(1)
	screen.new_campaign()
	await settle()
	check(
		screen.map_view.buttons.has("salt") and not screen.map_view.buttons.has("ford"),
		"alternate graph UI does not depend on province IDs"
	)
	screen.queue_free()
	viewport.queue_free()
	await settle()
	print("PROVINCE PRESENTATION: %d failures" % failures)
	quit(0 if failures == 0 else 1)
