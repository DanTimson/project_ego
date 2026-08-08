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

class MaxRollRng extends Rng:
	func _init() -> void:
		super(0)

	func roll(x: int, _stream: StringName = &"combat") -> int:
		return maxi(0, x - 1)


func _trace_index(lines: Array, fragment: String) -> int:
	for i in lines.size():
		if fragment in String(lines[i]):
			return i
	return -1


func _check(ok: bool, what: String, detail: String = "") -> void:
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("  — " + detail) if detail != "" else ""])
	if not ok:
		failures += 1


func _fighter(unit_name: String, at: Array, overrides: Dictionary = {}) -> Dictionary:
	var unit := {
		"name": unit_name, "at": at, "attack": 8, "ranged_attack": 8,
		"shooting_range": 8, "ammo": 2, "counter_attack": 3,
		"defence": 0, "ranged_defence": 0, "life": 40,
		"stamina": 10, "stamina_base": 10, "morale": 10, "speed": 5,
	}
	unit.merge(overrides, true)
	return unit


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
	var r8_result := _run_profile_combat(r8_spec)
	var final: Dictionary = r8_result["final"]["attacker"]
	_check(final["steps_this_round"] == 1, "the R8 vector has movement history")
	_check(final["movement_remaining"] == 0,
		"the ranged executor clears capacity after comparing live value 3")
	_check(_trace_index(r8_result["log"], "effective speed 3") >= 0,
		"the pre-clear capacity/effective-speed comparison is trace-visible")
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
			and restored_final["movement_remaining"] == 0,
		"restored live capacity is compared, then ranged execution clears it")
	_check(_trace_index(restored_result["log"], "effective speed 4") >= 0,
		"restored capacity comparison survives reselection and is traced")
	_check(restored_final["stamina"] == 9,
		"restored capacity costs 1 despite nonzero movement history")


func _numeric_modifier(ability: int, stat: String = "", power: int = 0) -> Dictionary:
	var modifier := {
		"ability": ability, "handler": "modifier_%02x" % ability,
		"hook": "DAMAGE_VS_TARGET", "power": power,
		"source": "modifier %02x" % ability,
	}
	if stat != "":
		modifier["handler"] = "stat_delta"
		modifier["hook"] = "STAT_PASSIVE"
		modifier["params"] = {"stat": stat}
	return modifier


func _test_melee_numeric_tranche_integration() -> void:
	print("\n[integration] melee R3/R9/R10 ordering and live state")
	var spec := {
		"name": "numeric melee integration", "profile": "genesis", "seed": 1,
		"battlefield": {"width": 8, "height": 3, "tiles": []},
		"sides": [
			{"id": 0, "is_attacker": true, "leader_initiative": 1, "units": [{
				"name": "attacker", "at": [0, 0], "attack": 9,
				"counter_attack": 0, "defence": 0, "life": 30,
				"stamina": 10, "stamina_base": 10, "morale": 10, "speed": 8,
				"conditional_bonus": 5,
				"modifiers": [_numeric_modifier(0x25)],
			}]},
			{"id": 1, "leader_initiative": 0, "units": [{
				"name": "target", "at": [4, 0], "attack": 0,
				"counter_attack": 0, "defence": 3, "life": 30,
				"stamina": 0, "morale": 10, "speed": 1,
				"modifiers": [_numeric_modifier(4, "defence", 4)],
			}]},
		],
		"commands": [{"op": "attack", "unit": "attacker", "target": "target"}],
	}
	var result := Scenario.new(spec, MaxRollRng.new()).run()
	var lines: Array = result["log"]
	var entry := _trace_index(lines, "command-entry charge |")
	var movement := _trace_index(lines, "closes to")
	var conditional := _trace_index(lines, "conditional attack contribution")
	var randomisation := _trace_index(lines, "attack randomisation")
	var provider := _trace_index(lines, "defence provider total")
	var halving := _trace_index(lines, "zero-stamina defence halving")
	var subtraction := _trace_index(lines, "defence subtraction")
	var consumption := _trace_index(lines, "command-entry charge consumption")
	_check(result["final"]["target"]["life"] == 19,
		"exact target life is 30 - (9 resolved + 2 charge) = 19")
	_check(entry >= 0 and entry < movement,
		"modifier 0x25 applicability and value are traced before approach")
	_check(conditional < randomisation and randomisation < provider
			and provider < halving and halving < subtraction
			and subtraction < consumption,
		"R10 -> randomisation -> R9 -> defence -> R3 consumption is trace-visible")
	_check("value 2" in String(lines[entry]),
		"command-entry trace records charge value 2")


func _ranged_numeric_spec(base_ranged_attack: int = 20,
		later_environment_provider: bool = false) -> Dictionary:
	var spec := {
		"name": "numeric ranged integration", "profile": "genesis", "seed": 1,
		"battlefield": {"width": 8, "height": 3,
			"tiles": [{"col": 1, "row": 0, "stam_cost": 2}]},
		"sides": [
			{"id": 0, "is_attacker": true, "leader_initiative": 1, "units": [{
				"name": "shooter", "at": [0, 0], "ranged_attack": base_ranged_attack,
				"shooting_range": 8, "ammo": 2, "counter_attack": 0,
				"defence": 0, "life": 30, "stamina": 0, "stamina_base": 10,
				"morale": 10, "speed": 4, "conditional_bonus": 5,
				"modifiers": [_numeric_modifier(0x12)],
			}]},
			{"id": 1, "leader_initiative": 0, "units": [{
				"name": "target", "at": [3, 0], "counter_attack": 0,
				"ranged_defence": 3, "life": 20, "stamina": 0,
				"morale": 10, "speed": 1,
				"modifiers": [_numeric_modifier(5, "ranged_defence", 4)],
			}]},
		],
		"commands": [
			{"op": "move", "unit": "shooter", "to": [1, 0]},
			{"op": "shoot", "unit": "shooter", "target": "target"},
		],
	}
	if later_environment_provider:
		spec["sides"][0]["units"][0]["auras"] = [{
			"id": "later-ranged-provider", "name": "later ranged provider",
			"scope": "SELF", "affects": "ALLY",
			"modifiers": [_numeric_modifier(2, "ranged_attack", 6)],
		}]
	return spec


func _test_ranged_numeric_tranche_integration() -> void:
	print("\n[integration] ranged R6/R8/R9/R11 ordering and live state")
	var result := Scenario.new(_ranged_numeric_spec(), MaxRollRng.new()).run()
	var lines: Array = result["log"]
	var shooter: Dictionary = result["final"]["shooter"]
	_check(result["final"]["target"]["life"] == 16,
		"zero-stamina attack 8 randomises to 7, then R9 defence 3 gives 4 damage")
	_check(shooter["stamina"] == 0 and shooter["movement_remaining"] == 0
			and shooter["steps_this_round"] == 1 and shooter["action_spent"],
		"modifier 0x12 preserves stamina while ranged execution ends activation")
	var discriminator := _trace_index(lines, "live-capacity stamina discriminator")
	_check(discriminator >= 0 and "effective speed 2" in String(lines[discriminator])
			and "selected base cost 2" in String(lines[discriminator]),
		"R8 traces capacity 1 < effective speed 2 and selects cost 2")
	_check(_trace_index(lines, "modifier 0x12 stamina mutation suppression") >= 0,
		"R11 suppression is visible at covered mutation sites")
	_check(_trace_index(lines, "defence provider total: 7 -> 7") >= 0
			and _trace_index(lines, "zero-stamina defence halving: 7 -> 3") >= 0,
		"R9 ranged providers precede exact-zero halving")
	_check(_trace_index(lines, "conditional attack contribution") == -1,
		"the conditional numeric stage is excluded from ranged")

	var zero_scenario := Scenario.new(
		_ranged_numeric_spec(0, true), MaxRollRng.new())
	var later: Array = zero_scenario.environment(zero_scenario.units["shooter"])
	var has_positive_later := false
	for modifier in later:
		if (modifier as Modifier).power == 6 \
				and String((modifier as Modifier).params.get("stat", "")) == "ranged_attack":
			has_positive_later = true
	_check(has_positive_later,
		"distinguishing vector has a positive environment/aura provider")
	var zero := zero_scenario.run()
	_check(zero["final"]["target"]["life"] == 20,
		"R6 zero early sum returns before the positive later provider")
	_check(_trace_index(zero["log"], "ranged early provider total: 0 -> 0") >= 0
			and _trace_index(zero["log"], "later ranged provider") == -1,
		"trace shows the accepted early cutoff without resolving the aura")


func _test_action_terminality() -> void:
	print("\n[CX-009] terminal actions close only their actor's activation")
	var melee_spec := {
		"name": "melee terminality", "profile": "native", "seed": 9,
		"battlefield": {"width": 7, "height": 3, "tiles": []},
		"sides": [
			{"id": 0, "is_attacker": true, "leader_initiative": 2,
				"units": [_fighter("actor", [0, 0]), _fighter("ally", [0, 2])]},
			{"id": 1, "leader_initiative": 1,
				"units": [_fighter("defender", [3, 0], {"attack": 1})]},
		],
		"commands": [
			{"op": "move", "unit": "actor", "to": [1, 0]},
			{"op": "attack", "unit": "actor", "target": "defender"},
			{"op": "move", "unit": "actor", "to": [0, 0]},
			{"op": "attack", "unit": "actor", "target": "defender"},
		],
	}
	var melee := Scenario.new(melee_spec)
	var melee_result := melee.run()
	var actor: Combatant = melee.units["actor"]
	var ally: Combatant = melee.units["ally"]
	var defender: Combatant = melee.units["defender"]
	_check(actor.action_spent and actor.movement_remaining > 0
			and not ActionPoints.has_resources(actor),
		"move -> melee is terminal despite leftover movement")
	_check(melee.state.active_side == 0 and ActionPoints.has_resources(ally),
		"melee ends only its actor; the same side's ally remains eligible")
	_check(not defender.action_spent and ActionPoints.has_resources(defender),
		"the defender's counterattack does not spend its activation")
	var melee_refusals := 0
	for line in melee_result["log"]:
		if "actor has already acted" in String(line):
			melee_refusals += 1
	_check(melee_refusals == 1
			and "actor cannot reach 0,0" in "\n".join(melee_result["log"]),
		"movement and a second attack are refused after terminal melee")

	var refused_spec: Dictionary = melee_spec.duplicate(true)
	refused_spec["sides"][0]["units"] = [
		_fighter("actor", [0, 0], {"speed": 1}), _fighter("ally", [0, 2])]
	refused_spec["sides"][1]["units"] = [_fighter("defender", [6, 0])]
	refused_spec["commands"] = [
		{"op": "attack", "unit": "actor", "target": "defender"}]
	var refused := Scenario.new(refused_spec)
	var refused_result := refused.run()
	_check("cannot reach" in "\n".join(refused_result["log"])
			and not (refused.units["actor"] as Combatant).action_spent,
		"an unreachable melee refusal is non-terminal")

	var ranged_spec: Dictionary = melee_spec.duplicate(true)
	ranged_spec["name"] = "ranged terminality"
	ranged_spec["sides"][1]["units"][0]["at"] = [5, 0]
	ranged_spec["commands"] = [
		{"op": "move", "unit": "actor", "to": [1, 0]},
		{"op": "shoot", "unit": "actor", "target": "defender"},
		{"op": "shoot", "unit": "actor", "target": "defender"},
		{"op": "move", "unit": "actor", "to": [0, 0]},
	]
	var ranged := Scenario.new(ranged_spec)
	var ranged_result := ranged.run()
	var ranged_actor: Combatant = ranged.units["actor"]
	var discriminator := _trace_index(
		ranged_result["log"], "live-capacity stamina discriminator")
	var capacity_clear := _trace_index(
		ranged_result["log"], "ranged activation capacity clear")
	_check(ranged_actor.action_spent and ranged_actor.movement_remaining == 0
			and ranged_actor.ammo == 1,
		"move/history -> ranged is terminal and a refused second shot spends no ammo")
	_check(discriminator >= 0 and discriminator < capacity_clear,
		"R8 evaluates live capacity before ranged terminal clearing")
	var ranged_refusals := 0
	for line in ranged_result["log"]:
		if "actor has already acted" in String(line):
			ranged_refusals += 1
	_check(ranged_refusals == 1
			and "actor cannot reach 0,0" in "\n".join(ranged_result["log"]),
		"shooting and movement are refused after terminal ranged resolution")

	var action_spec := {
		"name": "active action terminality", "profile": "native", "seed": 3,
		"battlefield": {"width": 5, "height": 3, "tiles": []},
		"actions": [
			{"id": "terminal", "name": "Terminal fixture", "target": 0,
				"consumes_action": true,
				"grants": [["terminal-effect", 1, 1]]},
			{"id": "free", "name": "Free fixture", "target": 0,
				"consumes_action": false, "grants": [["free-effect", 1, 1]]},
			{"id": "unavailable", "name": "Unavailable fixture", "target": 0,
				"cost_stamina": 99, "consumes_action": true,
				"grants": [["unavailable-effect", 1, 1]]},
		],
		"sides": [
			{"id": 0, "is_attacker": true, "leader_initiative": 2,
				"units": [_fighter("consumer", [0, 0]),
					_fighter("exception", [0, 2])]},
			{"id": 1, "leader_initiative": 1,
				"units": [_fighter("target", [4, 0])]},
		],
		"commands": [
			{"op": "move", "unit": "consumer", "to": [1, 0]},
			{"op": "action", "unit": "consumer", "action": "terminal"},
			{"op": "move", "unit": "consumer", "to": [0, 0]},
			{"op": "action", "unit": "consumer", "action": "terminal"},
			{"op": "action", "unit": "exception", "action": "unavailable"},
			{"op": "action", "unit": "exception", "action": "free"},
			{"op": "move", "unit": "exception", "to": [1, 2]},
		],
	}
	var active := Scenario.new(action_spec)
	var active_result := active.run()
	var consumer: Combatant = active.units["consumer"]
	var exception: Combatant = active.units["exception"]
	var active_log := "\n".join(active_result["log"])
	_check(consumer.action_spent and consumer.movement_remaining > 0
			and not ActionPoints.has_resources(consumer),
		"resolved consuming Action policy terminates the actor")
	_check("consumer cannot reach 0,0" in active_log
			and "cannot use Terminal fixture: already acted" in active_log,
		"ordinary and consuming-action follow-ups are refused")
	_check("cannot use Unavailable fixture: not enough stamina" in active_log
			and exception.stamina == 10,
		"an unavailable action refusal is non-terminal and spends nothing")
	_check(not exception.action_spent and exception.steps_this_round == 1
			and ActionPoints.has_resources(exception),
		"resolved non-consuming Action policy remains a real exception")


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
	_test_melee_numeric_tranche_integration()
	_test_ranged_numeric_tranche_integration()
	_test_action_terminality()

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
