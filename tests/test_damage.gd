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
