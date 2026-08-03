# core/rules/damage.gd
class_name Damage
extends RefCounted

## The attack pipeline. Port of oracle/combat.py; every number here is checked
## against the Eadoropedia's published tables by tests/test_damage.gd using
## fixtures the oracle generates.
##
##     ТекущаяАтака = (База + ПлюсуемыеБонусы) * StaminaMod * MoraleMod * WoundMod
##
## Additive before multiplicative is documented and not negotiable.

# ---------------------------------------------------------------------------
# Pipeline wiring
#
# Set by Scenario.run() or by whatever owns the battle. `null` means "no content
# loaded" — the scalar attack_bonus/defence_bonus path still works, which keeps
# the pre-pipeline tests and scenarios valid.
# ---------------------------------------------------------------------------

static var _pipeline: Pipeline = null

## Supplies modifiers that come from the unit's SURROUNDINGS rather than from the
## unit — auras today, terrain later. Injected rather than imported, because those
## need the battlefield and the side layout, and the rules must not depend on
## either.
static var _environment: Callable = Callable()


static func bind_pipeline(p: Pipeline) -> void:
	_pipeline = p


## `provider(unit) -> Array[Modifier]`. Pass an empty Callable to detach.
static func bind_environment(provider: Callable) -> void:
	_environment = provider


## EVERY modifier acting on this unit, from every source.
##
## There are three, and forgetting one is invisible until something is cast:
##
##   u.modifiers              innate abilities, from unit.var via the roster
##   u.statuses[].modifiers   timed effects — buffs, curses, enchantments
##   _environment(u)          auras, and terrain when it lands
##
## This exists because the damage path used only the first. Statuses passed every
## test in isolation while a Благословение granting +2 attack did nothing, because
## nothing merged the sources. has_flag walked all three already, so FLAGS from
## statuses worked and NUMBERS did not — the most confusing possible failure shape.
static func effective_modifiers(u: Combatant) -> Array:
	var out: Array = u.modifiers.duplicate()
	for effect in u.statuses:
		out.append_array(effect.modifiers)
	if _environment.is_valid():
		out.append_array(_environment.call(u))
	return out


## Returns [value, trace] or [base, null] when nothing applies.
static func _run_hook(base: Variant, u: Combatant, hook: int, ctx: Dictionary,
		label: String) -> Array:
	if _pipeline == null:
		return [base, null]
	var mods: Array = effective_modifiers(u)
	if mods.is_empty():
		return [base, null]
	return _pipeline.resolve(base, mods, hook, ctx, label)


const _STAT_FOR_KIND: Dictionary = {
	Combatant.AttackKind.MELEE: "attack",
	Combatant.AttackKind.COUNTER: "counter_attack",
	Combatant.AttackKind.RANGED: "ranged_attack",
}


## Returns [value: float, trace: Trace].
static func current_attack(u: Combatant, kind: Combatant.AttackKind) -> Array:
	var t := Trace.new("%s.attack[%d]" % [u.name, kind])
	var base: int = u.base_attack_for(kind)
	t.base = float(base)
	var value: float = float(base)

	if u.attack_bonus != 0:
		var nv: float = value + float(u.attack_bonus)
		t.step("additive bonuses", value, nv)
		value = nv

	# STAT_PASSIVE sits INSIDE the multiplier chain: additive before
	# multiplicative is documented and not negotiable.
	var passive: Array = _run_hook(value, u, Modifier.Hook.STAT_PASSIVE,
		{"stat": _STAT_FOR_KIND[kind], "unit": u, "kind": kind}, "modifiers")
	if passive[1] != null and float(passive[0]) != value:
		for step in (passive[1] as Trace).steps:
			t.steps.append(step)
		value = float(passive[0])

	for entry in [
		["StaminaMod", Stamina.modifier(u)],
		["MoraleMod", Morale.modifier(u)],
		["WoundMod", Wounds.modifier(u)],
	]:
		var label: String = entry[0]
		var m: float = entry[1][0]
		var note: String = entry[1][1]
		if m != 1.0 or note != "":
			var nv: float = value * m
			t.step("%s x%.2f" % [label, m], value, nv, note)
			value = nv

	t.result = value
	return [value, t]


## Defence floors, then clamps to a minimum of 0. At stamina 0 both defence
## values are halved: «его Защита и Защита от выстрела уменьшаются в 2 раза».
## Returns [value: int, trace: Trace].
static func current_defence(u: Combatant, kind: Combatant.AttackKind) -> Array:
	var t := Trace.new("%s.defence" % u.name)
	var base: int = u.base_defence_for(kind)
	t.base = float(base)
	var value: float = float(base)

	if u.defence_bonus != 0:
		var nv: float = value + float(u.defence_bonus)
		t.step("additive bonuses", value, nv)
		value = nv

	var stat: String = "ranged_defence" if kind == Combatant.AttackKind.RANGED \
		else "defence"
	var passive: Array = _run_hook(value, u, Modifier.Hook.STAT_PASSIVE,
		{"stat": stat, "unit": u, "kind": kind}, "modifiers")
	if passive[1] != null and float(passive[0]) != value:
		for step in (passive[1] as Trace).steps:
			t.steps.append(step)
		value = float(passive[0])

	if Stamina.is_exhausted(u):
		var nv: float = value * 0.5
		t.step("exhausted x0.50", value, nv, "stamina 0")
		value = nv

	var final: int = maxi(0, int(floorf(value)))
	if float(final) != value:
		t.step("floor, clamp >= 0", value, float(final))
	t.result = float(final)
	return [final, t]


## «Расчёт урона при атаках», exact form.
##
##     attack >= 5:  attack + attack/5 - Random(2*(attack/5) + 1)
##     attack <  5:  attack + 1 - Random(3)
##
## All division is integer and floors. Clamps to a minimum of 1.
##
## Do NOT substitute the page's simplified `attack * Random(0.8;1.2)`: floor()
## on a symmetric distribution biases it low by a constant ~0.5, which is a 10%
## error at attack 5 and negligible at 50.
##
## Returns [value: int, note: String].
static func roll_attack(attack: int, rng: Rng, stream: StringName = &"attack") -> Array:
	var rolled: int
	var note: String
	if attack >= 5:
		var k: int = attack / 5
		rolled = attack + k - rng.roll(2 * k + 1, stream)
		note = "uniform [%d, %d]" % [attack - k, attack + k]
	else:
		rolled = attack + 1 - rng.roll(3, stream)
		note = "uniform [%d, %d]" % [attack - 1, attack + 1]
	if rolled < 1:
		return [1, note + ", clamped to 1"]
	return [rolled, note]


## «"Отрицательный" урон»: at damage <= 0 but > -10, one point still lands if
## Random(20 + damage) >= 10. Probability 1 - 10/(20+damage).
static func negative_damage_hits(damage: int, rng: Rng, stream: StringName = &"chip") -> bool:
	if damage <= -10:
		return false
	return rng.roll(20 + damage, stream) >= 10


## Full pipeline. Returns [damage: int, traces: Array[Trace]].
static func resolve_attack(attacker: Combatant, defender: Combatant,
		kind: Combatant.AttackKind, rng: Rng) -> Array:
	var atk: Array = current_attack(attacker, kind)
	var atk_value: float = atk[0]
	var atk_trace: Trace = atk[1]

	# ASSUMPTION (OPEN_QUESTIONS item 7): conditional bonuses are added after
	# all three multipliers. The page states only that MORALE skips them; it is
	# silent on stamina and wound. Distinguishable by one wounded-unit test.
	if attacker.conditional_bonus != 0:
		var nv: float = atk_value + float(attacker.conditional_bonus)
		atk_trace.step("conditional bonus", atk_value, nv, "ASSUMED outside multipliers")
		atk_value = nv
		atk_trace.result = nv

	if attacker.has_flag(&"Не сражается"):
		return [0, [atk_trace]]

	var attack_int: int = int(floorf(atk_value))
	var rolled_pair: Array = roll_attack(attack_int, rng)
	var rolled: int = rolled_pair[0]
	var roll_trace := Trace.new("%s.roll" % attacker.name)
	roll_trace.base = float(attack_int)
	roll_trace.step("randomise", float(attack_int), float(rolled), rolled_pair[1])
	roll_trace.result = float(rolled)

	var def_pair: Array = current_defence(defender, kind)
	var def_value: int = def_pair[0]
	var damage: int = rolled - def_value

	var dmg_trace := Trace.new("damage")
	dmg_trace.base = float(rolled)
	dmg_trace.step("- defence %d" % def_value, float(rolled), float(damage))

	if damage <= 0:
		if negative_damage_hits(damage, rng):
			dmg_trace.step("chip roll", float(damage), 1.0, "negative-damage rule succeeded")
			damage = 1
		else:
			dmg_trace.step("chip roll", float(damage), 0.0, "negative-damage rule failed")
			damage = 0
	dmg_trace.result = float(damage)
	return [damage, [atk_trace, roll_trace, def_pair[1], dmg_trace]]
