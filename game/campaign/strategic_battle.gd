extends TacticalController

signal map_requested(commit: bool)

var campaign: RefCounted
var encounter: CampaignEncounter
var destination: String
var army_id := ""
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
		var was_site: bool = campaign is ContestedCampaign and campaign.contest().get("kind") == "site"
		if not campaign.abandon(encounter).ok:
			return false
		var opened: Dictionary
		if was_site:
			opened = campaign.execute({"op": "site", "army": army_id})
			if opened.ok:
				opened = campaign.execute({"op": "decide", "choice": "fight",
					"token": campaign.encounter_choice().token})
		elif campaign is ContestedCampaign:
			opened = campaign.execute({"op": "travel", "army": army_id, "to": destination})
		else:
			opened = campaign.travel(destination)
		if opened.ok and campaign.content().has("province_rules") and not campaign.in_battle():
			opened = campaign.execute({"op": "decide", "choice": "fight",
				"token": campaign.encounter_choice().token})
		if not opened.ok:
			return false
		encounter = opened.encounter
	_initial = false
	var begun := _start_session(encounter.session)
	if begun and campaign is ContestedCampaign and session.active_side_id() == 1:
		_presentation_before = scenario._command_state()
		_apply_command_result({"accepted": true, "events": [], "observations": []})
	return begun


func _refresh() -> void:
	super._refresh()
	if return_button == null or session == null:
		return
	var collectable: bool = encounter.collect().ok
	return_button.text = (
		"Apply result • Return to map" if collectable else "Abandon • Return to map"
	)
	restart_button.visible = true
	if campaign is ContestedCampaign and campaign.contest().get("defense", false):
		return_button.text = "Apply defense result" if collectable else "Concede province and defenders"
		restart_button.visible = false
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
