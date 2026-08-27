class_name DeclarativeActionRecipe
extends RefCounted

## Composition-time validator and fresh-plan compiler for the CX-014 v1 safe
## declarative subset. This is data parsing, not a gameplay executor or legacy
## opcode interpreter.


static func _is_int_value(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT
		and is_finite(float(value)) and float(value) == floor(float(value)))


static func _exact_keys(value: Dictionary, expected: Dictionary,
		where: String) -> String:
	var unknown: Array[String] = []
	var missing: Array[String] = []
	for key in value:
		if not expected.has(String(key)):
			unknown.append(String(key))
	for key in expected:
		if not value.has(key):
			missing.append(String(key))
	unknown.sort()
	missing.sort()
	if not unknown.is_empty():
		return "%s has unknown fields: %s" % [where, ", ".join(unknown)]
	if not missing.is_empty():
		return "%s is missing fields: %s" % [where, ", ".join(missing)]
	return ""


static func validate(raw: Variant, action_magnitude: int) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {"ok": false, "error": "recipe must be an object"}
	var recipe_raw: Dictionary = raw
	var error := _exact_keys(recipe_raw,
		{"version": true, "operations": true}, "recipe")
	if error != "":
		return {"ok": false, "error": error}
	if not _is_int_value(recipe_raw["version"]) or int(recipe_raw["version"]) != 1:
		return {"ok": false, "error": "recipe version must be integer 1"}
	if typeof(recipe_raw["operations"]) != TYPE_ARRAY:
		return {"ok": false, "error": "recipe operations must be a list"}
	var operations_raw: Array = recipe_raw["operations"]
	if operations_raw.is_empty():
		return {"ok": false, "error": "recipe operation list must not be empty"}

	var operations: Array = []
	var attack_seen := false
	for index in operations_raw.size():
		var operation_v: Variant = operations_raw[index]
		var where := "recipe operation %d" % index
		if typeof(operation_v) != TYPE_DICTIONARY:
			return {"ok": false, "error": "%s must be an object" % where}
		var operation: Dictionary = operation_v
		var kind: Variant = operation.get("kind")
		if kind == "attack":
			error = _exact_keys(operation,
				{"kind": true, "mode": true, "scale": true}, where)
			if error != "":
				return {"ok": false, "error": error}
			if attack_seen:
				return {"ok": false,
					"error": "recipe permits at most one attack operation"}
			if index != operations_raw.size() - 1:
				return {"ok": false, "error": "attack operation must be final"}
			if operation["mode"] != "melee":
				return {"ok": false, "error": "%s supports melee mode only" % where}
			if typeof(operation["scale"]) != TYPE_DICTIONARY:
				return {"ok": false, "error": "%s scale must be an object" % where}
			var scale: Dictionary = operation["scale"]
			error = _exact_keys(scale,
				{"numerator": true, "denominator": true}, "%s scale" % where)
			if error != "":
				return {"ok": false, "error": error}
			if not _is_int_value(scale["numerator"]) 					or not _is_int_value(scale["denominator"]) 					or int(scale["numerator"]) <= 0 					or int(scale["denominator"]) <= 0:
				return {"ok": false, "error": (
					"%s scale numerator and denominator must be positive integers" % where)}
			operations.append({"kind": "attack",
				"numerator": int(scale["numerator"]),
				"denominator": int(scale["denominator"])})
			attack_seen = true
		elif kind == "resource_delta":
			error = _exact_keys(operation, {"kind": true, "target": true,
				"resource": true, "amount": true}, where)
			if error != "":
				return {"ok": false, "error": error}
			if attack_seen:
				return {"ok": false,
					"error": "operation after attack is not permitted"}
			if operation["target"] != "selected_enemy":
				return {"ok": false,
					"error": "%s supports selected_enemy only" % where}
			if operation["resource"] != "stamina":
				return {"ok": false, "error": "%s supports stamina only" % where}
			var amount: Variant = operation["amount"]
			if _is_int_value(amount):
				if int(amount) > 0:
					return {"ok": false,
						"error": "%s amount must be non-positive" % where}
				operations.append({"kind": "resource_delta",
					"amount_kind": "fixed", "amount": int(amount)})
			elif typeof(amount) == TYPE_DICTIONARY:
				var amount_dict: Dictionary = amount
				error = _exact_keys(amount_dict,
					{"source": true, "sign": true}, "%s amount" % where)
				if error != "":
					return {"ok": false, "error": error}
				if amount_dict.get("source") != "action_magnitude" 						or amount_dict.get("sign") != "negative":
					return {"ok": false,
						"error": "%s amount must be negative action_magnitude" % where}
				if action_magnitude < 0:
					return {"ok": false, "error": (
						"%s resolved action magnitude must be non-negative" % where)}
				operations.append({"kind": "resource_delta",
					"amount_kind": "negative_action_magnitude"})
			else:
				return {"ok": false, "error": (
					"%s amount must be a non-positive integer or negative action_magnitude" % where)}
		else:
			return {"ok": false, "error": (
				"%s has unknown operation kind '%s'" % [where, str(kind)])}
	return {"ok": true, "recipe": {
		"version": 1, "operations": operations}.duplicate(true), "error": ""}


static func uses_action_magnitude(recipe: Dictionary) -> bool:
	for operation in recipe.get("operations", []):
		if operation.get("kind") == "resource_delta" 				and operation.get("amount_kind") == "negative_action_magnitude":
			return true
	return false


static func compile(recipe: Dictionary, action_magnitude: int) -> Dictionary:
	## The normalized recipe is copied on Action access. Build all operations in
	## local storage before exposing a plan, so compilation cannot be partial.
	var operations: Array = []
	for recipe_operation in recipe.get("operations", []):
		if recipe_operation.get("kind") == "attack":
			operations.append(ActionExecutionPlan.AttackOp.new(
				ActionExecutionPlan.AttackMode.MELEE,
				int(recipe_operation["numerator"]),
				int(recipe_operation["denominator"])))
		elif recipe_operation.get("kind") == "resource_delta":
			var amount := int(recipe_operation.get("amount", 0))
			if recipe_operation.get("amount_kind") == "negative_action_magnitude":
				amount = -action_magnitude
			if amount > 0:
				return {"ok": false,
					"error": "resolved declarative stamina delta would be positive"}
			operations.append(ActionExecutionPlan.ResourceDeltaOp.new(
				ActionExecutionPlan.OperationTarget.SELECTED_ENEMY,
				ActionExecutionPlan.ResourceKind.STAMINA, amount))
		else:
			return {"ok": false, "error": "invalid normalized recipe operation"}
	if operations.is_empty():
		return {"ok": false, "error": "invalid empty normalized recipe"}
	return {"ok": true, "plan": ActionExecutionPlan.new(operations), "error": ""}
