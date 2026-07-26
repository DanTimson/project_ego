"""
combat.py — executable reference implementation of the Eador attack pipeline.

Source: Eadoropedia "Игровая механика", sections «Расчёт урона при атаках»,
«Тяжёлые ранения», «Выносливость», «Боевой дух (мораль)».

This is Python, not GDScript, on purpose. It runs in CI today, its outputs are
diffable, and it is the ORACLE the Godot port gets checked against. Porting it
is mechanical; verifying it is not, so verification happens here first.

Every quantity carries a Trace. That is not a debug convenience — it is the
tooltip system, the combat log, and the diff target against the original, all
the same object.

MASTER FORMULA (documented verbatim):

    ТекущаяАтака = (БазоваяАтака + ПлюсуемыеБонусы) * StaminaMod * MoraleMod * WoundMod

then randomised, then reduced by defence, then the negative-damage rule.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum


# ---------------------------------------------------------------------------
# Deterministic RNG with named streams.
#
# Named streams so that adding a roll in one subsystem does not shift every
# other subsystem's sequence. Without this, any rules change invalidates every
# stored replay and differential testing becomes impossible.
#
# NOTE: this is a placeholder LCG. The ORIGINAL generator is unidentified —
# it is one of the three remaining unknowns, alongside MoraleMod values and
# grid geometry. Swapping this class out is the only change needed once the
# real PRNG is identified, which is why the roll surface is kept this narrow.
# ---------------------------------------------------------------------------

class Rng:
    """Integer rolls only. `roll(x)` returns a uniform integer in [0, x-1],
    matching the Eadoropedia's `Random(x)` convention exactly.

    PORTABILITY IS THE POINT. Stream seeding uses FNV-1a over the UTF-8 bytes
    of the stream name, NOT the host language's `hash()`. Python randomises
    string hashing per process (PYTHONHASHSEED), so an earlier version of this
    class produced a different sequence on every run — which silently defeats
    fixtures, replays, and any differential test against the original. The
    algorithm below is fully specified so the GDScript port produces bit-identical
    streams; see tests/test_rng.gd.

        FNV-1a 32-bit:  h = 2166136261;  for each byte: h ^= b; h *= 16777619
        stream seed  :  fnv1a(name) XOR (seed * 2654435761), forced odd-nonzero
        step         :  s = (1103515245 * s + 12345) mod 2^31
    """

    FNV_OFFSET = 2166136261
    FNV_PRIME = 16777619
    MASK32 = 0xFFFFFFFF
    MASK31 = 0x7FFFFFFF

    def __init__(self, seed: int):
        self._seed = seed & self.MASK32
        self._streams: dict[str, int] = {}
        self.calls: dict[str, int] = {}

    @classmethod
    def fnv1a(cls, text: str) -> int:
        h = cls.FNV_OFFSET
        for b in text.encode("utf-8"):
            h = ((h ^ b) * cls.FNV_PRIME) & cls.MASK32
        return h

    def _state(self, stream: str) -> int:
        if stream not in self._streams:
            mixed = (self._seed * 2654435761) & self.MASK32
            s = (self.fnv1a(stream) ^ mixed) & self.MASK31
            self._streams[stream] = s or 1
            self.calls[stream] = 0
        return self._streams[stream]

    def roll(self, x: int, stream: str = "combat") -> int:
        """Uniform integer in [0, x-1]. Returns 0 for x <= 1."""
        if x <= 1:
            return 0
        s = self._state(stream)
        s = (1103515245 * s + 12345) & self.MASK31
        self._streams[stream] = s
        self.calls[stream] += 1
        return s % x


# ---------------------------------------------------------------------------
# Trace
# ---------------------------------------------------------------------------

@dataclass
class Trace:
    label: str
    base: float = 0.0
    steps: list = field(default_factory=list)
    result: float = 0.0

    def step(self, source: str, before: float, after: float, note: str = "") -> None:
        if before != after or note:
            self.steps.append((source, before, after, note))

    def explain(self, indent: str = "") -> str:
        out = [f"{indent}{self.label}: base {_fmt(self.base)}"]
        for source, before, after, note in self.steps:
            tail = f"   # {note}" if note else ""
            out.append(f"{indent}  {source:<26} {_fmt(before)} -> {_fmt(after)}{tail}")
        out.append(f"{indent}  = {_fmt(self.result)}")
        return "\n".join(out)


def _fmt(v: float) -> str:
    return str(int(v)) if float(v).is_integer() else f"{v:.3f}"


# ---------------------------------------------------------------------------
# Combatant state
#
# Deliberately a plain dataclass with no engine types. `flags` is a set of
# ability names rather than an enum: which abilities exist is CONTENT and
# differs between the genesis and new_horizons packs, so it cannot be a
# compile-time enum. See the pack-bindings decision.
# ---------------------------------------------------------------------------

class AttackKind(Enum):
    MELEE = "melee"
    COUNTER = "counter"
    RANGED = "ranged"


@dataclass
class Combatant:
    name: str = "unit"
    # base (unmodified) stats
    attack: int = 0
    counter_attack: int = 0
    ranged_attack: int = 0
    defence: int = 0
    ranged_defence: int = 0
    resist: int = 0
    life_base: int = 1
    life: int = 1
    stamina_base: int = 10
    stamina: int = 10
    morale_base: int = 10
    morale: int = 10
    speed: int = 1
    # additive bonuses that ARE inside the multiplier chain
    # (commander auras, spell buffs — the ones visible in the unit panel)
    attack_bonus: int = 0
    defence_bonus: int = 0
    # additive bonuses applied AFTER the multipliers (see PIPELINE NOTE below)
    conditional_bonus: int = 0
    flags: set = field(default_factory=set)

    def base_attack_for(self, kind: AttackKind) -> int:
        return {
            AttackKind.MELEE: self.attack,
            AttackKind.COUNTER: self.counter_attack,
            AttackKind.RANGED: self.ranged_attack,
        }[kind]

    def base_defence_for(self, kind: AttackKind) -> int:
        return self.ranged_defence if kind is AttackKind.RANGED else self.defence


# ---------------------------------------------------------------------------
# The three multipliers
# ---------------------------------------------------------------------------

def wound_mod(u: Combatant) -> tuple[float, str]:
    """«Тяжёлые ранения»: below 50% life, 0.5 + current/base.

    Exceptions are documented explicitly: «Не чувствует боли» and the
    «Боевое безумие» effect both suppress the penalty entirely.
    """
    if "Не чувствует боли" in u.flags or "Боевое безумие" in u.flags:
        return 1.0, "immune to wound penalty"
    if u.life >= u.life_base * 0.5:
        return 1.0, ""
    return 0.5 + u.life / u.life_base, f"life {u.life}/{u.life_base}"


def stamina_mod(u: Combatant) -> tuple[float, str]:
    """«Выносливость»: at stamina <= 5, 0.4 + 0.1 * stamina.

    «Неутомимый» units never lose stamina at all, so they never reach the
    penalty band; the check is on the flag rather than on the value so that a
    debuff which sets stamina directly still cannot penalise them.
    """
    if "Неутомимый" in u.flags:
        return 1.0, "tireless"
    if u.stamina > 5:
        return 1.0, ""
    return 0.4 + 0.1 * u.stamina, f"stamina {u.stamina}"


# --- MoraleMod ------------------------------------------------------------
#
# OPEN QUESTION. The Eadoropedia states the mechanism but withholds the
# numbers: «* - точные цифры не разглашаются». This table is a PLACEHOLDER
# shaped to match the other two multipliers (linear, centred on 1.0 at base
# morale). It is almost certainly wrong in detail.
#
# Recovering it is a sampling exercise: fix a unit, vary only its morale, and
# read the displayed attack value off the unit panel — the wiki notes the map
# panel shows attack WITHOUT morale and the battle panel WITH it, so the ratio
# between the two screens is the multiplier, no combat required.
#
MORALE_MOD_TABLE: dict[int, float] = {}   # morale delta from base -> multiplier
MORALE_MOD_PER_POINT = 0.05               # placeholder slope


def morale_mod(u: Combatant) -> tuple[float, str]:
    if "Боевое безумие" in u.flags:
        return 1.0, "morale effects suppressed"
    delta = u.morale - u.morale_base
    if delta in MORALE_MOD_TABLE:
        return MORALE_MOD_TABLE[delta], f"morale {u.morale} (table)"
    if delta == 0:
        return 1.0, ""
    return 1.0 + MORALE_MOD_PER_POINT * delta, f"morale {u.morale} (PLACEHOLDER)"


# ---------------------------------------------------------------------------
# Attack value
# ---------------------------------------------------------------------------

def current_attack(u: Combatant, kind: AttackKind) -> tuple[float, Trace]:
    """(base + additive) * StaminaMod * MoraleMod * WoundMod.

    Order is documented and not negotiable: «Сначала к Атаке применяются
    "плюсуемые" бонусы ... а потом уже "умножаемые"».
    """
    t = Trace(f"{u.name}.{kind.value}_attack")
    base = u.base_attack_for(kind)
    t.base = base
    value = float(base)

    if u.attack_bonus:
        nv = value + u.attack_bonus
        t.step("additive bonuses", value, nv)
        value = nv

    for label, fn in (("StaminaMod", stamina_mod),
                      ("MoraleMod", morale_mod),
                      ("WoundMod", wound_mod)):
        m, note = fn(u)
        if m != 1.0 or note:
            nv = value * m
            t.step(f"{label} x{m:.2f}", value, nv, note)
            value = nv

    t.result = value
    return value, t


# ---------------------------------------------------------------------------
# Randomisation
# ---------------------------------------------------------------------------

def roll_attack(attack: int, rng: Rng, stream: str = "attack") -> tuple[int, str]:
    """«Расчёт урона при атаках», exact form.

        attack >= 5:  attack + attack/5 - Random(2*(attack/5) + 1)
        attack <  5:  attack + 1 - Random(3)

    All division is integer and floors. The result clamps to a minimum of 1.

    Equivalent closed form, which the page itself states as a cross-check:
    a uniform integer over [attack - attack//5, attack + attack//5] for
    attack >= 5, and over [attack - 1, attack + 1] below that.
    """
    if attack >= 5:
        k = attack // 5
        rolled = attack + k - rng.roll(2 * k + 1, stream)
        note = f"uniform [{attack - k}, {attack + k}]"
    else:
        rolled = attack + 1 - rng.roll(3, stream)
        note = f"uniform [{attack - 1}, {attack + 1}]"
    if rolled < 1:
        return 1, note + ", clamped to 1"
    return rolled, note


# ---------------------------------------------------------------------------
# Damage
# ---------------------------------------------------------------------------

def negative_damage_hits(damage: int, rng: Rng, stream: str = "chip") -> bool:
    """«"Отрицательный" урон»: when damage <= 0 but > -10, one point still
    lands if Random(20 + damage) >= 10. Probability 1 - 10/(20+damage).
    """
    if damage <= -10:
        return False
    return rng.roll(20 + damage, stream) >= 10


def resolve_attack(attacker: Combatant, defender: Combatant,
                   kind: AttackKind, rng: Rng) -> tuple[int, list]:
    """Full pipeline. Returns (damage_dealt, [traces])."""
    atk_value, atk_trace = current_attack(attacker, kind)

    # PIPELINE NOTE / ASSUMPTION.
    # The page says morale «не увеличивает урон от Сокрушения зла и подобных
    # эффектов, только прямые бонусы на атаки». It does NOT say whether stamina
    # and wound multipliers skip them too. Applying conditional bonuses after
    # all three multipliers is the simplest reading consistent with the text.
    # The alternative — conditional bonuses inside Stamina/Wound but outside
    # Morale — is distinguishable by one wounded-unit test against a target the
    # bonus applies to. Flagged, not settled.
    if attacker.conditional_bonus:
        nv = atk_value + attacker.conditional_bonus
        atk_trace.step("conditional bonus", atk_value, nv, "ASSUMED outside multipliers")
        atk_value = nv
        atk_trace.result = nv

    attack_int = int(math.floor(atk_value))
    if "Не сражается" in attacker.flags:
        return 0, [atk_trace]

    rolled, roll_note = roll_attack(attack_int, rng)
    roll_trace = Trace(f"{attacker.name}.roll")
    roll_trace.base = attack_int
    roll_trace.step("randomise", attack_int, rolled, roll_note)
    roll_trace.result = rolled

    def_value, def_trace = current_defence(defender, kind)
    damage = rolled - def_value

    dmg_trace = Trace("damage")
    dmg_trace.base = rolled
    dmg_trace.step(f"- defence {def_value}", rolled, damage)

    if damage <= 0:
        if negative_damage_hits(damage, rng):
            dmg_trace.step("chip roll", damage, 1, "negative-damage rule succeeded")
            damage = 1
        else:
            dmg_trace.step("chip roll", damage, 0, "negative-damage rule failed")
            damage = 0
    dmg_trace.result = damage
    return damage, [atk_trace, roll_trace, def_trace, dmg_trace]


def current_defence(u: Combatant, kind: AttackKind) -> tuple[int, Trace]:
    """Defence clamps to a minimum of 0. At stamina 0 both defence values are
    halved — «его Защита и Защита от выстрела уменьшаются в 2 раза»."""
    t = Trace(f"{u.name}.defence")
    base = u.base_defence_for(kind)
    t.base = base
    value = float(base)

    if u.defence_bonus:
        nv = value + u.defence_bonus
        t.step("additive bonuses", value, nv)
        value = nv

    if u.stamina <= 0 and "Неутомимый" not in u.flags:
        nv = value * 0.5
        t.step("exhausted x0.50", value, nv, "stamina 0")
        value = nv

    final = max(0, int(math.floor(value)))
    if final != value:
        t.step("floor, clamp >= 0", value, final)
    t.result = final
    return final, t
