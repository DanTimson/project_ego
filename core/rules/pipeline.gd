class_name Pipeline
extends RefCounted

## Runs modifiers at a hook, in order, through the ability registry.
##
## Content loading resolves an opcode to a handler name; this is what finally
## calls it. Without this, ContentDb.resolve() returns a name nobody uses.

var registry: AbilityRegistry


func _init(p_registry: AbilityRegistry) -> void:
	registry = p_registry


## Modifiers for one hook, in a STABLE order.
##
## Sorted by (ability, source) rather than left in list order: two
## implementations that build the list differently would otherwise apply the
## same set in a different sequence.
##
## This ordering is for DETERMINISM ONLY and carries no semantics — it is
## alphabetical by ability name, which means nothing mechanically. Handlers that
## are non-commutative with each other must therefore live at DIFFERENT hooks;
## that is what the hook order is for. A halving belongs at DEFENCE_APPLY,
## downstream of the additive STAT_PASSIVE stage, so the two can never
## interleave by accident.
func at(mods: Array, hook: int) -> Array:
	var out: Array = []
	for m in mods:
		if m.hook == hook:
			out.append(m)
	out.sort_custom(func(a: Modifier, b: Modifier) -> bool:
		if a.ability != b.ability:
			return a.ability < b.ability
		if a.source != b.source:
			return a.source < b.source
		return String(a.handler) < String(b.handler))
	return out


## Returns [value, Trace]. Unknown handlers are skipped and RECORDED: an unbound
## opcode must not silently behave as if it did nothing, and must not crash the
## battle either.
func resolve(base: Variant, mods: Array, hook: int, ctx: Dictionary,
		label: String = "") -> Array:
	var t := Trace.new(label if label != "" else "hook:%d" % hook)
	t.base = float(base)
	var value: Variant = base
	for m in at(mods, hook):
		if not registry.has(m.handler):
			t.step(m.describe(), float(value), float(value),
				"no handler '%s' — skipped" % m.handler)
			continue
		var params: Dictionary = m.params.duplicate()
		params["power"] = m.power
		var before: Variant = value
		value = registry.call_handler(m.handler, ctx, value, params)
		t.step(m.describe(), float(before), float(value), String(m.handler))
	t.result = float(value)
	return [value, t]


## True if any modifier at this hook asserts. For immunities and other yes/no
## questions, where a numeric value would be meaningless.
func flag(mods: Array, hook: int, ctx: Dictionary) -> bool:
	for m in at(mods, hook):
		if not registry.has(m.handler):
			continue
		var params: Dictionary = m.params.duplicate()
		params["power"] = m.power
		if bool(registry.call_handler(m.handler, ctx, false, params)):
			return true
	return false
