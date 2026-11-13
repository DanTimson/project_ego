extends SceneTree

const Authored = preload("res://content/campaign/province_campaign.gd")
const Policy = preload("res://core/campaign/strategic_policy.gd")
var suite := preload("res://tests/province_test_support.gd").new()


func equipment_and_casualties() -> void:
	var c := Authored.definition()
	c.factions.azure.gold = 40
	c.factions.azure.crystals = 10
	var hero_type: String = c.heroes.warden.faction_defs.azure
	c.definitions[hero_type].life = 1
	c.definitions[hero_type].attack = 1
	c.definitions["campaign:unit/8"]["counter_attack"] = 20
	var m := ContestedCampaign.create(c)
	suite.issue(m, {"op": "hire", "id": "warden", "province": "home"})
	suite.issue(m, {"op": "assign", "hero": "azure:warden", "army": "azure-first"})
	suite.issue(
		m, {"op": "order", "army": "azure-first", "units": ["azure:warden", "azure-vanguard"]}
	)
	suite.refused(m, {"op": "order", "army": "azure-first", "units": [1, "azure:warden"]})
	suite.issue(m, {"op": "travel", "army": "azure-first", "to": "quarry"})
	suite.decide(m, "fight")
	var encounter := m.pending_encounter()
	encounter.session.begin()
	var attack := {
		"op": "attack",
		"unit": encounter.session.scenario.spec.name + ":azure:warden",
		"target": encounter.session.scenario.spec.name + ":neutral-guard"
	}
	suite.check(
		encounter.session.issue_command(attack).accepted, "ordinary hero melee with retaliation"
	)
	suite.fight(m)
	suite.check(
		(
			m.snapshot().casualties.has("azure:warden")
			and m.snapshot().armies.has("azure-first")
			and m.members("azure-first") == ["azure-vanguard"]
		),
		"hero dies once; surviving troop continues as unled army"
	)
	suite.refused(m, {"op": "assign", "hero": "azure:warden", "army": "azure-first"})
	suite.end_round(m)
	suite.refused(m, {"op": "hire", "id": "warden", "province": "home"})
	var loaded := ContestedCampaign.from_checkpoint(c, m.checkpoint().data)
	suite.check(
		loaded.ok and loaded.campaign.snapshot() == m.snapshot(),
		"linked hero casualty verified by replay"
	)
	# Equipment keeps a unique owner; neither free operation changes current wounds.
	c = Authored.definition()
	c.factions.azure.gold = 40
	c.factions.azure.crystals = 10
	m = ContestedCampaign.create(c)
	suite.issue(m, {"op": "hire", "id": "warden", "province": "home"})
	suite.issue(m, {"op": "assign", "hero": "azure:warden", "army": "azure-first"})
	suite.issue(
		m, {"op": "order", "army": "azure-first", "units": ["azure:warden", "azure-vanguard"]}
	)
	suite.end_round(m)
	suite.issue(m, {"op": "buy", "id": "steel", "hero": "azure:warden", "province": "home"})
	suite.issue(m, {"op": "equip", "hero": "azure:warden", "item": "azure:warden:steel"})
	suite.refused(m, {"op": "equip", "hero": "azure:warden", "item": "azure:warden:steel"})
	suite.refused(m, {"op": "unequip", "hero": "azure:warden", "slot": "body"})
	suite.end_round(m)
	suite.refused(m, {"op": "buy", "id": "steel", "hero": "azure:warden", "province": "home"})
	suite.issue(m, {"op": "hire", "id": "ranger", "province": "home"})
	suite.refused(m, {"op": "assign", "hero": "azure:ranger", "army": "azure-first"})
	suite.refused(m, {"op": "equip", "hero": "azure:ranger", "item": "azure:warden:steel"})
	suite.issue(m, {"op": "travel", "army": "azure-first", "to": "quarry"})
	suite.decide(m, "fight")
	suite.fight(m)
	var life: int = m.snapshot().units["azure:warden"].life
	suite.issue(m, {"op": "unequip", "hero": "azure:warden", "slot": "hand"})
	suite.issue(m, {"op": "equip", "hero": "azure:warden", "item": "azure:warden:steel"})
	suite.check(
		m.snapshot().units["azure:warden"].life == life, "equip and unequip preserve wounds"
	)
	suite.check(
		m.hero_stats("azure:warden").effective.attack == 23,
		"level and equipment numeric composition"
	)
	var store := CampaignCheckpointStore.new("user://cx034-roundtrip-test.json")
	suite.check(store.save_campaign(m).ok, "atomic on-disk v4 write")
	suite.check(store.load_campaign(c, true).ok, "on-disk v4 reconstruction")
	var saved: Dictionary = m.checkpoint().data
	for modification in [
		"equipment", "leader", "site", "life", "discovery", "outcome", "currency", "transcript"
	]:
		var bad := saved.duplicate(true)
		match modification:
			"equipment":
				bad.state.heroes["azure:ranger"].slots["hand"] = "azure:warden:steel"
			"leader":
				bad.state.units["azure:ranger"].army = "azure-first"
			"site":
				bad.state.provinces.home.site.guards[0].def = "unknown"
			"life":
				bad.state.units["azure:warden"].life = 999
			"discovery":
				bad.state.knowledge.crimson.home.resource = true
			"outcome":
				bad.state.outcomes.append({"attempt": 1, "decision": "win"})
			"currency":
				bad.state.factions.azure.crystals += 1
			"transcript":
				for event in bad.journal:
					if event.op == "finish":
						event.commands.clear()
		suite.check(
			not ContestedCampaign.from_checkpoint(c, bad).ok, "reject inconsistent " + modification
		)
	# Failed resume does not replace a live scene model or overwrite the good slot.
	suite.check(
		(
			store.load_campaign(Authored.definition(true), true).ok == false
			and store.load_campaign(c, true).ok
		),
		"cross-content disk load preserves checkpoint"
	)
	DirAccess.remove_absolute(store.path)


func recapture_clock() -> void:
	var c := Authored.definition()
	c.armies.erase("crimson-second")
	c.units = c.units.filter(func(u: Dictionary) -> bool: return u.id != "crimson-patrol")
	c.armies["azure-first"].province = "ford"
	c.units[0].province = "ford"
	c.provinces.ford.owner = "azure"
	c.factions.azure.gold = 40
	c.factions.azure.crystals = 10
	c.province_rules.policy = {"explore": 0, "site": 0, "travel": 100, "service": 0}
	var m := ContestedCampaign.create(c)
	suite.issue(m, {"op": "build", "id": "farm", "province": "ford"})
	suite.issue(m, {"op": "explore", "army": "azure-first"})
	suite.issue(m, {"op": "end_turn"})
	suite.check(m.concede().ok, "resource province lost after discovery")
	var capture_payout := 0
	for entry in m.snapshot().money_log:
		if entry.faction == "crimson" and entry.round == 1 and entry.sign == 1:
			capture_payout += entry.amounts.gold
	suite.check(
		capture_payout == 21,
		"new owner gets no undiscovered seam and no construction-round farm yield"
	)

	# At round two the previous-round farm follows current control; resource does not.
	suite.check(
		m.yields("ford", true).gold == 5 and m.yields("ford", true).crystals == 0,
		"facility ownership follows control at integer-scaled payout"
	)
	suite.issue(m, {"op": "form", "province": "home", "units": ["azure-guard"]})
	suite.issue(m, {"op": "end_turn"})
	if m.in_battle():
		suite.fight(m)
	var army := m.field_at("home")
	suite.issue(m, {"op": "travel", "army": army, "to": "ford"})
	if not m.encounter_choice().is_empty():
		suite.decide(m, "fight")
	if m.in_battle():
		suite.fight(m)
	var s := m.snapshot()
	suite.check(
		s.provinces.ford.owner == "azure" and s.provinces.ford.stability == 50,
		"recapture lowers surviving stability instead of resetting it"
	)
	suite.check(
		s.knowledge.azure.ford.resource and m.yields("ford").gold == 6,
		"returning owner's remembered discovery contributes once under recovery scale"
	)
	var round_before: int = s.round
	suite.end_round(m)
	suite.check(
		m.snapshot().provinces.ford.stability == 50, "recapture round grants no free recovery"
	)
	suite.end_round(m)
	suite.check(
		m.snapshot().provinces.ford.stability == 60 and m.snapshot().round == round_before + 2,
		"one full owned round advances recovery across integer threshold"
	)
	suite.check(
		ContestedCampaign.from_checkpoint(c, m.checkpoint().data).ok,
		"capture/loss/recovery clocks resume"
	)


func oversized_save_preserves_slot() -> void:
	var c := Authored.definition()
	var model = ContestedCampaign.create(c)
	var store := CampaignCheckpointStore.new("user://cx034-budget-%d.json" % Time.get_ticks_usec())
	suite.check(store.save_campaign(model).ok, "write baseline province checkpoint")
	var original := FileAccess.get_file_as_string(store.path)
	var commands: Array = []
	commands.resize(2049)
	commands.fill({"op": "end_phase"})
	# Inject an over-bound completed transcript without playing thousands of turns.
	model._journal.append({"op": "finish", "commands": commands})
	var result := store.save_campaign(model)
	suite.check(
		not result.ok
		and result.reason.contains("transcript")
		and FileAccess.get_file_as_string(store.path) == original
		and store.load_campaign(c, true).ok,
		"oversized checkpoint refuses before replacing the previous readable slot"
	)
	DirAccess.remove_absolute(store.path)


func _initialize() -> void:
	equipment_and_casualties()
	recapture_clock()
	oversized_save_preserves_slot()
	print("PROVINCE CHECKPOINT: %d failures" % suite.failures)
	quit(0 if suite.failures == 0 else 1)
