extends SceneTree

const Authored = preload("res://content/campaign/contested_campaign.gd")
const Policy = preload("res://core/campaign/strategic_policy.gd")
var failures := 0


func check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func play(model: ContestedCampaign) -> void:
	for battle in 12:
		if not model.in_battle():
			return
		var e := model.pending_encounter()
		e.session.begin()
		for index in 256:
			if e.session.battle_complete():
				break
			check(e.session.issue_command(Policy.tactical_command(e.session)).accepted,
				"ordinary tactical command")
		check(model.finish(e).ok, "ordinary tactical result")


func services() -> void:
	var c := Authored.definition()
	c.factions.azure.gold = 200
	c.policy.hold = 1000
	var model := ContestedCampaign.create(c)
	for id in c.buildings:
		var s := model.snapshot()
		var round_number: int = s.round
		check(model.execute({"op": "build", "id": id}).ok, "contested build " + id)
		check(model.snapshot().factions.azure.gold == s.factions.azure.gold - c.buildings[id].cost,
			"construction pays price before income")
		check(not model.execute({"op": "recruit", "id": c.recruit_def}).ok
			and not model.execute({"op": "build", "id": id}).ok, "one service and no duplicate facility")
		var payout := model.province_income("home", true)
		var gold: int = model.snapshot().factions.azure.gold
		model.execute({"op": "end_turn"})
		play(model)
		check(model.snapshot().round == round_number + 1
			and model.snapshot().factions.azure.gold == gold + payout, "payout once using prior facilities")
		check(ContestedCampaign.from_checkpoint(c, model.checkpoint().data).ok,
			"service ledger and prerequisites round trip " + id)
	check(model.province_income("home") == 7, "Market/Workshop effective income")
	var recruit_id := "recruited-%d" % model.snapshot().next_unit
	check(model.execute({"op": "recruit", "id": "campaign:unit/6"}).ok,
		"unlocked selected Veteran recruitment")
	check(model.snapshot().units[recruit_id].life == 24
		and model.snapshot().units[recruit_id].army == "", "recruit definition and Home garrison")
	check(not model.execute({"op": "transfer", "unit": "azure-vanguard", "army": ""}).ok,
		"garrison capacity guard")
	# Obtain wounds through combat, then use the ordinary targeted Home recovery service.
	model = ContestedCampaign.create(Authored.definition())
	model.execute({"op": "travel", "army": "azure-first", "to": "ford"})
	model.execute({"op": "end_turn"})
	play(model)
	model.execute({"op": "travel", "army": "azure-first", "to": "home"})
	var life: int = model.snapshot().units["azure-vanguard"].life
	var gold: int = model.snapshot().factions.azure.gold
	check(not model.execute({"op": "recover", "units": ["crimson-raider"]}).ok,
		"casualties cannot recover")
	check(model.execute({"op": "recover", "units": ["azure-vanguard"]}).ok
		and model.snapshot().units["azure-vanguard"].life == mini(20, life + 6)
		and model.snapshot().factions.azure.gold == gold - 8,
		"targeted recovery at Home heals only eligible co-located troops and spends no round")


func combined_defense() -> void:
	var c := Authored.definition()
	c.provinces.ford.owner = "azure"
	c.armies["azure-first"].province = "ford"
	c.units[0].province = "ford"
	for index in 3:
		var unit: Dictionary = c.units[2].duplicate()
		unit.id = "extra-defender-%d" % index
		if index > 0:
			unit.army = ""
		c.units.append(unit)
	var model := ContestedCampaign.create(c)
	check(model != null, "maximum legal combined army and garrison accepted")
	var e: CampaignEncounter = model.execute({"op": "travel", "army": "azure-first",
		"to": "watchpost"}).encounter
	check(e._opponent_mapping.size() == 4, "complete combined defense deployment")
	for id in e._opponent_mapping:
		var tactical: Combatant = e.session.scenario.units[e._opponent_mapping[id].instance_id]
		check(tactical.content_id == "campaign:unit/7" and tactical.life == 8
			and tactical.attack == 3, "defender actual definition, life and identity " + id)
	model.abandon(e)
	check(model.snapshot().armies["crimson-first"].province == "watchpost"
		and model.members("", "watchpost").size() == 2, "abandon preserves both defending containers")


func rival_policy() -> void:
	var model := ContestedCampaign.create(Authored.definition())
	model.execute({"op": "travel", "army": "azure-first", "to": "ford"})
	model.execute({"op": "end_turn"})
	var before := model.snapshot()
	var e := model.pending_encounter()
	var calls: Dictionary = e.session.scenario.rng.calls.duplicate(true)
	var a := Policy.choose(model, "crimson")
	var b := Policy.choose(model, "crimson")
	check(a == b and model.snapshot() == before and calls == e.session.scenario.rng.calls,
		"policy queries consume neither strategic state nor tactical RNG")
	play(model)
	# One-command bound permits at most one rival move, including suspended/resumed attacks.
	var c := Authored.definition()
	c.policy.commands = 1
	model = ContestedCampaign.create(c)
	model.execute({"op": "travel", "army": "azure-first", "to": "ford"})
	model.execute({"op": "end_turn"})
	play(model)
	check(model.snapshot().armies["crimson-second"].province == "mill"
		and model.snapshot().round == 2, "rival command bound survives interactive suspension")
	# A third faction uses ordinary NPC/NPC tactical commands without involving Azure.
	c = Authored.definition()
	c.factions["ochre"] = {"name": "Ochre", "home": "ford", "gold": 0}
	c.provinces.ford.owner = "ochre"
	var unit: Dictionary = c.units[1].duplicate()
	unit.id = "ochre-guard"
	unit.faction = "ochre"
	unit.province = "ford"
	unit.def = "campaign:unit/7"
	c.units.append(unit)
	model = ContestedCampaign.create(c)
	check(model != null, "three authored factions validate")
	model.execute({"op": "end_turn"})
	play(model)
	check(model.snapshot().round == 2 and model.snapshot().completed == 1,
		"NPC contest and remaining faction phases finish exactly once")
	# Capital loss ends run even though a distant Azure army remains alive.
	c = Authored.definition()
	c.provinces.ford.owner = "crimson"
	c.armies["crimson-first"].province = "ford"
	c.units[2].province = "ford"
	model = ContestedCampaign.create(c)
	model.execute({"op": "travel", "army": "azure-first", "to": "quarry"})
	model.execute({"op": "end_turn"})
	check(model.contest().to == "home" and model.concede().ok,
		"capital defense can explicitly concede")
	check(model.snapshot().status == "defeat" and model.snapshot().armies.has("azure-first")
		and model.snapshot().provinces.home.owner == "crimson", "capital loss ends surviving-army run")
	check(ContestedCampaign.from_checkpoint(c, model.checkpoint().data).ok,
		"capital-loss terminal checkpoint")


func _initialize() -> void:
	services()
	combined_defense()
	rival_policy()
	print("CONTESTED RULES: %d failures" % failures)
	quit(0 if failures == 0 else 1)
