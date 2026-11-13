# Explicit private output only. Compatible with the CX-031 frozen base.
extends SceneTree

var output: String
var phase: String
var rehearsal := false
var viewport: SubViewport
var measurements: Array = []


func _initialize() -> void:
	_run.call_deferred()


func settle() -> void:
	for index in 8:
		await process_frame


func rect(control: Control) -> Array:
	var bounds := control.get_global_rect()
	return [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]


func capture(id: String, scene: Control) -> void:
	await settle()
	var record := {"screen": id, "size": [viewport.size.x, viewport.size.y]}
	if id == "menu":
		record["panorama_fraction"] = scene.get_node("Center").anchor_top
		record["button"] = rect(scene.get_node("%PlayButton"))
	elif id in ["map", "home"] and scene.get("footer") != null:
		record["footer"] = rect(scene.footer)
		record["context"] = rect(scene.context_panel)
		record["field"] = rect(scene.map_view if id == "map" else scene.home_view)
	elif id == "battle":
		record["rail"] = rect(scene.right_panel)
		record["field"] = rect(scene.battlefield_region)
		record["pass"] = rect(scene.pass_button)
		record["cancel"] = rect(scene.cancel_button)
	elif id == "action-picker":
		record["picker"] = [
			scene.picker.position.x,
			scene.picker.position.y,
			scene.picker.size.x,
			scene.picker.size.y
		]
		record["description"] = rect(scene.picker_description)
	measurements.append(record)
	if rehearsal:
		print("GEOMETRY ", JSON.stringify(record))
		return
	await RenderingServer.frame_post_draw
	var path := output.path_join("%s-%s-%dx%d.png" % [phase, id, viewport.size.x, viewport.size.y])
	var error := viewport.get_texture().get_image().save_png(path)
	print("CAPTURE %s error=%d" % [path, error])
	if error != OK:
		quit(1)


func run_size(dimensions: Vector2i) -> void:
	viewport.size = dimensions
	var menu = load("res://game/demo/demo_main.tscn").instantiate()
	viewport.add_child(menu)
	await capture("menu", menu)
	menu.queue_free()
	await settle()
	var strategy = load("res://game/campaign/strategic_main.tscn").instantiate()
	viewport.add_child(strategy)
	strategy.new_campaign()
	await settle()
	if strategy.has_method("inspect_province"):
		strategy.map_view.inspect("ford")
	await capture("map", strategy)
	strategy.show_home()
	await capture("home", strategy)
	strategy.show_map()
	strategy.travel("ford")
	await settle()
	strategy.battle.playback.speed = "Instant"
	strategy.battle.select_unit(strategy.battle.encounter._mapping["azure-vanguard"].instance_id)
	await capture("battle", strategy.battle)
	strategy.queue_free()
	await settle()
	if phase == "after":
		var battle = load("res://game/tactical/tactical_main.tscn").instantiate()
		viewport.add_child(battle)
		await settle()
		battle.playback.speed = "Instant"
		battle.select_unit("azure-vanguard-01")
		battle.dispatch_move(Vector2i(3, 1))
		battle.pass_side()
		battle.select_unit("crimson-guard-42")
		battle.dispatch_move(Vector2i(4, 1))
		battle.pass_side()
		battle.select_unit("azure-vanguard-01")
		battle.show_action_picker()
		battle.picker_actions[2].grab_focus()
		await capture("action-picker", battle)
		battle._choose_action(2)
		await capture("targeting", battle)
		battle.cancel_selection()
		battle.queue_free()
		await settle()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args[1] not in ["before", "after"]:
		push_error("Usage: -- PRIVATE_OUTPUT before|after [--rehearse] [--minimum]")
		quit(1)
		return
	output = args[0]
	phase = args[1]
	rehearsal = args.has("--rehearse")
	if DisplayServer.get_name() == "headless" and not rehearsal:
		push_error("Rendered captures require a WSLg display; use --rehearse for geometry only.")
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new()
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sizes := (
		[Vector2i(960, 540)]
		if args.has("--minimum")
		else [Vector2i(960, 540), Vector2i(1152, 648), Vector2i(1440, 810)]
	)
	for dimensions in sizes:
		await run_size(dimensions)
	var file := FileAccess.open(output.path_join(phase + "-geometry.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(measurements, "  ") + "\n")
	viewport.queue_free()
	await settle()
	print("REFERENCE_REVIEW_COMPLETE")
	quit()
