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


func _test_primary_melee_charge_consumption() -> void:
	print("\n[5] command-entry charge is flat post-defence melee damage")

	# Defence drives ordinary damage to zero. Every old attack-power insertion
	# point is absorbed; only post-defence consumption inflicts all six charge.
	var ordinary := Counterattack.resolve(
		_unit({"attack": 3}),
		_unit({"counter_attack": 0, "defence": 20, "life": 30}), Rng.new(1))
	var charged_defender := _unit(
		{"counter_attack": 0, "defence": 20, "life": 30})
	var charged := Counterattack.resolve(
		_unit({"attack": 3}), charged_defender, Rng.new(1),
		Combatant.AttackKind.MELEE, null, 6)
	_check(ordinary.attack_damage == 0,
		"the distinguishing vector resolves ordinary damage to zero",
		str(ordinary.attack_damage))
	_check(charged.attack_damage == ordinary.attack_damage + 6,
		"defence does not absorb flat post-defence charge",
		"%d = %d + 6" % [charged.attack_damage, ordinary.attack_damage])

	# The exact combined capped value reaches the existing accumulator/order
	# consumer path and life subtraction.
	var capped_defender := _unit(
		{"counter_attack": 0, "defence": 0, "life": 5})
	var capped := Counterattack.resolve(
		_unit({"attack": 3}), capped_defender, Rng.new(1),
		Combatant.AttackKind.MELEE, null, 6)
	_check(capped.attack_damage == 5
			and String(capped.order[0][0]) == "attack"
			and int(capped.order[0][1]) == 5,
		"combined capped damage reaches accounting and attack consumers",
		"accumulator %d, order %s" % [capped.attack_damage, str(capped.order)])
	_check(capped_defender.life == 0 and capped.defender_died,
		"life subtraction consumes the same combined capped damage")

	var plain_exchange := Counterattack.resolve(
		_unit({"attack": 3, "life": 50}),
		_unit({"counter_attack": 7, "defence": 0, "life": 50}), Rng.new(7))
	var charged_exchange := Counterattack.resolve(
		_unit({"attack": 3, "life": 50}),
		_unit({"counter_attack": 7, "defence": 0, "life": 50}), Rng.new(7),
		Combatant.AttackKind.MELEE, null, 2)
	_check(charged_exchange.counter_damage == plain_exchange.counter_damage,
		"retaliation remains charge-free and RNG-identical",
		"%d vs %d" % [charged_exchange.counter_damage,
			plain_exchange.counter_damage])

	var ranged_plain := Counterattack.resolve(
		_unit({"ranged_attack": 3}),
		_unit({"counter_attack": 0, "ranged_defence": 0, "life": 30}),
		Rng.new(9), Combatant.AttackKind.RANGED)
	var ranged_with_charge := Counterattack.resolve(
		_unit({"ranged_attack": 3}),
		_unit({"counter_attack": 0, "ranged_defence": 0, "life": 30}),
		Rng.new(9), Combatant.AttackKind.RANGED, null, 20)
	_check(ranged_with_charge.attack_damage == ranged_plain.attack_damage,
		"ranged attacks ignore primary-melee charge")


func _revive_marker() -> Status:
	var effect := Status.new()
	effect.id = &"runtime-revive"
	effect.modifiers.append(Modifier.make(
		DeathLifecycle.REVIVE, &"add_flat", Modifier.Hook.STAT_PASSIVE))
	return effect


func _lifecycle_exchange(attacker: Combatant,
		defender: Combatant) -> Counterattack.Exchange:
	var field := Battlefield.new(3, 2)
	var left := RoundLoop.Side.new()
	left.id = 0
	left.units = [attacker]
	var right := RoundLoop.Side.new()
	right.id = 1
	right.units = [defender]
	var sides: Array = [left, right]
	field.place(attacker, Battlefield.offset_to_axial(0, 0))
	field.place(defender, Battlefield.offset_to_axial(1, 0))
	Counterattack.bind_death_resolver(
		func(casualty: Combatant):
			return DeathLifecycle.resolve(casualty, field, sides))
	var exchange := Counterattack.resolve(attacker, defender, Rng.new(17))
	Counterattack.bind_death_resolver(Callable())
	return exchange


func _test_fatal_event_melee_lifecycle_sequencing() -> void:
	print("\n[CX-011] fatal event versus final alive sequencing")
	var attacker := _unit({"name": "initiator", "attack": 30, "life": 1})
	attacker.statuses.append(_revive_marker())
	var defender := _unit({"name": "first striker", "counter_attack": 100,
		"life": 30, "flags": ["Первый удар"]})
	var revived_first := _lifecycle_exchange(attacker, defender)
	_check(revived_first.attacker_fatal_event and not revived_first.attacker_died,
		"lethal first strike records fatal_event separately from final alive")
	_check([revived_first.order[0][0], revived_first.order[1][0]]
		== ["counter", "attack"],
		"revived initiator still executes its primary")

	attacker = _unit({"name": "doomed", "attack": 30, "life": 1})
	defender = _unit({"name": "first striker", "counter_attack": 100,
		"life": 30, "flags": ["Первый удар"]})
	var final_first := _lifecycle_exchange(attacker, defender)
	_check(final_first.order.size() == 1 and final_first.order[0][0] == "counter",
		"lethal first strike without survival suppresses primary")

	attacker = _unit({"name": "initiator", "attack": 100, "life": 30})
	defender = _unit({"name": "revived defender", "counter_attack": 30,
		"life": 1})
	defender.statuses.append(_revive_marker())
	var revived_primary := _lifecycle_exchange(attacker, defender)
	_check(revived_primary.defender_fatal_event and not revived_primary.defender_died,
		"lethal primary can leave defender finally alive")
	_check(revived_primary.order.size() == 1
		and revived_primary.order[0][0] == "attack",
		"fatal initiating primary suppresses retaliation after revival")

	attacker = _unit({"name": "initiator", "attack": 1, "life": 30})
	defender = _unit({"name": "ordinary defender", "counter_attack": 30,
		"defence": 0, "life": 50})
	var nonfatal := _lifecycle_exchange(attacker, defender)
	_check(nonfatal.order.size() == 2 and nonfatal.order[1][0] == "counter",
		"nonfatal primary control retains ordinary retaliation")


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

	_test_primary_melee_charge_consumption()
	_test_fatal_event_melee_lifecycle_sequencing()

	print("\n[6] determinism")
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
