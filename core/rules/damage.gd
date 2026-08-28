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


## Runtime/status and environment/aura providers already have distinct storage.
## Keep that existing distinction available to ordering-sensitive rules (R6).
static func _later_modifiers(u: Combatant) -> Array:
	# CX-008 R6 boundary: status/runtime modifiers enter only here, after the
	# ranged definition + unit-owned early-provider zero check.
	var out: Array = Statuses.active_modifiers(u)
	if _environment.is_valid():
		out.append_array(_environment.call(u))
	return out


## Every modifier acting on this unit, from every represented source.
static func effective_modifiers(u: Combatant) -> Array:
	var out: Array = u.modifiers.duplicate()
	out.append_array(_later_modifiers(u))
	return out


## Numeric modifier membership across every currently available provider.
static func has_effective_modifier(u: Combatant, ability: int) -> bool:
	for modifier in effective_modifiers(u):
		if int((modifier as Modifier).ability) == ability:
			return true
	return false


static func has_effective_modifier_semantic(
		u: Combatant, query: ModifierSemantic.Query) -> bool:
	for modifier in effective_modifiers(u):
		if (modifier as Modifier).has_semantic(query):
			return true
	return false


static func effective_modifier_value(u: Combatant, ability: int) -> int:
	## Signed numeric total for one modifier ID across represented providers.
	var total := 0
	for modifier in effective_modifiers(u):
		if int((modifier as Modifier).ability) == ability:
			total += int((modifier as Modifier).power)
	return total


static func _offensive_disabled(u: Combatant) -> bool:
	return has_effective_modifier_semantic(
		u, ModifierSemantic.Query.MELEE_EXCHANGE_SUPPRESSED) or u.has_flag(&"Не сражается")


## Returns [value, trace] or [base, null] when nothing applies.
static func _run_hook_for(base: Variant, mods: Array, hook: int,
		ctx: Dictionary, label: String) -> Array:
	if _pipeline == null or mods.is_empty():
		return [base, null]
	return _pipeline.resolve(base, mods, hook, ctx, label)


static func _run_hook(base: Variant, u: Combatant, hook: int, ctx: Dictionary,
		label: String) -> Array:
	return _run_hook_for(base, effective_modifiers(u), hook, ctx, label)


static func _append_hook_steps(trace: Trace, resolved: Array, before: float) -> float:
	if resolved[1] != null and float(resolved[0]) != before:
		for step in (resolved[1] as Trace).steps:
			trace.steps.append(step)
	return float(resolved[0])


const _STAT_FOR_KIND: Dictionary = {
	Combatant.AttackKind.MELEE: "attack",
	Combatant.AttackKind.COUNTER: "counter_attack",
	Combatant.AttackKind.RANGED: "ranged_attack",
}


## Returns [value: float, trace: Trace].
static func current_attack(u: Combatant, kind: Combatant.AttackKind) -> Array:
	var trace_stat := "ranged_attack" if kind == Combatant.AttackKind.RANGED else "melee_attack"
	if kind == Combatant.AttackKind.COUNTER:
		trace_stat = "counter_attack"
	var t := Trace.new("%s.%s" % [u.name, trace_stat])
	var base: int = u.base_attack_for(kind)
	t.base = float(base)
	var value: float = float(base)

	# R6: the three effective-attack functions do NOT share entry semantics.
	#
	# Melee and counterattack test the melee-exchange-suppression semantic
	# «Не сражается» first and return zero outright; the final minimum-one clamp
	# is never reached on that path.
	if (kind == Combatant.AttackKind.MELEE or kind == Combatant.AttackKind.COUNTER) \
			and _offensive_disabled(u):
		t.step("combat.melee_exchange_suppressed", value, 0.0, "cannot attack")
		t.result = 0.0
		return [0.0, t]

	var ctx := {"stat": _STAT_FOR_KIND[kind], "unit": u, "kind": kind}
	if kind == Combatant.AttackKind.RANGED:
		# Existing unit modifiers are the represented instance/intrinsic channel.
		# Resolve them into the accepted early sum before consulting the already
		# separate status and environment channels.
		var early := _run_hook_for(value, u.modifiers,
			Modifier.Hook.STAT_PASSIVE, ctx, "early unit modifiers")
		value = _append_hook_steps(t, early, value)
		t.step("ranged early provider total", float(base), value,
			"definition plus unit modifiers; status/environment not consulted")
		if int(value) == 0:
			t.step("ranged zero-sum early return", value, 0.0,
				"before runtime/status/environment, state and clamp")
			t.result = 0.0
			return [0.0, t]

		# The scalar shorthand is documented as battle-visible spell/aura input,
		# so it remains on the later side of the ranged cutoff.
		if u.attack_bonus != 0:
			var later_value := value + float(u.attack_bonus)
			t.step("later additive bonuses", value, later_value)
			value = later_value
		var later := _run_hook_for(value, _later_modifiers(u),
			Modifier.Hook.STAT_PASSIVE, ctx, "status/environment modifiers")
		value = _append_hook_steps(t, later, value)
	else:
		# Preserve the established melee/counter provider behavior: scalar and all
		# modifier sources still resolve as one combined additive stage.
		if u.attack_bonus != 0:
			var nv: float = value + float(u.attack_bonus)
			t.step("additive bonuses", value, nv)
			value = nv
		var passive := _run_hook(value, u, Modifier.Hook.STAT_PASSIVE,
			ctx, "modifiers")
		value = _append_hook_steps(t, passive, value)

	# Stamina and wound act inside the x100 scaled domain; morale is applied
	# LAST, on an integer, as a whole-percent bonus. The order is the binary's,
	# not a rearrangement of the documented product: with truncation between the
	# steps the order is observable. docs/FORMULAS.md §1.4.
	for entry in [
		["StaminaMod", Stamina.modifier(u)],
		["WoundMod", Wounds.modifier(u)],
	]:
		var label: String = entry[0]
		var m: float = entry[1][0]
		var note: String = entry[1][1]
		if m != 1.0 or note != "":
			var nv: float = value * m
			t.step("%s x%.2f" % [label, m], value, nv, note)
			value = nv

	# result = max(1, pre_morale + trunc0(bonus_percent * pre_morale / 100))
	#
	# The clamp is UNCONDITIONAL — it is the final line of all three recovered
	# effective-attack functions, not part of the morale branch — so it applies
	# at neutral morale too. 2 Genesis and 22 NH units carry Attack 0 (siege
	# engines), and attack 1 reduced by the stamina-0 halving also truncates to
	# 0; without the clamp those return 0 here and 1 in the original.
	# docs/FORMULAS.md §1.4.
	var mor: Array = Morale.percent(u)
	var pct: int = mor[0]
	var mnote: String = mor[1]
	# int() truncates toward zero in GDScript, matching C.
	var pre: int = int(value)
	var raw: int = pre + int(float(pct * pre) / 100.0)
	var nv: float = float(maxi(1, raw))
	if pct != 0 or mnote != "" or nv != value:
		var label: String = ("MoraleMod %+d%%" % pct) if pct != 0 else "MoraleMod"
		if raw < 1:
			label += " (min-1 clamp)"
		t.step(label, value, nv, mnote)
	value = nv

	t.result = value
	return [value, t]


## Defence halves at exactly zero stamina, then clamps to a minimum of 0 (R9).
## At stamina 0 both defence
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

	# R9: shared accepted final tail for ordinary and ranged defence:
	#
	#     if current_stamina == 0: value = trunc0(value / 2)
	#     return max(value, 0)
	#
	# Three corrections against the previous implementation:
	#   - the predicate is EQUALITY WITH ZERO, not "exhausted"/<= 0;
	#   - the stamina-mutation-suppression semantic is NOT consulted by either function — the
	#     exemption belongs to stamina COSTS, not to the defence halving;
	#   - the signed divide truncates toward zero (CDQ; SUB; SAR), not floors.
	var path_name := "ranged" if kind == Combatant.AttackKind.RANGED else "ordinary"
	t.step("defence provider total", value, value,
		"%s providers complete before stamina handling" % path_name)
	if u.stamina == 0:
		var nv: float = float(int(value / 2.0))
		t.step("zero-stamina defence halving", value, nv,
			"signed truncation toward zero")
		value = nv

	var final: int = maxi(0, int(value))
	t.step("final defence clamp", value, float(final), "minimum 0")
	t.result = float(final)
	return [final, t]


static func current_resistance(u: Combatant) -> Array:
	## Represented effective resistance providers, without defence stamina rules.
	var t := Trace.new("%s.resistance" % u.name)
	t.base = float(u.resist)
	var value := float(u.resist)
	var resolved := _run_hook(value, u, Modifier.Hook.STAT_PASSIVE,
		{"stat": "resist", "unit": u}, "modifiers")
	value = _append_hook_steps(t, resolved, value)
	var provider_total := int(value)
	t.step("resistance provider total", value, float(provider_total),
		"represented providers complete; signed integer truncation")
	var final := maxi(0, provider_total)
	t.step("final resistance clamp", float(provider_total), float(final),
		"minimum 0")
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
static func roll_attack(attack: int, rng: Variant, stream: StringName = &"attack") -> Array:
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
static func negative_damage_hits(damage: int, rng: Variant, stream: StringName = &"chip") -> bool:
	if damage <= -10:
		return false
	return rng.roll(20 + damage, stream) >= 10


## Final attack power immediately before randomisation (R10).
##
## `conditional_bonus` is an already-resolved applicability/provider boundary:
## callers decide whether modifier 0x3D contributes. This function freezes only
## its numeric placement and does not infer a target class from presentation.
## Returns [power: int, trace: Trace].
static func trunc0_ratio(value: int, numerator: int, denominator: int) -> int:
	## Integer-only signed rational scaling; division truncates toward zero.
	assert(denominator > 0, "ratio denominator must be positive")
	var product := value * numerator
	@warning_ignore("integer_division")
	var magnitude := absi(product) / denominator
	return -magnitude if product < 0 else magnitude


static func attack_power_before_randomisation(attacker: Combatant,
		kind: Combatant.AttackKind, selected_ordinary_1_5x: bool = false,
		initiating_scale_numerator: int = 1,
		initiating_scale_denominator: int = 1) -> Array:
	var atk: Array = current_attack(attacker, kind)
	var atk_value: float = atk[0]
	var atk_trace: Trace = atk[1]

	if kind == Combatant.AttackKind.MELEE and selected_ordinary_1_5x:
		initiating_scale_numerator = 3
		initiating_scale_denominator = 2
	assert(initiating_scale_denominator > 0,
		"initiating attack scale denominator must be positive")
	if (kind == Combatant.AttackKind.MELEE
			and (initiating_scale_numerator != 1
				or initiating_scale_denominator != 1)):
		var before := int(atk_value)
		var scaled := trunc0_ratio(before, initiating_scale_numerator,
			initiating_scale_denominator)
		var source := "selected ordinary 1.5x branch" if selected_ordinary_1_5x else \
			"initiating attack scale %d/%d" % [
				initiating_scale_numerator, initiating_scale_denominator]
		atk_trace.step(source, atk_value, float(scaled),
			"after finalized effective attack; exact rational trunc0")
		atk_value = float(scaled)

	if ((kind == Combatant.AttackKind.MELEE
			or kind == Combatant.AttackKind.COUNTER)
			and attacker.conditional_bonus != 0):
		var nv: float = atk_value + float(attacker.conditional_bonus)
		atk_trace.step("conditional attack contribution", atk_value, nv,
			"already-applicable numeric input; after selected branch; before randomisation")
		atk_value = nv

	atk_trace.result = atk_value
	return [int(atk_value), atk_trace]


## Existing randomized resolver with an already-selected defensive input.
static func _resolve_attack_against_defence(attack_int: int, atk_trace: Trace,
		attacker_name: String, defence_input: int, defence_trace: Trace, rng: Variant,
		defence_note: String = "effective defence") -> Array:
	var rolled_pair: Array = roll_attack(attack_int, rng)
	var rolled: int = rolled_pair[0]
	var roll_trace := Trace.new("%s.roll" % attacker_name)
	roll_trace.base = float(attack_int)
	roll_trace.step("attack randomisation", float(attack_int),
		float(rolled), rolled_pair[1])
	roll_trace.result = float(rolled)

	var damage := rolled - defence_input
	var dmg_trace := Trace.new("damage")
	dmg_trace.base = float(rolled)
	dmg_trace.step("defence subtraction", float(rolled), float(damage),
		"%s %d" % [defence_note, defence_input])
	if damage <= 0:
		if negative_damage_hits(damage, rng):
			dmg_trace.step("chip roll", float(damage), 1.0,
				"negative-damage rule succeeded")
			damage = 1
		else:
			dmg_trace.step("chip roll", float(damage), 0.0,
				"negative-damage rule failed")
			damage = 0
	dmg_trace.result = float(damage)
	return [damage, [atk_trace, roll_trace, defence_trace, dmg_trace]]


static func trunc0_half(value: int) -> int:
	## Exact signed division by two toward zero, shared by frozen damage branches.
	var half := value >> 1
	return half + 1 if value < 0 and (value & 1) != 0 else half


static func resolve_ranged_attack(attacker: Combatant, defender: Combatant,
		rng: Variant) -> Array:
	## Frozen DAMAGE-RANGED-001 calculator: [damage, traces, sink channel].
	var attack_power := attack_power_before_randomisation(
		attacker, Combatant.AttackKind.RANGED)
	var attack_int := int(attack_power[0])
	var atk_trace := attack_power[1] as Trace
	var modifier_0x1c := effective_modifier_value(attacker, 0x1C)
	var channel := 2 if modifier_0x1c != 0 else 1
	if attack_int == 0:
		var channel_trace := Trace.new("ranged channel")
		channel_trace.step("ranged received-damage channel", float(channel),
			float(channel), "modifier 0x1C nonzero" if channel == 2
			else "ordinary ranged branch")
		channel_trace.result = float(channel)
		return [0, [atk_trace, channel_trace], channel]

	if modifier_0x1c != 0:
		var resistance_pair := current_resistance(defender)
		var defence_input := int(resistance_pair[0])
		var defence_trace := resistance_pair[1] as Trace
		defence_trace.step("ranged resistance branch", float(defence_input),
			float(defence_input), "effective modifier 0x1C is nonzero")
		var modifier_0x5f := effective_modifier_value(attacker, 0x5F)
		var reduced := defence_input - modifier_0x5f
		defence_trace.step("modifier 0x5F resistance subtraction",
			float(defence_input), float(reduced),
			"resistance branch before resolver")
		defence_input = reduced
		defence_trace.result = float(defence_input)
		var resolved := _resolve_attack_against_defence(
			attack_int, atk_trace, attacker.name, defence_input, defence_trace, rng,
			"selected defensive input")
		var channel_trace := Trace.new("ranged channel")
		channel_trace.step("ranged received-damage channel", 2.0, 2.0,
			"0x1C resistance branch returns before non-resistance tail")
		channel_trace.result = 2.0
		(resolved[1] as Array).append(channel_trace)
		return [int(resolved[0]), resolved[1], 2]

	var defence_pair := current_defence(defender, Combatant.AttackKind.RANGED)
	var defence_input := int(defence_pair[0])
	var defence_trace := defence_pair[1] as Trace
	defence_trace.step("ordinary ranged-defence branch", float(defence_input),
		float(defence_input), "effective modifier 0x1C is zero")
	var modifier_0x11 := effective_modifier_value(attacker, 0x11)
	if modifier_0x11 != 0:
		var halved := trunc0_half(defence_input)
		defence_trace.step("modifier 0x11 ranged-defence halving",
			float(defence_input), float(halved),
			"signed truncation toward zero; before 0x4D")
		defence_input = halved
	var modifier_0x4d := effective_modifier_value(attacker, 0x4D)
	var reduced := defence_input - modifier_0x4d
	defence_trace.step("modifier 0x4D ranged-defence subtraction",
		float(defence_input), float(reduced),
		"non-resistance branch before resolver")
	defence_input = reduced
	defence_trace.result = float(defence_input)
	var resolved := _resolve_attack_against_defence(
		attack_int, atk_trace, attacker.name, defence_input, defence_trace, rng,
		"selected defensive input")
	var damage := int(resolved[0])
	var modifier_0x3c := effective_modifier_value(attacker, 0x3C)
	var target_resistance := int(current_resistance(defender)[0])
	var excess := maxi(0, modifier_0x3c - target_resistance)
	var post_trace := Trace.new("ranged post-resolver")
	post_trace.base = float(damage)
	post_trace.step("modifier 0x3C excess over resistance", float(damage),
		float(damage + excess), "max(0, %d - %d)" % [
			modifier_0x3c, target_resistance])
	damage += excess
	post_trace.step("ranged received-damage channel", 1.0, 1.0,
		"ordinary non-resistance branch")
	post_trace.result = float(damage)
	(resolved[1] as Array).append(post_trace)
	return [damage, resolved[1], 1]


## Full pipeline. Returns [damage: int, traces: Array[Trace]].
static func resolve_attack(attacker: Combatant, defender: Combatant,
		kind: Combatant.AttackKind, rng: Variant,
		selected_ordinary_1_5x: bool = false,
		initiating_scale_numerator: int = 1,
		initiating_scale_denominator: int = 1) -> Array:
	if kind == Combatant.AttackKind.RANGED:
		var ranged := resolve_ranged_attack(attacker, defender, rng)
		return [ranged[0], ranged[1]]

	var attack_power := attack_power_before_randomisation(
		attacker, kind, selected_ordinary_1_5x,
		initiating_scale_numerator, initiating_scale_denominator)
	var attack_int := int(attack_power[0])
	var atk_trace := attack_power[1] as Trace
	if _offensive_disabled(attacker):
		return [0, [atk_trace]]
	var defence_pair := current_defence(defender, kind)
	return _resolve_attack_against_defence(
		attack_int, atk_trace, attacker.name, int(defence_pair[0]),
		defence_pair[1], rng)


# ---------------------------------------------------------------------------
# Central received-damage sink (CX-011)
# ---------------------------------------------------------------------------

static func adjust_morale(unit: Combatant, delta: int) -> bool:
	## Apply recovered morale-underflow suppression and morale underflow accounting.
	if has_effective_modifier_semantic(
		unit, ModifierSemantic.Query.MORALE_UNDERFLOW_SUPPRESSED):
		return false
	var after := unit.morale + delta
	if after < 0:
		unit.morale_break_accumulator += -after * 10
		after = 0
	unit.morale = after
	return true


static func apply_received_damage(unit: Combatant, amount: int,
		channel: int = 0, death_resolver: Callable = Callable()) -> Dictionary:
	## Account -> remove-on-damage -> subtract/cap -> exactly one death resolve.
	## fatal_event deliberately does not mean permanent kill, credit, reward or R17.
	assert(channel >= 0 and channel < unit.damage_received.size())
	amount = maxi(0, amount)
	unit.damage_received[channel] += amount
	Statuses.remove_on_damage(unit)
	unit.life = maxi(0, unit.life - amount)
	var fatal_event := unit.alive and unit.life == 0
	var lifecycle: Dictionary = {}
	if fatal_event:
		if death_resolver.is_valid():
			var resolved: Variant = death_resolver.call(unit)
			if typeof(resolved) == TYPE_DICTIONARY:
				lifecycle = resolved
			else:
				lifecycle = {"error": "death resolver returned no result"}
				unit.alive = false
		else:
			unit.alive = false
	var final_alive := unit.alive and unit.life > 0
	var outcome := {
		"fatal_event": fatal_event,
		"final_alive": final_alive,
		"final_death": fatal_event and not final_alive,
	}
	var lifecycle_error := String(lifecycle.get("error", ""))
	if lifecycle_error != "":
		outcome["error"] = lifecycle_error
		outcome["lifecycle"] = lifecycle
	return outcome
