extends SceneTree

## CX-014 declarative data-defined action plan acceptance cells A-F.

var failures := 0


func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		(" — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1


func _has_property(value: Object, property_name: StringName) -> bool:
	for property in value.get_property_list():
		if StringName(property["name"]) == property_name:
			return true
	return false


func _unit(name: String) -> Dictionary:
	return {"name": name, "life": 40, "life_base": 40, "attack": 9,
		"counter_attack": 0, "defence": 3, "stamina": 10,
		"stamina_base": 10, "morale": 10, "speed": 3}


func _provider(pack: String, overlay: Dictionary,
		target_override: Dictionary = {}) -> ScenarioContentProvider:
	var target := _unit("Target")
	target.merge(target_override, true)
	return ScenarioContentProvider.new(pack, {
		"%s:unit/1" % pack: _unit("Actor"),
		"%s:unit/2" % pack: target,
	}, "v1", "", "", overlay)


func _spec(provider: ScenarioContentProvider, profile: String = "native",
		mode: String = "strict") -> Dictionary:
	var out := {"name": "cx014", "profile": profile, "seed": 7,
		"content": {"pack": provider.pack_id, "version": "v1"},
		"battlefield": {"width": 3, "height": 2},
		"sides": [
			{"id": 0, "units": [{"id": "actor",
				"def": "%s:unit/1" % provider.pack_id, "at": [0, 0]}]},
			{"id": 1, "units": [{"id": "target",
				"def": "%s:unit/2" % provider.pack_id, "at": [1, 0]}]},
		], "commands": []}
	if mode != "strict":
		out["action_load_mode"] = mode
	return out


func _attack_recipe(numerator: int = 3, denominator: int = 2) -> Dictionary:
	return {"version": 1, "operations": [{"kind": "attack", "mode": "melee",
		"scale": {"numerator": numerator, "denominator": denominator}}]}


func _fixed_drain(amount: int = -3) -> Dictionary:
	return {"version": 1, "operations": [{"kind": "resource_delta",
		"target": "selected_enemy", "resource": "stamina", "amount": amount}]}


func _magnitude_drain() -> Dictionary:
	return {"version": 1, "operations": [{"kind": "resource_delta",
		"target": "selected_enemy", "resource": "stamina",
		"amount": {"source": "action_magnitude", "sign": "negative"}}]}


func _definition(source_id: int, recipe: Variant, name: String = "Localized",
		magnitude: int = 0) -> Dictionary:
	var out := {"source_id": source_id, "name": name,
		"target": "enemy_melee", "magnitude": magnitude}
	if recipe != null:
		out["recipe"] = recipe
	return out


func _overlay(definitions: Array, grants: Array) -> Dictionary:
	return {"definitions": definitions, "grants": {"alpha:unit/1": grants}}


func _contains(lines: Array, text: String) -> bool:
	for line in lines:
		if text in String(line):
			return true
	return false


func _test_attack_plan_and_identity() -> void:
	var overlay := _overlay([_definition(700, _attack_recipe(), "First locale")],
		[{"source_id": 700}])
	var provider := _provider("alpha", overlay)
	var composed := provider.compose_actions("native")
	var action: Action = composed["definitions"][&"alpha:action/700"]
	var first := ActionRecipeResolver.resolve(action)
	action.name = "Completely different locale"
	action.source_id = 999
	var second := ActionRecipeResolver.resolve(action)
	var first_op: ActionExecutionPlan.AttackOp = first.plan.operations()[0]
	var second_op: ActionExecutionPlan.AttackOp = second.plan.operations()[0]
	_check(first.supported and second.supported
		and first.plan != second.plan and first_op != second_op,
		"declarative resolution produces fresh typed plans")
	_check(first_op.mode == ActionExecutionPlan.AttackMode.MELEE
		and first_op.initiating_attack_scale_numerator == 3
		and first_op.initiating_attack_scale_denominator == 2,
		"declarative melee compiles to existing exact AttackOp")
	var recipe_copy := action.declarative_recipe()
	recipe_copy["operations"][0]["numerator"] = 99
	_check(action.declarative_recipe()["operations"][0]["numerator"] == 3,
		"resolved recipe context cannot mutate shared definition")

	var battle := Scenario.new(_spec(provider), null, provider)
	battle.cmd_action(battle.units["actor"], "700", battle.units["target"])
	_check(battle.log[-1] == "unknown action '700'",
		"raw source id cannot invoke declarative recipe")
	battle.cmd_action(battle.units["actor"], "alpha:action/700", battle.units["target"])
	_check(_contains(battle.log, "resolved plan [AttackOp]")
		and _contains(battle.log, "initiating attack scale 3/2")
		and battle.units["target"].life < 40,
		"pack action executes scale through shared melee path")


func _test_resource_paths() -> void:
	var fixed_provider := _provider("alpha", _overlay(
		[_definition(701, _fixed_drain(-3))], [{"source_id": 701}]))
	var fixed := Scenario.new(_spec(fixed_provider), null, fixed_provider)
	fixed.cmd_action(fixed.units["actor"], "alpha:action/701", fixed.units["target"])
	_check(fixed.units["target"].stamina == 7
		and fixed.units["target"].life == 40
		and not _contains(fixed.log, " hits ")
		and not _contains(fixed.log, " counters"),
		"fixed declarative drain uses ResourceDeltaOp without damage chain")

	var magnitude_overlay := _overlay(
		[_definition(702, _magnitude_drain(), "Magnitude", 2)],
		[{"source_id": 702, "overrides": {"magnitude": 5}}])
	var magnitude_provider := _provider("alpha", magnitude_overlay)
	var magnitude := Scenario.new(_spec(magnitude_provider), null, magnitude_provider)
	var shared: Action = magnitude.catalogue[&"alpha:action/702"]
	var granted: Action = magnitude.unit_catalogues["actor"][&"alpha:action/702"]
	magnitude.cmd_action(magnitude.units["actor"], "alpha:action/702",
		magnitude.units["target"])
	_check(shared.magnitude == 2 and granted.magnitude == 5
		and magnitude.units["target"].stamina == 5,
		"per-unit magnitude compiles only that unit's negative magnitude")
	_check(shared.declarative_recipe() == granted.declarative_recipe(),
		"grant override does not rewrite shared recipe")

	var protected_provider := _provider("alpha", magnitude_overlay, {"modifiers": [{
		"ability": 0x12, "handler": "grant_flag", "power": 1,
		"params": {"flag": "cx014-0x12"}}]})
	var protected := Scenario.new(_spec(protected_provider), null, protected_provider)
	protected.cmd_action(protected.units["actor"], "alpha:action/702",
		protected.units["target"])
	_check(protected.units["target"].stamina == 10
		and _contains(protected.log, "modifier 0x12 stamina mutation suppression"),
		"effective target 0x12 remains authoritative for declarative drain")


func _test_ordered_plan() -> void:
	var ordered := {"version": 1, "operations": [
		{"kind": "resource_delta", "target": "selected_enemy",
			"resource": "stamina", "amount": -1},
		{"kind": "resource_delta", "target": "selected_enemy",
			"resource": "stamina", "amount": -2},
		{"kind": "attack", "mode": "melee",
			"scale": {"numerator": 1, "denominator": 1}},
	]}
	var provider := _provider("alpha", _overlay(
		[_definition(703, ordered)], [{"source_id": 703}]))
	var battle := Scenario.new(_spec(provider), null, provider)
	battle.cmd_action(battle.units["actor"], "alpha:action/703", battle.units["target"])
	var seen: Array[String] = []
	for line in battle.log:
		if "  [action] operation " in line:
			seen.append("AttackOp" if "AttackOp" in line else "ResourceDeltaOp")
	_check(seen == ["ResourceDeltaOp", "ResourceDeltaOp", "AttackOp"]
		and battle.units["target"].stamina == 7
		and battle.units["target"].alive,
		"two drains then final attack execute in declared non-fatal order", str(seen))


func _invalid_recipes() -> Dictionary:
	return {
		"unknown operation": {"version": 1, "operations": [{"kind": "teleport"}]},
		"invalid ratio": _attack_recipe(3, 0),
		"positive delta": _fixed_drain(1),
		"two attacks": {"version": 1, "operations": [
			{"kind": "attack", "mode": "melee",
				"scale": {"numerator": 1, "denominator": 1}},
			{"kind": "attack", "mode": "melee",
				"scale": {"numerator": 1, "denominator": 1}}]},
		"after attack": {"version": 1, "operations": [
			{"kind": "attack", "mode": "melee",
				"scale": {"numerator": 1, "denominator": 1}},
			{"kind": "resource_delta", "target": "selected_enemy",
				"resource": "stamina", "amount": -1}]},
		"empty": {"version": 1, "operations": []},
	}


func _test_strict_permissive_and_order_rejections() -> void:
	for label in _invalid_recipes():
		var overlay := _overlay([
			_definition(710, _invalid_recipes()[label], "Invalid"),
			_definition(711, _fixed_drain(-2), "Unrelated")],
			[{"source_id": 710}, {"source_id": 711}])
		var strict := ActionDefinitionComposer.compose(
			"alpha", "native", overlay, ActionDefinitionComposer.STRICT)
		_check(not strict["ok"] and strict["diagnostics"].any(
			func(d): return d.get("code") == "invalid_declarative_recipe"),
			"strict rejects %s" % label)
		var permissive := ActionDefinitionComposer.compose(
			"alpha", "native", overlay, ActionDefinitionComposer.PERMISSIVE)
		_check(permissive["ok"] and permissive["definitions"].has(&"alpha:action/710")
			and permissive["definitions"].has(&"alpha:action/711"),
			"permissive retains invalid diagnostic and unrelated action for %s" % label)
		var provider := _provider("alpha", overlay)
		var battle := Scenario.new(_spec(provider, "native", "permissive"), null, provider)
		var actor: Combatant = battle.units["actor"]
		var target: Combatant = battle.units["target"]
		var before := [actor.stamina, actor.action_spent, target.life, target.stamina]
		battle.cmd_action(actor, "alpha:action/710", target)
		_check("invalid declarative recipe" in battle.log[-1]
			and [actor.stamina, actor.action_spent, target.life, target.stamina] == before,
			"invalid %s refuses before payment with no partial execution" % label)
		battle.cmd_action(actor, "alpha:action/711", target)
		_check(target.stamina == int(before[3]) - 2,
			"unrelated valid action remains operational for %s" % label)


func _test_shared_precedence() -> void:
	var attempted := _definition(59,
		{"version": 1, "operations": [{"kind": "unknown"}]}, "Attempt")
	attempted["shared_id"] = "crushing_blow"
	attempted["replace"] = true
	var overlay := _overlay([attempted, _definition(720, _fixed_drain(-1))],
		[{"source_id": 59}, {"source_id": 720}])
	var strict := ActionDefinitionComposer.compose(
		"alpha", "genesis", overlay, ActionDefinitionComposer.STRICT)
	var permissive := ActionDefinitionComposer.compose(
		"alpha", "genesis", overlay, ActionDefinitionComposer.PERMISSIVE)
	var crushing: Action = permissive["definitions"][&"crushing_blow"]
	var resolution := ActionRecipeResolver.resolve(crushing)
	_check(not strict["ok"] and strict["diagnostics"].any(
		func(d): return d.get("code") == "shared_recipe_override"),
		"shared engine recipe override fails strict with specific diagnostic")
	_check(not crushing.has_declarative_recipe() and resolution.supported
		and resolution.plan.operations()[0] is ActionExecutionPlan.AttackOp,
		"permissive shared override retains engine AttackOp recipe")
	var provider := _provider("alpha", overlay)
	var battle := Scenario.new(_spec(provider, "genesis", "permissive"), null, provider)
	battle.cmd_action(battle.units["actor"], "crushing_blow", battle.units["target"])
	_check(_contains(battle.log, "crushing_blow resolved plan [AttackOp]")
		and battle.units["target"].life < 40,
		"shared invocation executes engine recipe, never attempted declarative data")
	var unrelated := Scenario.new(
		_spec(provider, "genesis", "permissive"), null, provider)
	unrelated.cmd_action(unrelated.units["actor"], "alpha:action/720",
		unrelated.units["target"])
	_check(unrelated.units["target"].stamina == 9,
		"shared override diagnostic preserves unrelated permissive action")


func _test_pack_isolation_and_existing_boundaries() -> void:
	var one := _provider("one", {"definitions": [
		_definition(730, _fixed_drain(-1), "One")]})
	var two := _provider("two", {"definitions": [
		_definition(730, _fixed_drain(-4), "Two")]})
	var a1: Action = one.compose_actions("native")["definitions"][&"one:action/730"]
	var a2: Action = two.compose_actions("native")["definitions"][&"two:action/730"]
	var amount_one: int = ActionRecipeResolver.resolve(a1).plan.operations()[0].amount
	var amount_two: int = ActionRecipeResolver.resolve(a2).plan.operations()[0].amount
	a1.name = "Translated"
	_check(amount_one == -1 and amount_two == -4
		and ActionRecipeResolver.resolve(a1).plan.operations()[0].amount == -1,
		"same local id stays pack-isolated and display-name independent")
	var theft := _definition(731, _fixed_drain(-1))
	theft["canonical_id"] = "two:action/731"
	var stolen := ActionDefinitionComposer.compose("one", "native",
		{"definitions": [theft]}, ActionDefinitionComposer.PERMISSIVE)
	_check(not stolen["definitions"].has(&"two:action/731")
		and not stolen["diagnostics"].is_empty(),
		"one pack cannot attach a recipe to another pack identity")

	var unsupported_ids := ["extra_shot", "power_shot", "whirlwind", "frenzy",
		"turtle", "forced_march", "sniper_shot", "healing", "repair",
		"gather_ammo", "carrion_eater", "strike_and_return"]
	var all_unsupported := true
	for action_id in unsupported_ids:
		var action := Action.from_dict({"id": action_id, "name": action_id})
		all_unsupported = all_unsupported and not ActionRecipeResolver.resolve(action).supported
	var sample_attack := ActionExecutionPlan.AttackOp.new(
		ActionExecutionPlan.AttackMode.MELEE, 1, 1)
	_check(all_unsupported and unsupported_ids.size() == 12,
		"other twelve reference actions remain unsupported")
	_check(not _has_property(Action.new(), &"suppresses_counterattack")
		and not _has_property(sample_attack, &"suppresses_counterattack"),
		"no action or operation counterattack suppression field exists")


func _init() -> void:
	_test_attack_plan_and_identity()
	_test_resource_paths()
	_test_ordered_plan()
	_test_strict_permissive_and_order_rejections()
	_test_shared_precedence()
	_test_pack_isolation_and_existing_boundaries()
	print("\n%s" % ["ALL PASS" if failures == 0 else "%d FAILURES" % failures])
	quit(1 if failures else 0)
