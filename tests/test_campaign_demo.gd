extends SceneTree

const MENU := "res://game/demo/demo_main.tscn"
const Campaign = preload("res://game/demo/campaign_demo.gd")

var failures := 0
var viewport := SubViewport.new()


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _settle() -> void:
	await process_frame
	await process_frame


func _launch() -> Campaign:
	var menu := current_scene as DemoMain
	if menu == null:
		return null
	(menu.get_node("%CampaignButton") as Button).pressed.emit()
	await _settle()
	var campaign := current_scene as Campaign
	if campaign != null:
		# A SubViewport tracks injected mouse motion in headless runs.
		campaign.reparent(viewport, false)
		await _settle()
	return campaign


func _click(battle: Campaign, cell: Vector2i) -> void:
	var view := battle.battlefield_view
	var position := view.to_global(view.adapter.cell_to_pixel(cell))
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	await _settle()
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = position
		click.global_position = position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		viewport.push_input(click, true)
	await _settle()


func _run() -> void:
	root.size = Vector2i(960, 540)
	viewport.size = root.size
	root.add_child(viewport)
	if change_scene_to_file(MENU) != OK:
		quit(2)
		return
	await _settle()
	var battle := await _launch()
	if battle == null or battle.session == null:
		push_error("Campaign Demo did not launch Ford.")
		quit(2)
		return
	var ford: Combatant = battle.scenario.units["ford:azure-vanguard"]
	_check(ford.life == 20 and battle.automated_crimson
		and battle.get_node("%CampaignHeading").text.contains("Ford"), "campaign starts at Ford")
	_check(not battle.get_node("%ContinueButton").visible and not battle.continue_campaign(),
		"unfinished Ford cannot write back")
	await _click(battle, Vector2i(0, 0))
	await _click(battle, Vector2i(1, 0))
	if not _advance(battle):
		quit(1)
		return
	var watchpost: Combatant = battle.scenario.units["watchpost:azure-vanguard"]
	_check(ford.life == 14 and watchpost.life == 14 and watchpost != ford
		and watchpost.instance_id != ford.instance_id, "Vanguard enters Watchpost at 14/20")
	_check(battle.scenario.units.has("watchpost:azure-scout"), "surviving Scout redeploys")
	await _click(battle, Vector2i(0, 0))
	await _click(battle, Vector2i(1, 0))
	await _click(battle, Vector2i(2, 0))
	_check(battle.session.winning_side_id() == 0
		and battle.get_node("%CampaignHeading").text.contains("Campaign complete"),
		"Watchpost victory is visible as campaign completion")
	_check(battle.restart_button.visible, "completed Watchpost offers a retry")
	battle.restart_button.pressed.emit()
	var retried: Combatant = battle.scenario.units["watchpost:azure-vanguard"]
	_check(retried != watchpost and retried.life == 14 and battle._roster.snapshot().revision == 1,
		"retry uses the same post-Ford roster")

	battle.reparent(root, false)
	(battle.get_node("%MenuButton") as Button).pressed.emit()
	await _settle()
	battle = await _launch()
	if battle == null or battle.session == null:
		quit(2)
		return
	_check(battle.scenario.units["ford:azure-vanguard"].life == 20
		and battle.scenario.units["ford:azure-scout"].life == 4
		and battle._roster.snapshot().revision == 0, "menu relaunch creates a fresh roster")
	await _click(battle, Vector2i(1, 1))
	await _click(battle, Vector2i(1, 0))
	_check(battle.scenario.units["ford:azure-scout"].life == 0
		and not battle.get_node("%ContinueButton").visible, "Scout can fall during a real Ford attack")
	await _click(battle, Vector2i(0, 0))
	await _click(battle, Vector2i(1, 0))
	if not _advance(battle):
		quit(1)
		return
	_check(not battle.scenario.units.has("watchpost:azure-scout")
		and battle._roster.snapshot().entries["azure-scout"].life == 0,
		"casualty stays absent from Watchpost")
	battle.reparent(root, false)
	(battle.get_node("%MenuButton") as Button).pressed.emit()
	await _settle()
	battle = await _launch()
	if battle == null or battle.session == null:
		quit(2)
		return
	for turn in range(12):
		if battle.session.battle_complete():
			break
		battle.pass_side()
	_check(battle.session.winning_side_id() == 1
		and not battle.get_node("%ContinueButton").visible
		and not battle.continue_campaign() and battle._roster.snapshot().revision == 0,
		"Ford defeat cannot advance or write back")
	_check(battle.restart_battle() and battle.scenario.units["ford:azure-vanguard"].life == 20,
		"retrying a defeat restores the Ford opening roster")
	quit(0 if failures == 0 else 1)


func _advance(battle: Campaign) -> bool:
	var next := battle.get_node("%ContinueButton") as Button
	if battle.session.winning_side_id() != 0 or not next.visible:
		_check(false, "Ford victory offers Continue to Watchpost")
		return false
	var menu := battle.get_node("%MenuButton") as Button
	battle.scenario.runtime_error = "synthetic halt"
	battle._refresh()
	_check(not next.visible and not battle.continue_campaign()
		and battle._roster.snapshot().revision == 0, "a halted victory cannot advance or write back")
	battle.scenario.runtime_error = ""
	battle._refresh()
	var panel_rect := battle.right_panel.get_global_rect()
	_check(panel_rect.encloses(next.get_global_rect()) and panel_rect.encloses(menu.get_global_rect()),
		"campaign navigation fits the minimum window")
	next.pressed.emit()
	var opened := battle.scenario.units.has("watchpost:azure-vanguard")
	_check(opened and not battle.continue_campaign() and battle._roster.snapshot().revision == 1,
		"Continue opens Watchpost and applies Ford once")
	return opened
