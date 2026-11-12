extends TacticalController

const MENU := "res://game/demo/demo_main.tscn"
const VANGUARD := "azure-vanguard"
const SCOUT := "azure-scout"
const ROSTER := [
	{"id": VANGUARD, "def": "campaign:unit/1", "life": 20,
		"definition": {"name": "Vanguard", "life": 20, "attack": 30}},
	{"id": SCOUT, "def": "campaign:unit/2", "life": 4,
		"definition": {"name": "Scout", "life": 4, "attack": 3, "speed": 2}},
]
const ENCOUNTERS := [
	{"id": "ford", "name": "Ford", "seed": 42, "enemy": {
		"id": "ford:guard", "name": "Ford Guard", "at": [1, 0], "life": 8,
		"attack": 6, "counter_attack": 5, "flags": ["Первый удар"]}},
	{"id": "watchpost", "name": "Watchpost", "seed": 43, "enemy": {
		"id": "watchpost:sentinel", "name": "Sentinel", "at": [2, 0], "life": 10,
		"attack": 5, "counter_attack": 3}},
]

var _roster: CampaignRoster
var _encounter: CampaignEncounter
var _stage := 0
var _ford_applied := false

@onready var _heading: Label = %CampaignHeading
@onready var _continue: Button = %ContinueButton


func _ready() -> void:
	# Centre the authored 4 × 3 field in the existing battlefield view.
	battlefield_view.adapter.origin = Vector2(268, 285)
	_continue.pressed.connect(continue_campaign)
	%MenuButton.pressed.connect(_return_to_menu)
	restart_button.text = "Retry Encounter"
	super._ready()


func restart_battle() -> bool:
	if _ford_applied and _stage == 0:
		return false
	if _roster == null:
		var created := CampaignRoster.create(ROSTER, "native-campaign-demo-v1")
		if not created.ok:
			return _show_error(created.reason)
		_roster = created.roster
	return _open_encounter(_stage)


func _open_encounter(stage: int) -> bool:
	var setup: Dictionary = ENCOUNTERS[stage]
	var source := _roster.snapshot()
	var mapping: Dictionary = {}
	var positions := {VANGUARD: [0, 0], SCOUT: [1, 1]}
	for id in positions:
		if source.entries[id].life > 0:
			mapping[id] = {"instance_id": "%s:%s" % [setup.id, id], "at": positions[id]}
	var opened := CampaignEncounter.open(source, setup.id, setup.seed, mapping,
		{"width": 4, "height": 3}, [setup.enemy])
	if not opened.ok:
		return _show_error(opened.reason)
	_encounter = opened.encounter
	_stage = stage
	return _start_session(_encounter.session)


func continue_campaign() -> bool:
	if not _can_continue():
		return false
	if not _ford_applied:
		var collected := _encounter.collect()
		if not collected.ok:
			return _show_error(collected.reason)
		var applied := _roster.apply(collected.outcome)
		if not applied.ok:
			return _show_error(applied.reason)
		_ford_applied = true
	return _open_encounter(1)


func _can_continue() -> bool:
	return _stage == 0 and session != null and session.started \
		and scenario.runtime_error.is_empty() and session.winning_side_id() == 0


func _refresh() -> void:
	super._refresh()
	_heading.text = "%s  •  %d of %d" % [ENCOUNTERS[_stage].name, _stage + 1, ENCOUNTERS.size()]
	_continue.visible = _can_continue()
	if _ford_applied and _stage == 0:
		restart_button.hide()
	if _stage == 1 and session != null and scenario.runtime_error.is_empty() \
			and session.winning_side_id() == 0:
		_heading.text = "Watchpost secured • Campaign complete"


func _show_error(reason: String) -> bool:
	latest_feedback = "Campaign could not proceed. " + reason
	_refresh()
	feedback_label.text = latest_feedback
	return false


func _return_to_menu() -> void:
	var error := get_tree().change_scene_to_file(MENU)
	if error != OK:
		_show_error(error_string(error))
