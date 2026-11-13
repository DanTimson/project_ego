extends SceneTree

var failures := 0
var viewport: SubViewport


func check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func settle() -> void:
	for index in 6:
		await process_frame


func key(code: Key, target: Viewport = null) -> void:
	if target == null:
		target = viewport
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		target.push_input(event, true)
	await settle()


func click(position: Vector2, target: Viewport = null) -> void:
	if target == null:
		target = viewport
	var motion := InputEventMouseMotion.new()
	motion.position = position
	target.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		target.push_input(event, true)
	await settle()


func contained(control: Control, parent: Control) -> bool:
	return parent.get_global_rect().grow(0.5).encloses(control.get_global_rect())


func run_size(dimensions: Vector2i) -> void:
	viewport.size = dimensions
	var menu := load("res://game/demo/demo_main.tscn").instantiate() as DemoMain
	viewport.add_child(menu)
	await settle()
	check(is_equal_approx(menu.menu_chrome.position.y / dimensions.y, 0.62), "menu panorama split")
	var play := menu.get_node("%PlayButton") as Button
	check(absf(play.size.x / dimensions.x - 0.27) < 0.002, "menu row width")
	var rect := play.get_global_rect()
	menu.get_node("Center/Panel/Margin/Buttons").get_child(0).grab_focus()
	await key(KEY_TAB)
	check(menu.get_node("%CampaignButton").has_focus(), "menu Tab follows row order")
	menu.show_options()
	await settle()
	check(menu.options_dialog.visible, "Options opens sound controls")
	menu.options_dialog.hide()
	menu.options_dialog.canceled.emit()
	await settle()
	check(
		menu.options_button.has_focus() and play.get_global_rect() == rect,
		"Options returns focus to a stationary row"
	)
	menu.queue_free()
	await settle()
	var strategy = load("res://game/campaign/strategic_main.tscn").instantiate()
	viewport.add_child(strategy)
	strategy.new_campaign()
	await settle()
	var checkpoint: Dictionary = strategy.campaign.checkpoint().data
	var strip: Rect2 = strategy.footer.get_global_rect()
	strategy.map_view.buttons.keep.grab_focus()
	await settle()
	check(
		strategy.inspected == "keep" and strategy.travel_button.disabled,
		"distant province keyboard inspection is distinct from travel"
	)
	check(
		(
			strategy.context_status.text.contains("Hostile")
			and strategy.context_status.text.contains("Army at Home")
		),
		"province owner and actual army location"
	)
	strategy.home_button.grab_focus()
	await key(KEY_ENTER)
	check(
		strategy.home_view.visible and strategy.home_button.button_pressed,
		"keyboard Home navigation has active state"
	)
	strategy.map_button.grab_focus()
	await key(KEY_ENTER)
	check(
		strategy.map_view.visible and strategy.map_button.button_pressed,
		"keyboard Map return has active state"
	)
	check(
		strategy.footer.get_global_rect() == strip and contained(strategy.footer, strategy),
		"resource strip persists through Map Home Map"
	)
	check(
		strategy.campaign.checkpoint().data == checkpoint,
		"inspection and navigation leave authoritative campaign unchanged"
	)
	strategy.queue_free()
	await settle()
	var battle := load("res://game/tactical/tactical_main.tscn").instantiate() as TacticalController
	viewport.add_child(battle)
	await settle()
	for control in [
		battle.pass_button, battle.cancel_button, battle.skip_button, battle.picker_button
	]:
		check(
			contained(control, battle.right_panel),
			"essential control contained without scrolling: " + control.text
		)
	check(battle.name_label.text == "Selected: —", "unselected state exposes absent values")
	battle.select_unit("azure-vanguard-01")
	battle.show_action_picker()
	await settle()
	check(
		Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(
			Rect2(Vector2(battle.picker.position), Vector2(battle.picker.size))
		),
		"action picker stays within the supported viewport"
	)
	check(
		(
			battle.picker_actions[2].disabled
			and battle.picker_description.text.contains("temporarily illegal")
		),
		"granted but distant action has an explicit legality reason"
	)
	check(
		(
			battle.picker_actions[3].disabled
			and battle.picker_description.text.contains("not implemented")
		),
		"spell slot is plainly unavailable"
	)
	battle.picker.hide()
	battle.picker.canceled.emit()
	check(battle.picker_button.has_focus(), "picker cancellation returns focus")
	battle.dispatch_move(Vector2i(3, 1))
	battle.pass_side()
	battle.select_unit("crimson-guard-42")
	battle.dispatch_move(Vector2i(4, 1))
	battle.pass_side()
	battle.select_unit("azure-vanguard-01")
	var before := battle.scenario._command_state()
	var calls: Dictionary = battle.scenario.rng.calls.duplicate(true)
	battle.show_action_picker()
	await settle()
	check(not battle.picker_actions[2].disabled, "real granted action is live for a legal target")
	battle.picker_actions[2].grab_focus()
	await key(KEY_ENTER, battle.picker)
	check(
		battle.input_mode == TacticalController.MODE_ACTION and not battle.picker.visible,
		"keyboard chooser arms existing targeting mode"
	)
	check(
		(
			battle.mode_label.text.contains("adjacent enemy")
			and contained(battle.cancel_button, battle.right_panel)
		),
		"targeting instructions and Cancel remain visible"
	)
	await key(KEY_ESCAPE)
	check(
		battle.selected_unit == null and battle.picker_button.has_focus(),
		"targeting Escape clears selection with return focus"
	)
	check(
		battle.scenario._command_state() == before and battle.scenario.rng.calls == calls,
		"picker and cancellation never execute a command or consume RNG"
	)
	battle.select_unit("azure-vanguard-01")
	battle.show_action_picker()
	await settle()
	battle._describe_picker(battle.picker_actions[2])
	check(battle.picker_description.text.count("Stamina Drain: granted action.") == 1,
		"focused action description appears once")
	if dimensions.x > 960:
		var wide := battle.picker.size.x
		viewport.size = Vector2i(960, 540)
		await settle()
		check(battle.picker.size.x < wide and battle.picker.visible
			and Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(
				Rect2(Vector2(battle.picker.position), Vector2(battle.picker.size))),
			"open action picker reflows on viewport shrink")
		viewport.size = dimensions
		await settle()
	await click(battle.picker_actions[3].get_global_rect().get_center(), battle.picker)
	check(
		battle.picker.visible and battle.scenario._command_state() == before,
		"unavailable spell ignores pointer activation"
	)
	await click(battle.picker_actions[2].get_global_rect().get_center(), battle.picker)
	check(
		not battle.picker.visible and battle.input_mode == TacticalController.MODE_ACTION,
		"pointer chooser arms the same targeting mode"
	)
	await click(battle.cancel_button.get_global_rect().get_center())
	check(
		battle.selected_unit == null and battle.scenario._command_state() == before,
		"pointer Cancel clears targeting without mutation"
	)
	battle.select_unit("azure-vanguard-01")
	battle.playback.speed = "Normal"
	battle.enter_action_mode()
	var result := battle.dispatch_action("crimson-guard-42")
	check(
		result.accepted and battle.playback.busy and not battle.skip_button.disabled,
		"accepted action enables persistent Skip"
	)
	check(
		(
			battle.battlefield_view._visual_stamina(battle.scenario.units["crimson-guard-42"])
			== int(battle.battlefield_view.visual_state.units["crimson-guard-42"].stamina)
		),
		"field stamina uses intermediate observation"
	)
	battle.playback.skip()
	battle.restart_battle()
	battle.picker_button.grab_focus()
	await key(KEY_SPACE)
	check(
		battle.session.active_side_id() == 1 and not battle.picker.visible,
		"Space passes even when a command button holds keyboard focus"
	)
	battle.queue_free()
	await settle()


func _run() -> void:
	# Headless's dummy 64px window otherwise downsamples fonts before measuring.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	viewport = SubViewport.new()
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	for dimensions in [Vector2i(960, 540), Vector2i(1152, 648), Vector2i(1440, 810)]:
		await run_size(dimensions)
	viewport.queue_free()
	await settle()
	print("REFERENCE LAYOUT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
