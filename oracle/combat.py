# oracle/combat.py
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


# eq=False gives Combatant IDENTITY semantics: two units with identical stats are
# not the same unit, and `==` should say so. It also makes instances hashable,
# which auras need — an aura is keyed by the unit projecting it, and a dataclass
# with the default eq=True sets __hash__ to None.
@dataclass(eq=False)
class Combatant:
    name: str = "unit"
    # base (unmodified) stats
    attack: int = 0
    counter_attack: int = 0
    ranged_attack: int = 0
    shooting_range: int = 0
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

    ## Every Modifier on this unit: innate abilities, level-up perks, item
    ## enchants, spell buffs, terrain, medals, auras. `attack_bonus` and
    ## `defence_bonus` above remain as a shorthand for tests and simple
    ## scenarios; anything content-driven arrives here instead.
    modifiers: list = field(default_factory=list)

    ## Timed effects. They contribute Modifiers through the same pipeline as
    ## everything else, so a status never computes a number itself.
    statuses: list = field(default_factory=list)

    flags: set = field(default_factory=set)
    subtypes: set = field(default_factory=set)

    # --- resources and per-round state -------------------------------------
    ammo: int = 0
    ## Set when an action that consumes the activation has been used this round.
    ## Movement is tracked separately, since a unit may move, yield, and return.
    action_spent: bool = False
    ## Tiles still spendable this round. Reset at ROUND_START from effective
    ## speed, which already includes the stamina penalty.
    movement_remaining: int = 0
    ## Set when the unit hits 0 stamina; consumes the next round entirely.
    forced_rest: bool = False
    ## Rested this round, so it forgoes counterattacks.
    resting: bool = False
    ## Восстановление сил, added to the base +2 on rest.
    stamina_recovery: int = 0
    alive: bool = True
    ## Sources that have fired their «только один раз за ход» effect this round.
    ## Cleared by begin_round and by NOTHING else — an extra turn must not
    ## refill it, or Кровавое безумие would chain without bound.
    once_per_round: set = field(default_factory=set)
    ## Cumulative path length this round — NOT displacement. Feeds Атака с
    ## разгона; its `> 0` test is the stamina -2/-1 discriminator.
    steps_this_round: int = 0

    def has_flag(self, f: str) -> bool:
        """A flag is DERIVED, not stored.

        `self.flags` holds flags set directly — by a scenario, a test, or a
        rule. But a flag can also come from an ability, and abilities live in
        the modifier list; and a modifier can come from a status effect, which
        expires.

        Checking all three sources here means a spell granting Неутомимый for
        three rounds works with no extra machinery: the modifier appears when
        the status is applied and vanishes when it expires, and every existing
        `has_flag` call site — wounds, stamina, counterattack — follows along
        without knowing statuses exist.

        The alternative was to have the roster run grant_flag at build time and
        mutate `flags`. That works for innate abilities and silently fails for
        every temporary one.
        """
        if f in self.flags:
            return True
        for m in self.modifiers:
            if m.handler == "grant_flag" and m.params.get("flag") == f:
                return True
        for effect in self.statuses:
            for m in effect.modifiers:
                if m.handler == "grant_flag" and m.params.get("flag") == f:
                    return True
        return False

    def all_flags(self) -> set:
        """Every flag from every source. For display and for the AI."""
        out = set(self.flags)
        for m in self.modifiers:
            if m.handler == "grant_flag" and m.params.get("flag"):
                out.add(m.params["flag"])
        for effect in self.statuses:
            for m in effect.modifiers:
                if m.handler == "grant_flag" and m.params.get("flag"):
                    out.add(m.params["flag"])
        return out

    def has_subtype(self, s: str) -> bool:
        return s in self.subtypes

    def moved_this_round(self) -> bool:
        return self.steps_this_round > 0

    def reset_round(self) -> None:
        self.action_spent = False
        self.steps_this_round = 0

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
    if u.has_flag("Не чувствует боли") or u.has_flag("Боевое безумие"):
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
    if u.has_flag("Неутомимый"):
        return 1.0, "tireless"
    if u.stamina > 5:
        return 1.0, ""
    return 0.4 + 0.1 * u.stamina, f"stamina {u.stamina}"


# --- MoraleMod ------------------------------------------------------------
#
# Keyed on ABSOLUTE morale. morale_base does NOT enter the attack multiplier —
# the earlier delta-from-base form was a placeholder shape, not the rule.
#
#   morale 0..5   ->  0.4 + 0.1 * morale     (0 -> 0.4, and the unit panics)
#   morale 6..15  ->  1.0
#   morale >= 16  ->  1.0 + 0.05 * n, band n starting at 15 + n(n+1)/2
#                     16-17 = 1.05  18-20 = 1.10  21-24 = 1.15  25-29 = 1.20
#                     30-35 = 1.25  36-42 = 1.30  43-50 = 1.35  … («и так далее»)
#
# 0..15 is VERIFIED: the Genesis binary's «−10% per missing point below 6» and
# the published table's 0.4 + 0.1*morale are the same function at every point,
# across two independent sources and two builds. See docs/FORMULAS.md §1.4.
#
# >=16 is STRONG INFERENCE for Genesis: both sources agree the step is 5%, but
# the band widths come only from NH 26.0620.f01 documentation and the Genesis
# high-morale branch has not been read. OPEN_QUESTIONS item 1.
#
# Applies to the three ATTACK values only, never to defence.
#
# The band index is computed iteratively rather than by solving the quadratic
# with a float sqrt, so this and the GDScript port agree bit for bit.


def _trunc(x: float) -> int:
    """C integer division truncates toward zero, not toward negative infinity.
    Python's // floors, which diverges for the negative bonuses below morale 6.
    """
    return int(x)


def morale_band(morale: int) -> int:
    """Band index n for morale >= 16; multiplier is 1.0 + 0.05 * n."""
    n = 1
    while 15 + (n + 1) * (n + 2) // 2 <= morale:
        n += 1
    return n


def morale_percent(u: Combatant) -> tuple[int, str]:
    """Morale as the INTEGER percentage the binary actually applies.

    The executable does not multiply by a float. After the wound and stamina
    steps it converts the internal x100 value back to an integer and then adds
    a whole-percent bonus:

        pre_morale = scaled_attack / 100
        result     = pre_morale + bonus_percent * pre_morale / 100

    Both divisions are C integer divisions, truncating toward zero.
    See docs/FORMULAS.md 1.4 (source EXP-R1-001).
    """
    if u.has_flag("Боевое безумие"):
        return 0, "morale effects suppressed"
    m = u.morale
    if m <= 5:
        # -10 percentage points per point of morale missing below 6.
        return -10 * (6 - max(m, 0)), f"morale {m}"
    if m <= 15:
        return 0, ""
    return 5 * morale_band(m), f"morale {m}"


def morale_mod(u: Combatant) -> tuple[float, str]:
    """The documented multiplier view of the same curve.

    Kept for the published-table fixtures and for tracing. The attack pipeline
    uses morale_percent() instead, because a float multiplier cannot reproduce
    the binary: 1.15 is not exactly representable, so 100 * 1.15 truncates to
    114 where the executable returns 115.
    """
    pct, note = morale_percent(u)
    return 1.0 + pct / 100.0, note


# ---------------------------------------------------------------------------
# Attack value
# ---------------------------------------------------------------------------

# Set by rules.bind_pipeline(). None means "no content loaded" — the scalar
# attack_bonus/defence_bonus path still works, which is what keeps every
# pre-existing test and scenario valid.
_PIPELINE = None
_CONTEXT_EXTRA = {}


def bind_pipeline(pipeline) -> None:
    """Install the modifier pipeline. Called once, after content loads."""
    global _PIPELINE
    _PIPELINE = pipeline


## Supplies modifiers that come from the unit's SURROUNDINGS rather than from the
## unit — auras today, terrain later. Injected rather than imported, because those
## need the battlefield and the side layout, and combat must not depend on either.
_ENVIRONMENT = None


def bind_environment(provider) -> None:
    """`provider(unit) -> list[Modifier]`. Pass None to detach."""
    global _ENVIRONMENT
    _ENVIRONMENT = provider


def effective_modifiers(u) -> list:
    """EVERY modifier acting on this unit, from every source.

    There are three, and forgetting one is invisible until something is cast:

        u.modifiers              innate abilities, from unit.var via the roster
        u.statuses[].modifiers   timed effects — buffs, curses, enchantments
        _ENVIRONMENT(u)          auras, and terrain when it lands

    This function exists because the damage path used only the first. Statuses
    passed every test in isolation while a Благословение granting +2 attack did
    nothing, because nothing merged the sources. `has_flag` walked all three
    already, so FLAGS from statuses worked and NUMBERS did not — the most
    confusing possible failure shape.

    Statuses are read by duck-typing rather than importing the module, since
    statuses.py imports Trace from here.
    """
    out = list(u.modifiers)
    for effect in u.statuses:
        out.extend(effect.modifiers)
    if _ENVIRONMENT is not None:
        out.extend(_ENVIRONMENT(u))
    return out


def _run_hook(base, u, hook, ctx, label):
    if _PIPELINE is None:
        return base, None
    mods = effective_modifiers(u)
    if not mods:
        return base, None
    return _PIPELINE.resolve(base, mods, hook, ctx, label)


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

    # STAT_PASSIVE sits INSIDE the multiplier chain: additive before
    # multiplicative is documented and not negotiable.
    from modifier import Hook
    ctx = {"stat": _STAT_FOR_KIND[kind], "unit": u, "kind": kind}
    nv, sub = _run_hook(value, u, Hook.STAT_PASSIVE, ctx, "modifiers")
    if sub is not None and nv != value:
        for step in sub.steps:
            t.steps.append(step)
        value = nv

    # Stamina and wound act inside the x100 scaled domain; morale is applied
    # LAST, on an integer, as a whole-percent bonus. The order is the binary's,
    # not a rearrangement of the documented product: with truncation between
    # the steps the order is observable. docs/FORMULAS.md 1.4.
    for label, fn in (("StaminaMod", stamina_mod),
                      ("WoundMod", wound_mod)):
        m, note = fn(u)
        if m != 1.0 or note:
            nv = value * m
            t.step(f"{label} x{m:.2f}", value, nv, note)
            value = nv

    pct, note = morale_percent(u)
    if pct or note:
        pre = _trunc(value)
        nv = float(pre + _trunc(pct * pre / 100))
        t.step(f"MoraleMod {pct:+d}%", value, nv, note)
        value = nv

    t.result = value
    return value, t


_STAT_FOR_KIND = {
    AttackKind.MELEE: "attack",
    AttackKind.COUNTER: "counter_attack",
    AttackKind.RANGED: "ranged_attack",
}


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
    if attacker.has_flag("Не сражается"):
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

    from modifier import Hook
    ctx = {"stat": "ranged_defence" if kind is AttackKind.RANGED else "defence",
           "unit": u, "kind": kind}
    nv, sub = _run_hook(value, u, Hook.STAT_PASSIVE, ctx, "modifiers")
    if sub is not None and nv != value:
        for step in sub.steps:
            t.steps.append(step)
        value = nv

    if u.stamina <= 0 and not u.has_flag("Неутомимый"):
        nv = value * 0.5
        t.step("exhausted x0.50", value, nv, "stamina 0")
        value = nv

    final = max(0, int(math.floor(value)))
    if final != value:
        t.step("floor, clamp >= 0", value, final)
    t.result = final
    return final, t
