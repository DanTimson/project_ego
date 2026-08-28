extends SceneTree

## CX-017 tranche-1 semantic modifier boundary acceptance coverage.

var failures := 0


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1


func _make(query: ModifierSemantic.Query, hook: Modifier.Hook = Modifier.Hook.STAT_PASSIVE,
		opcode: int = 0) -> Modifier:
	return Modifier.make(opcode, &"noop", hook, 0, {"nested": {"value": 1}}, "",
		[query])


func _registry() -> AbilityRegistry:
	var registry := AbilityRegistry.new()
	registry.register(&"noop", func(_ctx, value, _params): return value)
	return registry


func _write_binding(pack_id: String, abilities: Dictionary) -> String:
	var directory := "user://cx017".path_join(pack_id)
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("bindings.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"pack": pack_id, "abilities": abilities}))
	file.close()
	return directory


func _test_vocabulary_and_modifier() -> void:
	var parsed := ModifierSemantic.parse([
		"morale.underflow_suppressed", "stamina.mutation_suppressed",
		"morale.underflow_suppressed"])
	_check(bool(parsed["ok"]) and parsed["semantics"] == [
		ModifierSemantic.Query.STAMINA_MUTATION_SUPPRESSED,
		ModifierSemantic.Query.MORALE_UNDERFLOW_SUPPRESSED],
		"semantics validate, deduplicate, and use canonical order")
	var native := Modifier.make(0, &"noop", Modifier.Hook.STAMINA, 0,
		{"nested": {"value": 1}}, "", parsed["semantics"])
	var clone := native.copy()
	clone.semantics.clear()
	clone.params["nested"]["value"] = 2
	_check(native.semantics.size() == 2 and int(native.params["nested"]["value"]) == 1,
		"Modifier copy has no mutable semantic or params alias")
	_check(native.semantic_names() == ["stamina.mutation_suppressed",
		"morale.underflow_suppressed"] and native.ability == 0,
		"native semantic Modifier serializes deterministically without a source opcode")
	_check(not bool(ModifierSemantic.parse(["plugin.opaque"])["ok"]),
		"unknown semantic fails closed")


func _test_bindings() -> void:
	var arbitrary := ContentDb.load_pack("arbitrary", _write_binding("arbitrary", {
		"18": {"handler": "noop", "semantics": [
			"morale.underflow_suppressed", "stamina.mutation_suppressed",
			"stamina.mutation_suppressed"]},
		"19": {"handler": "noop"},
		"38": {"handler": "noop", "semantics": ["plugin.opaque"]},
	}), _registry())
	_check(arbitrary.resolve_semantics(18) == [
		ModifierSemantic.Query.STAMINA_MUTATION_SUPPRESSED,
		ModifierSemantic.Query.MORALE_UNDERFLOW_SUPPRESSED],
		"binding semantics parse independently from handler")
	_check(arbitrary.resolve_semantics(19).is_empty(),
		"numeric opcode with no metadata has no semantics")
	_check(arbitrary.pack.binding(38) == null
		and arbitrary.report.errors.any(func(error):
			return "unknown modifier semantic" in String(error)),
		"unknown binding semantic rejects the binding with a diagnostic")

	var collision := ContentDb.load_pack("genesis", _write_binding("genesis", {
		"18": {"handler": "noop"}, "19": {"handler": "noop"},
		"38": {"handler": "noop"},
	}), _registry(), {}, "genesis")
	_check(collision.resolve_semantics(18).is_empty()
		and collision.resolve_semantics(19).is_empty()
		and collision.resolve_semantics(38).is_empty(),
		"pack id, compatibility, and numeric coincidence grant no semantics")

	var legacy := ContentDb.load_pack("legacy", _write_binding("legacy", {
		"18": {"handler": "noop", "hook": "STAMINA",
			"semantics": ["stamina.mutation_suppressed"]},
	}), _registry())
	legacy.pack.tables = {
		"unit": {1: {"index": 1, "Name": "Bound", "Abilityes": [1]}},
		"unit_upg": {1: {"index": 1, "Name": "Legacy", "Upg Type": 18,
			"Quantity": 0}},
		"ability_num": {1: {"index": 1, "Number": 18, "Name": "Legacy"}},
	}
	var built := Roster.new(legacy).build("legacy:unit/1")
	var runtime: Modifier = built.unit.modifiers[0]
	_check(built.complete() and runtime.ability == 18
		and runtime.has_semantic(ModifierSemantic.Query.STAMINA_MUTATION_SUPPRESSED),
		"Roster propagates only explicit binding semantics to runtime Modifier")


func _test_stamina() -> void:
	var protected := Combatant.new()
	protected.stamina = 3
	protected.stamina_base = 10
	protected.speed = 3
	protected.movement_remaining = 3
	protected.modifiers.append(_make(
		ModifierSemantic.Query.STAMINA_MUTATION_SUPPRESSED, Modifier.Hook.STAMINA))
	ActionPoints.spend_move(protected, 1, 2)
	_check(protected.stamina == 3, "semantic stamina suppression preserves mutation")
	_check(is_equal_approx(Stamina.modifier(protected)[0], 0.7),
		"stamina suppression does not suppress low-stamina penalties")

	var raw := Combatant.new()
	raw.stamina = 3
	raw.stamina_base = 10
	raw.speed = 3
	raw.movement_remaining = 3
	raw.modifiers.append(Modifier.make(18, &"noop", Modifier.Hook.STAMINA))
	ActionPoints.spend_move(raw, 1, 2)
	_check(raw.stamina == 1, "raw-18-only normalized Modifier has no stamina authority")


func _test_melee() -> void:
	var protected := Combatant.new()
	protected.attack = 7
	protected.counter_attack = 7
	protected.ranged_attack = 7
	protected.morale = 10
	var semantic_modifier := _make(
		ModifierSemantic.Query.MELEE_EXCHANGE_SUPPRESSED,
		Modifier.Hook.DAMAGE_VS_TARGET)
	Damage.bind_environment(func(unit: Combatant) -> Array:
		return [semantic_modifier] if unit == protected else [])
	var melee: float = Damage.current_attack(protected, Combatant.AttackKind.MELEE)[0]
	var counter: float = Damage.current_attack(protected, Combatant.AttackKind.COUNTER)[0]
	var ranged: float = Damage.current_attack(protected, Combatant.AttackKind.RANGED)[0]
	Damage.bind_environment(Callable())
	_check(melee == 0 and counter == 0 and ranged == 7,
		"melee semantic covers environment provider without broadening to ranged")
	var raw := Combatant.new()
	raw.attack = 7
	raw.morale = 10
	raw.modifiers.append(Modifier.make(38, &"noop", Modifier.Hook.DAMAGE_VS_TARGET))
	_check(Damage.current_attack(raw, Combatant.AttackKind.MELEE)[0] == 7,
		"raw-38-only normalized Modifier has no melee authority")


func _test_morale() -> void:
	var protected := Combatant.new()
	protected.morale = 0
	protected.modifiers.append(_make(
		ModifierSemantic.Query.MORALE_UNDERFLOW_SUPPRESSED, Modifier.Hook.MORALE))
	_check(not Damage.adjust_morale(protected, -2)
		and protected.morale == 0 and protected.morale_break_accumulator == 0,
		"semantic morale-underflow suppression preserves the narrow sink")
	_check(is_equal_approx(Morale.modifier(protected)[0], 0.4),
		"underflow semantic is not broad morale-stat immunity")
	var raw := Combatant.new()
	raw.morale = 0
	raw.modifiers.append(Modifier.make(19, &"noop", Modifier.Hook.MORALE))
	_check(Damage.adjust_morale(raw, -2)
		and raw.morale_break_accumulator == 20,
		"raw-19-only normalized Modifier has no morale authority")


func _init() -> void:
	print("\n[CX-017] semantic modifier boundary")
	_test_vocabulary_and_modifier()
	_test_bindings()
	_test_stamina()
	_test_melee()
	_test_morale()
	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures else 0)
