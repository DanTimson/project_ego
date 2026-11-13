extends ContestedCampaign

# All CX-034 rules are opt-in. The inherited round/contest path remains authoritative.
# gdlint: disable=max-returns,max-file-lines
const ProvinceValidation = preload("res://core/campaign/province_validation.gd")
var _decision: Dictionary = {}
var _journal: Array = []
var _depth := 0


static func create_province(c: Dictionary) -> ContestedCampaign:
	if ProvinceValidation.definition_error(c) != "":
		return null
	var model = load("res://core/campaign/province_campaign.gd").new()
	model._content = c.duplicate(true)
	model._state = ContestedCampaign.opening_state(c)
	model._initialize_provinces()
	return model


func _initialize_provinces() -> void:
	_state["knowledge"] = {}
	_state["heroes"] = {}
	_state["inventory"] = {}
	_state["formation"] = {}
	_state["outcomes"] = []
	_state["money_log"] = []
	for faction in _content.factions:
		_state.factions[faction]["crystals"] = _content.factions[faction].crystals
		_state.knowledge[faction] = {}
		for id in _content.provinces:
			_state.knowledge[faction][id] = {
				"level": "unknown", "progress": 0, "resource": false, "site": false, "memory": {}
			}
	for id in _content.provinces:
		var p: Dictionary = _state.provinces[id]
		var authored: Dictionary = _content.provinces[id]
		p["stability"] = authored.stability
		p["captured"] = 0
		p["site"] = {
			"status": "guarded" if not authored.site.is_empty() else "absent",
			"guards": [],
			"resolved_by": ""
		}
		for index in authored.site.get("guards", []).size():
			var type: String = authored.site.guards[index]
			p.site.guards.append(
				{"id": "site:%s:%d" % [id, index], "def": type, "life": _max_life(type)}
			)
		if p.owner != "":
			_reveal(p.owner, id)
	_sync_memory()


func members(army: String, province := "") -> Array:
	var ids := super.members(army, province)
	if army != "" and _state.has("formation"):
		var order: Array = _state.formation.get(army, [])
		var sorted: Array = order.filter(func(id: String) -> bool: return id in ids)
		for id in ids:
			if id not in sorted:
				sorted.append(id)
		return sorted
	return ids


func _reveal(faction: String, id: String) -> void:
	_state.knowledge[faction][id].level = "known"
	for neighbor in _content.provinces[id].links:
		if _state.knowledge[faction][neighbor].level == "unknown":
			_state.knowledge[faction][neighbor].level = "frontier"


func _visible(faction: String, id: String) -> bool:
	return (
		_state.provinces[id].owner == faction
		or _state.armies.values().any(
			func(a: Dictionary) -> bool: return a.faction == faction and a.province == id
		)
	)


func _sync_memory() -> void:
	for faction in _content.factions:
		for id in _content.provinces:
			if _visible(faction, id):
				_reveal(faction, id)
				_state.knowledge[faction][id].memory = _province_view(faction, id)


func _province_view(faction: String, id: String) -> Dictionary:
	var k: Dictionary = _state.knowledge[faction][id]
	var p: Dictionary = _state.provinces[id]
	var a: Dictionary = _content.provinces[id]
	var view := {
		"name": a.name,
		"terrain": a.terrain,
		"tier": a.tier,
		"owner": p.owner,
		"stability": p.stability,
		"recovery": _content.province_rules.recovery,
		"recovery_due": p.owner != "" and p.captured < _state.round,
		"income_scale": _stability_scale(p.stability),
		"progress": k.progress,
		"base": {"gold": a.income, "crystals": a.crystals},
		"payout": yields(id, true),
		"garrison": members("", id).size(),
		"resource": a.resource.duplicate(true) if k.resource else {},
		"site": p.site.duplicate(true) if k.site else {},
		"site_name": a.site.name if k.site else "",
		"buildings": p.buildings.duplicate(true)
	}
	return view


## The only policy/presentation province data source. Hidden values never escape here.
func faction_view(faction: String) -> Dictionary:
	var result := {
		"provinces": {},
		"armies": {},
		"units": {},
		"treasury": _state.factions[faction].duplicate(true)
	}
	for id in _content.provinces:
		var k: Dictionary = _state.knowledge[faction][id]
		var visible := _visible(faction, id)
		var p: Dictionary = _province_view(faction, id) if visible else k.memory.duplicate(true)
		p["knowledge"] = k.level
		p["visibility"] = "current" if visible else "remembered" if k.level == "known" else k.level
		p["point"] = _content.provinces[id].point.duplicate()
		p["links"] = _content.provinces[id].links.filter(
			func(other: String) -> bool:
				return k.level != "unknown" and _state.knowledge[faction][other].level != "unknown"
		)
		result.provinces[id] = p
	for id in _state.armies:
		if _state.armies[id].faction == faction:
			result.armies[id] = _state.armies[id].duplicate(true)
	for id in _state.units:
		if _state.units[id].faction == faction:
			result.units[id] = _state.units[id].duplicate(true)
	return result


func _budget(army: String) -> Dictionary:
	if not _state.armies.has(army) or _state.armies[army].faction != active_faction():
		return _refuse("Select a living active faction army.")
	if (
		_state.armies[army].moves == 0
		or members(army).any(func(id: String) -> bool: return _state.units[id].moved)
	):
		return _refuse("Travel, Explore and encounters share one movement budget.")
	return _ok("")


func query(command: Dictionary) -> Dictionary:
	if not CampaignRoster.values_only(command) or not command.get("op") is String:
		return _refuse("Invalid command.")
	if _state.status != "active" or in_battle():
		return _refuse("Resolve the encounter or campaign first.")
	if not _decision.is_empty():
		if command.op != "decide":
			return _refuse("Choose Fight, Withdraw or Negotiate first.")
		return _decision_query(command)
	var fields := {
		"explore": ["army"],
		"site": ["army"],
		"build": ["id", "province"],
		"recruit": ["id", "province"],
		"recover": ["units", "province"],
		"hire": ["id", "province"],
		"buy": ["id", "hero", "province"],
		"assign": ["hero", "army"],
		"equip": ["hero", "item"],
		"unequip": ["hero", "slot"],
		"order": ["army", "units"]
	}
	if not fields.has(command.op):
		if command.op in ["transfer", "form"]:
			var base := super.query(command)
			if base.ok and command.op == "transfer" and _state.heroes.has(command.unit):
				return _refuse("Use the leader assignment command.")
			if (
				base.ok
				and command.op == "form"
				and command.units.any(func(id: String) -> bool: return _state.heroes.has(id))
			):
				return _refuse("Form with troops, then assign a leader.")
			return base
		return super.query(command)
	if command.size() != fields[command.op].size() + 1:
		return _refuse("Invalid command fields.")
	for key in fields[command.op]:
		if (
			not command.has(key)
			or (key == "units" and not command[key] is Array)
			or (key != "units" and not command[key] is String)
		):
			return _refuse("Invalid command values.")
	match command.op:
		"explore", "site":
			var budget := _budget(command.army)
			if not budget.ok:
				return budget
			var province: String = _state.armies[command.army].province
			var k: Dictionary = _state.knowledge[active_faction()][province]
			if command.op == "explore":
				if (
					_state.provinces[province].owner not in ["", active_faction()]
					or k.progress == 100
				):
					return _refuse("Explore a friendly/neutral province below 100%.")
			elif not k.site or _state.provinces[province].site.status != "guarded":
				return _refuse("No discovered guarded site here.")
			return _ok("")
		"build", "recruit", "recover", "hire", "buy":
			return _local_service_query(command)
		"assign", "equip", "unequip":
			return _hero_query(command)
		"order":
			if (
				not _state.armies.has(command.army)
				or _state.armies[command.army].faction != active_faction()
			):
				return _refuse("Select a friendly army.")
			if not command.units.all(func(id: Variant) -> bool: return id is String):
				return _refuse("Formation IDs must be strings.")
			var expected := members(command.army)
			var proposed: Array = command.units.duplicate()
			proposed.sort()
			expected.sort()
			if proposed != expected:
				return _refuse("Order must contain each army member exactly once.")
	return _ok("")


func execute(command: Dictionary) -> Dictionary:
	var legal := query(command)
	if not legal.ok:
		return legal
	_depth += 1
	var result := _apply(command)
	_depth -= 1
	_sync_memory()
	if not _decision.is_empty():
		_decision.stamp = _terms_stamp()
		_decision.token = str(_decision.attempt) + ":" + _decision.stamp
	if result.ok and _depth == 0:
		_journal.append({"op": "command", "command": command.duplicate(true)})
	return result


func _apply(command: Dictionary) -> Dictionary:
	match command.op:
		"explore":
			var id: String = _state.armies[command.army].province
			var k: Dictionary = _state.knowledge[active_faction()][id]
			k.progress = mini(100, k.progress + _content.province_rules.explore)
			for feature in ["resource", "site"]:
				if (
					not _content.provinces[id][feature].is_empty()
					and k.progress >= _content.provinces[id][feature].threshold
				):
					k[feature] = true
			_spend_move(command.army)
			_note(
				(
					"%s explores %s to %d%%; discovery applies at next eligible payout"
					% [active_faction(), id, k.progress]
				)
			)
		"site":
			return _prepare_choice(command.army, _state.armies[command.army].province, "site")
		"decide":
			return _decide(command.choice)
		"build", "recruit", "recover", "hire", "buy":
			_local_service(command)
		"assign":
			var u: Dictionary = _state.units[command.hero]
			var old: String = u.army
			u.army = command.army
			if u.army != "" and u.moved:
				_state.armies[u.army].moves = 0
			_disband_empty(old)
		"equip":
			var item: Dictionary = _state.inventory[command.item]
			var slot: String = _content.equipment[item.type].slot
			_state.heroes[command.hero].slots[slot] = command.item
			item.equipped = true
		"unequip":
			var slots: Dictionary = _state.heroes[command.hero].slots
			_state.inventory[slots[command.slot]].equipped = false
			slots.erase(command.slot)
		"order":
			_state.formation[command.army] = command.units.duplicate()
		_:
			return super.execute(command)
	_note("%s %s" % [active_faction(), JSON.stringify(command)])
	return _ok("Command applied.")


func _local_service_query(cmd: Dictionary) -> Dictionary:
	var faction := active_faction()
	if not _state.provinces.has(cmd.province) or _state.provinces[cmd.province].owner != faction:
		return _refuse("Service target must be an owned settlement.")
	if _state.factions[faction].service == _state.round:
		return _refuse("One shared paid service per faction round.")
	var p: Dictionary = _state.provinces[cmd.province]
	var authored: Dictionary = _content.provinces[cmd.province]
	var capital: bool = authored.tier == "capital"
	match cmd.op:
		"build":
			if not _content.buildings.has(cmd.id) or p.buildings.has(cmd.id):
				return _refuse("Unknown or already built facility.")
			var b: Dictionary = _content.buildings[cmd.id]
			if (b.district == "capital") != capital:
				return _refuse("Wrong settlement district.")
			if b.has("terrains") and authored.terrain not in b.terrains:
				return _refuse("Ineligible terrain.")
			for required in b.requires:
				if not p.buildings.has(required):
					return _refuse("Local prerequisite: " + _content.buildings[required].name)
		"recruit":
			if not _content.recruits.has(cmd.id):
				return _refuse("Unknown recruit.")
			var required: String = _content.recruits[cmd.id].requires
			if (
				(not capital and required == "")
				or (required != "" and not p.buildings.has(required))
			):
				return _refuse("Local recruitment facility required.")
			if members("", cmd.province).size() >= _content.garrison_cap:
				return _refuse("Settlement garrison is full.")
		"recover":
			if cmd.units.is_empty():
				return _refuse("Select wounded local survivors.")
			var seen: Array = []
			for id in cmd.units:
				if not id is String or id in seen or not _state.units.has(id):
					return _refuse("Invalid recovery selection.")
				var u: Dictionary = _state.units[id]
				if u.faction != faction or u.province != cmd.province or u.life >= _max_life(u.def):
					return _refuse("Recover wounded friendly local survivors only.")
				seen.append(id)
		"hire":
			if not _content.heroes.has(cmd.id) or _state.heroes.has(faction + ":" + cmd.id):
				return _refuse("Unknown or already hired hero identity.")
			if members("", cmd.province).size() >= _content.garrison_cap:
				return _refuse("Settlement garrison is full, including leaders.")
		"buy":
			if (
				not _content.equipment.has(cmd.id)
				or not _state.units.has(cmd.hero)
				or not _state.heroes.has(cmd.hero)
				or _state.units[cmd.hero].faction != faction
				or _state.units[cmd.hero].province != cmd.province
			):
				return _refuse("Buy equipment for a living local hero.")
			if _state.inventory.has(cmd.hero + ":" + cmd.id):
				return _refuse("Hero already owns this item.")
	return _afford(faction, _price(cmd))


func _price(cmd: Dictionary) -> Dictionary:
	match cmd.op:
		"build":
			return {
				"gold": _content.buildings[cmd.id].cost,
				"crystals": _content.buildings[cmd.id].crystals
			}
		"recruit":
			return {
				"gold": _content.recruits[cmd.id].cost,
				"crystals": _content.recruits[cmd.id].get("crystals", 0)
			}
		"hire":
			return _content.heroes[cmd.id]
		"buy":
			return _content.equipment[cmd.id]
	return {"gold": _content.recovery_cost, "crystals": 0}


func _afford(faction: String, price: Dictionary) -> Dictionary:
	for currency in ["gold", "crystals"]:
		if _state.factions[faction][currency] < price.get(currency, 0):
			return _refuse("Not enough " + currency + " before income.")
	return _ok("")


## One ledger mutation for payouts and payments, with named integer currencies.
func _pay(faction: String, amounts: Dictionary, reason: String, sign_value := 1) -> void:
	for currency in ["gold", "crystals"]:
		_state.factions[faction][currency] += sign_value * amounts.get(currency, 0)
	_state.money_log.append(
		{
			"faction": faction,
			"round": _state.round,
			"amounts": amounts.duplicate(true),
			"sign": sign_value,
			"reason": reason
		}
	)
	_note(
		(
			"%s %s: %dg %dc"
			% [
				faction,
				reason,
				sign_value * amounts.get("gold", 0),
				sign_value * amounts.get("crystals", 0)
			]
		)
	)


func _local_service(cmd: Dictionary) -> void:
	var faction := active_faction()
	var price := _price(cmd).duplicate(true)
	match cmd.op:
		"build":
			_state.provinces[cmd.province].buildings[cmd.id] = _state.round
		"recruit", "hire":
			var hero: bool = cmd.op == "hire"
			var id: String = faction + ":" + cmd.id if hero else "recruited-%d" % _state.next_unit
			var type: String = _content.heroes[cmd.id].faction_defs[faction] if hero else cmd.id
			if hero:
				_state.heroes[id] = {"role": cmd.id, "xp": 0, "level": 1, "slots": {}}
			else:
				_state.next_unit += 1
			_state.units[id] = {
				"id": id,
				"def": type,
				"faction": faction,
				"province": cmd.province,
				"army": "",
				"life": _max_life(type),
				"moved": false
			}
		"recover":
			for id in cmd.units:
				var u: Dictionary = _state.units[id]
				u.life = mini(
					_max_life(u.def),
					u.life + _content.recovery_life + _bonus(cmd.province, "recovery", false)
				)
		"buy":
			_state.inventory[cmd.hero + ":" + cmd.id] = {
				"hero": cmd.hero, "type": cmd.id, "equipped": false
			}
	_pay(faction, {"gold": price.gold, "crystals": price.get("crystals", 0)}, "service", -1)
	_state.factions[faction].service = _state.round
	_state.factions[faction].services.append(
		{"round": _state.round, "command": cmd.duplicate(true)}
	)


func _hero_query(cmd: Dictionary) -> Dictionary:
	if (
		not _state.heroes.has(cmd.hero)
		or not _state.units.has(cmd.hero)
		or _state.units[cmd.hero].faction != active_faction()
	):
		return _refuse("Select a living friendly hero.")
	var u: Dictionary = _state.units[cmd.hero]
	if _state.provinces[u.province].owner != u.faction:
		return _refuse("Use an owned settlement.")
	var slots: Dictionary = _state.heroes[cmd.hero].slots
	match cmd.op:
		"assign":
			if u.army == cmd.army:
				return _refuse("Leader already assigned there.")
			if cmd.army == "":
				if members("", u.province).size() >= _content.garrison_cap:
					return _refuse("Settlement garrison is full.")
			elif (
				not _state.armies.has(cmd.army)
				or _state.armies[cmd.army].faction != u.faction
				or _state.armies[cmd.army].province != u.province
				or members(cmd.army).size() >= _content.army_cap
				or members(cmd.army).any(func(id: String) -> bool: return _state.heroes.has(id))
			):
				return _refuse("Co-located army needs one free slot and no leader.")
		"equip":
			if not _state.inventory.has(cmd.item) or _state.inventory[cmd.item].hero != cmd.hero:
				return _refuse("Item must belong to this hero.")
			var slot: String = _content.equipment[_state.inventory[cmd.item].type].slot
			if slots.has(slot):
				return _refuse("Unequip the occupied slot first.")
		"unequip":
			if not slots.has(cmd.slot):
				return _refuse("Slot is empty.")
	return _ok("")


func _unit_definition(id: String) -> Dictionary:
	var result := super._unit_definition(id)
	if _state.heroes.has(id):
		var h: Dictionary = _state.heroes[id]
		result.attack += (h.level - 1) * _content.province_rules.level_attack
		for item in h.slots.values():
			var equipment: Dictionary = _content.equipment[_state.inventory[item].type]
			result[equipment.stat] = result.get(equipment.stat, 0) + equipment.value
	return result


func hero_stats(id: String) -> Dictionary:
	if not _state.units.has(id) or not _state.heroes.has(id):
		return {}
	return {
		"base": _content.definitions[_state.units[id].def].duplicate(true),
		"effective": _unit_definition(id),
		"progress": _state.heroes[id].duplicate(true)
	}


func encounter_choice() -> Dictionary:
	return _decision.duplicate(true)


func _prepare_choice(army: String, destination: String, kind: String) -> Dictionary:
	if _state.serial >= 1000000:
		return _refuse("Encounter allocation exhausted.")
	_state.serial += 1
	var a: Dictionary = _content.provinces[destination]
	var faction: String = _state.armies[army].faction
	var known: Dictionary = faction_view(faction).provinces[destination]
	var price: Dictionary = a.site.get("tribute", {}) if kind == "site" else a.get("tribute", {})
	_decision = {
		"army": army,
		"to": destination,
		"kind": kind,
		"from": _state.armies[army].province,
		"faction": faction,
		"attempt": _state.serial,
		"reward": a.site.reward.duplicate(true) if kind == "site" else {},
		"token": "",
		"stamp": "",
		"known": known,
		"price": price.duplicate(true),
		"negotiate":
		not price.is_empty() and (kind == "site" or _state.provinces[destination].owner == "")
	}
	_note("Encounter choice %d: %s; no movement spent" % [_state.serial, kind])
	return _ok("Choose Fight, Withdraw or Negotiate.")


func _decision_query(cmd: Dictionary) -> Dictionary:
	if (
		cmd.size() != 3
		or not cmd.get("choice") is String
		or not cmd.get("token") is String
		or cmd.choice not in ["fight", "withdraw", "negotiate"]
	):
		return _refuse("Invalid encounter decision.")
	if cmd.token != _decision.token or _decision.stamp != _terms_stamp():
		return _refuse("Stale encounter terms; position, control or funds changed.")
	if cmd.choice == "withdraw":
		return _ok("")
	var legal := _budget(_decision.army)
	if not legal.ok:
		return legal
	if cmd.choice == "negotiate":
		if not _decision.negotiate:
			return _refuse("Negotiation is not offered.")
		return _afford(active_faction(), _decision.price)
	return _ok("")


func _decide(choice: String) -> Dictionary:
	var d := _decision.duplicate(true)
	_decision.clear()
	if choice == "withdraw":
		_note("Withdraw attempt %d; roster, movement, control and rewards preserved" % d.attempt)
		return _ok("Withdrawn to " + d.from + ".")
	if choice == "negotiate":
		_pay(d.faction, d.price, "tribute attempt %d" % d.attempt, -1)
		_spend_move(d.army)
		if d.kind == "site":
			_state.provinces[d.to].site.status = "negotiated"
			_state.provinces[d.to].site.resolved_by = d.faction
		else:
			for id in members("", d.to):
				_retire(id)
			_change_control(d.to, d.faction)
			_relocate(d.army, d.to)
			_reveal(d.faction, d.to)
		_state.outcomes.append(
			{
				"attempt": d.attempt,
				"kind": d.kind,
				"to": d.to,
				"decision": "negotiated",
				"faction": d.faction
			}
		)
		_check_terminal()
		return _ok("Tribute paid once; no battle rewards or XP.")
	if d.kind == "site":
		return _open_site(d.army, d.to)
	return _fight_travel(d.army, d.to)


func _travel(army: String, destination: String) -> Dictionary:
	var defenders := members("", destination)
	var field := field_at(destination)
	if field != "":
		defenders.append_array(members(field))
	if (
		not defenders.is_empty()
		and _state.provinces[destination].owner != active_faction()
		and _state.provinces[destination].owner != _content.player
	):
		return _prepare_choice(army, destination, "travel")
	return _fight_travel(army, destination)


func _fight_travel(army: String, destination: String) -> Dictionary:
	var prior: String = _state.provinces[destination].owner
	var result := super._travel(army, destination)
	if result.ok and not in_battle():
		_after_control(destination, prior)
		_reveal(_state.armies[army].faction, destination)
	return result


func _open_site(army: String, province: String) -> Dictionary:
	var entries: Array = []
	var mappings: Array = [{}, {}]
	var participants: Array = [members(army), []]
	var attacker_side := 0
	var encounter_id := "%s:site-attempt-%d" % [_content.id, _state.serial]
	for id in participants[0]:
		entries.append(
			{
				"id": id,
				"def": _state.units[id].def,
				"life": _state.units[id].life,
				"definition": _unit_definition(id)
			}
		)
	for guard in _state.provinces[province].site.guards:
		if guard.life > 0:
			participants[1].append(guard.id)
			entries.append(
				{
					"id": guard.id,
					"def": guard.def,
					"life": guard.life,
					"definition": _content.definitions[guard.def].duplicate(true)
				}
			)
	for side in 2:
		for id in participants[side]:
			mappings[side][id] = {
				"instance_id": encounter_id + ":" + id,
				"at": _content.deployment[side][mappings[side].size()].duplicate()
			}
	var opened := CampaignEncounter.open_contest(
		entries,
		_content.rules,
		encounter_id,
		_content.seed + _state.completed,
		mappings,
		_content.battlefield,
		attacker_side,
		[_content.factions[active_faction()].name, _content.provinces[province].site.name]
	)
	if not opened.ok:
		return opened
	_pending = opened.encounter
	_contest = {
		"army": army,
		"from": province,
		"to": province,
		"attacker": active_faction(),
		"attacker_side": 0,
		"defense": false,
		"participants": participants,
		"kind": "site",
		"attempt": _state.serial
	}
	_note("Site battle %s; independent guards; save blocked" % encounter_id)
	return {"ok": true, "reason": "Site battle opened.", "encounter": _pending}


func _retire(id: String) -> void:
	var u: Dictionary = _state.units[id].duplicate(true)
	u.life = 0
	u.army = ""
	u.province = ""
	_state.casualties[id] = u
	_state.units.erase(id)


func _change_control(id: String, faction: String) -> void:
	var prior: String = _state.provinces[id].owner
	_state.provinces[id].owner = faction
	_after_control(id, prior)


func _after_control(id: String, prior: String) -> void:
	var p: Dictionary = _state.provinces[id]
	if p.owner == prior:
		return
	p.stability = maxi(0, p.stability - _content.province_rules.capture_loss)
	p.captured = _state.round
	# Captured unassigned leaders are casualties; their inventory stays with their identity.
	for hero in _state.heroes:
		if (
			_state.units.has(hero)
			and _state.units[hero].province == id
			and _state.units[hero].army == ""
			and _state.units[hero].faction != p.owner
		):
			_retire(hero)
	if p.owner != "":
		_reveal(p.owner, id)
	_note(
		(
			"Control %s: %s -> %s; stability %d; recovery begins after capture round"
			% [id, prior, p.owner, p.stability]
		)
	)


func finish(encounter: CampaignEncounter) -> Dictionary:
	var inputs: Array = (
		encounter.session.command_history.duplicate(true) if encounter != null else []
	)
	_depth += 1
	var result := super.finish(encounter)
	_depth -= 1
	_sync_memory()
	if result.ok and _depth == 0:
		_journal.append({"op": "finish", "commands": inputs})
	return result


func abandon(encounter: CampaignEncounter) -> Dictionary:
	var result := super.abandon(encounter)
	if result.ok and _depth == 0:
		_journal.append({"op": "abandon"})
	return result


func concede() -> Dictionary:
	_depth += 1
	var result := super.concede()
	_depth -= 1
	_sync_memory()
	if result.ok and _depth == 0:
		_journal.append({"op": "concede"})
	return result


func _resolve(winner: int, results: Array) -> Dictionary:
	var prior: String = _state.provinces[_contest.to].owner
	var destination: String = _contest.to
	var participants: Array = _contest.participants[winner] if winner in [0, 1] else []
	var attacker: String = _contest.attacker
	var attacker_side: int = _contest.attacker_side
	var attempt: int = _state.serial
	if _contest.get("kind") != "site":
		# base resolution can continue rivals; apply capture/XP before that continuation.
		var phase: String = _state.phase
		_state.phase = "player"
		var result := super._resolve(winner, results)
		if not result.ok:
			_state.phase = phase
			return result
		_after_control(destination, prior)
		_state.outcomes.append(
			{
				"attempt": attempt,
				"to": destination,
				"kind": "travel",
				"decision": "win" if winner == attacker_side else "loss",
				"faction": attacker
			}
		)
		_award_xp(participants)
		if _state.status == "active":
			_state.phase = phase
			if phase == "rival":
				return _advance_rivals()
		return result
	# CampaignEncounter has already checked detached life, definitions and identity.
	var site: Dictionary = _state.provinces[destination].site
	for result in results:
		if _state.units.has(result.roster_id):
			_state.units[result.roster_id].life = result.life
			if result.life == 0:
				_retire(result.roster_id)
		else:
			for guard in site.guards:
				if guard.id == result.roster_id:
					guard.life = result.life
	if _state.armies.has(_contest.army):
		_spend_move(_contest.army)
	if winner == 0:
		site.status = "cleared"
		site.resolved_by = _contest.attacker
		_pay(_contest.attacker, _content.provinces[destination].site.reward, "site reward")
		_award_xp(participants)
	_state.outcomes.append(
		{
			"attempt": _contest.attempt,
			"to": destination,
			"kind": "site",
			"decision": "win" if winner == 0 else "loss",
			"faction": _contest.attacker
		}
	)
	for id in _state.armies.keys():
		_disband_empty(id)
	_note("Site result applied once; guard wounds persist; province control unchanged")
	_pending.session.end()
	_pending = null
	_contest = {}
	if _state.phase == "rival":
		return _advance_rivals()
	return _ok("Site outcome applied once.")


func _award_xp(participants: Array) -> void:
	for id in participants:
		if not _state.heroes.has(id) or not _state.units.has(id):
			continue
		var h: Dictionary = _state.heroes[id]
		h.xp += _content.province_rules.xp
		h.level = 1
		for threshold in _content.province_rules.levels.slice(1):
			if h.xp >= threshold:
				h.level += 1
		_note("Hero %s XP %d level %d; wounds preserved" % [id, h.xp, h.level])


func yields(id: String, delayed := true) -> Dictionary:
	var p: Dictionary = _state.provinces[id]
	var a: Dictionary = _content.provinces[id]
	var result := {"gold": a.income + _bonus(id, "income", delayed), "crystals": a.crystals}
	for b in p.buildings:
		if not delayed or p.buildings[b] < _state.round:
			result.crystals += _content.buildings[b].crystal_yield
	if p.owner != "" and _state.knowledge[p.owner][id].resource:
		result.gold += a.resource.gold
		result.crystals += a.resource.crystals
	var scale := _stability_scale(p.stability)
	for currency in result:
		result[currency] = int(result[currency] * scale / 100)
	return result


func province_income(id: String, payout := false) -> int:
	return yields(id, payout).gold


func _complete_round() -> void:
	var factions: Array = _content.factions.keys()
	factions.sort()
	for faction in factions:
		var total := {"gold": 0, "crystals": 0}
		for id in _state.provinces:
			var p: Dictionary = _state.provinces[id]
			if p.owner == faction:
				var income := yields(id, true)
				for currency in total:
					total[currency] += income[currency]
				# Pay using current stability, then recover after a full owned round.
				if p.captured < _state.round:
					p.stability = mini(100, p.stability + _content.province_rules.recovery)
		_pay(faction, total, "end-round payout; prior-round facilities, then stability recovery")
	_state.completed += 1
	_check_terminal()
	_state.rival_index = 0
	_state.rival_commands = 0
	if _state.status != "active":
		return
	_state.round += 1
	_state.phase = "player"
	for a in _state.armies.values():
		a.moves = 1
	for u in _state.units.values():
		u.moved = false
	_note("Player round %d: army and troop movement refreshed" % _state.round)


func choose_province_action(faction: String) -> Dictionary:
	if not _decision.is_empty():
		var choice := {"op": "decide", "choice": "negotiate", "token": _decision.token}
		if query(choice).ok:
			return choice
		choice.choice = "fight"
		return choice if query(choice).ok else {}
	var view := faction_view(faction)
	var candidates: Array = []
	var weights: Dictionary = _content.province_rules.policy
	var armies: Array = view.armies.keys()
	armies.sort()
	for army in armies:
		for op in ["site", "explore"]:
			var command := {"op": op, "army": army}
			if query(command).ok:
				candidates.append({"command": command, "score": weights[op], "key": army + op})
		var origin: String = view.armies[army].province
		for to in view.provinces[origin].links:
			var command := {"op": "travel", "army": army, "to": to}
			if query(command).ok:
				var known: Dictionary = view.provinces[to]
				var score: int = weights.travel
				if known.get("owner", "") == faction:
					score = 0
				candidates.append({"command": command, "score": score, "key": army + to})
	for province in view.provinces:
		if view.provinces[province].get("owner", "") != faction:
			continue
		for id in _content.buildings:
			var command := {"op": "build", "id": id, "province": province}
			if query(command).ok:
				candidates.append(
					{"command": command, "score": weights.service, "key": province + id}
				)
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return a.score > b.score if a.score != b.score else a.key < b.key
	)
	if candidates.is_empty() or candidates[0].score == 0:
		return {}
	return candidates[0].command


func checkpoint() -> Dictionary:
	if in_battle() or _state.phase == "rival" or not _decision.is_empty():
		return _refuse("Save at a quiescent player map boundary; close the encounter panel first.")
	var data := {
		"version": 4,
		"mode": "province",
		"content": _content.id,
		"fingerprint": JSON.stringify(_content).sha256_text(),
		"state": snapshot(),
		"journal": _journal.duplicate(true)
	}
	# Dynamic load keeps the replay codec outside the campaign preload chain.
	var codec: Script = load("res://core/campaign/province_checkpoint.gd")
	var bounds: String = codec.replay_bounds_error(data)
	return {"ok": true, "data": data} if bounds.is_empty() else _refuse(bounds)


func _terms_stamp() -> String:
	return (
		JSON
		. stringify(
			{
				"armies": _state.armies,
				"units": _state.units,
				"provinces": _state.provinces,
				"factions": _state.factions
			}
		)
		. sha256_text()
	)


func _stability_scale(stability: int) -> int:
	var scale := 0
	for threshold in _content.province_rules.stability:
		if stability >= threshold[0]:
			scale = threshold[1]
	return scale
