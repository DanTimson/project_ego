extends SceneTree

const RosterModel = preload("res://core/campaign/campaign_roster.gd")
const Encounter = preload("res://core/campaign/campaign_encounter.gd")
const ROSTER_ID := "azure-vanguard"
const BASE_LIFE := 20
var failures: int = 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func open_encounter(source: Dictionary, encounter_id: String, seed_value: int,
		roster_id: String = ROSTER_ID) -> Dictionary:
	return Encounter.open(source, encounter_id, seed_value,
		{roster_id: {"instance_id": encounter_id + ":vanguard", "at": [0, 0]}},
		{"width": 3, "height": 2},
		[{"id": "guard", "name": "Guard", "at": [1, 0], "life": 8,
			"stamina": 10, "morale": 10, "counter_attack": 5,
			"flags": ["Первый удар"]}])


func refusal(roster: RefCounted, outcome: Dictionary, message: String) -> void:
	var before: Dictionary = roster.snapshot()
	check(not roster.apply(outcome).ok, message)
	check(roster.snapshot() == before, message + ": entire state unchanged")


func _initialize() -> void:
	var definition := {"name": "Vanguard", "life": BASE_LIFE,
		"stamina": 10, "morale": 10, "attack": 30}
	var entries := [
		{"id": ROSTER_ID, "def": "campaign:unit/1", "definition": definition,
			"life": BASE_LIFE},
		{"id": "casualty", "def": "campaign:unit/1", "definition": definition,
			"life": 1}]
	var created: Dictionary = RosterModel.create(entries, "native-cx026-v1")
	check(created.ok, "create roster")
	if not created.ok:
		quit(1)
		return
	var roster: RefCounted = created.roster
	var initial: Dictionary = roster.snapshot()
	var frozen := initial.duplicate(true)
	check(not Encounter.open(initial, "duplicate-map", 1, {
		ROSTER_ID: {"instance_id": "same", "at": [0, 0]},
		"casualty": {"instance_id": "same", "at": [0, 1]}},
		{"width": 3, "height": 2}, []).ok, "duplicate deployment instance refuses")
	check(not open_encounter(initial, "unknown-map", 1, "unknown").ok,
		"unknown deployment roster ID refuses")
	var wrong_source := initial.duplicate(true)
	wrong_source.pins.content.fingerprint = "sha256:wrong"
	check(not open_encounter(wrong_source, "wrong-source", 1).ok,
		"changed source content pin refuses")
	definition.attack = 0
	entries[0].life = 0
	check(roster.snapshot() == frozen, "authored inputs are detached")
	var opened := open_encounter(initial, "ford", 42)
	check(opened.ok, "open Ford")
	if not opened.ok:
		push_error(str(opened))
		quit(1)
		return
	var first: RefCounted = opened.encounter
	check(not first.collect().ok, "unstarted collection refuses")
	check(first.session.begin().ok, "begin Ford")
	check(not first.collect().ok, "unfinished collection refuses")
	var result: Dictionary = first.session.issue_command({"op": "attack",
		"unit": "ford:vanguard", "target": "guard"})
	var survivor: Combatant = first.session.scenario.units["ford:vanguard"]
	check(result.accepted and not result.errored and first.session.winning_side_id() == 0,
		"real Ford melee finishes battle")
	check(survivor.life == 14, "preserve supplied combat vector")
	check(initial == frozen and roster.snapshot() == frozen,
		"battle leaves initial snapshot and live roster unchanged")
	var collected: Dictionary = first.collect()
	check(collected.ok, "collect completed Ford")
	if not collected.ok:
		push_error(str(collected))
		quit(1)
		return
	var outcome: Dictionary = collected.outcome
	var pristine := outcome.duplicate(true)
	var applied: Dictionary = roster.apply(outcome)
	check(applied.ok and applied.receipt.revision == 1, "apply Ford once")
	var original_receipt: Dictionary = applied.receipt.duplicate(true)
	outcome.units[0].life = 0
	applied.receipt.outcome.units.clear()
	check(roster.snapshot().entries[ROSTER_ID].life == 14,
		"outcomes and returned receipts cannot alias live state")

	# A separate deployment records the weak entry's final death through real combat.
	var casualty_open := open_encounter(roster.snapshot(), "casualty-ford", 44, "casualty")
	check(casualty_open.ok, "open casualty encounter")
	var casualty: RefCounted = casualty_open.encounter
	check(casualty.session.begin().ok, "begin casualty encounter")
	var fatal: Dictionary = casualty.session.issue_command({"op": "attack",
		"unit": "casualty-ford:vanguard", "target": "guard"})
	check(fatal.accepted and not fatal.errored and casualty.session.battle_complete(),
		"first strike kills weak roster entry")
	var death: Dictionary = casualty.collect()
	check(death.ok and death.outcome.units[0].life == 0, "collect casualty")
	check(roster.apply(death.outcome).ok, "apply casualty")
	check(roster.snapshot().revision == 2, "revision advances once per outcome")
	check(not open_encounter(roster.snapshot(), "dead", 45, "casualty").ok,
		"casualty cannot redeploy")
	var before_retry: Dictionary = roster.snapshot()
	var retry: Dictionary = roster.apply(pristine.duplicate(true))
	check(retry.ok and retry.receipt == original_receipt,
		"identical retry returns original complete receipt after revision advances")
	check(roster.snapshot() == before_retry, "retry does not mutate any state")
	var conflict := pristine.duplicate(true)
	conflict.units[0].life = 13
	refusal(roster, conflict, "conflicting duplicate")
	var stale := pristine.duplicate(true)
	stale.encounter_id = "unseen-stale"
	refusal(roster, stale, "stale unseen outcome")
	var current := pristine.duplicate(true)
	current.encounter_id = "unseen-current"
	current.source_revision = 2
	for bad_pin in ["rules", "content", "profile"]:
		var wrong := current.duplicate(true)
		wrong.pins[bad_pin] = "wrong"
		refusal(roster, wrong, "wrong pin " + bad_pin)
	for field in ["roster_id", "def", "instance_id", "life"]:
		var invalid := current.duplicate(true)
		invalid.units[0][field] = -1 if field == "life" else ""
		refusal(roster, invalid, "invalid unit " + field)
	var unknown := current.duplicate(true)
	unknown.units[0].roster_id = "unknown"
	refusal(roster, unknown, "unknown roster ID")
	var duplicate := current.duplicate(true)
	duplicate.units[0].life = 13
	duplicate.units.append(duplicate.units[0].duplicate(true))
	refusal(roster, duplicate, "duplicate roster ID")
	var duplicate_instance := current.duplicate(true)
	duplicate_instance.units.append({"roster_id": "casualty", "def": "campaign:unit/1",
		"instance_id": "ford:vanguard", "life": 0})
	refusal(roster, duplicate_instance, "duplicate tactical ID")
	var wrong_owner := current.duplicate(true)
	wrong_owner.owner = 1
	refusal(roster, wrong_owner, "wrong owner")

	# Collection failures never reach roster state, even after a completed battle.
	var complete_state: Dictionary = roster.snapshot()
	first.session.scenario.runtime_error = "synthetic halt"
	check(not first.collect().ok, "halted collection refuses")
	first.session.scenario.runtime_error = ""
	var old_id := survivor.instance_id
	survivor.instance_id = "changed"
	check(not first.collect().ok, "changed identity refuses")
	survivor.instance_id = old_id
	var old_life := survivor.life
	survivor.life = -1
	check(not first.collect().ok, "invalid mapped life refuses")
	survivor.life = old_life
	var attack := survivor.attack
	survivor.attack += 1
	check(not first.collect().ok, "changed static definition refuses")
	survivor.attack = attack
	var azure: Array = first.session.scenario.state.sides[0].units
	azure.erase(survivor)
	first.session.scenario.state.sides[1].units.append(survivor)
	check(not first.collect().ok, "changed ownership refuses")
	first.session.scenario.state.sides[1].units.erase(survivor)
	azure.append(survivor)
	survivor.battle_owned = true
	check(not first.collect().ok, "replacement refuses")
	survivor.battle_owned = false
	first.session.scenario.units["summon"] = Combatant.new()
	check(not first.collect().ok, "summon refuses")
	first.session.scenario.units.erase("summon")
	check(first.collect().ok and roster.snapshot() == complete_state,
		"collection refusals leave entire roster and receipts unchanged")

	# Only current life crosses; tactical resources and effects remain local.
	survivor.stamina = 1
	survivor.morale = 2
	survivor.ammo = 7
	survivor.action_spent = true
	survivor.statuses.append(Status.new())
	var recollected: Dictionary = first.collect()
	check(recollected.ok and recollected.outcome == pristine,
		"collection exports only life, with no tactical resources or statuses")
	var second_open := open_encounter(roster.snapshot(), "watchpost", 43)
	check(second_open.ok, "open Watchpost")
	var second: RefCounted = second_open.encounter
	check(second.session.begin().ok, "begin Watchpost")
	var next_unit: Combatant = second.session.scenario.units["watchpost:vanguard"]
	check(next_unit.life == 14 and next_unit.life_base == BASE_LIFE
		and next_unit != survivor and next_unit.instance_id != old_id,
		"fresh encounter object and instance retain life")
	check(next_unit.stamina == 10 and next_unit.morale == 10 and next_unit.ammo == 0
		and next_unit.statuses.is_empty() and not next_unit.action_spent,
		"tactical state resets to authored values")
	check(second.session.scenario != first.session.scenario,
		"each encounter owns a distinct tactical state")
	check(second.session.scenario.seed_value == 43,
		"encounter uses caller-supplied seed")
	var detached: Dictionary = roster.snapshot()
	detached.entries.clear()
	detached.receipts.clear()
	check(roster.snapshot() == complete_state, "returned snapshot is detached")
	print("Roster %s life: first=%d second=%d" % [ROSTER_ID, survivor.life, next_unit.life])
	print("Campaign roster checks: %d failures" % failures)
	quit(0 if failures == 0 else 1)
