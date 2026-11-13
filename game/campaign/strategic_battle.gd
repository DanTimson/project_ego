extends TacticalController

signal map_requested(commit: bool)

var campaign: StrategicCampaign
var encounter: CampaignEncounter
var destination: String
var return_button: Button
var _initial := true


func _ready() -> void:
	battlefield_view.adapter.origin = Vector2(268, 285)
	var controls := get_node("RightPanel/Frame/Margin/PanelScroll/VBox")
	var heading := Label.new()
	heading.text = "Campaign encounter • " + destination.capitalize()
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(heading)
	controls.move_child(heading, 0)
	return_button = Button.new()
	return_button.pressed.connect(_return_to_map)
	controls.add_child(return_button)
	controls.move_child(return_button, 1)
	restart_button.text = "Retry from map roster"
	super._ready()


func restart_battle() -> bool:
	if not _initial:
		if not campaign.abandon(encounter).ok:
			return false
		var opened := campaign.travel(destination)
		if not opened.ok:
			return false
		encounter = opened.encounter
	_initial = false
	return _start_session(encounter.session)


func _refresh() -> void:
	super._refresh()
	if return_button == null or session == null:
		return
	var collectable: bool = encounter.collect().ok
	return_button.text = (
		"Apply result • Return to map" if collectable else "Abandon • Return to map"
	)
	restart_button.visible = true
	if scenario.runtime_error != "":
		feedback_label.text = (
			"Battle halted: " + scenario.runtime_error + ". Return to map without applying."
		)


func _return_to_map() -> void:
	map_requested.emit(encounter.collect().ok)


func _bind_presentation_roles() -> void:
	# All enemies in this authored encounter family have the guard visual role.
	# This uses side membership, with no display-name or attempt-ID parsing.
	for unit in scenario.units.values():
		if scenario.side_of(unit).id == 1:
			asset_resolver.assign_role(unit, "campaign_guard")
