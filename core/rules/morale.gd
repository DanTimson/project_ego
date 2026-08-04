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

## Morale as the INTEGER percentage the binary actually applies.
##
## The executable does not multiply by a float. After the wound and stamina
## steps it converts the internal x100 value back to an integer and then adds a
## whole-percent bonus:
##
##     pre_morale = scaled_attack / 100
##     result     = pre_morale + bonus_percent * pre_morale / 100
##
## Both divisions truncate toward zero. docs/FORMULAS.md §1.4 (EXP-R1-001).
##
## Returns [percent: int, note: String].
static func percent(u: Combatant) -> Array:
	if u.has_flag(&"Боевое безумие"):
		return [0, "morale effects suppressed"]
	var m: int = u.morale
	if m <= 5:
		# -10 percentage points per point of morale missing below 6.
		return [-10 * (6 - max(m, 0)), "morale %d" % m]
	if m <= 15:
		return [0, ""]
	return [5 * band(m), "morale %d" % m]

## The documented multiplier view of the same curve.
##
## Kept for the published-table fixtures and for tracing. The attack pipeline
## uses percent() instead, because a float multiplier cannot reproduce the
## binary: 1.15 is not exactly representable, so 100 * 1.15 truncates to 114
## where the executable returns 115.
##
## Returns [multiplier: float, note: String].
static func modifier(u: Combatant) -> Array:
	var r: Array = percent(u)
	return [1.0 + float(r[0]) / 100.0, r[1]]
