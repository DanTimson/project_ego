extends SceneTree

## Differential test: GDScript status effects vs the Python oracle.
##
## Run: godot --headless --script tests/test_statuses.gd
##
## No RNG. Two things here are easy to get wrong and expensive to notice later:
##
##   TICK BEFORE AGEING — an effect that deals damage on the round it expires
##   should still deal it. Ageing first silently drops the last tick of every
##   damage-over-time effect, which reads as a balance problem rather than a bug.
##
##   STACKING IS PER-EFFECT — «кумулятивному воздействию» stacks; «не
##   складываются, вместо этого выбирается» takes the maximum. One global policy
##   would be wrong for one of them whichever way it went.

const FIXTURE := "res://tests/fixtures/status_fixture.json"

var failures: int = 0

func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1

func _effect(spec: Dictionary) -> Statuses.Effect:
	var e := Statuses.Effect.new()
	e.id = StringName(String(spec["id"]))
	e.name = String(spec.get("name", ""))
	e.duration = int(spec.get("duration", Statuses.PERMANENT))
	e.power = int(spec.get("power", 0))
	e.tick = spec.get("tick", {})
	e.stacking = Statuses.Stacking[String(spec.get("stacking", "REFRESH"))]
	e.prevents_action = bool(spec.get("prevents_action", false))
	e.hostile = bool(spec.get("hostile", false))
	for tag in spec.get("tags", []):
		e.tags.append(StringName(String(tag)))
	if spec.has("decay_per"):
		e.decay_per = spec["decay_per"]
	return e

func _unit(spec: Dictionary) -> Combatant:
	var u := Combatant.new()
	u.name = "u"
	u.life = 30
	u.stamina = 10
	u.morale = 10
	for key in spec:
		u.set(String(key), spec[key])
	u.life_base = int(spec.get("life", 30))
	u.stamina_base = 10
	u.morale_base = 10
	return u

func _init() -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		push_error("fixture not found: %s" % FIXTURE)
		quit(1)
		return
	var fx: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	print("\n[1] duration arithmetic")
	for case in fx["durations"]:
		var got := Statuses.effective_duration(
			int(case["base"]), int(case["concentration"]),
			int(case["duration_mod"]), int(case["target_resist"]),
			int(case["resist_duration"]), int(case["thaumaturgy"]))
		_check(got == int(case["expected"]),
			"base %d conc %d mod %d resist %d/%d thaum %d -> %d" % [
				int(case["base"]), int(case["concentration"]),
				int(case["duration_mod"]), int(case["target_resist"]),
				int(case["resist_duration"]), int(case["thaumaturgy"]),
				int(case["expected"])],
			"got %d" % got)

	print("\n[2] application, ticking and expiry")
	for case in fx["sequences"]:
		var u := _unit(case["unit"])
		for spec in case["effects"]:
			Statuses.apply(u, _effect(spec))
		if int(case["reduce_by"]) > 0:
			Statuses.reduce_duration(u, int(case["reduce_by"]), true,
				case["reduce_tags"])
		for i in int(case["rounds"]):
			Statuses.tick_round(u)

		var w: Dictionary = case["after"]
		var act: Array = Statuses.can_act(u)
		var durations: Array = []
		for e in u.statuses:
			durations.append(e.duration)
		durations.sort()
		var want_dur: Array = w["durations"]
		var dur_ok := durations.size() == want_dur.size()
		if dur_ok:
			for i in durations.size():
				if int(durations[i]) != int(want_dur[i]):
					dur_ok = false

		var ok: bool = (u.life == int(w["life"])
			and u.stamina == int(w["stamina"])
			and u.morale == int(w["morale"])
			and u.alive == bool(w["alive"])
			and u.statuses.size() == int(w["statuses"])
			and bool(act[0]) == bool(w["can_act"])
			and String(act[1]) == String(w["blocked_by"])
			and dur_ok)
		_check(ok, String(case["label"]),
			"life %d/%d, statuses %d/%d, durations %s/%s" % [
				u.life, int(w["life"]), u.statuses.size(), int(w["statuses"]),
				str(durations), str(want_dur)])

	print("\n[3] modifiers flow through the normal pipeline")
	var u := _unit({})
	_check(Statuses.active_modifiers(u).is_empty(), "no effects, no modifiers")
	var boon := Statuses.Effect.new()
	boon.id = &"ancestral"
	boon.name = "Ярость предков"
	boon.duration = 4
	boon.modifiers = [Modifier.make(2, &"stat_delta",
		Modifier.Hook.STAT_PASSIVE, 3, {"stat": "attack"}, "Ярость предков")]
	Statuses.apply(u, boon)
	_check(Statuses.active_modifiers(u).size() == 1,
		"an active effect contributes its modifiers")
	for i in 4:
		Statuses.tick_round(u)
	_check(Statuses.active_modifiers(u).is_empty(),
		"and they vanish with it, without separate bookkeeping")

	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
