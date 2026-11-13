extends SceneTree

const Authored = preload("res://content/campaign/native_campaign.gd")
var failures := 0


func check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func refused(model: StrategicCampaign, command: String, id := "") -> void:
	var before := model.snapshot()
	var preview := model.query(command, id)
	var result: Dictionary
	match command:
		"build": result = model.build(id)
		"recruit": result = model.recruit(id)
		_: result = model.recover()
	check(not preview.ok and result == preview and before == model.snapshot(),
		"atomic preview/command refusal: %s %s %s" % [command, id, result.reason])


func win(model: StrategicCampaign, id: String, sacrifice := false, archer := "") -> void:
	var opened := model.travel(id)
	check(opened.ok and opened.has("encounter"), "open " + id)
	if not opened.ok or not opened.has("encounter"):
		return
	var encounter: CampaignEncounter = opened.encounter
	check(encounter.session.begin().ok, "begin " + id)
	var target: String = encounter.session.living_units(1)[0].instance_id
	if sacrifice:
		check(encounter.session.issue_command({"op": "attack", "unit":
			encounter._mapping["azure-scout"].instance_id, "target": target}).accepted,
			"real Scout sacrifice")
	if archer != "":
		var unit: Combatant = encounter.session.scenario.units[encounter._mapping[archer].instance_id]
		check(unit.life == 12 and unit.attack == 4 and unit.ranged_attack == 12
			and unit.shooting_range == 4 and unit.ammo == 3, "authored Archer reaches tactical model")
		var scenario := encounter.session.scenario
		var guard: Combatant = scenario.units[target]
		var command := {"op": "shoot", "unit": unit.instance_id, "target": target}
		var before: int = guard.life
		var state := scenario._command_state()
		var calls: Dictionary = scenario.rng.calls.duplicate(true)
		check(guard not in encounter.session.legal_ranged_targets(unit),
			"adjacent guard is absent from ranged highlights")
		var refusal := encounter.session.issue_command(command)
		check(not refusal.accepted and refusal.reason.contains("adjacent")
			and scenario._command_state() == state and scenario.rng.calls == calls,
			"adjacent shot refuses without combat state or RNG changes")
		scenario.cmd_shoot(unit, guard)
		check(scenario._command_state() == state and scenario.rng.calls == calls,
			"direct shot also refuses before ammo, action and RNG")
		check(encounter.session.issue_command({"op": "move", "unit": unit.instance_id,
			"to": [0, 2]}).accepted, "Archer steps back out of contact")
		var shot := encounter.session.issue_command(command)
		var after: int = encounter.session.scenario.units[target].life
		check(shot.accepted and unit.ammo == 2 and after < before,
			"legal ranged shot spends ammo and damages")
		print("ARCHER SHOT: accepted=", shot.accepted, " enemy life=", before, " -> ", after,
			" ammo=", unit.ammo)
	if not encounter.session.battle_complete():
		check(encounter.session.issue_command({"op": "attack", "unit":
			encounter._mapping["azure-vanguard"].instance_id, "target": target}).accepted,
			"real Vanguard melee")
	check(encounter.session.winning_side_id() == 0 and model.finish(encounter).ok, "capture " + id)
	print("CASTLE ROUTE: ", id, " turn=", model.snapshot().turn, " gold=", model.snapshot().gold)


func routes() -> void:
	var model := StrategicCampaign.create(Authored.definition())
	check(model.build("market").ok and model.snapshot().gold == 7
		and model.snapshot().turn == 1 and model.province_income("home") == 5,
		"Market 12 - 8 + 3 = 7; activates after its build")
	refused(model, "recruit")
	win(model, "ford", true)
	model.travel("home")
	check(model.recover().ok, "economy route pays recovery")
	check(model.recruit().ok, "economy route buys Home Guard")
	model.travel("ford")
	win(model, "watchpost")
	win(model, "keep")
	check(model.snapshot().status == "victory" and model.snapshot().turn == 8
		and model.snapshot().gold == 70, "Market route reaches Keep within baseline limit")
	model = StrategicCampaign.create(Authored.definition())
	check(model.build("archery_range").ok and model.snapshot().gold == 5
		and model.snapshot().turn == 1, "Range opening costs ten before income")
	refused(model, "recruit", "campaign:unit/5")
	win(model, "quarry")
	model.travel("home")
	check(model.recruit("campaign:unit/5").ok, "ordinary income affords Archer at Home")
	model.travel("quarry")
	var before := model.snapshot()
	var attempt: CampaignEncounter = model.travel("mill").encounter
	refused(model, "build", "market")
	refused(model, "recruit", "campaign:unit/5")
	check(model.abandon(attempt).ok, "abandon Archer deployment")
	var after := model.snapshot()
	after.battle_serial = before.battle_serial
	check(before == after, "abandon preserves turn, gold, buildings and members")
	win(model, "mill", false, "recruit-1")
	win(model, "keep")
	check(model.snapshot().status == "victory" and model.snapshot().turn == 7
		and model.snapshot().gold == 53, "Archer route reaches Keep within baseline limit")


func catalogue() -> void:
	var content := Authored.definition()
	var model := StrategicCampaign.create(content)
	for id in ["unknown", "workshop", "guard_tower"]:
		refused(model, "build", id)
	for type in ["unknown", "campaign:unit/4", "campaign:unit/5", "campaign:unit/6"]:
		refused(model, "recruit", type)
	var detached := model.catalogue()
	detached[0].requires.append("tamper")
	var options := model.recruit_options()
	options.clear()
	var snap := model.snapshot()
	snap.buildings.append({"id": "market", "turn": 0})
	check(model.catalogue()[0].requires.is_empty() and not model.has_building("market")
		and model.recruit_options().size() == 4, "queries and snapshots are detached")
	content.opening_gold = 200
	model = StrategicCampaign.create(content)
	win(model, "ford", true)
	refused(model, "build", "market")
	model.travel("home")
	var income := 3
	for id in content.buildings:
		var gold: int = model.snapshot().gold
		check(model.build(id).ok, "build " + id)
		check(model.snapshot().gold == gold - content.buildings[id].cost + income + 4,
			"build credits prior effective owned income once")
		if content.buildings[id].effect == "income":
			income += content.buildings[id].value
		refused(model, "build", id)
	check(model.province_income("home") == 7 and model.recovery_life() == 8,
		"Market, Workshop and Granary effects compose")
	for type in ["campaign:unit/4", "campaign:unit/5", "campaign:unit/6"]:
		check(model.recruit(type).ok, "unlocked recruit " + type)
	refused(model, "recruit")
	var deployment: CampaignEncounter = model.travel("quarry").encounter
	check(deployment._mapping.size() == 4 and not deployment._mapping.has("azure-scout"),
		"mixed recruits deploy through the ordinary cap/casualty path")
	for id in ["recruit-1", "recruit-2", "recruit-3"]:
		var unit: Combatant = deployment.session.scenario.units[deployment._mapping[id].instance_id]
		var definition: Dictionary = content.definitions[model.snapshot().roster.entries[id].def]
		check(unit.life == definition.life and unit.attack == definition.attack
			and unit.defence == definition.get("defence", 0), "full-life recruit stats " + id)
	model.abandon(deployment)
	var data: Dictionary = model.checkpoint().data
	var resumed := StrategicCampaign.from_checkpoint(content, data)
	check(resumed.ok and resumed.campaign.checkpoint().data == data,
		"v2 round trip all buildings, mixed recruits, wounds and casualty")
	var wounded: int = model.snapshot().roster.entries["azure-vanguard"].life
	check(model.recover() == resumed.campaign.recover()
		and model.checkpoint().data == resumed.campaign.checkpoint().data,
		"same next command after resume")
	check(model.snapshot().roster.entries["azure-vanguard"].life == mini(20, wounded + 8)
		and model.snapshot().roster.entries["azure-scout"].life == 0,
		"Granary heals survivors only")
	refused(model, "build", "market")
	for mutation in [
		"unknown", "duplicate", "order", "turn", "recruit_turn", "type", "unlock", "gold"
	]:
		var bad := data.duplicate(true)
		match mutation:
			"unknown": bad.state.buildings[0].id = "missing"
			"duplicate": bad.state.buildings[1].id = "market"
			"order": bad.state.buildings[0].id = "workshop"
			"turn": bad.state.buildings[0].turn = 0
			"recruit_turn": bad.state.recruit_turns[0] = bad.state.buildings[0].turn
			"type": bad.members[2].def = "campaign:unit/1"
			"unlock": bad.state.buildings.remove_at(3)
			"gold": bad.state.gold = 10000
		check(not StrategicCampaign.from_checkpoint(content, bad).ok,
			"reject malformed v2 " + mutation)
	for mutation in ["missing", "cycle", "effect", "recruit", "unlock", "default"]:
		var bad := Authored.definition()
		match mutation:
			"missing": bad.buildings.workshop.requires = ["missing"]
			"cycle": bad.buildings.market.requires = ["workshop"]
			"effect": bad.buildings.market.effect = "callback"
			"recruit": bad.buildings.barracks.value = "missing"
			"unlock": bad.recruits["campaign:unit/4"].requires = "market"
			"default": bad.recruit_def = "missing"
		check(StrategicCampaign.create(bad) == null, "definition rejects " + mutation)
	var opening := StrategicCampaign.create(Authored.definition())
	opening.build("market")
	var bonus_ceiling: Dictionary = opening.checkpoint().data
	# Conservative province ceiling is 29 per turn; no bonus on Market's own turn.
	bonus_ceiling.state.gold = 34
	check(not StrategicCampaign.from_checkpoint(Authored.definition(), bonus_ceiling).ok,
		"gold ceiling excludes income bonus on its own build turn")
	content = Authored.definition()
	content.turn_limit = 1
	model = StrategicCampaign.create(content)
	check(model.build("market").ok and model.snapshot().status == "defeat"
		and model.snapshot().gold == 7, "last-turn construction credits old income then exhausts")
	check(StrategicCampaign.from_checkpoint(content, model.checkpoint().data).ok,
		"final-turn built checkpoint valid")


func _initialize() -> void:
	routes()
	catalogue()
	print("CASTLE CAMPAIGN: %d failures" % failures)
	quit(0 if failures == 0 else 1)
