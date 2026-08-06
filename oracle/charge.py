"""Profile-clean arithmetic for command-entry melee charge.

Profile selection and modifier applicability belong to the battle composition
root.  This rule receives only the captured coordinates and whether the attack
command actually requested approach movement.
"""

from __future__ import annotations


def command_entry_charge(attacker_xy: tuple[int, int],
                        target_xy: tuple[int, int],
                        movement_requested: bool) -> int:
    """Return the recovered command-entry charge value (R3)."""
    if not movement_requested:
        return 0
    attacker_x, attacker_y = attacker_xy
    target_x, target_y = target_xy
    return max(abs(target_x - attacker_x) + abs(target_y - attacker_y) - 2, 0)
