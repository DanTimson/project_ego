"""
counterattack.py — melee retaliation.

Twenty-three abilities in the documentation touch this, and between them they
pin the rules down further than any single one does:

    Контратака            «сколько повреждений воин наносит атаковавшему его
                          противнику во время ответного удара» — a separate
                          stat, not a copy of Attack
    Первый удар           «наносит ответный удар ПРЕЖДЕ, чем его ударит
                          противник ... не действует, если противник тоже
                          обладает первым ударом»
    Ловкость              «атаковать противника врукопашную, ИЗБЕГАЯ ответных
                          ударов» — attacker-side suppression
    Не сражается          «не может атаковать и контратаковать»
    Касание вампира       «не получать контратаки»
    Смертельное касание   «не действует при контратаках» — some on-hit riders
                          are suppressed during a counter
    Парализующее касание  «атаки, контратаки и выстрелы» — and some are not
    Жажда крови           killing by counterattack gives HALF the morale a
                          melee kill would
    Повреждение оружия    melee attackers lose 1 attack AND 1 counterattack

RANGED ATTACKS DO NOT PROVOKE. Every rule above says «врукопашную». A shot is
answered by nothing, which is most of why archers are worth their cost.

FIRST STRIKE IS A REORDERING, NOT AN EXTRA BLOW. `Первый удар` moves the
defender's retaliation ahead of the attack that caused it, so a defender can
kill an attacker before the attack lands. It does not grant a second
retaliation, and two units that both have it cancel out to the normal order.
"""

from __future__ import annotations

import modifier_semantic as semantic

from enum import Enum

import combat
from combat import AttackKind, Combatant, Trace


class NoCounter(Enum):
    """Why a counterattack did not happen. Distinct values because the combat
    log should say which, and the AI needs to know whether it can be arranged
    again next round."""
    NONE = "counterattacked"
    DEAD = "defender is down"
    RANGED = "ranged attacks are not answered"
    NO_STAT = "no counterattack value"
    EXHAUSTED = "at 0 stamina a unit does not counterattack"
    RESTING = "resting forgoes counterattacks"
    CANNOT_FIGHT = "Не сражается"
    EVADED = "the attacker avoided it"


## Attacker-side abilities that avoid retaliation entirely.
EVASIVE = ("Ловкость", "Касание вампира")

# Battle context is scoped by Scenario around one exchange, like the existing
# Damage pipeline/environment bindings. Direct rule tests may leave it unset.
_death_resolver = None


def bind_death_resolver(resolver) -> None:
    global _death_resolver
    _death_resolver = resolver


def why_no_counter(defender: Combatant, attacker: Combatant,
                   kind: AttackKind) -> NoCounter:
    """Decidable before any dice are rolled."""
    if kind is not AttackKind.MELEE:
        return NoCounter.RANGED
    if not defender.alive or defender.life <= 0:
        return NoCounter.DEAD
    if (combat.has_effective_modifier_semantic(
            defender, semantic.Query.MELEE_EXCHANGE_SUPPRESSED)
            or defender.has_flag("Не сражается")):
        return NoCounter.CANNOT_FIGHT
    if defender.counter_attack <= 0:
        return NoCounter.NO_STAT
    # Live exhaustion remains authoritative even when stamina mutation is
    # suppressed by the effective stamina-mutation semantic or its symbolic compatibility alias.
    if defender.stamina <= 0:
        return NoCounter.EXHAUSTED
    if defender.resting:
        return NoCounter.RESTING
    if any(attacker.has_flag(f) for f in EVASIVE):
        return NoCounter.EVADED
    return NoCounter.NONE


def will_counter(defender: Combatant, attacker: Combatant,
                 kind: AttackKind) -> bool:
    return why_no_counter(defender, attacker, kind) is NoCounter.NONE


def strikes_first(defender: Combatant, attacker: Combatant) -> bool:
    """«Это правило не действует, если противник тоже обладает первым ударом.»

    Both having it is not a race — it cancels to the normal order.
    """
    return (defender.has_flag("Первый удар")
            and not attacker.has_flag("Первый удар"))


class Exchange:
    """One melee exchange: the attack, the retaliation, and their order.

    Returned rather than applied so the caller decides what to do with the
    numbers — the scenario runner logs them, the AI evaluates them without
    committing.
    """

    def __init__(self):
        self.attack_damage = 0
        self.ordinary_attack_damage = 0
        self.primary_melee_charge = None
        self.counter_damage = 0
        self.countered = False
        self.counter_first = False
        self.reason = NoCounter.NONE
        self.attacker_fatal_event = False
        self.defender_fatal_event = False
        # Final post-lifecycle death, deliberately distinct from fatal_event.
        self.attacker_died = False
        self.defender_died = False
        self.traces: list = []
        self.order: list = []      # ("attack"|"counter", damage)


def resolve(attacker: Combatant, defender: Combatant, rng,
            kind: AttackKind = AttackKind.MELEE, action=None,
            primary_melee_charge: int | None = None) -> Exchange:
    """Resolve an attack and any retaliation, in the correct order.

    EXP-CI11 distinguishes fatal_event from final post-lifecycle alive state:
    a first-strike survivor still attacks, while a fatal initiating primary
    suppresses ordinary retaliation even if its target survives the lifecycle.
    """
    ex = Exchange()
    ex.reason = why_no_counter(defender, attacker, kind)
    ex.countered = ex.reason is NoCounter.NONE
    ex.counter_first = ex.countered and strikes_first(defender, attacker)

    def do_attack() -> None:
        # Resolve the ordinary strike completely before consuming R3 charge.
        # The combined capped value then feeds the exchange accumulator/order
        # before life subtraction. Retaliation has its own charge-free path.
        scale_numerator = int(getattr(
            action, "initiating_attack_scale_numerator", 1))
        scale_denominator = int(getattr(
            action, "initiating_attack_scale_denominator", 1))
        if kind is AttackKind.RANGED:
            ordinary_damage, traces, ranged_channel = combat.resolve_ranged_attack(
                attacker, defender, rng)
        else:
            ordinary_damage, traces = combat.resolve_attack(
                attacker, defender, kind, rng,
                initiating_scale_numerator=scale_numerator,
                initiating_scale_denominator=scale_denominator)
            ranged_channel = 0
        ex.ordinary_attack_damage = ordinary_damage
        damage = ordinary_damage
        if kind is AttackKind.MELEE and primary_melee_charge is not None:
            charge = max(0, int(primary_melee_charge))
            ex.primary_melee_charge = charge
            combined = ordinary_damage + charge
            damage = min(combined, max(0, defender.life))
            combined_trace = Trace("primary melee combined damage")
            combined_trace.base = ordinary_damage
            combined_trace.step("command-entry charge consumption", ordinary_damage,
                                combined,
                                "initiating primary melee; flat, unrandomized, "
                                "undefended")
            if damage != combined:
                combined_trace.step("target-life cap", combined, damage,
                                    "current target life")
            combined_trace.result = damage
            traces.append(combined_trace)
        ex.attack_damage = damage
        ex.traces.extend(traces)
        ex.order.append(("attack", damage))
        outcome = combat.apply_received_damage(
            defender, damage,
            ranged_channel if kind is AttackKind.RANGED else 0,
            _death_resolver)
        ex.defender_fatal_event = outcome["fatal_event"]
        ex.defender_died = outcome["final_death"]

    def do_counter() -> None:
        damage, traces = combat.resolve_attack(
            defender, attacker, AttackKind.COUNTER, rng)
        ex.counter_damage = damage
        ex.traces.extend(traces)
        ex.order.append(("counter", damage))
        outcome = combat.apply_received_damage(
            attacker, damage, 0, _death_resolver)
        ex.attacker_fatal_event = outcome["fatal_event"]
        ex.attacker_died = outcome["final_death"]

    if ex.counter_first:
        do_counter()
        # A fatal first strike may revive/replace the initiator; resulting life,
        # not fatal_event, decides whether its primary still occurs.
        if attacker.alive and attacker.life > 0:
            do_attack()
    else:
        do_attack()
        # A fatal initiating primary remains on the fatal-event branch even if
        # lifecycle resolution revives/replaces the defender. It receives no
        # ordinary retaliation in this exchange.
        if ex.countered and not ex.defender_fatal_event and defender.alive:
            do_counter()
        elif ex.countered:
            ex.countered = False
            ex.reason = NoCounter.DEAD

    return ex


## «При убийстве противника контратакой или выстрелом воин дополнительно
## получит только половину этого значения.» Killing by counter or by shot is
## worth half the morale a melee kill is.
def morale_kill_share(kind: AttackKind) -> float:
    return 1.0 if kind is AttackKind.MELEE else 0.5


## «Не действует при контратаках» (Смертельное касание) versus «атаки,
## контратаки и выстрелы» (Парализующее касание): whether an on-hit rider fires
## during a counter is per-ability, so it is a property of the rider rather than
## a blanket rule.
COUNTER_SUPPRESSED_RIDERS = ("Смертельное касание",)


def rider_fires(ability_name: str, kind: AttackKind) -> bool:
    if kind is AttackKind.COUNTER and ability_name in COUNTER_SUPPRESSED_RIDERS:
        return False
    return True
