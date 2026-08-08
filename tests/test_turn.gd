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

	# Partial movement permits re-entry until a terminal action succeeds.
	ActionPoints.spend_move(a.units[0], 1)
	_check(RoundLoop.activatable(st, 0).size() == 2,
		"a partially-spent unit remains selectable")
	_check(a.units[0].movement_remaining == 3,
		"movement carries across the yield", "%d" % a.units[0].movement_remaining)
	ActionPoints.spend_attack(a.units[0])
	_check(a.units[0].movement_remaining == 3
			and ActionPoints.can_move(a.units[0]) == ActionPoints.Refusal.ACTION_SPENT
			and not ActionPoints.has_resources(a.units[0]),
		"leftover capacity cannot reopen a terminal melee activation")
	_check(RoundLoop.activatable(st, 0) == [a.units[1]] and st.active_side == 0,
		"the same side may activate its other unit")
	ActionPoints.spend_attack(a.units[1])
	_check(RoundLoop.phase_done(st, 0), "A's phase ends when every activation is spent")
	_check(not RoundLoop.end_phase(st) and st.active_side == 1, "control passes to B")

	ActionPoints.spend_attack(b.units[0])
	_check(RoundLoop.end_phase(st) and st.round_number == 2,
		"a new round begins when neither side can act", "round %d" % st.round_number)
	var all_reset := true
	for s in st.sides:
		for u in s.units:
			if u.steps_this_round != 0 or u.movement_remaining <= 0:
				all_reset = false
	_check(all_reset, "movement restored and steps reset — once per round only")

	print("\n[5] extra turns — spells and on-kill abilities")
	for case in fx["extra_turns"]:
		var u := _unit(case["setup"])
		var granted: Array = []
		for pair in case["steps"]:
			match String(pair[0]):
				"move": ActionPoints.spend_move(u, int(pair[1]))
				"attack": ActionPoints.spend_attack(u)
				"rest": ActionPoints.rest(u)
				"new_round": ActionPoints.begin_round(u)
				"extra":
					granted.append(bool(ActionPoints.grant_extra_turn(u)[0]))
				"extra_rs":
					granted.append(bool(ActionPoints.grant_extra_turn(u, &"", false, true)[0]))
				"extra_once":
					granted.append(bool(ActionPoints.grant_extra_turn(
						u, StringName(pair[1]), true)[0]))
		var w: Dictionary = case["after"]
		var want_granted: Array = case["granted"]
		var ok_g := granted.size() == want_granted.size()
		if ok_g:
			for i in granted.size():
				if bool(granted[i]) != bool(want_granted[i]):
					ok_g = false
		var ok: bool = ok_g and (u.stamina == int(w["stamina"])
			and u.movement_remaining == int(w["movement_remaining"])
			and u.steps_this_round == int(w["steps_this_round"])
			and u.action_spent == bool(w["action_spent"])
			and u.forced_rest == bool(w["forced_rest"])
			and u.resting == bool(w["resting"]))
		_check(ok, String(case["label"]),
			"granted %s/%s, stamina %d/%d, move %d/%d, steps %d/%d" % [
				str(granted), str(want_granted),
				u.stamina, int(w["stamina"]),
				u.movement_remaining, int(w["movement_remaining"]),
				u.steps_this_round, int(w["steps_this_round"])])

	print("\n[6] group grants — filters and exclusions")
	var caster := _unit({})
	var d1 := _unit({})
	var d2 := _unit({})
	var un := _unit({})
	var servant := _unit({})
	d1.add_subtype(&"Демон")
	d2.add_subtype(&"Демон")
	un.add_subtype(&"Нежить")
	servant.add_subtype(&"Нежить")
	servant.add_subtype(&"Слуга Смерти")
	var everyone: Array = [d1, d2, un, servant, caster]
	for u in everyone:
		ActionPoints.spend_move(u, u.movement_remaining)
		ActionPoints.spend_attack(u)

	var t1: Array = ActionPoints.grant_extra_turn_to(everyone, [], &"Демон")
	_check(t1.size() == 2, "Искажение Хаоса reaches both demons only", "%d" % t1.size())
	_check(ActionPoints.has_resources(d1) and not ActionPoints.has_resources(caster),
		"and leaves everyone else spent")

	for u in everyone:
		u.action_spent = true
		u.movement_remaining = 0
	var t2: Array = ActionPoints.grant_extra_turn_to(everyone, [servant], &"Нежить")
	_check(t2.size() == 1, "Клич некроманта skips слуги Смерти", "%d" % t2.size())
	_check(ActionPoints.has_resources(un) and not ActionPoints.has_resources(servant),
		"the excluded servant stays spent")

	for u in everyone:
		u.action_spent = true
		u.movement_remaining = 0
	var t3: Array = ActionPoints.grant_extra_turn_to(everyone, [caster])
	_check(t3.size() == 4 and not ActionPoints.has_resources(caster),
		"excluding the caster works the same way", "%d" % t3.size())

	print("\n[R11] numeric modifier 0x12 suppresses local stamina mutations")
	var immune := _unit({"stamina": 3, "stamina_base": 10, "speed": 3})
	immune.modifiers.append(Modifier.make(
		0x12, &"modifier_0x12", Modifier.Hook.STAMINA, 0, {}, "0x12"))
	immune.movement_remaining = 3
	var move_trace := ActionPoints.spend_move(immune, 1, 2)
	_check(immune.stamina == 3, "movement stamina mutation is suppressed")
	var ranged_trace := ActionPoints.spend_ranged_attack(immune)
	_check(immune.stamina == 3 and immune.movement_remaining == 0,
		"ranged cost is suppressed while the executor still ends activation")
	var suppressed := false
	for trace in [move_trace, ranged_trace]:
		for step in (trace as Trace).steps:
			if String(step["source"]) == "modifier 0x12 stamina mutation suppression":
				suppressed = true
	_check(suppressed, "modifier 0x12 suppression is trace-visible")

	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
