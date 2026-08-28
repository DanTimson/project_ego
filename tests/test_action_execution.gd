extends SceneTree

## Independent plan-level and scenario-level coverage for CX-013 typed actions.

var failures := 0


class ZeroRng extends Rng:
	func _init() -> void:
		super(0)

	func roll(_x: int, _stream: StringName = &"combat") -> int:
		return 0


func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1


func _action(action_id: String, magnitude: int = 0,
		display_name: String = "Localized") -> Dictionary:
	if action_id == "extra_shot":
		return {"id": action_id, "source_id": 20, "name": display_name,
			"target": 2, "attack_surcharge": true, "is_attack": true}
	if action_id == "crushing_blow":
		return {"id": action_id, "source_id": 59, "name": display_name,
			"target": 1, "attack_surcharge": true, "is_attack": true,
			"damage_scale": 1.5}
	return {"id": "shield_bash", "source_id": 388, "name": display_name,
		"target": 1, "cost_stamina": 1, "attack_surcharge": true,
		"consumes_action": true, "magnitude": magnitude, "is_attack": true,
		"damage_scale": 0.0, "excluded_targets": ["Бестелесный"]}


func _fighter(unit_name: String, at: Array,
		overrides: Dictionary = {}) -> Dictionary:
	var unit := {
		"name": unit_name, "at": at, "life": 30, "life_base": 30,
		"attack": 9, "counter_attack": 5, "defence": 3,
		"speed": 2, "stamina": 10, "stamina_base": 10, "morale": 10,
	}
	unit.merge(overrides, true)
	return unit


func _run_action(action_id: String = "shield_bash", magnitude: int = 4,
		actor_overrides: Dictionary = {}, target_overrides: Dictionary = {},
		target_at: Array = [2, 1], command_target: Variant = "target",
		allied: bool = false, profile: String = "native") -> Array:
	var actor := _fighter("actor", [1, 1], actor_overrides)
	var target := _fighter("target", target_at, target_overrides)
	var command := {"op": "action", "unit": "actor", "action": action_id}
	if command_target != null:
		command["target"] = command_target
	var friendly_units: Array = [actor]
	if allied:
		friendly_units.append(target)
	var actions: Array = []
	if action_id != "nonesuch":
		actions.append(_action(action_id, magnitude))
	var spec := {
		"name": "typed action vector", "profile": profile, "seed": 19,
		"death_replacement_load_mode": "permissive",
		"battlefield": {"width": 6, "height": 4, "tiles": []},
		"actions": actions,
		"sides": [
			{"id": 0, "is_attacker": true, "leader_initiative": 2,
				"units": friendly_units},
			{"id": 1, "leader_initiative": 1,
				"units": [] if allied else [target]},
		],
		"commands": [command],
	}
	var battle := Scenario.new(spec)
	return [battle, battle.run()]


func _contains(lines: Array, fragment: String) -> bool:
	for line in lines:
		if fragment in String(line):
			return true
	return false


func _count(lines: Array, fragment: String) -> int:
	var total := 0
	for line in lines:
		if fragment in String(line):
			total += 1
	return total


func _has_property(value: Object, property_name: StringName) -> bool:
	for property in value.get_property_list():
		if StringName(property["name"]) == property_name:
			return true
	return false


func _test_integer_scale_and_executor_boundary() -> void:
	print("\n[CX-013 correction] integer scale and plan executor ownership")
	var scaled: Array[int] = []
	for value in [1, 3, 9, 19, -3]:
		scaled.append(Damage.trunc0_ratio(value, 3, 2))
	_check(scaled == [1, 4, 13, 28, -4],
		"integer-only 3/2 scaling truncates signed realistic odd values")

	var plan := ActionExecutionPlan.new([
		ActionExecutionPlan.AttackOp.new(
			ActionExecutionPlan.AttackMode.MELEE, 3, 2),
		ActionExecutionPlan.ResourceDeltaOp.new(
			ActionExecutionPlan.OperationTarget.SELECTED_ENEMY,
			ActionExecutionPlan.ResourceKind.STAMINA, 0),
	])
	var seen: Array[String] = []
	var attack := func(_operation: ActionExecutionPlan.AttackOp) -> Variant:
		seen.append("AttackOp")
		return null
	var drain := func(_operation: ActionExecutionPlan.ResourceDeltaOp) -> Variant:
		seen.append("ResourceDeltaOp")
		return null
	var results := ActionExecutionPlan.Executor.execute(plan, attack, drain)
	_check(seen == ["AttackOp", "ResourceDeltaOp"] and results.size() == 2,
		"typed plan executor owns deterministic ordered operation iteration")
	var resolver := ActionRecipeResolver.new()
	_check(not resolver.has_method("execute")
		and not resolver.has_method("execute_command")
		and not resolver.has_method("prepare"),
		"recipe resolver exposes no validation, payment, or execution surface")


func _test_plan_architecture() -> void:
	print("\n[CX-013 plan] canonical identity resolves fresh immutable typed plans")
	var crushing := Action.from_dict(_action("crushing_blow", 0, "Locale A"))
	var renamed := Action.from_dict(_action("crushing_blow", 0, "Locale B"))
	var r1 := ActionRecipeResolver.resolve(crushing)
	var r2 := ActionRecipeResolver.resolve(renamed)
	var op1 := r1.plan.operations()[0] as ActionExecutionPlan.AttackOp
	var op2 := r2.plan.operations()[0] as ActionExecutionPlan.AttackOp
	_check(r1.supported and r2.supported, "Crushing Blow recipe is supported")
	_check(r1.plan.operations().size() == 1
		and op1.mode == ActionExecutionPlan.AttackMode.MELEE,
		"Crushing Blow is exactly one melee AttackOp")
	_check(op1.initiating_attack_scale_numerator == 3
		and op1.initiating_attack_scale_denominator == 2,
		"initiating scale is the exact rational 3/2")
	_check(not _has_property(op1, &"suppresses_counterattack"),
		"AttackOp carries no speculative counterattack policy")
	var source_catalogue := {crushing.id: crushing}
	_check(crushing.source_id == 59 and renamed.name == "Locale B"
		and Action.canonical_id_for_source(59, source_catalogue)
			== &"crushing_blow",
		"source ID maps to canonical identity; display name is irrelevant")
	_check(r1.plan != r2.plan and op1 != op2,
		"separate resolutions share no plan or operation context")
	var external_operations := r1.plan.operations()
	external_operations.clear()
	_check(r1.plan.operations().size() == 1,
		"callers cannot mutate the plan's ordered operation list")

	var shield := Action.from_dict(_action("shield_bash", 7, "Other locale"))
	var shield_resolution := ActionRecipeResolver.resolve(shield)
	var resource := shield_resolution.plan.operations()[0] as \
		ActionExecutionPlan.ResourceDeltaOp
	_check(shield_resolution.plan.operations().size() == 1
		and resource.target == ActionExecutionPlan.OperationTarget.SELECTED_ENEMY
		and resource.resource == ActionExecutionPlan.ResourceKind.STAMINA
		and resource.amount == -7 and resource.amount <= 0,
		"Shield Bash is exactly one drain-only stamina ResourceDeltaOp")
	_check(shield.source_id == 388 and shield.magnitude == 7,
		"resolution leaves ActionDefinition metadata unchanged")

	var unsupported := ActionRecipeResolver.resolve(
		Action.from_dict(_action("extra_shot")))
	_check(not unsupported.supported and unsupported.plan == null,
		"known unsupported actions produce no executable plan")


func _test_refusals() -> void:
	print("\n[CX-013 refusal] every validation failure is mutation-free")
	var cases: Array = [
		_run_action("nonesuch"),
		_run_action("extra_shot"),
		_run_action("shield_bash", 4, {"stamina": 1}),
		_run_action("shield_bash", 4, {}, {}, [2, 1], null),
		_run_action("shield_bash", 4, {}, {}, [2, 1], "absent"),
		_run_action("shield_bash", 4, {}, {}, [2, 1], "target", true),
		_run_action("shield_bash", 4, {}, {"alive": false, "life": 0}),
		_run_action("shield_bash", 4, {}, {}, [5, 3]),
		_run_action("shield_bash", 4, {}, {"flags": ["Бестелесный"]}),
	]
	for i in cases.size():
		var battle: Scenario = cases[i][0]
		var result: Dictionary = cases[i][1]
		var actor: Combatant = battle.units["actor"]
		var expected_stamina := 1 if i == 2 else 10
		_check(actor.stamina == expected_stamina and not actor.action_spent
			and not _contains(result["log"], " requests action "),
			"refusal %d leaves the actor unchanged" % i)


func _test_crushing_blow() -> void:
	print("\n[CX-013 AttackOp] scale precedes RNG/defence and never leaks")
	var attacker := Combatant.new()
	attacker.name = "a"
	attacker.attack = 9
	attacker.life = 30
	attacker.life_base = 30
	attacker.stamina = 10
	attacker.stamina_base = 10
	attacker.morale = 10
	var defender := Combatant.new()
	defender.name = "d"
	defender.defence = 8
	defender.life = 30
	defender.life_base = 30
	defender.stamina = 10
	defender.stamina_base = 10
	defender.morale = 10
	var scaled := Damage.resolve_attack(attacker, defender,
		Combatant.AttackKind.MELEE, ZeroRng.new(), false, 3, 2)
	# Independent arithmetic: 9 -> trunc0(9*3/2)=13 -> roll 15 -> 8 = 7.
	# Scaling the ordinary final 2 damage would instead produce 3.
	_check(int(scaled[0]) == 7 and int(scaled[0]) != 3,
		"distinguishing vector proves pre-randomisation/pre-defence scaling")

	var executed := _run_action("crushing_blow")
	var battle: Scenario = executed[0]
	var result: Dictionary = executed[1]
	var actor: Combatant = battle.units["actor"]
	var target: Combatant = battle.units["target"]
	_check(actor.stamina == 9 and actor.action_spent,
		"action payment is exact and terminal")
	_check(not _contains(result["log"], "attack stamina mutation"),
		"AttackOp does not pay ordinary attack stamina a second time")
	_check(_count(result["log"], "initiating attack scale 3/2") == 1,
		"scale reaches only the initiating primary")
	_check(_contains(result["log"], "target counters") and not target.action_spent,
		"ordinary unscaled retaliation remains possible and non-terminal")
	var charge_modifier := {"ability": 0x25, "handler": "grant_flag",
		"power": 1, "params": {"flag": "test-0x25"}}
	var charged := _run_action("crushing_blow", 0,
		{"modifiers": [charge_modifier]}, {}, [2, 1], "target", false,
		"genesis")
	_check(_contains(charged[1]["log"], "command-entry charge")
		and _contains(charged[1]["log"], "command-entry charge consumption"),
		"ordinary command-entry charge gate remains active",
		"\n".join(charged[1]["log"]))
	_check(target.damage_received[0] > 0,
		"primary damage reaches the shared received-damage sink")

	var ordinary := Damage.resolve_attack(attacker, defender,
		Combatant.AttackKind.MELEE, ZeroRng.new())
	_check(int(ordinary[0]) == 2,
		"a later ordinary attack has no leaked 3/2 context")

	var gated := _run_action(
		"crushing_blow", 0, {"flags": ["Ловкость"]})
	_check(not _contains(gated[1]["log"], " counters")
		and (gated[0].units["actor"] as Combatant).life == 30,
		"existing no-retaliation gate remains effective")

	var fatal := _run_action("crushing_blow", 0, {},
		{"life": 1, "life_base": 1, "counter_attack": 9})
	var fatal_target: Combatant = fatal[0].units["target"]
	_check(not fatal_target.alive and fatal_target.damage_received[0] > 0
		and _count(fatal[1]["log"], "target falls") == 1,
		"ordinary fatal lifecycle executes once with no survival marker")


func _test_shield_bash() -> void:
	print("\n[CX-013 ResourceDeltaOp] stamina-only with local R11 gate")
	var executed := _run_action(
		"shield_bash", 4, {}, {"flags": ["Первый удар"]})
	var battle: Scenario = executed[0]
	var result: Dictionary = executed[1]
	var actor: Combatant = battle.units["actor"]
	var target: Combatant = battle.units["target"]
	_check(actor.stamina == 8 and actor.action_spent,
		"Shield Bash pays its resolved action cost once and terminates")
	_check(target.stamina == 6 and target.life == 30
		and target.damage_received == [0, 0, 0, 0],
		"target loses magnitude stamina and no life/damage channel")
	_check(not _contains(result["log"], " hits ")
		and not _contains(result["log"], " counters")
		and not _contains(result["log"], "attack randomisation"),
		"Shield Bash bypasses first-strike/melee/on-hit/reaction chain")

	var floor := _run_action("shield_bash", 4, {},
		{"stamina": 2, "stamina_base": 10})
	_check((floor[0].units["target"] as Combatant).stamina == 0,
		"negative target stamina floors at zero")

	var modifier := {"ability": 0x12, "handler": "grant_flag", "power": 1,
		"semantics": ["stamina.mutation_suppressed"], "params": {"flag": "test-0x12"}}
	var immune_target := _run_action("shield_bash", 4, {},
		{"stamina": 7, "modifiers": [modifier]})
	_check((immune_target[0].units["target"] as Combatant).stamina == 7
		and _contains(immune_target[1]["log"],
			"stamina.mutation_suppressed"),
		"effective target modifier 0x12 suppresses only the target delta")

	var aura_immune := _run_action("shield_bash", 4, {
		"auras": [{"id": "effective-0x12", "scope": "ADJACENT",
			"affects": "ENEMY", "modifiers": [modifier]}],
	}, {"stamina": 7})
	var aura_target: Combatant = aura_immune[0].units["target"]
	_check(aura_target.stamina == 7 and not aura_target.has_modifier_id(0x12),
		"battle-contextual effective 0x12 suppresses without raw provider presence")

	var raw := Combatant.new()
	raw.name = "raw"
	raw.stamina = 7
	raw.modifiers.append(Modifier.make(0x12, &"grant_flag",
		Modifier.Hook.STAT_PASSIVE, 1, {"flag": "raw-0x12"}))
	Stamina.apply_tactical_drain(raw, -2, false)
	_check(raw.stamina == 5,
		"drain helper trusts the supplied effective result, not raw membership")

	var immune_actor := _run_action(
		"shield_bash", 4, {"modifiers": [modifier]})
	var protected_actor: Combatant = immune_actor[0].units["actor"]
	_check(protected_actor.stamina == 10 and protected_actor.action_spent,
		"actor 0x12 suppresses payment but not successful terminality")


func _test_scenario_expected_state() -> void:
	print("\n[CX-013 scenario] both supported actions have independent expectations")
	var file := FileAccess.open("res://tests/scenarios/actions.json", FileAccess.READ)
	var spec: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var result := Scenario.new(spec).run()
	_check(result["final"]["CrusherTarget"]["life"] == 19
		and result["final"]["Crusher"]["life"] == 26
		and result["final"]["Crusher"]["stamina"] == 9,
		"Crushing Blow independent final state")
	_check(result["final"]["BashTarget"]["life"] == 25
		and result["final"]["BashTarget"]["stamina"] == 5
		and result["final"]["Basher"]["stamina"] == 8,
		"Shield Bash independent final state")
	_check(_contains(result["log"], "crushing_blow resolved plan [AttackOp]")
		and _contains(result["log"],
			"shield_bash resolved plan [ResourceDeltaOp]"),
		"trace names canonical identities and typed operation kinds")


func _init() -> void:
	_test_integer_scale_and_executor_boundary()
	_test_plan_architecture()
	_test_refusals()
	_test_crushing_blow()
	_test_shield_bash()
	_test_scenario_expected_state()
	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures else 0)
