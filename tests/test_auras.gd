extends SceneTree

## Aura port parity — differential against oracle/auras.py.
##
## `core/rules/auras.gd` had no test at all, and `tests/scenarios/aura_and_poison.json`
## was referenced by nothing: 213 lines of port that could diverge silently.
## Auras are the worst place for that, because nothing about them is stored —
## every call re-derives reach from positions, sides, subtypes, source liveness
## and stacking, so a divergence yields a plausible battle rather than an error.
##
## Each fixture case declares a battlefield, placed units and projected auras,
## and carries the oracle's answer for: which aura ids end up active per unit,
## the summed per-round tick, and unit state after the tick is applied.
##
## Run: godot --headless --script tests/test_auras.gd

const FIXTURE := "res://tests/fixtures/aura_fixture.json"

var _fails: Array[String] = []
var _sides: Dictionary = {}


func _check(ok: bool, label: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", label,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		_fails.append(label)


func _side_of(u: Combatant) -> String:
	return String(_sides.get(u.name, ""))


func _scope(s: String) -> Auras.Scope:
	match s:
		"battlefield": return Auras.Scope.BATTLEFIELD
		"self": return Auras.Scope.SELF
		_: return Auras.Scope.ADJACENT


func _affects(s: String) -> Auras.Side:
	match s:
		"enemy": return Auras.Side.ENEMY
		"all": return Auras.Side.ALL
		_: return Auras.Side.ALLY


func _stacking(s: String) -> Auras.Stacking:
	return Auras.Stacking.CUMULATIVE if s == "cumulative" else Auras.Stacking.MAXIMUM


func _init() -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		push_error("missing %s — run oracle/make_fixtures.py tests/fixtures/" % FIXTURE)
		quit(1)
		return
	var fx: Dictionary = JSON.parse_string(f.get_as_text())

	var n := 0
	for case in fx["cases"]:
		n += 1
		print("\n[%d] %s" % [n, String(case["label"])])
		var field := Battlefield.new(int(case["width"]), int(case["height"]))
		var units: Dictionary = {}
		_sides = {}

		for spec in case["units"]:
			var u := Combatant.new()
			u.name = String(spec["name"])
			u.life = int(spec["life"])
			u.life_base = int(spec["life_base"])
			u.stamina = int(spec["stamina"])
			u.stamina_base = int(spec["stamina_base"])
			u.morale = int(spec["morale"])
			u.morale_base = int(spec["morale_base"])
			u.alive = bool(spec["alive"])
			for sub in spec["subtypes"]:
				u.subtypes[StringName(sub)] = true
			units[u.name] = u
			_sides[u.name] = String(spec["side"])
			field.place(u, Vector2i(int(spec["q"]), int(spec["r"])))

		var by_source: Dictionary = {}
		for spec in case["auras"]:
			var a := Auras.Aura.new()
			a.id = StringName(spec["id"])
			a.name = String(spec["id"])
			a.scope = _scope(String(spec["scope"]))
			a.affects = _affects(String(spec["affects"]))
			a.stacking = _stacking(String(spec["stacking"]))
			a.power = int(spec["power"])
			a.tick = (spec["tick"] as Dictionary).duplicate()
			for sub in spec["only_subtypes"]:
				a.only_subtypes.append(StringName(sub))
			for sub in spec["except_subtypes"]:
				a.except_subtypes.append(StringName(sub))
			var src: Combatant = units[String(spec["source"])]
			a.source = src
			if not by_source.has(src):
				by_source[src] = []
			(by_source[src] as Array).append(a)

		for want in case["expected"]:
			var u: Combatant = units[String(want["unit"])]

			# 1. which auras survive side, reach, subtype and stacking filters
			var active: Array = Auras.active_for(u, by_source, field, _side_of)
			var got_ids: Array = []
			for a in active:
				got_ids.append(String(a.id))
			got_ids.sort()
			var want_ids: Array = []
			for i in want["active"]:
				want_ids.append(String(i))
			var ids_ok := got_ids.size() == want_ids.size()
			if ids_ok:
				for i in want_ids.size():
					if String(got_ids[i]) != String(want_ids[i]):
						ids_ok = false
			_check(ids_ok, "%s: active auras" % u.name,
				"got %s want %s" % [str(got_ids), str(want_ids)])

			# 2. the summed per-round tick — opposing auras add, never override
			var res: Array = Auras.tick_for(u, by_source, field, _side_of)
			var totals: Dictionary = res[0]
			var want_tick: Dictionary = want["tick"]
			var tick_ok := totals.size() == want_tick.size()
			if tick_ok:
				for k in want_tick:
					if not totals.has(k) or int(totals[k]) != int(want_tick[k]):
						tick_ok = false
			_check(tick_ok, "%s: tick totals" % u.name,
				"got %s want %s" % [str(totals), str(want_tick)])

			# 3. applying it, with caps, floors and death
			Auras.apply_tick(u, totals)
			var after: Dictionary = want["after"]
			_check(u.life == int(after["life"]) and u.stamina == int(after["stamina"])
					and u.morale == int(after["morale"])
					and u.alive == bool(after["alive"]),
				"%s: state after tick" % u.name,
				"got life %d stamina %d morale %d alive %s want %s"
					% [u.life, u.stamina, u.morale, str(u.alive), str(after)])

	print("\n%s" % ("ALL PASS" if _fails.is_empty()
		else "%d FAILURES: %s" % [_fails.size(), ", ".join(_fails)]))
	quit(1 if not _fails.is_empty() else 0)
