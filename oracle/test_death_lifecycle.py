from __future__ import annotations

import modifier_semantic as semantic

import battlefield as bfmod
import combat
import death_lifecycle as death
import scenario
import statuses
import turn
from combat import Combatant
from modifier import Hook, Modifier


def marker(ability: int, *, remove_on_damage: bool = False):
    return statuses.StatusEffect(
        id="runtime-%x" % ability, remove_on_damage=remove_on_damage,
        modifiers=[Modifier(ability=ability, handler="add_flat",
                            hook=Hook.STAT_PASSIVE)])


def setup(victim=None):
    field = bfmod.Battlefield(5, 5)
    victim = victim or Combatant(name="victim", instance_id="victim",
                                 life=1, life_base=10, stamina=3,
                                 stamina_base=8, morale=7, morale_base=12,
                                 ammo=2, ammo_base=5, speed=4)
    ally = Combatant(name="ally", instance_id="ally", life=10, life_base=10,
                     morale=5, morale_base=10)
    enemy = Combatant(name="enemy", instance_id="enemy", life=10, life_base=10,
                      morale=5, morale_base=10)
    sides = [turn.Side(id=0, name="left", units=[victim, ally]),
             turn.Side(id=1, name="right", units=[enemy])]
    field.place(victim, bfmod.offset_to_axial(2, 2))
    field.place(ally, bfmod.offset_to_axial(1, 2))
    field.place(enemy, bfmod.offset_to_axial(3, 2))
    return field, sides, victim, ally, enemy


def resolve_damage(field, sides, victim, amount=1, resolver=None):
    resolver = resolver or (lambda unit: death.resolve(unit, field, sides))
    return combat.apply_received_damage(victim, amount, 0, resolver)


def test_ordinary_final_death_and_damage_boundary():
    field, sides, victim, ally, enemy = setup()
    victim.statuses = [statuses.StatusEffect(id="fragile", remove_on_damage=True),
                       statuses.StatusEffect(id="cleared-at-death")]
    calls = []
    result = combat.apply_received_damage(
        victim, 3, 0,
        lambda unit: calls.append(death.resolve(unit, field, sides)))
    assert result == {"fatal_event": True, "final_alive": False,
                      "final_death": True}
    assert len(calls) == 1
    assert victim.damage_received == [3, 0, 0, 0]
    assert victim.statuses == []
    assert not victim.alive and victim.life == 0
    assert field.find(victim) is None
    assert victim in sides[0].units and not victim.discarded
    assert victim.last_position == bfmod.offset_to_axial(2, 2)


def test_death_morale_precedes_revival_and_immunity():
    field, sides, victim, ally, enemy = setup()
    victim.statuses = [marker(death.REVIVE)]
    immune = Combatant(name="immune", instance_id="immune", life=10,
                       life_base=10, morale=5,
                       modifiers=[Modifier(ability=0x13, handler="add_flat",
                                           hook=Hook.STAT_PASSIVE,
                                           semantics=(semantic.Query.MORALE_UNDERFLOW_SUPPRESSED,))])
    sides[0].units.append(immune)
    field.place(immune, bfmod.offset_to_axial(2, 1))
    broken = Combatant(name="broken", instance_id="broken", life=10,
                       life_base=10, morale=0)
    sides[0].units.append(broken)
    field.place(broken, bfmod.offset_to_axial(1, 3))
    result = resolve_damage(field, sides, victim)
    assert result["fatal_event"] and result["final_alive"]
    assert victim.alive and victim.life == victim.life_base
    assert ally.morale == 4 and enemy.morale == 6 and immune.morale == 5
    assert broken.morale == 0 and broken.morale_break_accumulator == 10


def test_revival_preserves_resources_activation_and_clears_break():
    field, sides, victim, _, _ = setup()
    victim.statuses = [marker(death.REVIVE), statuses.StatusEffect(id="other")]
    victim.morale_break_accumulator = 30
    victim.movement_remaining = 2
    victim.action_spent = True
    before = (victim.stamina, victim.ammo, victim.morale,
              victim.movement_remaining, victim.action_spent)
    resolve_damage(field, sides, victim)
    assert victim.life == 10 and victim.morale_break_accumulator == 0
    assert victim.statuses == []
    assert (victim.stamina, victim.ammo, victim.morale,
            victim.movement_remaining, victim.action_spent) == before


def original_snapshot(**overrides):
    original = Combatant(name="original", content_id="synthetic:unit/7",
                         definition_id=7, tier=2, attack=4, counter_attack=3,
                         life_base=17, stamina_base=9, morale_base=11,
                         speed=3, ammo_base=4, flags={"original"})
    snap = original.definition_snapshot()
    snap.update(overrides)
    return snap


def test_rollback_alone_restores_identity_clamps_down_and_dies():
    field, sides, victim, _, _ = setup()
    victim.name = "temporary"
    victim.content_id = "synthetic:unit/999"
    victim.definition_id = 999
    victim.tier = 4
    victim.life_base = 40
    victim.speed = 8
    victim.ammo_base = 12
    victim.movement_remaining = 7
    victim.ammo = 9
    victim.original_definition = original_snapshot()
    victim.statuses = [marker(death.ROLLBACK)]
    resolve_damage(field, sides, victim)
    assert (victim.name, victim.content_id, victim.definition_id, victim.tier) == (
        "original", "synthetic:unit/7", 7, 2)
    assert victim.movement_remaining == 2 and victim.ammo == 4
    assert victim.stamina == 3 and victim.morale == 7 and victim.life == 0
    assert not victim.alive

    field, sides, victim, _, _ = setup()
    victim.movement_remaining, victim.ammo = 1, 2
    victim.original_definition = original_snapshot()
    victim.statuses = [marker(death.ROLLBACK)]
    resolve_damage(field, sides, victim)
    assert victim.movement_remaining == 1 and victim.ammo == 2


def test_rollback_before_revival_uses_restored_maximum():
    field, sides, victim, _, _ = setup()
    victim.life_base = 40
    victim.original_definition = original_snapshot(life_base=17)
    victim.statuses = [marker(death.ROLLBACK), marker(death.REVIVE)]
    result = resolve_damage(field, sides, victim)
    assert result["final_alive"] and victim.life == 17
    assert victim.definition_id == 7 and victim.statuses == []


def replacement_definition(definition_id):
    return {
        "name": "replacement-%d" % definition_id,
        "content_id": "synthetic:unit/%d" % definition_id,
        "tier": 4, "life_base": 20 + definition_id,
        "stamina_base": 6, "morale_base": 13, "ammo_base": 7,
        "speed": 2,
    }


def synthetic_replacement_decision(definition_id=901, tier=3):
    return lambda _unit: {
        "status": "resolved", "definition": replacement_definition(definition_id),
        "definition_id": definition_id, "tier": tier,
    }


def test_synthetic_replacement_resources_and_no_activation_refresh():
    field, sides, victim, _, _ = setup()
    victim.original_definition = original_snapshot(tier=3)
    victim.statuses = [statuses.StatusEffect(id="other")]
    victim.movement_remaining = 9
    victim.action_spent = True
    victim.morale_break_accumulator = 20
    result = combat.apply_received_damage(
        victim, 1, 0,
        lambda unit: death.resolve(
            unit, field, sides, synthetic_replacement_decision()))
    assert result["fatal_event"] and result["final_alive"]
    assert victim.definition_id == 901
    assert (victim.life, victim.stamina, victim.ammo, victim.morale) == (
        921, 6, 7, 13)
    assert victim.morale_break_accumulator == 0 and victim.statuses == []
    assert victim.movement_remaining == 9 and victim.action_spent
    assert field.find(victim) == bfmod.offset_to_axial(2, 2)


def test_revival_precedes_synthetic_replacement():
    field, sides, victim, _, _ = setup()
    victim.definition_id = 8
    victim.statuses = [marker(death.REVIVE)]
    victim.life = 0
    victim.alive = False
    result = death.resolve(victim, field, sides,
                           synthetic_replacement_decision())
    assert result["final_alive"] and victim.definition_id == 8
    assert victim.life == victim.life_base


def test_direct_and_post_revival_transfer_preserve_one_identity_and_state():
    field, sides, victim, _, _ = setup()
    position = field.find(victim)
    status = statuses.StatusEffect(id="ordinary")
    victim.statuses = [status]
    victim.movement_remaining = 2
    victim.action_spent = False
    before = (victim.life, victim.stamina, victim.ammo,
              victim.movement_remaining, victim.action_spent, list(victim.statuses))
    assert death.transfer_to_opposite_side(victim, sides)
    assert victim not in sides[0].units and sides[1].units.count(victim) == 1
    assert field.find(victim) == position
    assert (victim.life, victim.stamina, victim.ammo,
            victim.movement_remaining, victim.action_spent,
            list(victim.statuses)) == before
    state = turn.BattleState(sides=sides)
    assert victim not in turn.activatable(state, 0)
    assert victim in turn.activatable(state, 1)

    # Move it back, then exercise revive-before-transfer and no refresh.
    assert death.transfer_to_opposite_side(victim, sides)
    victim.life = 1
    victim.action_spent = True
    victim.statuses = [marker(death.REVIVE), marker(death.TRANSFER)]
    resolve_damage(field, sides, victim)
    assert victim in sides[1].units and victim not in sides[0].units
    assert victim.life == victim.life_base and victim.action_spent


def test_battle_owned_is_discarded_persistent_dead_record_is_retained():
    field, sides, persistent, _, _ = setup()
    resolve_damage(field, sides, persistent)
    assert persistent in sides[0].units and not persistent.discarded

    field, sides, transferred_dead, _, _ = setup()
    transferred_dead.statuses = [marker(death.TRANSFER)]
    resolve_damage(field, sides, transferred_dead)
    assert not transferred_dead.alive and transferred_dead in sides[1].units
    assert transferred_dead not in sides[0].units and field.find(transferred_dead) is None

    owned = Combatant(name="owned", instance_id="owned", life=1, life_base=5,
                      battle_owned=True)
    sides[0].units.append(owned)
    field.place(owned, bfmod.offset_to_axial(0, 0))
    resolve_damage(field, sides, owned)
    assert owned not in sides[0].units and owned.discarded and not owned.alive
    assert field.find(owned) is None


def test_special_ids_are_runtime_status_only_and_all_statuses_clear():
    field, sides, victim, _, _ = setup()
    victim.modifiers.append(Modifier(ability=death.REVIVE, handler="add_flat",
                                     hook=Hook.STAT_PASSIVE))
    victim.statuses = [statuses.StatusEffect(id="neutral")]
    result = resolve_damage(field, sides, victim)
    assert result["final_death"] and not victim.alive
    assert victim.statuses == []

    field, sides, victim, _, _ = setup()
    victim.statuses = [marker(death.REVIVE, remove_on_damage=True)]
    result = resolve_damage(field, sides, victim)
    assert result["final_death"] and not victim.alive



def test_upkeep_resolves_only_new_death_transition_and_roster_mutation_is_safe():
    def self_drain(unit_id, at, *, battle_owned=False):
        return {
            "id": unit_id, "name": unit_id, "at": at,
            "life": 1, "life_base": 1, "stamina": 1, "morale": 5,
            "speed": 1, "battle_owned": battle_owned,
            "auras": [{
                "id": "self-drain-" + unit_id, "scope": "SELF",
                "affects": "ALLY", "stacking": "MAXIMUM",
                "tick": {"life": -1},
            }],
        }

    spec = {
        "name": "upkeep fatal transition", "profile": "native", "seed": 1,
        "battlefield": {"width": 5, "height": 5, "tiles": []},
        "sides": [
            {"id": 0, "is_attacker": True, "units": [
                self_drain("owned", [0, 0], battle_owned=True),
                self_drain("persistent", [2, 2]),
                {"id": "ally", "name": "ally", "at": [1, 2],
                 "life": 10, "stamina": 1, "morale": 5, "speed": 1},
            ]},
            {"id": 1, "units": [
                {"id": "enemy", "name": "enemy", "at": [4, 4],
                 "life": 10, "stamina": 1, "morale": 5, "speed": 1},
            ]},
        ], "commands": [],
    }
    sc = scenario.Scenario(spec)
    sc._round_upkeep()
    persistent = sc.units["persistent"]
    owned = sc.units["owned"]
    ally = sc.units["ally"]
    assert sum("persistent death_started" in line for line in sc.log) == 1
    assert sum("owned death_started" in line for line in sc.log) == 1
    assert ally.morale == 4
    assert persistent in sc.sides[0].units and not persistent.alive
    assert sc.field.find(persistent) is None
    assert owned not in sc.sides[0].units and owned.discarded

    # A later upkeep sees retained dead records but cannot reopen their event.
    sc._round_upkeep()
    assert sum("persistent death_started" in line for line in sc.log) == 1
    assert sum("owned death_started" in line for line in sc.log) == 1
    assert ally.morale == 4
    assert persistent in sc.sides[0].units and not persistent.alive
    assert sc.field.find(persistent) is None
