extends SceneTree

## Differential test: GDScript counterattack rules vs the Python oracle.
##
## Run: godot --headless --script tests/test_counterattack.gd
##
## Section 2 is the one that matters. A model that always resolves the counter
## after the attack passes every naive check and gets Первый удар exactly
## backwards — the ability's whole point is that a defender can kill an attacker
## before the attack lands.
##
## Run tests/test_rng.gd first: the damage numbers here depend on the RNG
## sequences matching.

const FIXTURE := "res://tests/fixtures/counter_fixture.json"

var failures: int = 0

func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1

func _unit(spec: Dictionary) -> Combatant:
	var c := Combatant.new()
	c.name = "u"
	c.attack = 8
	c.counter_attack = 6
	c.defence = 0
	c.life = 30
	c.stamina = 10
	c.stamina_base = 10
	c.morale = 10
	c.morale_base = 10
	for key in spec:
		match String(key):
			"flags":
				for f in spec[key]:
					c.set_flag(StringName(String(f)))
			"resting":
				c.resting = bool(spec[key])
			"alive":
				c.alive = bool(spec[key])
			_:
				c.set(String(key), spec[key])
	c.life_base = c.life
	return c

class _SuppressingAction extends RefCounted:
	var suppresses_counterattack: bool = true

func _init() -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		push_error("fixture not found: %s" % FIXTURE)
		quit(1)
		return
	var fx: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	print("\n[1] when a counterattack does not happen")
	for case in fx["refusals"]:
		var d := _unit(case["defender"])
		var a := _unit(case["attacker"])
		var action: Variant = _SuppressingAction.new() if bool(case["suppress"]) else null
		var got := Counterattack.why_no_counter(d, a, int(case["kind"]), action)
		var want := int(case["expected"])
		_check(got == want, "%s -> %s" % [case["label"], case["expected_name"]],
			"got %d, expected %d" % [got, want])

	print("\n[2] exchange order — the case a naive model gets backwards")
	for case in fx["exchanges"]:
		var a := _unit(case["attacker"])
		var d := _unit(case["defender"])
		var ex := Counterattack.resolve(a, d, Rng.new(int(case["seed"])),
			int(case["kind"]))
		var want: Array = case["order"]
		var ok := ex.order.size() == want.size()
		if ok:
			for i in want.size():
				if String(ex.order[i][0]) != String(want[i][0]) \
						or int(ex.order[i][1]) != int(want[i][1]):
					ok = false
		ok = ok and ex.counter_first == bool(case["counter_first"])
		ok = ok and ex.attacker_died == bool(case["attacker_died"])
		ok = ok and ex.defender_died == bool(case["defender_died"])
		var got_shape: Array = []
		for o in ex.order:
			got_shape.append("%s:%d" % [o[0], o[1]])
		_check(ok, String(case["label"]),
			"got %s, first=%s" % [str(got_shape), ex.counter_first])

	print("\n[3] a kill by counterattack is worth half the morale")
	_check(Counterattack.morale_kill_share(Combatant.AttackKind.MELEE)
		== float(fx["morale_share"]["melee"]), "melee kill: full")
	_check(Counterattack.morale_kill_share(Combatant.AttackKind.COUNTER)
		== float(fx["morale_share"]["counter"]), "counter kill: half")
	_check(Counterattack.morale_kill_share(Combatant.AttackKind.RANGED)
		== float(fx["morale_share"]["ranged"]), "ranged kill: half")

	print("\n[4] rider suppression is per-ability, not a blanket rule")
	for case in fx["riders"]:
		var got := Counterattack.rider_fires(
			StringName(String(case["ability"])), int(case["kind"]))
		_check(got == bool(case["expected"]),
			"%s on kind %d -> %s" % [case["ability"], int(case["kind"]),
				bool(case["expected"])],
			"got %s" % got)

	print("\n[5] determinism")
	var first: Array = []
	for i in 10:
		var a := _unit({})
		var d := _unit({})
		var ex := Counterattack.resolve(a, d, Rng.new(42))
		var shape: Array = []
		for o in ex.order:
			shape.append("%s:%d" % [o[0], o[1]])
		if i == 0:
			first = shape
		elif str(shape) != str(first):
			_check(false, "the same seed gives the same exchange", str(shape))
			break
	_check(true, "10 runs of one seed agree", str(first))

	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
