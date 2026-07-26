extends SceneTree

## Differential test: GDScript Action vs the Python oracle.
##
## Run: godot --headless --script tests/test_actions.gd
##
## No RNG here — legality and cost are deterministic, so this is meaningful
## independently of the RNG port.

const FIXTURE := "res://tests/fixtures/action_fixture.json"

var failures: int = 0

func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1

func _actor(spec: Dictionary) -> Combatant:
	var c := Combatant.new()
	c.stamina = 10
	c.stamina_base = 10
	c.ammo = 4
	for key in spec:
		match String(key):
			"flags":
				for f in spec[key]:
					c.set_flag(StringName(f))
			"subtypes":
				for s in spec[key]:
					c.add_subtype(StringName(s))
			_:
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

	# Build the catalogue from data, exactly as a ContentPack would.
	var catalogue: Dictionary = {}
	for d in fx["catalogue"]:
		var a := Action.from_dict(d)
		catalogue[a.id] = a

	print("\n[1] catalogue round-trips from data")
	_check(catalogue.size() == fx["catalogue"].size(),
		"all %d actions built" % fx["catalogue"].size(), "got %d" % catalogue.size())
	var attacks: int = 0
	for id in catalogue:
		if catalogue[id].is_attack:
			attacks += 1
	_check(attacks == 7, "seven actions perform an attack", "got %d" % attacks)

	print("\n[2] resolved stamina cost (documented cost + attack surcharge)")
	for d in fx["catalogue"]:
		var a: Action = catalogue[StringName(d["id"])]
		var want: int = int(d["cost_stamina"]) + (1 if bool(d["attack_surcharge"]) else 0)
		_check(a.resolved_stamina() == want, "%s -> %d" % [d["name"], want],
			"got %d" % a.resolved_stamina())

	print("\n[3] availability and payment")
	for case in fx["cases"]:
		var a: Action = catalogue[StringName(case["action"])]
		var actor := _actor(case["actor"])
		var avail: int = a.availability(actor)
		var want_avail: int = int(case["availability"])
		var ok_avail: bool = avail == want_avail
		if avail == Action.Refusal.OK:
			a.pay(actor)
		var after: Dictionary = case["after"]
		var ok_state: bool = (actor.stamina == int(after["stamina"])
			and actor.ammo == int(after["ammo"])
			and actor.action_spent == bool(after["action_spent"]))
		_check(ok_avail and ok_state, String(case["label"]),
			"avail %d/%d, stamina %d/%d, ammo %d/%d, spent %s/%s" % [
				avail, want_avail,
				actor.stamina, int(after["stamina"]),
				actor.ammo, int(after["ammo"]),
				actor.action_spent, bool(after["action_spent"])])

	print("\n[4] suppression and scaling survive the data round-trip")
	var extra: Action = catalogue[&"extra_shot"]
	_check(extra.suppresses.has(&"Бронебойный выстрел"),
		"Дополнительный выстрел suppresses Бронебойный выстрел")
	_check(extra.scales.get(&"Точный выстрел", 0.0) == 0.5,
		"Дополнительный выстрел halves Точный выстрел")
	_check(catalogue[&"sniper_shot"].scales.get(&"Точный выстрел", 0.0) == 2.0,
		"Снайперский выстрел doubles Точный выстрел")
	_check(catalogue[&"shield_bash"].suppresses_counterattack,
		"Удар щитом suppresses the counterattack")
	_check(catalogue[&"shield_bash"].excluded_targets.has(&"Бестелесный"),
		"Удар щитом excludes incorporeal targets")
	_check(catalogue[&"healing"].excluded_targets.has(&"Нежить"),
		"Целительство excludes undead")

	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
