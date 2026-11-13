# Run with a rendering display; writes only into the explicitly supplied private root.
extends SceneTree

var output: String
var prefix: String
var viewport: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _settle() -> void:
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw


func _capture(id: String) -> void:
	await _settle()
	var path := output.path_join("%s-%s-%dx%d.png" % [prefix, id, viewport.size.x, viewport.size.y])
	var error := viewport.get_texture().get_image().save_png(path)
	print("CAPTURE %s error=%d" % [path, error])
	if error != OK:
		push_error("Could not save presentation capture: " + path)
		quit(1)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or DisplayServer.get_name() == "headless":
		push_error(
			"Usage: --script tools/capture_presentation.gd -- PRIVATE_OUTPUT PREFIX (display required)"
		)
		quit(1)
		return
	output = args[0]
	prefix = args[1]
	var safe_prefix := RegEx.new()
	safe_prefix.compile("^[A-Za-z0-9_-]+$")
	if safe_prefix.search(prefix) == null:
		push_error("Capture prefix must contain only letters, digits, hyphens or underscores")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for dimensions in [Vector2i(960, 540), Vector2i(1152, 648), Vector2i(1440, 810)]:
		viewport.size = dimensions
		var menu := load("res://game/demo/demo_main.tscn").instantiate() as Control
		viewport.add_child(menu)
		await _capture("menu")
		menu.queue_free()
		await process_frame
		var strategy := load("res://game/campaign/strategic_main.tscn").instantiate() as Control
		viewport.add_child(strategy)
		strategy.new_campaign()
		if strategy.has_method("show_home"):
			strategy.show_home()
		await _capture("home")
		if strategy.has_method("show_map"):
			strategy.show_map()
		strategy.travel("ford")
		await _settle()
		strategy.battle.select_unit(
			strategy.battle.encounter._mapping["azure-vanguard"].instance_id
		)
		await _capture("battle")
		strategy.battle.dispatch_melee(strategy.battle._unit_at(Vector2i(1, 0)).instance_id)
		strategy.return_from_battle(true)
		await _capture("map")
		strategy.queue_free()
		await process_frame
	viewport.queue_free()
	await process_frame
	quit()
