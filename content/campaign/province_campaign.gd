extends RefCounted

const Contested = preload("res://content/campaign/contested_campaign.gd")


## Authored native balance, separate from the CX-033 Eador UI observations.
static func definition(coast := false) -> Dictionary:
	var c := Contested.alternate() if coast else Contested.definition()
	c.id = "ego-province-coast-v1" if coast else "ego-province-six-v1"
	c.rules = "native-province-cx034-v1"
	c.round_limit = 40
	c["province_rules"] = {
		"explore": 50,
		"capture_loss": 30,
		"recovery": 10,
		"stability": [[0, 50], [50, 75], [80, 100]],
		"xp": 5,
		"levels": [0, 5, 15],
		"level_attack": 3,
		"policy": {"explore": 80, "site": 90, "travel": 20, "service": 10}
	}
	c["heroes"] = {
		"warden": {"name": "Warden", "def": "campaign:unit/9", "gold": 8, "crystals": 2},
		"ranger": {"name": "Ranger", "def": "campaign:unit/10", "gold": 8, "crystals": 2}
	}
	c.definitions["campaign:unit/9"] = {"name": "Warden", "life": 24, "attack": 16, "defence": 2}
	c.definitions["campaign:unit/10"] = {
		"name": "Ranger",
		"life": 18,
		"attack": 10,
		"ranged_attack": 12,
		"shooting_range": 4,
		"ammo": 3,
		"ammo_base": 3
	}
	var definition_number := 12
	for role in c.heroes:
		c.heroes[role]["faction_defs"] = {}
		for faction in c.factions:
			var identity := "campaign:unit/%d" % definition_number
			definition_number += 1
			c.definitions[identity] = c.definitions[c.heroes[role].def].duplicate(true)
			c.heroes[role].faction_defs[faction] = identity
	c["equipment"] = {
		"steel":
		{
			"name": "Steel blade",
			"slot": "hand",
			"stat": "attack",
			"value": 4,
			"gold": 4,
			"crystals": 1
		},
		"mail":
		{"name": "Mail", "slot": "body", "stat": "defence", "value": 2, "gold": 4, "crystals": 1}
	}
	c.buildings["farm"] = {
		"name": "Crystal farm", "cost": 6, "requires": [], "effect": "income", "value": 3
	}
	c.definitions["campaign:unit/11"] = {"name": "Village Guard", "life": 20, "attack": 18}
	c.recruits["campaign:unit/11"] = {"cost": 6, "requires": "outpost", "crystals": 1}
	c.buildings["outpost"] = {
		"name": "Local mustering yard",
		"cost": 8,
		"requires": ["farm"],
		"effect": "recruit",
		"value": "campaign:unit/11"
	}
	for id in c.buildings:
		c.buildings[id]["district"] = "province" if id in ["farm", "outpost"] else "capital"
		c.buildings[id]["crystals"] = 1 if id in ["farm", "outpost"] else 0
		c.buildings[id]["terrains"] = ["Woodland"] if id in ["farm", "outpost"] else ["Plains"]
		c.buildings[id]["crystal_yield"] = 1 if id == "farm" else 0
	for id in c.factions:
		c.factions[id]["crystals"] = 0
	for id in c.provinces:
		var p: Dictionary = c.provinces[id]
		var capital: bool = (
			id in c.factions.values().map(func(f: Dictionary) -> String: return f.home)
		)
		p["terrain"] = "Plains" if capital else "Woodland"
		p["tier"] = "capital" if capital else "village"
		p["stability"] = 100
		p["crystals"] = 1 if capital else 0
		p["resource"] = {"name": "Crystal seam", "threshold": 50, "gold": 2, "crystals": 1}
		p["site"] = {
			"name": "Old ruin",
			"threshold": 50,
			"guards": ["campaign:unit/8"],
			"reward": {"gold": 12, "crystals": 4},
			"tribute": {"gold": 3, "crystals": 1}
		}
		p["tribute"] = {"gold": 5, "crystals": 1}
	# A defended neutral destination supplies the separate negotiation route.
	var neutral: String = "orchard" if coast else "quarry"
	c.units.append(
		{
			"id": "neutral-guard",
			"def": "campaign:unit/8",
			"faction": "",
			"army": "",
			"province": neutral
		}
	)
	return c
