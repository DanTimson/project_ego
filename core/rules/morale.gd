class_name Morale
extends RefCounted

## «Боевой дух» — Eadoropedia, Игровая механика.
##
## OPEN. The mechanism is documented; the numbers are deliberately withheld:
## «точные цифры не разглашаются». The table below is a PLACEHOLDER shaped like
## the other two multipliers (linear, 1.0 at base morale) and is almost
## certainly wrong in detail.
##
## Closing it needs no combat: the map panel shows attack WITHOUT morale, the
## battle panel WITH it, so the ratio between the two screens is the multiplier.
## Fix a unit, vary morale, read both. See OPEN_QUESTIONS item 1.

## delta from base morale -> multiplier. Fill from observation; entries here
## take precedence over the linear placeholder.
const TABLE: Dictionary = {}

const PER_POINT: float = 0.05

## Returns [multiplier: float, note: String].
static func modifier(u: Combatant) -> Array:
	if u.has_flag(&"Боевое безумие"):
		return [1.0, "morale effects suppressed"]
	var delta: int = u.morale - u.morale_base
	if TABLE.has(delta):
		return [float(TABLE[delta]), "morale %d (table)" % u.morale]
	if delta == 0:
		return [1.0, ""]
	return [1.0 + PER_POINT * float(delta), "morale %d (PLACEHOLDER)" % u.morale]
