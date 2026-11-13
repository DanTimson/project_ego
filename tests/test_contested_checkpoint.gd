extends SceneTree

const Authored = preload("res://content/campaign/contested_campaign.gd")
const Native = preload("res://content/campaign/native_campaign.gd")
const Validation = preload("res://core/campaign/contested_validation.gd")
const Policy = preload("res://core/campaign/strategic_policy.gd")
var failures := 0

class FailedStore extends CampaignCheckpointStore:
	func _publish(_temporary: String) -> Error:
		return ERR_CANT_CREATE


func check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func fight(model: ContestedCampaign) -> void:
	while model.in_battle():
		var encounter := model.pending_encounter()
		encounter.session.begin()
		for step in 256:
			if encounter.session.battle_complete():
				break
			check(encounter.session.issue_command(Policy.tactical_command(encounter.session)).accepted,
				"real battle command")
		check(model.finish(encounter).ok, "collect both rosters")


func checkpoint_cases() -> void:
	var c := Authored.definition()
	var model := ContestedCampaign.create(c)
	model.execute({"op": "build", "id": "market"})
	model.execute({"op": "travel", "army": "azure-first", "to": "ford"})
	model.execute({"op": "end_turn"})
	fight(model)
	model.execute({"op": "recruit", "id": c.recruit_def})
	model.execute({"op": "form", "province": "home", "units": ["recruited-1"]})
	var data: Dictionary = model.checkpoint().data
	var baseline := model.snapshot()
	var roundtrip := ContestedCampaign.from_checkpoint(c, JSON.parse_string(JSON.stringify(data)))
	check(roundtrip.ok and roundtrip.campaign.snapshot() == baseline,
		"JSON version 3 round trip buildings, armies, wounds, casualties and spent budgets")
	for mutation in ["version", "mode", "content", "fingerprint", "phase", "round", "completed",
		"counter", "duplicate", "missing", "owner", "troop_owner", "life", "casualty", "position",
		"budget", "formation", "spent", "empty", "capacity", "gold", "service", "unlock",
		"extra", "fraction"]:
		var bad := data.duplicate(true)
		match mutation:
			"version": bad.version = 2
			"mode": bad.mode = "native"
			"content": bad.content = "other"
			"fingerprint": bad.fingerprint = "forged"
			"phase": bad.state.phase = "rival"
			"round": bad.state.round = 4
			"completed": bad.state.completed = 9
			"counter": bad.state.next_unit = 3
			"duplicate": bad.state.casualties["azure-vanguard"] = bad.state.units["azure-vanguard"]
			"missing": bad.state.units.erase("azure-vanguard")
			"owner": bad.state.provinces.home.owner = "missing"
			"troop_owner": bad.state.units["azure-vanguard"].faction = "crimson"
			"life": bad.state.units["azure-vanguard"].life = 21
			"casualty": bad.state.casualties["crimson-raider"].army = "azure-first"
			"position": bad.state.armies["azure-first"].province = "keep"
			"budget": bad.state.armies["formed-2"].moves = 2
			"formation": bad.state.armies["formed-2"].moves = 1
			"spent":
				bad.state.units["azure-vanguard"].moved = true
				bad.state.armies["azure-first"].moves = 1
			"empty": bad.state.units["recruited-1"].army = ""
			"capacity":
				bad.state.units["recruited-1"].army = ""
				bad.state.units["azure-vanguard"].army = ""
				bad.state.units["azure-vanguard"].province = "home"
			"gold": bad.state.factions.azure.gold = 10000
			"service": bad.state.factions.azure.service = 0
			"unlock": bad.state.units["recruited-1"].def = "campaign:unit/6"
			"extra": bad.state.units["azure-vanguard"]["display_name"] = "forged identity"
			"fraction": bad.state.factions.azure.gold = 0.5
		check(not ContestedCampaign.from_checkpoint(c, bad).ok and model.snapshot() == baseline,
			"atomic malformed checkpoint refusal " + mutation)
	var directory := "user://cx033-checkpoints-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	var store := CampaignCheckpointStore.new(directory.path_join("contested.json"))
	check(store.save_campaign(model).ok and store.load_campaign(c, true).ok,
		"distinct contested slot uses atomic store")
	var previous := FileAccess.get_file_as_string(store.path)
	var failed := FailedStore.new(store.path)
	model.execute({"op": "travel", "army": "azure-first", "to": "watchpost"})
	check(not failed.save_campaign(model).ok and FileAccess.get_file_as_string(store.path) == previous,
		"failed contested publication preserves prior slot")
	var resumed: ContestedCampaign = roundtrip.campaign
	resumed.execute({"op": "travel", "army": "azure-first", "to": "watchpost"})
	check(model.snapshot() == resumed.snapshot(), "next player move deterministic after resume")
	model.execute({"op": "end_turn"})
	resumed.execute({"op": "end_turn"})
	check(not store.save_campaign(model).ok
		and FileAccess.get_file_as_string(store.path) == previous, "pending rival save preserves slot")
	fight(model)
	fight(resumed)
	check(model.snapshot() == resumed.snapshot(),
		"full next rival transition deterministic after resume")
	check(not store.load_campaign(Native.definition()).ok
		and not ContestedCampaign.from_checkpoint(Native.definition(), data).ok,
		"native and contested modes cannot cross-load")
	DirAccess.remove_absolute(store.path)
	DirAccess.remove_absolute(directory)


func authored_validation() -> void:
	for mutation in ["home", "objective", "owner", "link", "duplicate_link", "disconnected",
		"army", "empty", "unit", "duplicate", "faction", "cap", "deployment", "army_budget",
		"definition", "prerequisite", "policy", "occupied", "garrison", "moves"]:
		var bad := Authored.definition()
		match mutation:
			"home": bad.factions.azure.home = "missing"
			"objective": bad.objective = "missing"
			"owner": bad.provinces.ford.owner = "missing"
			"link": bad.provinces.home.links = ["keep"]
			"duplicate_link": bad.provinces.home.links.append("ford")
			"disconnected":
				bad.provinces.home.links = []
				bad.provinces.ford.links.erase("home")
				bad.provinces.quarry.links.erase("home")
			"army": bad.armies["azure-first"].province = "keep"
			"empty": bad.units.remove_at(0)
			"unit": bad.units[0].army = "missing"
			"duplicate": bad.units.append(bad.units[0].duplicate())
			"faction": bad.units[0].faction = "crimson"
			"cap": bad.army_cap = 3
			"deployment": bad.deployment[1][0] = bad.deployment[0][0]
			"army_budget": bad.armies["azure-first"].moves = 2
			"definition": bad.definitions["campaign:unit/1"].life = -1
			"prerequisite": bad.buildings.market.requires = ["workshop"]
			"policy": bad.policy.commands = 100000
			"occupied":
				bad.armies["extra"] = bad.armies["azure-first"].duplicate()
			"garrison":
				for index in 3:
					var u: Dictionary = bad.units[1].duplicate()
					u.id = "excess-%d" % index
					bad.units.append(u)
			"moves": bad.armies["azure-first"] = "wrong type"
		check(ContestedCampaign.create(bad) == null, "authored validation " + mutation)


func abandon_and_collection() -> void:
	var c := Authored.definition()
	c.provinces.ford.owner = "azure"
	c.armies["azure-first"].province = "ford"
	c.units[0].province = "ford"
	var model := ContestedCampaign.create(c)
	var before := model.snapshot()
	var attempt: CampaignEncounter = model.execute(
		{"op": "travel", "army": "azure-first", "to": "watchpost"}).encounter
	var opened := model.snapshot()
	check(not model.finish(attempt).ok and model.snapshot() == opened,
		"unfinished result atomic refusal")
	check(not model.execute({"op": "transfer", "unit": "azure-vanguard", "army": ""}).ok,
		"no transfers through pending battle")
	check(model.abandon(attempt).ok, "player attack may be abandoned")
	var after := model.snapshot()
	after.serial = before.serial
	after.trace = before.trace
	check(after == before, "abandon preserves all gameplay values")
	var retry: CampaignEncounter = model.execute(
		{"op": "travel", "army": "azure-first", "to": "watchpost"}).encounter
	check(retry._mapping != attempt._mapping and not model.finish(attempt).ok,
		"fresh attempt identity and stale guard")
	retry.session.begin()
	retry.session.scenario.runtime_error = "test halt"
	check(not model.finish(retry).ok, "halted result refuses without committing")
	retry.session.scenario.runtime_error = ""
	model.abandon(retry)
	# A real attacking loss preserves the defending army's wounds and position.
	c.definitions["campaign:unit/1"] = {"name": "Fragile Vanguard", "life": 2, "attack": 1}
	model = ContestedCampaign.create(c)
	model.execute({"op": "travel", "army": "azure-first", "to": "watchpost"})
	fight(model)
	check(model.snapshot().status == "active" and not model.snapshot().armies.has("azure-first")
		and model.snapshot().provinces.watchpost.owner == "crimson"
		and model.snapshot().units["crimson-raider"].life < 8
		and model.snapshot().armies["crimson-first"].province == "watchpost",
		"real attack loss: persistent defending army survives at original province")


func _initialize() -> void:
	authored_validation()
	abandon_and_collection()
	checkpoint_cases()
	print("CONTESTED CHECKPOINT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
