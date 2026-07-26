## core_skeleton.gd — shape of the simulation core for project_ego.
##
## Everything here is RefCounted. Nothing extends Node. Nothing touches the
## scene tree. That is the load-bearing constraint: it is what lets the whole
## rules layer run under `godot --headless --script test_battle.gd` in CI, and
## it is what makes differential testing against the original possible.
##
## Split these into separate files under res://core/ when you commit; they are
## in one block here so the relationships are readable.

# ---------------------------------------------------------------------------
# Hooks. The ordered resolution sequence. This enum IS the architecture — the
# order of these values decides rounding, clamping, and whether percentage
# modifiers compound. Changing the order later changes every battle outcome.
# ---------------------------------------------------------------------------

class Hook:
	enum V {
		BATTLE_START, ROUND_START, INITIATIVE, TURN_START,
		MOVE_LEGALITY, MOVE_COST, MOVE_COMPLETE,
		ATTACK_DECLARE, ATTACK_ACCURACY, DAMAGE_BASE, DAMAGE_VS_TARGET,
		EVASION, DEFENCE_APPLY, DAMAGE_TAKEN,
		ON_HIT, ON_DAMAGED, COUNTERATTACK, ON_KILL, ON_DEATH,
		STAMINA, MORALE, AMMO, REGEN, STATUS_APPLY, STATUS_RESIST,
		SPELL_POWER, SPELL_GRANT, SUMMON,
		STAT_PASSIVE, AURA,
		TURN_END, ROUND_END, BATTLE_END,
	}

# ---------------------------------------------------------------------------
# Modifier — the atomic value type. Everything that changes a number is one of
# these: innate ability, level-up perk, item enchant, spell buff, terrain,
# medal, aura. One type, one resolution path, one place to debug.
# ---------------------------------------------------------------------------

class Modifier extends RefCounted:
	var ability_id: int          ## opaque; meaningful only against its pack
	var handler: StringName      ## resolved at load from the pack's bindings
	var hook: Hook.V
	var power: int
	var duration: int = -1       ## -1 = permanent
	var area: int = 0
	var source: StringName       ## "unit:5/innate", "item:300", "spell:40" …

	func _init(p_ability: int, p_handler: StringName, p_hook: Hook.V,
			p_power: int, p_source: StringName) -> void:
		ability_id = p_ability
		handler = p_handler
		hook = p_hook
		power = p_power
		source = p_source

# ---------------------------------------------------------------------------
# Resolution trace. Every computed stat can explain itself. This is not a debug
# luxury: it is simultaneously the tooltip system, the combat log, and the
# diff target when comparing against the original. Build it in from line one —
# retrofitting introspection into a pipeline is far more work than having it.
# ---------------------------------------------------------------------------

class Trace extends RefCounted:
	var base: int
	var steps: Array[Dictionary] = []   ## {source, handler, before, after}

	func step(source: StringName, handler: StringName, before: int, after: int) -> void:
		steps.append({"source": source, "handler": handler,
					  "before": before, "after": after})

	func explain() -> String:
		var out := "base %d" % base
		for s in steps:
			out += "\n  %-28s %s  %d -> %d" % [s.source, s.handler, s.before, s.after]
		return out

# ---------------------------------------------------------------------------
# AbilityRegistry — handler name to implementation. Handlers are ENGINE code
# and are named, never numbered. The pack supplies the number->name mapping.
# This indirection is what lets `genesis` and `new_horizons` disagree about
# what opcode 30 means without a single conditional in the rules.
# ---------------------------------------------------------------------------

class AbilityRegistry extends RefCounted:
	var _handlers: Dictionary = {}     ## StringName -> Callable

	func register(name: StringName, fn: Callable) -> void:
		_handlers[name] = fn

	func has(name: StringName) -> bool:
		return _handlers.has(name)

	func call_handler(name: StringName, ctx: Dictionary, value: int, power: int) -> int:
		return _handlers[name].call(ctx, value, power)

# ---------------------------------------------------------------------------
# ContentPack — parsed tables plus the opcode->handler binding manifest.
# Loading MUST fail loudly on unbound opcodes and report which. That failure
# list is your implementation progress meter: start with vanilla's 89 core
# opcodes bound, and the unbound count for the NH pack tells you exactly how
# far that pack is from playable.
# ---------------------------------------------------------------------------

class ContentPack extends RefCounted:
	var id: StringName
	var units: Dictionary = {}         ## int -> Dictionary
	var upgrades: Dictionary = {}      ## int -> Dictionary  (the OPTION layer)
	var abilities: Dictionary = {}     ## opcode int -> Dictionary
	var bindings: Dictionary = {}      ## opcode int -> StringName handler
	var unbound: Array[int] = []

	func load_from(dir_path: String, registry: AbilityRegistry) -> Error:
		# parse the converted JSON produced by eador_var.py --json
		# … units / upgrades / abilities / bindings …
		unbound.clear()
		for opcode in abilities.keys():
			var handler: StringName = bindings.get(opcode, &"")
			if handler == &"" or not registry.has(handler):
				unbound.append(opcode)
		if not unbound.is_empty():
			push_warning("%s: %d unbound opcodes: %s"
				% [id, unbound.size(), unbound.slice(0, 12)])
		return OK

# ---------------------------------------------------------------------------
# ContentDb — a CONSTRUCTED, PASSED instance. Not an autoload. The autoload, if
# you keep one, holds only the *currently active* db for the UI to read; the
# simulation always takes it as an argument. The moment the rules can only run
# inside a live scene tree you lose the headless harness.
# ---------------------------------------------------------------------------

class ContentDb extends RefCounted:
	var pack: ContentPack
	var registry: AbilityRegistry

	func _init(p_pack: ContentPack, p_registry: AbilityRegistry) -> void:
		pack = p_pack
		registry = p_registry

	## The single place a derived stat is computed. Deliberately boring.
	func resolve(base: int, mods: Array, hook: Hook.V, ctx: Dictionary) -> Array:
		var trace := Trace.new()
		trace.base = base
		var value := base
		for m in mods:
			if m.hook != hook:
				continue
			var before := value
			value = registry.call_handler(m.handler, ctx, value, m.power)
			trace.step(m.source, m.handler, before, value)
		return [value, trace]

# ---------------------------------------------------------------------------
# Deterministic RNG. Named streams so that adding a roll in one subsystem does
# not shift every other subsystem's sequence — the single cheapest thing you
# can do to keep replays stable while the rules are still changing.
# ---------------------------------------------------------------------------

class Rng extends RefCounted:
	var _streams: Dictionary = {}
	var _seed: int

	func _init(p_seed: int) -> void:
		_seed = p_seed

	func stream(name: StringName) -> RandomNumberGenerator:
		if not _streams.has(name):
			var r := RandomNumberGenerator.new()
			r.seed = hash(str(_seed) + "/" + name)
			_streams[name] = r
		return _streams[name]
