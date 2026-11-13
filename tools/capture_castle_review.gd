# Run on the host display. Writes captures only to the supplied private directory.
extends SceneTree

var output: String
var prefix: String
var viewport: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func settle() -> void:
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw


func capture(id: String) -> void:
	await settle()
	var path := output.path_join("%s-%s-960x540.png" % [prefix, id])
	var error := viewport.get_texture().get_image().save_png(path)
	print("CAPTURE %s error=%d" % [path, error])
	if error != OK:
		push_error("Capture failed: " + path)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or DisplayServer.get_name() == "headless":
		push_error("Usage: --script tools/capture_castle_review.gd -- PRIVATE_OUTPUT PREFIX")
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
	InteractionAudio.muted = true
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var screen := load("res://game/campaign/strategic_main.tscn").instantiate() as Control
	viewport.add_child(screen)
	screen.new_campaign()
	screen.show_home()
	await capture("home-opening")
	screen.show_construction()
	await capture("catalogue-opening")
	screen.construct("market")
	screen.show_map()
	screen.travel("ford")
	await settle()
	screen.battle.select_unit(screen.battle.encounter._mapping["azure-vanguard"].instance_id)
	screen.battle.dispatch_melee(screen.battle._unit_at(Vector2i(1, 0)).instance_id)
	screen.return_from_battle(true)
	screen.travel("home")
	screen.show_construction()
	await capture("catalogue-built-available-locked")
	screen.castle_rows.archery_range.inspect.grab_focus()
	await capture("catalogue-scrolled")
	screen.show_home()
	await capture("home-built")
	screen.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	quit()
