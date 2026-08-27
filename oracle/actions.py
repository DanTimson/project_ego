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

    ## Original/source ability identity retained only at the content boundary.
    ## Runtime recipes resolve from canonical ``id`` and never dispatch on this.
    source_id: int = -1

    ## From unit_upg.Quantity. Meaning is per-action: heal amount, stamina
    ## drain inflicted, ammo collected, defence bonus.
    magnitude: int = 0

    ## Performs an attack, so it competes with the normal attack rather than
    ## being usable alongside it.
    is_attack: bool = False

    ## Damage multiplier for attack-replacing actions. For the accepted selected
    ## ordinary-attack 1.5x branch this adds trunc0(effective attack / 2) before
    ## conditional contribution, randomisation and defence. Ranged action
    ## execution remains outside the currently accepted boundary.
    damage_scale: float = 1.0

    ## Abilities switched off for the duration of this action.
    suppresses: tuple = ()

    ## Abilities whose magnitude is scaled for the duration of this action.
    scales: tuple = ()          # ((ability_name, factor), ...)

    ## Target tags this action cannot affect.
    excluded_targets: tuple = ()

    ## Modifiers granted to the actor, as (ability_name, magnitude, duration).
    grants: tuple = ()

    notes: str = ""

    # Composition-owned normalized metadata for pack-defined declarative plans.
    # The value is an immutable DeclarativeRecipe; malformed permissive content
    # retains only its durable error and can never partially compile.
    declarative_recipe: object | None = None
    declarative_recipe_error: str = ""

    def availability(self, actor,
                     modifier_0x12_effective: bool = False) -> Refusal:
        """Decidable from the actor alone. Target legality is checked by the
        battle layer, which knows what is adjacent and what is dead."""
        stamina_suppressed = (modifier_0x12_effective
                              or actor.has_modifier_id(0x12)
                              or actor.has_flag("Неутомимый"))
        if actor.action_spent and self.cost.resolve(actor).consumes_action:
            return Refusal.ACTION_SPENT
        # At 0 stamina the unit is forced to Rest next round and can do nothing
        # else — «в свой следующий ход принудительно выполняет команду Отдых».
        if actor.stamina <= 0 and not stamina_suppressed:
            return Refusal.EXHAUSTED
        c = self.cost.resolve(actor)
        if c.stamina > 0 and not stamina_suppressed and actor.stamina < c.stamina:
            return Refusal.NO_STAMINA
        if c.ammo > 0 and actor.ammo < c.ammo:
            return Refusal.NO_AMMO
        return Refusal.OK

    def is_available(self, actor,
                     modifier_0x12_effective: bool = False) -> bool:
        return self.availability(actor, modifier_0x12_effective) is Refusal.OK

    def pay(self, actor, modifier_0x12_effective: bool = False):
        from combat import Trace
        c = self.cost.resolve(actor)
        t = Trace(f"{actor.name}.action_stamina_cost")
        t.base = actor.stamina
        stamina_suppressed = (modifier_0x12_effective
                              or actor.has_modifier_id(0x12)
                              or actor.has_flag("Неутомимый"))
        if c.stamina and stamina_suppressed:
            t.step("modifier 0x12 stamina mutation suppression",
                   t.base, t.base,
                   "requested action stamina cost %d" % c.stamina)
        elif c.stamina:
            actor.stamina = max(0, actor.stamina - c.stamina)
            t.step("action stamina mutation", t.base, actor.stamina,
                   "resolved action cost")
        actor.ammo = max(0, actor.ammo - c.ammo)
        if c.consumes_action:
            actor.action_spent = True
        t.result = actor.stamina
        return t


# ---------------------------------------------------------------------------
# Fourteen evidence/reference entries. They are not a production composition source.
# Production stock defaults deliberately include only currently executable, tracked
# bindings and live in content_actions.py.
# ---------------------------------------------------------------------------

def action_from_dict(d: dict) -> Action:
    """Build an Action from plain data.

    Mirrors `Action.from_dict` in core/model/action.gd so a scenario file can
    carry its own actions and both implementations build the same catalogue from
    the same bytes.

    `target` accepts the ORDINAL used by the fixtures (the port's enum index) as
    well as this module's string value, because the serialized form the port
    reads is the ordinal.
    """
    return Action(
        id=str(d.get("id", "")),
        name=str(d.get("name", "")),
        cost=Cost(stamina=int(d.get("cost_stamina", 0)),
                  ammo=int(d.get("cost_ammo", 0)),
                  consumes_action=bool(d.get("consumes_action", True)),
                  attack_surcharge=bool(d.get("attack_surcharge", False)),
                  free_action_for=tuple(d.get("free_action_for", ()))),
        target=(list(Target)[int(d["target"])] if isinstance(d.get("target"), int)
                else Target(d.get("target", Target.SELF.value))),
        source_id=int(d.get("source_id", -1)),
        magnitude=int(d.get("magnitude", 0)),
        is_attack=bool(d.get("is_attack", False)),
        damage_scale=float(d.get("damage_scale", 1.0)),
        suppresses=tuple(d.get("suppresses", ())),
        scales=tuple(tuple(x) for x in d.get("scales", ())),
        excluded_targets=tuple(d.get("excluded_targets", ())),
        grants=tuple(tuple(g) for g in d.get("grants", ())),
        notes=str(d.get("notes", "")),
        declarative_recipe=d.get("__validated_declarative_recipe"),
        declarative_recipe_error=str(d.get("__declarative_recipe_error", "")),
    )


REFERENCE_CATALOGUE: dict[str, Action] = {}


def _add(a: Action) -> Action:
    REFERENCE_CATALOGUE[a.id] = a
    return a


# --- attack replacements ---------------------------------------------------

_add(Action(
    id="extra_shot", source_id=20, name="Дополнительный выстрел",
    cost=Cost(stamina=0, attack_surcharge=True),   # stamina from Расход выносливости
    target=Target.ENEMY_RANGED, is_attack=True,
    suppresses=("Бронебойный выстрел",),
    scales=(("Точный выстрел", 0.5),),
    notes="Two shots at one target. Fully disables armour-piercing shot, halves accurate shot.",
))

_add(Action(
    id="power_shot", source_id=361, name="Мощный выстрел",
    cost=Cost(stamina=0, attack_surcharge=True),
    target=Target.ENEMY_RANGED, is_attack=True, damage_scale=1.5,
))

_add(Action(
    id="crushing_blow", source_id=59, name="Сокрушающий удар",
    cost=Cost(stamina=0, attack_surcharge=True),
    target=Target.ENEMY_MELEE, is_attack=True, damage_scale=1.5,
))

_add(Action(
    id="whirlwind", source_id=66, name="Круговая атака",
    cost=Cost(stamina=0, attack_surcharge=True),
    target=Target.ALL_ADJACENT_ENEMIES, is_attack=True,
))

_add(Action(
    id="shield_bash", source_id=388, name="Удар щитом",
    cost=Cost(stamina=1, attack_surcharge=True),
    target=Target.ENEMY_MELEE, is_attack=True, damage_scale=0.0,
    excluded_targets=("Бестелесный",),
    notes="No damage and no normal on-hit effects; drains `magnitude` stamina "
          "from the target. Defender does not retaliate.",
))

_add(Action(
    id="frenzy", source_id=454, name="Бешенство",
    cost=Cost(stamina=2, attack_surcharge=True),
    target=Target.ENEMY_MELEE, is_attack=True,
    notes="Heals the actor up to `magnitude`, capped at damage actually dealt — "
          "so the heal must be sequenced after damage resolution.",
))

# --- self buffs ------------------------------------------------------------

_add(Action(
    id="turtle", source_id=458, name="Глухая оборона",
    cost=Cost(stamina=0), target=Target.SELF,
    grants=(("Защита", None, 1), ("Защита от выстрела", None, 1), ("Бдительность", 1, 1)),
    notes="+magnitude to both defences and Бдительность until next turn; "
          "attack and counterattack drop by a second documented amount. "
          "OPEN: the penalty is a separate %d from the bonus.",
))

_add(Action(
    id="forced_march", source_id=29, name="Марш-бросок",
    cost=Cost(stamina=3), target=Target.SELF,
    grants=(("Скорость", 1, 0),),
    notes="+1 speed until end of turn.",
))

_add(Action(
    id="sniper_shot", source_id=360, name="Снайперский выстрел",
    cost=Cost(stamina=0, attack_surcharge=True),
    target=Target.ENEMY_RANGED, is_attack=True,
    scales=(("Точный выстрел", 2.0),),
    notes="Speed becomes 1 and shooting range +1 for the shot.",
))

# --- support ---------------------------------------------------------------

_add(Action(
    id="healing", source_id=24, name="Целительство",
    cost=Cost(ammo=1), target=Target.ALLY_IN_SHOOTING_RANGE,
    excluded_targets=("Нежить", "Механизм", "Голем", "Стихийный дух"),
    notes="Restores `magnitude` life on average — randomised, distribution unknown.",
))

_add(Action(
    id="repair", source_id=374, name="Ремонт",
    cost=Cost(ammo=1), target=Target.ALLY_IN_SHOOTING_RANGE,
    notes="Mechanisms only. Restores `magnitude` on average and shortens armour "
          "and weapon damage effects.",
))

# --- resource --------------------------------------------------------------

_add(Action(
    id="gather_ammo", source_id=23, name="Сбор снарядов",
    cost=Cost(), target=Target.NONE,
    notes="Up to `magnitude` ammo. An adjacent Оруженосец guarantees at least one; "
          "multiple Оруженосец take the MAXIMUM, they do not sum.",
))

_add(Action(
    id="carrion_eater", source_id=49, name="Трупоед",
    cost=Cost(free_action_for=("Крысолюд",)), target=Target.CORPSE,
    notes="Restores up to `magnitude` life. Free action for Крысолюд.",
))

# --- movement rider --------------------------------------------------------

_add(Action(
    id="strike_and_return", source_id=518, name="Удар и возврат",
    cost=Cost(stamina=1), target=Target.SELF,
    notes="Returns to the tile where the ATTACK COMMAND was issued, not the "
          "round-start tile. FAILS if a defender carrying Корни or "
          "Калечащий удар counterattacks — so resolution is conditional on the "
          "counterattack outcome.",
))


def canonical_id_for_source(source_id: int,
                            catalogue: dict[str, Action]) -> str | None:
    """Explicit content/import-boundary lookup over composed definitions."""
    definitions = catalogue
    for canonical_id, action in definitions.items():
        if action.source_id == int(source_id):
            return canonical_id
    return None
