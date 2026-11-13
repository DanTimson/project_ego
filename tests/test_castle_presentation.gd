extends SceneTree

const Strategy = preload("res://game/campaign/strategic_main.gd")
var failures := 0
var viewport: SubViewport


func check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func settle() -> void:
	for frame in 5:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Availability/navigation tests do not need the asynchronous audio mixer.
	InteractionAudio.muted = true
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 540)
	root.add_child(viewport)
	var screen := load("res://game/campaign/strategic_main.tscn").instantiate() as Strategy
	viewport.add_child(screen)
	await settle()
	screen.new_campaign()
	screen.show_home()
	await settle()
	check(screen.construction_button.visible and not screen.construction_button.disabled,
		"Home exposes construction")
	# Real pointer activation, with keyboard focus retained through the successful build.
	screen.construction_button.grab_focus()
	await settle()
	var point := screen.construction_button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)
	await settle()
	check(screen.castle_view.visible and not screen.map_view.visible,
		"pointer opens dedicated construction view")
	check(screen.castle_rows.keys() == screen.Authored.definition().buildings.keys(),
		"construction cards follow the authored catalogue")
	check(screen.castle_rows.guard_tower.reason.text.contains("Barracks")
		and screen.castle_rows.workshop.reason.text.contains("Market"),
		"readable model prerequisites")
	var button: Button = screen.castle_rows.market.button
	button.grab_focus()
	var key := InputEventAction.new()
	key.action = "ui_accept"
	key.pressed = true
	viewport.push_input(key, true)
	key = InputEventAction.new()
	key.action = "ui_accept"
	key.pressed = false
	viewport.push_input(key, true)
	await settle()
	check(screen.campaign.has_building("market") and screen.campaign.snapshot().gold == 7,
		"keyboard build invokes guarded model")
	check(screen.castle_rows.market.inspect.has_focus()
		and screen.castle_rows.market.title.text.contains("Built"),
		"refresh preserves keyboard inspection focus after Build disables")
	check(screen.castle_rows.archery_range.reason.text == screen.campaign.query(
		"build", "archery_range").reason, "availability text is authoritative")
	screen.castle_rows.archery_range.inspect.grab_focus()
	await settle()
	check(screen.castle_scroll.scroll_vertical > 0, "last card focus scrolls into view")
	check(screen.castle_scroll.get_global_rect().encloses(
		screen.castle_rows.archery_range.inspect.get_global_rect()),
		"last facility remains accessible at 960x540")
	screen.show_home()
	await settle()
	check(screen.settlement.buildings.size() == 1, "built facility appears in settlement")
	screen.show_map()
	await settle()
	check(screen.context_status.text.contains("+5g")
		and screen.map_view._content.provinces.home.income == 5,
		"Home effective income agrees on map and province card")
	check(screen.map_view.visible and not screen.castle_view.visible, "return to map")
	var content: Dictionary = screen.Authored.definition()
	content.opening_gold = 100
	screen.campaign = StrategicCampaign.create(content)
	screen.show_home()
	screen.construct("archery_range")
	var range_slot: int = screen.settlement.buildings[0].settlement_slot
	screen.construct("market")
	check(screen.settlement.buildings[1].id == "archery_range"
		and screen.settlement.buildings[1].settlement_slot == range_slot,
		"new construction does not move an existing facility")
	screen.recruit_rows["campaign:unit/5"].button.pressed.emit()
	check(screen.campaign.snapshot().roster.entries["recruit-1"].def == "campaign:unit/5",
		"selected recruitment button dispatches its actual definition")
	screen.queue_free()
	viewport.queue_free()
	await settle()
	print("CASTLE PRESENTATION: %d failures" % failures)
	quit(0 if failures == 0 else 1)
