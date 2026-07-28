extends SceneTree

## Differential test: GDScript roster building vs the Python oracle.
##
## Run: godot --headless --script tests/test_roster.gd
##
## THE FIXTURE IS SELF-CONTAINED. Every other test describes inputs the test
## constructs; this one carries the .var-derived TABLES too, because the real
## ones live in packs/<id>/data/ which is gitignored and machine-local. A test
## that read them would pass or fail depending on whose machine ran it —
## worthless in CI, and worse than no test because it would look like coverage.
##
## The records are shaped like the real ones but are ours, so nothing here
## redistributes anyone's content.
##
## No RNG: building a unit rolls nothing.

const FIXTURE := "res://tests/fixtures/roster_fixture.json"

var failures: int = 0

func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1

## Write the fixture's pack to user:// so ContentDb loads it the ordinary way,
## rather than through a test-only construction path that could diverge from
## how packs are really loaded.
func _write_pack(fx: Dictionary) -> String:
	var dir := "user://roster_fixture_pack"
	DirAccess.make_dir_recursive_absolute(dir.path_join("data"))
	var f := FileAccess.open(dir.path_join("bindings.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"pack": String(fx["pack"]),
		"abilities": fx["bindings"]}))
	f.close()
	for table_name in fx["tables"]:
		var t := FileAccess.open(
			dir.path_join("data").path_join("%s.json" % table_name),
			FileAccess.WRITE)
		t.store_string(JSON.stringify({"file": "%s.var" % table_name,
			"records": fx["tables"][table_name]}))
		t.close()
	return dir

func _init() -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		push_error("fixture not found: %s" % FIXTURE)
		quit(1)
		return
	var fx: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	var dir := _write_pack(fx)
	var reg := AbilityRegistry.new()
	Handlers.register_all(reg)
	var db := ContentDb.load_pack(String(fx["pack"]), dir, reg, {
		"unit": "unit.json", "unit_upg": "unit_upg.json",
		"ability_num": "ability_num.json"})
	var r := Roster.new(db)

	print("\n[1] the corpus loads")
	var want_names: Array = fx["names"]
	var got_names := r.names()
	var names_ok := got_names.size() == want_names.size()
	if names_ok:
		for i in want_names.size():
			if String(got_names[i]) != String(want_names[i]):
				names_ok = false
	_check(names_ok, "roster names match, in the same order",
		"got %s" % str(got_names))
	_check(r.build("Не существует") == null, "an unknown name returns null")

	print("\n[2] stats come from the table")
	for unit_name in fx["built"]:
		var want: Dictionary = fx["built"][unit_name]["stats"]
		var built := r.build(String(unit_name))
		if built == null:
			_check(false, "%s builds" % unit_name)
			continue
		var bad := ""
		for key in want:
			var got: int = int(built.unit.get(String(key)))
			if got != int(want[key]):
				bad += " %s=%d/%d" % [key, got, int(want[key])]
		_check(bad == "", "%s stats" % unit_name, bad)

	print("\n[3] compound rows resolve PER OPCODE, not all-or-nothing")
	for unit_name in fx["built"]:
		var case: Dictionary = fx["built"][unit_name]
		var built := r.build(String(unit_name))
		var want_mods: Array = case["modifiers"]
		var ok := built.unit.modifiers.size() == want_mods.size()
		var detail := "%d/%d modifiers" % [built.unit.modifiers.size(),
			want_mods.size()]
		if ok:
			for i in want_mods.size():
				var m: Modifier = built.unit.modifiers[i]
				var w: Dictionary = want_mods[i]
				if m.ability != int(w["ability"]) \
						or String(m.handler) != String(w["handler"]) \
						or int(m.hook) != int(w["hook"]) \
						or m.power != int(w["power"]) \
						or m.source != String(w["source"]):
					ok = false
					detail = "modifier %d differs: %d/%s vs %d/%s" % [
						i, m.ability, m.handler, int(w["ability"]),
						String(w["handler"])]
		_check(ok, "%s modifiers" % unit_name, detail)

	print("\n[4] failures are reported, never silently dropped")
	for unit_name in fx["built"]:
		var case: Dictionary = fx["built"][unit_name]
		var built := r.build(String(unit_name))
		var want_un: Array = case["unresolved"]
		var ok := built.unresolved.size() == want_un.size()
		var detail := "%d/%d unresolved" % [built.unresolved.size(),
			want_un.size()]
		if ok:
			for i in want_un.size():
				var u: Roster.Unresolved = built.unresolved[i]
				var w: Dictionary = want_un[i]
				if u.upgrade_index != int(w["upgrade_index"]) \
						or u.reason != String(w["reason"]):
					ok = false
					detail = "entry %d: '%s' vs '%s'" % [i, u.reason,
						String(w["reason"])]
		_check(ok, "%s unresolved entries" % unit_name, detail)
		_check(built.complete() == bool(case["complete"]),
			"%s completeness = %s" % [unit_name, bool(case["complete"])])

	print("\n[5] coverage — the content-side progress meter")
	var cov := r.coverage()
	var want_cov: Dictionary = fx["coverage"]
	_check(cov["units"] == int(want_cov["units"]),
		"units examined: %d" % int(want_cov["units"]), "got %d" % cov["units"])
	_check(cov["complete"] == int(want_cov["complete"]),
		"complete: %d" % int(want_cov["complete"]), "got %d" % cov["complete"])
	_check(cov["partial"] == int(want_cov["partial"]),
		"partial: %d" % int(want_cov["partial"]), "got %d" % cov["partial"])
	_check(int(cov["complete"]) + int(cov["partial"]) == int(cov["units"]),
		"and each unit is one or the other, never both")

	print("\n[6] building is deterministic and unshared")
	var a := r.build("Мечник")
	var b := r.build("Мечник")
	var same := a.unit.modifiers.size() == b.unit.modifiers.size()
	if same:
		for i in a.unit.modifiers.size():
			if a.unit.modifiers[i].ability != b.unit.modifiers[i].ability:
				same = false
	_check(same, "the same unit builds the same modifiers in the same order")
	_check(a.unit != b.unit, "but as separate instances — no shared state")

	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
