"""Authoritative address-free tactical death lifecycle (CX-011)."""

from __future__ import annotations

import copy

import combat
import turn

TRANSFER = 0x49
REVIVE = 0x4A
ROLLBACK = 0x5A
REPLACE = 0x5B
REPLACEMENT_BY_TIER = {1: 21, 2: 37, 3: 56, 4: 65}


def replacement_id_for_tier(tier: int) -> int:
    try:
        return REPLACEMENT_BY_TIER[int(tier)]
    except KeyError as exc:
        raise ValueError("death replacement requires original tier 1..4") from exc


def _runtime_marker(unit, ability: int):
    """Return the owning runtime status, never an intrinsic/aura provider."""
    for status in unit.statuses:
        if any(int(modifier.ability) == ability for modifier in status.modifiers):
            return status
    return None


def _side_of(unit, sides):
    return next((side for side in sides if unit in side.units), None)


def transfer_to_opposite_side(unit, sides) -> bool:
    """Move one logical combatant between side rosters without refreshing it."""
    source = _side_of(unit, sides)
    target = next((side for side in sides if side is not source), None)
    if source is None or target is None:
        return False
    source.units.remove(unit)
    if unit not in target.units:
        target.units.append(unit)
    return True


def _normalize_definition(spec: dict, definition_id: int | None = None) -> dict:
    """Convert a content/test definition to the narrow static snapshot shape."""
    out = copy.deepcopy(spec)
    if definition_id is not None:
        out["definition_id"] = int(definition_id)
    for current, maximum in (("life", "life_base"),
                             ("stamina", "stamina_base"),
                             ("morale", "morale_base"),
                             ("ammo", "ammo_base")):
        if maximum not in out and current in out:
            out[maximum] = int(out[current])
    if "flags" in out:
        out["flags"] = set(out["flags"])
    if "subtypes" in out:
        out["subtypes"] = set(out["subtypes"])
    return out


def _emit(events: list, sink, kind: str, unit, **details) -> None:
    event = {"event": kind, "unit": unit.instance_id or unit.name, **details}
    events.append(event)
    if sink is not None:
        sink(event)


def resolve(unit, battlefield, sides, definition_resolver=None, event_sink=None) -> dict:
    """Resolve exactly one fatal event after life has reached zero.

    Death morale precedes every survival branch. Runtime markers are read only
    from Status-owned Modifiers, rollback happens during the pre-clear scan,
    and the complete runtime collection is then consumed before branch choice.
    """
    events = []
    _emit(events, event_sink, "death_started", unit)
    original_side = _side_of(unit, sides)
    position = battlefield.find(unit)
    if position is not None:
        unit.last_position = position

    # Morale reacts to the fatal event, not to the eventual survival result.
    if position is not None and original_side is not None:
        for adjacent in battlefield.adjacent_occupants(position):
            if adjacent is unit or not adjacent.alive or adjacent.life <= 0:
                continue
            delta = -1 if adjacent in original_side.units else 1
            applied = combat.adjust_morale(adjacent, delta)
            _emit(events, event_sink, "death_morale", unit,
                  target=adjacent.instance_id or adjacent.name, delta=delta,
                  applied=applied, morale=adjacent.morale)

    transfer_status = _runtime_marker(unit, TRANSFER)
    revive_status = _runtime_marker(unit, REVIVE)
    replace_status = _runtime_marker(unit, REPLACE)
    rollback_status = _runtime_marker(unit, ROLLBACK)

    if rollback_status is not None and unit.original_definition:
        unit.restore_definition(unit.original_definition)
        unit.original_definition = {}
        restored_speed = turn.effective_speed(unit)[0]
        unit.movement_remaining = min(unit.movement_remaining, restored_speed)
        unit.ammo = min(unit.ammo, unit.ammo_base)
        _emit(events, event_sink, "transformation_reverted", unit,
              definition_id=unit.definition_id)

    cleared = len(unit.statuses)
    unit.statuses.clear()
    _emit(events, event_sink, "statuses_cleared", unit, count=cleared)

    branch = "final"
    if revive_status is not None:
        branch = "revived"
        unit.life = unit.life_base
        unit.morale_break_accumulator = 0
        unit.alive = True
        unit.discarded = False
        _emit(events, event_sink, "revived", unit, life=unit.life)
    elif replace_status is not None:
        branch = "replaced"
        original_tier = int(unit.original_definition.get("tier", unit.tier))
        replacement_id = replacement_id_for_tier(original_tier)
        if definition_resolver is None:
            raise ValueError("death replacement requires a definition resolver")
        definition = definition_resolver(unit, replacement_id)
        if not isinstance(definition, dict):
            raise ValueError("replacement definition %d was not resolved" % replacement_id)
        unit.restore_definition(_normalize_definition(definition, replacement_id))
        unit.original_definition = {}
        unit.life = unit.life_base
        unit.stamina = unit.stamina_base
        unit.ammo = unit.ammo_base
        unit.morale = unit.morale_base
        unit.morale_break_accumulator = 0
        unit.alive = True
        unit.discarded = False
        _emit(events, event_sink, "replaced", unit,
              definition_id=replacement_id, tier=original_tier)
    else:
        unit.life = 0
        unit.alive = False
        if position is not None:
            battlefield.remove(position)
        if unit.battle_owned:
            unit.discarded = True
            if original_side is not None and unit in original_side.units:
                original_side.units.remove(unit)
        _emit(events, event_sink, "death_finalized", unit,
              battle_owned=unit.battle_owned, discarded=unit.discarded)

    transferred = False
    if transfer_status is not None and not (branch == "final" and unit.battle_owned):
        transferred = transfer_to_opposite_side(unit, sides)
        if transferred:
            _emit(events, event_sink, "side_transferred", unit,
                  side=_side_of(unit, sides).id)

    return {
        "fatal_event": True,
        "final_alive": bool(unit.alive and unit.life > 0),
        "branch": branch,
        "transferred": transferred,
        "events": events,
    }
