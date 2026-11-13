extends SceneTree

const Strategy = preload("res://game/campaign/strategic_main.gd")
var failures := 0
var viewport: SubViewport
var directory: String


func check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func settle() -> void:
	for index in 4:
		await process_frame


func click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	viewport.push_input(motion, true)
	await settle()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		viewport.push_input(event, true)
	await settle()


func keys(battle: TacticalController) -> Array:
	var result: Array = []
	for unit in battle.scenario.units.values():
		result.append(
			[
				unit.content_id,
				battle.asset_resolver.logical_key_for_unit(unit),
				battle.asset_resolver.logical_key_for_unit(unit, "shadows"),
				battle.asset_resolver.logical_key_for_unit(unit, "portraits")
			]
		)
	return result


func run_size(dimensions: Vector2i, mode: String) -> void:
	viewport.size = dimensions
	var menu := load("res://game/demo/demo_main.tscn").instantiate() as DemoMain
	viewport.add_child(menu)
	await settle()
	for id in [
		"PlayButton",
		"CampaignButton",
		"StrategicButton",
		"ControlsButton",
		"AboutButton",
		"QuitButton"
	]:
		var button := menu.get_node("%" + id) as Button
		check(
			menu.get_global_rect().encloses(button.get_global_rect()),
			"%s menu %s contained %s" % [mode, id, dimensions]
		)
		button.grab_focus()
		check(
			button.has_focus() and button.get_theme_stylebox("focus") != null,
			"keyboard focus remains visible: " + id
		)
	menu.queue_free()
	await settle()
	var screen := load("res://game/campaign/strategic_main.tscn").instantiate() as Strategy
	viewport.add_child(screen)
	screen.new_campaign()
	await settle()
	var checkpoint: Dictionary = screen.campaign.checkpoint().data
	check(screen.map_view.size.x >= 580, "map retains landmark and route space")
	for id in screen.map_view.buttons:
		var button: Button = screen.map_view.buttons[id]
		check(
			Rect2(Vector2.ZERO, screen.map_view.size).encloses(button.get_rect()),
			"province hit target contained: " + id
		)
		for other in screen.map_view.buttons:
			if id < other:
				check(
					not button.get_rect().intersects(screen.map_view.buttons[other].get_rect()),
					"province hit targets separate: %s/%s" % [id, other]
				)
	check(
		(
			screen.map_view.buttons.home.disabled
			and not screen.map_view.buttons.ford.disabled
			and screen.map_view.buttons.keep.disabled
		),
		"current, adjacent and distant map states"
	)
	screen.show_home()
	await settle()
	check(
		(
			screen.home_view.visible
			and not screen.map_view.visible
			and screen.recovery_button.disabled
			and not screen.recruit_button.disabled
		),
		"Home has distinct visible services with authoritative states"
	)
	check(
		screen.recovery_button.text.contains("8g") and screen.recruit_button.text.contains("10g"),
		"Home shows current service costs"
	)
	for row in screen.roster_rows.get_children():
		if row is Button:
			check(
				row.icon != null and row.text.contains("life"),
				"inspectable roster portrait and life"
			)
			row.pressed.emit()
	check(
		screen.campaign.checkpoint().data == checkpoint,
		"view and roster inspection preserve checkpoint"
	)
	screen.show_map()
	await settle()
	var ford: Button = screen.map_view.buttons.ford
	await click(ford.get_global_rect().get_center())
	check(screen.battle != null, "map landmark hit opens the adjacent battle")
	if screen.battle != null:
		var battle: TacticalController = screen.battle
		var before := keys(battle)
		var old_ids: Array = battle.scenario.units.keys()
		var selected: Combatant = battle._unit_at(Vector2i(0, 0))
		await click(
			battle.battlefield_view.to_global(
				battle.battlefield_view.adapter.cell_to_pixel(Vector2i(0, 0))
			)
		)
		check(
			(
				battle.selected_unit == selected
				and not battle.battlefield_view.melee_targets.is_empty()
			),
			"scaled tactical click selects and shows legal targets"
		)
		if mode == "local":
			for unit in battle.scenario.units.values():
				check(
					(
						battle.asset_resolver.texture_for_unit(unit) != null
						and battle.asset_resolver.texture_for_shadow(unit) != null
						and battle.asset_resolver.texture_for_portrait(unit) != null
					),
					"local campaign art covers both sides"
				)
		elif mode == "partial":
			check(
				(
					battle.asset_resolver.texture_for_unit(selected) != null
					and battle.asset_resolver.texture_for_shadow(selected) == null
				),
				"partial mapping mixes mapped figure and authored fallback"
			)
		battle.restart_battle()
		check(
			keys(battle) == before and battle.scenario.units.keys() != old_ids,
			"fresh retry instance IDs retain the exact unit/shadow/portrait selection"
		)
		screen.return_from_battle(false)
		await settle()
		check(
			screen.campaign.snapshot().turn == 0 and screen.campaign.snapshot().gold == 12,
			"presentation retry/abandon preserves committed economy"
		)
	screen.queue_free()
	await settle()


func _run() -> void:
	directory = "user://cx029-presentation-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color("c2a574"))
	image.save_png(directory.path_join("unit.png"))
	var file := FileAccess.open(directory.path_join("index.json"), FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"version": 1,
				"assets":
				[
					{
						"key": "Synthetic:Figure",
						"archive": "Synthetic",
						"source_id": "Figure",
						"type": "image",
						"path": "unit.png"
					}
				]
			}
		)
	)
	file.close()
	file = FileAccess.open(directory.path_join("mapping.json"), FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"version": 2,
				"units":
				{
					"content": [{"id": "campaign:unit/1", "asset": "Synthetic:Figure"}],
					"instances": []
				},
				"shadows": {"content": [], "instances": []},
				"portraits": {"content": [], "instances": []},
				"ui": [],
				"terrain": [],
				"decorations": []
			}
		)
	)
	file.close()
	var original_index := OS.get_environment("EGO_ASSET_INDEX")
	var original_mapping := OS.get_environment("EGO_ASSET_MAPPING")
	viewport = SubViewport.new()
	root.add_child(viewport)
	var modes := ["fallback", "partial"]
	if FileAccess.file_exists(original_index) and FileAccess.file_exists(original_mapping):
		modes.append("local")
	for mode in modes:
		OS.set_environment(
			"EGO_ASSET_INDEX",
			(
				original_index
				if mode == "local"
				else directory.path_join("index.json" if mode == "partial" else "absent.json")
			)
		)
		OS.set_environment(
			"EGO_ASSET_MAPPING",
			original_mapping if mode == "local" else directory.path_join("mapping.json")
		)
		for dimensions in [Vector2i(960, 540), Vector2i(1152, 648), Vector2i(1440, 810)]:
			await run_size(dimensions, mode)
	OS.set_environment("EGO_ASSET_INDEX", original_index)
	OS.set_environment("EGO_ASSET_MAPPING", original_mapping)
	viewport.queue_free()
	await settle()
	for name in ["unit.png", "mapping.json", "index.json"]:
		DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	print("CAMPAIGN PRESENTATION: %d failures" % failures)
	quit(0 if failures == 0 else 1)
