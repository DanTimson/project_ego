extends RefCounted

## Visible-state native policy. Stable string keys break ties; no tactical RNG.
static func choose(model: RefCounted, faction: String) -> Dictionary:
	var s: Dictionary = model.snapshot()
	var c: Dictionary = model.content()
	var candidates: Array = []
	for army in s.armies:
		if s.armies[army].faction != faction:
			continue
		var origin: String = s.armies[army].province
		for destination in c.provinces[origin].links:
			var command := {"op": "travel", "army": army, "to": destination}
			if not model.query(command).ok:
				continue
			var owner: String = s.provinces[destination].owner
			var score: int = c.policy.neutral if owner == "" else c.policy.enemy
			if owner == faction:
				score = c.policy.advance * (_distance(c, s, origin, faction)
					- _distance(c, s, destination, faction))
			else:
				for f in c.factions:
					if f != faction and c.factions[f].home == destination:
						score += c.policy.objective
			if score > c.policy.hold:
				candidates.append({"command": command, "score": score,
					"key": army + ":" + destination})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.score > b.score if a.score != b.score else a.key < b.key)
	if not candidates.is_empty():
		return candidates[0].command
	# Reinforce through exactly the same individual transfer and formation guards.
	var provinces: Array = s.provinces.keys()
	provinces.sort()
	for province in provinces:
		if s.provinces[province].owner != faction:
			continue
		var garrison: Array = model.members("", province)
		var army: String = model.field_at(province)
		if garrison.is_empty():
			continue
		if army != "":
			var transfer := {"op": "transfer", "unit": garrison[0], "army": army}
			if model.query(transfer).ok:
				return transfer
		else:
			var form := {"op": "form", "province": province,
				"units": garrison.slice(0, c.army_cap)}
			if model.query(form).ok:
				return form
	# Invest in catalogue income facilities, then heal or recruit at the faction Home.
	var buildings: Array = c.buildings.keys()
	buildings.sort()
	for id in buildings:
		var build := {"op": "build", "id": id}
		if c.buildings[id].effect == "income" and model.query(build).ok:
			return build
	var wounded: Array = []
	for u in s.units.values():
		if u.faction == faction and u.province == c.factions[faction].home \
				and u.life < c.definitions[u.def].get("life_base", c.definitions[u.def].life):
			wounded.append(u.id)
	var recovery := {"op": "recover", "units": wounded}
	if model.query(recovery).ok:
		return recovery
	var recruit := {"op": "recruit", "id": c.recruit_def}
	return recruit if model.query(recruit).ok else {}


static func _distance(c: Dictionary, s: Dictionary, start: String, faction: String) -> int:
	var frontier: Array = [start]
	var seen: Array = [start]
	for distance in c.provinces.size():
		var next: Array = []
		for id in frontier:
			if s.provinces[id].owner != faction:
				return distance
			for link in c.provinces[id].links:
				if link not in seen:
					seen.append(link)
					next.append(link)
		frontier = next
	return c.provinces.size()


## Existing tactical policy, selected side explicit for NPC/NPC contests and tests.
static func tactical_command(session: ManualBattleSession) -> Dictionary:
	var command := CrimsonPolicy.choose_command(session, session.active_side_id())
	return command if not command.is_empty() else {"op": "pass"}
