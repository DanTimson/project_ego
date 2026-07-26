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
	# The check is on the FLAG, not the value: Неутомимый units never lose
	# stamina for any action, so a debuff that sets the value directly must not
	# be able to penalise them.
	if u.has_flag(&"Неутомимый"):
		return [1.0, "tireless"]
	if u.stamina > 5:
		return [1.0, ""]
	return [0.4 + 0.1 * float(u.stamina), "stamina %d" % u.stamina]

## Speed penalty: -1 at stamina 3-4, -2 at 2 or below. Speed floors at 1.
static func speed_penalty(u: Combatant) -> int:
	if u.has_flag(&"Неутомимый") or u.stamina > 4:
		return 0
	return -1 if u.stamina >= 3 else -2

static func is_exhausted(u: Combatant) -> bool:
	return u.stamina <= 0 and not u.has_flag(&"Неутомимый")
