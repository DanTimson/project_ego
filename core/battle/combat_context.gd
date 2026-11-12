class_name CombatContext
extends RefCounted

## Services owned by one battle, passed explicitly through rules and exchanges.
## Environment lookup stays live; no ambient current battle or provider cache.
var pipeline: Pipeline
var environment: Callable
var fatal_resolver: Callable


func _init(p_pipeline: Pipeline = null, p_environment: Callable = Callable(),
		p_fatal_resolver: Callable = Callable()) -> void:
	pipeline = p_pipeline
	environment = p_environment
	fatal_resolver = p_fatal_resolver


## Represented generic stat providers, kept separate by source collection.
## Tactical auras are not commander/squad providers. That channel is evidence-held:
## future eligibility must exclude battle-owned/nonpersistent tactical units.
func stat_contributions(unit: Combatant, stat: StringName) -> Dictionary:
	var personal := _stat_delta(unit.modifiers, unit, stat)
	var runtime := 0
	for effect in unit.statuses:
		runtime += _stat_delta(effect.modifiers, unit, stat)
	return {"personal": personal, "runtime": runtime, "commander": 0}


func speed_contribution(unit: Combatant) -> int:
	var terms := stat_contributions(unit, &"speed")
	return int(terms.personal) + int(terms.runtime) + int(terms.commander)


func _stat_delta(modifiers: Array, unit: Combatant, stat: StringName) -> int:
	var represented: Array = []
	for modifier in modifiers:
		if modifier.hook == Modifier.Hook.STAT_PASSIVE and modifier.handler == &"stat_delta":
			represented.append(modifier)
	if pipeline == null:
		return 0
	return int(pipeline.resolve(0, represented, Modifier.Hook.STAT_PASSIVE,
		{"unit": unit, "stat": String(stat)})[0])
