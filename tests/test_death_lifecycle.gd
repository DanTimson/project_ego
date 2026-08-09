extends SceneTree

## CX-011 tactical death lifecycle distinguishing vectors.

var failures := 0


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1


func _marker(ability: int, remove_on_damage: bool = false) -> Status:
	var effect := Status.new()
	effect.id = StringName("runtime-%x" % ability)
	effect.remove_on_damage = remove_on_damage
	effect.modifiers.append(Modifier.make(
		ability, &"add_flat", Modifier.Hook.STAT_PASSIVE))
	return effect


func _set_statuses(unit: Combatant, values: Array) -> void:
	unit.statuses.clear()
	for value in values:
		unit.statuses.append(value)


func _setup() -> Dictionary:
	var field := Battlefield.new(5, 5)
	var victim := Combatant.new()
	victim.name = "victim"
	victim.instance_id = "victim"
	victim.life = 1
	victim.life_base = 10
	victim.stamina = 3
	victim.stamina_base = 8
	victim.morale = 7
	victim.morale_base = 12
	victim.ammo = 2
	victim.ammo_base = 5
	victim.speed = 4
	var ally := Combatant.new()
	ally.name = "ally"
	ally.instance_id = "ally"
	ally.life = 10
	ally.life_base = 10
	ally.morale = 5
	ally.morale_base = 10
	var enemy := Combatant.new()
	enemy.name = "enemy"
	enemy.instance_id = "enemy"
	enemy.life = 10
	enemy.life_base = 10
	enemy.morale = 5
	enemy.morale_base = 10
	var left := RoundLoop.Side.new()
	left.id = 0
	left.units = [victim, ally]
	var right := RoundLoop.Side.new()
	right.id = 1
	right.units = [enemy]
	var sides: Array = [left, right]
	field.place(victim, Battlefield.offset_to_axial(2, 2))
	field.place(ally, Battlefield.offset_to_axial(1, 2))
	field.place(enemy, Battlefield.offset_to_axial(3, 2))
	return {"field": field, "sides": sides, "victim": victim,
		"ally": ally, "enemy": enemy}


func _damage(context: Dictionary, resolver: Callable = Callable()) -> Dictionary:
	if not resolver.is_valid():
		resolver = func(unit: Combatant):
			return DeathLifecycle.resolve(unit, context.field, context.sides)
	return Damage.apply_received_damage(context.victim, 1, 0, resolver)


func _original_snapshot(tier: int = 2, life_base: int = 17) -> Dictionary:
	var original := Combatant.new()
	original.name = "original"
	original.content_id = "synthetic:unit/7"
	original.definition_id = 7
	original.tier = tier
	original.attack = 4
	original.counter_attack = 3
	original.life_base = life_base
	original.stamina_base = 9
	original.morale_base = 11
	original.speed = 3
	original.ammo_base = 4
	original.set_flag(&"original")
	return original.definition_snapshot()


func _replacement(definition_id: int) -> Dictionary:
	return {"name": "replacement-%d" % definition_id,
		"content_id": "synthetic:unit/%d" % definition_id,
		"tier": 4, "life_base": 20 + definition_id,
		"stamina_base": 6, "morale_base": 13, "ammo_base": 7,
		"speed": 2}


func _test_ordinary_final_death() -> void:
	print("\n[1] ordinary final death and central damage boundary")
	var c := _setup()
	_set_statuses(c.victim, [_marker(1, true), _marker(2)])
	var calls := [0]
	var outcome := Damage.apply_received_damage(c.victim, 3, 0,
		func(unit: Combatant):
			calls[0] += 1
			return DeathLifecycle.resolve(unit, c.field, c.sides))
	_check(outcome.fatal_event and not outcome.final_alive,
		"fatal_event is separate from final state")
	_check(calls[0] == 1, "fatal damage resolves exactly once")
	_check(c.victim.damage_received == [3, 0, 0, 0],
		"damage accounting remains correct")
	_check(c.victim.statuses.is_empty(), "complete status collection clears")
	_check(not c.victim.alive and not c.field.has_unit(c.victim),
		"final death is nonliving and leaves living occupancy")
	_check(c.sides[0].units.has(c.victim) and not c.victim.discarded,
		"persistent dead record remains representable")


func _test_morale_and_revival() -> void:
	print("\n[2] death morale before revival and immunity")
	var c := _setup()
	_set_statuses(c.victim, [_marker(DeathLifecycle.REVIVE)])
	var immune := Combatant.new()
	immune.name = "immune"
	immune.instance_id = "immune"
	immune.life = 10
	immune.life_base = 10
	immune.morale = 5
	immune.modifiers.append(Modifier.make(
		0x13, &"add_flat", Modifier.Hook.STAT_PASSIVE))
	c.sides[0].units.append(immune)
	c.field.place(immune, Battlefield.offset_to_axial(2, 1))
	var broken := Combatant.new()
	broken.name = "broken"
	broken.instance_id = "broken"
	broken.life = 10
	broken.life_base = 10
	broken.morale = 0
	c.sides[0].units.append(broken)
	c.field.place(broken, Battlefield.offset_to_axial(1, 3))
	var outcome := _damage(c)
	_check(outcome.fatal_event and outcome.final_alive,
		"fatal victim revives after lifecycle entry")
	_check(c.ally.morale == 4 and c.enemy.morale == 6,
		"adjacent ally loses and opponent gains morale before revival")
	_check(immune.morale == 5, "modifier 0x13 suppresses death morale")
	_check(broken.morale == 0 and broken.morale_break_accumulator == 10,
		"morale underflow becomes a ten-point break-accumulator step")


func _test_revival_preservation() -> void:
	print("\n[3] revival state preservation")
	var c := _setup()
	_set_statuses(c.victim, [_marker(DeathLifecycle.REVIVE), _marker(2)])
	c.victim.morale_break_accumulator = 30
	c.victim.movement_remaining = 2
	c.victim.action_spent = true
	var before := [c.victim.stamina, c.victim.ammo, c.victim.morale,
		c.victim.movement_remaining, c.victim.action_spent]
	_damage(c)
	_check(c.victim.life == 10 and c.victim.morale_break_accumulator == 0,
		"revival restores life and clears morale break")
	_check([c.victim.stamina, c.victim.ammo, c.victim.morale,
		c.victim.movement_remaining, c.victim.action_spent] == before,
		"revival does not refresh resources or activation")
	_check(c.victim.statuses.is_empty(), "revival clears all statuses")


func _test_rollback() -> void:
	print("\n[4] rollback alone and rollback-before-revival")
	var c := _setup()
	c.victim.name = "temporary"
	c.victim.content_id = "synthetic:unit/999"
	c.victim.definition_id = 999
	c.victim.tier = 4
	c.victim.life_base = 40
	c.victim.speed = 8
	c.victim.ammo_base = 12
	c.victim.movement_remaining = 7
	c.victim.ammo = 9
	c.victim.original_definition = _original_snapshot()
	_set_statuses(c.victim, [_marker(DeathLifecycle.ROLLBACK)])
	_damage(c)
	_check(c.victim.definition_id == 7 and c.victim.content_id == "synthetic:unit/7",
		"rollback restores original identity")
	_check(c.victim.movement_remaining == 2 and c.victim.ammo == 4,
		"rollback clamps capacity and ammunition down to restored maxima")
	_check(c.victim.stamina == 3 and c.victim.morale == 7 and not c.victim.alive,
		"rollback alone restores no life/stamina/morale and ends dead")

	c = _setup()
	c.victim.movement_remaining = 1
	c.victim.ammo = 2
	c.victim.original_definition = _original_snapshot()
	_set_statuses(c.victim, [_marker(DeathLifecycle.ROLLBACK)])
	_damage(c)
	_check(c.victim.movement_remaining == 1 and c.victim.ammo == 2,
		"rollback never raises below-maximum resources")

	c = _setup()
	c.victim.life_base = 40
	c.victim.original_definition = _original_snapshot(2, 17)
	_set_statuses(c.victim, [_marker(DeathLifecycle.ROLLBACK),
		_marker(DeathLifecycle.REVIVE)])
	_damage(c)
	_check(c.victim.alive and c.victim.life == 17 and c.victim.definition_id == 7,
		"rollback precedes revival and supplies revived maximum life")


func _test_replacement_and_precedence() -> void:
	print("\n[5] exact replacement mapping and revival precedence")
	_check([DeathLifecycle.replacement_id_for_tier(1),
		DeathLifecycle.replacement_id_for_tier(2),
		DeathLifecycle.replacement_id_for_tier(3),
		DeathLifecycle.replacement_id_for_tier(4)] == [21, 37, 56, 65],
		"tiers 1..4 map exactly to 21/37/56/65")
	for tier in range(1, 5):
		var c := _setup()
		c.victim.original_definition = _original_snapshot(tier)
		_set_statuses(c.victim, [_marker(DeathLifecycle.REPLACE), _marker(2)])
		c.victim.movement_remaining = 9
		c.victim.action_spent = true
		c.victim.morale_break_accumulator = 20
		var outcome := _damage(c,
			func(unit: Combatant):
				return DeathLifecycle.resolve(unit, c.field, c.sides,
					func(_replacement_unit: Combatant, definition_id: int):
						return _replacement(definition_id)))
		var expected := int(DeathLifecycle.REPLACEMENT_BY_TIER[tier])
		_check(outcome.final_alive and c.victim.definition_id == expected,
			"tier %d establishes exact replacement identity" % tier)
		_check([c.victim.life, c.victim.stamina, c.victim.ammo, c.victim.morale]
			== [20 + expected, 6, 7, 13],
			"tier %d replacement resets declared resources" % tier)
		_check(c.victim.statuses.is_empty()
			and c.victim.morale_break_accumulator == 0,
			"replacement clears statuses and morale break")
		_check(c.victim.movement_remaining == 9 and c.victim.action_spent,
			"replacement preserves capacity and action terminality")
		_check(c.field.has_unit(c.victim), "replacement preserves battle position")

	var c := _setup()
	c.victim.definition_id = 8
	_set_statuses(c.victim, [_marker(DeathLifecycle.REVIVE),
		_marker(DeathLifecycle.REPLACE)])
	_damage(c)
	_check(c.victim.alive and c.victim.definition_id == 8,
		"0x4A revival takes precedence over 0x5B replacement")


func _test_transfer_and_battle_owned() -> void:
	print("\n[6] side transfer and battle-owned final handling")
	var c := _setup()
	var position: Vector2i = c.field.find_unit(c.victim)
	_set_statuses(c.victim, [_marker(2)])
	c.victim.movement_remaining = 2
	c.victim.action_spent = false
	var before := [c.victim.life, c.victim.stamina, c.victim.ammo,
		c.victim.movement_remaining, c.victim.action_spent,
		c.victim.statuses.duplicate()]
	_check(DeathLifecycle.transfer_to_opposite_side(c.victim, c.sides),
		"direct living transfer succeeds")
	_check(not c.sides[0].units.has(c.victim)
		and c.sides[1].units.count(c.victim) == 1,
		"one logical combatant moves between side rosters")
	_check(c.field.find_unit(c.victim) == position
		and [c.victim.life, c.victim.stamina, c.victim.ammo,
			c.victim.movement_remaining, c.victim.action_spent,
			c.victim.statuses.duplicate()] == before,
		"direct transfer preserves position/resources/status/action state")
	var state := RoundLoop.BattleState.new()
	state.sides = c.sides
	var old_eligible := RoundLoop.activatable(state, 0)
	var new_eligible := RoundLoop.activatable(state, 1)
	_check(not old_eligible.has(c.victim) and new_eligible.has(c.victim),
		"side eligibility no longer sees a duplicate under the old side")

	DeathLifecycle.transfer_to_opposite_side(c.victim, c.sides)
	c.victim.life = 1
	c.victim.action_spent = true
	_set_statuses(c.victim, [_marker(DeathLifecycle.REVIVE),
		_marker(DeathLifecycle.TRANSFER)])
	_damage(c)
	_check(c.victim.alive and c.sides[1].units.has(c.victim)
		and c.victim.action_spent,
		"revival establishes survival before transfer without activation refresh")

	c = _setup()
	_set_statuses(c.victim, [_marker(DeathLifecycle.TRANSFER)])
	_damage(c)
	_check(not c.victim.alive and c.sides[1].units.has(c.victim)
		and not c.sides[0].units.has(c.victim)
		and not c.field.has_unit(c.victim),
		"persistent final dead record transfers without living occupancy")

	c = _setup()
	var owned := Combatant.new()
	owned.name = "owned"
	owned.instance_id = "owned"
	owned.life = 1
	owned.life_base = 5
	owned.battle_owned = true
	c.sides[0].units.append(owned)
	c.field.place(owned, Battlefield.offset_to_axial(0, 0))
	Damage.apply_received_damage(owned, 1, 0,
		func(unit: Combatant):
			return DeathLifecycle.resolve(unit, c.field, c.sides))
	_check(owned.discarded and not c.sides[0].units.has(owned)
		and not c.field.has_unit(owned),
		"battle-owned final death discards active tactical state")


func _test_runtime_only_markers() -> void:
	print("\n[7] special IDs are runtime-status-only")
	var c := _setup()
	c.victim.modifiers.append(Modifier.make(
		DeathLifecycle.REVIVE, &"add_flat", Modifier.Hook.STAT_PASSIVE))
	_set_statuses(c.victim, [_marker(2)])
	var outcome := _damage(c)
	_check(outcome.final_death and not c.victim.alive,
		"intrinsic numeric 0x4A does not activate revival")
	_check(c.victim.statuses.is_empty(), "final death clears every runtime status")

	c = _setup()
	_set_statuses(c.victim, [_marker(DeathLifecycle.REVIVE, true)])
	outcome = _damage(c)
	_check(outcome.final_death and not c.victim.alive,
		"remove-on-damage processing precedes lifecycle marker scan")


func _upkeep_unit(unit_id: String, at: Array, battle_owned: bool = false) -> Dictionary:
	return {
		"id": unit_id, "name": unit_id, "at": at,
		"life": 1, "life_base": 1, "stamina": 1, "morale": 5,
		"speed": 1, "battle_owned": battle_owned,
		"auras": [{
			"id": "self-drain-" + unit_id, "scope": "SELF",
			"affects": "ALLY", "stacking": "MAXIMUM", "tick": {"life": -1},
		}],
	}


func _death_started_count(lines: Array[String], unit_id: String) -> int:
	var count := 0
	for line in lines:
		if "%s death_started" % unit_id in line:
			count += 1
	return count


func _test_upkeep_fatal_transition_is_single() -> void:
	print("\n[8] upkeep resolves only a new living-to-dead transition")
	var spec := {
		"name": "upkeep fatal transition", "profile": "native", "seed": 1,
		"battlefield": {"width": 5, "height": 5, "tiles": []},
		"sides": [
			{"id": 0, "is_attacker": true, "units": [
				_upkeep_unit("owned", [0, 0], true),
				_upkeep_unit("persistent", [2, 2]),
				{"id": "ally", "name": "ally", "at": [1, 2], "life": 10,
					"stamina": 1, "morale": 5, "speed": 1},
			]},
			{"id": 1, "units": [
				{"id": "enemy", "name": "enemy", "at": [4, 4], "life": 10,
					"stamina": 1, "morale": 5, "speed": 1},
			]},
		], "commands": [],
	}
	var scenario := Scenario.new(spec)
	scenario._round_upkeep()
	var persistent: Combatant = scenario.units["persistent"]
	var owned: Combatant = scenario.units["owned"]
	var ally: Combatant = scenario.units["ally"]
	_check(_death_started_count(scenario.log, "persistent") == 1
		and _death_started_count(scenario.log, "owned") == 1,
		"each newly fatal upkeep transition resolves exactly once")
	_check(ally.morale == 4, "adjacent death morale changes once")
	_check(scenario.state.sides[0].units.has(persistent)
		and not persistent.alive and not scenario.field.has_unit(persistent),
		"persistent dead record remains nonliving and nonoccupying")
	_check(not scenario.state.sides[0].units.has(owned) and owned.discarded,
		"battle-owned removal does not skip the following persistent unit")

	scenario._round_upkeep()
	_check(_death_started_count(scenario.log, "persistent") == 1
		and _death_started_count(scenario.log, "owned") == 1,
		"later upkeep does not reopen either finalized fatal event")
	_check(ally.morale == 4 and not persistent.alive
		and not scenario.field.has_unit(persistent),
		"later upkeep preserves morale and nonliving occupancy state")


func _init() -> void:
	_test_ordinary_final_death()
	_test_morale_and_revival()
	_test_revival_preservation()
	_test_rollback()
	_test_replacement_and_precedence()
	_test_transfer_and_battle_owned()
	_test_runtime_only_markers()
	_test_upkeep_fatal_transition_is_single()
	print("\n%s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
