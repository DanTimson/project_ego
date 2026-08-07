extends SceneTree

const DEFAULT_SIZE := Vector2i(1152, 648)
const MINIMUM_SIZE := Vector2i(960, 540)
const LARGE_SIZE := Vector2i(1440, 810)
const DEMO_SCENE := "res://game/demo/demo_main.tscn"
const TACTICAL_SCENE := "res://game/tactical/tactical_main.tscn"

var failures := 0


func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		(" — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1


func _inside_x(child: Control, parent: Control) -> bool:
	var child_rect := child.get_global_rect()
	var parent_rect := parent.get_global_rect()
	return (child_rect.position.x >= parent_rect.position.x - 0.5
		and child_rect.end.x <= parent_rect.end.x + 0.5)


func _positive(control: Control) -> bool:
	return control.size.x > 0.0 and control.size.y > 0.0


func _new_viewport(logical_size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = logical_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(viewport)
	return viewport


func _settle() -> void:
	await process_frame
	await process_frame


func _test_demo_size(logical_size: Vector2i) -> void:
	var viewport := _new_viewport(logical_size)
	var menu := (load(DEMO_SCENE) as PackedScene).instantiate() as DemoMain
	viewport.add_child(menu)
	await _settle()
	var panel := menu.get_node("Center/Panel") as PanelContainer
	_check(menu.size == Vector2(logical_size),
		"demo follows logical size %s" % logical_size, str(menu.size))
	_check(menu.get_rect().encloses(panel.get_rect()),
		"demo panel stays inside %s" % logical_size,
		"menu=%s panel=%s" % [menu.get_rect(), panel.get_rect()])
	for button_name in ["PlayButton", "ControlsButton", "AboutButton", "QuitButton"]:
		var button := menu.get_node(
			"Center/Panel/Margin/Buttons/%s" % button_name) as Button
		_check(_positive(button) and button.size.x + 0.5 >= button.get_combined_minimum_size().x,
			"%s has label-safe size at %s" % [button_name, logical_size])
	var long_value := "metadata-" + "0123456789abcdef".repeat(24)
	menu.about_dialog.dialog_text = menu.about_text({
		"milestone": long_value,
		"commit": long_value,
		"godot_version": long_value,
		"mode": long_value,
		"built_at": long_value,
	})
	_check(menu.about_dialog.get_label().autowrap_mode
		== TextServer.AUTOWRAP_WORD_SMART,
		"long build metadata retains smart wrapping")
	viewport.queue_free()
	await process_frame


func _stress_tactical_text(controller: TacticalController) -> void:
	controller.select_unit("azure-vanguard-01")
	var unit := controller.selected_unit
	unit.name = "Selected Unit With A Deliberately Long Display Name That Must Wrap"
	unit.life = 999999999
	unit.life_base = 999999999
	unit.stamina = 999999999
	unit.stamina_base = 999999999
	unit.movement_remaining = 999999999
	unit.attack = 999999999
	unit.ranged_attack = 999999999
	unit.defence = 999999999
	unit.ranged_defence = 999999999
	unit.ammo = 999999999
	controller.scenario.state.side(controller.session.active_side_id()).name = (
		"The Extremely Long Coalition Name Used For Layout Stress")
	var long_event := (
		"A representative recent event contains a deliberately long description "
		+ "of movement, damage, effects, and phase changes without truncating data.")
	controller.scenario.log.append(long_event)
	controller.effects_label.text = (
		"EFFECTS / STATUS\nRepresentative unusually long effect name, "
		+ "another long status name, and a third timed effect")
	controller._controller_refusal(
		"Command refused because this representative authoritative explanation "
		+ "is deliberately long and must remain readable without leaving the panel.")


func _test_tactical_size(logical_size: Vector2i) -> void:
	var viewport := _new_viewport(logical_size)
	var controller := (load(TACTICAL_SCENE) as PackedScene).instantiate() 		as TacticalController
	viewport.add_child(controller)
	await _settle()
	_stress_tactical_text(controller)
	await _settle()
	_check(controller.selected_unit.name.length() > 40
		and controller.latest_feedback.length() > 80
		and String(controller.scenario.log.back()).length() > 80,
		"long model/status/event strings remain untruncated")
	var panel := controller.right_panel
	var region := controller.battlefield_region
	var vbox := controller.get_node(
		"RightPanel/Frame/Margin/PanelScroll/VBox") as VBoxContainer
	_check(controller.size == Vector2(logical_size),
		"tactical scene follows logical size %s" % logical_size,
		str(controller.size))
	_check(controller.get_rect().encloses(panel.get_rect()) and _positive(panel),
		"right panel stays wholly visible at %s" % logical_size)
	_check(region.get_global_rect().end.x <= panel.get_global_rect().position.x + 0.5,
		"panel does not overlap battlefield at %s" % logical_size)
	var drawn_extent := (
		TacticalController.BATTLEFIELD_LOGICAL_SIZE
		* controller.battlefield_view.scale)
	_check(controller.battlefield_view.position.x >= -0.5
		and controller.battlefield_view.position.y >= -0.5
		and controller.battlefield_view.position.x + drawn_extent.x <= region.size.x + 0.5
		and controller.battlefield_view.position.y + drawn_extent.y <= region.size.y + 0.5,
		"scaled battlefield stays inside its region at %s" % logical_size)
	for control in [controller.command_button, controller.ranged_button,
		controller.pass_button, controller.cancel_button]:
		_check(_positive(control) and _inside_x(control, vbox)
			and control.size.x + 0.5 >= control.get_combined_minimum_size().x,
			"%s remains label-safe in panel at %s" % [control.name, logical_size])
	for control in [controller.side_label, controller.name_label,
		controller.identity_label, controller.attack_label, controller.defence_label,
		controller.effects_label, controller.feedback_label, controller.events_label]:
		_check(_positive(control) and _inside_x(control, vbox),
			"%s has valid wrapped/scrollable geometry at %s" % [control.name, logical_size])
	_check(controller.feedback_label.scroll_active
		and controller.events_label.scroll_active
		and controller.effects_label.scroll_active,
		"long feedback, events, and effects are scrollable")
	var cell := Vector2i(3, 2)
	var local_centre := controller.battlefield_view.adapter.cell_to_pixel(cell)
	var displayed_centre := controller.battlefield_view.to_global(local_centre)
	var transformed_back := controller.battlefield_view.to_local(displayed_centre)
	_check(controller.battlefield_view.hit_test_local(transformed_back) == cell,
		"battlefield hit test survives presentation scaling at %s" % logical_size)
	viewport.queue_free()
	await process_frame


func _test_resize_settles() -> void:
	var viewport := _new_viewport(DEFAULT_SIZE)
	var controller := (load(TACTICAL_SCENE) as PackedScene).instantiate() \
		as TacticalController
	viewport.add_child(controller)
	await _settle()
	var default_scale := controller.battlefield_view.scale.x
	viewport.size = MINIMUM_SIZE
	await _settle()
	var minimum_scale := controller.battlefield_view.scale.x
	_check(controller.size == Vector2(MINIMUM_SIZE)
		and is_equal_approx(controller.right_panel.get_rect().end.x, controller.size.x),
		"resize settles at the minimum size")
	viewport.size = LARGE_SIZE
	await _settle()
	_check(controller.size == Vector2(LARGE_SIZE)
		and controller.battlefield_view.scale.x > minimum_scale
		and not is_equal_approx(default_scale, minimum_scale),
		"resize settles again at a larger size")
	viewport.queue_free()
	await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("\n[Milestone 0.1.1 UI logical-size hardening]")
	for logical_size in [DEFAULT_SIZE, MINIMUM_SIZE, LARGE_SIZE]:
		await _test_demo_size(logical_size)
		await _test_tactical_size(logical_size)
	await _test_resize_settles()
	print("\n%s" % ["ALL PASS" if failures == 0 else "%d FAILURES" % failures])
	quit(0 if failures == 0 else 1)
