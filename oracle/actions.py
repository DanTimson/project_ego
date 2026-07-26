"""
actions.py — activated abilities.

The Hook enum models passives that intervene in a resolution pipeline. These are
different in kind: things a unit CHOOSES to do, competing for its action, with
costs and preconditions. The tell in the documentation is uniform —
«Особое умение, позволяющее воину…» plus a cost.

THREE FINDINGS FROM READING ALL FOURTEEN TOGETHER
-------------------------------------------------

1. COST IS NOT IN THE DATA. `unit_upg.Quantity` supplies the effect MAGNITUDE,
   never the cost. Бешенство costs 2 stamina and heals %d; Марш-бросок costs 3
   and grants +1 speed; Целительство costs 1 ammo and heals %d. The costs are
   literals in the prose, so they must come from our binding/override layer.
   Anything that reads Quantity as a cost will be wrong for most of the set.

2. ACTIONS SUPPRESS AND SCALE OTHER ABILITIES. This is not a cost-and-effect
   model. Дополнительный выстрел «полностью отключает Бронебойный выстрел, и
   уменьшает наполовину Точный выстрел»; Снайперский выстрел doubles Точный
   выстрел for that shot; Удар щитом suppresses the whole normal on-hit chain
   AND the defender's counterattack. So an Action needs to modify the ability
   environment for the duration of the attack it performs.

3. COST IS A FUNCTION OF THE UNIT, NOT A CONSTANT. «Крысолюды способны есть
   трупы без затрат хода» — Трупоед costs the turn for everyone except one
   subtype. Cost must be resolved against the actor.

Plus the documented global rule: an activated ability costs 1 MORE stamina than
its description states, because the attack itself is charged separately.

WHAT THIS FILE DOES NOT DO
--------------------------
Execution. Effects are declared as data; running them needs battle state that
does not exist yet (adjacency, corpses, target lists). Legality and cost are
implemented and tested, because those are decidable from the actor alone.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class Target(Enum):
    SELF = "self"
    ENEMY_MELEE = "enemy_melee"
    ENEMY_RANGED = "enemy_ranged"
    ALL_ADJACENT_ENEMIES = "all_adjacent_enemies"
    ALLY_IN_SHOOTING_RANGE = "ally_in_shooting_range"
    CORPSE = "corpse"
    NONE = "none"


class Refusal(Enum):
    """Why an action is unavailable. Distinct values because the UI needs to say
    which, and the AI needs to know whether waiting would help."""
    OK = "ok"
    NO_STAMINA = "not enough stamina"
    NO_AMMO = "not enough ammo"
    ACTION_SPENT = "already acted this round"
    EXHAUSTED = "forced to rest at 0 stamina"
    NO_LEGAL_TARGET = "no legal target"


@dataclass(frozen=True)
class Cost:
    stamina: int = 0
    ammo: int = 0
    consumes_action: bool = True

    ## «в этом случае тратится на 1 Выносливость больше, чем написано в описании
    ## умения (она тратится за факт атаки)» — set only for abilities that
    ## perform an attack.
    attack_surcharge: bool = False

    ## Subtypes that pay no action cost. Трупоед is free for Крысолюд.
    free_action_for: tuple = ()

    def resolve(self, actor) -> "Cost":
        stamina = self.stamina + (1 if self.attack_surcharge else 0)
        consumes = self.consumes_action
        if consumes and any(actor.has_subtype(s) for s in self.free_action_for):
            consumes = False
        return Cost(stamina=stamina, ammo=self.ammo, consumes_action=consumes)


@dataclass(frozen=True)
class Action:
    id: str
    name: str
    cost: Cost
    target: Target

    ## From unit_upg.Quantity. Meaning is per-action: heal amount, stamina
    ## drain inflicted, ammo collected, defence bonus.
    magnitude: int = 0

    ## Performs an attack, so it competes with the normal attack rather than
    ## being usable alongside it.
    is_attack: bool = False

    ## Damage multiplier for attack-replacing actions. «в полтора раза большие
    ## повреждения» = 1.5. OPEN: whether this scales the attack value before
    ## the roll or the final damage after defence. Those differ, because the
    ## roll is integer and defence is subtracted afterwards.
    damage_scale: float = 1.0

    ## Abilities switched off for the duration of this action.
    suppresses: tuple = ()

    ## Abilities whose magnitude is scaled for the duration of this action.
    scales: tuple = ()          # ((ability_name, factor), ...)

    ## Target tags this action cannot affect.
    excluded_targets: tuple = ()

    ## Modifiers granted to the actor, as (ability_name, magnitude, duration).
    grants: tuple = ()

    ## Defender does not retaliate against this action.
    suppresses_counterattack: bool = False

    notes: str = ""

    def availability(self, actor) -> Refusal:
        """Decidable from the actor alone. Target legality is checked by the
        battle layer, which knows what is adjacent and what is dead."""
        if actor.action_spent and self.cost.resolve(actor).consumes_action:
            return Refusal.ACTION_SPENT
        # At 0 stamina the unit is forced to Rest next round and can do nothing
        # else — «в свой следующий ход принудительно выполняет команду Отдых».
        if actor.stamina <= 0 and not actor.has_flag("Неутомимый"):
            return Refusal.EXHAUSTED
        c = self.cost.resolve(actor)
        if c.stamina > 0 and not actor.has_flag("Неутомимый") and actor.stamina < c.stamina:
            return Refusal.NO_STAMINA
        if c.ammo > 0 and actor.ammo < c.ammo:
            return Refusal.NO_AMMO
        return Refusal.OK

    def is_available(self, actor) -> bool:
        return self.availability(actor) is Refusal.OK

    def pay(self, actor) -> None:
        c = self.cost.resolve(actor)
        if not actor.has_flag("Неутомимый"):
            actor.stamina = max(0, actor.stamina - c.stamina)
        actor.ammo = max(0, actor.ammo - c.ammo)
        if c.consumes_action:
            actor.action_spent = True


# ---------------------------------------------------------------------------
# The fourteen. Magnitudes come from unit_upg.Quantity at load time; the values
# here are the DEFINITIONS, not instances.
# ---------------------------------------------------------------------------

CATALOGUE: dict[str, Action] = {}


def _add(a: Action) -> Action:
    CATALOGUE[a.id] = a
    return a


# --- attack replacements ---------------------------------------------------

_add(Action(
    id="extra_shot", name="Дополнительный выстрел",
    cost=Cost(stamina=0, attack_surcharge=True),   # stamina from Расход выносливости
    target=Target.ENEMY_RANGED, is_attack=True,
    suppresses=("Бронебойный выстрел",),
    scales=(("Точный выстрел", 0.5),),
    notes="Two shots at one target. Fully disables armour-piercing shot, halves accurate shot.",
))

_add(Action(
    id="power_shot", name="Мощный выстрел",
    cost=Cost(stamina=0, attack_surcharge=True),
    target=Target.ENEMY_RANGED, is_attack=True, damage_scale=1.5,
))

_add(Action(
    id="crushing_blow", name="Сокрушающий удар",
    cost=Cost(stamina=0, attack_surcharge=True),
    target=Target.ENEMY_MELEE, is_attack=True, damage_scale=1.5,
))

_add(Action(
    id="whirlwind", name="Круговая атака",
    cost=Cost(stamina=0, attack_surcharge=True),
    target=Target.ALL_ADJACENT_ENEMIES, is_attack=True,
))

_add(Action(
    id="shield_bash", name="Удар щитом",
    cost=Cost(stamina=1, attack_surcharge=True),
    target=Target.ENEMY_MELEE, is_attack=True, damage_scale=0.0,
    suppresses_counterattack=True,
    excluded_targets=("Бестелесный",),
    notes="No damage and no normal on-hit effects; drains `magnitude` stamina "
          "from the target. Defender does not retaliate.",
))

_add(Action(
    id="frenzy", name="Бешенство",
    cost=Cost(stamina=2, attack_surcharge=True),
    target=Target.ENEMY_MELEE, is_attack=True,
    notes="Heals the actor up to `magnitude`, capped at damage actually dealt — "
          "so the heal must be sequenced after damage resolution.",
))

# --- self buffs ------------------------------------------------------------

_add(Action(
    id="turtle", name="Глухая оборона",
    cost=Cost(stamina=0), target=Target.SELF,
    grants=(("Защита", None, 1), ("Защита от выстрела", None, 1), ("Бдительность", 1, 1)),
    notes="+magnitude to both defences and Бдительность until next turn; "
          "attack and counterattack drop by a second documented amount. "
          "OPEN: the penalty is a separate %d from the bonus.",
))

_add(Action(
    id="forced_march", name="Марш-бросок",
    cost=Cost(stamina=3), target=Target.SELF,
    grants=(("Скорость", 1, 0),),
    notes="+1 speed until end of turn.",
))

_add(Action(
    id="sniper_shot", name="Снайперский выстрел",
    cost=Cost(stamina=0, attack_surcharge=True),
    target=Target.ENEMY_RANGED, is_attack=True,
    scales=(("Точный выстрел", 2.0),),
    notes="Speed becomes 1 and shooting range +1 for the shot.",
))

# --- support ---------------------------------------------------------------

_add(Action(
    id="healing", name="Целительство",
    cost=Cost(ammo=1), target=Target.ALLY_IN_SHOOTING_RANGE,
    excluded_targets=("Нежить", "Механизм", "Голем", "Стихийный дух"),
    notes="Restores `magnitude` life on average — randomised, distribution unknown.",
))

_add(Action(
    id="repair", name="Ремонт",
    cost=Cost(ammo=1), target=Target.ALLY_IN_SHOOTING_RANGE,
    notes="Mechanisms only. Restores `magnitude` on average and shortens armour "
          "and weapon damage effects.",
))

# --- resource --------------------------------------------------------------

_add(Action(
    id="gather_ammo", name="Сбор снарядов",
    cost=Cost(), target=Target.NONE,
    notes="Up to `magnitude` ammo. An adjacent Оруженосец guarantees at least one; "
          "multiple Оруженосец take the MAXIMUM, they do not sum.",
))

_add(Action(
    id="carrion_eater", name="Трупоед",
    cost=Cost(free_action_for=("Крысолюд",)), target=Target.CORPSE,
    notes="Restores up to `magnitude` life. Free action for Крысолюд.",
))

# --- movement rider --------------------------------------------------------

_add(Action(
    id="strike_and_return", name="Удар и возврат",
    cost=Cost(stamina=1), target=Target.SELF,
    notes="Returns to the tile where the ATTACK COMMAND was issued, not the "
          "round-start tile. FAILS if a defender carrying Корни or "
          "Калечащий удар counterattacks — so resolution is conditional on the "
          "counterattack outcome.",
))
