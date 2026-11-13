extends SceneTree

const Authored = preload("res://content/campaign/province_campaign.gd")
const Policy = preload("res://core/campaign/strategic_policy.gd")
var suite := preload("res://tests/province_test_support.gd").new()


func route() -> void:
	var c := Authored.definition()
	var m := ContestedCampaign.create(c)
	suite.check(m != null, "opt-in province model")
	if m == null:
		return
	var view: Dictionary = m.faction_view("azure")
	suite.check(
		(
			view.provinces.watchpost.knowledge == "unknown"
			and not view.provinces.watchpost.has("terrain")
			and view.provinces.ford.knowledge == "frontier"
		),
		"unknown frontier has no hidden fields"
	)
	suite.issue(m, {"op": "travel", "army": "azure-first", "to": "ford"})
	suite.check(
		m.faction_view("azure").provinces.watchpost.knowledge == "frontier",
		"movement discovers next frontier"
	)
	suite.end_round(m)
	suite.issue(m, {"op": "explore", "army": "azure-first"})
	var k: Dictionary = m.snapshot().knowledge.azure.ford
	suite.check(
		k.progress == 50 and k.resource and k.site, "50% threshold discovers resource and ruin"
	)
	suite.refused(m, {"op": "travel", "army": "azure-first", "to": "home"})
	suite.end_round(m)
	suite.issue(m, {"op": "site", "army": "azure-first"})
	var before := m.snapshot()
	suite.decide(m, "withdraw")
	suite.check(
		(
			m.snapshot().armies == before.armies
			and m.snapshot().units == before.units
			and m.snapshot().provinces == before.provinces
		),
		"withdraw preserves map and movement"
	)
	suite.issue(m, {"op": "site", "army": "azure-first"})
	suite.decide(m, "fight")
	suite.check(not m.checkpoint().ok, "site battle blocks save")
	var stale := suite.fight(m)
	suite.check(
		(
			m.snapshot().provinces.ford.site.status == "cleared"
			and m.snapshot().provinces.ford.owner == "azure"
		),
		"site clear pays without changing control"
	)
	before = m.snapshot()
	suite.check(
		not m.finish(stale).ok and before == m.snapshot(), "duplicate result refuses atomically"
	)
	suite.issue(m, {"op": "build", "id": "farm", "province": "ford"})
	suite.end_round(m)
	suite.issue(m, {"op": "hire", "id": "warden", "province": "ford"})
	suite.issue(m, {"op": "assign", "hero": "azure:warden", "army": "azure-first"})
	suite.issue(
		m, {"op": "order", "army": "azure-first", "units": ["azure:warden", "azure-vanguard"]}
	)
	suite.end_round(m)
	suite.issue(m, {"op": "buy", "id": "steel", "hero": "azure:warden", "province": "ford"})
	suite.issue(m, {"op": "equip", "hero": "azure:warden", "item": "azure:warden:steel"})
	suite.check(
		m.hero_stats("azure:warden").effective.attack == 23, "equipment composes tactical attack"
	)
	var exported := m.checkpoint()
	var loaded := ContestedCampaign.from_checkpoint(
		c, JSON.parse_string(JSON.stringify(exported.data))
	)
	suite.check(loaded.ok, "integrated checkpoint reconstructs every state value")
	if not loaded.ok:
		print(loaded)
	else:
		suite.end_round(m)
		suite.end_round(loaded.campaign)
		suite.check(
			m.snapshot() == loaded.campaign.snapshot(),
			"resume next payout and rival choices identical"
		)
	suite.issue(m, {"op": "build", "id": "outpost", "province": "ford"})
	suite.end_round(m)
	suite.issue(m, {"op": "recruit", "id": "campaign:unit/11", "province": "ford"})
	suite.check(m.members("", "ford").size() == 1, "local facility recruitment uses garrison")
	suite.issue(m, {"op": "travel", "army": "azure-first", "to": "home"})
	suite.end_round(m)
	suite.issue(m, {"op": "explore", "army": "azure-first"})
	suite.end_round(m)
	suite.issue(m, {"op": "site", "army": "azure-first"})
	suite.decide(m, "fight")
	var encounter := m.pending_encounter()
	var hero: Combatant = encounter.session.scenario.units.get(
		encounter.session.scenario.spec.name + ":azure:warden"
	)
	suite.check(
		hero != null and hero.attack == 23, "equipped leader deploys as linked tactical participant"
	)
	suite.check(
		encounter.session.unit_position(hero) == Vector2i(0, 0), "formation controls deployment"
	)
	suite.fight(m)
	suite.check(
		(
			m.hero_stats("azure:warden").progress.level == 3
			and m.hero_stats("azure:warden").effective.attack == 26
		),
		"real victory earns level and stat change"
	)
	print(
		"INTEGRATED ROUTE round=",
		m.snapshot().round,
		" ledger=",
		m.snapshot().factions.azure,
		" hero=",
		m.hero_stats("azure:warden")
	)
	suite.check(
		ContestedCampaign.from_checkpoint(c, m.checkpoint().data).ok,
		"level/formation/outcomes round trip"
	)
	suite.end_round(m)
	suite.issue(m, {"op": "travel", "army": "azure-first", "to": "ford"})
	suite.end_round(m)
	suite.issue(m, {"op": "travel", "army": "azure-first", "to": "watchpost"})
	if not m.encounter_choice().is_empty():
		suite.decide(m, "fight")
	if m.in_battle():
		suite.fight(m)
	suite.end_round(m)
	suite.issue(m, {"op": "travel", "army": "azure-first", "to": "keep"})
	suite.decide(m, "fight")
	var final_encounter := m.pending_encounter()
	var veteran: Combatant = final_encounter.session.scenario.units.get(
		final_encounter.session.scenario.spec.name + ":azure:warden"
	)
	suite.check(veteran != null and veteran.attack == 26, "earned level affects next real battle")
	suite.fight(m)
	suite.check(
		m.snapshot().status == "victory", "integrated route reaches actual campaign objective"
	)
	print(
		"PROVINCE VICTORY round=",
		m.snapshot().round,
		" gold=",
		m.snapshot().factions.azure.gold,
		" crystals=",
		m.snapshot().factions.azure.crystals
	)
	suite.check(
		ContestedCampaign.from_checkpoint(c, m.checkpoint().data).ok, "v4 terminal victory resume"
	)


func _initialize() -> void:
	route()
	print("PROVINCE CAMPAIGN: %d failures" % suite.failures)
	quit(0 if suite.failures == 0 else 1)
