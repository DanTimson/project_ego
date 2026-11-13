extends SceneTree

const Authored = preload("res://content/campaign/province_campaign.gd")
const Policy = preload("res://core/campaign/strategic_policy.gd")
const Validate = preload("res://core/campaign/province_validation.gd")
var suite := preload("res://tests/province_test_support.gd").new()


func knowledge_and_budgets() -> void:
	var c := Authored.definition(true)
	c.province_rules.explore = 25
	var m := ContestedCampaign.create(c)
	suite.check(m != null, "same model on independently authored coast graph")
	suite.issue(m, {"op": "explore", "army": "coast-company"})
	suite.check(
		(
			not m.snapshot().knowledge.azure.haven.resource
			and m.snapshot().knowledge.azure.haven.progress == 25
		),
		"below discovery threshold"
	)
	suite.issue(m, {"op": "transfer", "unit": "coast-vanguard", "army": ""})
	suite.issue(m, {"op": "form", "province": "haven", "units": ["coast-vanguard"]})
	suite.refused(m, {"op": "explore", "army": "formed-1"})
	suite.refused(m, {"op": "travel", "army": "formed-1", "to": "salt"})
	suite.end_round(m)
	suite.issue(m, {"op": "explore", "army": "formed-1"})
	suite.check(
		(
			m.snapshot().knowledge.azure.haven.resource
			and not m.snapshot().knowledge.crimson.haven.resource
		),
		"threshold and faction separation"
	)
	suite.end_round(m)
	suite.issue(m, {"op": "explore", "army": "formed-1"})
	suite.end_round(m)
	suite.issue(m, {"op": "explore", "army": "formed-1"})
	suite.check(m.snapshot().knowledge.azure.haven.progress == 100, "bounded exploration")
	suite.end_round(m)
	suite.refused(m, {"op": "explore", "army": "formed-1"})
	suite.check(m.snapshot().armies["formed-1"].moves == 1, "completed explore spends nothing")
	var bonus: Dictionary = m.yields("haven")
	suite.check(
		bonus.gold == 5 and bonus.crystals == 2, "discovery counted once after repeated exploration"
	)
	var hidden := c.duplicate(true)
	hidden.provinces.haven.income = 999
	hidden.provinces.haven.resource.gold = 600
	var other := ContestedCampaign.create(hidden)
	# Both have the same Crimson opening information despite different unknown Azure economy.
	var opening := ContestedCampaign.create(c)
	suite.check(
		opening.faction_view("crimson") == other.faction_view("crimson"),
		"faction projection independent of hidden income"
	)
	# Policy is evaluated in the same active rival phase via the production End Turn path.
	suite.end_round(opening)
	suite.end_round(other)
	suite.check(
		(
			opening.snapshot().knowledge.crimson == other.snapshot().knowledge.crimson
			and opening.snapshot().armies == other.snapshot().armies
		),
		"rival decisions cannot inspect unknown economic values"
	)
	suite.check(
		opening.snapshot().knowledge.crimson.tower.progress == 25,
		"rival Explore uses the production command path"
	)


func negotiations() -> void:
	var c := Authored.definition()
	var m := ContestedCampaign.create(c)
	suite.issue(m, {"op": "travel", "army": "azure-first", "to": "quarry"})
	var d: Dictionary = m.encounter_choice()
	suite.check(
		d.kind == "travel" and d.negotiate and not d.known.has("terrain"),
		"defended frontier has exact authored tribute, hidden opposition"
	)
	suite.refused(m, {"op": "decide", "choice": "negotiate", "token": d.token})
	suite.check(
		m.snapshot().armies["azure-first"].province == "home", "unaffordable crystals leave origin"
	)
	suite.decide(m, "withdraw")
	suite.end_round(m)
	var before := m.snapshot()
	suite.issue(m, {"op": "travel", "army": "azure-first", "to": "quarry"})
	d = m.encounter_choice()
	suite.refused(m, {"op": "decide", "choice": "negotiate", "token": "stale"})
	suite.decide(m, "negotiate")
	var s := m.snapshot()
	suite.check(
		(
			s.provinces.quarry.owner == "azure"
			and s.armies["azure-first"].moves == 0
			and s.factions.azure.gold == before.factions.azure.gold - 5
			and s.factions.azure.crystals == before.factions.azure.crystals - 1
		),
		"neutral negotiation pays both currencies once and spends one move"
	)
	suite.refused(m, {"op": "decide", "choice": "negotiate", "token": d.token})
	suite.check(
		s.provinces.quarry.stability == 70 and m.yields("quarry").gold == 3,
		"negotiated conquest incurs authored stability and revenue scaling"
	)
	suite.end_round(m)
	suite.check(
		(
			m.snapshot().factions.azure.gold == s.factions.azure.gold + 6
			and m.snapshot().provinces.quarry.stability == 70
		),
		"next end-round pays conquered revenue; no capture-round recovery"
	)
	suite.issue(m, {"op": "explore", "army": "azure-first"})
	suite.end_round(m)
	suite.issue(m, {"op": "site", "army": "azure-first"})
	before = m.snapshot()
	suite.decide(m, "negotiate")
	suite.check(
		(
			m.snapshot().provinces.quarry.site.status == "negotiated"
			and m.snapshot().factions.azure.gold == before.factions.azure.gold - 3
		),
		"site access resolves without reward or battle"
	)
	suite.end_round(m)
	suite.refused(m, {"op": "site", "army": "azure-first"})
	suite.check(
		ContestedCampaign.from_checkpoint(c, m.checkpoint().data).ok,
		"terminal negotiation and neutral identities persist"
	)
	# Changed funds/control/position invalidate the entire quote, not just the button.
	for field in ["funds", "position", "owner"]:
		var fresh := ContestedCampaign.create(c)
		suite.issue(fresh, {"op": "travel", "army": "azure-first", "to": "quarry"})
		var quote: Dictionary = fresh.encounter_choice()
		match field:
			"funds":
				fresh._state.factions.azure.gold += 1
			"position":
				fresh._state.armies["azure-first"].province = "ford"
			"owner":
				fresh._state.provinces.quarry.owner = "crimson"
		suite.refused(fresh, {"op": "decide", "choice": "fight", "token": quote.token})
		suite.refused(fresh, {"op": "decide", "choice": "negotiate", "token": quote.token})


func guard_losses_and_abandon() -> void:
	var c := Authored.definition()
	c.definitions["campaign:unit/1"] = {"name": "Test company", "life": 20, "attack": 3}
	c.provinces.home.site.guards = ["campaign:unit/8", "campaign:unit/8"]
	c.province_rules.policy = {"explore": 1, "site": 0, "travel": 0, "service": 0}
	var m := ContestedCampaign.create(c)
	suite.issue(m, {"op": "explore", "army": "azure-first"})
	suite.end_round(m)
	suite.issue(m, {"op": "site", "army": "azure-first"})
	suite.decide(m, "fight")
	var encounter := m.pending_encounter()
	encounter.session.begin()
	var result := encounter.session.issue_command(Policy.tactical_command(encounter.session))
	suite.check(result.accepted, "unfinished site accepts ordinary tactical damage")
	var before := m.snapshot()
	suite.check(not m.finish(encounter).ok and m.snapshot() == before, "unfinished result atomic")
	suite.check(m.abandon(encounter).ok, "unfinished site abandon")
	suite.check(
		(
			m.snapshot().provinces == before.provinces
			and m.snapshot().units == before.units
			and m.snapshot().armies == before.armies
		),
		"abandon discards temporary damage and movement"
	)
	suite.issue(m, {"op": "site", "army": "azure-first"})
	suite.decide(m, "fight")
	suite.check(m.snapshot().serial > before.serial, "monotonic site attempt IDs")
	suite.fight(m)
	var site: Dictionary = m.snapshot().provinces.home.site
	print("GUARD LOSS ", site)
	suite.check(
		(
			site.status == "guarded"
			and site.guards.any(
				func(g: Dictionary) -> bool: return g.life < c.definitions[g.def].life
			)
		),
		"loss preserves dead/wounded site guards"
	)
	var loaded := ContestedCampaign.from_checkpoint(c, m.checkpoint().data)
	suite.check(
		loaded.ok and loaded.campaign.snapshot().provinces.home.site == site,
		"site loss and survivors resume"
	)
	if m.snapshot().armies.has("azure-first"):
		suite.check(m.snapshot().armies["azure-first"].moves == 0, "completed loss spends movement")


func captures_and_heroes() -> void:
	var c := Authored.definition()
	# A small front line with an unassigned hero at risk; all commands remain production commands.
	c.armies.erase("crimson-second")
	c.units = c.units.filter(func(u: Dictionary) -> bool: return u.id != "crimson-patrol")
	c.armies["azure-first"].province = "ford"
	c.units[0].province = "ford"
	c.provinces.ford.owner = "azure"
	c.factions.azure.crystals = 10
	c.factions.azure.gold = 40
	c.province_rules.policy = {"explore": 0, "site": 0, "travel": 100, "service": 0}
	var m := ContestedCampaign.create(c)
	suite.issue(m, {"op": "build", "id": "farm", "province": "ford"})
	suite.issue(m, {"op": "explore", "army": "azure-first"})
	suite.issue(m, {"op": "end_turn"})
	suite.check(m.in_battle(), "rival uses legal front-line attack")
	# Concession is an explicit real result, not a fabricated winner.
	suite.check(m.concede().ok, "lose province through real defensive concession")
	suite.check(
		(
			m.snapshot().provinces.ford.owner == "crimson"
			and m.snapshot().provinces.ford.buildings.has("farm")
			and not m.snapshot().knowledge.crimson.ford.resource
		),
		"facilities follow capture, resource discovery remains faction-specific"
	)
	suite.refused(m, {"op": "recruit", "id": c.recruit_def, "province": "ford"})
	suite.issue(m, {"op": "hire", "id": "warden", "province": "home"})
	suite.issue(m, {"op": "form", "province": "home", "units": ["azure-guard"]})
	suite.issue(m, {"op": "assign", "hero": "azure:warden", "army": m.field_at("home")})
	suite.refused(m, {"op": "hire", "id": "ranger", "province": "ford"})
	suite.issue(m, {"op": "end_turn"})
	# Crimson proceeds to Home; concession resolves the hero and troop once.
	if m.in_battle():
		suite.check(m.concede().ok, "hero-led army defensive loss")
	suite.check(
		m.snapshot().casualties.has("azure:warden") and not m.snapshot().units.has("azure:warden"),
		"dead leader cannot resurrect on transfer"
	)
	suite.check(
		ContestedCampaign.from_checkpoint(c, m.checkpoint().data).ok, "hero death round trip"
	)
	# Separate unassigned capture route: guard and leader deploy together within defense capacity.
	var unassigned := ContestedCampaign.create(c)
	suite.issue(unassigned, {"op": "hire", "id": "warden", "province": "ford"})
	suite.issue(unassigned, {"op": "end_turn"})
	suite.check(unassigned.in_battle(), "unassigned leader defends settlement")
	suite.check(
		unassigned.concede().ok and unassigned.snapshot().casualties.has("azure:warden"),
		"captured unassigned leader becomes permanent casualty"
	)


func malformed_and_atomic() -> void:
	var c := Authored.definition()
	var poor := c.duplicate(true)
	poor.factions.azure.gold = 0
	poor.factions.azure.crystals = 10
	var unfunded := ContestedCampaign.create(poor)
	suite.refused(unfunded, {"op": "hire", "id": "warden", "province": "home"})
	var m := ContestedCampaign.create(c)
	suite.refused(m, {"op": "hire", "id": "warden", "province": "home"})
	suite.refused(
		m, {"op": "order", "army": "azure-first", "units": ["azure-vanguard", "azure-vanguard"]}
	)
	suite.refused(m, {"op": "explore", "army": 3})
	suite.refused(m, {"op": "travel", "army": "azure-first", "to": "ford", "extra": 1})
	suite.end_round(m)
	var saved: Dictionary = m.checkpoint().data
	for field in [
		"knowledge", "provinces", "factions", "heroes", "inventory", "formation", "outcomes"
	]:
		var bad := saved.duplicate(true)
		bad.state[field] = {"forged": true}
		suite.check(not ContestedCampaign.from_checkpoint(c, bad).ok, "reject forged " + field)
	var bad := saved.duplicate(true)
	bad.state.provinces.home.stability = 100.5
	suite.check(not ContestedCampaign.from_checkpoint(c, bad).ok, "reject fractional values")
	bad = saved.duplicate(true)
	bad.journal.append({"op": "command", "command": {"op": "buy", "id": "unknown"}})
	suite.check(not ContestedCampaign.from_checkpoint(c, bad).ok, "reject illegal replay command")
	suite.check(
		not ContestedCampaign.from_checkpoint(Authored.definition(true), saved).ok,
		"cross-graph fingerprint refusal"
	)
	suite.check(
		not (
			ContestedCampaign
			. from_checkpoint(
				preload("res://content/campaign/contested_campaign.gd").definition(), saved
			)
			. ok
		),
		"v4 never cross-loads into CX-033"
	)
	suite.check(m.snapshot() == saved.state, "failed loads leave live state unchanged")
	for field in ["explore", "levels", "stability"]:
		bad = c.duplicate(true)
		bad.province_rules[field] = -1
		suite.check(ContestedCampaign.create(bad) == null, "invalid authored " + field)


func resource_only_and_site_only() -> void:
	for feature in ["resource", "site"]:
		var c := Authored.definition(true)
		c.provinces.haven[feature] = {}
		var model := ContestedCampaign.create(c)
		suite.check(model != null, "optional discovery: " + feature)
		if model == null:
			continue
		suite.issue(model, {"op": "explore", "army": "coast-company"})
		var knowledge: Dictionary = model.snapshot().knowledge.azure.haven
		suite.check(not knowledge[feature], "absent discovery never becomes known")
		suite.check(
			ContestedCampaign.from_checkpoint(c, model.checkpoint().data).ok,
			"partial discovery definition resumes"
		)


func rediscovery_after_capture() -> void:
	var c := Authored.definition()
	c.player = "crimson"
	c.objective = "home"
	c.provinces.ford.owner = "azure"
	c.armies["azure-first"].province = "ford"
	c.units[0].province = "ford"
	for u in c.units:
		if u.id == "crimson-raider":
			u.def = "campaign:unit/1"
	var model := ContestedCampaign.create(c)
	suite.end_round(model)
	suite.check(
		(
			model.snapshot().knowledge.azure.ford.resource
			and not model.snapshot().knowledge.crimson.ford.resource
		),
		"old owner discovers before capture through rival production commands"
	)
	suite.issue(model, {"op": "travel", "army": "crimson-first", "to": "ford"})
	suite.decide(model, "fight")
	suite.fight(model)
	suite.check(
		(
			model.snapshot().provinces.ford.owner == "crimson"
			and not model.snapshot().knowledge.crimson.ford.resource
			and model.yields("ford").gold == 3
		),
		"capture does not inherit another faction's resource discovery"
	)
	suite.end_round(model)
	suite.issue(model, {"op": "explore", "army": "crimson-first"})
	var before: Dictionary = model.snapshot().factions.crimson.duplicate(true)
	suite.check(
		model.snapshot().knowledge.crimson.ford.resource, "new owner rediscovers through Explore"
	)
	suite.end_round(model)
	suite.check(
		(
			model.snapshot().factions.crimson.gold == before.gold + 22
			and model.snapshot().factions.crimson.crystals == before.crystals + 1
		),
		"rediscovered yield pays once at next boundary with separate integer currency scaling"
	)
	suite.check(
		ContestedCampaign.from_checkpoint(c, model.checkpoint().data).ok,
		"two factions' discoveries and capture history resume"
	)


func _initialize() -> void:
	rediscovery_after_capture()
	resource_only_and_site_only()
	knowledge_and_budgets()
	negotiations()
	guard_losses_and_abandon()
	captures_and_heroes()
	malformed_and_atomic()
	print("PROVINCE RULES: %d failures" % suite.failures)
	quit(0 if suite.failures == 0 else 1)
