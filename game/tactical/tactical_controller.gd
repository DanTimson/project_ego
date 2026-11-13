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
var details_dialog: AcceptDialog
var details_content: VBoxContainer
var picker: AcceptDialog
var picker_description: RichTextLabel
var picker_actions: Array[Button] = []
var picker_button: Button
var details_button: Button
var skip_button: Button
var rail_footer: VBoxContainer
var picker_portrait: TextureRect
var picker_frame: PanelContainer
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
	_compose_rail()
	_prepare_dossier()
	playback = BattlePlayback.new()
	add_child(playback)
	if DisplayServer.get_name() == "headless":
		playback.speed = "Instant"
	var controls := details_content
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
	for signal_name in ["mouse_entered", "mouse_exited", "button_down", "button_up",
		"focus_entered", "focus_exited"]:
		cancel_button.connect(signal_name, _update_cancel_art.call_deferred)
	_update_cancel_art()
	_layout_presentation.call_deferred()


func _queue_layout_presentation() -> void:
	_layout_presentation.call_deferred()


func _layout_presentation() -> void:
	if not is_node_ready():
		return
	var rail_width := clampf(size.x * 0.20, 240, 288)
	right_panel.custom_minimum_size.x = rail_width
	right_panel.offset_left = -rail_width
	battlefield_region.offset_right = -rail_width
	var available := battlefield_region.size
	var presentation_scale := minf(
		available.x / BATTLEFIELD_LOGICAL_SIZE.x,
		available.y / BATTLEFIELD_LOGICAL_SIZE.y)
	presentation_scale = maxf(presentation_scale, 0.01)
	battlefield_view.scale = Vector2.ONE * presentation_scale
	battlefield_view.position = Vector2(
		maxf(0.0, (available.x - BATTLEFIELD_LOGICAL_SIZE.x * presentation_scale) * 0.5),
		maxf(0.0, (available.y - BATTLEFIELD_LOGICAL_SIZE.y * presentation_scale) * 0.5))
	if picker.visible:
		_fit_picker()


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
	if playback.busy:
		return
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
	if playback.busy:
		return
	input_mode = MODE_COMMAND
	_set_feedback("Command mode: select, move, or click an orange melee target.")


func enter_ranged_mode() -> void:
	if playback.busy:
		return
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
	_present_vitals(observation.state)


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


# Battle hotkeys keep their meaning after a command button takes focus.
# Dialogs own their own keyboard input, including Escape and Space.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if picker.visible or details_dialog.visible:
		return
	match event.keycode:
		KEY_ESCAPE:
			cancel_selection()
		KEY_R:
			enter_ranged_mode()
		KEY_SPACE:
			pass_side()
		_:
			return
	get_viewport().set_input_as_handled()


func _apply_visual_assets() -> void:
	if not is_node_ready():
		return
	# The original 140x768 panel is never stretched beneath the sidebar.
	# Use a native portrait crop, model labels and authored group frames.
	var panel := asset_resolver.texture_for_named("ui", "panel")
	panel_texture.texture = panel
	panel_texture.hide()
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
	stage.custom_minimum_size = Vector2(74, 88)
	dossier = UnitDossier.new()
	stage.add_child(dossier)
	stage.move_child(dossier, 1)
	dossier.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_rect.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	portrait_rect.position = Vector2(9, 8)
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
	side_label.text = "Active: %s" % session.side_name(session.active_side_id())
	mode_label.text = "Mode: %s" % input_mode
	if input_mode == MODE_ACTION:
		mode_label.text += "\nChoose adjacent enemy • Esc cancels"
	elif input_mode == MODE_RANGED:
		mode_label.text += "\nChoose magenta enemy • Esc cancels"
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
		life_label.text = "Life %d/%d" % [maxi(0, selected_unit.life), selected_unit.life_base]
		stamina_label.text = "Stamina %d/%d" % [selected_unit.stamina, selected_unit.stamina_base]
		movement_label.text = "Move: %d" % selected_unit.movement_remaining
		ammo_label.text = "Ammo: %d" % selected_unit.ammo
		attack_label.text = "Atk %d • Rng %d" % [selected_unit.attack, selected_unit.ranged_attack]
		defence_label.text = "Def %d • RDef %d" % [
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
	victory_label.visible = winner >= 0 and not playback.busy
	restart_button.visible = session.battle_complete()
	command_button.disabled = false
	cancel_button.disabled = false
	action_button.visible = _has_drain_grant()
	action_button.disabled = session.battle_complete() or not _action_available()
	action_button.tooltip_text = _action_reason()
	ranged_button.disabled = session.battle_complete() or selected_unit == null
	if selected_unit != null:
		ranged_button.disabled = (ranged_button.disabled
			or session.legal_ranged_targets(selected_unit).is_empty())
	ranged_button.tooltip_text = _ranged_reason()
	command_button.tooltip_text = "Select an active unit; green cells move, orange targets attack."
	cancel_button.tooltip_text = "Clear selection and return to Move / melee [Esc]."
	pass_button.tooltip_text = "End the active side's phase [Space]."
	pass_button.disabled = session.battle_complete()
	for control in [command_button, ranged_button, action_button, pass_button, cancel_button]:
		control.disabled = control.disabled or playback.busy
	skip_button.disabled = not playback.busy
	picker_button.disabled = playback.busy or session.battle_complete()
	get_node("%StatsRegion").visible = not playback.busy
	get_node("%EffectsRegion").visible = not playback.busy
	if playback.busy:
		victory_label.text = ""
		round_label.text = "R%d" % _presentation_before.get("round", 1)
		side_label.text = "Playback • input locked"
		_present_vitals(battlefield_view.visual_state)
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


func _compose_rail() -> void:
	# Preserve the inherited scene paths and command nodes; disclose long content.
	var rail := get_node("RightPanel/Frame/Margin/PanelScroll/VBox") as VBoxContainer
	rail.add_theme_constant_override("separation", 3)
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := get_node("RightPanel/Frame/Margin") as MarginContainer
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 0)
	var rail_scroll := get_node("RightPanel/Frame/Margin/PanelScroll") as ScrollContainer
	var rail_stack := VBoxContainer.new()
	margin.add_child(rail_stack)
	rail_scroll.reparent(rail_stack)
	rail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_scroll.follow_focus = true
	rail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var title := rail.get_node("Header/HUDTitle") as Label
	title.text = "BATTLE"
	title.add_theme_font_size_override("font_size", 14)
	details_dialog = AcceptDialog.new()
	details_dialog.title = "Battle details • Events & settings"
	add_child(details_dialog)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_dialog.add_child(scroll)
	details_content = VBoxContainer.new()
	details_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(details_content)
	var campaign_controls: Array[Control] = []
	for child in rail.get_children():
		if child == get("return_button"):
			campaign_controls.append(child)
		elif child.name == "CampaignActions":
			for button in child.get_children():
				campaign_controls.append(button)
			child.reparent(details_content)
		elif child.name in ["FeedbackLabel", "EventsLabel", "RestartButton"]:
			child.reparent(details_content)
		elif child.name not in ["Header", "SideLabel", "IdentityRegion", "StatsRegion",
			"ActionRegion", "EffectsRegion", "VictoryLabel"]:
			# Campaign-specific heading, return/retry and continuation controls.
			child.reparent(details_content)
	feedback_label.custom_minimum_size.y = 88
	events_label.custom_minimum_size.y = 180
	var identity := get_node("%IdentityRegion") as Control
	identity.custom_minimum_size.y = 0
	name_label.reparent(rail)
	rail.move_child(name_label, 2)
	name_label.add_theme_font_size_override("font_size", 14)
	for label in [life_label, stamina_label, movement_label, ammo_label, attack_label,
		defence_label, side_label]:
		label.add_theme_font_size_override("font_size", 13)
	for group in ["IdentityRegion", "StatsRegion", "ActionRegion", "EffectsRegion"]:
		var style := PresentationTheme.frame()
		style.content_margin_left = 3
		style.content_margin_right = 3
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		(get_node("%" + group) as PanelContainer).add_theme_stylebox_override("panel", style)
	mode_label.reparent(rail)
	rail.move_child(mode_label, rail.get_child_count() - 1)
	mode_label.add_theme_font_size_override("font_size", 13)
	(get_node("%EffectsRegion") as Control).custom_minimum_size.y = 48
	effects_label.add_theme_font_size_override("normal_font_size", 13)
	var grid := get_node("%ActionRegion").get_child(0)
	rail_footer = VBoxContainer.new()
	rail_stack.add_child(rail_footer)
	for button in campaign_controls:
		button.reparent(rail_footer)
		button.custom_minimum_size.y = 32
		button.add_theme_font_size_override("font_size", 13)
	if campaign_controls.is_empty():
		_rail_button(details_content, "Main Menu", func() -> void:
			get_tree().change_scene_to_file("res://game/demo/demo_main.tscn"))
	var commands := HBoxContainer.new()
	rail_footer.add_child(commands)
	for button in [pass_button, cancel_button]:
		button.reparent(commands)
	pass_button.text = "Pass"
	cancel_button.text = "Cancel"
	command_button.text = "Move / melee"
	ranged_button.text = "Ranged [R]"
	action_button.text = "Stamina Drain"
	picker_button = _rail_button(grid, "Actions…", show_action_picker)
	var utilities := HBoxContainer.new()
	rail_footer.add_child(utilities)
	details_button = _rail_button(utilities, "Details…", show_details)
	skip_button = _rail_button(utilities, "Skip", func() -> void: playback.skip())
	for button in [command_button, ranged_button, action_button, pass_button, cancel_button]:
		button.custom_minimum_size.y = 32
		button.add_theme_font_size_override("font_size", 13)
	details_dialog.confirmed.connect(func() -> void: details_button.grab_focus())
	details_dialog.canceled.connect(func() -> void: details_button.grab_focus())
	_build_picker()


func _rail_button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 32
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func show_details() -> void:
	details_dialog.popup_centered_clamped(Vector2i(540, 440), 0.85)


func _build_picker() -> void:
	picker = AcceptDialog.new()
	picker.title = "Unit actions"
	add_child(picker)
	picker.ok_button_text = "Close"
	picker_frame = PanelContainer.new()
	picker.add_child(picker_frame)
	var columns := HBoxContainer.new()
	picker_frame.add_child(columns)
	var slots := GridContainer.new()
	slots.columns = 2
	columns.add_child(slots)
	for text in ["Move / melee", "Ranged", "Stamina Drain", "Spells — unavailable"]:
		var index := picker_actions.size()
		var button := _rail_button(slots, text, func() -> void: _choose_action(index))
		picker_actions.append(button)
		button.custom_minimum_size.y = 48
		button.focus_entered.connect(func() -> void: _describe_picker(button))
		button.mouse_entered.connect(func() -> void: _describe_picker(button))
	for index in 2:
		var empty := PanelContainer.new()
		empty.custom_minimum_size.y = 32
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slots.add_child(empty)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(detail)
	picker_portrait = TextureRect.new()
	picker_portrait.custom_minimum_size = Vector2(64, 64)
	picker_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picker_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail.add_child(picker_portrait)
	picker_description = RichTextLabel.new()
	picker_description.custom_minimum_size = Vector2(160, 120)
	picker_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_description.focus_mode = Control.FOCUS_ALL
	picker_description.selection_enabled = true
	picker_description.scroll_active = true
	picker_description.add_theme_font_size_override("normal_font_size", 14)
	picker_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(picker_description)
	picker.confirmed.connect(func() -> void: picker_button.grab_focus())
	picker.canceled.connect(func() -> void: picker_button.grab_focus())


func show_action_picker() -> void:
	if playback.busy:
		return
	picker.title = "Unit actions • " + (
		selected_unit.name if selected_unit != null else "No selection")
	picker_portrait.texture = (asset_resolver.texture_for_portrait(selected_unit)
		if selected_unit != null else null)
	if picker_portrait.texture == null:
		picker_portrait.texture = preload("res://game/presentation/art/company_portrait.svg")
	for index in 3:
		picker_actions[index].icon = asset_resolver.texture_for_named(
			"ui", ["attack", "ranged", "stamina"][index])
		picker_actions[index].expand_icon = true
		picker_actions[index].add_theme_constant_override("icon_max_width", 24)
	picker_actions[0].disabled = selected_unit == null
	picker_actions[0].tooltip_text = ("Select a unit first." if selected_unit == null
		else "Move to a green cell or attack an orange adjacent enemy.")
	picker_actions[1].disabled = ranged_button.disabled
	picker_actions[1].tooltip_text = ranged_button.tooltip_text
	picker_actions[2].disabled = not _action_available()
	picker_actions[2].tooltip_text = _action_reason()
	picker_actions[3].disabled = true
	picker_actions[3].icon = asset_resolver.texture_for_named("ui", "spell_disabled")
	picker_actions[3].expand_icon = true
	picker_actions[3].add_theme_constant_override("icon_max_width", 24)
	picker_actions[3].tooltip_text = "Unavailable: spell casting is not implemented."
	picker.popup_centered_clamped(_picker_size(), 0.90)
	_fit_picker()
	for button in picker_actions:
		if not button.disabled:
			_describe_picker(button)
			button.grab_focus()
			return
	_describe_picker(picker_actions[0])
	picker_description.grab_focus()


func _picker_size() -> Vector2i:
	var content_size := picker_frame.get_combined_minimum_size()
	return Vector2i(Vector2(maxf(content_size.x, size.x * 0.48), content_size.y))


func _fit_picker() -> void:
	picker.size = _picker_size()
	picker.position = Vector2i((size - Vector2(picker.size)) * 0.5)


func _choose_action(index: int) -> void:
	if index >= 3 or picker_actions[index].disabled:
		return
	picker.hide()
	if index == 0:
		enter_command_mode()
	elif index == 1:
		enter_ranged_mode()
	else:
		enter_action_mode()
	picker_button.grab_focus()


func _action_available() -> bool:
	if not _has_drain_grant() or session.battle_complete():
		return false
	for target in session.living_units():
		if session.query_command(_action_command(target.instance_id)).accepted:
			return true
	return false


func _action_reason() -> String:
	if selected_unit == null:
		return "Stamina Drain: select a unit to inspect its granted action."
	if not _has_drain_grant():
		return "Stamina Drain is not granted to this unit."
	if not _action_available():
		return "Stamina Drain is granted; temporarily illegal: no legal adjacent enemy or action spent."
	return ("Stamina Drain: granted action. Choose a highlighted adjacent enemy "
		+ "using the normal action targeting path.")


func _update_cancel_art() -> void:
	var state := "normal"
	if cancel_button.get_draw_mode() in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED]:
		state = "pressed"
	elif cancel_button.is_hovered() or cancel_button.has_focus():
		state = "hover"
	cancel_button.icon = asset_resolver.texture_for_named("ui", "cancel_" + state)
	cancel_button.expand_icon = true
	cancel_button.add_theme_constant_override("icon_max_width", 20)


func _describe_picker(button: Button) -> void:
	var descriptions: PackedStringArray = [button.tooltip_text]
	for action in picker_actions:
		if action != button and action.disabled and not action.tooltip_text.is_empty():
			descriptions.append(action.tooltip_text)
	picker_description.text = "\n\n".join(descriptions)
	picker_description.scroll_to_line(0)


func _present_vitals(state: Dictionary) -> void:
	if selected_unit == null or state.is_empty():
		return
	var unit: Dictionary = state.units.get(selected_unit.instance_id, {})
	if unit.is_empty():
		return
	life_label.text = "Life %d/%d" % [maxi(0, unit.life), selected_unit.life_base]
	stamina_label.text = "Stamina %d/%d" % [unit.stamina, selected_unit.stamina_base]
	movement_label.text = "Move: %d" % unit.movement_remaining


func _ranged_reason() -> String:
	if selected_unit == null:
		return "Ranged: select a unit first."
	var restriction := Statuses.restriction_reason(selected_unit, Status.Capability.RANGED)
	if restriction != "":
		return "Ranged: " + restriction + ". " + scenario.opening_restriction_description(selected_unit)
	if session.legal_ranged_targets(selected_unit).is_empty():
		return "Ranged: needs ammunition and a non-adjacent enemy within range."
	return "Ranged: click a magenta enemy target."
