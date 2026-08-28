extends SceneTree

## DELIB-0004 production action-definition composition acceptance cells.

var failures := 0


func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		(" — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1


func _unit(name: String) -> Dictionary:
	return {"name": name, "life": 20, "attack": 6, "counter_attack": 3,
		"defence": 1, "stamina": 10, "morale": 10, "speed": 3}


func _provider(pack: String, overlay: Dictionary) -> ScenarioContentProvider:
	return ScenarioContentProvider.new(pack, {
		"%s:unit/1" % pack: _unit("Actor"),
		"%s:unit/2" % pack: _unit("Target"),
	}, "v1", "", "", overlay)


func _spec(provider: ScenarioContentProvider, profile: String = "native") -> Dictionary:
	return {"name": "composition", "profile": profile, "seed": 3,
		"death_replacement_load_mode": "permissive",
		"content": {"pack": provider.pack_id, "version": "v1"},
		"battlefield": {"width": 3, "height": 2},
		"sides": [
			{"id": 0, "units": [{"id": "actor",
				"def": "%s:unit/1" % provider.pack_id, "at": [0, 0]}]},
			{"id": 1, "units": [{"id": "target",
				"def": "%s:unit/2" % provider.pack_id, "at": [1, 0]}]},
		], "commands": []}


func _novel(source_id: int, name: String = "Novel") -> Dictionary:
	return {"source_id": source_id, "name": name, "target": "enemy_melee"}


func _has_property(value: Object, property_name: StringName) -> bool:
	for property in value.get_property_list():
		if StringName(property["name"]) == property_name:
			return true
	return false


func _test_provider_identity_and_isolation() -> void:
	var one := _provider("one", {"definitions": [_novel(7)], "grants": {
		"one:unit/1": [{"source_id": 7}]}})
	var two := _provider("two", {"definitions": [_novel(8)], "grants": {
		"two:unit/1": [{"source_id": 8}]}})
	var a := Scenario.new(_spec(one), null, one)
	var b := Scenario.new(_spec(two), null, two)
	_check(a.catalogue.size() == 1 and a.catalogue.has(&"one:action/7"),
		"injected provider supplies the visible production set", str(a.catalogue.keys()))
	_check(b.catalogue.has(&"two:action/8") and not b.catalogue.has(&"one:action/7"),
		"sequential providers cannot leak definitions")
	_check(a.unit_catalogues["actor"].has(&"one:action/7"),
		"resolved unit grant owns command availability")
	a.cmd_action(a.units["target"], "one:action/7", a.units["actor"])
	_check(a.log[-1].ends_with("action is not granted"),
		"command availability refuses a definition not granted to that unit")

	var shared := one.compose_actions("genesis")
	_check(shared["source_map"][59] == "crushing_blow"
		and ActionRecipeResolver.resolve(shared["definitions"][&"crushing_blow"]).supported,
		"accepted shared binding retains canonical recipe identity")
	var raw_dispatch := Scenario.new(_spec(one, "genesis"), null, one)
	raw_dispatch.cmd_action(raw_dispatch.units["actor"], "59", raw_dispatch.units["target"])
	_check(raw_dispatch.log[-1] == "unknown action '59'",
		"raw source identity never dispatches a recipe")
	_check(shared["source_map"][7] == "one:action/7"
		and not ActionRecipeResolver.resolve(shared["definitions"][&"one:action/7"]).supported,
		"novel action is namespaced and valid without a recipe")
	var other_same := _provider("other", {"definitions": [_novel(7)]})
	_check(other_same.compose_actions("native")["source_map"][7] == "other:action/7",
		"same local novel identity is distinct in another pack")


func _test_grant_overrides() -> void:
	var overlay := {"definitions": [{"source_id": 700, "name": "Novel",
		"target": "enemy_melee", "magnitude": 2}], "grants": {
		"alpha:unit/1": [{"source_id": 700, "overrides": {"magnitude": 9}}],
		"alpha:unit/2": [{"source_id": 700}],
	}}
	var provider := _provider("alpha", overlay)
	var sc := Scenario.new(_spec(provider), null, provider)
	var shared: Action = sc.catalogue[&"alpha:action/700"]
	var first: Action = sc.unit_catalogues["actor"][&"alpha:action/700"]
	var second: Action = sc.unit_catalogues["target"][&"alpha:action/700"]
	_check(shared.magnitude == 2 and second.magnitude == 2 and first.magnitude == 9,
		"allowed magnitude override is isolated per grant")
	_check(first != second and first != shared,
		"resolved grants never alias their shared definition")
	var forbidden := overlay.duplicate(true)
	forbidden["grants"]["alpha:unit/1"][0]["overrides"] = {"cost_stamina": 0}
	var rejected := ActionDefinitionComposer.compose("alpha", "native", forbidden)
	_check(not rejected["ok"]
		and rejected["diagnostics"][0]["code"] == "forbidden_override",
		"forbidden grant override fails strict composition")


func _test_strict_permissive() -> void:
	var cases := {
		"malformed_binding": {"definitions": [_novel(1), {"source_id": "bad"}]},
		"missing_binding": {"definitions": [_novel(1)], "required_source_ids": [99]},
		"identity_collision": {"definitions": [_novel(1), {
			"source_id": 2, "name": "Collision", "canonical_id": "alpha:action/1"},
			_novel(3, "Unrelated collision survivor")]},
		"unresolved_grant": {"definitions": [_novel(1)], "grants": {
			"alpha:unit/1": [{"source_id": 99}]}}
	}
	for expected_code in cases:
		var strict := ActionDefinitionComposer.compose(
			"alpha", "native", cases[expected_code], ActionDefinitionComposer.STRICT)
		var permissive := ActionDefinitionComposer.compose(
			"alpha", "native", cases[expected_code], ActionDefinitionComposer.PERMISSIVE)
		var strict_codes: Array = strict["diagnostics"].map(func(d): return d["code"])
		var permissive_codes: Array = permissive["diagnostics"].map(func(d): return d["code"])
		_check(not strict["ok"] and strict_codes.has(expected_code),
			"strict fails closed for %s" % expected_code)
		_check(permissive["ok"] and permissive_codes.has(expected_code),
			"permissive retains durable %s diagnostic" % expected_code)
		_check(not permissive["definitions"].is_empty(),
			"permissive %s preserves unrelated valid content" % expected_code)

	var provider := _provider("alpha", cases["unresolved_grant"])
	var spec := _spec(provider)
	spec["action_load_mode"] = "permissive"
	var sc := Scenario.new(spec, null, provider)
	sc.cmd_action(sc.units["actor"], "alpha:action/99", sc.units["target"])
	_check(sc.log.any(func(line): return "unresolved action grant" in line),
		"permissive unresolved invocation explicitly refuses", str(sc.log))
	sc.cmd_rest(sc.units["target"])
	_check(sc.units["target"].resting,
		"permissive diagnostics preserve unrelated valid runtime operation")


func _test_profile_and_legacy_inheritance() -> void:
	var provider := _provider("legacy", {"definitions": [_novel(700)]})
	var genesis := provider.compose_actions("genesis")
	var native := provider.compose_actions("native")
	var nh := provider.compose_actions("new_horizons")
	_check(genesis["source_map"][59] == "crushing_blow"
		and not native["source_map"].has(59) and not nh["source_map"].has(59),
		"Genesis stock binding is profile-qualified")
	_check(genesis["source_map"][700] == "legacy:action/700"
		and genesis["definitions"].size() == 3,
		"overlay adds novel identity without reproducing stock profile")

	# Synthetic legacy .var-shaped tables: no EGO actions manifest is present.
	var pack := ContentPack.new("legacy")
	pack.version = "v1"
	pack.tables = {
		"unit": {1: {"index": 1, "Name": "Legacy actor", "Life": 20,
			"Attack": 6, "CounterAttack": 3, "Defence": 1, "Stamina": 10,
			"Morale": 10, "Speed": 3, "Abilityes": [{"ref": 1}]}},
		"unit_upg": {1: {"index": 1, "Name": "Tracked grant",
			"Upg Type": 388, "Quantity": 7}},
		"ability_num": {1: {"index": 1, "Number": 388, "Name": "Tracked action"}},
	}
	var registry := AbilityRegistry.new()
	Handlers.register_all(registry)
	var db := ContentDb.new(pack, registry, pack.report(registry))
	var spec := {"name": "legacy", "profile": "genesis", "seed": 1,
		"death_replacement_load_mode": "permissive",
		"content": {"pack": "legacy", "version": "v1"},
		"battlefield": {"width": 2, "height": 1}, "sides": [
			{"id": 0, "units": [{"id": "legacy-1", "def": "legacy:unit/1",
				"at": [0, 0]}]},
			{"id": 1, "units": [{"id": "dummy", "name": "Dummy",
				"life": 10, "at": [1, 0]}]}], "commands": []}
	var sc := Scenario.new(spec, null, db)
	_check(sc.construction_error == ""
		and sc.unit_catalogues["legacy-1"][&"shield_bash"].magnitude == 7
		and sc.catalogue[&"shield_bash"].magnitude == 0,
		"legacy source grant inherits stock definition and explicit magnitude path",
		sc.construction_error)


func _test_malformed_legacy_action_quantities() -> void:
	for bad_quantity in ["bad", [7]]:
		var pack := ContentPack.new("legacy")
		pack.version = "v1"
		pack.tables = {
			"unit": {1: {"index": 1, "Name": "Legacy actor", "Life": 20,
					"Attack": 6, "CounterAttack": 3, "Defence": 1, "Stamina": 10,
					"Morale": 10, "Speed": 3, "Abilityes": [{"ref": 1}]}},
			"unit_upg": {1: {"index": 1, "Name": "Malformed grant",
					"Upg Type": 388, "Quantity": bad_quantity}},
			"ability_num": {1: {"index": 1, "Number": 388, "Name": "Tracked action"}},
		}
		var registry := AbilityRegistry.new()
		Handlers.register_all(registry)
		var db := ContentDb.new(pack, registry, pack.report(registry))
		var spec := {"name": "legacy", "profile": "genesis", "seed": 1,
		"death_replacement_load_mode": "permissive",
				"content": {"pack": "legacy", "version": "v1"},
				"battlefield": {"width": 2, "height": 1}, "sides": [
					{"id": 0, "units": [{"id": "legacy-1", "def": "legacy:unit/1",
							"at": [0, 0]}]},
					{"id": 1, "units": [{"id": "dummy", "name": "Dummy",
							"life": 10, "at": [1, 0]}]}], "commands": []}

		var strict_sc := Scenario.new(spec.duplicate(true), null, db)
		_check(strict_sc.construction_error != ""
				and strict_sc.field == null and strict_sc.units.is_empty(),
				"malformed legacy action Quantity fails strict construction")

		var permissive_spec := spec.duplicate(true)
		permissive_spec["action_load_mode"] = "permissive"
		var permissive_sc := Scenario.new(permissive_spec, null, db)
		_check(permissive_sc.construction_error == ""
				and permissive_sc.action_diagnostics.any(
					func(d): return d.get("code") == "malformed_grant")
				and not permissive_sc.unit_catalogues["legacy-1"].has(&"shield_bash")
				and permissive_sc.action_refusals["legacy-1"].has("shield_bash"),
				"malformed legacy action Quantity remains unresolved action grant",
				permissive_sc.construction_error)
		permissive_sc.cmd_action(
				permissive_sc.units["legacy-1"], "shield_bash",
				permissive_sc.units["dummy"])
		_check(permissive_sc.log.any(
				func(line): return "unresolved action grant" in line),
				"malformed action grant refuses explicitly")
		permissive_sc.cmd_rest(permissive_sc.units["dummy"])
		_check(permissive_sc.units["dummy"].resting,
				"malformed action grant preserves unrelated permissive runtime")


func _test_provider_cx013_end_to_end() -> void:
	var provider := _provider("alpha", {"grants": {"alpha:unit/1": [
		{"source_id": 59},
		{"source_id": 388, "overrides": {"magnitude": 4}},
	]}})
	var crushing := Scenario.new(_spec(provider, "genesis"), null, provider)
	var crushing_target: Combatant = crushing.units["target"]
	crushing.cmd_action(crushing.units["actor"], "crushing_blow", crushing_target)
	_check(crushing_target.life < crushing_target.life_base
		and crushing.log.any(func(line): return "resolved plan [AttackOp]" in line),
		"provider-composed Crushing Blow preserves CX-013 execution")
	var shield := Scenario.new(_spec(provider, "genesis"), null, provider)
	var shield_target: Combatant = shield.units["target"]
	var before_life := shield_target.life
	var before_stamina := shield_target.stamina
	shield.cmd_action(shield.units["actor"], "shield_bash", shield_target)
	_check(shield_target.life == before_life
		and shield_target.stamina == before_stamina - 4
		and shield.log.any(func(line): return "resolved plan [ResourceDeltaOp]" in line),
		"provider-composed Shield Bash preserves drain-only structure")

	var invalid := _provider("bad", {"definitions": [{"source_id": "bad"}]})
	var failed := Scenario.new(_spec(invalid), null, invalid)
	_check("action composition failed" in failed.construction_error
		and failed.field == null and failed.units.is_empty(),
		"strict Scenario composition fails closed before runtime state")


func _test_recipe_refusal_and_cl1() -> void:
	var provider := _provider("alpha", {"definitions": [_novel(700)], "grants": {
		"alpha:unit/1": [{"source_id": 700}]}})
	var sc := Scenario.new(_spec(provider), null, provider)
	sc.cmd_action(sc.units["actor"], "alpha:action/700", sc.units["target"])
	_check(sc.log[-1] == "Actor(actor): action alpha:action/700 is known but unsupported",
		"valid novel action gains no synthesized semantics", sc.log[-1])
	var parsed := Action.from_dict({"id": "x", "name": "X",
		"suppresses_counterattack": true})
	_check(not _has_property(parsed, &"suppresses_counterattack"),
		"CL-1 field is absent and legacy serialized key is inert")


func _init() -> void:
	_test_provider_identity_and_isolation()
	_test_grant_overrides()
	_test_strict_permissive()
	_test_profile_and_legacy_inheritance()
	_test_provider_cx013_end_to_end()
	_test_recipe_refusal_and_cl1()
	print("\n%s" % ["ALL PASS" if failures == 0 else "%d FAILURES" % failures])
	quit(1 if failures else 0)
