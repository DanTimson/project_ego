extends RefCounted

# Explicit fail-closed guards for authored content and untrusted checkpoint values.
# gdlint: disable=max-returns

static func normalize(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 1e12:
		return int(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = normalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(normalize(item))
		return result
	return value


static func _integer(value: Variant, low: int, high: int) -> bool:
	return value is int and value >= low and value <= high


static func _keys(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() \
		and keys.all(func(key: String) -> bool: return value.has(key))


static func definition_error(c: Dictionary) -> String:
	if not CampaignRoster.values_only(c):
		return "Content must contain detached values."
	for field in ["id", "rules", "player", "objective", "recruit_def"]:
		if not c.get(field) is String or c[field].is_empty():
			return "Missing content identity/reference."
	for field in ["factions", "provinces", "definitions", "armies", "buildings", "recruits", "policy"]:
		if not c.get(field) is Dictionary:
			return "Missing content collection."
	for field in ["army_limit", "army_cap", "garrison_cap", "round_limit",
		"recovery_cost", "recovery_life"]:
		if not _integer(c.get(field), 1, 100):
			return "Invalid authored limit or service."
	if not _integer(c.get("seed"), 0, 1000000) or c.factions.size() < 2 \
			or not c.factions.has(c.player) or not c.provinces.has(c.objective):
		return "Invalid factions, objective or seed."
	if StrategicCampaign.validate_definition(c) != "":
		return "Invalid construction/recruit catalogue."
	if not c.get("battlefield") is Dictionary or not c.get("deployment") is Array \
			or c.deployment.size() != 2 or not c.get("units") is Array:
		return "Missing tactical layout or opening troops."
	var field: Dictionary = c.battlefield
	if not _keys(field, ["width", "height"]) or not _integer(field.get("width"), 2, 30) \
			or not _integer(field.get("height"), 1, 30):
		return "Invalid battlefield size."
	var cells: Array = []
	for deployment in c.deployment:
		if not deployment is Array or deployment.size() < c.army_cap + c.garrison_cap:
			return "Legal army plus garrison cannot deploy completely."
		for cell in deployment:
			if not cell is Array or cell.size() != 2 or cell in cells \
					or not _integer(cell[0], 0, field.width - 1) \
					or not _integer(cell[1], 0, field.height - 1):
				return "Invalid or overlapping deployment."
			cells.append(cell)
	var homes: Array = []
	for id in c.factions:
		var f: Variant = c.factions[id]
		if id.is_empty() or not f is Dictionary or not f.get("name") is String \
				or not f.get("home") is String or not c.provinces.has(f.home) \
				or f.home in homes or not _integer(f.get("gold"), 0, 1000000):
			return "Invalid faction/Home."
		homes.append(f.home)
		if not c.provinces[f.home] is Dictionary or c.provinces[f.home].get("owner") != id:
			return "Opening Home must belong to its faction."
	if not c.provinces[c.objective] is Dictionary \
			or c.provinces[c.objective].get("owner") in ["", c.player]:
		return "Objective must open under a rival."
	for id in c.provinces:
		var p: Variant = c.provinces[id]
		if id.is_empty() or not p is Dictionary or not p.get("name") is String \
				or not p.get("owner") is String or (p.owner != "" and not c.factions.has(p.owner)) \
				or not p.get("links") is Array or not _integer(p.get("income"), 0, 1000) \
				or not p.get("point") is Array or p.point.size() != 2:
			return "Invalid province."
		for coordinate in p.point:
			if not (coordinate is float or coordinate is int) or coordinate < 0 or coordinate > 1:
				return "Invalid map point."
		var seen: Array = []
		for link in p.links:
			if not link is String or link == id or link in seen or not c.provinces.has(link) \
					or not c.provinces[link] is Dictionary \
					or not c.provinces[link].get("links") is Array or id not in c.provinces[link].links:
				return "Graph links must be distinct and reciprocal."
			seen.append(link)
	var reached: Array = [c.provinces.keys()[0]]
	for iteration in c.provinces.size():
		for id in reached.duplicate():
			for link in c.provinces[id].links:
				if link not in reached:
					reached.append(link)
	if reached.size() != c.provinces.size():
		return "Disconnected graph."
	for id in c.armies:
		if id.begins_with("formed-") or id.is_empty():
			return "Reserved or empty army ID."
		var army: Variant = c.armies[id]
		if not _keys(army, ["faction", "province", "moves"]) \
				or not c.factions.has(army.faction) or not c.provinces.has(army.province) \
				or not _integer(army.moves, 0, 1):
			return "Invalid opening army."
	for type in c.definitions:
		if not c.definitions[type] is Dictionary:
			return "Invalid definition."
	var entries: Array = []
	var ids: Array = []
	for u in c.units:
		if not _keys(u, ["id", "def", "faction", "army", "province"]) \
				or not u.id is String or u.id.is_empty() or u.id in ids \
				or u.id.begins_with("recruited-") or not c.definitions.has(u.def) \
				or not u.army is String or (u.army != "" and not c.armies.has(u.army)) \
				or not c.provinces.has(u.province) \
				or (u.faction != "" and not c.factions.has(u.faction)):
			return "Invalid/duplicate opening unit identity."
		ids.append(u.id)
		entries.append({"id": u.id, "def": u.def, "life": c.definitions[u.def].get("life", 0),
			"definition": c.definitions[u.def]})
	if not CampaignRoster.create(entries, c.rules).ok:
		return "Invalid troop definitions."
	# Validate unused recruits too, before any command can construct them.
	for type in c.definitions:
		if not CampaignRoster.create([{"id": "validation", "def": type,
			"life": c.definitions[type].get("life", 0), "definition": c.definitions[type]}], c.rules).ok:
			return "Invalid definition."
	if not _integer(c.policy.get("commands"), 1, 64):
		return "Invalid policy command bound."
	for key in ["enemy", "neutral", "objective", "advance", "hold"]:
		if not _integer(c.policy.get(key), 0, 1000):
			return "Invalid policy weight."
	return ""


static func state_error(c: Dictionary, s: Dictionary) -> String:
	if not _keys(s, ["round", "completed", "phase", "status", "rival_index", "rival_commands",
		"serial", "next_army", "next_unit", "factions", "provinces", "armies", "units",
		"casualties", "trace"]) or not CampaignRoster.values_only(s):
		return "Malformed strategic state."
	if not _integer(s.round, 1, c.round_limit) or not _integer(s.completed, 0, c.round_limit) \
			or s.phase not in ["player", "complete"] or s.status not in ["active", "victory", "defeat"] \
			or s.rival_index != 0 or s.rival_commands != 0:
		return "Impossible phase/counters or rival boundary."
	if (s.status == "active" and (s.phase != "player" or s.completed != s.round - 1)) \
			or (s.status != "active" and s.phase != "complete"):
		return "Inconsistent round boundary."
	for key in ["serial", "next_army", "next_unit"]:
		if not _integer(s[key], 0 if key == "serial" else 1, 1000000):
			return "Impossible allocation counter."
	for key in ["factions", "provinces", "armies", "units", "casualties"]:
		if not s[key] is Dictionary:
			return "Invalid state collection."
	if not _keys(s.factions, c.factions.keys()) or not _keys(s.provinces, c.provinces.keys()):
		return "Wrong faction/province identities."
	var maximum_income := 0
	for p in c.provinces.values():
		maximum_income += p.income
	for b in c.buildings.values():
		if b.effect == "income":
			maximum_income += b.value * c.factions.size()
	for id in s.factions:
		var f: Variant = s.factions[id]
		if not _keys(f, ["gold", "service", "services"]) \
				or not _integer(f.gold, 0, c.factions[id].gold + maximum_income * s.completed) \
				or not _integer(f.service, 0, s.round) or not f.services is Array:
			return "Impossible treasury/service budget."
	for id in s.provinces:
		var p: Variant = s.provinces[id]
		if not _keys(p, ["owner", "buildings"]) or not p.owner is String \
				or (p.owner != "" and not c.factions.has(p.owner)) or not p.buildings is Dictionary:
			return "Invalid control or buildings."
		var turns: Array = []
		for building in p.buildings:
			if id not in c.factions.values().map(func(f: Dictionary) -> String: return f.home) \
					or not c.buildings.has(building) or not _integer(p.buildings[building], 1, s.round) \
					or p.buildings[building] in turns:
				return "Invalid building or service turn."
			turns.append(p.buildings[building])
			for required in c.buildings[building].requires:
				if not p.buildings.has(required) or p.buildings[required] >= p.buildings[building]:
					return "Invalid prerequisite chronology."
	var occupied: Array = []
	var army_counts: Dictionary = {}
	for id in s.armies:
		var a: Variant = s.armies[id]
		if not _keys(a, ["faction", "province", "moves", "formed_round"]) \
				or not c.factions.has(a.faction) \
				or not s.provinces.has(a.province) or s.provinces[a.province].owner != a.faction \
				or a.province in occupied or not _integer(a.moves, 0, 1) \
				or not _integer(a.formed_round, 0, s.round) \
				or (a.formed_round == s.round and a.moves != 0):
			return "Invalid army ownership, position or budget."
		if c.armies.has(id):
			if a.faction != c.armies[id].get("faction") or a.formed_round != 0:
				return "Changed army faction."
		elif not _allocated(id, "formed-", s.next_army) or a.formed_round == 0:
			return "Unknown army identity."
		army_counts[a.faction] = army_counts.get(a.faction, 0) + 1
		if army_counts[a.faction] > c.army_limit:
			return "Too many field armies."
		occupied.append(a.province)
	var containers: Dictionary = {}
	var opening: Dictionary = {}
	for u in c.units:
		opening[u.id] = u
	var recruits: Array = []
	for collection in [s.units, s.casualties]:
		for id in collection:
			var u: Variant = collection[id]
			if not _keys(u, ["id", "def", "faction", "army", "province", "life", "moved"]) \
					or id != u.id or not c.definitions.has(u.def) \
					or not u.faction is String or (u.faction != "" and not c.factions.has(u.faction)) \
					or not u.moved is bool or not u.army is String or not u.province is String \
					or not _integer(u.life, 0,
						c.definitions[u.def].get("life_base", c.definitions[u.def].life)):
				return "Invalid unit values."
			if opening.has(id):
				if u.def != opening[id].def or u.faction != opening[id].faction:
					return "Changed opening identity."
			elif not _allocated(id, "recruited-", s.next_unit) or not c.recruits.has(u.def):
				return "Unknown recruit identity."
			else:
				recruits.append(id)
			if u.life == 0:
				if not s.casualties.has(id) or s.units.has(id) or u.army != "" or u.province != "":
					return "Casualty cannot deploy."
				continue
			if s.casualties.has(id) or not s.provinces.has(u.province) \
					or s.provinces[u.province].owner != u.faction:
				return "Duplicate identity or invalid troop control."
			var container: String = "garrison:" + u.province
			var cap: int = c.garrison_cap
			if u.army != "":
				if not s.armies.has(u.army) or s.armies[u.army].faction != u.faction \
						or s.armies[u.army].province != u.province \
						or (u.moved and s.armies[u.army].moves != 0):
					return "Troop does not belong to exactly one co-located army/garrison."
				container = u.army
				cap = c.army_cap
			containers[container] = containers.get(container, 0) + 1
			if containers[container] > cap:
				return "Over-capacity roster."
	for id in s.armies:
		if not containers.has(id):
			return "Empty army must disband."
	for id in opening:
		if not s.units.has(id) and not s.casualties.has(id):
			return "Missing persistent identity."
	if recruits.size() != s.next_unit - 1:
		return "Missing or duplicate recruit allocation."
	var services_error := _services_error(c, s, maximum_income)
	if services_error != "":
		return services_error
	var expected := "active"
	if s.provinces[c.factions[c.player].home].owner != c.player:
		expected = "defeat"
	elif s.provinces[c.objective].owner == c.player:
		expected = "victory"
	elif s.completed >= c.round_limit:
		expected = "defeat"
	if s.status != expected or s.completed not in [s.round - 1, s.round] \
			or (s.completed == s.round and s.completed != c.round_limit):
		return "Inconsistent terminal state."
	if not s.trace is Array or s.trace.size() > 20000:
		return "Invalid trace."
	for line in s.trace:
		if not line is String:
			return "Invalid trace line."
	return ""


static func _services_error(c: Dictionary, s: Dictionary, maximum_income: int) -> String:
	var recorded_recruits: Array = []
	for faction in s.factions:
		var f: Dictionary = s.factions[faction]
		var home: String = c.factions[faction].home
		var buildings: Dictionary = s.provinces[home].buildings
		var built: Array = []
		var last := 0
		var paid := 0
		for record in f.services:
			if not _keys(record, ["round", "op", "id"]) \
					or not _integer(record.round, last + 1, s.round) or not record.id is String:
				return "Invalid paid service chronology."
			last = record.round
			match record.op:
				"build":
					if not buildings.has(record.id) or buildings[record.id] != record.round \
							or record.id in built:
						return "Building lacks its paid service."
					built.append(record.id)
					paid += c.buildings[record.id].cost
				"recruit":
					var u: Dictionary = s.units.get(record.id, s.casualties.get(record.id, {}))
					if u.is_empty() or u.faction != faction or not c.recruits.has(u.def) \
							or record.id in recorded_recruits or not record.id.begins_with("recruited-"):
						return "Invalid paid recruit identity."
					var recruit: Dictionary = c.recruits[u.def]
					if recruit.requires != "" and (not buildings.has(recruit.requires) \
							or buildings[recruit.requires] >= record.round):
						return "Recruit predates its unlock."
					recorded_recruits.append(record.id)
					paid += recruit.cost
				"recover":
					if record.id != "":
						return "Invalid recovery service."
					paid += c.recovery_cost
				_:
					return "Unknown service."
		if last != f.service or built.size() != buildings.size() \
				or f.gold > c.factions[faction].gold + maximum_income * s.completed - paid:
			return "Inconsistent service counter, building ledger or paid treasury."
	if recorded_recruits.size() != s.next_unit - 1:
		return "Recruit lacks a paid service."
	return ""


static func _allocated(id: String, prefix: String, next: int) -> bool:
	if not id.begins_with(prefix):
		return false
	var suffix := id.trim_prefix(prefix)
	return suffix.is_valid_int() and str(int(suffix)) == suffix and int(suffix) > 0 \
		and int(suffix) < next
