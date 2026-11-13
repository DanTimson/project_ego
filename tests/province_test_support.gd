extends RefCounted

const Authored = preload("res://content/campaign/province_campaign.gd")
const Policy = preload("res://core/campaign/strategic_policy.gd")
var failures := 0


func check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func issue(model: ContestedCampaign, cmd: Dictionary) -> Dictionary:
	var preview := model.query(cmd)
	var result := model.execute(cmd)
	check(preview.ok and result.ok, "command " + JSON.stringify(cmd) + " " + result.reason)
	return result


func refused(model: ContestedCampaign, cmd: Dictionary) -> void:
	var before := model.snapshot()
	var q := model.query(cmd)
	check(
		not q.ok and model.execute(cmd) == q and model.snapshot() == before,
		"atomic refusal " + JSON.stringify(cmd)
	)


func decide(model: ContestedCampaign, choice: String) -> Dictionary:
	return issue(model, {"op": "decide", "choice": choice, "token": model.encounter_choice().token})


func fight(model: ContestedCampaign) -> CampaignEncounter:
	var encounter := model.pending_encounter()
	check(encounter != null, "real tactical encounter")
	if encounter == null:
		return null
	if not encounter.session.started:
		check(encounter.session.begin().ok, "begin tactical encounter")
	for index in 256:
		if encounter.session.battle_complete():
			break
		var result := encounter.session.issue_command(Policy.tactical_command(encounter.session))
		check(result.accepted, "ordinary tactical command " + result.reason)
		if not result.accepted:
			break
	check(model.finish(encounter).ok, "detached result applied")
	return encounter


func end_round(model: ContestedCampaign) -> void:
	issue(model, {"op": "end_turn"})
	for index in 16:
		if not model.in_battle():
			break
		fight(model)
