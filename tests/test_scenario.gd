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

	print("\n[profiles] identity normalization and RNG selection")
	var base: Dictionary = fx["scenarios"].values()[0]["spec"].duplicate(true)

	var native_spec := base.duplicate(true)
	native_spec.erase("rng")
	native_spec["profile"] = " NATIVE "
	var native := Scenario.new(native_spec)
	_check(native.profile == "native", "explicit native identity is normalized")
	_check(native.rng is Rng, "explicit native selects named streams")

	var genesis_spec := base.duplicate(true)
	genesis_spec.erase("rng")
	genesis_spec["profile"] = "genesis"
	var genesis := Scenario.new(genesis_spec)
	_check(genesis.profile == "genesis", "explicit genesis identity is exposed")
	_check(genesis.rng is LegacyRng, "explicit genesis selects LegacyRng")

	var incomplete_spec := base.duplicate(true)
	incomplete_spec.erase("rng")
	incomplete_spec["profile"] = "new_horizons"
	var incomplete: Dictionary = Scenario.profile_configuration(incomplete_spec)
	_check(incomplete["profile"] == "new_horizons"
			and incomplete["error"] == Scenario.NEW_HORIZONS_INCOMPLETE,
		"incomplete new_horizons is rejected clearly")

	var unknown_spec := base.duplicate(true)
	unknown_spec.erase("rng")
	unknown_spec["profile"] = "future"
	var unknown: Dictionary = Scenario.profile_configuration(unknown_spec)
	_check(unknown["profile"] == ""
			and unknown["error"] == 'unknown scenario profile "future"',
		"an unknown profile is rejected")

	var conflict_spec := base.duplicate(true)
	conflict_spec["profile"] = "native"
	conflict_spec["rng"] = "legacy"
	var conflict: Dictionary = Scenario.profile_configuration(conflict_spec)
	_check(conflict["profile"] == ""
			and conflict["error"] == Scenario.PROFILE_CONFLICT,
		"profile plus rng is rejected as conflicting configuration")

	var alias_spec := base.duplicate(true)
	alias_spec.erase("profile")
	alias_spec["rng"] = " LEGACY "
	var alias := Scenario.new(alias_spec)
	_check(alias.profile == "genesis" and alias.rng is LegacyRng,
		"omitted profile plus legacy rng maps to genesis")

	var fallback_spec := base.duplicate(true)
	fallback_spec.erase("profile")
	fallback_spec.erase("rng")
	var fallback := Scenario.new(fallback_spec)
	_check(fallback.profile == "native" and fallback.rng is Rng,
		"phase-1 omission fallback remains native")

	for scenario_file in fx["scenarios"]:
		var case: Dictionary = fx["scenarios"][scenario_file]
		print("\n[%s]" % scenario_file)

		var s := Scenario.new(case["spec"])
		_check(s.profile == "native",
			"committed scenario declares normalized native profile")
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
