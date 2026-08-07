class_name TacticalController
extends Node2D

const MODE_COMMAND := "Move / melee"
const MODE_RANGED := "Ranged"

@export_file("*.json") var scenario_path := "res://scenarios/playable_tactical_slice.json"

var scenario: Scenario
var session: ManualBattleSession
var selected_unit: Combatant
var input_mode := MODE_COMMAND
var asset_resolver := TacticalAssetResolver.new()
var latest_feedback := "Select a highlighted active-side unit."

@onready var battlefield_view: TacticalBattlefieldView = %BattlefieldView
@onready var round_label: Label = %RoundLabel
@onready var side_label: Label = %SideLabel
@onready var name_label: Label = %NameLabel
@onready var identity_label: Label = %IdentityLabel
@onready var life_label: Label = %LifeLabel
@onready var stamina_label: Label = %StaminaLabel
@onready var movement_label: Label = %MovementLabel
@onready var ammo_label: Label = %AmmoLabel
@onready var mode_label: Label = %ModeLabel
@onready var feedback_label: Label = %FeedbackLabel
@onready var victory_label: Label = %VictoryLabel
@onready var events_label: RichTextLabel = %EventsLabel
@onready var ranged_button: Button = %RangedButton
@onready var pass_button: Button = %PassButton
@onready var restart_button: Button = %RestartButton
@onready var cancel_button: Button = %CancelButton


func _ready() -> void:
	battlefield_view.cell_clicked.connect(_on_cell_clicked)
	battlefield_view.cancel_requested.connect(cancel_selection)
	ranged_button.pressed.connect(enter_ranged_mode)
	pass_button.pressed.connect(pass_side)
	restart_button.pressed.connect(restart_battle)
	cancel_button.pressed.connect(cancel_selection)
	restart_battle()


func _load_scenario_spec() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(scenario_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Playable tactical scenario is malformed: %s" % scenario_path)
		return {}
	return parsed


func restart_battle() -> bool:
	if session != null:
		session.end()
	# Reload the ignored local index/mapping so changing presentation assets does
	# not require an editor restart.
	asset_resolver.configure()
	var scenario_spec := _load_scenario_spec()
	if scenario_spec.is_empty():
		latest_feedback = "Could not load the playable scenario."
		_refresh()
		return false
	scenario = Scenario.new(scenario_spec)
	session = ManualBattleSession.new(scenario)
	var begun := session.begin()
	selected_unit = null
	input_mode = MODE_COMMAND
	latest_feedback = "Battle ready. Select an Azure Company unit."
	battlefield_view.configure(session, asset_resolver)
	_refresh()
	return bool(begun["ok"])


func select_unit(instance_id: String) -> bool:
	if scenario == null or session.battle_complete():
		_set_feedback("Selection refused: the battle is over.")
		return false
	var unit: Combatant = scenario.units.get(instance_id)
	if unit == null:
		_set_feedback("Selection refused: unknown unit '%s'." % instance_id)
		return false
	if not session.can_select(unit):
		_set_feedback("Selection refused: %s is inactive, down, or spent." % unit.label())
		return false
	selected_unit = unit
	input_mode = MODE_COMMAND
	_set_feedback("Selected %s." % unit.label())
	return true


func dispatch_move(cell: Vector2i) -> Dictionary:
	if selected_unit == null:
		return _controller_refusal("Select a unit before moving.")
	var result := session.issue_command({
		"op": "move", "unit": selected_unit.instance_id,
		"to": [cell.x, cell.y],
	})
	_apply_command_result(result)
	return result


func dispatch_melee(target_id: String) -> Dictionary:
	if selected_unit == null:
		return _controller_refusal("Select a unit before attacking.")
	var result := session.issue_command({
		"op": "attack", "unit": selected_unit.instance_id, "target": target_id,
	})
	_apply_command_result(result)
	return result


func dispatch_ranged(target_id: String) -> Dictionary:
	if selected_unit == null:
		return _controller_refusal("Select a unit before shooting.")
	var result := session.issue_command({
		"op": "shoot", "unit": selected_unit.instance_id, "target": target_id,
	})
	input_mode = MODE_COMMAND
	_apply_command_result(result)
	return result


func pass_side() -> Dictionary:
	if scenario == null:
		return _controller_refusal("No battle is loaded.")
	var result := session.issue_command({"op": "end_phase"})
	selected_unit = null
	input_mode = MODE_COMMAND
	_apply_command_result(result)
	return result


func enter_ranged_mode() -> void:
	if selected_unit == null:
		_set_feedback("Ranged mode refused: select a unit first.")
		return
	if session.legal_ranged_targets(selected_unit).is_empty():
		_set_feedback("Ranged mode refused: no legal target, range, or ammunition.")
		return
	input_mode = MODE_RANGED
	_set_feedback("Ranged mode: click a magenta enemy target.")


func cancel_selection() -> void:
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


func _apply_command_result(result: Dictionary) -> void:
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
	_refresh()


func _set_feedback(message: String) -> void:
	latest_feedback = message
	_refresh()


func _unit_at(cell: Vector2i) -> Combatant:
	for unit in session.living_units():
		if session.unit_position(unit) == cell:
			return unit
	return null


func _on_cell_clicked(cell: Vector2i) -> void:
	if session.battle_complete():
		_set_feedback("Battle complete. Use Restart Battle.")
		return
	var occupant := _unit_at(cell)
	if occupant != null:
		if scenario.side_of(occupant).id == session.active_side_id():
			select_unit(occupant.instance_id)
		elif selected_unit == null:
			_set_feedback("Selection refused: that unit belongs to the inactive side.")
		elif input_mode == MODE_RANGED:
			dispatch_ranged(occupant.instance_id)
		else:
			dispatch_melee(occupant.instance_id)
		return
	if input_mode == MODE_RANGED:
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


func _refresh() -> void:
	if not is_node_ready() or scenario == null:
		return
	round_label.text = "Round: %d" % scenario.state.round_number
	side_label.text = "Active side: %s (#%d)" % [
		session.side_name(session.active_side_id()), session.active_side_id()]
	mode_label.text = "Input mode: %s" % input_mode
	feedback_label.text = "Latest: %s" % latest_feedback
	if selected_unit == null:
		name_label.text = "Selected: —"
		identity_label.text = "Instance: —"
		life_label.text = "Life: —"
		stamina_label.text = "Stamina: —"
		movement_label.text = "Movement: —"
		ammo_label.text = "Ammunition: —"
	else:
		name_label.text = "Selected: %s" % selected_unit.name
		identity_label.text = "Instance: %s" % selected_unit.instance_id
		life_label.text = "Life: %d / %d" % [maxi(0, selected_unit.life), selected_unit.life_base]
		stamina_label.text = "Stamina: %d / %d" % [selected_unit.stamina, selected_unit.stamina_base]
		movement_label.text = "Movement remaining: %d" % selected_unit.movement_remaining
		ammo_label.text = "Ammunition: %d" % selected_unit.ammo
	var winner := session.winning_side_id()
	victory_label.text = "Victory: %s" % session.side_name(winner) \
		if winner >= 0 else ""
	restart_button.visible = session.battle_complete()
	ranged_button.disabled = session.battle_complete()
	pass_button.disabled = session.battle_complete()
	var recent_start := maxi(0, scenario.log.size() - 8)
	events_label.text = "\n".join(scenario.log.slice(recent_start))
	var move_cells: Array[Vector2i] = []
	var melee: Array[Combatant] = []
	var ranged: Array[Combatant] = []
	if selected_unit != null:
		if input_mode == MODE_COMMAND:
			move_cells = session.reachable_cells(selected_unit)
			melee = session.legal_melee_targets(selected_unit)
		else:
			ranged = session.legal_ranged_targets(selected_unit)
	battlefield_view.refresh_highlights(selected_unit, move_cells, melee, ranged)
