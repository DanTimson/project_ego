extends RefCounted

## Public synthetic presentation-only action grant; standalone JSON stays portable.
const ACTION_ID := &"tactical_demo:action/1"


static func provider_for(spec: Dictionary) -> ScenarioContentProvider:
	var definition_id := "tactical_demo:unit/1"
	for side in spec["sides"]:
		for index in side["units"].size():
			var unit: Dictionary = side["units"][index]
			if unit.get("id") != "azure-vanguard-01":
				continue
			var definition := unit.duplicate(true)
			definition.erase("id")
			definition.erase("at")
			side["units"][index] = {
				"id": unit["id"], "def": definition_id, "at": unit["at"]}
			spec["content"] = {"pack": "tactical_demo", "version": "v1"}
			return ScenarioContentProvider.new("tactical_demo", {
				definition_id: definition}, "v1", "", "", {
				"definitions": [{"source_id": 1, "name": "Stamina Drain",
					"target": "enemy_melee", "recipe": {"version": 1,
						"operations": [{"kind": "resource_delta",
							"target": "selected_enemy", "resource": "stamina", "amount": -3}]}}],
				"grants": {definition_id: [{"source_id": 1}]}})
	return null


static func setup_opening_restriction(scenario: Scenario) -> String:
	return scenario.setup_opening_restriction("azure-ranger-17", Status.from_dict({
		"id": "tactical_demo:tangled_bowstring", "name": "Tangled Bowstring",
		"restrictions": ["ranged"],
	}))
