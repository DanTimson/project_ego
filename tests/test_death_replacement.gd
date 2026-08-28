extends SceneTree

## CX-016 profile-qualified Genesis death-replacement acceptance coverage.

var failures := 0


func _check(ok: bool, label: String, detail: Variant = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", label,
		(" — " + str(detail)) if detail != "" else ""])
	if not ok:
		failures += 1


func _definition(name: String, life: int) -> Dictionary:
	return {"name": name, "tier": 1, "life_base": life,
		"stamina_base": 7, "morale_base": 9, "ammo_base": 3,
		"speed": 2, "modifiers": []}


func _provider(pack: String = "balance_mod", compatibility: String = "genesis",
		missing: Array = [], malformed: Array = []) -> ScenarioContentProvider:
	var definitions: Dictionary = {}
	for source in [21, 37, 56, 65]:
		if missing.has(source):
			continue
		var definition := _definition("modified-%d" % source, 100 + source)
		if malformed.has(source):
			definition["modifiers"] = ["malformed"]
		definitions["%s:unit/%d" % [pack, source]] = definition
	return ScenarioContentProvider.new(pack, definitions, "", "", "", {},
		compatibility)


func _marker() -> Status:
	var effect := Status.new()
	effect.id = "synthetic Genesis marker"
	effect.modifiers.append(Modifier.make(
		GenesisDeathReplacementResolver.GENESIS_REPLACEMENT_MARKER,
		&"noop", Modifier.Hook.STAT_PASSIVE))
	return effect


func _victim(tier: int = 1) -> Combatant:
	var unit := Combatant.new()
	unit.name = "victim"
	unit.instance_id = "victim"
	unit.tier = tier
	unit.life = 0
	unit.life_base = 10
	unit.alive = false
	unit.statuses.append(_marker())
	return unit


func _lifecycle(unit: Combatant, resolver: GenesisDeathReplacementResolver) -> Dictionary:
	var field := Battlefield.new(3, 3)
	field.place(unit, Battlefield.offset_to_axial(1, 1))
	var left := RoundLoop.Side.new()
	left.id = 0
	left.name = "left"
	left.units = [unit]
	var right := RoundLoop.Side.new()
	right.id = 1
	right.name = "right"
	right.units = []
	return DeathLifecycle.resolve(unit, field, [left, right],
		Callable(resolver, "decision_for"))


func _test_fixed_mapping_and_modded_pack() -> void:
	print("\n[A/B] fixed mapping and modified compatible pack")
	_check([GenesisDeathReplacementResolver.source_record_for_tier(1),
		GenesisDeathReplacementResolver.source_record_for_tier(2),
		GenesisDeathReplacementResolver.source_record_for_tier(3),
		GenesisDeathReplacementResolver.source_record_for_tier(4)] == [21, 37, 56, 65],
		"dedicated resolver owns exact Genesis mapping")
	_check(GenesisDeathReplacementResolver.source_record_for_tier(0) == -1,
		"invalid tier fails explicit lookup")
	var resolver := GenesisDeathReplacementResolver.new("genesis", _provider())
	_check(resolver.configuration_error == "", "strict compatible preflight succeeds")
	var decision := resolver.decision_for(_victim(1))
	_check(decision.status == "resolved" and decision.definition_id == 21,
		"tier 1 resolves source record 21")
	_check(decision.definition.content_id == "balance_mod:unit/21"
		and decision.definition.name == "modified-21",
		"arbitrary pack id returns modified canonical definition")
	var unit := _victim(1)
	var result := _lifecycle(unit, resolver)
	_check(result.branch == "replaced" and unit.life == 121
		and unit.content_id == "balance_mod:unit/21",
		"generic lifecycle restores selected modified definition")


func _test_collision_independence_and_override() -> void:
	print("\n[C/D] numeric collision, rules independence, explicit override")
	var collision := _provider("unrelated", "unspecified")
	var mismatch := GenesisDeathReplacementResolver.new("genesis", collision)
	_check(mismatch.configuration_error.contains("Genesis-compatible"),
		"Genesis rules reject non-compatible numeric collision")
	var native := GenesisDeathReplacementResolver.new("native", collision)
	_check(native.decision_for(_victim()).status == "not_applicable",
		"native rules ignore equal source numbers")
	var native_genesis := GenesisDeathReplacementResolver.new("native", _provider())
	_check(native_genesis.decision_for(_victim()).status == "not_applicable",
		"Genesis-compatible content does not activate native rules")
	var override := GenesisDeathReplacementResolver.new("genesis",
		_provider("odd_name", "new_horizons"), "genesis")
	var state := override.normalized_state()
	_check(state.compatibility_override and state.compatibility_source == "load_override",
		"explicit override is normalized and observable")
	_check(override.decision_for(_victim(4)).definition_id == 65,
		"override retains fixed mapping")


func _test_strict_and_permissive() -> void:
	print("\n[E/F] strict validation and permissive incomplete content")
	var missing := GenesisDeathReplacementResolver.new(
		"genesis", _provider("partial", "genesis", [56]))
	_check(missing.configuration_error != ""
		and missing.diagnostics.any(func(d): return d.get("source_record") == 56),
		"strict preflight validates all targets and fails closed")
	var malformed := GenesisDeathReplacementResolver.new(
		"genesis", _provider("bad", "genesis", [], [37]))
	_check(malformed.configuration_error != ""
		and malformed.diagnostics.any(func(d): return d.get("source_record") == 37),
		"malformed target fails strict preflight")
	var permissive := GenesisDeathReplacementResolver.new(
		"genesis", _provider("partial", "genesis", [56]), "", "permissive")
	_check(permissive.configuration_error == ""
		and permissive.diagnostics.any(func(d): return d.get("source_record") == 56),
		"permissive retains durable missing-target diagnostic")
	_check(permissive.decision_for(_victim(1)).status == "resolved",
		"present tier remains resolvable")
	var unrelated := _victim(3)
	unrelated.statuses.clear()
	_check(permissive.decision_for(unrelated).status == "not_applicable",
		"unrelated path remains usable")
	var invalid := _lifecycle(_victim(3), permissive)
	_check(invalid.branch == "invalid_replacement"
		and String(invalid.error).contains("source record 56"),
		"missing tier fails explicitly only when exercised")
	_check(permissive.decision_for(_victim(5)).status == "unresolved",
		"applicable invalid tier fails explicitly")


func _scenario_spec() -> Dictionary:
	return {"name": "replacement composition", "profile": "genesis", "seed": 1,
		"battlefield": {"width": 2, "height": 1},
		"sides": [
			{"id": 0, "units": [{"name": "actor", "at": [0, 0]}]},
			{"id": 1, "units": [{"name": "target", "at": [1, 0]}]},
		], "commands": []}


func _test_scenario_composition_root() -> void:
	print("\n[integration] Scenario strict/permissive composition root")
	var mismatch := Scenario.new(_scenario_spec(), null,
		_provider("collision", "unspecified"))
	_check(mismatch.construction_error.contains("Genesis-compatible")
		and mismatch.field == null,
		"strict mismatch fails before battle construction")
	var strict := Scenario.new(_scenario_spec(), null, _provider())
	_check(strict.construction_error == ""
		and strict.death_replacement_state.content_compatibility == "genesis",
		"strict compatible Scenario validates all targets")
	var missing := Scenario.new(_scenario_spec(), null,
		_provider("partial", "genesis", [65]))
	_check(missing.construction_error != "" and missing.field == null,
		"strict missing target fails before commands")
	var permissive_spec := _scenario_spec()
	permissive_spec["death_replacement_load_mode"] = "permissive"
	var permissive := Scenario.new(permissive_spec, null,
		_provider("partial", "genesis", [65]))
	permissive.cmd_rest(permissive.units["actor"])
	_check(permissive.construction_error == "" and permissive.units["actor"].resting,
		"permissive missing target preserves unrelated battle operation")
	var override_spec := _scenario_spec()
	override_spec["content_compatibility_override"] = "genesis"
	var overridden := Scenario.new(override_spec, null,
		_provider("odd", "new_horizons"))
	_check(overridden.construction_error == ""
		and overridden.death_replacement_state.compatibility_override,
		"Scenario exposes explicit compatibility override")


func _init() -> void:
	_test_fixed_mapping_and_modded_pack()
	_test_collision_independence_and_override()
	_test_strict_and_permissive()
	_test_scenario_composition_root()
	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(0 if failures == 0 else 1)
