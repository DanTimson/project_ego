extends RefCounted

# gdlint: disable=max-returns
const Base = preload("res://core/campaign/contested_validation.gd")


static func whole(value: Variant, low := 0, high := 1000000) -> bool:
	return value is int and value >= low and value <= high


static func money(value: Variant) -> bool:
	return value is Dictionary and whole(value.get("gold")) and whole(value.get("crystals"))


static func definition_error(c: Dictionary) -> String:
	var error := Base.definition_error(c)
	if error != "":
		return error
	var r: Variant = c.get("province_rules")
	if (
		not r is Dictionary
		or not whole(r.get("explore"), 1, 100)
		or not whole(r.get("capture_loss"), 1, 100)
		or not whole(r.get("recovery"), 1, 100)
		or not whole(r.get("xp"), 1, 100)
		or not whole(r.get("level_attack"), 1, 100)
		or not r.get("levels") is Array
		or r.levels.is_empty()
		or r.levels[0] != 0
		or not r.get("stability") is Array
		or r.stability.is_empty()
		or not r.get("policy") is Dictionary
	):
		return "Invalid province rules."
	var last := -1
	for threshold in r.levels:
		if not whole(threshold, last + 1):
			return "Invalid XP thresholds."
		last = threshold
	last = -1
	for threshold in r.stability:
		if (
			not threshold is Array
			or threshold.size() != 2
			or not whole(threshold[0], last + 1, 100)
			or not whole(threshold[1], 0, 100)
		):
			return "Invalid stability thresholds."
		last = threshold[0]
	if r.stability[0][0] != 0:
		return "Stability must cover zero."
	for op in ["site", "explore", "travel", "service"]:
		if not whole(r.policy.get(op), 0, 1000):
			return "Invalid province policy."
	for faction in c.factions.values():
		if not whole(faction.get("crystals")):
			return "Invalid crystal treasury."
	for p in c.provinces.values():
		if (
			not p.get("terrain") is String
			or p.get("tier") not in ["capital", "village"]
			or not whole(p.get("stability"), 0, 100)
			or not whole(p.get("crystals"), 0, 1000)
		):
			return "Invalid province context."
		for feature in ["resource", "site"]:
			if not p.get(feature) is Dictionary:
				return "Invalid discovery definition."
			if p[feature].is_empty():
				continue
			if (
				not p[feature].get("name") is String
				or not whole(p[feature].get("threshold"), 1, 100)
			):
				return "Invalid discovery threshold."
		if not p.resource.is_empty() and not money(p.resource):
			return "Invalid resource yield."
		if not p.site.is_empty():
			if (
				not p.site.get("guards") is Array
				or p.site.guards.is_empty()
				or p.site.guards.size() > c.garrison_cap
				or not money(p.site.get("reward"))
			):
				return "Invalid site."
			for guard in p.site.guards:
				if not guard is String or not c.definitions.has(guard):
					return "Unknown site guard."
		if (
			(p.site.has("tribute") and not money(p.site.tribute))
			or (p.has("tribute") and not money(p.tribute))
		):
			return "Invalid tribute."

	for b in c.buildings.values():
		if (
			b.get("district") not in ["capital", "province"]
			or not whole(b.get("crystals"))
			or not whole(b.get("crystal_yield"), 0, 100)
		):
			return "Invalid district or facility yield."
		if (
			b.has("terrains")
			and (
				not b.terrains is Array
				or not b.terrains.all(func(t: Variant) -> bool: return t is String)
			)
		):
			return "Invalid terrain eligibility."
	for rct in c.recruits.values():
		if not whole(rct.get("crystals", 0)):
			return "Invalid recruit price."
	if (
		not c.get("heroes") is Dictionary
		or c.heroes.size() < 2
		or not c.get("equipment") is Dictionary
	):
		return "Missing hero/equipment catalogue."
	for h in c.heroes.values():
		if (
			not h is Dictionary
			or not h.get("name") is String
			or not h.get("def") is String
			or not c.definitions.has(h.def)
			or not money(h)
		):
			return "Invalid hero."
	var identities: Array = []
	for h in c.heroes.values():
		if not h.get("faction_defs") is Dictionary or h.faction_defs.size() != c.factions.size():
			return "Missing faction hero definitions."
		for faction in c.factions:
			if (
				not c.definitions.has(h.faction_defs.get(faction))
				or h.faction_defs[faction] in identities
			):
				return "Unknown or shared hero definition."
			identities.append(h.faction_defs[faction])
	for e in c.equipment.values():
		if (
			not e is Dictionary
			or not e.get("name") is String
			or not money(e)
			or e.get("slot") not in ["hand", "body"]
			or e.get("stat") not in ["attack", "defence"]
			or not whole(e.get("value"), 1, 100)
		):
			return "Invalid equipment."
	return Base.state_error(c, ContestedCampaign.opening_state(c))
