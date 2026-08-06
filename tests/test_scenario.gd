extends SceneTree

## Differential test: the whole engine against the Python oracle.
##
## Run: godot --headless --script tests/test_scenario.gd
##
## This is the integration test. Pathfinding updates live capacity and
## command-entry coordinates; the composed profile rule resolves primary-melee
## charge; stamina scales the ordinary attack; the RNG rolls it; defence reduces
## it; then charge is added. Comparing the log LINE FOR LINE means a
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


func _profile_combat_spec(profile_name: String = "genesis",
		attacker_at: Vector2i = Vector2i(0, 0),
		target_at: Vector2i = Vector2i(4, 0),
		charge_modifier: bool = true) -> Dictionary:
	var attacker := {
		"name": "attacker", "at": [attacker_at.x, attacker_at.y],
		"attack": 10, "ranged_attack": 10, "shooting_range": 8,
		"ammo": 3, "counter_attack": 0, "defence": 0,
		"ranged_defence": 0, "life": 100, "stamina": 10,
		"stamina_base": 10, "morale": 10, "speed": 8,
	}
	if charge_modifier:
		# The inert handler keeps applicability at the Genesis composition seam.
		attacker["modifiers"] = [{
			"ability": 0x25, "handler": "genesis_charge",
			"hook": "DAMAGE_VS_TARGET", "source": "charge",
		}]
	var target := {
		"name": "target", "at": [target_at.x, target_at.y],
		"attack": 0, "counter_attack": 0, "defence": 0,
		"ranged_defence": 0, "life": 100, "stamina": 10,
		"morale": 10, "speed": 1,
	}
	return {
		"name": "combat profile integration", "profile": profile_name, "seed": 1,
		"battlefield": {"width": 8, "height": 3, "tiles": []},
		"sides": [
			{"id": 0, "is_attacker": true, "leader_initiative": 1,
				"units": [attacker]},
			{"id": 1, "leader_initiative": 0, "units": [target]},
		],
		"commands": [{"op": "attack", "unit": "attacker", "target": "target"}],
	}


func _run_profile_combat(combat_spec: Dictionary) -> Dictionary:
	# Inject the same named-stream generator to isolate charge policy from the
	# independently selected profile RNG topology.
	return Scenario.new(combat_spec.duplicate(true), Rng.new(123)).run()


func _with_charge_aura(combat_spec: Dictionary,
		source_at: Vector2i) -> Dictionary:
	combat_spec["sides"][0]["units"].append({
		"name": "charge aura source", "at": [source_at.x, source_at.y],
		"attack": 0, "counter_attack": 0, "defence": 0,
		"ranged_defence": 0, "life": 100, "stamina": 10,
		"stamina_base": 10, "morale": 10, "speed": 0,
		"auras": [{
			"id": "charge-aura", "scope": "ADJACENT", "affects": "ALLY",
			"stacking": "MAXIMUM",
			"modifiers": [{
				"ability": 0x25, "handler": "genesis_charge",
				"hook": "DAMAGE_VS_TARGET",
			}],
		}],
	})
	return combat_spec


func _has_charge_modifier(modifiers: Array) -> bool:
	for modifier in modifiers:
		if (modifier as Modifier).ability == 0x25:
			return true
	return false


func _test_genesis_command_entry_charge() -> void:
	print("\n[R3] Genesis command-entry charge")
	var adjacent := _profile_combat_spec(
		"genesis", Vector2i(3, 0), Vector2i(4, 0), true)
	var adjacent_plain := _profile_combat_spec(
		"genesis", Vector2i(3, 0), Vector2i(4, 0), false)
	var no_move := _run_profile_combat(adjacent)
	var no_move_plain := _run_profile_combat(adjacent_plain)
	_check(no_move["final"]["target"]["life"]
			== no_move_plain["final"]["target"]["life"],
		"a no-movement attack receives zero charge")

	# A resolved Genesis value of zero still selects the combined-damage/current-
	# life-cap path. Native supplies null and preserves ordinary accounting.
	var genesis_cap := _profile_combat_spec(
		"genesis", Vector2i(3, 0), Vector2i(4, 0), true)
	genesis_cap["sides"][1]["units"][0]["life"] = 3
	var native_uncapped := _profile_combat_spec(
		"native", Vector2i(3, 0), Vector2i(4, 0), true)
	native_uncapped["sides"][1]["units"][0]["life"] = 3
	var genesis_cap_result := _run_profile_combat(genesis_cap)
	var native_uncapped_result := _run_profile_combat(native_uncapped)
	_check("hits target for 3" in "\n".join(genesis_cap_result["log"]),
		"resolved zero charge still uses Genesis combined/current-life cap")
	_check("hits target for 9" in "\n".join(native_uncapped_result["log"]),
		"native zero-charge absence retains ordinary uncapped accounting")

	var ordinary := _profile_combat_spec(
		"genesis", Vector2i(0, 0), Vector2i(4, 0), true)
	var ordinary_plain := _profile_combat_spec(
		"genesis", Vector2i(0, 0), Vector2i(4, 0), false)
	var charged := _run_profile_combat(ordinary)
	var plain := _run_profile_combat(ordinary_plain)
	_check(Charge.command_entry_charge(Vector2i(0, 0), Vector2i(4, 0), true) == 2,
		"ordinary command-entry distance computes max(L1 - 2, 0)")
	_check("closes to" in "\n".join(charged["log"]),
		"the charged command performs automatic approach movement")
	_check(charged["final"]["target"]["life"] < plain["final"]["target"]["life"],
		"the pre-approach coordinates survive into the primary attack",
		"%d vs %d" % [charged["final"]["target"]["life"],
			plain["final"]["target"]["life"]])

	# Existing adjacency-aura machinery changes 0x25 applicability across the
	# automatic approach, so no production-only test hook is needed.
	var entry_aura_spec := _with_charge_aura(_profile_combat_spec(
		"genesis", Vector2i(0, 0), Vector2i(4, 0), false), Vector2i(0, 1))
	var entry_aura := Scenario.new(entry_aura_spec.duplicate(true), Rng.new(123))
	var entry_attacker: Combatant = entry_aura.units["attacker"]
	_check(_has_charge_modifier(entry_aura.environment(entry_attacker)),
		"0x25 is effective at command entry through an adjacent aura")
	var entry_result := entry_aura.run()
	_check(not _has_charge_modifier(entry_aura.environment(entry_attacker)),
		"the entry aura is no longer effective after automatic approach")
	_check(entry_result["final"]["target"]["life"]
			== charged["final"]["target"]["life"],
		"entry-only 0x25 still supplies charge before movement",
		"%d vs charged control %d" % [
			entry_result["final"]["target"]["life"],
			charged["final"]["target"]["life"]])

	var exit_aura_spec := _with_charge_aura(_profile_combat_spec(
		"genesis", Vector2i(0, 0), Vector2i(4, 0), false), Vector2i(3, 1))
	var exit_aura := Scenario.new(exit_aura_spec.duplicate(true), Rng.new(123))
	var exit_attacker: Combatant = exit_aura.units["attacker"]
	_check(not _has_charge_modifier(exit_aura.environment(exit_attacker)),
		"0x25 is absent at command entry in the inverse aura vector")
	var exit_result := exit_aura.run()
	_check(_has_charge_modifier(exit_aura.environment(exit_attacker)),
		"0x25 becomes effective only after automatic approach")
	_check(exit_result["final"]["target"]["life"]
			== plain["final"]["target"]["life"],
		"post-approach-only 0x25 cannot retroactively supply charge",
		"%d vs plain control %d" % [
			exit_result["final"]["target"]["life"],
			plain["final"]["target"]["life"]])

	var prior := _profile_combat_spec(
		"genesis", Vector2i(1, 0), Vector2i(4, 0), true)
	prior["commands"] = [
		{"op": "move", "unit": "attacker", "to": [0, 0]},
		{"op": "move", "unit": "attacker", "to": [1, 0]},
		{"op": "attack", "unit": "attacker", "target": "target"},
	]
	var prior_result := _run_profile_combat(prior)
	var same_entry := _run_profile_combat(_profile_combat_spec(
		"genesis", Vector2i(1, 0), Vector2i(4, 0), true))
	_check(prior_result["final"]["attacker"]["steps_this_round"]
			> same_entry["final"]["attacker"]["steps_this_round"],
		"move-away-and-back accumulates diagnostic path steps")
	_check(prior_result["final"]["target"]["life"]
			== same_entry["final"]["target"]["life"],
		"but prior path length does not accumulate Genesis charge")

	var split := _profile_combat_spec(
		"genesis", Vector2i(0, 0), Vector2i(5, 0), true)
	split["commands"] = [
		{"op": "move", "unit": "attacker", "to": [1, 0]},
		{"op": "extra_turn", "unit": "attacker"},
		{"op": "attack", "unit": "attacker", "target": "target"},
	]
	var split_result := _run_profile_combat(split)
	var split_control := _run_profile_combat(_profile_combat_spec(
		"genesis", Vector2i(1, 0), Vector2i(5, 0), true))
	_check(split_result["final"]["attacker"]["steps_this_round"]
			> split_control["final"]["attacker"]["steps_this_round"],
		"split activation preserves diagnostic prior movement")
	_check(split_result["final"]["target"]["life"]
			== split_control["final"]["target"]["life"],
		"split activation recomputes charge from its command-entry tile")

	var native := _profile_combat_spec(
		"native", Vector2i(0, 0), Vector2i(4, 0), true)
	var native_result := _run_profile_combat(native)
	_check(native_result["final"]["target"]["life"]
			== plain["final"]["target"]["life"],
		"the native counterpart receives no charge")


func _test_genesis_r8_live_capacity() -> void:
	print("\n[R8] Genesis live-capacity attack stamina")
	var r8_spec := _profile_combat_spec(
		"genesis", Vector2i(0, 0), Vector2i(4, 0), false)
	var attacker: Dictionary = r8_spec["sides"][0]["units"][0]
	attacker["speed"] = 4
	attacker["stamina"] = 5
	attacker["stamina_base"] = 5
	r8_spec["battlefield"]["tiles"] = [{"col": 1, "row": 0, "stam_cost": 2}]
	r8_spec["commands"] = [
		{"op": "move", "unit": "attacker", "to": [1, 0]},
		{"op": "shoot", "unit": "attacker", "target": "target"},
	]
	var final: Dictionary = _run_profile_combat(r8_spec)["final"]["attacker"]
	_check(final["steps_this_round"] == 1, "the R8 vector has movement history")
	_check(final["movement_remaining"] == 3,
		"movement leaves capacity equal to stamina-reduced effective speed")
	_check(final["stamina"] == 2,
		"strict live-capacity comparison charges 1, not history-based 2",
		"final stamina %d (history rule would leave 1)" % final["stamina"])

	var restored := _profile_combat_spec(
		"genesis", Vector2i(0, 0), Vector2i(4, 0), false)
	var restored_attacker: Dictionary = restored["sides"][0]["units"][0]
	restored_attacker["speed"] = 4
	restored_attacker["stamina"] = 10
	restored_attacker["stamina_base"] = 10
	restored["commands"] = [
		{"op": "move", "unit": "attacker", "to": [1, 0]},
		{"op": "extra_turn", "unit": "attacker"},
		{"op": "shoot", "unit": "attacker", "target": "target"},
	]
	var restored_result := _run_profile_combat(restored)
	var restored_final: Dictionary = restored_result["final"]["attacker"]
	_check(restored_final["steps_this_round"] == 1
			and restored_final["movement_remaining"] == 4,
		"existing extra-turn helper expresses restored live capacity")
	_check(restored_final["stamina"] == 9,
		"restored capacity costs 1 despite nonzero movement history")


func _init() -> void:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		push_error("fixture not found: %s" % FIXTURE)
		quit(1)
		return
	var fx: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	print("\n[profiles] strict identity and RNG selection")
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

	var missing_spec := base.duplicate(true)
	missing_spec.erase("profile")
	missing_spec.erase("rng")
	var missing: Dictionary = Scenario.profile_configuration(missing_spec)
	_check(missing["profile"] == ""
			and missing["error"] == Scenario.PROFILE_REQUIRED,
		"missing profile is rejected")

	var old_rng_spec := base.duplicate(true)
	old_rng_spec.erase("profile")
	old_rng_spec["rng"] = "legacy"
	var old_rng: Dictionary = Scenario.profile_configuration(old_rng_spec)
	_check(old_rng["profile"] == "" and old_rng["error"] == Scenario.RNG_REMOVED,
		"old rng key is rejected with migration guidance")

	var conflict_spec := base.duplicate(true)
	conflict_spec["profile"] = "native"
	conflict_spec["rng"] = "legacy"
	var conflict: Dictionary = Scenario.profile_configuration(conflict_spec)
	_check(conflict["profile"] == "" and conflict["error"] == Scenario.RNG_REMOVED,
		"rng is rejected even alongside a profile")

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

	var injected := Rng.new(12345)
	var direct := Scenario.new(genesis_spec, injected)
	_check(direct.rng == injected, "direct RNG dependency injection remains supported")

	_test_genesis_command_entry_charge()
	_test_genesis_r8_live_capacity()

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
