# Rendered host review. Godot Movie Maker records the viewport and mixed game audio.
extends SceneTree

var output: String
var menu: DemoMain
var strategy: Control
var rehearsal := false

func _initialize() -> void:
	_run.call_deferred()

func pause(seconds := 0.7) -> void:
	if rehearsal:
		await process_frame
	else:
		await create_timer(seconds).timeout

func still(name: String) -> void:
	if rehearsal:
		return
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output.path_join(name + ".png"))
	if error != OK:
		push_error("Could not save capture: " + name)

func finish_playback(battle: TacticalController) -> void:
	while battle.playback.busy:
		await process_frame
	await pause()

func attack(member: String) -> void:
	var battle: TacticalController = strategy.battle
	battle.select_unit(battle.encounter._mapping[member].instance_id)
	await pause()
	battle.dispatch_melee(battle._unit_at(Vector2i(1, 0)).instance_id)
	await finish_playback(battle)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	rehearsal = args.has("--rehearse")
	if args.is_empty() or (DisplayServer.get_name() == "headless" and not rehearsal):
		push_error("Requires display: --script tools/capture_interaction.gd -- PRIVATE_OUTPUT")
		quit(1)
		return
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	menu = load("res://game/demo/demo_main.tscn").instantiate()
	root.add_child(menu)
	await pause()
	var landscape: PresentationLandscape
	for node in menu.get_children():
		if node is PresentationLandscape:
			landscape = node
	landscape.set_process(false)
	for direction in [1.0, -1.0, 0.0]:
		for frame in 90:
			landscape.advance_pan(1.0 / 30, root.size.x * (direction + 1) * 0.5)
			await pause(1.0 / 30)
	await still("menu")
	menu.queue_free()
	await process_frame
	strategy = load("res://game/campaign/strategic_main.tscn").instantiate()
	root.add_child(strategy)
	strategy.new_campaign()
	await pause()
	await still("map")
	strategy.travel("ford")
	await pause()
	await attack("azure-scout")
	await attack("azure-vanguard")
	await still("battle")
	strategy.return_from_battle(true)
	await pause(1.2)
	await still("capture")
	strategy.travel("home")
	await pause()
	strategy.show_home()
	strategy.recover()
	await pause(1.2)
	strategy.recruit()
	await pause(1.2)
	await still("home")
	strategy.queue_free()
	await process_frame
	# Standalone encounter: ordinary melee + policy-controlled Crimson response.
	var packed := load("res://game/tactical/tactical_vs_crimson.tscn") as PackedScene
	var battle := packed.instantiate() as TacticalController
	root.add_child(battle)
	battle.pass_side()
	await finish_playback(battle)
	battle.select_unit("azure-vanguard-01")
	var targets := battle.session.legal_melee_targets(battle.selected_unit)
	if not targets.is_empty():
		battle.dispatch_melee(targets[0].instance_id)
		await finish_playback(battle)
	battle.pass_side()
	await finish_playback(battle)
	await still("crimson")
	battle.queue_free()
	await process_frame
	menu = null
	strategy = null
	landscape = null
	battle = null
	await create_timer(0.3).timeout
	print("INTERACTION_CAPTURE_COMPLETE")
	quit.call_deferred()
