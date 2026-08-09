# core/battle/scenario_numeric_ordering.gd
class_name ScenarioNumericOrdering
extends RefCounted

## Narrow battle-seam plumbing for trace-visible CX-008 numeric ordering.

const TRACE_SOURCES := {
	"conditional attack contribution": true,
	"attack randomisation": true,
	"ranged early provider total": true,
	"defence provider total": true,
	"zero-stamina defence halving": true,
	"final defence clamp": true,
	"defence subtraction": true,
	"resistance provider total": true,
	"final resistance clamp": true,
	"ranged resistance branch": true,
	"ordinary ranged-defence branch": true,
	"modifier 0x5F resistance subtraction": true,
	"modifier 0x11 ranged-defence halving": true,
	"modifier 0x4D ranged-defence subtraction": true,
	"modifier 0x3C excess over resistance": true,
	"ranged received-damage channel": true,
	"command-entry charge consumption": true,
	"live-capacity stamina discriminator": true,
	"attack stamina mutation": true,
	"modifier 0x12 stamina mutation suppression": true,
	"ranged activation capacity clear": true,
}


static func append_traces(log: Array, traces: Array) -> void:
	for trace_v in traces:
		var trace := trace_v as Trace
		if trace == null:
			continue
		for step in trace.steps:
			var source := String(step["source"])
			if not TRACE_SOURCES.has(source):
				continue
			var note := String(step["note"])
			log.append("  [trace] %s | %s: %s -> %s%s" % [
				trace.label, source, Trace.fmt(float(step["before"])),
				Trace.fmt(float(step["after"])),
				(" # " + note) if note != "" else "",
			])


static func genesis_charge(unit: Combatant, attacker_xy: Vector2i,
		target_xy: Vector2i, movement_requested: bool) -> Dictionary:
	var applicable := Damage.has_effective_modifier(unit, 0x25)
	var value := Charge.command_entry_charge(
		attacker_xy, target_xy, movement_requested) if applicable else 0
	return {"applicable": applicable, "value": value}


static func append_charge(log: Array, decision: Dictionary,
		attacker_xy: Vector2i, target_xy: Vector2i,
		movement_requested: bool) -> void:
	log.append(("  [trace] command-entry charge | modifier 0x25 applicable %s; "
		+ "movement requested %s; attacker %d,%d; target %d,%d; value %d") % [
		str(bool(decision["applicable"])), str(movement_requested),
		attacker_xy.x, attacker_xy.y, target_xy.x, target_xy.y,
		int(decision["value"]),
	])


static func spend_attack(unit: Combatant,
		kind: Combatant.AttackKind) -> Trace:
	var modifier_0x12 := Damage.has_effective_modifier(unit, 0x12)
	if kind == Combatant.AttackKind.RANGED:
		return ActionPoints.spend_ranged_attack(unit, modifier_0x12)
	# R8 stays ranged-only; melee retains its established cost boundary.
	return ActionPoints.spend_attack(unit, modifier_0x12)


static func resolve_exchange(log: Array, unit: Combatant, target: Combatant,
		rng: Rng, kind: Combatant.AttackKind, action: Variant,
		primary_melee_charge: Variant) -> Counterattack.Exchange:
	var exchange := Counterattack.resolve(
		unit, target, rng, kind, action, primary_melee_charge)
	var cost_trace := spend_attack(unit, kind)
	append_traces(log, exchange.traces)
	append_traces(log, [cost_trace])
	return exchange


static func charge_value(log: Array, decision: Variant,
		attacker_xy: Vector2i, target_xy: Vector2i,
		movement_requested: bool) -> Variant:
	if decision == null:
		return null
	var resolved := decision as Dictionary
	append_charge(log, resolved, attacker_xy, target_xy, movement_requested)
	return int(resolved["value"]) if bool(resolved["applicable"]) else null
