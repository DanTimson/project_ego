extends SceneTree

## Differential test: GDScript content loading vs the Python oracle.
##
## Run: godot --headless --script tests/test_content.gd
##
## No RNG. The point of the report is that it SEPARATES three failure kinds —
## conflating them would make the number comfortable and useless:
##
##   unbound   the pack leaves the handler empty       -> work not started
##   missing   the pack names a handler we don't have  -> a typo or a rename
##   orphaned  we implement a handler nothing binds to -> dead code

const FIXTURE := "res://tests/fixtures/content_fixture.json"

var failures: int = 0

func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1

func _write_pack(pack_id: String, abilities: Dictionary) -> String:
	var dir := "user://test_packs".path_join(pack_id)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("bindings.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"pack": pack_id, "abilities": abilities}))
	f.close()
	return dir

func _registry(handlers: Array) -> AbilityRegistry:
	var r := AbilityRegistry.new()
	for h in handlers:
		r.register(StringName(String(h)), func(_ctx, v, _p): return v)
	return r

func _pairs_match(got: Array, want: Array) -> bool:
	if got.size() != want.size():
		return false
	for i in got.size():
		if int(got[i][0]) != int(want[i][0]):
			return false
	return true

func _init() -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		push_error("fixture not found: %s" % FIXTURE)
		quit(1)
		return
	var fx: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	print("\n[1] registry")
	var r := AbilityRegistry.new()
	r.register(&"a", func(_c, v, _p): return int(v) + 1)
	_check(r.has(&"a") and not r.has(&"b"), "membership")
	_check(int(r.call_handler(&"a", {}, 1, {})) == 2, "dispatch reaches the handler")

	print("\n[2] load reports match the oracle")
	for pack_id in fx["packs"]:
		var abilities: Dictionary = fx["packs"][pack_id]
		var want: Dictionary = fx["expected"][pack_id]
		var dir := _write_pack(String(pack_id), abilities)
		var db := ContentDb.load_pack(String(pack_id), dir, _registry(fx["handlers"]))
		var rep := db.report

		_check(rep.total == int(want["total"]), "%s: total %d" % [pack_id, int(want["total"])],
			"got %d" % rep.total)
		_check(rep.usable() == int(want["usable"]),
			"%s: usable %d" % [pack_id, int(want["usable"])], "got %d" % rep.usable())
		_check(_pairs_match(rep.unbound, want["unbound"]),
			"%s: %d unbound" % [pack_id, (want["unbound"] as Array).size()],
			"got %d" % rep.unbound.size())
		_check(_pairs_match(rep.missing, want["missing"]),
			"%s: %d missing" % [pack_id, (want["missing"] as Array).size()],
			"got %d" % rep.missing.size())
		_check(str(rep.orphaned) == str(want["orphaned"]),
			"%s: orphaned handlers" % pack_id, "got %s" % str(rep.orphaned))
		_check(rep.ok() == bool(want["ok"]), "%s: ok = %s" % [pack_id, bool(want["ok"])],
			"got %s" % rep.ok())

	print("\n[3] resolve")
	for pack_id in fx["packs"]:
		var dir := "user://test_packs".path_join(String(pack_id))
		var db := ContentDb.load_pack(String(pack_id), dir, _registry(fx["handlers"]))
		var want: Dictionary = fx["expected"][pack_id]["resolve"]
		for key in want:
			var got: Array = db.resolve(int(String(key)))
			var expected_handler: String = String((want[key] as Array)[0])
			_check(String(got[0]) == expected_handler,
				"%s opcode %s -> '%s'" % [pack_id, key, expected_handler],
				"got '%s'" % String(got[0]))

	print("\n[4] the same opcode dispatches differently per pack")
	var reg := _registry(fx["handlers"])
	var g := ContentDb.load_pack("genesis_like",
		"user://test_packs/genesis_like", reg)
	var n := ContentDb.load_pack("nh_like", "user://test_packs/nh_like", reg)
	_check(String(g.resolve(30)[0]) == "magic_immunity"
		and String(n.resolve(30)[0]) == "armor_pierce",
		"opcode 30 means different things in each pack — no conditional in the rules")

	print("\n[5] failures degrade rather than crash")
	var absent := ContentDb.load_pack("nope", "user://test_packs/does_not_exist", reg)
	_check(not absent.report.errors.is_empty(),
		"an absent bindings file is an error, not a crash",
		absent.report.errors[0] if not absent.report.errors.is_empty() else "")
	_check(not absent.report.ok(), "and the pack is not ok")
	var mismatched := ContentDb.load_pack("wrong_id",
		"user://test_packs/clean", reg)
	var caught := false
	for e in mismatched.report.errors:
		if e.contains("declare"):
			caught = true
	_check(caught, "a pack id mismatch is caught")

	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
