extends RefCounted


## Project-authored native design; no recovered strategic values or save format.
static func definition() -> Dictionary:
	return {
		"id": "ego-six-provinces-v1",
		"rules": "native-strategy-cx028-v1",
		"opening_gold": 12,
		"turn_limit": 12,
		"living_cap": 4,
		"recovery_cost": 8,
		"recovery_life": 6,
		"recruit_cost": 10,
		"recruit_def": "campaign:unit/3",
		"definitions":
		{
			"campaign:unit/1": {"name": "Vanguard", "life": 20, "attack": 30},
			"campaign:unit/2": {"name": "Scout", "life": 4, "attack": 3, "speed": 2},
			"campaign:unit/3": {"name": "Home Guard", "life": 20, "attack": 18},
		},
		"opening":
		[
			{"id": "azure-vanguard", "def": "campaign:unit/1"},
			{"id": "azure-scout", "def": "campaign:unit/2"},
		],
		"deployment": [[0, 0], [1, 1], [0, 1], [0, 2]],
		"battlefield": {"width": 4, "height": 3},
		"provinces":
		{
			"home": {"name": "Home", "links": ["ford", "quarry"], "income": 3},
			"ford":
			{
				"name": "Ford",
				"links": ["home", "watchpost"],
				"income": 4,
				"seed": 42,
				"enemies": [_guard("ford", 8, 6)]
			},
			"quarry":
			{
				"name": "Quarry",
				"links": ["home", "mill"],
				"income": 4,
				"seed": 42,
				"enemies": [_guard("quarry", 8, 6)]
			},
			"watchpost":
			{
				"name": "Watchpost",
				"links": ["ford", "keep"],
				"income": 5,
				"seed": 43,
				"enemies": [_guard("watchpost", 8, 2)]
			},
			"mill":
			{
				"name": "Mill",
				"links": ["quarry", "keep"],
				"income": 5,
				"seed": 43,
				"enemies": [_guard("mill", 8, 2)]
			},
			"keep":
			{
				"name": "Keep",
				"links": ["watchpost", "mill"],
				"income": 8,
				"seed": 44,
				"enemies": [_guard("keep", 10, 3)]
			},
		},
	}


static func _guard(province: String, life: int, attack: int) -> Dictionary:
	return {
		"id": province + ":guard",
		"name": province.capitalize() + " Guard",
		"at": [1, 0],
		"life": life,
		"attack": attack,
		"counter_attack": attack,
		"flags": ["Первый удар"]
	}
