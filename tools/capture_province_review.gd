extends SceneTree

const Main = preload("res://game/campaign/province_main.gd")
const Policy = preload("res://core/campaign/strategic_policy.gd")
var screen: Main
var output := "/tmp/cx034-review"
var failures := 0


func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
	_run.call_deferred()


func settle() -> void:
	for frame in 6:
		await process_frame


func capture(name_value: String) -> void:
	await settle()
	if DisplayServer.get_name() == "headless":
		print("CAPTURE skipped (headless): ", name_value)
		return
	await RenderingServer.frame_post_draw
	var path := output.path_join(name_value + ".png")
	var error := root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " error=", error)
	if error != OK:
		failures += 1


func issue(command: Dictionary) -> void:
	var result := screen.issue(command)
	if not result.ok:
		push_error("Capture command refused: " + JSON.stringify(command) + " " + result.reason)
		failures += 1
	await settle()


func decide(choice: String) -> void:
	await issue({"op": "decide", "choice": choice, "token": screen.model.encounter_choice().token})


func battles() -> void:
	for encounter_index in 8:
		if not screen.model.in_battle():
			return
		if screen.battle == null:
			screen.defend()
		await settle()
		var battle := screen.battle
		for command_index in 256:
			if battle.session.battle_complete():
				break
			battle.playback.cancel()
			var result := battle._issue_command(Policy.tactical_command(battle.session))
			if not result.accepted:
				failures += 1
				return
			battle._apply_command_result(result)
			battle.playback.cancel()
			await settle()
		if not screen.return_from_battle(true).ok:
			failures += 1
			return
		await settle()


func _run() -> void:
	InteractionAudio.muted = true
	root.size = Vector2i(960, 540)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(output)
	screen = load("res://game/campaign/province_main.tscn").instantiate() as Main
	root.add_child(screen)
	await capture("01-unknown-frontier")
	screen.inspect("ford")
	await issue({"op": "travel", "army": "azure-first", "to": "ford"})
	await issue({"op": "end_turn"})
	await battles()
	await issue({"op": "explore", "army": "azure-first"})
	await issue({"op": "end_turn"})
	await battles()
	await capture("02-discovery")
	await issue({"op": "site", "army": "azure-first"})
	await capture("03-encounter-choice")
	await decide("withdraw")
	await issue({"op": "site", "army": "azure-first"})
	await decide("fight")
	await capture("04-site-battle")
	await battles()
	await issue({"op": "build", "id": "farm", "province": "ford"})
	await issue({"op": "end_turn"})
	await battles()
	await issue({"op": "hire", "id": "warden", "province": "ford"})
	await issue({"op": "assign", "hero": "azure:warden", "army": "azure-first"})
	await issue({"op": "order", "army": "azure-first", "units": ["azure:warden", "azure-vanguard"]})
	await issue({"op": "end_turn"})
	await battles()
	await issue({"op": "buy", "id": "steel", "hero": "azure:warden", "province": "ford"})
	await issue({"op": "equip", "hero": "azure:warden", "item": "azure:warden:steel"})
	screen.pages.current_tab = 2
	await capture("05-hero-equipment-formation")
	screen.pages.current_tab = 1
	await capture("06-provincial-district")
	print("PROVINCE CAPTURE errors=", failures)
	screen.queue_free()
	await settle()
	quit(0 if failures == 0 else 1)
