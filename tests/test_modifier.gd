extends SceneTree

## Differential test: GDScript modifier pipeline vs the Python oracle.
##
## Run: godot --headless --script tests/test_modifier.gd
##
## No RNG. The Hook VALUES are checked first and deliberately: the enum's
## numeric order IS the resolution order, so a divergence there would silently
## reorder every battle rather than failing anything visibly.

const FIXTURE := "res://tests/fixtures/modifier_fixture.json"

var failures: int = 0

func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1

func _mods(specs: Array) -> Array:
	var out: Array = []
	for s in specs:
		var m := Modifier.make(
			int(s["ability"]), StringName(String(s["handler"])), int(s["hook"]),
			int(s["power"]), s["params"], String(s["source"]))
		out.append(m)
	return out

func _init() -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		push_error("fixture not found: %s" % FIXTURE)
		quit(1)
		return
	var fx: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	var reg := AbilityRegistry.new()
	Handlers.register_all(reg)
	var p := Pipeline.new(reg)

	print("\n[1] hook values — the enum's order is the resolution order")
	for name in fx["hooks"]:
		var want := int(fx["hooks"][name])
		var got: int = Modifier.Hook.get(name, -1)
		_check(got == want, "Hook.%s = %d" % [name, want], "got %d" % got)

	print("\n[2] pipeline cases")
	for case in fx["cases"]:
		var mods := _mods(case["mods"])
		var ctx: Dictionary = (case["ctx"] as Dictionary).duplicate()
		# A target is rebuilt from its subtypes: only its subtype membership
		# affects any handler here.
		if case["ctx_target_subtypes"] != null:
			var target := Combatant.new()
			for st in case["ctx_target_subtypes"]:
				target.add_subtype(StringName(String(st)))
			ctx["target"] = target

		if String(case["mode"]) == "flag":
			var got_flag := p.flag(mods, int(case["hook"]), ctx)
			_check(got_flag == bool(case["expected"]), String(case["label"]),
				"got %s" % got_flag)
		else:
			var result: Array = p.resolve(case["base"], mods, int(case["hook"]), ctx)
			var got: float = float(result[0])
			var want: float = float(case["expected"])
			_check(absf(got - want) < 1e-9, String(case["label"]),
				"got %s, expected %s" % [got, want])

	print("\n[3] an unknown handler is recorded, not silently ignored")
	var ghost := Modifier.make(99, &"not_implemented", Modifier.Hook.STAT_PASSIVE,
		5, {"stat": "attack"}, "opcode 99")
	var r: Array = p.resolve(8, [ghost], Modifier.Hook.STAT_PASSIVE, {"stat": "attack"})
	_check(float(r[0]) == 8.0, "the value is unchanged")
	var noted := false
	for step in (r[1] as Trace).steps:
		if String(step["note"]).contains("no handler"):
			noted = true
	_check(noted, "and the trace says so")

	print("\n[4] spell grants are enumerable rather than numeric")
	var grants := _mods(fx["spell_grants"]["mods"])
	var known := Handlers.spells_granted(grants)
	var want_known: Array = fx["spell_grants"]["expected"]
	var same := known.size() == want_known.size()
	if same:
		for i in known.size():
			if String(known[i]) != String(want_known[i]):
				same = false
	_check(same, "walking the modifiers lists what the unit knows",
		"got %s" % str(known))

	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
