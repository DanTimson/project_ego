extends SceneTree

const LOGICAL_SIZE := Vector2i(1152, 648)
const TACTICAL_SCENE := "res://game/tactical/tactical_main.tscn"
const ACTIVE_UNIT_ID := "azure-vanguard-01"

var failures := 0


func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		(" — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1


func _settle() -> void:
	await process_frame
	await process_frame


func _push_mouse_motion(viewport: Viewport, position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)


func _push_mouse_button(viewport: Viewport, position: Vector2,
		button: MouseButton, pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.position = position
	click.global_position = position
	click.button_index = button
	click.pressed = pressed
	click.button_mask = (1 << (button - 1)) if pressed else 0
	viewport.push_input(click, true)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("\n[tactical battlefield mouse input routing]")
	var viewport := SubViewport.new()
	viewport.size = LOGICAL_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(viewport)
	var controller := (load(TACTICAL_SCENE) as PackedScene).instantiate() \
		as TacticalController
	viewport.add_child(controller)
	await _settle()

	_check(controller.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"TacticalMain ignores GUI mouse events")
	_check(controller.battlefield_region.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"BattlefieldRegion ignores GUI mouse events")

	var unit: Combatant = controller.scenario.units[ACTIVE_UNIT_ID]
	var unit_cell := controller.session.unit_position(unit)
	var local_centre := controller.battlefield_view.adapter.cell_to_pixel(unit_cell)
	var viewport_position := controller.battlefield_view.to_global(local_centre)
	_check(controller.session.can_select(unit),
		"mouse target is a selectable active-side unit", str(unit_cell))
	_check(controller.battlefield_region.get_global_rect().has_point(viewport_position),
		"active unit renders inside the battlefield input region",
		str(viewport_position))

	_push_mouse_motion(viewport, viewport_position)
	await _settle()
	_check(controller.battlefield_view.hovered == unit_cell,
		"viewport mouse motion reaches battlefield hover hit-testing",
		"expected=%s actual=%s" % [unit_cell, controller.battlefield_view.hovered])
	_push_mouse_button(viewport, viewport_position, MOUSE_BUTTON_LEFT, true)
	_push_mouse_button(viewport, viewport_position, MOUSE_BUTTON_LEFT, false)
	await _settle()
	_check(controller.selected_unit == unit,
		"viewport-routed left click selects the active-side unit")

	_push_mouse_button(viewport, viewport_position, MOUSE_BUTTON_RIGHT, true)
	_push_mouse_button(viewport, viewport_position, MOUSE_BUTTON_RIGHT, false)
	await _settle()
	_check(controller.selected_unit == null
		and controller.latest_feedback == "Selection cancelled.",
		"viewport-routed right click requests battlefield cancellation")

	viewport.queue_free()
	await process_frame
	print("\n%s" % ["ALL PASS" if failures == 0 else "%d FAILURES" % failures])
	quit(0 if failures == 0 else 1)
