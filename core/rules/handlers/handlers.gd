class_name Handlers
extends RefCounted

## The engine side of the opcode bindings.
##
## Handlers are named, never numbered. A pack maps opcode 30 to "magic_immunity"
## or to "armor_pierce"; the rules layer calls whichever name came back and
## contains no conditional about which pack is loaded. That indirection is why
## the vanilla/NH opcode reassignment is a data problem, not a code problem.
##
## Signature is uniform: (ctx, value, params) -> value.
##   ctx     what is being computed and for whom — "stat", "unit", "target"
##   value   the running value at this point in the pipeline
##   params  from the pack binding, plus "power" injected from the modifier
##
## Registering a handler moves an opcode from `unbound` to `usable` in the load
## report, so this file is the progress meter's denominator.


## The largest unambiguous family: 15-16 opcodes per pack collapse here because
## the stat is a parameter rather than part of the opcode. The guard matters — a
## modifier granting +2 Attack must not raise Defence when the pipeline happens
## to be resolving Defence.
static func stat_delta(ctx: Dictionary, value: Variant, params: Dictionary) -> Variant:
	if params.get("stat") != ctx.get("stat"):
		return value
	return value + int(params.get("power", 0))


## Percentage modifiers; `power` is a percentage, so 50 means +50%.
## Kept separate from stat_delta because they must not interleave — additive
## before multiplicative is documented, and separate hooks enforce it
## structurally rather than by convention.
static func stat_scale(ctx: Dictionary, value: Variant, params: Dictionary) -> Variant:
	if params.get("stat") != ctx.get("stat"):
		return value
	return float(value) * (1.0 + float(int(params.get("power", 0))) / 100.0)


## «её значение считается в 2 раза меньшим» — the documented form is a HALVING,
## not a flat subtraction.
static func armor_pierce(_ctx: Dictionary, value: Variant, _params: Dictionary) -> Variant:
	return float(value) * 0.5


## Flat bypass, for abilities whose text gives a number rather than a fraction.
## Floors at 0 — negative defence would turn a bypass into a bonus.
static func defence_ignore(_ctx: Dictionary, value: Variant, params: Dictionary) -> Variant:
	return maxi(0, int(value) - int(params.get("power", 0)))


## `Охотник на X`, `Сокрушение зла` and similar. Morale does not multiply these,
## so the modifier carrying this handler should set outside_multipliers.
static func bonus_vs_subtype(ctx: Dictionary, value: Variant, params: Dictionary) -> Variant:
	var target: Variant = ctx.get("target")
	var wanted: Variant = params.get("subtype")
	if target == null or wanted == null:
		return value
	if not (target as Combatant).has_subtype(StringName(String(wanted))):
		return value
	return value + int(params.get("power", 0))


## Yes/no answers run through Pipeline.flag(), where `value` arrives as false.
static func immunity(ctx: Dictionary, _value: Variant, params: Dictionary) -> Variant:
	return params.get("against") == ctx.get("against")


## Partial resistance reduces rather than nullifies, so it returns a value and
## is used through resolve() rather than flag().
static func resistance(ctx: Dictionary, value: Variant, params: Dictionary) -> Variant:
	if params.get("against") != ctx.get("against"):
		return value
	return float(value) * maxf(0.0, 1.0 - float(int(params.get("power", 0))) / 100.0)


static func magic_immunity(ctx: Dictionary, _value: Variant, _params: Dictionary) -> Variant:
	return ctx.get("school") != null


## 276 of 598 NH opcodes, one handler. Granting a spell changes no number; it
## exists to be enumerable — asking what a unit knows means walking its
## modifiers for this handler.
static func grant_spell(ctx: Dictionary, value: Variant, params: Dictionary) -> Variant:
	var known: Variant = ctx.get("known_spells")
	if known != null and params.get("spell") != null:
		(known as Dictionary)[params["spell"]] = true
	return value


static func spells_granted(mods: Array) -> Array:
	var out: Array = []
	for m in mods:
		if m.handler == &"grant_spell" and m.params.get("spell") != null:
			if not out.has(m.params["spell"]):
				out.append(m.params["spell"])
	out.sort()
	return out


## Presence-only abilities.
##
## The single highest-leverage handler here. A large family of abilities compute
## nothing — they are simply TRUE or FALSE about a unit, and the rules modules
## already ask: wounds.gd for "Не чувствует боли" and "Боевое безумие",
## stamina.gd for "Неутомимый", counterattack.gd for "Ловкость", "Первый удар",
## "Не сражается" and "Касание вампира".
##
## Those checks were written against flags nothing set. Binding an opcode here
## makes the existing rule light up with no further work — which is why one
## handler closed 13 of the Genesis blockers at once.
##
## A NO-OP BY DESIGN: flags are DERIVED from the modifier list by
## Combatant.has_flag rather than written into the unit. Mutating here would
## work for innate abilities and silently fail for every temporary one.
static func grant_flag(_ctx: Dictionary, value: Variant, _params: Dictionary) -> Variant:
	return value


## «тратит только единицу скорости ... и не тратит выносливость. Кроме того,
## каждый пункт знания выше первого увеличивает защиту и контратаку на 1»
##
## Two effects from one ability, the second conditional on exceeding the FIRST
## point: rank 1 gives movement relief only, rank 3 gives +2 defence and
## counterattack on top.
static func terrain_knowledge(ctx: Dictionary, value: Variant,
		params: Dictionary) -> Variant:
	var stat := String(ctx.get("stat", ""))
	if stat != "defence" and stat != "counter_attack":
		return value
	return value + maxi(0, int(params.get("power", 0)) - 1)


static func knows_terrain(mods: Array, terrain: String) -> int:
	for m in mods:
		if m.handler == &"terrain_knowledge" and String(m.params.get("terrain", "")) == terrain:
			return m.power
	return 0


## «наносит магический урон, и от неё спасает не защита, а сопротивление» —
## a change of WHICH STAT the defender applies, not of any number, so this only
## records the type and the damage path reads it.
static func damage_type(_ctx: Dictionary, value: Variant, _params: Dictionary) -> Variant:
	return value


static func defence_stat_for(mods: Array, kind_is_ranged: bool) -> String:
	var want := "ranged" if kind_is_ranged else "melee"
	for m in mods:
		if m.handler == &"damage_type" and String(m.params.get("applies_to", "")) == want:
			if String(m.params.get("type", "")) == "magic":
				return "resist"
	return "ranged_defence" if kind_is_ranged else "defence"


## Осада, Мародер, Грабитель do nothing in a battle. Bound to an explicit no-op
## rather than left unbound, because "implemented, and it does nothing here" and
## "not implemented yet" are different facts the load report must not conflate.
static func strategic_only(_ctx: Dictionary, value: Variant, _params: Dictionary) -> Variant:
	return value


## «восстанавливает %d жизни каждый ход» — applied by the round machinery, not
## computed here. This exists to make the ability enumerable and carry its rate.
static func regeneration(_ctx: Dictionary, value: Variant, _params: Dictionary) -> Variant:
	return value


static func regeneration_rate(mods: Array) -> int:
	var total := 0
	for m in mods:
		if m.handler == &"regeneration":
			total += m.power
	return total


static func register_all(registry: AbilityRegistry) -> void:
	var table: Dictionary = {
		&"stat_delta": Callable(Handlers, "stat_delta"),
		&"stat_scale": Callable(Handlers, "stat_scale"),
		&"armor_pierce": Callable(Handlers, "armor_pierce"),
		&"defence_ignore": Callable(Handlers, "defence_ignore"),
		&"bonus_vs_subtype": Callable(Handlers, "bonus_vs_subtype"),
		&"immunity": Callable(Handlers, "immunity"),
		&"resistance": Callable(Handlers, "resistance"),
		&"magic_immunity": Callable(Handlers, "magic_immunity"),
		&"grant_spell": Callable(Handlers, "grant_spell"),
		&"grant_flag": Callable(Handlers, "grant_flag"),
		&"terrain_knowledge": Callable(Handlers, "terrain_knowledge"),
		&"damage_type": Callable(Handlers, "damage_type"),
		&"strategic_only": Callable(Handlers, "strategic_only"),
		&"regeneration": Callable(Handlers, "regeneration"),
	}
	for name in table:
		if not registry.has(name):
			registry.register(name, table[name])
