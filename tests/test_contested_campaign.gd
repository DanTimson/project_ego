extends SceneTree

const Authored = preload("res://content/campaign/contested_campaign.gd")
const Policy = preload("res://core/campaign/strategic_policy.gd")
var failures := 0


func check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func issue(model: ContestedCampaign, command: Dictionary) -> Dictionary:
	var preview := model.query(command)
	var result := model.execute(command)
	check(preview.ok and result.ok, "command " + JSON.stringify(command) + " " + result.reason)
	return result


func refused(model: ContestedCampaign, command: Dictionary) -> void:
	var before := model.snapshot()
	var preview := model.query(command)
	check(not preview.ok and preview == model.execute(command) and model.snapshot() == before,
		"atomic refusal " + JSON.stringify(command) + " " + preview.reason)


func fight(model: ContestedCampaign) -> CampaignEncounter:
	var encounter := model.pending_encounter()
	check(encounter != null, "real encounter pending")
	if encounter == null:
		return null
	check(encounter.session.begin().ok, "begin retained tactical session")
	var attacker: int = model.contest().attacker_side
	check(encounter.session.active_side_id() == attacker, "actual attacker receives tie initiative")
	for index in 256:
		if encounter.session.battle_complete():
			break
		var command := Policy.tactical_command(encounter.session)
		var result := encounter.session.issue_command(command)
		check(result.accepted, "real tactical command " + JSON.stringify(command))
		if not result.accepted:
			break
	check(encounter.collect_contest().ok, "detached two-sided result collects")
	var result := model.finish(encounter)
	check(result.ok, "atomic roster/control resolution " + result.reason)
	return encounter


func fights(model: ContestedCampaign) -> void:
	for index in 12:
		if not model.in_battle():
			return
		fight(model)
	check(false, "bounded defensive encounters")


func routes() -> void:
	var c := Authored.definition()
	var model := ContestedCampaign.create(c)
	issue(model, {"op": "build", "id": "market"})
	check(model.snapshot().factions.azure.gold == 4 and model.snapshot().round == 1,
		"Market spends before income without advancing round")
	refused(model, {"op": "recruit", "id": c.recruit_def})
	issue(model, {"op": "travel", "army": "azure-first", "to": "ford"})
	refused(model, {"op": "travel", "army": "azure-first", "to": "watchpost"})
	var waiting := issue(model, {"op": "end_turn"})
	check(waiting.has("encounter") and model.snapshot().phase == "rival"
		and not model.checkpoint().ok, "rival phase suspends for interactive defense; saves blocked")
	var before := model.snapshot()
	check(not model.abandon(model.pending_encounter()).ok and model.snapshot() == before,
		"defense cannot abandon or cancel rival turn")
	refused(model, {"op": "end_turn"})
	var defense := fight(model)
	check(model.snapshot().round == 2 and model.snapshot().completed == 1
		and model.snapshot().factions.azure.gold == 11, "one payout excludes new Market")
	check(model.snapshot().units["azure-vanguard"].life == 16
		and model.snapshot().casualties.has("crimson-raider")
		and model.snapshot().provinces.quarry.owner == "crimson"
		and model.snapshot().next_army == 2, "two-sided life, casualty, second rival move and formation")
	before = model.snapshot()
	check(not model.finish(defense).ok and model.snapshot() == before,
		"stale defense cannot resume phase twice")
	issue(model, {"op": "recruit", "id": c.recruit_def})
	issue(model, {"op": "form", "province": "home",
		"units": ["azure-guard", "recruited-1"]})
	issue(model, {"op": "transfer", "unit": "azure-guard", "army": ""})
	check(model.army_count("azure") == 2 and model.members("", "home") == ["azure-guard"],
		"second army forms while retaining Home garrison")
	refused(model, {"op": "travel", "army": "formed-2", "to": "quarry"})
	issue(model, {"op": "travel", "army": "azure-first", "to": "watchpost"})
	issue(model, {"op": "end_turn"})
	fights(model)
	var s := model.snapshot()
	print("CONTESTED ROUTE ROUND 3 ", JSON.stringify(s))
	check(s.status == "active" and s.round == 3 and s.factions.azure.gold == 15,
		"second payout uses Market and post-rival ownership")
	issue(model, {"op": "travel", "army": "formed-2", "to": "quarry"})
	issue(model, {"op": "travel", "army": "azure-first", "to": "keep"})
	fights(model)
	s = model.snapshot()
	check(s.status == "victory" and s.provinces.keep.owner == "azure"
		and s.provinces.quarry.owner == "azure", "complete real-command victory with second army")
	check(ContestedCampaign.from_checkpoint(c, model.checkpoint().data).ok, "terminal save round trip")
	print("CONTESTED VICTORY round=", s.round, " gold=", s.factions.azure.gold,
		" units=", s.units)


func loss_and_reclaim() -> void:
	var c := Authored.definition()
	var model := ContestedCampaign.create(c)
	issue(model, {"op": "travel", "army": "azure-first", "to": "ford"})
	issue(model, {"op": "end_turn"})
	check(model.concede().ok and not model.in_battle(), "explicit real defensive concession resumes")
	var s := model.snapshot()
	check(s.status == "active" and not s.armies.has("azure-first")
		and s.casualties.has("azure-vanguard") and s.provinces.ford.owner == "crimson",
		"army loss survivable with capital; conceded defenders retained as casualties")
	var saved: Dictionary = model.checkpoint().data
	var restored := ContestedCampaign.from_checkpoint(c, JSON.parse_string(JSON.stringify(saved)))
	check(restored.ok and restored.campaign.snapshot() == s, "loss ownership and survivors resume")
	var resumed: ContestedCampaign = restored.campaign
	for m in [model, resumed]:
		issue(m, {"op": "form", "province": "home", "units": ["azure-guard"]})
		issue(m, {"op": "end_turn"})
		fights(m)
	check(model.snapshot() == resumed.snapshot(),
		"next rival/player transitions identical after resume")
	# Surviving defender can take back Ford on the following player round.
	var army := model.field_at("home")
	if army != "" and model.snapshot().status == "active":
		issue(model, {"op": "travel", "army": army, "to": "ford"})
		fights(model)
	check(model.snapshot().provinces.ford.owner == "azure"
		and model.snapshot().casualties.has("azure-vanguard"),
		"reclaim lost Ford without resurrecting casualties")
	var reclaimed := ContestedCampaign.from_checkpoint(c, model.checkpoint().data)
	check(reclaimed.ok and reclaimed.campaign.snapshot() == model.snapshot()
		and reclaimed.campaign.snapshot().units["azure-guard"].life == 14
		and reclaimed.campaign.snapshot().armies[army].moves == 0,
		"reclaimed ownership, wounded survivor and spent budget survive a second resume")
	print("RECLAIM STATE ", JSON.stringify(model.snapshot()))


func transfers() -> void:
	var c := Authored.definition()
	var model := ContestedCampaign.create(c)
	refused(model, {"op": "transfer", "unit": "crimson-raider", "army": "azure-first"})
	refused(model, {"op": "form", "province": "home", "units": ["azure-guard"]})
	var limited := Authored.definition()
	limited.army_limit = 1
	check(ContestedCampaign.create(limited) == null,
		"opening with two rival armies exceeds the one-army limit")
	limited.armies.erase("crimson-second")
	for unit in limited.units:
		if unit.army == "crimson-second":
			unit.army = ""
	var at_limit := ContestedCampaign.create(limited)
	check(at_limit != null, "one-army fixture has legal opening forces")
	if at_limit == null:
		return
	issue(at_limit, {"op": "travel", "army": "azure-first", "to": "ford"})
	var formation := {"op": "form", "province": "home", "units": ["azure-guard"]}
	refused(at_limit, formation)
	check(at_limit.query(formation).reason == "Field army limit or province occupied.",
		"second army is refused specifically by the field-army limit")
	issue(model, {"op": "transfer", "unit": "azure-guard", "army": "azure-first"})
	issue(model, {"op": "travel", "army": "azure-first", "to": "ford"})
	issue(model, {"op": "transfer", "unit": "azure-guard", "army": ""})
	issue(model, {"op": "transfer", "unit": "azure-vanguard", "army": ""})
	check(not model.snapshot().armies.has("azure-first"), "empty army disbands")
	issue(model, {"op": "form", "province": "ford", "units": ["azure-vanguard"]})
	refused(model, {"op": "travel", "army": "formed-1", "to": "watchpost"})
	issue(model, {"op": "transfer", "unit": "azure-guard", "army": "formed-1"})
	check(model.snapshot().units["azure-guard"].moved
		and model.snapshot().units["azure-guard"].life == 20
		and model.snapshot().armies["formed-1"].moves == 0,
		"transfers preserve life and spent troop movement")
	refused(model, {"op": "transfer", "unit": "azure-guard", "army": "crimson-second"})
	refused(model, {"op": "form", "province": "home", "units": []})
	var detached := model.snapshot()
	detached.units.clear()
	check(not model.snapshot().units.is_empty(), "snapshots detached")


func alternate_and_boundaries() -> void:
	var c := Authored.alternate()
	var model := ContestedCampaign.create(c)
	check(model != null, "different authored graph and army setup without engine edits")
	issue(model, {"op": "travel", "army": "coast-company", "to": "salt"})
	issue(model, {"op": "end_turn"})
	fights(model)
	issue(model, {"op": "travel", "army": "coast-company", "to": "port"})
	fights(model)
	check(model.snapshot().status == "victory" and model.snapshot().factions.azure.gold == 17
		and model.snapshot().units["coast-vanguard"].life == 16,
		"alternate real-command capital route: round 2, 17g, Vanguard 16/20")
	c = Authored.alternate()
	c.round_limit = 1
	model = ContestedCampaign.create(c)
	issue(model, {"op": "travel", "army": "coast-company", "to": "salt"})
	issue(model, {"op": "end_turn"})
	fights(model)
	check(model.snapshot().status == "defeat" and model.snapshot().completed == 1,
		"last completed round pays once then exhausts")
	check(ContestedCampaign.from_checkpoint(c, model.checkpoint().data).ok,
		"exhaustion checkpoint consistent")
	# Objective on the very last playable round wins before End Turn/exhaustion.
	c = Authored.alternate()
	c.round_limit = 1
	c.armies["coast-company"].province = "salt"
	c.provinces.salt.owner = "azure"
	c.units[0].province = "salt"
	model = ContestedCampaign.create(c)
	issue(model, {"op": "travel", "army": "coast-company", "to": "port"})
	fights(model)
	check(model.snapshot().status == "victory" and model.snapshot().round == 1
		and model.snapshot().completed == 0, "last-round objective victory before exhaustion")


func _initialize() -> void:
	transfers()
	routes()
	loss_and_reclaim()
	alternate_and_boundaries()
	print("CONTESTED CAMPAIGN: %d failures" % failures)
	quit(0 if failures == 0 else 1)
