extends SceneTree

## Differential test: GDScript action points / round loop vs the Python oracle.
##
## Run: godot --headless --script tests/test_turn.gd
##
## No RNG. The cases that matter are the re-entry ones — a model that resets
## state per activation rather than per round passes every naive test and is
## farmable by yielding and reselecting.

const FIXTURE := "res://tests/fixtures/turn_fixture.json"

var failures: int = 0

func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1

func _unit(setup: Dictionary) -> Combatant:
	var u := Combatant.new()
	u.name = "u"
	u.speed = 4
	u.stamina = 10
	u.stamina_base = 10
	for key in setup:
		if String(key) == "flags":
			for f in setup[key]:
				u.set_flag(StringName(f))
		else:
			u.set(String(key), setup[key])
	ActionPoints.begin_round(u)
	return u

func _init() -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		push_error("fixture not found: %s" % FIXTURE)
		quit(1)
		return
	var fx: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	print("\n[1] effective speed")
	for case in fx["speed"]:
		var u := Combatant.new()
		u.speed = int(case["speed"])
		u.stamina = int(case["stamina"])
		u.stamina_base = 10
		for flag in case["flags"]:
			u.set_flag(StringName(flag))
		var got: int = ActionPoints.effective_speed(u)[0]
		_check(got == int(case["expected"]),
			"speed %d at stamina %d%s -> %d" % [int(case["speed"]), int(case["stamina"]),
				(" " + str(case["flags"])) if not (case["flags"] as Array).is_empty() else "",
				int(case["expected"])],
			"got %d" % got)

	print("\n[2] action point sequences")
	for case in fx["sequences"]:
		var u := _unit(case["setup"])
		for pair in case["steps"]:
			match String(pair[0]):
				"move": ActionPoints.spend_move(u, int(pair[1]))
				"attack": ActionPoints.spend_attack(u)
				"rest": ActionPoints.rest(u)
				"new_round": ActionPoints.begin_round(u)
		var w: Dictionary = case["after"]
		var ok: bool = (u.stamina == int(w["stamina"])
			and u.movement_remaining == int(w["movement_remaining"])
			and u.steps_this_round == int(w["steps_this_round"])
			and u.action_spent == bool(w["action_spent"])
			and u.forced_rest == bool(w["forced_rest"])
			and u.resting == bool(w["resting"]))
		_check(ok, String(case["label"]),
			"stamina %d/%d, move %d/%d, steps %d/%d, spent %s/%s" % [
				u.stamina, int(w["stamina"]),
				u.movement_remaining, int(w["movement_remaining"]),
				u.steps_this_round, int(w["steps_this_round"]),
				u.action_spent, bool(w["action_spent"])])

	print("\n[3] initiative — army level, ties to the attacker")
	for case in fx["initiative"]:
		var a := RoundLoop.Side.new()
		a.id = 0
		a.leader_initiative = int(case["a"])
		a.is_attacker = bool(case["a_attacker"])
		var b := RoundLoop.Side.new()
		b.id = 1
		b.leader_initiative = int(case["b"])
		b.is_attacker = not bool(case["a_attacker"])
		var got: int = RoundLoop.first_side([a, b])
		_check(got == int(case["expected"]),
			"A=%d B=%d, A attacking=%s -> side %d" % [int(case["a"]), int(case["b"]),
				bool(case["a_attacker"]), int(case["expected"])],
			"got %d" % got)

	print("\n[4] round loop and re-entry")
	var a := RoundLoop.Side.new()
	a.id = 0
	a.leader_initiative = 5
	a.is_attacker = true
	a.units = [_unit({}), _unit({})]
	var b := RoundLoop.Side.new()
	b.id = 1
	b.leader_initiative = 2
	b.units = [_unit({})]
	var st := RoundLoop.BattleState.new()
	st.sides = [a, b]
	RoundLoop.begin_battle(st)

	_check(st.round_number == 1 and st.active_side == 0,
		"round 1, higher-initiative side active")
	_check(RoundLoop.activatable(st, 0).size() == 2, "both A units selectable")

	# partial spend, then confirm the unit is still selectable
	ActionPoints.spend_move(a.units[0], 1)
	_check(RoundLoop.activatable(st, 0).size() == 2,
		"a partially-spent unit remains selectable")
	_check(a.units[0].movement_remaining == 3,
		"movement carries across the yield", "%d" % a.units[0].movement_remaining)

	for u in a.units:
		ActionPoints.spend_move(u, u.movement_remaining)
		ActionPoints.spend_attack(u)
	_check(RoundLoop.phase_done(st, 0), "A's phase ends when nothing is selectable")
	_check(not RoundLoop.end_phase(st) and st.active_side == 1, "control passes to B")

	ActionPoints.spend_move(b.units[0], b.units[0].movement_remaining)
	ActionPoints.spend_attack(b.units[0])
	_check(RoundLoop.end_phase(st) and st.round_number == 2,
		"a new round begins when neither side can act", "round %d" % st.round_number)
	var all_reset := true
	for s in st.sides:
		for u in s.units:
			if u.steps_this_round != 0 or u.movement_remaining <= 0:
				all_reset = false
	_check(all_reset, "movement restored and steps reset — once per round only")

	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
