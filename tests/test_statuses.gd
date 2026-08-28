extends SceneTree

## Stable status-container and provider integration coverage.
## Automatic duration lifecycle cases are intentionally absent pending R13.

const FIXTURE := "res://tests/fixtures/status_fixture.json"

var failures: int = 0


func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1


func _status(specification: Dictionary) -> Status:
	var status := Status.new()
	status.id = StringName(String(specification["id"]))
	status.name = String(specification.get("name", ""))
	status.duration = int(specification.get("duration", Status.PERMANENT))
	status.power = int(specification.get("power", 0))
	status.tick = specification.get("tick", {}).duplicate(true)
	if specification.has("decay_per"):
		status.decay_per = specification["decay_per"].duplicate(true)
	status.stacking = Status.Stacking[String(specification.get("stacking", "REFRESH"))]
	var parsed := Status.parse_restrictions(specification.get("restrictions", []))
	status.restrictions.assign(parsed["restrictions"])
	status.hostile = bool(specification.get("hostile", false))
	for tag in specification.get("tags", []):
		status.tags.append(StringName(String(tag)))
	return status


func _unit() -> Combatant:
	var unit := Combatant.new()
	unit.name = "u"
	unit.attack = 5
	unit.life = 30
	unit.life_base = 30
	unit.stamina = 10
	unit.stamina_base = 10
	unit.morale = 10
	unit.morale_base = 10
	return unit


func _modifier(stat: String, power: int = 3) -> Modifier:
	return Modifier.make(2, &"stat_delta", Modifier.Hook.STAT_PASSIVE,
		power, {"stat": stat}, "synthetic status")


func _same_int_array(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index in actual.size():
		if int(actual[index]) != int(expected[index]):
			return false
	return true


func _same_string_array(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index in actual.size():
		if String(actual[index]) != String(expected[index]):
			return false
	return true


func _init() -> void:
	var file := FileAccess.open(FIXTURE, FileAccess.READ)
	if file == null:
		push_error("fixture not found: %s" % FIXTURE)
		quit(1)
		return
	var fixture: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	print("\n[1] duration resistance arithmetic")
	for case in fixture["durations"]:
		var got := Statuses.effective_duration(
			int(case["base"]), int(case["concentration"]),
			int(case["duration_mod"]), int(case["target_resist"]),
			int(case["resist_duration"]), int(case["thaumaturgy"]))
		_check(got == int(case["expected"]),
			"duration vector resolves to %d" % int(case["expected"]),
			"got %d" % got)

	print("\n[2] stable stacking and explicit manipulation fixture")
	for case in fixture["sequences"]:
		var unit := _unit()
		for specification in case["effects"]:
			Statuses.apply(unit, _status(specification))
		if int(case["reduce_by"]) > 0:
			Statuses.reduce_duration(unit, int(case["reduce_by"]), true,
				case["reduce_tags"])
		var removed := 0
		if String(case["remove_id"]) != "":
			removed = Statuses.remove(unit, StringName(String(case["remove_id"])))
		var ids: Array = []
		var durations: Array = []
		var powers: Array = []
		for status in unit.statuses:
			ids.append(String(status.id))
			durations.append(status.duration)
			powers.append(status.power)
		var expected: Dictionary = case["after"]
		var ok := (_same_string_array(ids, expected["ids"])
			and _same_int_array(durations, expected["durations"])
			and _same_int_array(powers, expected["powers"])
			and removed == int(expected["removed"]))
		_check(ok, String(case["label"]),
			"ids %s durations %s powers %s" % [str(ids), str(durations), str(powers)])

	print("\n[provisional lifecycle reference — not R13 truth]")
	for case in fixture["provisional_lifecycle"]:
		var unit := _unit()
		for key in case["unit"]:
			unit.set(String(key), case["unit"][key])
		unit.life_base = int(case["unit"].get("life", 30))
		for specification in case["effects"]:
			Statuses.apply(unit, _status(specification))
		for step in int(case["steps"]):
			Statuses.tick_round(unit)
		var ids: Array = []
		var durations: Array = []
		for status in unit.statuses:
			ids.append(String(status.id))
			durations.append(status.duration)
		var expected: Dictionary = case["after"]
		var ok := (unit.life == int(expected["life"])
			and unit.stamina == int(expected["stamina"])
			and unit.morale == int(expected["morale"])
			and unit.alive == bool(expected["alive"])
			and _same_string_array(ids, expected["ids"])
			and _same_int_array(durations, expected["durations"]))
		_check(ok, String(case["label"]),
			"life %d durations %s" % [unit.life, str(durations)])

	print("\n[3] construction isolation and deterministic serialization")
	var prototype := Status.new()
	prototype.id = &"boon"
	prototype.name = "Synthetic boon"
	prototype.source = "fixture"
	prototype.duration = 4
	prototype.power = 3
	prototype.tags.append(&"buff")
	prototype.modifiers.append(_modifier("attack"))
	var left := _unit()
	var right := _unit()
	Statuses.apply(left, prototype.copy())
	Statuses.apply(right, prototype.copy())
	left.statuses[0].duration = 1
	left.statuses[0].modifiers[0].power = 9
	left.statuses[0].modifiers[0].params["stat"] = "defence"
	_check(right.statuses[0].duration == 4, "status duration is not aliased")
	_check(right.statuses[0].modifiers[0].power == 3, "modifier is not aliased")
	_check(right.statuses[0].modifiers[0].params == {"stat": "attack"},
		"modifier params are not aliased")
	var serialized := right.statuses[0].to_dict()
	_check(serialized["id"] == "boon" and serialized["duration"] == 4,
		"identity and duration serialize")
	_check(serialized["modifiers"][0]["hook"] == "STAT_PASSIVE",
		"modifier payload serializes")

	print("\n[4] numeric modifier reaches live stats and remains a later provider")
	var registry := AbilityRegistry.new()
	Handlers.register_all(registry)
	Damage.bind_pipeline(Pipeline.new(registry))
	var actor := _unit()
	var boon := Status.new()
	boon.id = &"attack_boon"
	boon.duration = 4
	boon.modifiers.append(_modifier("attack"))
	Statuses.apply(actor, boon)
	_check(float(Damage.current_attack(actor, Combatant.AttackKind.MELEE)[0]) == 8.0,
		"status raises live effective attack")
	Statuses.remove(actor, &"attack_boon")
	_check(float(Damage.current_attack(actor, Combatant.AttackKind.MELEE)[0]) == 5.0,
		"removal restores live effective attack")

	var ranged := _unit()
	ranged.ranged_attack = 0
	var ranged_boon := Status.new()
	ranged_boon.id = &"ranged_boon"
	ranged_boon.duration = 4
	ranged_boon.modifiers.append(_modifier("ranged_attack", 6))
	Statuses.apply(ranged, ranged_boon)
	var zero_result := Damage.current_attack(ranged, Combatant.AttackKind.RANGED)
	_check(int(zero_result[0]) == 0,
		"status cannot resurrect the R6 zero early-provider sum")
	var status_resolved := false
	for step in (zero_result[1] as Trace).steps:
		if String(step["source"]).contains("synthetic status"):
			status_resolved = true
	_check(not status_resolved, "zero return precedes the status later provider")
	ranged.ranged_attack = 1
	_check(int(Damage.current_attack(ranged, Combatant.AttackKind.RANGED)[0]) == 7,
		"a nonzero early sum then consumes the status provider")
	Damage.bind_pipeline(null)

	print("\n[5] status flag reaches an existing live consumer")
	var wounded := _unit()
	wounded.life = 5
	wounded.life_base = 20
	var painless := Status.new()
	painless.id = &"painless"
	painless.duration = 4
	painless.modifiers.append(Modifier.make(13, &"grant_flag",
		Modifier.Hook.STAT_PASSIVE, 0, {"flag": "Не чувствует боли"}, "status flag"))
	Statuses.apply(wounded, painless)
	_check(wounded.has_flag(&"Не чувствует боли"), "Combatant.has_flag sees it")
	_check(float(Wounds.modifier(wounded)[0]) == 1.0,
		"existing wound consumer sees the status flag")
	Statuses.remove(wounded, &"painless")
	_check(float(Wounds.modifier(wounded)[0]) < 1.0,
		"explicit removal restores the wound penalty")

	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
