extends SceneTree

## CX-012 independent deterministic vectors for DAMAGE-RANGED-001.

var failures := 0


class MidpointRng extends Rng:
	func _init() -> void:
		super(0)

	func roll(x: int, _stream: StringName = &"combat") -> int:
		return x / 2


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1


func _modifier(ability: int, power: int = 1) -> Modifier:
	return Modifier.make(ability, &"cx012_numeric_branch",
		Modifier.Hook.DAMAGE_VS_TARGET, power, {}, "numeric branch")


func _resistance_modifier(power: int) -> Modifier:
	return Modifier.make(0x06, &"stat_delta", Modifier.Hook.STAT_PASSIVE,
		power, {"stat": "resist"}, "represented resistance provider")


func _resolve(ranged_defence: int, resistance: int,
		modifiers: Array = [], target_modifiers: Array = []) -> Array:
	var attacker := Combatant.new()
	attacker.name = "attacker"
	attacker.ranged_attack = 20
	attacker.life = 30
	attacker.life_base = 30
	attacker.stamina = 10
	attacker.morale = 10
	attacker.modifiers = modifiers.duplicate()
	var defender := Combatant.new()
	defender.name = "target"
	defender.ranged_defence = ranged_defence
	defender.resist = resistance
	defender.life = 40
	defender.life_base = 40
	defender.stamina = 10
	defender.morale = 10
	defender.modifiers = target_modifiers.duplicate()
	return Damage.resolve_ranged_attack(attacker, defender, MidpointRng.new())


func _sources(traces: Array) -> Array[String]:
	var out: Array[String] = []
	for trace in traces:
		for step in (trace as Trace).steps:
			out.append(String(step["source"]))
	return out


func _find_step(traces: Array, source: String) -> Dictionary:
	for trace in traces:
		for step in (trace as Trace).steps:
			if String(step["source"]) == source:
				return step
	return {}


func _represented_resistance(base: int, provider_power: int) -> Array:
	var defender := Combatant.new()
	defender.name = "target"
	defender.resist = base
	defender.life = 40
	defender.life_base = 40
	defender.stamina = 0
	defender.morale = 10
	defender.modifiers = [_resistance_modifier(provider_power)]
	return Damage.current_resistance(defender)


func _test_effective_resistance_provider_and_final_clamp() -> void:
	var result := _represented_resistance(4, 3)
	_check(int(result[0]) == 7,
		"base plus STAT_PASSIVE resistance provider, without stamina halving")

	result = _represented_resistance(2, -7)
	var trace := result[1] as Trace
	var ordered := _sources([trace])
	var clamp := _find_step([trace], "final resistance clamp")
	_check(int(result[0]) == 0,
		"negative resistance provider total clamps to exactly zero")
	_check(ordered.find("resistance provider total")
			< ordered.find("final resistance clamp")
			and int(clamp.get("before", 999)) == -5
			and int(clamp.get("after", 999)) == 0,
		"resistance trace separates provider total from final clamp")


func _test_clamped_resistance_consumers() -> void:
	var negative_provider := [_resistance_modifier(-7)] # base 2 -> total -5
	var result := _resolve(12, 2,
		[_modifier(0x1C), _modifier(0x5F, 3)], negative_provider)
	var ordered := _sources(result[1])
	# Clamp -5 to 0, then subtract 3: 20 - (0 - 3) = 23.
	_check(int(result[0]) == 23 and int(result[2]) == 2
			and ordered.find("final resistance clamp")
			< ordered.find("modifier 0x5F resistance subtraction")
			and ordered.find("modifier 0x5F resistance subtraction")
			< ordered.find("defence subtraction"),
		"0x1C uses resistance zero before separate 0x5F subtraction")

	result = _resolve(7, 2, [_modifier(0x3C, 3)], negative_provider)
	var excess_step := _find_step(result[1],
		"modifier 0x3C excess over resistance")
	# Resolver 20 - 7 = 13; excess uses clamped 0, so 13 + (3 - 0) = 16.
	_check(int(result[0]) == 16 and int(result[2]) == 1
			and String(excess_step.get("note", "")) == "max(0, 3 - 0)",
		"0x3C excess comparison uses clamped resistance zero")


func _test_frozen_branches() -> void:
	var cases := [
		["ordinary ranged defence", 7, 2, [], 13, 1],
		["0x1C resistance channel", 2, 4, [_modifier(0x1C)], 16, 2],
		["0x1C plus 0x5F", 2, 7,
			[_modifier(0x1C), _modifier(0x5F, 3)], 16, 2],
		["0x11 before 0x4D", 9, 20,
			[_modifier(0x11), _modifier(0x4D, 3)], 19, 1],
		["0x4D without 0x11", 9, 20, [_modifier(0x4D, 3)], 14, 1],
		["0x3C positive excess", 7, 3, [_modifier(0x3C, 8)], 18, 1],
		["0x3C no excess control", 7, 3, [_modifier(0x3C, 3)], 13, 1],
		["0x1C skips non-resistance tail", 12, 3,
			[_modifier(0x1C), _modifier(0x11), _modifier(0x4D, 9),
				_modifier(0x3C, 8)], 17, 2],
	]
	for case in cases:
		var result := _resolve(int(case[1]), int(case[2]), case[3])
		_check(int(result[0]) == int(case[4]) and int(result[2]) == int(case[5]),
			String(case[0]))


func _test_stage_controls() -> void:
	var result := _resolve(9, 20, [_modifier(0x11), _modifier(0x4D, 3)])
	var ordered := _sources(result[1])
	_check(int(result[0]) == 19 and int(result[2]) == 1
			and ordered.find("modifier 0x11 ranged-defence halving")
			< ordered.find("modifier 0x4D ranged-defence subtraction")
			and ordered.find("modifier 0x4D ranged-defence subtraction")
			< ordered.find("defence subtraction"),
		"0x11 halving precedes 0x4D and resolver")
	result = _resolve(12, 3, [_modifier(0x1C), _modifier(0x11),
		_modifier(0x4D, 9), _modifier(0x3C, 8)])
	ordered = _sources(result[1])
	_check(int(result[0]) == 17 and int(result[2]) == 2
			and not ordered.has("modifier 0x11 ranged-defence halving")
			and not ordered.has("modifier 0x4D ranged-defence subtraction")
			and not ordered.has("modifier 0x3C excess over resistance"),
		"0x1C branch returns before entire non-resistance tail")
	result = _resolve(7, 2, [_modifier(0x1C, 0)])
	_check(int(result[0]) == 13 and int(result[2]) == 1,
		"zero-valued 0x1C stays on ordinary channel-1 branch")
	_check(Damage.trunc0_half(5) == 2 and Damage.trunc0_half(-5) == -2,
		"0x11 signed half truncates toward zero")
	_check(Damage.trunc0_half(9007199254740995) == 4503599627370497
			and Damage.trunc0_half(-9007199254740995) == -4503599627370497,
		"0x11 signed half stays exact beyond floating-point integer precision")


func _init() -> void:
	var registry := AbilityRegistry.new()
	Handlers.register_all(registry)
	Damage.bind_pipeline(Pipeline.new(registry))
	_test_effective_resistance_provider_and_final_clamp()
	_test_clamped_resistance_consumers()
	_test_frozen_branches()
	_test_stage_controls()
	Damage.bind_pipeline(null)
	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
