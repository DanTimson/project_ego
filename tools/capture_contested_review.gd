# Host-only rendering review. No checkpoint is read or written.
extends SceneTree

const Main = preload("res://game/campaign/contested_main.gd")
const Policy = preload("res://core/campaign/strategic_policy.gd")
var output: String
var viewport: SubViewport
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func settle() -> void:
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw


func capture(id: String) -> void:
	await settle()
	var path := output.path_join(id + "-960x540.png")
	var error := viewport.get_texture().get_image().save_png(path)
	failed = failed or error != OK
	print("CAPTURE %s error=%d" % [path, error])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DisplayServer.get_name() == "headless":
		push_error("Usage: --script tools/capture_contested_review.gd -- PRIVATE_OUTPUT")
		quit(1)
		return
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	InteractionAudio.muted = true
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var screen := load("res://game/campaign/contested_main.tscn").instantiate() as Main
	viewport.add_child(screen)
	await capture("opening")
	screen.issue({"op": "build", "id": "market"})
	screen.issue({"op": "travel", "army": "azure-first", "to": "ford"})
	screen.issue({"op": "end_turn"})
	await capture("defense-prompt")
	screen.defend()
	await capture("interactive-defense")
	var battle := screen.battle
	for index in 64:
		if battle.session.battle_complete():
			break
		var command := Policy.tactical_command(battle.session)
		var result := battle._issue_command(command)
		if not result.accepted:
			failed = true
			break
		battle._apply_command_result(result)
		battle.playback.cancel()
	if battle.session.battle_complete():
		screen.return_from_battle(true)
	else:
		failed = true
	if not failed:
		screen.issue({"op": "recruit", "id": screen.definition.recruit_def})
		screen.inspect("home")
		screen._formation_selection = ["recruited-1"]
		screen.form_army()
		screen.army_picker.grab_focus()
		await capture("second-army-and-garrison")
		screen.graph_picker.select(1)
		screen.new_campaign()
		await capture("coast-graph")
	screen.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	quit(1 if failed else 0)
