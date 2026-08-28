class_name ModifierSemantic
extends RefCounted

## Closed EGO-owned vocabulary for passive-modifier behavioral queries.
## Source opcodes are translated into these identities only by pack bindings.

enum Query {
	STAMINA_MUTATION_SUPPRESSED,
	MELEE_EXCHANGE_SUPPRESSED,
	MORALE_UNDERFLOW_SUPPRESSED,
}

const NAMES: Dictionary = {
	Query.STAMINA_MUTATION_SUPPRESSED: "stamina.mutation_suppressed",
	Query.MELEE_EXCHANGE_SUPPRESSED: "combat.melee_exchange_suppressed",
	Query.MORALE_UNDERFLOW_SUPPRESSED: "morale.underflow_suppressed",
}
const BY_NAME: Dictionary = {
	"stamina.mutation_suppressed": Query.STAMINA_MUTATION_SUPPRESSED,
	"combat.melee_exchange_suppressed": Query.MELEE_EXCHANGE_SUPPRESSED,
	"morale.underflow_suppressed": Query.MORALE_UNDERFLOW_SUPPRESSED,
}


static func parse_names(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false, "semantics": [],
			"reason": "modifier semantics must be an array"}
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return {"ok": false, "semantics": [],
				"reason": "modifier semantic values must be names"}
	return parse(value)


static func parse(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false, "semantics": [],
			"reason": "modifier semantics must be an array"}
	var parsed: Array[int] = []
	for raw in value:
		var query: int
		if typeof(raw) == TYPE_INT and NAMES.has(int(raw)):
			query = int(raw)
		elif typeof(raw) == TYPE_STRING:
			var normalized := String(raw).strip_edges().to_lower()
			if not BY_NAME.has(normalized):
				return {"ok": false, "semantics": [],
					"reason": "unknown modifier semantic '%s'" % normalized}
			query = int(BY_NAME[normalized])
		else:
			return {"ok": false, "semantics": [],
				"reason": "modifier semantic values must be names"}
		if not parsed.has(query):
			parsed.append(query)
	parsed.sort()
	return {"ok": true, "semantics": parsed, "reason": ""}


static func names(values: Variant) -> Array[String]:
	var parsed := parse(values)
	if not bool(parsed["ok"]):
		return []
	var out: Array[String] = []
	for query in parsed["semantics"]:
		out.append(String(NAMES[int(query)]))
	return out
