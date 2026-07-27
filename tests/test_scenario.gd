extends SceneTree

## Differential test: the whole engine against the Python oracle.
##
## Run: godot --headless --script tests/test_scenario.gd
##
## This is the integration test. Pathfinding feeds steps_this_round, which sets
## the stamina charge, which feeds StaminaMod, which scales the attack, which the
## RNG rolls, which the defence reduces. Comparing the log LINE FOR LINE means a
## disagreement anywhere in that chain surfaces at the step where it happens,
## rather than as a mysteriously different final state.
##
## Run tests/test_rng.gd first: every damage line here depends on the RNG
## sequences matching, so an RNG divergence would make this look like a combat
## bug.

const FIXTURE := "res://tests/fixtures/scenario_fixture.json"

var failures: int = 0

func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1

func _init() -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		push_error("fixture not found: %s" % FIXTURE)
		quit(1)
		return
	var fx: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	for scenario_file in fx["scenarios"]:
		var case: Dictionary = fx["scenarios"][scenario_file]
		print("\n[%s]" % scenario_file)

		var s := Scenario.new(case["spec"])
		var result: Dictionary = s.run()
		var got: Array = result["log"]
		var want: Array = case["log"]

		# Compare line for line and report the FIRST divergence: that line is
		# where the two implementations parted company.
		var first_bad := -1
		var limit: int = mini(got.size(), want.size())
		for i in limit:
			if String(got[i]) != String(want[i]):
				first_bad = i
				break
		if first_bad == -1 and got.size() != want.size():
			first_bad = limit

		if first_bad == -1:
			_check(true, "log matches, %d lines" % want.size())
		else:
			var g: String = String(got[first_bad]) if first_bad < got.size() else "<end>"
			var w: String = String(want[first_bad]) if first_bad < want.size() else "<end>"
			_check(false, "log diverges at line %d" % first_bad,
				"\n      oracle: %s\n      port:   %s" % [w, g])

		var want_final: Dictionary = case["final"]
		var got_final: Dictionary = result["final"]
		for unit_name in want_final:
			var wf: Dictionary = want_final[unit_name]
			var gf: Variant = got_final.get(unit_name)
			if gf == null:
				_check(false, "%s missing from final state" % unit_name)
				continue
			var ok := true
			var diff := ""
			for key in wf:
				var a: Variant = wf[key]
				var b: Variant = (gf as Dictionary).get(key)
				if str(a) != str(b):
					ok = false
					diff += " %s=%s/%s" % [key, str(b), str(a)]
			_check(ok, "%s final state" % unit_name, diff)

	# Determinism inside this implementation, independent of the oracle.
	print("\n[determinism]")
	for scenario_file in fx["scenarios"]:
		var spec: Dictionary = fx["scenarios"][scenario_file]["spec"]
		var a: Array = Scenario.new(spec).run()["log"]
		var stable := true
		for i in 5:
			var b: Array = Scenario.new(spec).run()["log"]
			if a.size() != b.size():
				stable = false
				break
			for j in a.size():
				if String(a[j]) != String(b[j]):
					stable = false
					break
		_check(stable, "%s reproduces across 5 runs" % scenario_file)

	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
