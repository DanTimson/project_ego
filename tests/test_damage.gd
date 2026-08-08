extends SceneTree

## Differential test: GDScript pipeline vs the Python oracle.
##
## Run: godot --headless --script tests/test_damage.gd
##
## Sections 1-3 are RNG-free and valid regardless of whether the RNG port is
## confirmed. Sections 4-5 depend on tests/test_rng.gd passing first — if it
## fails, treat failures here as downstream noise.

const FIXTURE := "res://tests/fixtures/pipeline_fixture.json"
const EPS := 1e-6

var failures: int = 0

func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1

func _build(spec: Dictionary) -> Combatant:
	var c := Combatant.new()
	for key in spec:
		if key == "flags":
			for f in spec[key]:
				c.set_flag(StringName(f))
		else:
			c.set(String(key), spec[key])
	return c

func _init() -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		push_error("fixture not found: %s" % FIXTURE)
		quit(1)
		return
	var fx: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	print("\n[1] attack value — (base + additive) * Stamina * Morale * Wound")
	for case in fx["attack_value"]:
		var u := _build(case["unit"])
		var got: float = Damage.current_attack(u, case["kind"])[0]
		var want: float = float(case["expected"])
		_check(absf(got - want) < EPS, String(case["label"]),
			"got %.6f, expected %.6f" % [got, want])

	print("\n[2] defence value — floor, clamp >= 0, halved at stamina 0")
	for case in fx["defence_value"]:
		var u := _build(case["unit"])
		var got: int = Damage.current_defence(u, case["kind"])[0]
		var want: int = int(case["expected"])
		_check(got == want, String(case["label"]), "got %d, expected %d" % [got, want])

	print("\n[3] multiplier tables")
	for case in fx["multipliers"]["wound"]:
		var u := Combatant.new()
		u.life_base = int(case["life_base"])
		u.life = int(case["life"])
		var got: float = Wounds.modifier(u)[0]
		_check(absf(got - float(case["expected"])) < EPS,
			"wound: life %d%%" % int(case["life"]), "got %.4f" % got)
	for case in fx["multipliers"]["stamina"]:
		var u := Combatant.new()
		u.stamina = int(case["stamina"])
		var got: float = Stamina.modifier(u)[0]
		_check(absf(got - float(case["expected"])) < EPS,
			"stamina: %d" % int(case["stamina"]), "got %.4f" % got)
	for case in fx["multipliers"]["morale"]:
		var u := Combatant.new()
		u.morale = int(case["morale"])
		u.morale_base = int(case["morale_base"])
		var got: float = Morale.modifier(u)[0]
		_check(absf(got - float(case["expected"])) < EPS,
			"morale: %d" % int(case["morale"]), "got %.4f" % got)
	# Whole-stat vectors: these catch the integer truncation that a float
	# multiplier cannot express (100 * 1.15 == 114.999... -> 114, binary 115).
	# R8: attack stamina cost keys on live capacity vs effective speed, strict
	# less-than. steps_this_round is deliberately nonzero in every vector, so a
	# movement-history discriminator would fail here.
	for case in fx["capacity_cost"]:
		var u := Combatant.new()
		u.speed = int(case["speed"])
		u.stamina = int(case["stamina"])
		u.stamina_base = 10
		u.movement_remaining = int(case["capacity"])
		u.steps_this_round = 3
		var eff: int = int(ActionPoints.effective_speed(u)[0])
		_check(eff == int(case["effective_speed"]),
			"effective speed: speed %d stamina %d" % [int(case["speed"]), int(case["stamina"])],
			"got %d want %d" % [eff, int(case["effective_speed"])])
		var cost: int = ActionPoints.attack_stamina_cost(u)
		_check(cost == int(case["expected"]),
			"attack cost: speed %d stamina %d capacity %d"
				% [int(case["speed"]), int(case["stamina"]), int(case["capacity"])],
			"got %d want %d" % [cost, int(case["expected"])])

	# R6: entry semantics differ per attack kind before the shared tail.
	for case in fx["attack_entry"]:
		var u := Combatant.new()
		var b: int = int(case["base"])
		u.attack = b
		u.counter_attack = b
		u.ranged_attack = b
		u.morale = 10
		u.morale_base = 10
		if bool(case["no_fight"]):
			u.flags[&"Не сражается"] = true
		var res: Array = Damage.current_attack(u, int(case["kind"]) as Combatant.AttackKind)
		_check(int(res[0]) == int(case["expected"]),
			"attack entry: base %d kind %d no_fight %s"
				% [b, int(case["kind"]), str(case["no_fight"])],
			"got %d want %d" % [int(res[0]), int(case["expected"])])

	var disabled := Combatant.new()
	disabled.attack = 7
	disabled.counter_attack = 7
	disabled.ranged_attack = 7
	disabled.morale = 10
	disabled.modifiers.append(Modifier.make(
		0x26, &"modifier_0x26", Modifier.Hook.DAMAGE_VS_TARGET, 0, {}, "0x26"))
	_check(int(Damage.current_attack(disabled, Combatant.AttackKind.MELEE)[0]) == 0
			and int(Damage.current_attack(disabled, Combatant.AttackKind.COUNTER)[0]) == 0
			and int(Damage.current_attack(disabled, Combatant.AttackKind.RANGED)[0]) == 7,
		"effective modifier 0x26 disables ordinary/counter but not ranged entry")

	# R10: the already-applicable conditional input is outside all
	# effective-stat multipliers, after the selected ordinary 1.5x branch, and
	# excluded from ranged attack.
	for case in fx["conditional_attack_power"]:
		var u := _build(case["unit"])
		var res: Array = Damage.attack_power_before_randomisation(
			u, int(case["kind"]) as Combatant.AttackKind,
			bool(case["selected_ordinary_1_5x"]))
		_check(int(res[0]) == int(case["expected"]),
			"conditional power: %s" % String(case["label"]),
			"got %d want %d" % [int(res[0]), int(case["expected"])])
		if bool(case["selected_ordinary_1_5x"]):
			var sources: Array = []
			for step in (res[1] as Trace).steps:
				sources.append(String(step["source"]))
			_check(sources.find("selected ordinary 1.5x branch")
					< sources.find("conditional attack contribution"),
				"selected branch precedes conditional attack contribution")

	# R11: modifier 0x12 suppresses mutations, never live-stamina penalties.
	var immune := Combatant.new()
	immune.attack = 20
	immune.defence = 7
	immune.ranged_defence = 7
	immune.life_base = 20
	immune.life = 20
	immune.stamina = 0
	immune.morale = 10
	immune.modifiers.append(Modifier.make(
		0x12, &"modifier_0x12", Modifier.Hook.STAMINA, 0, {}, "0x12"))
	_check(int(Damage.current_attack(immune, Combatant.AttackKind.MELEE)[0]) == 8
			and int(Damage.current_defence(immune, Combatant.AttackKind.MELEE)[0]) == 3
			and int(Damage.current_defence(immune, Combatant.AttackKind.RANGED)[0]) == 3,
		"modifier 0x12 leaves live-stamina attack and defence penalties active")

	# R9: halve at EXACTLY zero stamina, then clamp to zero.
	for case in fx["defence_tail"]:
		var u := Combatant.new()
		u.defence = int(case["value"])
		u.ranged_defence = int(case["value"])
		u.stamina = int(case["stamina"])
		var res: Array = Damage.current_defence(u, int(case["kind"]) as Combatant.AttackKind)
		_check(int(res[0]) == int(case["expected"]),
			"defence tail: value %d stamina %d kind %d"
				% [int(case["value"]), int(case["stamina"]), int(case["kind"])],
			"got %d want %d" % [int(res[0]), int(case["expected"])])

	for case in fx["morale_attack"]:
		var u := Combatant.new()
		var base: int = int(case["base"])
		u.attack = base
		u.counter_attack = base
		u.ranged_attack = base
		u.morale = int(case["morale"])
		u.morale_base = 999
		var res: Array = Damage.current_attack(u, int(case["kind"]) as Combatant.AttackKind)
		var got: int = int(res[0])
		_check(got == int(case["expected"]),
			"morale attack: base %d morale %d kind %d" % [base, int(case["morale"]), int(case["kind"])],
			"got %d want %d" % [got, int(case["expected"])])

	print("\n[4] attack roll sequences (requires test_rng.gd to pass first)")
	for case in fx["roll_attack"]:
		var rng := Rng.new(int(case["seed"]))
		var expected: Array = case["expected"]
		var got: Array = []
		for i in expected.size():
			got.append(Damage.roll_attack(int(case["attack"]), rng)[0])
		var ok := true
		for i in expected.size():
			if int(expected[i]) != int(got[i]):
				ok = false
				break
		_check(ok, "attack %d" % int(case["attack"]), "got %s" % [str(got.slice(0, 6))])

	print("\n[5] full resolution sequences")
	for case in fx["resolve"]:
		var rng := Rng.new(int(case["seed"]))
		var atk := _build(case["attacker"])
		var dfn := _build(case["defender"])
		var expected: Array = case["expected"]
		var got: Array = []
		for i in expected.size():
			got.append(Damage.resolve_attack(atk, dfn, case["kind"], rng)[0])
		var ok := true
		for i in expected.size():
			if int(expected[i]) != int(got[i]):
				ok = false
				break
		_check(ok, String(case["label"]), "got %s" % [str(got)])

	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
