class_name TacticalController
extends Control

const BATTLEFIELD_LOGICAL_SIZE := Vector2(840.0, 720.0)
const MODE_COMMAND := "Move / melee"
const MODE_RANGED := "Ranged"
const MODE_ACTION := "Stamina Drain"
const DemoContent = preload("res://game/tactical/tactical_demo_content.gd")

@export var automated_crimson := false

@export_file("*.json") var scenario_path := "res://scenarios/playable_tactical_slice.json"

var last_crimson_report: Dictionary = {}

var scenario: Scenario
var session: ManualBattleSession
var selected_unit: Combatant
var input_mode := MODE_COMMAND
var asset_resolver := TacticalAssetResolver.new()
var playback: BattlePlayback
var sound: InteractionAudio
var dossier: UnitDossier
var latest_feedback := "Select a highlighted active-side unit."
var _presentation_before: Dictionary = {}

@onready var battlefield_region: Control = %BattlefieldRegion
@onready var battlefield_view: TacticalBattlefieldView = %BattlefieldView
@onready var right_panel: Control = %RightPanel
@onready var round_label: Label = %RoundLabel
@onready var side_label: Label = %SideLabel
@onready var name_label: Label = %NameLabel
@onready var identity_label: Label = %IdentityLabel
@onready var life_label: Label = %LifeLabel
@onready var stamina_label: Label = %StaminaLabel
@onready var movement_label: Label = %MovementLabel
@onready var ammo_label: Label = %AmmoLabel
@onready var mode_label: Label = %ModeLabel
@onready var feedback_label: RichTextLabel = %FeedbackLabel
@onready var victory_label: Label = %VictoryLabel
@onready var events_label: RichTextLabel = %EventsLabel
@onready var attack_label: Label = %AttackLabel
@onready var defence_label: Label = %DefenceLabel
@onready var effects_label: RichTextLabel = %EffectsLabel
@onready var portrait_rect: TextureRect = %SelectedPortrait
@onready var portrait_fallback_label: Label = %PortraitFallbackLabel
@onready var panel_texture: TextureRect = %PanelTexture
@onready var command_button: Button = %CommandButton
@onready var ranged_button: Button = %RangedButton
@onready var action_button: Button = %ActionButton
@onready var pass_button: Button = %PassButton
@onready var restart_button: Button = %RestartButton
@onready var cancel_button: Button = %CancelButton


func _ready() -> void:
	theme = PresentationTheme.create()
	_prepare_dossier()
	playback = BattlePlayback.new()
	add_child(playback)
	if DisplayServer.get_name() == "headless":
		playback.speed = "Instant"
	var controls := get_node("RightPanel/Frame/Margin/PanelScroll/VBox")
	sound = InteractionAudio.controls(controls)
	var speeds := OptionButton.new()
	for speed in ["Normal", "Fast", "Instant"]:
		speeds.add_item(speed)
	speeds.selected = 2 if playback.speed == "Instant" else 0
	speeds.item_selected.connect(func(index: int) -> void:
		playback.speed = speeds.get_item_text(index)
		if playback.speed == "Instant":
			playback.skip())
	controls.add_child(speeds)
	var reduce := CheckButton.new()
	reduce.text = "Reduced motion"
	reduce.toggled.connect(func(value: bool) -> void: playback.reduced_motion = value)
	controls.add_child(reduce)
	var skip := Button.new()
	skip.text = "Skip playback"
	skip.pressed.connect(playback.skip)
	controls.add_child(skip)
	playback.beat.connect(_present_beat)
	playback.finished.connect(_finish_playback)
	effects_label.focus_mode = Control.FOCUS_ALL
	effects_label.mouse_filter = Control.MOUSE_FILTER_STOP
	effects_label.focus_entered.connect(func() -> void:
		feedback_label.text = effects_label.tooltip_text)

	resized.connect(_queue_layout_presentation)
	battlefield_view.cell_clicked.connect(_on_cell_clicked)
	battlefield_view.cancel_requested.connect(cancel_selection)
	command_button.pressed.connect(enter_command_mode)
	ranged_button.pressed.connect(enter_ranged_mode)
	action_button.pressed.connect(enter_action_mode)
	pass_button.pressed.connect(pass_side)
	for signal_name in ["mouse_entered", "mouse_exited", "button_down", "button_up",
		"focus_entered", "focus_exited"]:
		pass_button.connect(signal_name, _update_pass_art.call_deferred)
	restart_button.pressed.connect(restart_battle)
	cancel_button.pressed.connect(cancel_selection)
	restart_battle()
	_layout_presentation.call_deferred()


func _queue_layout_presentation() -> void:
	_layout_presentation.call_deferred()


func _layout_presentation() -> void:
	if not is_node_ready():
		return
	var available := battlefield_region.size
	var presentation_scale := minf(
		available.x / BATTLEFIELD_LOGICAL_SIZE.x,
		available.y / BATTLEFIELD_LOGICAL_SIZE.y)
	presentation_scale = maxf(presentation_scale, 0.01)
	battlefield_view.scale = Vector2.ONE * presentation_scale
	battlefield_view.position = Vector2(
		maxf(0.0, (available.x - BATTLEFIELD_LOGICAL_SIZE.x * presentation_scale) * 0.5),
		maxf(0.0, (available.y - BATTLEFIELD_LOGICAL_SIZE.y * presentation_scale) * 0.5))


func _load_scenario_spec() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(scenario_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Playable tactical scenario is malformed: %s" % scenario_path)
		return {}
	return parsed


func restart_battle() -> bool:
	var scenario_spec := _load_scenario_spec()
	if scenario_spec.is_empty():
		latest_feedback = "Could not load the playable scenario."
		_refresh()
		return false
	var provider: ScenarioContentProvider
	if scenario_path == "res://scenarios/playable_tactical_slice.json":
		provider = DemoContent.provider_for(scenario_spec)
	var next_scenario := Scenario.new(scenario_spec, null, provider)
	if next_scenario.construction_error == "" \
			and scenario_path == "res://scenarios/playable_tactical_slice.json":
		var setup_refusal := DemoContent.setup_opening_restriction(next_scenario)
		if setup_refusal != "":
			latest_feedback = setup_refusal
			feedback_label.text = setup_refusal
			return false
	return _start_session(ManualBattleSession.new(next_scenario))


func _start_session(next_session: ManualBattleSession) -> bool:
	playback.cancel()
	battlefield_view.visual_state = {}
	battlefield_view.current_beat = null
	battlefield_view.motion_target = ""
	if session != null:
		session.end()
	# Reload local presentation assets when replacing the battle.
	asset_resolver.configure()
	_apply_visual_assets()
	session = next_session
	scenario = session.scenario
	_bind_presentation_roles()
	var begun := session.begin()
	selected_unit = null
	last_crimson_report = {}
	input_mode = MODE_COMMAND
	if not bool(begun["ok"]):
		latest_feedback = String(begun.get("message", "Could not begin the battle."))
		_refresh()
		return false
	latest_feedback = "Battle ready. Select an Azure Company unit."
	battlefield_view.configure(session, asset_resolver)
	_refresh()
	return true


func select_unit(instance_id: String) -> bool:
	if playback.busy or scenario == null or session.battle_complete():
		_set_feedback("Selection refused: the battle is over.")
		return false
	var unit: Combatant = scenario.units.get(instance_id)
	if unit == null:
		_set_feedback("Selection refused: unknown unit '%s'." % instance_id)
		return false
	if not _human_phase() or not session.can_select(unit):
		_set_feedback("Selection refused: %s is inactive, down, or spent." % unit.label())
		return false
	sound.cue("select")
	selected_unit = unit
	input_mode = MODE_COMMAND
	_set_feedback("Selected %s." % unit.label())
	return true


func dispatch_move(cell: Vector2i) -> Dictionary:
	if not _human_phase() or selected_unit == null:
		return _controller_refusal("Select a unit before moving.")
	var result := _issue_command({
		"op": "move", "unit": selected_unit.instance_id,
		"to": [cell.x, cell.y],
	})
	_apply_command_result(result)
	return result


func dispatch_melee(target_id: String) -> Dictionary:
	if not _human_phase() or selected_unit == null:
		return _controller_refusal("Select a unit before attacking.")
	var result := _issue_command({
		"op": "attack", "unit": selected_unit.instance_id, "target": target_id,
	})
	_apply_command_result(result)
	return result


func dispatch_ranged(target_id: String) -> Dictionary:
	if not _human_phase() or selected_unit == null:
		return _controller_refusal("Select a unit before shooting.")
	var result := _issue_command({
		"op": "shoot", "unit": selected_unit.instance_id, "target": target_id,
	})
	input_mode = MODE_COMMAND
	_apply_command_result(result)
	return result


func dispatch_action(target_id: String) -> Dictionary:
	if not _human_phase() or selected_unit == null:
		return _controller_refusal("Select a unit before using an action.")
	var target: Combatant = scenario.units.get(target_id)
	var stamina_before := target.stamina if target != null else 0
	var result := _issue_command(_action_command(target_id))
	var action_feedback := ""
	if bool(result.get("accepted", false)):
		input_mode = MODE_COMMAND
		if target != null:
			action_feedback = "Stamina Drain: %s stamina %d → %d" % [
				target.name, stamina_before, target.stamina]
	_apply_command_result(result, action_feedback)
	return result


func _action_command(target_id: String) -> Dictionary:
	return {"op": "action", "unit": selected_unit.instance_id,
		"action": String(DemoContent.ACTION_ID), "target": target_id}


func _has_drain_grant() -> bool:
	return selected_unit != null and scenario.unit_catalogues.get(
		selected_unit.instance_id, {}).has(DemoContent.ACTION_ID)


func enter_action_mode() -> void:
	if not _has_drain_grant():
		_set_feedback("Stamina Drain is not granted to this unit.")
		return
	input_mode = MODE_ACTION
	_set_feedback("Stamina Drain: click a highlighted adjacent enemy. Cancel [Esc].")


func pass_side() -> Dictionary:
	if scenario == null or not _human_phase():
		return _controller_refusal("Wait for Azure control.")
	var result := _issue_command({"op": "end_phase"})
	selected_unit = null
	input_mode = MODE_COMMAND
	_apply_command_result(result)
	return result


func enter_command_mode() -> void:
	input_mode = MODE_COMMAND
	_set_feedback("Command mode: select, move, or click an orange melee target.")


func enter_ranged_mode() -> void:
	if selected_unit == null:
		_set_feedback("Ranged mode refused: select a unit first.")
		return
	var restriction := Statuses.restriction_reason(selected_unit, Status.Capability.RANGED)
	if restriction != "":
		_set_feedback("Ranged mode refused: %s. %s" % [restriction,
			scenario.opening_restriction_description(selected_unit)])
		return
	if session.legal_ranged_targets(selected_unit).is_empty():
		_set_feedback("Ranged mode refused: no legal target, range, or ammunition.")
		return
	input_mode = MODE_RANGED
	_set_feedback("Ranged mode: click a magenta enemy target.")


func cancel_selection() -> void:
	if playback.busy:
		return
	selected_unit = null
	input_mode = MODE_COMMAND
	_set_feedback("Selection cancelled.")


func _controller_refusal(message: String) -> Dictionary:
	_set_feedback(message)
	return {
		"accepted": false, "command": "controller", "reason": message,
		"events": [], "state_changed": false,
		"ok": false, "message": message, "log": [],
		"battle_over": session.battle_complete() if scenario != null else false,
		"winner": -1,
	}


func _human_phase() -> bool:
	return not playback.busy and (not automated_crimson or session.active_side_id() == 0)


func _run_crimson_if_needed() -> String:
	if not automated_crimson or session.active_side_id() != CrimsonPolicy.CRIMSON:
		return ""
	selected_unit = null
	input_mode = MODE_COMMAND
	last_crimson_report = CrimsonPolicy.run_phase(session)
	var moves := 0
	var attacks := 0
	for index in last_crimson_report.commands.size():
		if not bool(last_crimson_report.results[index]["accepted"]):
			continue
		var command: Dictionary = last_crimson_report.commands[index]
		if command.op == "move":
			moves += 1
		elif command.op in ["shoot", "attack"]:
			attacks += 1
	var summary := "Crimson: %d moves, %d attacks. %s" % [moves, attacks,
		"Azure control." if _human_phase() and not session.battle_complete() else "Phase ended."]
	if last_crimson_report.reason != "":
		summary += " " + String(last_crimson_report.reason)
	return summary


func _apply_command_result(result: Dictionary, action_feedback: String = "") -> void:
	# Acceptance is a typed core field. Never infer it from event/log text.
	if bool(result.get("accepted", false)):
		var events: Array = result.get("events", [])
		latest_feedback = " | ".join(events) if not events.is_empty() \
			else "%s accepted." % String(result.get("command", "Command")).capitalize()
	else:
		latest_feedback = String(result.get("reason", "Command refused."))
	if selected_unit != null and not session.can_select(selected_unit):
		selected_unit = null
	if session.battle_complete():
		selected_unit = null
	var beats: Array[BattleObservation] = []
	beats.assign(result.get("observations", []))
	last_crimson_report = {}
	var crimson_feedback := _run_crimson_if_needed()
	for response in last_crimson_report.get("results", []):
		beats.append_array(response.get("observations", []))
	if not crimson_feedback.is_empty():
		latest_feedback = crimson_feedback if action_feedback.is_empty() else (
			action_feedback + "\n" + crimson_feedback)
	elif not action_feedback.is_empty():
		latest_feedback = action_feedback
	if result.get("accepted", false):
		battlefield_view.visual_state = _presentation_before.duplicate(true)
		playback.start(beats)
	else:
		sound.cue("refuse")
	_refresh()


func _issue_command(command: Dictionary) -> Dictionary:
	_presentation_before = scenario._command_state()
	return session.issue_command(command)


func _present_beat(observation: BattleObservation) -> void:
	battlefield_view.motion_from = battlefield_view.visual_state
	battlefield_view.motion_target = (observation.target
		if observation.kind == BattleObservation.Kind.MOVE else "")
	battlefield_view.motion_elapsed = 0
	battlefield_view.motion_duration = float(playback.timings[BattleObservation.Kind.MOVE]) / (
		3 if playback.speed == "Fast" else 1)
	battlefield_view.visual_state = observation.state
	battlefield_view.current_beat = observation
	battlefield_view.reduced_motion = playback.reduced_motion
	battlefield_view.queue_redraw()
	var cue: String = {BattleObservation.Kind.MOVE: "movement",
		BattleObservation.Kind.IMPACT: "impact"}.get(observation.kind, "")
	if cue != "" and not playback.skipping:
		sound.cue(cue)
	feedback_label.text = "%s • %s → %s%s" % [
		BattleObservation.Kind.keys()[observation.kind].capitalize(),
		observation.source, observation.target,
		" (%d)" % observation.amount if observation.kind == BattleObservation.Kind.IMPACT else ""]
	round_label.text = "R%d" % observation.state.round
	side_label.text = "Active: %s" % session.side_name(observation.state.active_side)


func _finish_playback() -> void:
	battlefield_view.visual_state = {}
	battlefield_view.current_beat = null
	battlefield_view.motion_target = ""
	_refresh()


func _exit_tree() -> void:
	if playback != null:
		playback.cancel()


func _set_feedback(message: String) -> void:
	latest_feedback = message
	_refresh()


func _unit_at(cell: Vector2i) -> Combatant:
	for unit in session.living_units():
		if session.unit_position(unit) == cell:
			return unit
	return null


func _on_cell_clicked(cell: Vector2i) -> void:
	if playback.busy:
		return
	if session.battle_complete():
		_set_feedback("Battle complete.")
		return
	var occupant := _unit_at(cell)
	if occupant != null:
		if selected_unit != null and input_mode == MODE_ACTION:
			dispatch_action(occupant.instance_id)
		elif scenario.side_of(occupant).id == session.active_side_id():
			select_unit(occupant.instance_id)
		elif selected_unit == null:
			_set_feedback("Selection refused: that unit belongs to the inactive side.")
		elif input_mode == MODE_RANGED:
			dispatch_ranged(occupant.instance_id)
		else:
			dispatch_melee(occupant.instance_id)
		return
	if input_mode == MODE_ACTION:
		_set_feedback("Stamina Drain requires a highlighted adjacent enemy.")
	elif input_mode == MODE_RANGED:
		_set_feedback("Ranged mode requires a magenta enemy target.")
	elif selected_unit != null:
		dispatch_move(cell)
	else:
		_set_feedback("Select a living active-side unit first.")


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			cancel_selection()
		KEY_R:
			enter_ranged_mode()
		KEY_SPACE:
			pass_side()


func _apply_visual_assets() -> void:
	if not is_node_ready():
		return
	# The original 140x768 panel is never stretched beneath the sidebar.
	# Use native portrait/value cells and separately cropped group frames.
	var panel := asset_resolver.texture_for_named("ui", "panel")
	panel_texture.texture = panel
	panel_texture.hide()
	for region_name in ["StatsRegion", "ActionRegion", "EffectsRegion"]:
		(get_node("%" + region_name) as Control).remove_theme_stylebox_override("panel")
	command_button.icon = asset_resolver.texture_for_named("ui", "command")
	ranged_button.icon = asset_resolver.texture_for_named("ui", "ranged")
	cancel_button.icon = asset_resolver.texture_for_named("ui", "cancel")
	for item in [[life_label, "life"], [stamina_label, "stamina"],
		[attack_label, "attack"], [defence_label, "defence"], [ammo_label, "ammo"]]:
		_set_stat_icon(item[0], item[1])
	pass_button.expand_icon = true
	pass_button.add_theme_constant_override("icon_max_width", 28)
	_update_pass_art()
	dossier.resolver = asset_resolver
	dossier.queue_redraw()


func _prepare_dossier() -> void:
	var stage := portrait_rect.get_parent() as Control
	stage.custom_minimum_size = Vector2(140, 132)
	dossier = UnitDossier.new()
	stage.add_child(dossier)
	stage.move_child(dossier, 1)
	dossier.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_rect.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	portrait_rect.position = Vector2(9, 18)
	portrait_rect.size = Vector2(64, 80)
	identity_label.hide()
	identity_label.tooltip_text = "Battle instance identity (diagnostics only)"


func _set_stat_icon(label: Label, slot: String) -> void:
	var icon := label.get_node_or_null("StatIcon") as TextureRect
	if icon == null:
		icon = TextureRect.new()
		icon.name = "StatIcon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(20, 20)
		label.add_child(icon)
		var margin := StyleBoxEmpty.new()
		margin.content_margin_left = 24
		label.add_theme_stylebox_override("normal", margin)
	icon.texture = asset_resolver.texture_for_named("ui", slot)


func _bind_presentation_roles() -> void:
	# Entry points override only the view-side art assignment.
	pass


func _refresh() -> void:
	if not is_node_ready() or scenario == null:
		return
	if scenario.state == null:
		feedback_label.text = latest_feedback
		victory_label.text = ""
		return
	round_label.text = "R%d" % scenario.state.round_number
	side_label.text = "Active: %s (#%d)" % [
		session.side_name(session.active_side_id()), session.active_side_id()]
	mode_label.text = "Mode: %s" % input_mode
	feedback_label.text = latest_feedback
	portrait_rect.texture = null
	portrait_fallback_label.text = "✦"
	if selected_unit == null:
		name_label.text = "Selected: —"
		identity_label.text = "Instance: —"
		life_label.text = "Life: —"
		stamina_label.text = "Stamina: —"
		movement_label.text = "Movement: —"
		ammo_label.text = "Ammo: —"
		attack_label.text = "Attack: —"
		defence_label.text = "Defence: —"
		effects_label.text = "EFFECTS / STATUS\n—"
	else:
		name_label.text = selected_unit.name
		identity_label.text = selected_unit.instance_id
		life_label.text = "Life: %d / %d" % [maxi(0, selected_unit.life), selected_unit.life_base]
		stamina_label.text = "Stamina: %d / %d" % [selected_unit.stamina, selected_unit.stamina_base]
		movement_label.text = "Move: %d" % selected_unit.movement_remaining
		ammo_label.text = "Ammo: %d" % selected_unit.ammo
		attack_label.text = "Atk: %d / Rng: %d" % [selected_unit.attack, selected_unit.ranged_attack]
		defence_label.text = "Def: %d / RDef: %d" % [
			selected_unit.defence, selected_unit.ranged_defence]
		var effect_names: Array = selected_unit.all_flags()
		if not selected_unit.statuses.is_empty():
			effect_names.append(Statuses.describe_all(selected_unit))
		var opening := scenario.opening_restriction_description(selected_unit)
		if opening != "":
			effect_names.append(opening)
		effects_label.text = "EFFECTS / STATUS\n%s" % [
			", ".join(effect_names) if not effect_names.is_empty() else "None"]
		portrait_rect.texture = asset_resolver.texture_for_portrait(selected_unit)
		portrait_fallback_label.text = selected_unit.name.substr(0, 1).to_upper()
	effects_label.tooltip_text = effects_label.text
	if selected_unit != null:
		var descriptions := {
			"Первый удар": "Retaliates before the melee hit unless both units have first strike.",
			"Ловкость": "Avoids melee retaliation.",
			"Касание вампира": "Avoids melee retaliation.",
			"Не сражается": "Cannot attack or retaliate in melee.",
		}
		for flag in selected_unit.all_flags():
			if descriptions.has(String(flag)):
				effects_label.tooltip_text += "\n" + String(descriptions[String(flag)])
	dossier.unit = selected_unit
	dossier.queue_redraw()
	portrait_fallback_label.visible = portrait_rect.texture == null
	var winner := session.winning_side_id()
	victory_label.text = "Victory: %s" % session.side_name(winner) \
		if winner >= 0 else ""
	restart_button.visible = session.battle_complete()
	command_button.disabled = false
	cancel_button.disabled = false
	action_button.visible = _has_drain_grant()
	action_button.disabled = session.battle_complete()
	ranged_button.disabled = session.battle_complete()
	pass_button.disabled = session.battle_complete()
	for control in [command_button, ranged_button, action_button, pass_button, cancel_button]:
		control.disabled = control.disabled or playback.busy
	get_node("%StatsRegion").visible = not playback.busy
	get_node("%EffectsRegion").visible = not playback.busy
	if playback.busy:
		victory_label.text = ""
		round_label.text = "R%d" % _presentation_before.get("round", 1)
		side_label.text = "Playback • input locked"
	_update_pass_art()
	var recent_start := maxi(0, scenario.log.size() - 8)
	events_label.text = "\n".join(scenario.log.slice(recent_start))
	if playback.busy:
		events_label.text = "Playback in progress • Skip to final state"
	var move_cells: Array[Vector2i] = []
	var melee: Array[Combatant] = []
	var ranged: Array[Combatant] = []
	if selected_unit != null:
		if input_mode == MODE_COMMAND:
			move_cells = session.reachable_cells(selected_unit)
			melee = session.legal_melee_targets(selected_unit)
		elif input_mode == MODE_ACTION:
			for target in session.living_units():
				if bool(session.query_command(_action_command(target.instance_id))["accepted"]):
					melee.append(target)
		else:
			ranged = session.legal_ranged_targets(selected_unit)
	battlefield_view.refresh_highlights(selected_unit, move_cells, melee, ranged)


func _update_pass_art() -> void:
	var state := "normal"
	if pass_button.disabled:
		state = "disabled"
	elif pass_button.get_draw_mode() in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED]:
		state = "pressed"
	elif pass_button.get_draw_mode() == BaseButton.DRAW_HOVER or pass_button.has_focus():
		state = "hover"
	var texture := asset_resolver.texture_for_named("ui", "pass_" + state)
	pass_button.icon = texture if texture != null else asset_resolver.texture_for_named("ui", "pass")
