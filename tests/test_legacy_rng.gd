extends SceneTree

## LegacyRng port parity — differential against oracle/legacy_rng.py.
##
## The published golden vectors live in oracle/test_legacy_rng.py, which asserts
## them by hand against docs/LEGACY_RNG.md. This file asserts that the GDScript
## port agrees with the oracle bit for bit, including CRT advance counts, which
## is the part that decides whether call ordering can ever match.
##
## Run: godot --headless --script tests/test_legacy_rng.gd

const FIXTURE := "res://tests/fixtures/legacy_rng_fixture.json"

var _fails: Array[String] = []


func _check(ok: bool, label: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", label,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		_fails.append(label)


func _init() -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		push_error("missing %s — run oracle/make_fixtures.py tests/fixtures/" % FIXTURE)
		quit(1)
		return
	var fx: Dictionary = JSON.parse_string(f.get_as_text())

	print("\n[1] MSVC CRT recurrence")
	for case in fx["raw"]:
		var r := LegacyRng.new(int(case["seed"]))
		var expected: Array = case["expected"]
		var got: Array = []
		for i in expected.size():
			got.append(r.next_u15())
		var ok := true
		for i in expected.size():
			if int(expected[i]) != int(got[i]):
				ok = false
		_check(ok, "seed %d" % int(case["seed"]), "got %s" % str(got.slice(0, 4)))

	print("\n[2] bounded adapter, value AND advance count")
	for case in fx["bounded"]:
		var r := LegacyRng.new(int(case["seed"]))
		var got: int = r.below(int(case["bound"]))
		_check(got == int(case["expected"]) and r.calls == int(case["advances"]),
			"below(%d)" % int(case["bound"]),
			"got %d in %d advances, want %d in %d"
				% [got, r.calls, int(case["expected"]), int(case["advances"])])

	print("\n[3] weighted roller, removal by value")
	for case in fx["weighted"]:
		var r := LegacyRng.new(int(case["seed"]))
		var res: Array = r.weighted(case["values"], case["weights"],
			bool(case["remove_selected"]))
		var after: Array = res[1]
		var want_after: Array = case["weights_after"]
		var ok := int(res[0]) == int(case["expected"]) and after.size() == want_after.size()
		if ok:
			for i in want_after.size():
				if int(after[i]) != int(want_after[i]):
					ok = false
		_check(ok, "weighted selection", "got %s / %s" % [str(res[0]), str(after)])

	print("\n[4] recovered reseed epochs")
	for case in fx["epochs"]:
		var r := LegacyRng.new()
		if String(case["kind"]) == "map_generation":
			var eff: int = r.seed_map_generation(int(case["map_seed"]))
			_check(eff == int(case["effective"]) and r.state == int(case["state"]),
				"map_generation(%d)" % int(case["map_seed"]),
				"effective %d state %d" % [eff, r.state])
		else:
			r.seed_strategic_turn(int(case["map_seed"]), int(case["turn"]))
			_check(r.state == int(case["state"]),
				"strategic_turn(%d)" % int(case["turn"]), "state %d" % r.state)

	print("\n[5] long sequences — 32-bit wraparound and repeated digit extension")
	for case in fx["sequences"]:
		var r := LegacyRng.new(int(case["seed"]))
		var expected: Array = case["expected"]
		var ok := true
		var first_bad := -1
		for i in expected.size():
			var got: int = r.below(int(case["bound"]))
			if got != int(expected[i]):
				ok = false
				if first_bad < 0:
					first_bad = i
		_check(ok and r.calls == int(case["advances"]),
			"seed %d bound %d x%d" % [int(case["seed"]), int(case["bound"]),
				expected.size()],
			"diverged at draw %d, %d advances (want %d)"
				% [first_bad, r.calls, int(case["advances"])])

	print("\n[6] the stream argument is ignored — one shared sequence")
	var a := LegacyRng.new(7)
	var b := LegacyRng.new(7)
	_check(a.roll(6, &"combat") == b.roll(6, &"loot"),
		"different stream labels draw from the same state")

	print("\n%s" % ("ALL PASS" if _fails.is_empty()
		else "%d FAILURES: %s" % [_fails.size(), ", ".join(_fails)]))
	quit(1 if not _fails.is_empty() else 0)
