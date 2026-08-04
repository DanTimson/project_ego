class_name Morale
extends RefCounted

## «Боевой дух» — attack multiplier.
##
## Keyed on ABSOLUTE morale. `morale_base` does NOT enter the attack multiplier;
## the earlier delta-from-base table was a placeholder shape, not the rule.
##
##   morale 0..5   ->  0.4 + 0.1 * morale     (0 -> 0.4, and the unit panics)
##   morale 6..15  ->  1.0
##   morale >= 16  ->  1.0 + 0.05 * n, band n starting at 15 + n(n+1)/2
##                     16-17 = 1.05  18-20 = 1.10  21-24 = 1.15  25-29 = 1.20
##                     30-35 = 1.25  36-42 = 1.30  43-50 = 1.35  … («и так далее»)
##
## 0..15 is VERIFIED: the Genesis binary's «−10% per missing point below morale
## 6» and the published table's `0.4 + 0.1 * morale` are the same function at
## every point, across two independent sources and two builds.
## See docs/FORMULAS.md §1.4.
##
## >=16 is STRONG INFERENCE for Genesis: both sources agree the step is 5%, but
## the band widths come only from NH 26.0620.f01 documentation and the Genesis
## high-morale branch has not been read. OPEN_QUESTIONS item 1.
##
## Applies to the three ATTACK values only, never to defence — defence is
## touched only by the stamina-0 halving in stamina.gd.
##
## The band index is computed iteratively rather than by solving the quadratic
## with a float sqrt, so this and the Python oracle agree bit for bit.

## Band index n for morale >= 16; multiplier is 1.0 + 0.05 * n.
static func band(morale: int) -> int:
	var n: int = 1
	while 15 + (n + 1) * (n + 2) / 2 <= morale:
		n += 1
	return n

## Returns [multiplier: float, note: String].
static func modifier(u: Combatant) -> Array:
	if u.has_flag(&"Боевое безумие"):
		return [1.0, "morale effects suppressed"]
	var m: int = u.morale
	if m <= 5:
		# m == 0 -> 0.4 and the unit panics; negative morale is unobserved.
		return [0.4 + 0.1 * float(max(m, 0)), "morale %d" % m]
	if m <= 15:
		return [1.0, ""]
	return [1.0 + 0.05 * float(band(m)), "morale %d" % m]
