class_name Stamina
extends RefCounted

## «Выносливость» — Eadoropedia, Игровая механика.
##
##     stamina >  5  ->  1.0
##     stamina <= 5  ->  0.4 + 0.1 * stamina
##
## Verified against the published table. At stamina 0 the unit is additionally
## forced to Rest, does not counterattack, and both defences are halved — see
## Damage.current_defence.

## Returns [multiplier: float, note: String].
static func modifier(u: Combatant) -> Array:
	# Derived from the LIVE stamina value. The stamina-suppression semantic «Неутомимость» is NOT
	# consulted: R11's write audit found that every recovered tactical stamina
	# mutation queries the stamina-suppression semantic, but no recovered effective-stat function does.
	# The previous flag check was an inference — "such a unit never loses stamina
	# so it never reaches the penalty band" — which is false when stamina is set
	# directly by a script, an import, malformed content or a mod, and produced a
	# unit simultaneously at low stamina and unpenalised. the stamina-suppression semantic is
	# stamina-mutation immunity, not penalty immunity.
	if u.stamina > 5:
		return [1.0, ""]
	return [0.4 + 0.1 * float(u.stamina), "stamina %d" % u.stamina]

## Speed penalty, kept for callers that want it in isolation. The live speed
## calculation is ActionPoints.effective_speed, which implements the recovered
## `004D0560` form directly; this helper must agree with it.
##
## The stamina-suppression semantic is not consulted, for the reason given on `modifier` above.
static func speed_penalty(u: Combatant) -> int:
	if u.stamina > 4:
		return 0
	return -1 if u.stamina >= 3 else -2

## True at exactly zero stamina. The predicate is equality, matching the
## recovered defence tail (R9); the stamina-suppression semantic is not consulted.
static func is_exhausted(u: Combatant) -> bool:
	return u.stamina == 0


## CX-013 tactical stamina drain. This is intentionally not a generic signed
## resource mutation: no authoritative maximum-stamina clamp is established here.
## The caller supplies the battle-contextual effective-the stamina-suppression semantic result; the Russian
## flag remains the existing compatibility alias.
static func apply_tactical_drain(u: Combatant, amount: int,
		semantic_suppression_effective: bool = false) -> Trace:
	assert(amount <= 0, "CX-013 tactical stamina operation supports drains only")
	var t := Trace.new("%s.stamina_delta" % u.name)
	t.base = float(u.stamina)
	var suppressed := semantic_suppression_effective or u.has_flag(&"Неутомимый")
	if amount != 0 and suppressed:
		t.step("stamina.mutation_suppressed", t.base, t.base,
			"requested tactical stamina drain %+d" % amount)
	elif amount < 0:
		u.stamina = maxi(0, u.stamina + amount)
		t.step("tactical stamina mutation", t.base, float(u.stamina),
			"signed resource delta %+d" % amount)
	t.result = float(u.stamina)
	return t
