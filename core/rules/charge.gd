class_name Charge
extends RefCounted

## Profile-clean command-entry charge arithmetic (R3).
##
## Profile selection and modifier applicability stay at the battle composition
## root. This rule receives only coordinates captured before automatic approach
## movement and whether that command actually requested movement.
static func command_entry_charge(attacker_xy: Vector2i, target_xy: Vector2i,
		movement_requested: bool) -> int:
	if not movement_requested:
		return 0
	return maxi(absi(target_xy.x - attacker_xy.x)
		+ absi(target_xy.y - attacker_xy.y) - 2, 0)
