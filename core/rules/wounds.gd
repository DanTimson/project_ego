class_name Wounds
extends RefCounted

## «Тяжёлые ранения» — Eadoropedia, Игровая механика.
##
##     life >= 50% of base  ->  1.0
##     life <  50% of base  ->  0.5 + current / base
##
## Verified against the published table (50%→1.0 … 10%→0.6).

## Returns [multiplier: float, note: String].
static func modifier(u: Combatant) -> Array:
	if u.has_flag(&"Не чувствует боли") or u.has_flag(&"Боевое безумие"):
		return [1.0, "immune to wound penalty"]
	if float(u.life) >= float(u.life_base) * 0.5:
		return [1.0, ""]
	return [0.5 + float(u.life) / float(u.life_base), "life %d/%d" % [u.life, u.life_base]]
