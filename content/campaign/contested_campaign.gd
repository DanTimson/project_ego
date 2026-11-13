extends RefCounted

const Native = preload("res://content/campaign/native_campaign.gd")


## Project-authored CX-033 balance. No original strategic compatibility claim.
static func definition() -> Dictionary:
	var native := Native.definition()
	return {
		"id": "ego-contested-six-v1", "rules": "native-contested-cx033-v1",
		"player": "azure", "objective": "keep", "seed": 42, "round_limit": 12,
		"army_limit": 2, "army_cap": 2, "garrison_cap": 2,
		"battlefield": {"width": 4, "height": 3},
		"deployment": [[[0, 0], [0, 1], [0, 2], [1, 2]],
			[[1, 0], [2, 1], [3, 0], [3, 2]]],
		"recovery_cost": native.recovery_cost, "recovery_life": native.recovery_life,
		"recruit_def": native.recruit_def, "recruits": native.recruits,
		"buildings": native.buildings,
		"definitions": _definitions(native),
		"factions": {
			"azure": {"name": "Azure", "home": "home", "gold": 12},
			"crimson": {"name": "Crimson", "home": "keep", "gold": 0},
		},
		"policy": {"commands": 8, "enemy": 30, "neutral": 20,
			"objective": 50, "advance": 10, "hold": 0},
		"provinces": {
			"home": _province("Home", ["ford", "quarry"], "azure", 3, [0.12, 0.5]),
			"ford": _province("Ford", ["home", "watchpost"], "", 4, [0.38, 0.24]),
			"quarry": _province("Quarry", ["home", "mill"], "", 4, [0.38, 0.76]),
			"watchpost": _province("Watchpost", ["ford", "keep"], "crimson", 5, [0.65, 0.24]),
			"mill": _province("Mill", ["quarry", "keep"], "crimson", 5, [0.65, 0.76]),
			"keep": _province("Keep", ["watchpost", "mill"], "crimson", 8, [0.88, 0.5]),
		},
		"armies": {
			"azure-first": {"faction": "azure", "province": "home", "moves": 1},
			"crimson-first": {"faction": "crimson", "province": "watchpost", "moves": 1},
			"crimson-second": {"faction": "crimson", "province": "mill", "moves": 1},
		},
		"units": [
			_member("azure-vanguard", "campaign:unit/1", "azure", "azure-first", "home"),
			_member("azure-guard", "campaign:unit/3", "azure", "", "home"),
			_member("crimson-raider", "campaign:unit/7", "crimson", "crimson-first", "watchpost"),
			_member("crimson-patrol", "campaign:unit/7", "crimson", "crimson-second", "mill"),
			_member("crimson-capital", "campaign:unit/8", "crimson", "", "keep"),
		],
	}


static func _definitions(native: Dictionary) -> Dictionary:
	var definitions: Dictionary = native.definitions.duplicate(true)
	definitions["campaign:unit/7"] = {"name": "Raider", "life": 8, "attack": 3}
	definitions["campaign:unit/8"] = {"name": "Capital Guard", "life": 10, "attack": 3}
	return definitions


## A separately authored five-node graph, different identities and opening forces.
static func alternate() -> Dictionary:
	var result := definition()
	result.id = "ego-contested-coast-v1"
	result.objective = "port"
	result.factions.azure.home = "haven"
	result.factions.crimson.home = "port"
	result.provinces = {
		"haven": _province("Haven", ["orchard", "salt"], "azure", 3, [0.12, 0.5]),
		"orchard": _province("Orchard", ["haven", "tower"], "", 4, [0.36, 0.2]),
		"salt": _province("Salt Flats", ["haven", "tower", "port"], "", 2, [0.4, 0.8]),
		"tower": _province("Tower", ["orchard", "salt", "port"], "crimson", 4, [0.64, 0.3]),
		"port": _province("Port", ["tower", "salt"], "crimson", 6, [0.88, 0.55]),
	}
	result.armies = {
		"coast-company": {"faction": "azure", "province": "haven", "moves": 1},
		"coast-raiders": {"faction": "crimson", "province": "tower", "moves": 1},
	}
	result.units = [
		_member("coast-vanguard", "campaign:unit/1", "azure", "coast-company", "haven"),
		_member("coast-guard", "campaign:unit/3", "azure", "", "haven"),
		_member("coast-raider", "campaign:unit/7", "crimson", "coast-raiders", "tower"),
		_member("port-guard", "campaign:unit/8", "crimson", "", "port"),
	]
	return result


static func _province(title: String, links: Array, owner: String, income: int,
		point: Array) -> Dictionary:
	return {"name": title, "links": links, "owner": owner, "income": income, "point": point}


static func _member(id: String, type: String, faction: String, army: String,
		province: String) -> Dictionary:
	return {"id": id, "def": type, "faction": faction, "army": army, "province": province}
