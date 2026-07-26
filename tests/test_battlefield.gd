extends SceneTree

## Differential test: GDScript hex grid vs the Python oracle.
##
## Run: godot --headless --script tests/test_battlefield.gd
##
## No RNG, but the paths are the part that matters. They are compared hex for
## hex, not by length: equal-cost routes are common on open ground, so a
## tie-break difference between the two implementations would show up here and
## nowhere else until replays started diverging.

const FIXTURE := "res://tests/fixtures/battlefield_fixture.json"

var failures: int = 0

func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1

func _offsets(path: Array) -> Array:
	var out: Array = []
	for h in path:
		var o := Battlefield.axial_to_offset(h)
		out.append([o.x, o.y])
	return out

func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if int(a[i][0]) != int(b[i][0]) or int(a[i][1]) != int(b[i][1]):
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

	print("\n[1] dimensions are parameters, not constants")
	for case in fx["dimensions"]:
		var bf := Battlefield.new(int(case["width"]), int(case["height"]))
		_check(bf.tiles.size() == int(case["tiles"]),
			"%dx%d holds %d tiles" % [int(case["width"]), int(case["height"]),
				int(case["tiles"])],
			"got %d" % bf.tiles.size())
	var small := Battlefield.new(3, 3)
	_check(not small.contains(Vector2i(99, 99)), "out-of-bounds hexes are absent")
	_check(small.tile(Vector2i(99, 99)) == null, "and tile() returns null, not an error")

	print("\n[2] coordinates and adjacency")
	var ok_rt := true
	for c in 8:
		for r in 8:
			var back := Battlefield.axial_to_offset(Battlefield.offset_to_axial(c, r))
			if back != Vector2i(c, r):
				ok_rt = false
	_check(ok_rt, "offset <-> axial round-trips")
	var grid := Battlefield.new(7, 7)
	var centre := Battlefield.offset_to_axial(3, 3)
	_check(grid.neighbours(centre).size() == 6, "an interior hex has six neighbours")
	_check(grid.neighbours(Battlefield.offset_to_axial(0, 0)).size() < 6,
		"a corner has fewer — out-of-bounds are filtered, not wrapped")
	var order_ok := true
	for i in 6:
		if Battlefield.neighbour_of(centre, i) - centre != Battlefield.NEIGHBOURS[i]:
			order_ok = false
	_check(order_ok, "neighbour ORDER is fixed — iteration must match the oracle")

	print("\n[3] range — shooting range and aura radius share this metric")
	for case in fx["range"]:
		var bf := Battlefield.new(int(case["width"]), int(case["height"]))
		var c := Battlefield.offset_to_axial(int(case["centre"][0]), int(case["centre"][1]))
		var radius := int(case["radius"])
		_check(bf.within(c, radius).size() == int(case["within"]),
			"radius %d covers %d hexes" % [radius, int(case["within"])],
			"got %d" % bf.within(c, radius).size())
		_check(bf.ring(c, radius).size() == int(case["ring"]),
			"ring %d is %d hexes" % [radius, int(case["ring"])],
			"got %d" % bf.ring(c, radius).size())

	print("\n[4] lines")
	for case in fx["lines"]:
		var bf := Battlefield.new(9, 9)
		var a := Battlefield.offset_to_axial(int(case["from"][0]), int(case["from"][1]))
		var b := Battlefield.offset_to_axial(int(case["to"][0]), int(case["to"][1]))
		var got := _offsets(bf.line(a, b))
		_check(_same(got, case["line"]),
			"line %s -> %s" % [str(case["from"]), str(case["to"])],
			"got %s" % str(got))

	print("\n[5] paths — compared hex for hex, not by length")
	for case in fx["paths"]:
		var bf := Battlefield.new(int(case["width"]), int(case["height"]))
		for w in case["walls"]:
			bf.tile(Battlefield.offset_to_axial(int(w[0]), int(w[1]))).move_cost = 0
		for o in case["occupied"]:
			bf.place(RefCounted.new(), Battlefield.offset_to_axial(int(o[0]), int(o[1])))
		var a := Battlefield.offset_to_axial(int(case["from"][0]), int(case["from"][1]))
		var b := Battlefield.offset_to_axial(int(case["to"][0]), int(case["to"][1]))
		var p := bf.path(a, b, bool(case["ignore_occupants"]))
		var want: Variant = case["path"]
		if want == null:
			_check(p.is_empty(), "%s: unreachable" % case["label"],
				"got %d steps" % p.size())
		else:
			_check(_same(_offsets(p), want),
				"%s: %d steps" % [case["label"], (want as Array).size()],
				"got %s" % str(_offsets(p)))

	print("\n[6] determinism")
	var d := Battlefield.new(9, 9)
	var a := Battlefield.offset_to_axial(0, 0)
	var b := Battlefield.offset_to_axial(6, 4)
	var first := _offsets(d.path(a, b))
	var stable := true
	for i in 20:
		if not _same(_offsets(Battlefield.new(9, 9).path(a, b)), first):
			stable = false
	_check(stable, "20 freshly built fields all produce the same path")

	print("\n[7] reachable")
	for case in fx["reachable"]:
		var bf := Battlefield.new(int(case["width"]), int(case["height"]))
		var c := Battlefield.offset_to_axial(int(case["centre"][0]), int(case["centre"][1]))
		for rough in case["rough"]:
			bf.tile(Battlefield.offset_to_axial(int(rough[0]), int(rough[1]))).move_cost = 2
		var got := bf.reachable(c, int(case["budget"])).size()
		_check(got == int(case["count"]),
			"budget %d reaches %d hexes%s" % [int(case["budget"]), int(case["count"]),
				" over rough ground" if not (case["rough"] as Array).is_empty() else ""],
			"got %d" % got)

	print("\n[8] occupancy")
	var bf := Battlefield.new(5, 5)
	var u := RefCounted.new()
	var h := Battlefield.offset_to_axial(2, 2)
	_check(bf.place(u, h), "placing on a free hex succeeds")
	_check(not bf.place(RefCounted.new(), h), "placing on an occupied hex fails")
	_check(bf.find_unit(u) == h, "find_unit locates it")
	_check(bf.adjacent_occupants(bf.neighbours(h)[0]).size() == 1,
		"adjacent_occupants backs Круговая атака and the morale triggers")
	bf.remove_occupant(h)
	_check(not bf.has_unit(u), "removal frees the hex")

	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
